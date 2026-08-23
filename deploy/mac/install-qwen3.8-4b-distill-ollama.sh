#!/usr/bin/env bash
# Download empero-ai/Qwen3.8-4B-Distill-GGUF via HF mirror and register in Ollama.
set -euo pipefail

MODEL_REPO="empero-ai/Qwen3.8-4B-Distill-GGUF"
GGUF_FILE="Qwen3.8-4B-Q4_K_M.gguf"
OLLAMA_NAME="qwen3.8-4b-distill"
IMPORT_DIR="${HOME}/.ollama/models/import/qwen3.8-4b-distill"
MODEFILE="${IMPORT_DIR}/Modelfile"

export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

mkdir -p "$IMPORT_DIR"

if [[ ! -f "${IMPORT_DIR}/${GGUF_FILE}" ]]; then
  echo "Downloading ${MODEL_REPO}/${GGUF_FILE} from ${HF_ENDPOINT} ..."
  hf download "$MODEL_REPO" "$GGUF_FILE" --local-dir "$IMPORT_DIR"
else
  echo "GGUF already present: ${IMPORT_DIR}/${GGUF_FILE}"
fi

cat >"$MODEFILE" <<EOF
FROM ${IMPORT_DIR}/${GGUF_FILE}
RENDERER qwen3.5
PARSER qwen3.5
PARAMETER temperature 0.6
PARAMETER top_p 0.95
PARAMETER top_k 20
PARAMETER num_ctx 32768
EOF

echo "Creating Ollama model: ${OLLAMA_NAME}"
ollama create "${OLLAMA_NAME}" -f "$MODEFILE"

echo "Done. Test: ollama run ${OLLAMA_NAME} 'Summarize: user fixed ACP resume bug.'"
