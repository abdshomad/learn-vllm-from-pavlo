# Global environment configuration for cluster scripts.
#
# These variables centralize the configuration that was previously scattered
# across the shell scripts inside `scripts/`. All helper scripts source
# `scripts/00_setup_common.sh`, which in turn sources this file (when present).
# Adjust the values below to match your deployment.

# Python version used by the `uv` virtual environment.
export PYTHON_VERSION=3.13

# Path to the project-local virtual environment managed by `uv`.
export VENV_DIR=/home/aiserver/LABS/GPU-CLUSTER/learn-vllm-from-pavlo-kheml-hpc/.venv

# Shared storage configuration for model assets.
export SHARED_DIR=/mnt/shared/cluster-llm
export MODEL_NAME=TinyLlama-1.1B-Chat-v1.0
export MODEL_REPO=https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0
export MODEL_DIR="${SHARED_DIR}/${MODEL_NAME}"

# Networking defaults for vLLM and Ray services.
export VLLM_HOST=0.0.0.0
export VLLM_HOST_IP="${VLLM_HOST}"
export TENSOR_PARALLEL_SIZE=2
export RAY_PORT=6379
export PROMETHEUS_PORT=9090
export GRAFANA_PORT=3000

# Toggle whether the Ray Serve deployment launches the TinyLlama service.
# Set to "1" to verify Serve-based LLMs. The deployment script will stop the
# standalone vLLM server automatically to free GPU memory.
export SERVE_ENABLE_TINYLLAMA=1


