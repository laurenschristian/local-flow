#!/bin/bash

# Download Whisper models for LocalFlow
# Usage: ./download-model.sh [tiny|base|small|medium]

set -e

MODEL=${1:-small}
MODELS_DIR="${HOME}/Library/Application Support/LocalFlow/Models"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

case "$MODEL" in
    tiny)   MODEL_FILE="ggml-tiny.en.bin" ;;
    base)   MODEL_FILE="ggml-base.en.bin" ;;
    small)  MODEL_FILE="ggml-small.en.bin" ;;
    medium) MODEL_FILE="ggml-medium.en.bin" ;;
    *)
        echo "Unknown model: $MODEL"
        echo "Available models: tiny, base, small, medium"
        exit 1
        ;;
esac

MODEL_PATH="$MODELS_DIR/$MODEL_FILE"

# Create models directory
mkdir -p "$MODELS_DIR"

if [[ -f "$MODEL_PATH" ]]; then
    echo "Model already exists: $MODEL_PATH"
    exit 0
fi

echo "Downloading $MODEL model ($MODEL_FILE)..."
echo "This may take a few minutes depending on your connection."
echo ""

curl -L --progress-bar "$BASE_URL/$MODEL_FILE" -o "$MODEL_PATH"

echo ""
echo "Download complete: $MODEL_PATH"
echo ""
echo "Model sizes:"
ls -lh "$MODELS_DIR"
