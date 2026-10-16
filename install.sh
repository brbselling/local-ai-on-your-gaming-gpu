#!/usr/bin/env bash
# Bonsai 2 27B on Linux or WSL2, one line:
#   curl -fsSL https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/main/install.sh | bash
# It finds your NVIDIA card, picks the prebuilt bundle and the model file for its VRAM, downloads them
# from Hugging Face, checks every SHA256, writes start-bonsai.sh next to them and starts it.
# AMD Radeon (beta): with no NVIDIA card it looks for a Radeon and takes PrismML's Vulkan build instead.
# Optional: BONSAI_DIR (default ~/models/bonsai2-27b), BONSAI_PORT (default 8899), BONSAI_NO_START=1.
#
# Two builds, one script. The default is Bonsai 2 27B, the standard build. `--model offrail` (or
# BONSAI_MODEL=offrail) installs Offrail 27B instead: the uncensored build, the same stack with
# OS-Software's Heretic weights (answers what the base refuses). With a terminal the installer asks once;
# `curl | bash` has no terminal, so it takes the default and never blocks. BONSAI_NO_PROMPT=1 skips the question.
set -euo pipefail

main() {
  local dir="${BONSAI_DIR:-$HOME/models/bonsai2-27b}" port="${BONSAI_PORT:-8899}"
  # BONSAI_HF (tests only): another base for the bundles, the MTP files and SHA256SUMS, e.g. a bundle not uploaded yet
  local hf=${BONSAI_HF:-https://huggingface.co/sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF/resolve/main}
  local prism=https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main
  local mmproj=Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf
  local mmproj_sha=6807ede61d570bb86ba34b756a0fa109edc33668604de867c6ea6d8f1d631903
  local test="${BONSAI_TEST:-}"

  # ---- which build: base (default) or offrail ----
  # --model base|offrail, BONSAI_MODEL=..., or one question when there is a terminal (/dev/tty, because a
  # piped script owns stdin). No terminal = base. BONSAI_OFFRAIL_HF is the test hook for the second repo.
  variant="${BONSAI_MODEL:-}"; local variant_set=0 arg j=0
  if [ -n "${BONSAI_MODEL:-}" ]; then variant_set=1; fi
  local -a argv=("$@")
  while [ "$j" -lt "${#argv[@]}" ]; do
    arg="${argv[$j]}"
    case "$arg" in
      --model)   j=$((j + 1)); variant="${argv[$j]:-}"; variant_set=1 ;;
      --model=*) variant="${arg#*=}"; variant_set=1 ;;
    esac
    j=$((j + 1))
  done
  case "$variant" in
    ''|base|bonsai|normal)  variant=base ;;
    offrail|uncensored)     variant=offrail ;;
    *) echo "--model takes base or offrail, not '$variant'."; return 1 ;;
  esac
  # -r /dev/tty is true even with no terminal attached (ssh without -t, docker, cron, CI), so try to open it
  if [ "$variant_set" = 0 ] && [ -z "${BONSAI_NO_PROMPT:-}" ] && [ -z "$test" ] && (: < /dev/tty) 2>/dev/null; then
    echo
    echo "Which model?"
    echo "  1) Bonsai 2 27B   the standard build (default)"
    echo "  2) Offrail 27B    the uncensored build, answers what the base refuses"
    printf "Choice [1]: "
    local answer=''; read -r answer < /dev/tty || answer=''
    case "$answer" in 2|offrail|uncensored|o|O) variant=offrail ;; *) variant=base ;; esac
    echo
  fi
  # globals on purpose: radeon() has its own scope and needs the same picks
  model_hf="$hf"; vname='Bonsai 2 27B'
  api_alias=bonsai-2-27b; slug=bonsai2
  if [ "$variant" = offrail ]; then
    model_hf=${BONSAI_OFFRAIL_HF:-https://huggingface.co/sudoingx/Offrail-27B-Uncensored/resolve/main}
    vname='Offrail 27B'; api_alias=offrail-27b; slug=offrail
  fi

  echo
  echo "$vname for small GPUs, Linux installer"
  echo "github.com/sudoingX/local-ai-on-your-gaming-gpu"
  echo

  # 1. the card (the one with the most VRAM if there are several)
  local rows
  if [ -n "${BONSAI_FAKE_GPU:-}" ]; then rows="$BONSAI_FAKE_GPU"
  else
    rows=''
    if command -v nvidia-smi >/dev/null; then rows=$(nvidia-smi --query-gpu=index,name,memory.total,driver_version,compute_cap --format=csv,noheader,nounits) || rows=''; fi
    if [ -z "$rows" ]; then
      # no NVIDIA card answers: an AMD Radeon (beta)?
      if [ -n "$(radeon_cards)" ]; then radeon; return; fi
      command -v nvidia-smi >/dev/null && { echo "nvidia-smi is here but reads no NVIDIA card (run nvidia-smi to see why). Fix the driver, then run this again."; return 1; }
      echo "No NVIDIA driver found (nvidia-smi is missing). Install the driver, then run this again."; return 1
    fi
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
  elif awk -v c="$cc" 'BEGIN { exit !(c >= 7.5 && c < 8.0) }'; then
    # Turing (RTX 20, the GTX 16 cards stop at the VRAM check below): the same v1.1 code built for sm_75
    bundle=bonsai2-small-gpu-linux-x64-cuda12.4-sm75-ff41412; min_driver=525; cards="RTX 20"; min_glibc=2.35
  else
    echo "This card (compute $cc) is not in the prebuilt bundles yet, they cover RTX 20, 30, 40 and 50."
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
  if [ "$variant" = offrail ]; then
    # Offrail: the same shapes as the base (its two files are the base's sizes: 7,012,820,544 and 6,297,658,848)
    if   [ "$mib" -ge 15000 ]; then tier=16gb; model=Offrail-27B-12G.gguf; vision=1; nmax=1
    elif [ "$mib" -ge 11500 ]; then tier=12gb; model=Offrail-27B-12G.gguf; vision=0; nmax=1
    elif [ "$mib" -ge 7500 ];  then tier=8gb;  model=Offrail-27B-8G.gguf;  vision=0; nmax=2
    else echo "$vname needs a card with 8 GB or more, this one has $mib MiB."; return 1
    fi
  elif [ "$mib" -ge 15000 ]; then tier=16gb; model=Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf;      vision=1; nmax=1
  elif [ "$mib" -ge 11500 ]; then tier=12gb; model=Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf;      vision=0; nmax=1
  elif [ "$mib" -ge 7500 ];  then tier=8gb;  model=Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf; vision=0; nmax=2
  else echo "$vname needs a card with 8 GB or more, this one has $mib MiB."; return 1
  fi
  # RTX 20: the head drafts 1 token on every tier. On an RTX 2070 Super n-max 1 decoded within 5% of n-max 2 and its server is
  # 150 MiB smaller, which buys the 48K window on an 8 GB card
  [ "$cards" = "RTX 20" ] && nmax=1
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

    # 4. downloads, every file checked against its SHA256. The bundles and the base build's weights come from
    # the base repo; Offrail ships its own SHA256SUMS in its own repo, so both manifests are searched.
    local sums ms; sums=$(curl -fsSL "$hf/SHA256SUMS")
    ms=''
    if [ "$variant" = offrail ]; then
      ms=$(curl -fsSL "$model_hf/SHA256SUMS") || { echo "could not read SHA256SUMS from the Offrail repo"; return 1; }
    fi
    # head -1: if a name ever appeared in both manifests, take one hash, not two lines
    want() { awk -v f="$1" '$2 == f || $2 == "*" f { print $1 }' <<< "$sums
$ms" | head -1; }
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
      get "$model_hf/$model" "$dir/$model" "$(want "$model")"
      if [ "$vision" = 1 ]; then get "$prism/$mmproj" "$dir/$mmproj" "$mmproj_sha"; fi
    fi
    # the chart the speed check's vision step reads (16 GB), from this repo
    if [ "$vision" = 1 ] && ! curl -fsSL -o "$dir/vision_check.png" \
        "https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/${BONSAI_REF:-main}/prompts/vision_check.png"; then
      rm -f "$dir/vision_check.png"; echo "  (no vision_check.png this time, the speed check skips its vision step)"
    fi
  fi

  # 5. the start script: --fit sizes the window to free VRAM, 8 GB cards get a window picked from free VRAM
  local ctx_line='CTX_ARGS=(--fit on --fit-target 1024 --fit-ctx 16384)'
  if [ "$tier" = 8gb ] && [ "$cards" = "RTX 20" ]; then
    ctx_line='FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i "$CUDA_VISIBLE_DEVICES" | head -1)
# RTX 20, lean file, head n-max 1, ubatch 256: the server peaks at 6,720 MiB at 16K, 7,155 at 32K and 7,587 at 48K after a
# 12,842-token prompt on an RTX 2070 Super (sweeps/rtx2070super-8gb.md), 64K does not load on 8 GB; each step = peak + 50
if [ "$FREE" -ge 7650 ]; then C=49152; elif [ "$FREE" -ge 7250 ]; then C=32768; else C=16384; fi
[ "$FREE" -ge 6800 ] || echo "Only $FREE MiB free on the card, the smallest window needs about 6,800 MiB: close games and video apps first."
CTX_ARGS=(-c "$C" --fit off -ub 256)'
  elif [ "$tier" = 8gb ]; then
    ctx_line='FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i "$CUDA_VISIBLE_DEVICES" | head -1)
# lean file with the head: about 7,150 MiB at 16K and 7,900 MiB at 64K (sweeps/rtx3000Ada-8gb.md)
if [ "$FREE" -ge 7950 ]; then C=65536; elif [ "$FREE" -ge 7700 ]; then C=49152; elif [ "$FREE" -ge 7450 ]; then C=32768; else C=16384; fi
CTX_ARGS=(-c "$C" --fit off)'
  fi
  local mm_arg=''
  [ "$vision" = 1 ] && mm_arg="--mmproj \"\$DIR/$mmproj\""
  cat > "$dir/start-bonsai.sh" <<EOF
#!/bin/bash
# $vname, written by install.sh for $name ($mib MiB), $tier tier. Chat page: http://127.0.0.1:\${BONSAI_PORT:-$port}
set -eu
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
B="\$DIR/$bundle"
export LD_LIBRARY_PATH="\$B/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=$idx GGML_CUDA_BATCH_INVARIANT=1
PORT="\${BONSAI_PORT:-$port}"
# 127.0.0.1 = this machine only; BONSAI_HOST=0.0.0.0 opens it to your network, set BONSAI_API_KEY with it
HOST="\${BONSAI_HOST:-127.0.0.1}"
KEY_ARGS=(); [ -n "\${BONSAI_API_KEY:-}" ] && KEY_ARGS=(--api-key "\$BONSAI_API_KEY")
$ctx_line
# the speed head drafts $nmax tokens; BONSAI_HEAD=off runs without it (the speed check uses that for its second pass)
HEAD_ARGS=(--spec-type draft-mtp --spec-draft-n-max $nmax); [ "\${BONSAI_HEAD:-on}" = off ] && HEAD_ARGS=()
echo "NVIDIA: GPU \$CUDA_VISIBLE_DEVICES, \$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i "\$CUDA_VISIBLE_DEVICES" 2>/dev/null | head -1) MiB free"
echo "Chat page: http://127.0.0.1:\$PORT   API for agents: http://127.0.0.1:\$PORT/v1 (OpenAI compatible, model $api_alias)"
exec "\$B/bin/llama-server" -m "\$DIR/$model" $mm_arg -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --alias $api_alias \\
  --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20 --host "\$HOST" --port "\$PORT" \\
  "\${CTX_ARGS[@]}" \${KEY_ARGS[@]+"\${KEY_ARGS[@]}"} \${HEAD_ARGS[@]+"\${HEAD_ARGS[@]}"} "\$@"
EOF
  chmod +x "$dir/start-bonsai.sh"
  speed_check nvidia > "$dir/bench-bonsai.sh"
  chmod +x "$dir/bench-bonsai.sh"

  echo
  echo "Installed."
  echo "Start it:         $dir/start-bonsai.sh"
  echo "Check your speed: $dir/bench-bonsai.sh, it saves your results and prints a short line to share"
  echo "Chat page:        http://127.0.0.1:$port"
  echo "API for agents:   http://127.0.0.1:$port/v1 (OpenAI compatible, model $api_alias, any API key)"
  if [ -z "$test" ] && [ -z "${BONSAI_NO_START:-}" ]; then
    echo; echo "Starting it now, Ctrl+C stops it."; echo
    exec "$dir/start-bonsai.sh"
  fi
}

# AMD cards in /sys/class/drm (vendor 0x1002), one line each: <card dir> <VRAM MiB> <GTT MiB>
radeon_cards() {
  local c v g
  for c in "${BONSAI_DRM:-/sys/class/drm}"/card*; do
    case "${c##*/}" in *-*) continue ;; esac
    [ "$(cat "$c/device/vendor" 2>/dev/null)" = 0x1002 ] || continue
    v=$(cat "$c/device/mem_info_vram_total" 2>/dev/null || echo 0)
    g=$(cat "$c/device/mem_info_gtt_total" 2>/dev/null || echo 0)
    echo "$c $((v / 1048576)) $((g / 1048576))"
  done
}

# the marketing name: the driver's own, then libdrm's table (the one RADV reads), then lspci, then the PCI id
radeon_name() {
  local d=$1 n id rev
  n=$(cat "$d/product_name" 2>/dev/null || true)
  id=$(sed 's/^0x//' "$d/device" 2>/dev/null | tr a-f A-F || true)
  rev=$(sed 's/^0x//' "$d/revision" 2>/dev/null | tr a-f A-F || true)
  [ -n "$n" ] || n=$(awk -v id="$id" -v rev="$rev" -F',' '$1 == id { r = $2; gsub(/[ \t]/, "", r); if (r == rev) { sub(/^[^,]*,[^,]*,[ \t]*/, ""); print; exit } }' \
    /usr/share/libdrm/amdgpu.ids 2>/dev/null || true)
  [ -n "$n" ] || n=$(lspci -mm -s "$(basename "$(readlink -f "$d")")" 2>/dev/null | awk -F'"' '{ print $6 }' || true)
  [ -n "$n" ] || n="Radeon${id:+ (PCI device 0x$id)}"
  case "$n" in AMD*) echo "$n" ;; *) echo "AMD $n" ;; esac
}

# Vulkan for a Radeon: the loader (libvulkan.so.1) and Mesa's RADV driver
vulkan_ok() {
  local icd="${BONSAI_VK_ICD_DIR:-/usr/share/vulkan/icd.d}" libs f
  ls "$icd"/radeon_icd*.json >/dev/null 2>&1 || return 1
  libs=$(ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null || true)
  case "$libs" in *libvulkan.so.1*) return 0 ;; esac
  for f in /usr/lib/x86_64-linux-gnu/libvulkan.so.1 /usr/lib64/libvulkan.so.1 /usr/lib/libvulkan.so.1; do [ -e "$f" ] && return 0; done
  return 1
}

# AMD Radeon (beta): PrismML's own Linux Vulkan build of the same fork, pinned and checked against its SHA256, with the same
# model files and tiers. The card with the most VRAM wins; an APU (a small carve-out and a big shared GTT, like Strix Halo)
# counts as a 16 GB card. Uses main's dir, port, hf, prism, mmproj, mmproj_sha and test.
radeon() {
  local build=llama-prism-b10772-e8fd209-bin-ubuntu-vulkan-x64
  local build_url=https://github.com/PrismML-Eng/llama.cpp/releases/download/prism-b10772-e8fd209/llama-prism-b10772-e8fd209-bin-ubuntu-vulkan-x64.tar.gz
  local build_sha=bf0849e2ad6ca39aed5338ab6072ea10f83c9ab28e30e1f34b553b87550af16e
  local card mib gtt name apu=0
  read -r card mib gtt <<< "$(radeon_cards | awk 'NR == 1 || $2 > m { m = $2; l = $0 } END { print l }')"
  name=$(radeon_name "$card/device")
  if [ "$mib" -lt 2048 ] && [ "$gtt" -gt 16384 ]; then apu=1; fi
  if [ "$apu" = 1 ]; then echo "Card:   $name, an APU: $mib MiB of its own and $gtt MiB shared (GTT), AMD Radeon beta"
  else echo "Card:   $name, $mib MiB, AMD Radeon beta"; fi

  # 2. Vulkan and the build
  if ! vulkan_ok; then
    echo "This Radeon runs on Vulkan, and Vulkan is missing (the loader or Mesa's RADV driver). On Ubuntu or Debian:"
    echo "  sudo apt install mesa-vulkan-drivers libvulkan1"
    echo "then run this again."
    return 1
  fi
  local glibc; glibc=$(ldd --version 2>/dev/null | head -1 | grep -o -E '[0-9]+\.[0-9]+$' || true)
  if [ -n "$glibc" ] && [ -z "$test" ] && awk -v g="$glibc" 'BEGIN { exit !(g < 2.34) }'; then
    echo "The Vulkan build needs glibc 2.34 or newer (Ubuntu 22.04 or newer), this system has $glibc."
    return 1
  fi

  # 3. the model file: the same tiers as NVIDIA; on Vulkan the head drafts 2 tokens on every tier (n-max 2 decoded 15 to 16%
  # faster than n-max 1 with both files on the Radeon 8060S), and the 8 GB windows were measured on Vulkan
  local tier model vision nmax
  if [ "$variant" = offrail ]; then
    if   [ "$apu" = 1 ] || [ "$mib" -ge 15000 ]; then tier=16gb; model=Offrail-27B-12G.gguf; vision=1; nmax=2
    elif [ "$mib" -ge 11500 ]; then tier=12gb; model=Offrail-27B-12G.gguf; vision=0; nmax=2
    elif [ "$mib" -ge 7500 ];  then tier=8gb;  model=Offrail-27B-8G.gguf;  vision=0; nmax=2
    else echo "$vname needs a card with 8 GB or more, this one has $mib MiB."; return 1
    fi
  elif [ "$apu" = 1 ] || [ "$mib" -ge 15000 ]; then tier=16gb; model=Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf; vision=1; nmax=2
  elif [ "$mib" -ge 11500 ]; then tier=12gb; model=Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf;      vision=0; nmax=2
  elif [ "$mib" -ge 7500 ];  then tier=8gb;  model=Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf; vision=0; nmax=2
  elif [ "$mib" -lt 2048 ]; then
    echo "This Radeon has $mib MiB of its own memory and $gtt MiB shared (GTT). $vname needs a card with 8 GB or more,"
    echo "or an APU with more than 16 GB of GTT (32 GB of RAM or more)."
    return 1
  else echo "$vname needs a card with 8 GB or more, this one has $mib MiB."; return 1
  fi
  echo "Build:  $build (PrismML, Vulkan)"
  echo "Model:  $model, $tier tier$([ "$vision" = 1 ] && echo ', with vision')"
  echo "Folder: $dir"
  echo

  mkdir -p "$dir"
  if [ -z "$test" ]; then
    local skip_model="${BONSAI_SKIP_MODEL:-}" need_gb=10   # BONSAI_SKIP_MODEL: CI only, the real build download without the model
    [ -n "$skip_model" ] && need_gb=2
    local free_kb; free_kb=$(df -Pk "$dir" | awk 'NR == 2 { print $4 }')
    if [ "$free_kb" -lt $((need_gb * 1024 * 1024)) ]; then echo "Not enough disk space in $dir: about $need_gb GB is needed."; return 1; fi

    # 4. downloads: the build from PrismML's GitHub release, the model from Hugging Face, every file checked against its SHA256
    # the model file comes from the variant's repo: Offrail ships its own SHA256SUMS, so both are searched
    local sums ms; sums=$(curl -fsSL "$hf/SHA256SUMS")
    ms=''
    if [ "$variant" = offrail ]; then
      ms=$(curl -fsSL "$model_hf/SHA256SUMS") || { echo "could not read SHA256SUMS from the Offrail repo"; return 1; }
    fi
    # head -1: if a name ever appeared in both manifests, take one hash, not two lines
    want() { awk -v f="$1" '$2 == f || $2 == "*" f { print $1 }' <<< "$sums
$ms" | head -1; }
    get() { # url file sha
      local url=$1 path=$2 sha=$3 leaf; leaf=$(basename "$2")
      if [ -f "$path" ] && [ "$(sha256sum "$path" | cut -d' ' -f1)" = "$sha" ]; then echo "  ok    $leaf (already here)"; return; fi
      echo "  get   $leaf"
      curl -fL --retry 5 --retry-delay 3 -C - -o "$path.part" "$url"
      if [ "$(sha256sum "$path.part" | cut -d' ' -f1)" != "$sha" ]; then rm -f "$path.part"; echo "checksum mismatch for $leaf, run the installer again"; return 1; fi
      mv "$path.part" "$path"; echo "  ok    $leaf (sha256 checked)"
    }
    [ -n "$(want "$model")" ] || { echo "SHA256SUMS on Hugging Face is missing a file this needs"; return 1; }
    echo "Downloading (the build from GitHub, the model from Hugging Face, about 8 GB the first time, it resumes if it stops):"
    if [ ! -x "$dir/$build/llama-server" ]; then
      get "$build_url" "$dir/$build.tar.gz" "$build_sha"
      echo "  unpack $build.tar.gz"; mkdir -p "$dir/$build" && tar xzf "$dir/$build.tar.gz" -C "$dir/$build" --strip-components=1 && rm -f "$dir/$build.tar.gz"
    else
      echo "  ok    $build (already unpacked)"
    fi
    if ! "$dir/$build/llama-server" --version >/dev/null 2>&1; then
      echo "The Vulkan build does not start here, missing:"
      ldd "$dir/$build/llama-server" 2>&1 | grep "not found" || true
      echo "On Ubuntu or Debian: sudo apt install libgomp1 libssl3 libstdc++6, then run this again."
      return 1
    fi
    if [ -z "$skip_model" ]; then
      get "$model_hf/$model" "$dir/$model" "$(want "$model")"
      if [ "$vision" = 1 ]; then get "$prism/$mmproj" "$dir/$mmproj" "$mmproj_sha"; fi
    fi
    # the chart the speed check's vision step reads (16 GB and APUs), from this repo
    if [ "$vision" = 1 ] && ! curl -fsSL -o "$dir/vision_check.png" \
        "https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/${BONSAI_REF:-main}/prompts/vision_check.png"; then
      rm -f "$dir/vision_check.png"; echo "  (no vision_check.png this time, the speed check skips its vision step)"
    fi
  fi

  # 5. the start script: it finds the Radeon among the Vulkan devices by its memory every time it starts, so the model
  # never splits onto an integrated GPU, and on 8 GB cards it picks the window from the free memory Vulkan reports
  {
    cat <<EOF
#!/bin/bash
# $vname, written by install.sh for $name ($mib MiB$([ "$apu" = 1 ] && echo ", APU with $gtt MiB GTT")), $tier tier, AMD Radeon beta on Vulkan.
# Chat page: http://127.0.0.1:\${BONSAI_PORT:-$port}
set -eu
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
B="\$DIR/$build"
MODEL=$model MMPROJ=$([ "$vision" = 1 ] && echo "$mmproj") TIER=$tier NMAX=$nmax CARD_MIB=$mib APU=$apu API_ALIAS=$api_alias
PORT="\${BONSAI_PORT:-$port}"
EOF
    cat <<'EOF'
export LD_LIBRARY_PATH="$B${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# 127.0.0.1 = this machine only; BONSAI_HOST=0.0.0.0 opens it to your network, set BONSAI_API_KEY with it
HOST="${BONSAI_HOST:-127.0.0.1}"
KEY_ARGS=(); [ -n "${BONSAI_API_KEY:-}" ] && KEY_ARGS=(--api-key "$BONSAI_API_KEY")
MM_ARGS=(); [ -n "$MMPROJ" ] && MM_ARGS=(--mmproj "$DIR/$MMPROJ")
# the Vulkan device whose memory matches this Radeon (an APU: the biggest one), AMD devices first
DEV='' FREE=0
read -r DEV FREE <<< "$("$B/llama-server" --list-devices 2>/dev/null | awk -v want="$CARD_MIB" -v apu="$APU" '
  $1 ~ /^Vulkan[0-9]+:$/ && $NF == "free)" {
    t = substr($(NF - 4), 2) + 0; d = (apu == 1) ? -t : (t > want ? t - want : want - t); amd = ($0 ~ /AMD|Radeon|RADV/) ? 1 : 0
    if (dev == "" || amd > bamd || (amd == bamd && d < bd)) { dev = substr($1, 1, length($1) - 1); bd = d; bamd = amd; bf = $(NF - 2) + 0 }
  }
  END { if (dev != "") print dev, bf }')"
if [ -z "$DEV" ]; then echo "No Vulkan device found. Check the AMD driver and Vulkan (sudo apt install mesa-vulkan-drivers libvulkan1)."; exit 1; fi
DRAFT_ARGS=()
if [ "$TIER" = 8gb ]; then
  # lean file with the head (n-max 2) and ubatch 256 on Vulkan. Each step: the window, the MiB the card must have free and
  # whether the draft model's cache goes q4_0. The MiB = the card's share of the server at the peak of a long prompt,
  # measured on a Radeon 8060S with the host buffers left out (a discrete card keeps them in system RAM), plus 50 MiB.
  # The q4_0 draft cache saves 80 to 280 MiB for about 3% decode, so it comes on only when it buys the bigger window.
  C=16384 DQ=1
  for s in 65536:8007:0 65536:7727:1 49152:7546:0 49152:7403:1 32768:7178:0 32768:7098:1; do
    IFS=: read -r c need q <<< "$s"
    if [ "$FREE" -ge "$need" ]; then C=$c DQ=$q; break; fi
  done
  [ "$FREE" -ge 6783 ] || echo "Only $FREE MiB free on the card, the smallest window needs about 6,800 MiB: close games and video apps or it may run slowly."
  CTX_ARGS=(-c "$C" --fit off -ub 256)
  [ "$DQ" = 1 ] && DRAFT_ARGS=(-ctkd q4_0 -ctvd q4_0)
elif [ "$TIER" = 12gb ]; then
  # 12 GB: ubatch 256 and the draft model's cache in q4_0 let --fit pick about 195K instead of 158K for about 1% decode
  CTX_ARGS=(--fit on --fit-target 1024 --fit-ctx 16384 -ub 256)
  DRAFT_ARGS=(-ctkd q4_0 -ctvd q4_0)
else
  CTX_ARGS=(--fit on --fit-target 1024 --fit-ctx 16384)
fi
# the speed head drafts NMAX tokens; BONSAI_HEAD=off runs without it (the speed check uses that for its second pass)
HEAD_ARGS=(--spec-type draft-mtp --spec-draft-n-max "$NMAX" ${DRAFT_ARGS[@]+"${DRAFT_ARGS[@]}"}); [ "${BONSAI_HEAD:-on}" = off ] && HEAD_ARGS=()
echo "Radeon: $DEV, $FREE MiB free"
echo "Chat page: http://127.0.0.1:$PORT   API for agents: http://127.0.0.1:$PORT/v1 (OpenAI compatible, model $API_ALIAS)"
exec "$B/llama-server" -m "$DIR/$MODEL" ${MM_ARGS[@]+"${MM_ARGS[@]}"} --device "$DEV" -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja \
  --alias "$API_ALIAS" --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20 --host "$HOST" --port "$PORT" \
  "${CTX_ARGS[@]}" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} ${HEAD_ARGS[@]+"${HEAD_ARGS[@]}"} "$@"
EOF
  } > "$dir/start-bonsai.sh"
  chmod +x "$dir/start-bonsai.sh"
  speed_check radeon > "$dir/bench-bonsai.sh"
  chmod +x "$dir/bench-bonsai.sh"

  echo
  echo "Installed."
  echo "Start it:         $dir/start-bonsai.sh"
  echo "Check your speed: $dir/bench-bonsai.sh, it saves your results and prints a short line to share"
  echo "Chat page:        http://127.0.0.1:$port"
  echo "API for agents:   http://127.0.0.1:$port/v1 (OpenAI compatible, model $api_alias, any API key)"
  echo "Radeon support is in beta: run the speed check once and share the result, it sets the numbers for every Radeon owner."
  if [ -z "$test" ] && [ -z "${BONSAI_NO_START:-}" ]; then
    echo; echo "Starting it now, Ctrl+C stops it."; echo
    exec "$dir/start-bonsai.sh"
  fi
}

# bench-bonsai.sh, the speed check: the same checks as bench-bonsai.bat on Windows (head on, then off, three 512-token greedy
# runs each, the identity run, the vision check on 16 GB), a results block saved next to it and a short line for X. It starts
# the model through start-bonsai.sh on port 8091, so the speed check always runs the settings the chat runs.
# speed_check radeon uses radeon's locals (AMD Radeon on Vulkan), speed_check nvidia uses main's (NVIDIA on CUDA).
speed_check() {
  if [ "$1" = radeon ]; then
    cat <<EOF
#!/bin/bash
# Bonsai 2 27B speed check, written by install.sh for $name ($mib MiB), $tier tier, AMD Radeon beta on Vulkan.
# About 3 to 5 minutes: the model starts on port 8091 with the speed head, then without it, and runs the same prompts as every
# row in github.com/sudoingX/local-ai-on-your-gaming-gpu. Stop the chat first (Ctrl+C in its window).
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
export DIR CARD_NAME=$(printf %q "$name") VARIANT_NAME=$(printf %q "$vname") VARIANT_SLUG=$slug CARD_MIB=$mib APU=$apu TIER=$tier NMAX=$nmax MODEL=$model MMPROJ=$([ "$vision" = 1 ] && echo "$mmproj") BUILD=$build RELEASE=prism-b10772-e8fd209
EOF
  else
    cat <<EOF
#!/bin/bash
# Bonsai 2 27B speed check, written by install.sh for $name ($mib MiB), $tier tier, NVIDIA on CUDA.
# About 3 to 5 minutes: the model starts on port 8091 with the speed head, then without it, and runs the same prompts as every
# row in github.com/sudoingX/local-ai-on-your-gaming-gpu. Stop the chat first (Ctrl+C in its window).
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
export DIR BACKEND=nvidia CARD_NAME=$(printf %q "$name") VARIANT_NAME=$(printf %q "$vname") VARIANT_SLUG=$slug CARD_MIB=$mib GPU_IDX=$idx CC=$cc DRIVER=$driver APU=0 TIER=$tier NMAX=$nmax MODEL=$model MMPROJ=$([ "$vision" = 1 ] && echo "$mmproj") BUILD=$bundle RELEASE=bonsai2-v1.1
EOF
  fi
  cat <<'EOF'
command -v python3 >/dev/null || { echo "The speed check needs python3 (Ubuntu or Debian: sudo apt install python3), then run it again."; exit 1; }
exec python3 - "$@" <<'PY'
import base64, glob, json, os, platform, re, shutil, statistics, subprocess, sys, time, urllib.request

E = os.environ
D, APU, PORT = E['DIR'], E.get('APU') == '1', 8091
NV = E.get('BACKEND') == 'nvidia'
BASE = f'http://127.0.0.1:{PORT}'
IDENT = 'Explain in about 150 words why speculative decoding with a multi-token prediction head can be lossless under greedy decoding.'
SPEED = ('Write a detailed explanation of how a GPU runs a matrix-vector multiply: memory bandwidth, warps, caching and why '
         'decode is bandwidth bound.')
CHART = ("This chart has a group called 'fresh chat' with three bars. Give the three tok/s values as JSON with keys stock, "
         "kernel, kernel_plus_head. Only the JSON.")


def card_dir():
    """this Radeon in /sys/class/drm: the AMD card whose VRAM matches, an APU the one with the biggest GTT"""
    best = None
    for c in sorted(glob.glob(os.path.join(E.get('BONSAI_DRM', '/sys/class/drm'), 'card*'))):
        if '-' in os.path.basename(c):
            continue
        try:
            if open(c + '/device/vendor').read().strip() != '0x1002':
                continue
            v = int(open(c + '/device/mem_info_vram_total').read()) // 1048576
            g = int(open(c + '/device/mem_info_gtt_total').read()) // 1048576
        except (OSError, ValueError):
            continue
        score = -g if APU else abs(v - int(E.get('CARD_MIB') or 0))
        if best is None or score < best[0]:
            best = (score, c)
    return best[1] if best else None


def used(c):
    """MiB in use on the card now (NVIDIA: nvidia-smi; a Radeon: /sys, an APU its own memory plus GTT), None when unread"""
    if NV:
        try:
            out = subprocess.run(['nvidia-smi', '--query-gpu=memory.used', '--format=csv,noheader,nounits', '-i', E['GPU_IDX']],
                                 capture_output=True, text=True, timeout=30).stdout
            return int(out.strip().splitlines()[0])
        except Exception:
            return None
    def rd(f):
        try:
            return int(open(f'{c}/device/{f}').read()) // 1048576
        except (OSError, ValueError):
            return None
    v = rd('mem_info_vram_used') if c else None
    return None if v is None else v + ((rd('mem_info_gtt_used') or 0) if APU else 0)


def stop(p):
    if p and p.poll() is None:
        p.terminate()
        try:
            p.wait(30)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
    time.sleep(2)


def start(head):
    log = os.path.join(D, 'bench-server-%s.log' % ('head' if head else 'nohead'))
    env = dict(E, BONSAI_PORT=str(PORT), BONSAI_HOST='127.0.0.1', BONSAI_HEAD='on' if head else 'off')
    env.pop('BONSAI_API_KEY', None)
    with open(log, 'w') as f:
        p = subprocess.Popen([os.path.join(D, 'start-bonsai.sh')], env=env, stdin=subprocess.DEVNULL, stdout=f,
                             stderr=subprocess.STDOUT)
    for _ in range(900):
        if p.poll() is not None:
            sys.exit(f'The server stopped while loading, the reason is at the end of {log}')
        try:
            urllib.request.urlopen(BASE + '/health', timeout=2).read()
            return p, log
        except Exception:
            time.sleep(1)
    stop(p)
    sys.exit(f'The server did not come up in 15 minutes, see {log}')


def ask(messages, max_tokens):
    body = {'messages': messages, 'max_tokens': max_tokens, 'temperature': 0, 'top_k': 1, 'seed': 42,
            'chat_template_kwargs': {'enable_thinking': False}}
    req = urllib.request.Request(BASE + '/v1/chat/completions', data=json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=1800) as r:
        j = json.loads(r.read())
    t = j.get('timings') or {}
    return {'text': j['choices'][0]['message'].get('content') or '', 'toks': float(t.get('predicted_per_second') or 0),
            'dn': int(t.get('draft_n') or 0), 'da': int(t.get('draft_n_accepted') or 0)}


def first_line(path, key, sep):
    try:
        for line in open(path):
            if line.startswith(key):
                return line.split(sep, 1)[1].strip().strip('"')
    except OSError:
        pass
    return None


def mesa():
    """the Vulkan driver's version: vulkaninfo when it is installed, else the package manager"""
    tries = [(['vulkaninfo', '--summary'], r'driverInfo\s*=\s*Mesa\s+(\S+)'),
             (['dpkg-query', '-W', '-f', '${Version}', 'mesa-vulkan-drivers'], r'^(?:\d+:)?([\d.]+)'),
             (['pacman', '-Q', 'vulkan-radeon'], r'vulkan-radeon\s+([\d.]+)'),
             (['rpm', '-q', '--qf', '%{VERSION}', 'mesa-vulkan-drivers'], r'^([\d.]+)')]
    for cmd, pat in tries:
        if not shutil.which(cmd[0]):
            continue
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
        except Exception:
            continue
        m = re.search(pat, out, re.M)
        if m:
            return 'Mesa ' + m.group(1)
    return 'Mesa n/a'


if shutil.which('pgrep') and subprocess.run(['pgrep', '-x', 'llama-server'], stdout=subprocess.DEVNULL).returncode == 0:
    sys.exit('Bonsai (or another llama-server) is running, stop it first (Ctrl+C in its window), then run the speed check again.')
stamp = time.strftime('%Y-%m-%d %H:%M')
print(f"{E['VARIANT_NAME']} speed check, about 3 to 5 minutes. Close games and video apps first.", flush=True)
card = None if NV else card_dir()
before = used(card)
png = os.path.join(D, 'vision_check.png')
vision = None
if E.get('MMPROJ') and os.path.exists(png):
    vision = [{'role': 'user', 'content': [
        {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,' + base64.b64encode(open(png, 'rb').read()).decode()}},
        {'type': 'text', 'text': CHART}]}]
res, p, dev = {}, None, None
try:
    for head in (True, False):
        tag = 'on' if head else 'off'
        print(f'Loading with the speed head {tag}...', flush=True)
        p, log = start(head)
        ctx = json.loads(urllib.request.urlopen(BASE + '/props', timeout=30).read()).get('default_generation_settings', {}).get('n_ctx')
        loaded = used(card)
        print('  identity run', flush=True)
        ident = ask([{'role': 'user', 'content': IDENT}], 400)
        runs = []
        for k in (1, 2, 3):
            print(f'  speed run {k} of 3', flush=True)
            runs.append(ask([{'role': 'user', 'content': SPEED}], 512))
        vis = None
        if head and vision:
            print('  vision check', flush=True)
            vis = ask(vision, 200)
        if head:
            m = re.search(r'^(?:Radeon|NVIDIA): (.+?), (\d+) MiB free', open(log).read(), re.M)
            dev = m and f'{m.group(1)}, {m.group(2)} MiB free before the runs'
        res[tag] = {'ctx': ctx, 'loaded': loaded, 'after': used(card), 'ident': ident, 'runs': runs, 'vis': vis}
        stop(p)
        p = None
finally:
    stop(p)

on, off = res['on'], res['off']
mon = statistics.median(r['toks'] for r in on['runs'])
moff = statistics.median(r['toks'] for r in off['runs'])
gain = round((mon / moff - 1) * 100) if moff else 0
mib = lambda v: 'n/a' if v is None else f'{v} MiB'
f1 = lambda v: f'{v:.1f}'
cpu = first_line('/proc/cpuinfo', 'model name', ':') or platform.processor() or 'n/a'
ram = first_line('/proc/meminfo', 'MemTotal:', ':')
ram = round(int(ram.split()[0]) / 1048576) if ram else 'n/a'
lines = [
    f"{E['VARIANT_NAME']}, Linux speed check ({stamp}, {E['RELEASE']})",
    f"card: {E['CARD_NAME']}, {E['CARD_MIB']} MiB, compute {E.get('CC')}, NVIDIA driver {E.get('DRIVER')}" if NV else
    f"card: {E['CARD_NAME']}, {E['CARD_MIB']} MiB{' of its own (an APU, the rest is shared GTT)' if APU else ''}, {mesa()} (RADV)",
    f"system: {first_line('/etc/os-release', 'PRETTY_NAME=', '=') or 'Linux'}, kernel {platform.release()}, {cpu}, {ram} GB RAM",
    f"build: {E['BUILD']}, tier {E['TIER']}, file {E['MODEL']}{' + vision' if E.get('MMPROJ') else ''}",
    f'vram in use before start (desktop and other apps): {mib(before)}',
    f"context: {on['ctx']} with the head, {off['ctx']} without",
    f"vram with the head: {mib(on['loaded'])} loaded, {mib(on['after'])} after the runs",
    f"speed with the head (mtp n-max {E['NMAX']}): {' / '.join(f1(r['toks']) for r in on['runs'])} tok/s, median {f1(mon)} tok/s, "
    f"draft {sum(r['da'] for r in on['runs'])}/{sum(r['dn'] for r in on['runs'])} accepted",
    f"speed without the head: {' / '.join(f1(r['toks']) for r in off['runs'])} tok/s, median {f1(moff)} tok/s",
    f"head gain: {'+' if gain >= 0 else ''}{gain}%",
    f"same greedy text with and without the head: {'yes' if on['ident']['text'] == off['ident']['text'] else 'NO'}",
]
if on['vis']:
    vals = [float(x) for x in re.findall(r'\d+(?:\.\d+)?', on['vis']['text'])]
    hits = sum(1 for w in (25.0, 39.8, 50.1) if any(abs(v - w) < 0.05 for v in vals))
    lines.append('vision check (fresh chat bars 25.0 / 39.8 / 50.1): '
                 + ('read right' if hits == 3 else 'missed, it answered: ' + on['vis']['text'].strip()))
if NV:
    turing = (E.get('CC') or '').startswith('7.')
    lines.append(f"nvidia: CUDA, {dev or 'n/a'}, memory from nvidia-smi, GGML_CUDA_BATCH_INVARIANT=1"
                 + (" (on RTX 20 cards it does not cover every kernel: a near tie can flip a token, so the greedy text with the "
                    "head can differ)" if turing else " (the same greedy text with and without the head is expected)"))
else:
    lines.append(f"radeon: AMD Radeon beta, Vulkan device {dev or 'n/a'}, memory from /sys/class/drm"
                 + (' (its own memory plus GTT)' if APU else ''))
    lines.append('greedy text on Vulkan: no batch-invariant mode, so a different text with and without the head is expected')
text = '\n'.join(lines)
size = 'apu' if APU else f"{round(int(E['CARD_MIB']) / 1024)}gb"
# the README's names: 16k / 32k / 48k / 64k for those windows, thousands for the rest (131k, 195k, 262k)
window = 'n/a' if not on['ctx'] else (f"{on['ctx'] // 1024}k" if on['ctx'] % 16384 == 0 and on['ctx'] < 131072
                                       else f"{round(on['ctx'] / 1000)}k")
short = (f"{E['VARIANT_NAME'].lower()} on my {E['CARD_NAME'].lower()} {size} (linux, {'cuda' if NV else 'vulkan'}): {f1(mon)} tok/s with "
         f"the mtp head, {f1(moff)} without, {window} context @sudoingX")
out = os.path.join(D, time.strftime(E['VARIANT_SLUG'] + '-results-%Y%m%d-%H%M.txt'))
with open(out, 'w') as f:
    f.write(text + '\n\nshort line for X:\n' + short + '\n')
copied = False
for cmd, need in ((['wl-copy'], 'WAYLAND_DISPLAY'), (['xclip', '-selection', 'clipboard'], 'DISPLAY'),
                  (['xsel', '--clipboard', '--input'], 'DISPLAY')):
    if E.get(need) and shutil.which(cmd[0]):
        try:
            subprocess.run(cmd, input=short.encode(), timeout=5, check=True)
            copied = True
            break
        except Exception:
            pass
print('\n' + text + '\n')
print(f'Saved to {out}.')
print('Short line for X' + (', copied to your clipboard:' if copied else ':'))
print(short + '\n')
print('Share it: post the short line in a reply to @sudoingX, or open a pull request with the full block at '
      'github.com/sudoingX/local-ai-on-your-gaming-gpu')
PY
EOF
}

main "$@"
