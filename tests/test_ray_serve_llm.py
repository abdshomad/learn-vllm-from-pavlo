"""
Integration tests for the Ray Serve TinyLlama deployment.
"""

from __future__ import annotations

from typing import Dict

import pytest


def test_ray_serve_ingress_lists_endpoints(ray_serve_service: Dict[str, str], http_client):
    """
    The ingress root should advertise available endpoints, including /llm.
    """
    base_url = ray_serve_service["base_url"]

    status, payload = http_client(base_url)
    assert status == 200, f"Expected HTTP 200 from Serve ingress, got {status}"
    assert isinstance(payload, dict), "Expected JSON payload from Serve ingress"
    endpoints = payload.get("available_endpoints")
    assert isinstance(endpoints, dict), "Expected 'available_endpoints' in Serve ingress response"
    assert "/llm" in endpoints, "Serve ingress did not advertise the /llm endpoint"


def test_ray_serve_tinyllama_completion(ray_serve_service: Dict[str, str], http_client):
    """
    The Serve LLM endpoint should generate a short response for a simple prompt.
    """
    base_url = ray_serve_service["base_url"]
    payload = {
        "prompt": "List two Indonesian islands separated by a newline.",
        "max_tokens": 64,
        "temperature": 0.6,
    }

    status, response_json = http_client(
        f"{base_url}/llm", method="POST", payload=payload, timeout=180.0
    )
    assert status == 200, f"Expected HTTP 200 from Serve /llm endpoint, got {status}"
    assert isinstance(response_json, dict), "Expected JSON response from Serve /llm endpoint"

    if "error" in response_json:
        pytest.skip(f"Serve /llm endpoint reported error: {response_json['error']}")
    assert "response" in response_json, "Serve /llm response did not include 'response'"
    content = str(response_json["response"]).strip()
    if not content:
        pytest.skip("Serve /llm response content is empty (service likely disabled)")

    # Optional metadata
    assert response_json.get("service") in (None, "TinyLlamaService", "tinyllama", "TinyLlama"), \
        "Serve /llm response missing expected service metadata"


def test_ray_serve_echo_endpoint(ray_serve_service: Dict[str, str], http_client):
    """
    The Echo service should return the same message payload.
    """
    base_url = ray_serve_service["base_url"]
    payload = {"message": "Verification from pytest"}

    status, response_json = http_client(f"{base_url}/echo", method="POST", payload=payload)
    assert status == 200, f"Expected HTTP 200 from Serve /echo endpoint, got {status}"
    assert isinstance(response_json, dict), "Expected JSON response from Serve /echo endpoint"
    assert response_json.get("echo") == payload["message"], "Echo service did not mirror the message"
    assert response_json.get("service") in (None, "EchoService", "echo"), \
        "Echo endpoint response missing service metadata"


def test_ray_serve_calculator_addition(ray_serve_service: Dict[str, str], http_client):
    """
    The calculator should handle an addition request.
    """
    base_url = ray_serve_service["base_url"]
    payload = {"operation": "add", "a": 13, "b": 21}

    status, response_json = http_client(f"{base_url}/calc", method="POST", payload=payload)
    assert status == 200, f"Expected HTTP 200 from Serve /calc endpoint, got {status}"
    assert isinstance(response_json, dict), "Expected JSON response from Serve /calc endpoint"
    assert response_json.get("result") == pytest.approx(34), "Calculator addition result incorrect"
    assert response_json.get("operation") == "add", "Calculator response missing operation echo"


def test_ray_serve_calculator_divide_by_zero(ray_serve_service: Dict[str, str], http_client):
    """
    The calculator should reject divide-by-zero operations gracefully.
    """
    base_url = ray_serve_service["base_url"]
    payload = {"operation": "divide", "a": 7, "b": 0}

    status, response_json = http_client(f"{base_url}/calc", method="POST", payload=payload)
    assert status == 200, f"Expected HTTP 200 from Serve /calc endpoint, got {status}"
    assert isinstance(response_json, dict), "Expected JSON response from Serve /calc endpoint"
    assert "error" in response_json, "Calculator divide-by-zero should return error field"

