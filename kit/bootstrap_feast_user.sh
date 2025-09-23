#!/usr/bin/env bash
set -euo pipefail
# Bootstrap a per-student Feast repo + schema
# Run as: sudo -u <student> /usr/local/bin/bootstrap_feast_user.sh

TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
REPO_DIR="${HOME_DIR}/class/feast"

# Config provided by cloud-init into /etc/class/
source /etc/class/db.env
source /etc/class/stack.env

install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$REPO_DIR"

# Per-user Postgres schema
export PGPASSWORD="$DB_PASS"
psql "host=${DB_HOST} port=5432 dbname=${DB_NAME} user=${DB_USER} sslmode=require" \
  -v schema="${TARGET_USER}" \
  -c 'CREATE SCHEMA IF NOT EXISTS :"schema";' >/dev/null

# feature_store.yaml
cat > "${REPO_DIR}/feature_store.yaml" <<YAML
project: ${TARGET_USER}
registry: s3://${FEAST_REGISTRY_BUCKET}/registry/${TARGET_USER}/registry.db
provider: local
online_store:
  type: dynamodb
  region: ${AWS_REGION}
  table_name: ${FEAST_ONLINE_TABLE}
offline_store:
  type: postgres
  host: ${DB_HOST}
  port: 5432
  database: ${DB_NAME}
  db_schema: ${TARGET_USER}
  user: ${DB_USER}
  password: ${DB_PASS}
  sslmode: require
YAML

cat > "${REPO_DIR}/README.txt" <<TXT
Feast repo for ${TARGET_USER}
- Offline schema: ${TARGET_USER}
- Online table: ${FEAST_ONLINE_TABLE}
- Registry: s3://${FEAST_REGISTRY_BUCKET}/registry/${TARGET_USER}/
TXT

chown -R "$TARGET_USER:$TARGET_USER" "$REPO_DIR"
echo "[feast-bootstrap] workspace ready at ${REPO_DIR}"

