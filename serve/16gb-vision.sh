#!/bin/bash
# 16GB cards with the vision tower: the full 262K plus the mmproj (629 MB), 12,684 MiB for the server on an RTX 5080 16GB.
"${LLAMA_SERVER:-llama-server}" -m "${1:-Ternary-Bonsai-2-27B-PTQ1_0.gguf}" --mmproj "${2:-Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf}" -c 262144 -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20 --host 127.0.0.1 --port 8899
