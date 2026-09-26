# Run the grading model in Colab

[`Run_qLoRA_Colab_vLLM.ipynb`](Run_qLoRA_Colab_vLLM.ipynb) serves the `Qwen/Qwen3.5-9B` base model with the `SmuFypTeam5/GradingQlora` LoRA adapter through an OpenAI-compatible vLLM API. The adapter is exposed as the model name `grading`. The notebook uses 4-bit BitsAndBytes loading by default and can expose the server through a temporary Cloudflare Quick Tunnel.

## Run the notebook

1. Open the notebook in Google Colab and select **Runtime → Change runtime type → GPU**. On a T4, the notebook uses FP16; on GPUs with native BF16 support, it uses BF16.
2. Provide `HF_TOKEN` and `VLLM_API_KEY` before running the configuration cell. You can add them to **Colab Secrets**, set them as environment variables, or upload the `.env` file from this folder to the Colab runtime's `/content` directory. Colab cannot read the copy on your computer automatically. The file should contain:

   ```env
   HF_TOKEN=your_hugging_face_token
   VLLM_API_KEY=your_private_api_key
   ```

   To upload the file, use Colab's **Files** sidebar and confirm it appears at `/content/.env`. The notebook reads `Path.cwd() / ".env"`, which is normally `/content/.env` in Colab. If either value is missing, the configuration cell prompts for it. You can leave `HF_TOKEN` blank if both Hugging Face repositories are public.
3. Run the cells from top to bottom. The install cell installs vLLM 0.30.0 and `vllm-bnb-plugin` 0.0.3, which provides the notebook's 4-bit BitsAndBytes quantization. It removes the unused TorchAudio package that can conflict with Colab's PyTorch CUDA build, then checks the vLLM CLI and BitsAndBytes registration. If you have already run notebook cells before changing packages, restart the runtime and run the notebook again from the top.
4. Authorize the Google Drive mount when the **Save model files** cell runs. On the first run, it downloads any missing base model and adapter files and saves complete copies under `MyDrive/qlora-vllm-models`. Allow about 20 GB of Drive space. If the files are already in this runtime's Hugging Face cache, the cell copies them to Drive without downloading them again. On a new runtime, it copies the saved files from Drive to local Colab storage before vLLM starts.
5. Wait for **`vLLM is ready.`** The notebook serves the local model and adapter in text-only mode, then checks `http://127.0.0.1:8000/v1/models`. The cell reports the latest log line each minute and waits up to 30 minutes. If startup times out, run the status and log cell immediately below it. The server process may still be loading, so check its status before rerunning the startup cell.
6. Run the local grading example. Then run the Cloudflare tunnel cell and copy its printed `VLLM_BASE_URL` (ending in `/v1`). Run the following verification cell to confirm the public endpoint responds.
7. Keep the Colab runtime and both processes running while clients use the API. Run the final cleanup cell when finished. A new tunnel URL is generated whenever the tunnel or runtime restarts.

The tunnel is intended for development or a demo. Keep its URL and API key private.

## Example API call

Run this from your computer after the tunnel cell prints its URL. Use the same API key supplied to the notebook:

```bash
export VLLM_BASE_URL="https://YOUR-SUBDOMAIN.trycloudflare.com/v1"
export VLLM_API_KEY="your_private_api_key"

curl -sS "$VLLM_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "grading",
    "messages": [
      {
        "role": "system",
        "content": "You are a strict grading assistant. Return ONLY a valid JSON array containing 0 or 1, with one value per criterion in order. Do not include explanations or markdown."
      },
      {
        "role": "user",
        "content": "Question:\nExplain why HTTPS is more secure than HTTP.\n\nDesired answer:\nHTTPS uses TLS to encrypt traffic between the client and server, helping protect data from interception and tampering.\n\nStudent answer:\nHTTPS encrypts the connection so attackers cannot easily read the traffic.\n\nCriteria:\n1. States that HTTPS encrypts traffic.\n2. States that HTTPS uses TLS/SSL.\n3. States that HTTPS protects against interception or tampering."
      }
    ],
    "temperature": 0,
    "max_tokens": 128,
    "stream": false,
    "chat_template_kwargs": {"enable_thinking": false}
  }'
```

The grading result is in `choices[0].message.content` and should be a JSON array such as `[1, 0, 1]`. For application use, copy the full `SYSTEM_PROMPT` and `make_messages(...)` format from the notebook so requests match the adapter's training format.
