"""
Deploy Ray Serve application.

This script deploys the Serve application defined in serve_app.py.
"""

import os
import ray
from ray import serve

# Get configuration from environment variables
SERVE_HOST = os.getenv('SERVE_HOST', '0.0.0.0')
SERVE_PORT = int(os.getenv('SERVE_PORT', '8001'))

# Model configuration (should be set by the calling script)
MODEL_DIR = os.getenv('MODEL_DIR', '/mnt/shared/cluster-llm/TinyLlama-1.1B-Chat-v1.0')
TENSOR_PARALLEL_SIZE = int(os.getenv('TENSOR_PARALLEL_SIZE', '1'))

print(f"Deploying Ray Serve application...")
print(f"  Serve host: {SERVE_HOST}")
print(f"  Serve port: {SERVE_PORT}")
print(f"  Model directory: {MODEL_DIR}")
print(f"  Tensor parallel size: {TENSOR_PARALLEL_SIZE}")

# Connect to existing Ray cluster
ray.init(address='auto', ignore_reinit_error=True)

# Start serve if not already started
try:
    serve.start(detached=True, http_options={'host': SERVE_HOST, 'port': SERVE_PORT})
except RuntimeError:
    # Serve already started
    pass

# Deploy using serve.run() which handles everything
from serve_app import app

# Deploy all services using serve.run() with the app
# This will deploy all services with route_prefix="/"
serve.run(app, name='serve_app', route_prefix="/", blocking=False)

print('Ray Serve application deployed successfully!')
print(f'Access echo service at: http://<NODE_IP>:{SERVE_PORT}/echo')
print(f'Access calculator at: http://<NODE_IP>:{SERVE_PORT}/calc')
print(f'Access TinyLlama LLM at: http://<NODE_IP>:{SERVE_PORT}/llm')

