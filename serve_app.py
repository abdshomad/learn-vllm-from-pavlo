"""
Simple Ray Serve application example.

This provides a basic HTTP service to demonstrate Ray Serve functionality.
Can be deployed using: serve deploy serve_app.py
"""

import os
from ray import serve
try:
    from vllm import LLM
    VLLM_AVAILABLE = True
except ImportError:
    VLLM_AVAILABLE = False


@serve.deployment(
    name="echo_service",
    num_replicas=1,
    route_prefix="/echo"
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
    num_replicas=1,
    route_prefix="/calc"
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
    tensor_parallel_size = int(os.getenv("TENSOR_PARALLEL_SIZE", "1"))
    num_gpus = max(1, tensor_parallel_size)  # At least 1 GPU, more if tensor parallel
    
    @serve.deployment(
        name="tinyllama",
        num_replicas=1,
        route_prefix="/llm",
        ray_actor_options={"num_gpus": num_gpus}
    )
    class TinyLlamaService:
        """TinyLlama LLM service using vLLM."""
        
        def __init__(self):
            if not VLLM_AVAILABLE:
                raise RuntimeError("vLLM is not available. Please install vllm package.")
            
            # Get model path from environment or use default
            model_path = os.getenv("MODEL_DIR", "/mnt/shared/cluster-llm/TinyLlama-1.1B-Chat-v1.0")
            tensor_parallel_size = int(os.getenv("TENSOR_PARALLEL_SIZE", "1"))
            
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
                outputs = self.llm.generate([prompt], max_tokens=max_tokens, temperature=temperature)
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


# Create bound deployments
echo_service = EchoService.bind()
calculator = Calculator.bind()

# Only include TinyLlama if vLLM is available
deployments = [echo_service, calculator]
if VLLM_AVAILABLE:
    TinyLlamaService = create_tinyllama_deployment()
    tinyllama_service = TinyLlamaService.bind()
    deployments.append(tinyllama_service)
    print("TinyLlama service will be deployed")
else:
    print("Warning: vLLM not available, TinyLlama service will not be deployed")

# Export app for serve deploy (if needed)
app = serve.Application(deployments)

