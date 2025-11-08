# Ray head node fails to start via `uv run ray`

## Issue

Running `scripts/04_start_ray_head.sh` (or other scripts that shell out to `uv run ray …`) failed immediately with:

```
error: Failed to spawn: `ray`
  Caused by: No such file or directory (os error 2)
```

or, after swapping to `python -m ray`, with:

```
/path/to/.venv/bin/python3: No module named ray.__main__; 'ray' is a package and cannot be directly executed
```

`uv run` does not automatically expose the `ray` console script inside the managed environment, so the CLI entrypoint could not be found or executed.

## Resolution

Use Ray's CLI module directly through Python:

- Replace `uv run ray <subcommand>` with `uv run python -m ray.scripts.scripts <subcommand>`.
- Update all project scripts (`04_start_ray_head.sh`, `05_start_ray_worker.sh`, `09_deploy_ray_serve.sh`, `99_shutdown_all.sh`) to invoke `python -m ray.scripts.scripts` for `start`, `status`, and `stop`.

After these changes, `scripts/98_run_all.sh` successfully brought up the Ray head node and proceeded with the rest of the workflow.


