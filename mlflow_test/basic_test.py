#!/usr/bin/env python3
import argparse
import mlflow
import numpy as np
from sklearn.linear_model import LinearRegression

def main(ip: str) -> None:
    # Build tracking URI
    tracking_uri = f"http://{ip}"
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment("infra-test")

    # Dummy data + model
    X = np.array([[1], [2], [3], [4], [5]])
    y = np.array([2, 4, 6, 8, 10])
    model = LinearRegression()

    with mlflow.start_run(run_name="hello-mlflow"):
        model.fit(X, y)
        preds = model.predict(X)

        # Log metrics
        mlflow.log_metric("mse", float(((preds - y) ** 2).mean()))
        mlflow.log_metric("r2", model.score(X, y))

        # Log params
        mlflow.log_param("fit_intercept", model.fit_intercept)

        # Log model
        mlflow.sklearn.log_model(model, name="model")

    print(f"Logged test run to {tracking_uri} as user {username}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MLflow smoke test")
    parser.add_argument("--ip", required=True, help="MLflow server public IP or hostname")
    args = parser.parse_args()

    main(args.ip)

