# MLtp — MLflow + DVC course

A tiny practce project for experiment tracking (**MLflow**) and data versioning (**DVC**), backed by a Neon Postgres DB and a Hugging Face Storage Bucket.

## 0. Setup

```bash
uv venv                        # create .venv
uv add mlflow python-dotenv    # deps (already in pyproject)
uv add "dvc[s3]" huggingface_hub pd  # dvc + hf bucket + pandas
source .venv/bin/activate      # activate
```

Everything is already installed in `pyproject.toml` — just `uv sync`.

### Environment (`.env`)

| Variable            | Purpose                                  |
|---------------------|------------------------------------------|
| `NEON_PGHOST/...`   | Neon Postgres (MLflow backend)           |
| `NEON_PGPASSWORD`   | DB password                              |
| `HF_TOKEN`          | Hugging Face API token                   |
| `HF_S3_ACCESS_KEY`  | S3 gateway key (generate on HF settings) |
| `HF_S3_SECRET_KEY`  | S3 gateway secret                        |

`.env` is `.gitignore`d — never commit it.

---

## Part 1 — MLflow (experiment tracking)

MLflow stores *metadata* (params, metrics, artifacts) about your runs. Here it writes to **Neon Postgres**.

### 1.1 Configuration

All notebooks/models use one shared module — `mlflow_config.py`:

```python
from mlflow_config import configure_mlflow
configure_mlflow()   # reads .env, sets tracking URI
```

`configure_mlflow()` calls `mlflow.set_tracking_uri(...)` **immediately**. The URI is kept in a process-wide global, so every later `log_*` call writes to Postgres. Call it before any experiment/run.

### 1.2 Log a run

```python
import mlflow

mlflow.set_experiment("my-model")                    # create/select experiment

with mlflow.start_run(run_name="run-1"):
    mlflow.log_param("model", "LinearRegression")    # hyperparameters / config
    mlflow.log_param("learning_rate", 0.01)

    for step in range(10):                           # metric per step (series)
        mlflow.log_metric("loss", 0.5 / (1 + step), step=step)

    mlflow.log_metric("rmse", 0.42)                  # final metric
    mlflow.log_artifact("model.txt")                 # save files
    print("run_id:", mlflow.active_run().info.run_id)
```

### 1.3 Query runs (MlflowClient)

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()
exp = client.get_experiment_by_name("my-model")
for run in client.search_runs(experiment_ids=[exp.experiment_id]):
    print(run.info.run_id, run.data.params, run.data.metrics)
```

### 1.4 UI

No need to copy the URI — `mlflow_ui.sh` reads `.env`, builds it and launches the server:

```bash
./mlflow_ui.sh                    # build URI from .env + start UI
./mlflow_ui.sh --port 5001        # optional flags pass through
# open http://localhost:5000
```

(Startup takes ~20-30 s while MLflow connects to Neon Postgres.)

> Tip: in the mlflow 3.x UI, the experiment opens on the "Overview" tab (GenAI
> traces/usage — empty unless you log traces). Click the **Runs** tab to see the
> params/metrics table.

### 1.5 Deleting runs / experiments

MLflow only **soft-deletes** (hidden from the UI, recoverable):

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()
client.delete_run("run_id")          # delete one run
client.restore_run("run_id")         # undo delete
client.delete_experiment("1")        # delete a whole experiment
client.restore_experiment("1")       # undo delete
```

Find run ids first:

```python
exp = client.get_experiment_by_name("my-model")
for r in client.search_runs([exp.experiment_id]):
    print(r.info.run_id, r.data.metrics)
```

To **fully purge** from Neon (rows stay in Postgres after soft delete), run SQL against
the DB, e.g. `DELETE FROM experiments WHERE experiment_id='1';` (or recreate the
database).

Mini cheat-sheet:

| You want…            | Use                                             |
|----------------------|-------------------------------------------------|
| point to a backend   | `mlflow.set_tracking_uri(uri)`                  |
| choose/create design | `mlflow.set_experiment("name")`                 |
| start a run          | `with mlflow.start_run(...)`                    |
| log hyperparam       | `mlflow.log_param("lr", 0.01)`                  |
| log metric           | `mlflow.log_metric("acc", 0.95)`                |
| save a file          | `mlflow.log_artifact("path")`                   |
| save a model         | `mlflow.sklearn.log_model(model, "model")`      |
| query runs           | `MlflowClient().search_runs([exp_id])`          |

---

## Part 2 — DVC (data versioning)

DVC tracks **data files**. Git stores small `.dvc` pointer files; the real bytes live on a **remote** — here a Hugging Face Storage Bucket via its S3 gateway.

### 2.0 Remote (already configured)

```bash
.venv/bin/dvc remote list          # hf-bucket  s3://MLTP-dvc/dvc-store (default)
cat .dvc/config                    # endpointurl = https://s3.hf.co/moussll
```

Credentials come from `.env` via the helper:

```bash
source hf_env.sh                   # exports AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
```

### 2.1 Track data

```bash
source hf_env.sh
dvc add data/          # creates data.dvc + updates .gitignore
git add data.dvc .gitignore && git commit -m "track data"
dvc push               # upload blobs to the bucket
```

### 2.2 The DVC lifecycle

| Step                    | Command                                |
|-------------------------|----------------------------------------|
| init DVC                | `dvc init`                             |
| track data file/dir     | `dvc add data/`                        |
| save to remote          | `dvc push`                             |
| fetch from remote       | `dvc pull`                             |
| local cache status      | `dvc status`                           |
| vs remote               | `dvc status --remote hf-bucket`        |
| edit data → re-version  | `dvc add data/` again, `dvc push`      |
| back to an old version  | `git checkout old-commit -- data.dvc` + `dvc checkout` |
| import external data    | `dvc import https://hf.co/datasets/... file.csv` |

### 2.3 Sharing with your friend

Friend needs:
1. the git repo (contains `data.dvc` + `.dvc/config` as only "code"),
2. the same `HF_S3_ACCESS_KEY` / `HF_S3_SECRET_KEY` (or their own bucket creds).

```bash
git clone <repo> && cd <repo>
source hf_env.sh        # their .env / helper
dvc pull                # downloads data from the HF bucket
```

Then both push/pull the same bucket — that's the whole point: code versioned in git, data versioned in DVC.

### 2.4 Removing data

Stop tracking a file/dir (deletes `data.dvc`, **keeps** the folder):

```bash
dvc remove data.dvc
```

Stop tracking **and** delete the files + cached copy:

```bash
dvc remove data.dvc --outs
```

Remove a remote from DVC config:

```bash
dvc remote remove hf-bucket
```

Delete pushed blobs from the HF bucket that the workspace no longer uses
(garbage-collect the remote):

```bash
source hf_env.sh
dvc gc -w -r hf-bucket
```

Alternatively wipe the whole bucket in the HF UI (or `hf buckets rm`). Reset all
local DVC state:

```bash
rm -rf .dvc data data.dvc
```

---

## Workflow summary

```bash
# 1. tune → every run logged to Neon Postgres
configure_mlflow(); with mlflow.start_run(): log_param(...); log_metric(...)

# 2. share experiments        → mlflow ui
# 3. version the dataset      → dvc add data/ && dvc push
# 4. friend gets data/experiments → git pull + dvc pull (+ mlflow reads Postgres)
```