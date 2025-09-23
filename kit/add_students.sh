#!/usr/bin/env bash
set -euo pipefail
# Usage: add_students.sh /path/to/students.csv
# CSV format: username,public_key,comment
CSV="${1:-/root/students.csv}"
if [[ ! -f "$CSV" ]]; then
  echo "[add_students] roster not found: $CSV"
  exit 1
fi

sudo /usr/sbin/groupadd -f students

while IFS=, read -r USER KEY COMMENT || [[ -n "${USER:-}" ]]; do
  [[ -z "${USER:-}" || "${USER:0:1}" == "#" ]] && continue

  if id "$USER" &>/dev/null; then
    echo "[add_students] user exists: $USER (updating key)"
  else
    sudo /usr/sbin/useradd -m -s /bin/bash -G students "$USER"
    echo "[add_students] created user: $USER"
  fi

  sudo install -d -m 700 -o "$USER" -g "$USER" "/home/$USER/.ssh"
  printf '%s %s\n' "$KEY" "${COMMENT:-}" | sudo tee "/home/$USER/.ssh/authorized_keys" >/dev/null
  sudo chown -R "$USER:$USER" "/home/$USER/.ssh"
  sudo chmod 600 "/home/$USER/.ssh/authorized_keys"
  sudo install -d -m 755 -o "$USER" -g "$USER" "/home/$USER/class"
done < "$CSV"

echo "[add_students] complete."

