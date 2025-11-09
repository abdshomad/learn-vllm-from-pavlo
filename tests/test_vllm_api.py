"""
Integration tests for the standalone vLLM OpenAI-compatible server.
"""

from __future__ import annotations

import json
from typing import Dict

import pytest


def test_vllm_lists_models(vllm_service: Dict[str, str], http_client):
    """
    The vLLM server should expose at least one model via /v1/models.
    """
    base_url = vllm_service["base_url"]

    status, payload = http_client(f"{base_url}/v1/models")
    assert status == 200, f"Expected HTTP 200 from /v1/models, got {status}"
    assert isinstance(payload, dict), "Expected JSON payload from /v1/models"
    assert payload.get("data"), "vLLM returned an empty model list"


def test_vllm_chat_completion(vllm_service: Dict[str, str], http_client):
    """
    The vLLM server should generate a short chat completion for a simple prompt.
    """
    base_url = vllm_service["base_url"]
    model_id = vllm_service["model"]

    prompt = "Respond with a friendly greeting in fewer than ten words."
    payload = {
        "model": model_id,
        "messages": [
            {"role": "system", "content": "You are a concise assistant."},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": 64,
        "temperature": 0.6,
    }

    status, response_json = http_client(
        f"{base_url}/v1/chat/completions", method="POST", payload=payload, timeout=120.0
    )
    assert status == 200, f"Expected HTTP 200 from chat completion, got {status}"
    assert isinstance(response_json, dict), "Expected JSON response from chat completion"
    assert response_json.get("choices"), "vLLM did not return any choices"

    choice = response_json["choices"][0]
    assert isinstance(choice, dict), "Completion choice should be a JSON object"
    message = choice.get("message", {})
    assert isinstance(message, dict), "Completion message should be a JSON object"
    content = message.get("content", "").strip()
    assert content, "vLLM returned an empty completion"
    assert len(content.split()) <= 20, "Completion appears unexpectedly long"

    usage = response_json.get("usage")
    if usage is not None:
        # Ensure usage stats follow the OpenAI schema when provided.
        assert set(usage.keys()).issuperset({"prompt_tokens", "completion_tokens", "total_tokens"})

