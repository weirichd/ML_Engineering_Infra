# Comp 376 Course Kit

All host-side, repeatable scripts for the training EC2.

## Contents
- `install-host.sh` – idempotent host setup (python libs, tools)
- `add_students.sh` – create/update Linux users from a CSV roster
- `bootstrap_feast_user.sh` – per-student Feast workspace (RDS schema, S3 registry, DDB online store)

