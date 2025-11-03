# Learn vLLM from Pavlo YouTube Tutorial 

## Run a Large Language Model on a Multi-Server, Multi-GPU Ray Cluster (from youtube-transcript.txt)

This guide distills the steps from `youtube-transcript.txt` into a clear, reproducible walkthrough. It shows how to:
- Bring up a Ray cluster (single or multi-node with multiple GPUs)
- Download a lightweight model (TinyLlama) onto shared storage
- Launch vLLM to serve an OpenAI-compatible endpoint
- Connect from Open WebUI
- Use `uv` to create and manage the Python virtual environment

### High-level overview
- Target model: TinyLlama (1.1B parameters; lightweight and fast for development/testing)
- Example scale: 1 server with 2 GPUs
- OS: Ubuntu 22.04.5 LTS
- CUDA: 12.6
- Python: 3.13.5
- GPU: 2x NVIDIA L40 (46 GB each)
- Shared filesystem mounted on all servers so they can see the same model files
- Multi-NIC note: set `VLLM_HOST_IP` explicitly to avoid network binding issues

---

## 1) Prerequisites
- Linux servers with NVIDIA GPUs and CUDA 12.6 drivers installed
- Shared filesystem mounted on all servers (e.g., `/mnt/shared`)
- Outbound internet access to download models (Hugging Face or similar)
- `git` and, if using Hugging Face repos with large files, `git-lfs`

Optional but recommended:
- Open WebUI instance reachable by users

---

## 2) Create and activate the virtual environment with uv

Install `uv` (if not already installed):
```bash
curl -Ls https://astral.sh/uv/install.sh | sh
# Restart your shell or source your profile if needed
```

Create and activate a Python 3.13 environment in the project directory:
```bash
cd /home/aiserver/LABS/GPU-CLUSTER/pavlo-khmel-hpc
uv venv .venv -p 3.13
source .venv/bin/activate
```

Install required Python packages:
```bash
uv pip install --upgrade pip
uv pip install "ray[default]" vllm huggingface_hub git-lfs
```

Notes:
- If `git-lfs` is not available as a Python package in your environment, install it via your OS package manager instead (e.g., `apt install git-lfs`).

---

## 3) Prepare shared storage
Choose or create a shared directory accessible by all servers:
```bash
sudo mkdir -p /mnt/shared/cluster-llm
sudo chown "$USER":"$USER" /mnt/shared/cluster-llm
```

---

## 4) Configure vLLM host IP (multi-NIC environments)
If your servers have multiple IP addresses, set `VLLM_HOST_IP` on each server so vLLM binds to the correct interface:
```bash
export VLLM_HOST_IP=<this_server_primary_ip>
```

You can add this to your shell profile if desired.

---

## 5) Start the Ray cluster
For a single-node setup with 2 GPUs:
```bash
ray start --head --node-ip-address <NODE_IP> --port 6379
ray status
```
You should see the head node and its 2 GPUs.

For multi-node setup (if expanding later):
On each worker node:
```bash
ray start --address '<HEAD_NODE_IP>:6379' --node-ip-address <WORKER_NODE_IP>
```
Verify the cluster:
```bash
ray status
# or
ray list nodes
```
You should see all nodes and the total GPU count.

---

## 6) Download the model
Download TinyLlama model to the shared filesystem.

Using Hugging Face with `git-lfs`:
```bash
cd /mnt/shared/cluster-llm
git lfs install
git clone https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0

# Optional: save space by removing the .git directory once files are fully present
rm -rf TinyLlama-1.1B-Chat-v1.0/.git
```

If you use another download method (e.g., `huggingface-cli`), place the model under `/mnt/shared/cluster-llm/<MODEL_DIR>` and ensure all nodes can read it.

TinyLlama is small (~637 MB) and downloads quickly, making it ideal for testing and development.

---

## 7) Launch vLLM
Below are two patterns. Use the one that fits your setup.

### A) Single-node (for TinyLlama)
```bash
python -m vllm.entrypoints.openai.api_server \
  --model /mnt/shared/cluster-llm/TinyLlama-1.1B-Chat-v1.0 \
  --host 0.0.0.0 --port 8000 \
  --tensor-parallel-size 2
```

### B) Multi-node with Ray (for very large models)
vLLM supports distributed execution with Ray. A typical command shape looks like:
```bash
python -m vllm.entrypoints.openai.api_server \
  --model /mnt/shared/cluster-llm/TinyLlama-1.1B-Chat-v1.0 \
  --host 0.0.0.0 --port 8000 \
  --distributed-executor-backend ray \
  --tensor-parallel-size 2
```

Notes:
- Ensure your Ray cluster is up before launching vLLM.
- For TinyLlama, we use `--tensor-parallel-size 2` to utilize both GPUs.
- Depending on vLLM version and model, you may need to provide tensor/pipeline parallel sizes and other tuning flags. Consult vLLM docs for your version.
- First startup can be lengthy (close to 1 hour for extremely large models) while weights are loaded and cached. TinyLlama should load in seconds.

When the server is ready you should see: "Application startup complete".

---

## 8) Test the API
Use the OpenAI-compatible endpoint:
```bash
curl http://<HOST_OR_HEAD_NODE_IP>:8000/v1/models
```

Chat example:
```bash
curl http://<HOST_OR_HEAD_NODE_IP>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    "messages": [
      {"role": "user", "content": "Draw a cat in ASCII."}
    ]
  }'
```

---

## 9) Connect from Open WebUI
In Open WebUI admin settings:
- Add an OpenAI API connection
- Set the Base URL to `http://<HOST_OR_HEAD_NODE_IP>:8000/v1`
- Verify connection and make the model public if desired
- Create a new chat and select the model

---

## 10) Monitor GPU utilization
On any server:
```bash
watch -n 1 nvidia-smi
```
You should see GPUs fully utilized during inference.

---

## 11) Troubleshooting
- Set `VLLM_HOST_IP` to the machine's primary IP if you have multiple NICs.
- Ensure the shared filesystem is mounted and readable from all nodes.
- Verify Ray cluster health with `ray status` and `ray list nodes`.
- For very large models, initial startup can be slow; be patient and check logs.
- Use quantized or distilled variants if you cannot meet the GPU memory requirements of the full-size model.

---

## 12) Reference
This README was created based on the steps described in `youtube-transcript.txt`.
- Source video: [YouTube video](https://youtu.be/4tHtzVtvhFw)
