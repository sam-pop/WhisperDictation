#!/bin/bash
# Download Whisper model from Hugging Face
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$PROJECT_DIR/Models"
MODEL_NAME="${1:-small.en}"
MODEL_FILE="ggml-${MODEL_NAME}.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"

mkdir -p "$MODELS_DIR"

if [ -f "$MODELS_DIR/$MODEL_FILE" ]; then
    echo "Model already exists: $MODELS_DIR/$MODEL_FILE"
    exit 0
fi

echo "==> Downloading $MODEL_FILE..."
echo "    URL: $MODEL_URL"
echo "    Destination: $MODELS_DIR/$MODEL_FILE"
echo ""

curl -L --progress-bar -o "$MODELS_DIR/$MODEL_FILE" "$MODEL_URL"

SIZE=$(ls -lh "$MODELS_DIR/$MODEL_FILE" | awk '{print $5}')
echo ""
echo "==> Downloaded $MODEL_FILE ($SIZE)"
