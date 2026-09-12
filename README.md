# qlora

## Install the vLLM server

Python 3.12 and an NVIDIA GPU with a compatible driver are required. Create a
dedicated environment and install the pinned serving dependencies:

```bash
uv venv --python 3.12 .venv-vllm
source .venv-vllm/bin/activate
uv pip install -r requirements-vllm.txt
```

Then start the quantized base model and QLoRA adapter:

```bash
./serve_qwen35_vllm.sh
```

## Compare the base and QLoRA models

Start `serve_qwen35_vllm.sh`, then send the same grading request to both
model aliases.

### Dataset example and ground truth

This example is taken from `training_data.csv` (row ID `1.6`).

- **Question:** Where are variables declared in a C++ program?
- **Desired answer:** Variables can be declared anywhere in a program. They can
  be declared inside a function (local variables) or outside the functions
  (global variables).
- **Student answer:** They can be declared right before they are used, but it is
  a good practice to declare them at the beginning of the program and label
  what they are food.
- **Criteria:**
  1. Answer mentions variables can be declared anywhere in program.
  2. Answer mentions local variables can be declared inside functions.
  3. Answer mentions global variables can be declared outside functions.
- **Ground truth:** `[1, 0, 0]`

### Base model

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen35-9b-base",
    "messages": [
      {
        "role": "system",
        "content": "You are a strict grading assistant. Evaluate whether the student answer fulfills each grading criterion independently. Return ONLY a valid JSON array containing 0 or 1, with exactly one value per criterion in the same order. Do not include explanations or markdown."
      },
      {
        "role": "user",
        "content": "Question:\nWhere are variables declared in a C++ program?\n\nDesired answer:\nVariables can be declared anywhere in a program. They can be declared inside a function (local variables) or outside the functions (global variables).\n\nStudent answer:\nThey can be declared right before they are used, but it is a good practice to declare them at the beginning of the program and label what they are food.\n\nCriteria:\n1. Answer mentions variables can be declared anywhere in program\n2. Answer mentions local variables can be declared inside functions\n3. Answer mentions global variables can be declared outside functions"
      }
    ],
    "temperature": 0,
    "max_tokens": 128,
    "chat_template_kwargs": {
      "enable_thinking": false
    }
  }' | python -m json.tool
```

### QLoRA model

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen35-9b-grading-qlora",
    "messages": [
      {
        "role": "system",
        "content": "You are a strict grading assistant. Evaluate whether the student answer fulfills each grading criterion independently. Return ONLY a valid JSON array containing 0 or 1, with exactly one value per criterion in the same order. Do not include explanations or markdown."
      },
      {
        "role": "user",
        "content": "Question:\nWhere are variables declared in a C++ program?\n\nDesired answer:\nVariables can be declared anywhere in a program. They can be declared inside a function (local variables) or outside the functions (global variables).\n\nStudent answer:\nThey can be declared right before they are used, but it is a good practice to declare them at the beginning of the program and label what they are food.\n\nCriteria:\n1. Answer mentions variables can be declared anywhere in program\n2. Answer mentions local variables can be declared inside functions\n3. Answer mentions global variables can be declared outside functions"
      }
    ],
    "temperature": 0,
    "max_tokens": 128,
    "chat_template_kwargs": {
      "enable_thinking": false
    }
  }' | python -m json.tool
```

The generated grading array is returned in `choices[0].message.content`.
