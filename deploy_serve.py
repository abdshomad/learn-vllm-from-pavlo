"""
Deploy Ray Serve application.

This script deploys the Serve application defined in serve_app.py.
"""

import os
import ray
from ray import serve
from serve_app import app

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

# Deploy the applications using serve.run
# This will start serve and deploy all deployments including TinyLlama
try:
    serve.run(app, host=SERVE_HOST, port=SERVE_PORT, name='serve_app')
except Exception as e:
    # If serve.run fails, try the alternative approach
    print(f"Warning: serve.run failed with {e}, trying alternative deployment method...")
    # Start serve explicitly
    serve.start(detached=True, http_options={'host': SERVE_HOST, 'port': SERVE_PORT})
    # Deploy the app
    serve.deploy(app, name='serve_app')

print('Ray Serve application deployed successfully!')
print(f'Access echo service at: http://<NODE_IP>:{SERVE_PORT}/echo')
print(f'Access calculator at: http://<NODE_IP>:{SERVE_PORT}/calc')
print(f'Access TinyLlama LLM at: http://<NODE_IP>:{SERVE_PORT}/llm')

