import os
from google import genai
from dotenv import load_dotenv

# Load Environment Variables from .env
env_path = os.path.join(os.path.dirname(__file__), '.env')
load_dotenv(dotenv_path=env_path)

api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    print("API Key not found")
    exit(1)

client = genai.Client(api_key=api_key)

try:
    print("Fetching available models...")
    # List models to see what's available
    # The SDK method might vary, trying common pattern for the new library
    # If the new `google-genai` library is used, we check its specific method.
    # Often it is client.models.list()
    
    # Using the low-level list method if specific high level one isn't obvious
    # or just try to get a known model to see if it works.
    
    # Just generic listing
    import requests
    url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
    resp = requests.get(url)
    if resp.status_code == 200:
        data = resp.json()
        print(f"Found {len(data.get('models', []))} models.")
        for m in data.get('models', []):
            name = m.get('name', '').replace('models/', '')
            if 'gemini' in name.lower():
                print(f"- {name}")
    else:
        print(f"Error listing models: {resp.status_code} {resp.text}")

except Exception as e:
    print(f"Error: {e}")
