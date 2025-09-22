# MLflow on AWS EC2 (with SQLite + S3 + Nginx + Basic Auth)

This repository provisions an **MLflow tracking server** on AWS using CloudFormation and GitHub Actions.  
The deployment includes:

- **EC2 instance** running MLflow (Dockerized)
- **SQLite** backend for tracking metadata
- **S3 bucket** for artifact storage
- **Nginx** reverse proxy
- **Basic authentication** (username/password login)

Once deployed, you’ll have a URL like:

```
http://<EC2_PUBLIC_IP>
```

which prompts for a username and password before accessing MLflow.

---

## Prerequisites

1. **AWS Account** with:
   - Administrator or sufficient IAM permissions to create EC2, S3, and IAM roles.
   - A default VPC + subnet in your chosen region.

2. **GitHub Repository Setup**
   - Fork or clone this repository.
   - In your repo, configure GitHub Actions secrets:
     - `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
     - `AWS_REGION` (e.g., `us-east-2`)

3. **Local Tools (optional for CLI deploys)**
   - [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
   - [jq](https://stedolan.github.io/jq/) (for JSON parsing)

---

## Deployment

### 1. Push to `main` branch
When you push changes to `main`, GitHub Actions will:

- Build/publish the Docker image to GHCR (`ghcr.io/<OWNER>/mlflow-server:latest`).
- Deploy/update the CloudFormation stack (`mlflow-ec2`).
- Output the public IP address of your MLflow server.

### 2. Access the MLflow server
Open:

```
http://<EC2_PUBLIC_IP>
```

You’ll see a login prompt. Use the credentials from `/var/lib/mlflow/auth/basic_auth.ini`.

Default (for testing):
- Username: `admin`
- Password: `password1234`

---

## Managing Users

MLflow’s basic auth stores user information in a SQLite DB (`basic_auth.db`) located at `/var/lib/mlflow/auth`.

### 1. SSH into the EC2 instance

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_PUBLIC_IP>
sudo -i   # become root
```

### 2. Open a shell inside the container

```bash
docker exec -it mlflow bash
```

### 3. Create the database if not already present

```bash
mlflow auth create-default-db --config-path /mlflow_auth/basic_auth.ini
```

### 4. Add a new user

```bash
mlflow auth create-user   --username bob   --password mysecurepass   --config-path /mlflow_auth/basic_auth.ini
```

### 5. Set user permissions

```bash
mlflow auth set-permission   --username bob   --permission READ   --config-path /mlflow_auth/basic_auth.ini
```

Available permissions:
- `READ` (can view experiments/runs)
- `WRITE` (can create/modify runs)
- `ADMIN` (full access, including managing users)

### 6. List users

```bash
mlflow auth list-users --config-path /mlflow_auth/basic_auth.ini
```

---

## Testing

You can test logging to MLflow with:

```bash
pip install mlflow boto3
python scripts/test_log.py --ip <EC2_PUBLIC_IP> --username <USER> --password <PASS>
```

This script:
- Connects to the remote tracking server
- Creates a test experiment/run
- Logs a parameter, metric, and artifact to S3

---

## Cleanup

To tear everything down:

```bash
aws cloudformation delete-stack --stack-name mlflow-ec2
```

This removes:
- EC2 instance
- Security group
- IAM role
- S3 artifact bucket

---

## End Result

- An accessible MLflow server at `http://<EC2_PUBLIC_IP>`
- Authentication enforced (per-user credentials)
- Persistent metadata in SQLite (on EC2 disk)
- Artifacts stored in S3
- Nginx reverse proxy for stability
