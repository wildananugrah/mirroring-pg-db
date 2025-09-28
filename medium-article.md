# PostgreSQL Replication Made Simple: A Beginner's Guide to Database Mirroring with Docker

## Introduction

Ever wondered what happens if your database server crashes? Or how big companies handle millions of users without their database becoming a bottleneck? The answer is **database replication** — and today, I'll show you how to set it up from scratch!

Think of database replication like having a backup singer who knows all the songs and is ready to take over if the lead singer loses their voice. Your "backup database" (we call it a standby or replica) stays synchronized with your main database, ready to jump in when needed.

## Why Should You Care About Database Replication?

Before we dive into the code, let's understand why replication matters:

1. **High Availability**: If your primary database fails, the standby can take over immediately
2. **Load Distribution**: You can send read queries to replicas, reducing load on the primary
3. **Disaster Recovery**: Having a real-time backup means minimal data loss
4. **Zero-Downtime Maintenance**: Perform updates on standby first, then switch roles

## What We're Building

We'll create a PostgreSQL replication setup with:
- One **Primary** database (handles all writes)
- One **Standby** database (read-only replica)
- Automatic real-time synchronization
- Docker containers for easy deployment

Here's what our architecture looks like:

```
┌──────────────┐         Replication         ┌──────────────┐
│              │ ──────────────────────────> │              │
│   Primary    │       (Streaming WAL)       │   Standby    │
│  PostgreSQL  │                             │  PostgreSQL  │
│   Port:6000  │                             │   Port:6001  │
└──────────────┘                             └──────────────┘
      ↑                                             ↑
      │ Write                                       │ Read
      │                                             │
┌─────────────────────────────────────────────────────────┐
│                     Application                          │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

You'll need:
- Docker and Docker Compose installed
- Basic understanding of PostgreSQL
- A terminal/command line
- 10 minutes of your time

## Step 1: Project Setup

First, let's create our project structure:

```bash
mkdir postgres-replication
cd postgres-replication

# Create directories for configuration
mkdir primary standby

# Create directories for data (will be created by Docker)
mkdir primary_data standby_data
```

## Step 2: Configure the Primary Database

### PostgreSQL Configuration (primary/postgresql.conf)

Create `primary/postgresql.conf`:

```conf
# Replication Settings
wal_level = replica                    # Enable replication
max_wal_senders = 3                    # Max number of replication connections
wal_keep_size = 256MB                  # Keep WAL files for standby
max_replication_slots = 3              # Max replication slots
hot_standby = on                       # Allow queries on standby
archive_mode = on                      # Enable archiving
archive_command = 'test ! -f /archive/%f && cp %p /archive/%f'

# Connection settings
listen_addresses = '*'                 # Listen on all interfaces
port = 5432
max_connections = 100
hba_file = '/etc/postgresql/pg_hba.conf'

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
work_mem = 4MB

# Logging
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
```

### Authentication Configuration (primary/pg_hba.conf)

Create `primary/pg_hba.conf`:

```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             all                                     trust
local   replication     all                                     trust

# IPv4 local connections
host    all             all             127.0.0.1/32            trust

# IPv6 local connections
host    all             all             ::1/128                 trust

# Allow replication connections from anywhere (for Docker)
host    replication     replicator      0.0.0.0/0               trust
host    replication     all             0.0.0.0/0               trust

# Allow all connections from Docker network
host    all             all             0.0.0.0/0               trust
```

### Primary Initialization Script (init-primary.sh)

Create `init-primary.sh`:

```bash
#!/bin/bash
set -e

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'replicator123';
    SELECT pg_create_physical_replication_slot('replication_slot');
EOSQL

echo "Primary server initialization completed"
```

## Step 3: Configure the Standby Database

### Standby PostgreSQL Configuration (standby/postgresql.conf)

Create `standby/postgresql.conf`:

```conf
# Replication Settings
wal_level = replica
max_wal_senders = 3
wal_keep_size = 256MB
max_replication_slots = 3
hot_standby = on
archive_mode = off                     # Standby doesn't archive

# Connection settings
listen_addresses = '*'
port = 5432
max_connections = 100
hba_file = '/etc/postgresql/pg_hba.conf'

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
work_mem = 4MB

# Logging
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
```

### Copy pg_hba.conf to standby

```bash
cp primary/pg_hba.conf standby/pg_hba.conf
```

## Step 4: Docker Compose Configuration

Create `docker-compose.yml`:

```yaml
services:
  postgres-primary:
    image: postgres:15-alpine
    container_name: postgres-primary
    environment:
      POSTGRES_DB: mydb
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin123
      POSTGRES_REPLICATION_MODE: master
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: replicator123
    ports:
      - "6000:5432"
    volumes:
      - ./primary_data:/var/lib/postgresql/data
      - ./primary/postgresql.conf:/etc/postgresql/postgresql.conf
      - ./primary/pg_hba.conf:/etc/postgresql/pg_hba.conf
      - ./init-primary.sh:/docker-entrypoint-initdb.d/init-primary.sh
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
    networks:
      - postgres-network

  postgres-standby:
    image: postgres:15-alpine
    container_name: postgres-standby
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin123
    ports:
      - "6001:5432"
    volumes:
      - ./standby_data:/var/lib/postgresql/data
      - ./standby/postgresql.conf:/etc/postgresql/postgresql.conf
      - ./standby/pg_hba.conf:/etc/postgresql/pg_hba.conf
    depends_on:
      - postgres-primary
    command: |
      bash -c "
      until pg_isready -h postgres-primary -p 5432 -U admin; do
        echo 'Waiting for primary to be ready...'
        sleep 2
      done

      if [ ! -f /var/lib/postgresql/data/PG_VERSION ]; then
        echo 'Starting base backup from primary...'
        rm -rf /var/lib/postgresql/data/*
        PGPASSWORD=replicator123 pg_basebackup -h postgres-primary -p 5432 -U replicator -D /var/lib/postgresql/data -Fp -Xs -R -P -v

        cat >> /var/lib/postgresql/data/postgresql.auto.conf <<EOF
      primary_conninfo = 'host=postgres-primary port=5432 user=replicator password=replicator123'
      primary_slot_name = 'replication_slot'
      EOF

        touch /var/lib/postgresql/data/standby.signal
        chmod 700 /var/lib/postgresql/data
        chown -R postgres:postgres /var/lib/postgresql/data
      fi

      chown postgres:postgres /var/lib/postgresql/data
      chmod 700 /var/lib/postgresql/data
      exec su-exec postgres postgres -c config_file=/etc/postgresql/postgresql.conf
      "
    networks:
      - postgres-network

networks:
  postgres-network:
    driver: bridge

volumes:
  primary_data:
  standby_data:
```

## Step 5: Start Your Replicated Database

Now, let's bring everything to life:

```bash
# Create the network
docker network create postgres-network

# Start the containers
docker-compose up -d

# Check if containers are running
docker ps

# View logs
docker-compose logs -f
```

## Step 6: Verify Replication is Working

Let's test if our replication is actually working:

```bash
# Check replication status on primary
docker exec postgres-primary psql -U admin -d mydb -c \
  "SELECT client_addr, state FROM pg_stat_replication;"

# You should see:
# client_addr |   state
# -------------+-----------
# 172.26.0.3  | streaming
```

## Step 7: Test Data Replication

Let's create some data and see it replicate:

```bash
# Create a table on primary
docker exec postgres-primary psql -U admin -d mydb -c \
  "CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100)
  );"

# Insert data on primary
docker exec postgres-primary psql -U admin -d mydb -c \
  "INSERT INTO users (name) VALUES ('Alice'), ('Bob'), ('Charlie');"

# Check data on standby (should see the same data!)
docker exec postgres-standby psql -U admin -d mydb -c \
  "SELECT * FROM users;"

# Output:
#  id |  name
# ----+---------
#   1 | Alice
#   2 | Bob
#   3 | Charlie
```

Congratulations! 🎉 Your data is being replicated in real-time!

## Step 8: Create a Monitoring Script

Save this as `check-replication.sh`:

```bash
#!/bin/bash

echo "==================================="
echo "PostgreSQL Replication Status"
echo "==================================="

echo -e "\n1. Replication Status:"
docker exec postgres-primary psql -U admin -d mydb -c \
  "SELECT client_addr, state, sync_state FROM pg_stat_replication;"

echo -e "\n2. Is Standby in Recovery Mode?"
docker exec postgres-standby psql -U admin -d mydb -c \
  "SELECT pg_is_in_recovery();"

echo -e "\n3. Replication Lag:"
docker exec postgres-primary psql -U admin -d mydb -t -c \
  "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT as lag_seconds;"

echo -e "\nReplication check complete!"
```

Make it executable and run:

```bash
chmod +x check-replication.sh
./check-replication.sh
```

## Common Issues and Solutions

### Issue 1: "no pg_hba.conf entry for replication"

**Solution**: Make sure your pg_hba.conf includes:
```conf
host    replication     replicator      0.0.0.0/0    trust
```

### Issue 2: Standby container keeps restarting

**Solution**: Check permissions on data directory:
```bash
# Fix permissions
docker-compose down
sudo rm -rf standby_data/*
docker-compose up -d
```

### Issue 3: High replication lag

**Solution**: Check network connectivity and increase `wal_keep_size` in postgresql.conf

## What's Next?

Now that you have basic replication working, you can explore:

1. **Synchronous Replication**: Ensure data is written to standby before confirming to client
2. **Multiple Standbys**: Add more replicas for better load distribution
3. **Automatic Failover**: Use tools like Patroni or repmgr
4. **Read/Write Splitting**: Direct read queries to standbys automatically
5. **Monitoring**: Set up proper monitoring with tools like pgMonitor

## Best Practices for Production

1. **Use Strong Passwords**: Replace 'replicator123' with secure passwords
2. **Network Security**: Don't use `0.0.0.0/0` in production; specify exact IP ranges
3. **Monitoring**: Set up alerts for replication lag and failures
4. **Backup Strategy**: Replication is not a backup! Still maintain regular backups
5. **Test Failover**: Regularly practice switching from primary to standby

## Conclusion

Congratulations! You've just set up PostgreSQL replication from scratch. You now have:

- A primary database handling all writes
- A standby database with real-time data synchronization
- Understanding of how replication works
- Tools to monitor replication health

Database replication might seem complex at first, but as you've seen, with Docker and proper configuration, it's quite manageable. This setup gives you high availability, better performance, and peace of mind knowing your data is safe.

Remember: replication is just one part of a robust database strategy. Combine it with regular backups, monitoring, and a solid disaster recovery plan for a production-ready setup.

## Resources

- [PostgreSQL Replication Documentation](https://www.postgresql.org/docs/current/high-availability.html)
- [Docker PostgreSQL Image](https://hub.docker.com/_/postgres)
- [pg_basebackup Documentation](https://www.postgresql.org/docs/current/app-pgbasebackup.html)
- [Source Code for this Tutorial](https://github.com/yourusername/postgres-replication)

---

*Found this helpful? Follow me for more database and DevOps tutorials! Have questions? Drop them in the comments below.*

*Happy replicating! 🐘*