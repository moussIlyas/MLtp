#!/usr/bin/env bash
set -a
[ -f .env ] && . ./.env
set +a
export AWS_ACCESS_KEY_ID="${HF_S3_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${HF_S3_SECRET_KEY}"

usage() {
    cat <<EOF
Sources .env and exports AWS credentials for the HF Storage Bucket DVC remote.
Usage:
    source hf_env.sh && dvc push
    source hf_env.sh && dvc pull
    source hf_env.sh && dvc status --remote hf-bucket
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Run with: source hf_env.sh" >&2
    usage
fi