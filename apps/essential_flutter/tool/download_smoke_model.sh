#!/usr/bin/env bash
set -euo pipefail

mkdir -p "test_models"
curl -L "https://huggingface.co/afrideva/Tinystories-gpt-0.1-3m-GGUF/resolve/22151c5d4c10828fec85cabe05620895d71b689a/tinystories-gpt-0.1-3m.Q2_K.gguf" -o "test_models/tinystories-gpt-0.1-3m.Q2_K.gguf"