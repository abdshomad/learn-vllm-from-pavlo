## Agent guide: Always use `uv` virtualenv to run Python

This repository standardizes on `uv` for Python environment management and execution. Always create and run inside a `uv`-managed virtual environment; do not use the system Python.

### 1) Install `uv` (once per machine)

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
# then ensure ~/.local/bin is in PATH, e.g.:
export PATH="$HOME/.local/bin:$PATH"
uv --version
```

Alternatively via pipx:

```bash
pipx install uv
```

### 2) Create the virtual environment

Create a project-local venv named `.venv` at the repo root:

```bash
cd /home/aiserver/LABS/GPU-CLUSTER/pavlo-khmel-hpc
uv venv .venv
```

You do not need to activate it; prefer `uv run` for commands. If you prefer activation:

```bash
source .venv/bin/activate
```

### 3) Install dependencies

If the project uses `pyproject.toml` (PEP 621/uv/poetry-style):

```bash
uv sync  # installs according to pyproject + lock
```

If the project uses `requirements.txt`:

```bash
uv pip install -r requirements.txt
```

To add a new dependency (pyproject workflow):

```bash
uv add <package>            # runtime dep
uv add --dev <package>      # dev/test dep
```

To update all locked deps (pyproject workflow):

```bash
uv lock --upgrade
uv sync
```

To capture an exact environment snapshot when using requirements files:

```bash
uv pip freeze > requirements-lock.txt
```

### 4) Run the application (always via `uv run`)

Run Python modules or scripts through `uv run` so the `.venv` is used automatically:

```bash
# Example: module entrypoint
uv run -m your_package.main

# Example: script file
uv run python app.py

# Example: invoke CLI inside env
uv run pytest -q
uv run ruff check .
```

### 5) Non-interactive/CI usage

```bash
uv venv .venv
uv sync || uv pip install -r requirements.txt
uv run -m your_package.main
```

### 6) Notes for GPU environments

- Ensure system CUDA/NVIDIA drivers match the installed Python packages (e.g., `torch`/`jax` wheels). If you need a specific CUDA build, pin the package accordingly.
- For multi-node or Ray/vLLM scripts, still wrap all Python execution with `uv run` to guarantee the correct interpreter and site-packages.

### 7) Quick reference

- Create venv: `uv venv .venv`
- Install (pyproject): `uv sync`
- Install (requirements): `uv pip install -r requirements.txt`
- Run code: `uv run <command>`
- Add dep: `uv add <name>`
- Freeze (reqs workflow): `uv pip freeze > requirements-lock.txt`


