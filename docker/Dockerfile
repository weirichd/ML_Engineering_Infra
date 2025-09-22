FROM python:3.11-slim

RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

ARG MLFLOW_VERSION=3.4.0
RUN pip install --no-cache-dir "mlflow==${MLFLOW_VERSION}" gunicorn boto3

RUN groupadd -g 1000 app && useradd -u 1000 -g 1000 -m app
USER app
WORKDIR /app
EXPOSE 5000

CMD mlflow server \
  --host 0.0.0.0 \
  --port 5000 \
  --backend-store-uri "${BACKEND_STORE_URI}" \
  --default-artifact-root "${DEFAULT_ARTIFACT_ROOT}" \
  --serve-artifacts \
  --workers 1

