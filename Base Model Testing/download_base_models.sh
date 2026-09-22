#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
MAX_WORKERS="${HF_DOWNLOAD_WORKERS:-1}"
MAX_RETRIES="${HF_DOWNLOAD_RETRIES:-3}"
CLEAN_INCOMPLETE=0
SELECTED_MODELS=()

usage() {
    cat <<'EOF'
Interactively download models used by Run Base Models.ipynb into the Hugging
Face cache.

Usage:
  ./download_base_models.sh [options]

Options:
  --env PATH             Read HF_TOKEN from this file instead of ./.env.
  --retries NUMBER       Attempts per model (default: 3).
  -h, --help             Show this help message.

The script prompts for:
  - HF_TOKEN when it cannot read one from the environment file
  - workers per model
  - models to download (individual choices or all)
  - whether to clean incomplete files for the selected models
EOF
}

while (($# > 0)); do
    case "$1" in
        --env)
            [[ $# -ge 2 ]] || { echo "ERROR: --env requires a path." >&2; exit 2; }
            ENV_FILE="$2"
            shift 2
            ;;
        --retries)
            [[ $# -ge 2 ]] || { echo "ERROR: --retries requires a number." >&2; exit 2; }
            MAX_RETRIES="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ "$MAX_RETRIES" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERROR: retries must be a positive integer." >&2
    exit 2
}

read_env_value() {
    local path="$1"
    local requested_key="$2"
    local line name value

    [[ -f "$path" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *"="* ]] && continue

        line="${line#export }"
        name="${line%%=*}"
        value="${line#*=}"
        name="${name%"${name##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        [[ "$name" == "$requested_key" ]] || continue

        if [[ ${#value} -ge 2 ]]; then
            if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
                value="${value:1:${#value}-2}"
            elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
                value="${value:1:${#value}-2}"
            fi
        fi

        printf '%s' "$value"
        return 0
    done < "$path"

    return 1
}

TOKEN_SOURCE="environment"
if [[ -z "${HF_TOKEN:-}" ]]; then
    HF_TOKEN="$(read_env_value "$ENV_FILE" HF_TOKEN || true)"
    TOKEN_SOURCE="$ENV_FILE"
fi

if [[ -z "$HF_TOKEN" ]]; then
    if [[ -f "$ENV_FILE" ]]; then
        echo "HF_TOKEN is missing or empty in $ENV_FILE."
    else
        echo "Environment file not found: $ENV_FILE"
    fi

    if ! read -r -s -p "Enter your Hugging Face token: " HF_TOKEN; then
        echo >&2
        echo "ERROR: unable to read HF_TOKEN." >&2
        exit 1
    fi
    echo

    if [[ -z "$HF_TOKEN" ]]; then
        echo "ERROR: HF_TOKEN cannot be empty." >&2
        exit 1
    fi

    TOKEN_SOURCE="secure terminal prompt"
fi
export HF_TOKEN

if ! command -v hf >/dev/null 2>&1; then
    echo "ERROR: the 'hf' command is unavailable." >&2
    echo "Activate the lora environment or install huggingface_hub first." >&2
    exit 1
fi

# Disable the Xet downloader that left multiple large temporary files during
# the stalled Qwen3.5-27B attempts. Standard HTTP downloads resume reliably.
export HF_HUB_DISABLE_XET=1
export HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-1800}"
export HF_HUB_ETAG_TIMEOUT="${HF_HUB_ETAG_TIMEOUT:-60}"

MODELS=(
    "Qwen/Qwen3.5-4B"
    "Qwen/Qwen3.5-9B"
    # "Qwen/Qwen3.5-27B"
    # "Qwen/Qwen3.8-27B"
    "google/gemma-4-12B-it"
    # "google/gemma-4-26B-A4B-it"
    "ibm-granite/granite-4.2-8b"
    "ornith-ai/Ornith-1.5-9B"
)

prompt_workers() {
    local answer

    while true; do
        if ! read -r -p "Workers per model [$MAX_WORKERS]: " answer; then
            echo >&2
            echo "ERROR: unable to read the worker count." >&2
            exit 1
        fi

        answer="${answer:-$MAX_WORKERS}"
        if [[ "$answer" =~ ^[1-9][0-9]*$ ]]; then
            MAX_WORKERS="$answer"
            return
        fi

        echo "Please enter a positive integer."
    done
}

prompt_models() {
    local answer item index
    local -A seen=()

    while true; do
        echo
        echo "Select models to download:"
        for index in "${!MODELS[@]}"; do
            printf '  [ ] %d) %s\n' "$((index + 1))" "${MODELS[$index]}"
        done
        echo "  [ ] A) All models"
        echo "Select multiple models with spaces or commas, for example: 1 3 5 or 1,3,5"

        if ! read -r -p "Enter model numbers [A]: " answer; then
            echo >&2
            echo "ERROR: unable to read the model selection." >&2
            exit 1
        fi

        if [[ -z "$answer" || "${answer,,}" == "a" || "${answer,,}" == "all" ]]; then
            SELECTED_MODELS=("${MODELS[@]}")
            break
        fi

        answer="${answer//,/ }"
        SELECTED_MODELS=()
        seen=()

        for item in $answer; do
            if [[ ! "$item" =~ ^[0-9]+$ ]]; then
                echo "Invalid choice: $item"
                SELECTED_MODELS=()
                break
            fi

            index=$((10#$item - 1))
            if ((index < 0 || index >= ${#MODELS[@]})); then
                echo "Choice out of range: $item"
                SELECTED_MODELS=()
                break
            fi

            if [[ -z "${seen[$index]+x}" ]]; then
                SELECTED_MODELS+=("${MODELS[$index]}")
                seen[$index]=1
            fi
        done

        if ((${#SELECTED_MODELS[@]} > 0)); then
            break
        fi

        echo "Please select one or more listed model numbers, or A for all."
    done

    echo
    echo "Download checklist:"
    for item in "${MODELS[@]}"; do
        local marker=" "
        for index in "${!SELECTED_MODELS[@]}"; do
            if [[ "${SELECTED_MODELS[$index]}" == "$item" ]]; then
                marker="x"
                break
            fi
        done
        printf '  [%s] %s\n' "$marker" "$item"
    done
}

prompt_cleanup() {
    local answer

    while true; do
        if ! read -r -p "Clean incomplete files and stale locks for selected models? [y/N]: " answer; then
            echo >&2
            echo "ERROR: unable to read the cleanup choice." >&2
            exit 1
        fi

        case "${answer,,}" in
            y|yes)
                CLEAN_INCOMPLETE=1
                return
                ;;
            ""|n|no)
                CLEAN_INCOMPLETE=0
                return
                ;;
            *)
                echo "Please enter y or n."
                ;;
        esac
    done
}

prompt_workers
prompt_models
prompt_cleanup

if [[ -n "${HF_HUB_CACHE:-}" ]]; then
    CACHE_ROOT="$HF_HUB_CACHE"
elif [[ -n "${HF_HOME:-}" ]]; then
    CACHE_ROOT="${HF_HOME}/hub"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    CACHE_ROOT="${XDG_CACHE_HOME}/huggingface/hub"
else
    CACHE_ROOT="${HOME:?HOME is not set}/.cache/huggingface/hub"
fi

cleanup_incomplete_for_model() {
    local model_id="$1"
    local cache_name="models--${model_id//\//--}"
    local model_cache="${CACHE_ROOT}/${cache_name}"
    local lock_cache="${CACHE_ROOT}/.locks/${cache_name}"
    local -a incomplete_files=()
    local -a lock_files=()

    # Refuse to operate unless the resolved names remain under the exact cache
    # locations constructed from the fixed model list above.
    [[ "$model_cache" == "${CACHE_ROOT}/models--"* ]] || {
        echo "ERROR: unsafe model cache path: $model_cache" >&2
        exit 1
    }
    [[ "$lock_cache" == "${CACHE_ROOT}/.locks/models--"* ]] || {
        echo "ERROR: unsafe lock cache path: $lock_cache" >&2
        exit 1
    }

    if [[ -d "${model_cache}/blobs" ]]; then
        mapfile -d '' incomplete_files < <(
            find "${model_cache}/blobs" -maxdepth 1 -type f -name '*.incomplete' -print0
        )
    fi
    if [[ -d "$lock_cache" ]]; then
        mapfile -d '' lock_files < <(
            find "$lock_cache" -maxdepth 1 -type f -name '*.lock' -print0
        )
    fi

    if ((${#incomplete_files[@]} > 0)); then
        echo "Removing ${#incomplete_files[@]} incomplete file(s) for $model_id"
        rm -f -- "${incomplete_files[@]}"
    fi
    if ((${#lock_files[@]} > 0)); then
        echo "Removing ${#lock_files[@]} stale lock(s) for $model_id"
        rm -f -- "${lock_files[@]}"
    fi
}

if ((CLEAN_INCOMPLETE)); then
    echo "Cleaning incomplete downloads for the selected models only."
    for model_id in "${SELECTED_MODELS[@]}"; do
        cleanup_incomplete_for_model "$model_id"
    done
fi

echo "HF token source: $TOKEN_SOURCE"
echo "Hugging Face cache: $CACHE_ROOT"
echo "Xet disabled: $HF_HUB_DISABLE_XET"
echo "Workers per model: $MAX_WORKERS"
echo "The token value will not be printed or placed in command arguments."

declare -a FAILED_MODELS=()

for model_id in "${SELECTED_MODELS[@]}"; do
    echo
    echo "============================================================"
    echo "Downloading: $model_id"
    echo "============================================================"

    downloaded=0
    for ((attempt = 1; attempt <= MAX_RETRIES; attempt++)); do
        echo "Attempt $attempt/$MAX_RETRIES"
        if hf download "$model_id" --max-workers "$MAX_WORKERS" --format human; then
            downloaded=1
            echo "Completed: $model_id"
            break
        fi

        echo "Attempt $attempt failed for $model_id" >&2
        if ((attempt < MAX_RETRIES)); then
            delay=$((attempt * 15))
            echo "Retrying in ${delay}s; existing HTTP partial files will be resumed."
            sleep "$delay"
        fi
    done

    if ((downloaded == 0)); then
        FAILED_MODELS+=("$model_id")
    fi
done

echo
if ((${#FAILED_MODELS[@]} > 0)); then
    echo "The following models failed after $MAX_RETRIES attempts:" >&2
    printf '  - %s\n' "${FAILED_MODELS[@]}" >&2
    exit 1
fi

echo "All selected base models are available in the Hugging Face cache."
echo ".ipynb notebooks will reuse them without downloading again."
