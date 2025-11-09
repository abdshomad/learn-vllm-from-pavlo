"""
Simple Ray Serve application example.

This provides a basic HTTP service to demonstrate Ray Serve functionality.
Can be deployed using: serve deploy serve_app.py
"""

import os
from ray import serve
try:
    from vllm import LLM
    from vllm import SamplingParams
    VLLM_AVAILABLE = True
except ImportError:
    VLLM_AVAILABLE = False


@serve.deployment(
    name="echo_service",
    num_replicas=1
)
class EchoService:
    """Simple echo service that returns the input message."""
    
    def __init__(self):
        self.service_name = "EchoService"
    
    async def __call__(self, request):
        """Handle HTTP requests."""
        if hasattr(request, "method") and request.method == "POST":
            data = await request.json()
            message = data.get("message", "Hello from Ray Serve!")
            return {"echo": message, "service": self.service_name}
        elif isinstance(request, dict):
            # Handle direct dict input
            message = request.get("message", "Hello from Ray Serve!")
            return {"echo": message, "service": self.service_name}
        else:
            return {"message": "Send a POST request with a 'message' field", "service": self.service_name}


@serve.deployment(
    name="calculator",
    num_replicas=1
)
class Calculator:
    """Simple calculator service."""
    
    def __init__(self):
        self.service_name = "Calculator"
    
    async def __call__(self, request):
        """Handle HTTP requests for calculations."""
        if hasattr(request, "method") and request.method == "POST":
            data = await request.json()
        elif isinstance(request, dict):
            data = request
        else:
            return {
                "message": "Send a POST request with 'operation' (add/subtract/multiply/divide), 'a', and 'b'",
                "service": self.service_name
            }
        
        operation = data.get("operation")
        a = float(data.get("a", 0))
        b = float(data.get("b", 0))
        
        if operation == "add":
            result = a + b
        elif operation == "subtract":
            result = a - b
        elif operation == "multiply":
            result = a * b
        elif operation == "divide":
            if b == 0:
                return {"error": "Division by zero"}
            result = a / b
        else:
            return {"error": f"Unknown operation: {operation}"}
        
        return {
            "operation": operation,
            "a": a,
            "b": b,
            "result": result,
            "service": self.service_name
        }


def create_tinyllama_deployment():
    """Create TinyLlama deployment with appropriate GPU allocation."""
    env_tensor_parallel = os.getenv("TENSOR_PARALLEL_SIZE", "1")
    try:
        tensor_parallel_size = max(1, int(env_tensor_parallel))
    except ValueError:
        tensor_parallel_size = 1
    num_gpus = tensor_parallel_size if tensor_parallel_size > 0 else 1
    ray_actor_options = {
        "num_gpus": num_gpus,
        "runtime_env": {"env_vars": {"TENSOR_PARALLEL_SIZE": str(tensor_parallel_size)}},
    }
    
    @serve.deployment(
        name="tinyllama",
        num_replicas=1,
        ray_actor_options=ray_actor_options
    )
    class TinyLlamaService:
        """TinyLlama LLM service using vLLM."""
        
        def __init__(self, tensor_parallel=tensor_parallel_size):
            if not VLLM_AVAILABLE:
                raise RuntimeError("vLLM is not available. Please install vllm package.")
            
            # Get model path from environment or use default
            model_path = os.getenv("MODEL_DIR", "/mnt/shared/cluster-llm/TinyLlama-1.1B-Chat-v1.0")
            tensor_parallel_size = tensor_parallel
            
            print(f"Loading TinyLlama model from: {model_path}")
            print(f"Tensor parallel size: {tensor_parallel_size}")
            
            # Initialize vLLM LLM engine
            self.llm = LLM(
                model=model_path,
                tensor_parallel_size=tensor_parallel_size,
                trust_remote_code=True
            )
            self.service_name = "TinyLlamaService"
            print(f"{self.service_name} initialized successfully")
        
        async def __call__(self, request):
            """Handle HTTP requests for LLM inference."""
            if hasattr(request, "method") and request.method == "POST":
                data = await request.json()
            elif isinstance(request, dict):
                data = request
            else:
                return {
                    "error": "Send a POST request with 'prompt' or 'messages' field",
                    "service": self.service_name
                }
            
            # Handle both prompt and messages format (OpenAI-compatible)
            if "messages" in data:
                # OpenAI chat format
                messages = data["messages"]
                prompt = self._messages_to_prompt(messages)
            elif "prompt" in data:
                prompt = data["prompt"]
            else:
                return {
                    "error": "Missing 'prompt' or 'messages' field",
                    "service": self.service_name
                }
            
            # Generate response
            max_tokens = data.get("max_tokens", 100)
            temperature = data.get("temperature", 0.7)
            
            try:
                # Use SamplingParams for vLLM
                sampling_params = SamplingParams(
                    max_tokens=max_tokens,
                    temperature=temperature
                )
                outputs = self.llm.generate([prompt], sampling_params=sampling_params)
                generated_text = outputs[0].outputs[0].text if outputs else ""
                
                return {
                    "prompt": prompt,
                    "response": generated_text,
                    "service": self.service_name
                }
            except Exception as e:
                return {
                    "error": str(e),
                    "service": self.service_name
                }
        
        def _messages_to_prompt(self, messages):
            """Convert OpenAI messages format to prompt string."""
            prompt_parts = []
            for msg in messages:
                role = msg.get("role", "user")
                content = msg.get("content", "")
                if role == "system":
                    prompt_parts.append(f"System: {content}")
                elif role == "user":
                    prompt_parts.append(f"User: {content}")
                elif role == "assistant":
                    prompt_parts.append(f"Assistant: {content}")
            return "\n".join(prompt_parts)
    
    return TinyLlamaService


# Create an ingress deployment that routes to different services
@serve.deployment
class Ingress:
    def __init__(self, echo_handle, calc_handle, llm_handle=None):
        self.echo_handle = echo_handle
        self.calc_handle = calc_handle
        self.llm_handle = llm_handle
    
    async def __call__(self, request):
        path = request.url.path.rstrip("/")
        
        # Extract request data if it's a POST request
        if hasattr(request, "method") and request.method == "POST":
            try:
                data = await request.json()
            except:
                data = {}
        else:
            data = {}
        
        if path == "/echo" or path.startswith("/echo/"):
            # Forward the request to echo service
            result = await self.echo_handle.remote(data if data else request)
            return result
        elif path == "/calc" or path.startswith("/calc/"):
            # Forward the request to calculator service
            result = await self.calc_handle.remote(data if data else request)
            return result
        elif path == "/llm" or path.startswith("/llm/"):
            if self.llm_handle:
                result = await self.llm_handle.remote(data if data else request)
                return result
            else:
                return {"error": "LLM service not available"}
        else:
            return {
                "message": "Ray Serve Application",
                "available_endpoints": {
                    "/echo": "Echo service - POST with {'message': 'text'}",
                    "/calc": "Calculator service - POST with {'operation': 'add|subtract|multiply|divide', 'a': number, 'b': number}",
                    "/llm": "TinyLlama LLM service - POST with {'prompt': 'text', 'max_tokens': number}"
                }
            }

"""
Environment flags:
- SERVE_ENABLE_TINYLLAMA: if set to "0", skip deploying the TinyLlama service
  so the app can be deployed alongside an external vLLM server that already
  occupies the GPUs. Default: "1" (deploy when vLLM is installed).
"""

# Create bound deployments
echo_service = EchoService.bind()
calculator = Calculator.bind()

# Only include TinyLlama if enabled AND vLLM is available
enable_tinyllama = os.getenv("SERVE_ENABLE_TINYLLAMA", "1") != "0"
if enable_tinyllama and VLLM_AVAILABLE:
    TinyLlamaService = create_tinyllama_deployment()
    tinyllama_service = TinyLlamaService.bind()
    app = Ingress.bind(echo_service, calculator, tinyllama_service)
    print("TinyLlama service will be deployed")
else:
    app = Ingress.bind(echo_service, calculator, None)
    if not enable_tinyllama:
        print("TinyLlama service disabled by SERVE_ENABLE_TINYLLAMA=0")
    else:
        print("Warning: vLLM not available, TinyLlama service will not be deployed")

