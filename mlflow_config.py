import os

import mlflow
from dotenv import load_dotenv

load_dotenv()


def mlflow_tracking_uri() -> str:
    return (
        f"postgresql://{os.environ['NEON_PGUSER']}:{os.environ['NEON_PGPASSWORD']}"
        f"@{os.environ['NEON_PGHOST']}:{os.environ['NEON_PGPORT']}"
        f"/{os.environ['NEON_PGDATABASE']}?sslmode={os.environ['NEON_SSLMODE']}"
    )


def configure_mlflow() -> str:
    uri = mlflow_tracking_uri()
    mlflow.set_tracking_uri(uri)
    return uri