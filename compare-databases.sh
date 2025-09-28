#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Database connection details
PRIMARY_HOST="localhost"
PRIMARY_PORT="6000"
STANDBY_HOST="localhost"
STANDBY_PORT="6001"
DB_USER="admin"
DB_NAME="mydb"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PostgreSQL Replication Comparison Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to execute query on primary
exec_primary() {
    docker exec postgres-primary psql -U $DB_USER -d $DB_NAME -t -c "$1" 2>/dev/null
}

# Function to execute query on standby
exec_standby() {
    docker exec postgres-standby psql -U $DB_USER -d $DB_NAME -t -c "$1" 2>/dev/null
}

# 1. Check replication status
echo -e "${YELLOW}1. Checking Replication Status:${NC}"
echo "   Primary replication info:"
docker exec postgres-primary psql -U $DB_USER -d $DB_NAME -c \
    "SELECT client_addr, state, sync_state, replay_lsn FROM pg_stat_replication;" 2>/dev/null

echo ""
echo "   Standby status:"
docker exec postgres-standby psql -U $DB_USER -d $DB_NAME -c \
    "SELECT pg_is_in_recovery() as is_standby, pg_last_wal_receive_lsn() as receive_lsn, pg_last_wal_replay_lsn() as replay_lsn;" 2>/dev/null

echo ""

# 2. Compare table counts
echo -e "${YELLOW}2. Comparing Table Counts:${NC}"
PRIMARY_TABLES=$(exec_primary "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
STANDBY_TABLES=$(exec_standby "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")

echo "   Primary tables: $PRIMARY_TABLES"
echo "   Standby tables: $STANDBY_TABLES"

if [ "$PRIMARY_TABLES" = "$STANDBY_TABLES" ]; then
    echo -e "   ${GREEN}✓ Table counts match${NC}"
else
    echo -e "   ${RED}✗ Table counts do not match!${NC}"
fi

echo ""

# 3. List all tables
echo -e "${YELLOW}3. Tables in both databases:${NC}"
echo "   Primary tables:"
docker exec postgres-primary psql -U $DB_USER -d $DB_NAME -c \
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;" 2>/dev/null

echo ""

# 4. Compare row counts for each table
echo -e "${YELLOW}4. Comparing Row Counts per Table:${NC}"

# Get list of tables
TABLES=$(exec_primary "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;")

for table in $TABLES; do
    PRIMARY_COUNT=$(exec_primary "SELECT COUNT(*) FROM $table;")
    STANDBY_COUNT=$(exec_standby "SELECT COUNT(*) FROM $table;")

    if [ "$PRIMARY_COUNT" = "$STANDBY_COUNT" ]; then
        echo -e "   $table: ${GREEN}✓${NC} Primary: $PRIMARY_COUNT, Standby: $STANDBY_COUNT"
    else
        echo -e "   $table: ${RED}✗${NC} Primary: $PRIMARY_COUNT, Standby: $STANDBY_COUNT"
    fi
done

echo ""

# 5. Check replication lag
echo -e "${YELLOW}5. Checking Replication Lag:${NC}"
LAG=$(docker exec postgres-primary psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT as lag_seconds FROM pg_stat_replication;" 2>/dev/null)

if [ -z "$LAG" ]; then
    echo "   Could not determine lag (might be 0 if fully synced)"
else
    echo "   Replication lag: ${LAG} seconds"
    if [ "$LAG" -lt "1" ] 2>/dev/null; then
        echo -e "   ${GREEN}✓ Replication is up to date${NC}"
    else
        echo -e "   ${YELLOW}⚠ Replication lag detected${NC}"
    fi
fi

echo ""

# # 6. Compare specific table data (if users table exists)
# echo -e "${YELLOW}6. Sample Data Comparison (users table):${NC}"
# USERS_EXIST=$(exec_primary "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users');")

# if [ "$USERS_EXIST" = "t" ]; then
#     echo "   Last 3 users in Primary:"
#     docker exec postgres-primary psql -U $DB_USER -d $DB_NAME -c \
#         "SELECT id, username, email FROM users ORDER BY id DESC LIMIT 3;" 2>/dev/null

#     echo ""
#     echo "   Last 3 users in Standby:"
#     docker exec postgres-standby psql -U $DB_USER -d $DB_NAME -c \
#         "SELECT id, username, email FROM users ORDER BY id DESC LIMIT 3;" 2>/dev/null

#     # Compare checksums
#     PRIMARY_CHECKSUM=$(exec_primary "SELECT MD5(string_agg(id::text || username || email, '')) FROM users;")
#     STANDBY_CHECKSUM=$(exec_standby "SELECT MD5(string_agg(id::text || username || email, '')) FROM users;")

#     echo ""
#     echo "   Data checksum comparison:"
#     echo "   Primary checksum: $PRIMARY_CHECKSUM"
#     echo "   Standby checksum: $STANDBY_CHECKSUM"

#     if [ "$PRIMARY_CHECKSUM" = "$STANDBY_CHECKSUM" ]; then
#         echo -e "   ${GREEN}✓ Data is identical${NC}"
#     else
#         echo -e "   ${RED}✗ Data mismatch detected!${NC}"
#     fi
# else
#     echo "   Users table not found. Run init-users-table.sql first."
# fi

# echo ""

# 7. Test real-time replication
# echo -e "${YELLOW}7. Testing Real-time Replication:${NC}"
# echo "   Creating test record on primary..."

# TEST_ID=$(date +%s)
# exec_primary "CREATE TABLE IF NOT EXISTS replication_test (id INT PRIMARY KEY, created_at TIMESTAMP DEFAULT NOW());"
# exec_primary "INSERT INTO replication_test (id) VALUES ($TEST_ID);"

# echo "   Waiting 2 seconds for replication..."
# sleep 2

# TEST_EXISTS=$(exec_standby "SELECT EXISTS (SELECT 1 FROM replication_test WHERE id = $TEST_ID);")

# if [ "$TEST_EXISTS" = "t" ]; then
#     echo -e "   ${GREEN}✓ Real-time replication is working!${NC}"
#     # Cleanup
#     exec_primary "DROP TABLE IF EXISTS replication_test;"
# else
#     echo -e "   ${RED}✗ Replication test failed!${NC}"
# fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Comparison Complete!${NC}"
echo -e "${BLUE}========================================${NC}"