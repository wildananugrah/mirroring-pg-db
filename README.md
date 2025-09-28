# PostgreSQL Streaming Replication with Docker

This guide walks you through setting up PostgreSQL master-slave replication using streaming replication in Docker containers.

## Overview

PostgreSQL streaming replication creates a real-time copy of your database by continuously shipping WAL (Write-Ahead Log) records from a primary server to one or more standby servers.

## Architecture

```
┌─────────────┐         ┌─────────────┐
│   Primary   │ ──────> │   Standby   │
│  (Master)   │  WAL    │   (Slave)   │
│   Port:5432 │ Stream  │  Port:5433  │
└─────────────┘         └─────────────┘
```

## Prerequisites

- Docker and Docker Compose installed
- Basic understanding of PostgreSQL
- Sufficient disk space for both databases

## Step 1: Project Structure

Create the following directory structure:

```
postgres-replication/
├── docker-compose.yml
├── primary/
│   ├── Dockerfile
│   ├── postgresql.conf
│   └── pg_hba.conf
└── standby/
    ├── Dockerfile
    └── recovery.conf
```

## Step 2: Docker Compose Configuration

Create `docker-compose.yml`:

```yaml
version: '3.8'

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
      - "5432:5432"
    volumes:
      - primary_data:/var/lib/postgresql/data
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
      POSTGRES_MASTER_HOST: postgres-primary
      POSTGRES_MASTER_PORT: 5432
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: replicator123
    ports:
      - "5433:5432"
    volumes:
      - standby_data:/var/lib/postgresql/data
      - ./standby/postgresql.conf:/etc/postgresql/postgresql.conf
      - ./init-standby.sh:/docker-entrypoint-initdb.d/init-standby.sh
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
        PGPASSWORD=replicator123 pg_basebackup -h postgres-primary -p 5432 -U replicator -D /var/lib/postgresql/data -Fp -Xs -R -P -v

        cat >> /var/lib/postgresql/data/postgresql.auto.conf <<EOF
      primary_conninfo = 'host=postgres-primary port=5432 user=replicator password=replicator123'
      primary_slot_name = 'replication_slot'
      EOF

        touch /var/lib/postgresql/data/standby.signal
      fi

      postgres -c config_file=/etc/postgresql/postgresql.conf
      "
    networks:
      - postgres-network

volumes:
  primary_data:
  standby_data:

networks:
  postgres-network:
    driver: bridge
```

## Step 3: Primary Server Configuration

Create `primary/postgresql.conf`:

```conf
# Replication Settings
wal_level = replica
max_wal_senders = 3
wal_keep_size = 256MB
max_replication_slots = 3
hot_standby = on
archive_mode = on
archive_command = 'test ! -f /archive/%f && cp %p /archive/%f'

# Connection settings
listen_addresses = '*'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
work_mem = 4MB

# Checkpoint settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1

# Logging
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_duration = off
log_lock_waits = on
log_statement = 'all'
```

Create `primary/pg_hba.conf`:

```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             all                                     trust

# IPv4 local connections
host    all             all             127.0.0.1/32            trust

# IPv6 local connections
host    all             all             ::1/128                 trust

# Allow replication connections from standby
host    replication     replicator      0.0.0.0/0               md5

# Allow all connections from Docker network
host    all             all             0.0.0.0/0               md5
```

## Step 4: Initialization Scripts

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

Create `init-standby.sh`:

```bash
#!/bin/bash
set -e

echo "Standby server initialization completed"
```

Make scripts executable:

```bash
chmod +x init-primary.sh init-standby.sh
```

## Step 5: Alternative - Using Bitnami PostgreSQL Images

For a simpler setup, you can use Bitnami PostgreSQL images which have built-in replication support:

```yaml
version: '3.8'

services:
  postgresql-primary:
    image: bitnami/postgresql:15
    container_name: postgresql-primary
    environment:
      - POSTGRESQL_POSTGRES_PASSWORD=adminpassword
      - POSTGRESQL_USERNAME=myuser
      - POSTGRESQL_PASSWORD=mypassword
      - POSTGRESQL_DATABASE=mydb
      - POSTGRESQL_REPLICATION_MODE=master
      - POSTGRESQL_REPLICATION_USER=repl_user
      - POSTGRESQL_REPLICATION_PASSWORD=repl_password
    ports:
      - '5432:5432'
    volumes:
      - 'postgresql_master_data:/bitnami/postgresql'
    networks:
      - postgres-network

  postgresql-standby:
    image: bitnami/postgresql:15
    container_name: postgresql-standby
    environment:
      - POSTGRESQL_POSTGRES_PASSWORD=adminpassword
      - POSTGRESQL_PASSWORD=mypassword
      - POSTGRESQL_REPLICATION_MODE=slave
      - POSTGRESQL_REPLICATION_USER=repl_user
      - POSTGRESQL_REPLICATION_PASSWORD=repl_password
      - POSTGRESQL_MASTER_HOST=postgresql-primary
      - POSTGRESQL_MASTER_PORT_NUMBER=5432
    ports:
      - '5433:5432'
    depends_on:
      - postgresql-primary
    volumes:
      - 'postgresql_slave_data:/bitnami/postgresql'
    networks:
      - postgres-network

volumes:
  postgresql_master_data:
  postgresql_slave_data:

networks:
  postgres-network:
    driver: bridge
```

## Step 6: Running the Setup

1. Start the containers:
```bash
docker-compose up -d
```

2. Check container status:
```bash
docker-compose ps
```

3. View logs:
```bash
docker-compose logs -f
```

## Step 7: Verifying Replication

1. Check replication status on primary:
```bash
docker exec -it postgres-primary psql -U admin -d mydb -c "SELECT * FROM pg_stat_replication;"
```

2. Check standby status:
```bash
docker exec -it postgres-standby psql -U admin -d mydb -c "SELECT * FROM pg_stat_wal_receiver;"
```

3. Test replication by creating data on primary:
```bash
# Create table on primary
docker exec -it postgres-primary psql -U admin -d mydb -c "CREATE TABLE test (id SERIAL PRIMARY KEY, name VARCHAR(50));"

# Insert data on primary
docker exec -it postgres-primary psql -U admin -d mydb -c "INSERT INTO test (name) VALUES ('Test Record 1'), ('Test Record 2');"

# Verify on standby (read-only)
docker exec -it postgres-standby psql -U admin -d mydb -c "SELECT * FROM test;"
```

## Step 8: Monitoring

### Key Metrics to Monitor

1. **Replication Lag**:
```sql
-- On primary
SELECT client_addr, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS sent_lag,
       pg_wal_lsn_diff(sent_lsn, flush_lsn) AS flush_lag,
       pg_wal_lsn_diff(flush_lsn, replay_lsn) AS replay_lag
FROM pg_stat_replication;
```

2. **Connection Status**:
```sql
-- On standby
SELECT status, received_lsn, latest_end_lsn,
       latest_end_time, slot_name
FROM pg_stat_wal_receiver;
```

## Step 9: Failover Procedures

### Manual Failover

1. Stop the primary:
```bash
docker-compose stop postgres-primary
```

2. Promote standby to primary:
```bash
docker exec -it postgres-standby psql -U admin -c "SELECT pg_promote();"
```

3. Update application connection strings to point to new primary (port 5433)

### Automatic Failover Options

For automatic failover, consider using:
- **Patroni**: A template for PostgreSQL HA with ZooKeeper, etcd, or Consul
- **repmgr**: Open-source tool for managing replication and failover
- **pg_auto_failover**: PostgreSQL extension for automated failover

## Step 10: Best Practices

1. **Backup Strategy**
   - Regular backups using pg_dump or pg_basebackup
   - Test restore procedures regularly

2. **Security**
   - Use strong passwords
   - Implement SSL/TLS for replication connections
   - Restrict network access

3. **Performance Tuning**
   - Monitor replication lag
   - Adjust wal_keep_size based on network speed
   - Use synchronous replication for critical data

4. **Maintenance**
   - Regular VACUUM and ANALYZE
   - Monitor disk space
   - Keep PostgreSQL versions synchronized

## Troubleshooting

### Common Issues

1. **Replication Slot Not Found**
```bash
# On primary, recreate slot
docker exec -it postgres-primary psql -U admin -c "SELECT pg_create_physical_replication_slot('replication_slot');"
```

2. **Authentication Failed**
- Check pg_hba.conf settings
- Verify replication user credentials
- Check network connectivity

3. **Standby Lag Increasing**
- Check network bandwidth
- Increase wal_keep_size
- Verify no long-running transactions on primary

4. **Standby Won't Start**
```bash
# Check logs
docker-compose logs postgres-standby

# Reinitialize standby
docker-compose down postgres-standby
docker volume rm postgres-replication_standby_data
docker-compose up -d postgres-standby
```

## Additional Resources

- [PostgreSQL Replication Documentation](https://www.postgresql.org/docs/current/high-availability.html)
- [Docker PostgreSQL Image Documentation](https://hub.docker.com/_/postgres)
- [Bitnami PostgreSQL Documentation](https://github.com/bitnami/containers/tree/main/bitnami/postgresql)

## Conclusion

This setup provides a robust PostgreSQL streaming replication environment using Docker. Remember to:
- Test thoroughly before production use
- Implement monitoring and alerting
- Have a documented failover procedure
- Regular backup and recovery testing

For production environments, consider adding:
- Load balancing (pgpool-II, HAProxy)
- Connection pooling (PgBouncer)
- Monitoring stack (Prometheus, Grafana)
- Automated failover management