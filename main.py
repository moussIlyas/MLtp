import os
from pprint import pprint

from mlflow.tracking import MlflowClient

from mlflow_config import configure_mlflow


def main():
    configure_mlflow()
    print(f"MLflow tracking connected to {os.environ['NEON_PGHOST']}/{os.environ['NEON_PGDATABASE']}")

    client = MlflowClient()
    pprint([{"name": e.name, "id": e.experiment_id} for e in client.search_experiments()])


if __name__ == "__main__":
    main()