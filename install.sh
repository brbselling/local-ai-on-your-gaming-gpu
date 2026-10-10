#!/usr/bin/env bash
# Bonsai 2 27B on Linux or WSL2, one line:
#   curl -fsSL https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-rtx/main/install.sh | bash
# It finds your NVIDIA card, picks the prebuilt bundle and the model file for its VRAM, downloads them
# from Hugging Face, checks every SHA256, writes start-bonsai.sh next to them and starts it.
# Optional: BONSAI_DIR (default ~/models/bonsai2-27b), BONSAI_PORT (default 8899), BONSAI_NO_START=1.
set -euo pipefail

main() {
  local dir="${BONSAI_DIR:-$HOME/models/bonsai2-27b}" port="${BONSAI_PORT:-8899}"
  local hf=https://huggingface.co/sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF/resolve/main
  local prism=https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main
  local mmproj=Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf
  local mmproj_sha=6807ede61d570bb86ba34b756a0fa109edc33668604de867c6ea6d8f1d631903
  local test="${BONSAI_TEST:-}"

  echo
  echo "Bonsai 2 27B for small GPUs, Linux installer"
  echo "github.com/sudoingX/local-ai-on-your-gaming-rtx"
  echo

  # 1. the card (the one with the most VRAM if there are several)
  local rows
  if [ -n "${BONSAI_FAKE_GPU:-}" ]; then rows="$BONSAI_FAKE_GPU"
  else
    command -v nvidia-smi >/dev/null || { echo "No NVIDIA driver found (nvidia-smi is missing). Install the driver, then run this again."; return 1; }
    rows=$(nvidia-smi --query-gpu=index,name,memory.total,driver_version,compute_cap --format=csv,noheader,nounits)
  fi
  local idx name mib driver cc
  IFS=',' read -r idx name mib driver cc <<< "$(sort -t, -k3 -n -r <<< "$rows" | head -1)"
  idx=$(echo $idx); name=$(echo $name); mib=$(echo $mib); driver=$(echo $driver); cc=$(echo $cc)
  echo "Card:   $name, $mib MiB, driver $driver"

  # 2. the bundle for this card
  local bundle min_driver cards min_glibc
  if awk -v c="$cc" 'BEGIN { exit !(c >= 12.0) }'; then
    bundle=bonsai2-small-gpu-linux-x64-cuda12.8-sm120-ff41412; min_driver=570; cards="RTX 50"; min_glibc=2.38
  elif awk -v c="$cc" 'BEGIN { exit !(c >= 8.6 && c < 9.0) }'; then
    bundle=bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d; min_driver=525; cards="RTX 30 and 40"; min_glibc=2.35
  else
    echo "This card (compute $cc) is not in the prebuilt bundles yet, they cover RTX 30, 40 and 50."
    echo "Older cards can build the bonsai2 branch of github.com/sudoingX/llama.cpp from source."
    return 1
  fi
  if [ "${driver%%.*}" -lt "$min_driver" ]; then
    echo "Driver $driver is too old for the $cards bundle. Update to $min_driver or newer, then run this again."
    return 1
  fi
  local glibc; glibc=$(ldd --version 2>/dev/null | head -1 | grep -o -E '[0-9]+\.[0-9]+$' || true)
  if [ -n "$glibc" ] && [ -z "$test" ] && awk -v g="$glibc" -v m="$min_glibc" 'BEGIN { exit !(g < m) }'; then
    echo "The $cards bundle needs glibc $min_glibc or newer (Ubuntu $([ "$min_glibc" = 2.38 ] && echo 24.04 || echo 22.04) or newer), this system has $glibc."
    echo "Upgrade, or build the bonsai2 branch of github.com/sudoingX/llama.cpp from source (see the README)."
    return 1
  fi

  # 3. the model file for this much VRAM
  local tier model vision nmax
  if   [ "$mib" -ge 15000 ]; then tier=16gb; model=Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf;      vision=1; nmax=1
  elif [ "$mib" -ge 11500 ]; then tier=12gb; model=Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf;      vision=0; nmax=1
  elif [ "$mib" -ge 7500 ];  then tier=8gb;  model=Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf; vision=0; nmax=2
  else echo "Bonsai 2 27B needs a card with 8 GB or more, this one has $mib MiB."; return 1
  fi
  echo "Bundle: $bundle ($cards)"
  echo "Model:  $model, $tier tier$([ "$vision" = 1 ] && echo ', with vision')"
  echo "Folder: $dir"
  echo

  mkdir -p "$dir"
  if [ -z "$test" ]; then
    local skip_model="${BONSAI_SKIP_MODEL:-}" need_gb=10   # BONSAI_SKIP_MODEL: CI only, the real bundle download without the model
    [ -n "$skip_model" ] && need_gb=2
    local free_kb; free_kb=$(df -Pk "$dir" | awk 'NR == 2 { print $4 }')
    if [ "$free_kb" -lt $((need_gb * 1024 * 1024)) ]; then echo "Not enough disk space in $dir: about $need_gb GB is needed."; return 1; fi

    # 4. downloads, every file checked against its SHA256
    local sums; sums=$(curl -fsSL "$hf/SHA256SUMS")
    want() { awk -v f="$1" '$2 == f || $2 == "*" f { print $1 }' <<< "$sums"; }
    get() { # url file sha
      local url=$1 path=$2 sha=$3 leaf; leaf=$(basename "$2")
      if [ -f "$path" ] && [ "$(sha256sum "$path" | cut -d' ' -f1)" = "$sha" ]; then echo "  ok    $leaf (already here)"; return; fi
      echo "  get   $leaf"
      curl -fL --retry 5 --retry-delay 3 -C - -o "$path.part" "$url"
      if [ "$(sha256sum "$path.part" | cut -d' ' -f1)" != "$sha" ]; then rm -f "$path.part"; echo "checksum mismatch for $leaf, run the installer again"; return 1; fi
      mv "$path.part" "$path"; echo "  ok    $leaf (sha256 checked)"
    }
    [ -n "$(want "$bundle.tar.gz")" ] && [ -n "$(want "$model")" ] || { echo "SHA256SUMS on Hugging Face is missing a file this needs"; return 1; }
    echo "Downloading from Hugging Face (about 8 GB the first time, it resumes if it stops):"
    if [ ! -x "$dir/$bundle/bin/llama-server" ]; then
      get "$hf/$bundle.tar.gz" "$dir/$bundle.tar.gz" "$(want "$bundle.tar.gz")"
      echo "  unpack $bundle.tar.gz"; tar xzf "$dir/$bundle.tar.gz" -C "$dir" && rm -f "$dir/$bundle.tar.gz"
    else
      echo "  ok    $bundle (already unpacked)"
    fi
    if [ -z "$skip_model" ]; then
      get "$hf/$model" "$dir/$model" "$(want "$model")"
      if [ "$vision" = 1 ]; then get "$prism/$mmproj" "$dir/$mmproj" "$mmproj_sha"; fi
    fi
  fi

  # 5. the start script: --fit sizes the window to free VRAM, 8 GB cards get a window picked from free VRAM
  local ctx_line='CTX_ARGS=(--fit on --fit-target 1024 --fit-ctx 16384)'
  if [ "$tier" = 8gb ]; then
    ctx_line='FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i "$CUDA_VISIBLE_DEVICES" | head -1)
# lean file with the head: about 7,150 MiB at 16K and 7,900 MiB at 64K (sweeps/rtx3000Ada-8gb.md)
if [ "$FREE" -ge 7950 ]; then C=65536; elif [ "$FREE" -ge 7700 ]; then C=49152; elif [ "$FREE" -ge 7450 ]; then C=32768; else C=16384; fi
CTX_ARGS=(-c "$C" --fit off)'
  fi
  local mm_arg=''
  [ "$vision" = 1 ] && mm_arg="--mmproj \"\$DIR/$mmproj\""
  cat > "$dir/start-bonsai.sh" <<EOF
#!/bin/bash
# Bonsai 2 27B, written by install.sh for $name ($mib MiB), $tier tier. Chat page: http://127.0.0.1:\${BONSAI_PORT:-$port}
set -eu
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
B="\$DIR/$bundle"
export LD_LIBRARY_PATH="\$B/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=$idx GGML_CUDA_BATCH_INVARIANT=1
PORT="\${BONSAI_PORT:-$port}"
# 127.0.0.1 = this machine only; BONSAI_HOST=0.0.0.0 opens it to your network, set BONSAI_API_KEY with it
HOST="\${BONSAI_HOST:-127.0.0.1}"
KEY_ARGS=(); [ -n "\${BONSAI_API_KEY:-}" ] && KEY_ARGS=(--api-key "\$BONSAI_API_KEY")
$ctx_line
echo "Chat page: http://127.0.0.1:\$PORT   API for agents: http://127.0.0.1:\$PORT/v1 (OpenAI compatible, model bonsai-2-27b)"
exec "\$B/bin/llama-server" -m "\$DIR/$model" $mm_arg -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --alias bonsai-2-27b \\
  --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20 --host "\$HOST" --port "\$PORT" \\
  "\${CTX_ARGS[@]}" \${KEY_ARGS[@]+"\${KEY_ARGS[@]}"} --spec-type draft-mtp --spec-draft-n-max $nmax "\$@"
EOF
  chmod +x "$dir/start-bonsai.sh"

  echo
  echo "Installed."
  echo "Start it:       $dir/start-bonsai.sh"
  echo "Chat page:      http://127.0.0.1:$port"
  echo "API for agents: http://127.0.0.1:$port/v1 (OpenAI compatible, model bonsai-2-27b, any API key)"
  if [ -z "$test" ] && [ -z "${BONSAI_NO_START:-}" ]; then
    echo; echo "Starting it now, Ctrl+C stops it."; echo
    exec "$dir/start-bonsai.sh"
  fi
}

main "$@"
