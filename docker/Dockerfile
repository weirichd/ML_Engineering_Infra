# docker/Dockerfile
FROM python:3.11-slim

# System deps for mlflow + sqlite
RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

# Pin a recent mlflow; add gunicorn + boto3
ARG MLFLOW_VERSION=3.4.0
RUN pip install --no-cache-dir "mlflow==${MLFLOW_VERSION}" gunicorn boto3

# Non-root user
RUN useradd -m app
USER app
WORKDIR /app
EXPOSE 5000

# Single worker for SQLite stability
CMD mlflow server \
  --host 0.0.0.0 \
  --port 5000 \
  --backend-store-uri "${BACKEND_STORE_URI}" \
  --default-artifact-root "${DEFAULT_ARTIFACT_ROOT}" \
  --serve-artifacts \
  --workers 1

