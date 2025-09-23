#!/usr/bin/env bash
set -euo pipefail
# Idempotent host setup for the training EC2 (Amazon Linux 2023)

echo "[course-kit] installing host dependencies…"
sudo dnf -y update

# Core tools
sudo dnf -y install aws-cli || true

# Postgres client (try 16, fallback to default)
if ! command -v psql >/dev/null 2>&1; then
  sudo dnf -y install postgresql16 || sudo dnf -y install postgresql
fi

# Python 3.12 + pip
if ! python3.12 -V >/dev/null 2>&1; then
  sudo dnf -y install python3.12 python3.12-pip python3.12-devel gcc
fi

# Python packages (pin anything you care about)
python3.12 -m pip install --upgrade pip
python3.12 -m pip install feast boto3 psycopg2-binary scikit-learn==1.5.2

echo "[course-kit] done."

