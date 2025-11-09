"""
Shared pytest fixtures and utilities for service-level integration tests.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, Tuple, Callable
from urllib import error, request

import pytest

JsonDict = Dict[str, Any]
HttpRequester = Callable[[str, str, JsonDict | None, float], Tuple[int, JsonDict | str | None]]


def _http_request(url: str, method: str = "GET", payload: JsonDict | None = None, timeout: float = 30.0) -> Tuple[int, JsonDict | str | None]:
    """Make a simple JSON HTTP request using stdlib ``urllib``."""
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    req = request.Request(url, data=data, method=method.upper())
    req.add_header("Accept", "application/json")
    if payload is not None:
        req.add_header("Content-Type", "application/json")

    with request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        if not raw:
            return resp.status, None

        body = raw.decode("utf-8")
        try:
            return resp.status, json.loads(body)
        except json.JSONDecodeError:
            # Some endpoints (e.g. plain text) may not return JSON.
            return resp.status, body


def _wait_for_endpoint(url: str, timeout: float = 60.0) -> int:
    """
    Poll ``url`` until the service responds or ``timeout`` seconds elapse.

    Returns the last HTTP status code received. Raises the last connection error
    if the endpoint never becomes reachable.
    """
    deadline = time.time() + timeout
    last_exc: Exception | None = None

    while time.time() < deadline:
        try:
            with request.urlopen(url, timeout=5.0) as resp:
                return resp.status
        except error.HTTPError as http_err:
            # HTTPError still indicates the service responded.
            return http_err.code
        except Exception as exc:  # URLError, socket timeout, etc.
            last_exc = exc
            time.sleep(2.0)

    if last_exc is None:
        raise TimeoutError(f"Timed out waiting for {url}")
    raise last_exc


@pytest.fixture(scope="session")
def http_client() -> HttpRequester:
    """Expose the lightweight HTTP helper to individual tests."""
    return _http_request


@pytest.fixture(scope="session")
def vllm_service(http_client: HttpRequester) -> Dict[str, Any]:
    """
    Ensure the standalone vLLM OpenAI-compatible endpoint is reachable.

    Returns a configuration dictionary containing the ``base_url`` and a model
    identifier that can be used for completion requests.
    """
    host = (
        os.getenv("VLLM_TEST_HOST")
        or os.getenv("VLLM_HOST_IP")
        or os.getenv("VLLM_HOST")
        or "127.0.0.1"
    )
    port = int(os.getenv("VLLM_TEST_PORT") or os.getenv("VLLM_PORT") or 8000)
    base_url = f"http://{host}:{port}"

    # vLLM provides both /health and /v1/models; try either before giving up.
    probe_urls = (f"{base_url}/health", f"{base_url}/v1/models")
    for probe in probe_urls:
        try:
            _wait_for_endpoint(probe, timeout=45.0)
            break
        except Exception:
            continue
    else:  # pragma: no cover - safety net for environments without vLLM.
        pytest.skip(f"vLLM endpoint not reachable at {base_url}")

    try:
        status, models_payload = http_client(f"{base_url}/v1/models")
    except error.HTTPError as exc:
        pytest.skip(f"vLLM service at {base_url} returned HTTP {exc.code} for /v1/models")
    except Exception as exc:  # pragma: no cover - skip when service missing.
        pytest.skip(f"Unable to query vLLM /v1/models at {base_url}: {exc}")
    if status != 200 or not isinstance(models_payload, dict) or not models_payload.get("data"):
        pytest.skip(f"vLLM service at {base_url} did not return any models")

    model_candidates = models_payload["data"]
    model_id = None
    if isinstance(model_candidates, list) and model_candidates:
        first_model = model_candidates[0]
        if isinstance(first_model, dict):
            model_id = first_model.get("id")
    if not model_id:
        pytest.skip("Unable to determine a model id from vLLM /v1/models response")

    return {
        "base_url": base_url,
        "model": model_id,
    }


@pytest.fixture(scope="session")
def ray_serve_service(http_client: HttpRequester) -> Dict[str, Any]:
    """
    Ensure the Ray Serve ingress endpoint is reachable for LLM traffic.

    Returns a configuration dictionary containing the ``base_url`` for tests.
    """
    host = (
        os.getenv("RAY_SERVE_TEST_HOST")
        or os.getenv("SERVE_HOST")
        or os.getenv("NODE_IP")
        or "127.0.0.1"
    )
    port = int(os.getenv("RAY_SERVE_TEST_PORT") or os.getenv("SERVE_PORT") or 8001)
    base_url = f"http://{host}:{port}"

    try:
        _wait_for_endpoint(base_url, timeout=45.0)
    except Exception:  # pragma: no cover - skip when Serve not deployed.
        pytest.skip(f"Ray Serve ingress not reachable at {base_url}")

    status, payload = http_client(base_url)
    if status != 200 or not isinstance(payload, dict):
        pytest.skip(f"Unexpected response from Ray Serve ingress at {base_url}")

    return {
        "base_url": base_url,
    }

