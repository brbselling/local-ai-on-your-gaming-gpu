# local-ai-on-your-gaming-gpu

Run a 27B local AI on the gaming card you already own: RTX 20, 30, 40 and 50, and AMD Radeon in beta, with 8 GB or more,
on Windows and Linux, one line to install.

Windows, in PowerShell:

```
irm https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/main/install.ps1 | iex
```

Linux or WSL2:

```
curl -fsSL https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/main/install.sh | bash
```

AMD Radeon with 8 GB or more, and Ryzen APUs like Strix Halo: the same two lines, on Vulkan with no ROCm to install,
in beta, see [Radeon (beta)](#radeon-beta).

The same installer also carries the uncensored build of the same model, one flag away: `--model offrail` on Linux,
`$env:BONSAI_MODEL='offrail'` on Windows, or answer the question it asks. See
[Uncensored: Offrail 27B](#uncensored-offrail-27b).

It finds your card, downloads the right build and model from Hugging Face (about 8 GB, every file checked against
its SHA256) and starts it. Chat in your browser at `http://127.0.0.1:8899`, or point any agent at
`http://127.0.0.1:8899/v1` (OpenAI compatible, model `bonsai-2-27b`). On Windows a desktop shortcut starts it again
and `bench-bonsai.bat` measures your card, see [Windows](#windows); on Linux `bench-bonsai.sh` in the install folder
does the same.

The model today is Ternary Bonsai 2 27B, PrismML's 5.95 GB ternary Qwen 3.8 27B, with the Qwen 3.8 MTP speed head:
50 tok/s on an RTX 3060 12GB. Native Windows is measured on real cards too: 48.6 tok/s on an RTX 3060 12GB and 84.7 on
an RTX 5070 Ti 16GB.

Under the hood: serve lines per VRAM tier with the measured flags, a 1.5x faster decode kernel for the PrismML fork,
the Qwen 3.8 MTP head grafted back onto the ternary file for lossless speculative decoding, and a sweep table that
grows by PR. The core numbers were measured on one RTX 3060 12GB, the most owned desktop GPU on Steam (3.92% of
every surveyed system, August 2026), the RTX 50 numbers on an RTX 5060 Ti 16GB and the RTX 20 numbers on an RTX 2070
Super 8GB. Other cards land as rows in
`sweeps/` from their owners.

## Uncensored: Offrail 27B

![Offrail 27B, the uncensored Bonsai 2 27B for 8GB and 12GB cards](assets/offrail_hf_banner_2x1.png)

The same installer, the same bundles, the same MTP head, with the uncensored weights of the same model instead of
PrismML's: OS-Software's Heretic build of ternary Qwen 3.8 27B. It answers what the standard build refuses, so use it
where that is what you want. Everything else is unchanged: the tiers, the window steps, the vision tower, the speed
check.

Windows, in PowerShell:

```
$env:BONSAI_MODEL='offrail'; irm https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/main/install.ps1 | iex
```

Linux or WSL2:

```
curl -fsSL https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/main/install.sh | bash -s -- --model offrail
```

With a terminal the installers ask which build, and `1` (or Enter) is the standard one, so nothing changes for anyone
who does not answer `2`. On Linux `BONSAI_MODEL=offrail` does the same as the flag; `BONSAI_NO_PROMPT=1` keeps the
standard build and never asks.

The weights come from [sudoingx/Offrail-27B-Uncensored](https://huggingface.co/sudoingx/Offrail-27B-Uncensored), its own
repo with its own SHA256SUMS, in the standard build's two sizes: `Offrail-27B-12G.gguf` on 12 GB and up (16 GB and up
with vision), `Offrail-27B-8G.gguf` on 8 GB. The bundles, the 8 GB window steps and the vision file are the standard
build's, so the tiers behave the same.

Measured on an RTX 3060 12GB: 50.8 tok/s with the MTP head at 131K context, 41.4 without, 10,618 MiB served, and the
greedy text identical with and without the head, like the standard build's rows. The chat model is `offrail-27b`, where
the standard build is `bonsai-2-27b`; the desktop shortcut and both `.bat` titles say Offrail 27B, and the speed check
saves `offrail-results-*.txt`, so a row from it cannot be read as a standard-build row.

## By hand: find your card

The installers above do this for you. By hand on Linux: prebuilt bundles on the [Hugging Face repo](https://huggingface.co/sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF),
driver only, no compiler. Find your card, take its bundle and script:

| your card | VRAM | bundle | script | what you get |
| --- | --- | --- | --- | --- |
| RTX 3050 8GB, 3060 8GB, 3060 Ti, 3070, 3070 Ti, 3080 10GB, 4060, 4060 Ti 8GB | 8 to 10 GB | cuda12.4 sm86-sm89 | `serve-8gb.sh` | 98K context; 64K if the card also drives your display |
| RTX 3060 12GB, 3080 12GB, 3080 Ti, 4070, 4070 Super, 4070 Ti | 12 GB | cuda12.4 sm86-sm89 | `serve-12gb-mtp.sh` | the MTP head, 131K context |
| RTX 4060 Ti 16GB, 4070 Ti Super, 4080, 4080 Super, 3090, 3090 Ti, 4090 | 16 to 24 GB | cuda12.4 sm86-sm89 | `serve-12gb-mtp.sh` with `CTX=262144` | the MTP head, the full 262K |
| RTX 5050, 5060, 5060 Ti 8GB | 8 GB | cuda12.8 sm120 | `serve-8gb.sh` | 98K context; 64K with a display |
| RTX 5070 | 12 GB | cuda12.8 sm120 | `serve-12gb-mtp.sh` | the MTP head, 131K context |
| RTX 5060 Ti 16GB, 5070 Ti, 5080, 5090 | 16 to 32 GB | cuda12.8 sm120 | `serve-16gb-mtp-vision.sh` | the MTP head, vision and the full 262K |
| RTX 2060 Super, 2070, 2070 Super, 2080, 2080 Super, 2080 Ti | 8 to 11 GB | cuda12.4 sm75 | `serve-8gb-mtp.sh` with `CTX=49152` | the MTP head, 48K context; 16K if the card also drives your display |
| RTX 2060 12GB, Titan RTX | 12 / 24 GB | cuda12.4 sm75 | `serve-12gb-mtp.sh` | the MTP head; not measured yet |

Laptop GPUs: the same series, go by your VRAM. Measured so far: RTX 2070 Super 8GB, RTX 3060 12GB, RTX 3060 Ti 8GB, RTX 4070 12GB (a
contributor), RTX 5060 Ti 16GB, RTX 5080 16GB (a contributor) and the RTX 3000 Ada Laptop 8GB (a contributor); the other rows follow from the same VRAM
numbers. The Ada Laptop is the case to read before expecting the kernel's gains: on a bandwidth-bound laptop part the
PTQ1_0 mat-vec is worth about +7% decode on `bdc23b56b`, while the current PrismML `prism` branch (post-#221) adds +6 to
+15% prefill and, with the lean (no-embed) MTP file, moves the lossless MTP window from 64K to 88064
(`sweeps/rtx3000Ada-8gb.md`, measured on AC; ~15-20% slower on battery, same window). Run it on yours and open a PR with your row.

RTX 5060 Ti 16GB (any 16GB or bigger RTX 50), four commands:

```
hf download sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf bonsai2-small-gpu-linux-x64-cuda12.8-sm120-ff41412.tar.gz --local-dir ~/models/bonsai2-27b
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf --local-dir ~/models/bonsai2-27b
cd ~/models/bonsai2-27b && tar xzf bonsai2-small-gpu-linux-x64-cuda12.8-sm120-ff41412.tar.gz
./bonsai2-small-gpu-linux-x64-cuda12.8-sm120-ff41412/serve-16gb-mtp-vision.sh
```

RTX 30 or 40 with 12GB or more, three:

```
hf download sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d.tar.gz --local-dir ~/models/bonsai2-27b
cd ~/models/bonsai2-27b && tar xzf bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d.tar.gz
./bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d/serve-12gb-mtp.sh
```

On 8GB cards take `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from `prism-ml/Ternary-Bonsai-2-27B-gguf` instead and run
`serve-8gb.sh`. Then open `http://localhost:8899`: the llama.cpp chat UI, and an OpenAI-compatible API at `/v1`.

By hand with the uncensored build: the same bundles and serve scripts, but the model file from
[sudoingx/Offrail-27B-Uncensored](https://huggingface.co/sudoingx/Offrail-27B-Uncensored), `Offrail-27B-12G.gguf` on
12 GB and up or `Offrail-27B-8G.gguf` on 8 GB, and add `--alias offrail-27b` if you want the API model name to match
what the installer sets.

What you need: Linux x86-64 (on Windows, the one line at the top, or WSL2) and `hf` (`pip install -U huggingface_hub`). The RTX 50
bundle wants NVIDIA driver 570 or newer and Ubuntu 24.04 or newer (glibc 2.38); the RTX 30 and 40 bundle wants driver
525 or newer and Ubuntu 22.04 or newer. On a card that also drives your display, start with a smaller window:
`CTX=131072 ./serve-16gb-mtp-vision.sh`. Every script takes `MODEL`, `CTX`, `HOST` and `PORT` from the environment.

## The numbers, RTX 3060 12GB, llama-bench r=3, flag off, original file

| build | tg128 | pp512 |
| --- | ---: | ---: |
| PrismML fork, prebuilt prism-b10685 | 26.32 tok/s | 269.6 tok/s |
| `pr-ptq1-mmv` branch (this repo's kernel) | 40.47 tok/s | 267.8 tok/s |

Decode by filled context, same two builds: fresh 26.4 to 40.5 tok/s (1.53x), 16K 21.7 to 30.9 (1.42x),
64K 14.3 to 17.9 (1.25x), 131K 9.8 to 11.4 (1.16x). Prefill unchanged, served VRAM unchanged (7.3 GB at
64K, 11.7 GB at 262K).

With the MTP head grafted on and `GGML_CUDA_BATCH_INVARIANT=1`, `--spec-type draft-mtp --spec-draft-n-max 1`
runs at 50.1 tok/s median over code, prose and bash (code 53.2), and greedy output equals greedy output
without the flag on all three prompts. Details and every run: `results/KERNEL_REPORT.md`. The uncensored build's
own rows are in [Uncensored: Offrail 27B](#uncensored-offrail-27b).

## RTX 50 series (Blackwell), v1.1

v1.1 makes the branch correct and fast on RTX 50 cards. Two fixes, both in `kernel/blackwell.md`: the PTQ1_0 mat-vec
kernel now waits for its input under programmatic dependent launch (before v1.1 a source build decoded a run of `!` on
RTX 50 cards with the head off), and llama.cpp's flash-attention q4_0 V dequant no longer sits on the stack on sm_120
(long-context decode with a q4_0 K/V cache ran at less than half speed). The branch also moved onto PrismML's latest
release, `prism-b10743-adfffbe`, so if you built it before v1.1, clone it again.

Measured on an RTX 5060 Ti 16GB with the v1.1 bundle (`sweeps/rtx5060ti-16gb.md`): fresh decode 42.0 tok/s on PrismML's
prism-b10743, 53.4 with v1.1 and 67.3 with the MTP head (probe median, the 16GB line: full file, mmproj, 262144); 39.5
tok/s with the head at 38,774 tokens of context and 21.0 at 119,489; the head, the vision tower and the full 262,144
window together in 15,070 MiB; four requests at once 127.1 tok/s in aggregate with the head, where prism-b10743 does 58.3
without it. At 261,000 tokens, the full window, v1.1 decodes at 12.35 tok/s with the head off and 12.07 with it, where
prism-b10743 does 3.73 (3.3x, head off to head off); past about 120K tokens the head stops adding speed. Up to 8 requests
at once, four agents with 60K of context each and board power are in the same file.

No compiler: the Hugging Face repo carries a cuda12.8 sm_120 bundle next to the cuda12.4 one (driver 570 or newer),
with a `serve-16gb-mtp-vision.sh` for 16GB cards; its README is `serve/prebuilt_README_sm120.md`.

## RTX 20 series (Turing), v1.4

The same v1.1 code, built for sm_75, and both installers now pick it for RTX 20 cards with 8 GB or more. Measured on an
RTX 2070 Super 8GB (`sweeps/rtx2070super-8gb.md`):

| what | measured |
| --- | --- |
| decode, live-stream, 3 x 512 greedy tokens, the 8 GB line (lean file, head n-max 1, ubatch 256, q4_0 K/V) | 52.6 tok/s with the MTP head, 42.6 without |
| window, card with no display | 48K (7,587 MiB at the peak of a 12,842-token prompt); 64K does not load on 8 GB |
| window with a desktop on the card (about 700 MiB taken) | 16K |
| llama-bench, the plain file, head off | tg128 42.3 tok/s, pp512 446.7 tok/s; tg128 33.4 / 19.0 tok/s at 16K / 64K depth |
| vision | the test chart read right at 16K with `--image-max-tokens 1024`, or at 8K with the full image |
| the fork's PTQ1_0 test suites on sm_75 | all pass, with and without `GGML_CUDA_BATCH_INVARIANT` |

Two differences from RTX 30 and up. On 8 GB the head drafts one token instead of two: on Turing n-max 1 decodes within 4%
of n-max 2 with a 150 MiB smaller server, and that buys the 48K window. And the greedy text with the head is not always
byte-identical to the text without it: `GGML_CUDA_BATCH_INVARIANT=1` does not cover every kernel on Turing, so a near tie
can flip a token late in an answer (2 of 5 test prompts at n-max 1); the text stays clean. On the same card the CUDA build
decodes 40% faster than PrismML's Vulkan build (52.6 vs 37.7 tok/s with the head), so RTX 20 stays on CUDA.

On Windows the RTX 20 zip is in beta until a real-card run is in. If you have an RTX 20 card on Windows, run
`bench-bonsai.bat` once and post the line it gives you in a reply to [@sudoingX](https://x.com/sudoingX) or as a PR.

## What is here

- `serve/` one script per tier: 8GB at 64K, 12GB at the full 262K, 12GB with the MTP head, 16GB with the
  vision tower, 16GB with the head and the vision tower at the full 262K. Read `serve/README.md` first.
- `kernel/` the changes to the PrismML fork as patch series and ready-to-read PR bodies: the PTQ1_0
  mat-vec kernel (fast, batch-invariant small batches) and the Hadamard fix for the MTP draft graph,
  plus `blackwell.md`, the two RTX 50 fixes of v1.1. Branches on github.com/sudoingX/llama.cpp:
  `pr-ptq1-mmv` (the kernel series, PrismML-Eng/llama.cpp#218) and `bonsai2`, the one to build: the
  kernel series and the v1.1 fixes on PrismML's latest release, which already carries the Hadamard fix
  (#205, which our #217 closed in favour of) and the PTQ1_0 MMQ tile loader (#214).
- `graft/` the tools that put the Qwen 3.8 27B MTP head back into the Bonsai 2 GGUF: a byte-range
  GGUF reader and writer that handles PrismML's custom quant types, head extraction, merge with a
  byte-exact `--strip`, the identity and batch-numerics probes, tests, and `recipe.txt`.
- `sweeps/` the measured rows and the PR template for new cards.
- `prompts/` the one-paragraph build prompt used for the on-camera test.
- `results/` the two run reports and the greedy identity transcripts.

## Run it in three lines

```
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-PTQ1_0.gguf --local-dir .
# PrismML fork, release prism-b10685-7dffb15 or newer (stock llama.cpp does not load this file):
# https://github.com/PrismML-Eng/llama.cpp/releases
bash serve/12gb.sh Ternary-Bonsai-2-27B-PTQ1_0.gguf
```

For the faster decode, build the `bonsai2` branch of github.com/sudoingX/llama.cpp:

```
git clone -b bonsai2 https://github.com/sudoingX/llama.cpp && cd llama.cpp
cmake -B build -DGGML_CUDA=ON && cmake --build build -j $(nproc)
export PATH=$PWD/build/bin:$PATH
```

then run the same serve line. RTX 50 cards need CUDA 12.8 or newer (`nvcc --version`); cmake picks the card's
architecture itself (sm_120 builds as `120a`). The build also builds the server's web UI, which needs npm or network
access; `-DLLAMA_BUILD_UI=OFF` skips it. The serve scripts listen on `127.0.0.1:8899`.

## Traps

Stock llama.cpp loads the Q2_0 variant and outputs gibberish, and rejects PTQ1_0 outright; use the fork.
The file skips 6GB cards, the weights alone are 5.95 GB; on 8GB the 64K line is the one to try.

The GGUF chat template defaults `reasoning_effort` to `xhigh`, which adds a "think carefully" system line; on the 3060 at a 4,096-token client cap that returned nothing on an SVG, an HTML page and a 100-line Python script (6 of 6 greedy runs spent the whole cap inside `<think>`), and the SVG never finished thinking even at 16,384. The serve lines therefore pass `--reasoning-effort medium` (thinking on, no extra line): the same tasks complete in 45 to 124 s with 22 to 2,381 thinking tokens; keep the client `max_tokens` at 8,192 or more for code, since thinking counts against it. Measurement: `kernel/reasoning_effort.md`.

## Windows

A native build, no WSL needed, measured on an RTX 3060 12GB and an RTX 5070 Ti 16GB (`sweeps/rtx3060-12gb-windows.md`,
`sweeps/rtx5070ti-16gb.md`). Needs Windows 10 or 11 x64, an RTX 20, 30
or 40 card with NVIDIA driver 551.61 or newer (RTX 20 in beta, see [RTX 20 series](#rtx-20-series-turing-v14)) or an RTX
50 card with driver 580 or newer, and about 10 GB of disk.

1. Open PowerShell and paste the line at the top. It installs to `%USERPROFILE%\bonsai2`, makes a desktop shortcut
   "Bonsai 2 27B", starts the model and opens the chat page when it has loaded.
2. Later, start it from the shortcut or `start-bonsai.bat`, and close its window to stop it.
3. `bench-bonsai.bat` measures your card: decode speed with and without the MTP head, whether the greedy text is
   identical both ways, and on 16 GB and up a chart-reading vision check. It saves the results and copies them to the
   clipboard, ready for a PR with your row.

What it picks: RTX 50 cards get the cuda13.3 sm_120 zip, RTX 30 and 40 the cuda12.4 sm_86 + sm_89 zip, RTX 20 the
cuda12.4 sm_75 zip, all with the
CUDA runtime and the Microsoft C++ runtime inside. 16 GB and up run the MTP file with vision, 12 GB the MTP file, 8 GB
the lean MTP file with a window picked from free VRAM. From 12 GB up `--fit` sizes the window to the VRAM the desktop
leaves free.

Either build: the standard model, or the uncensored one with `$env:BONSAI_MODEL='offrail'` set before the line. The
installer asks which build when a console is attached and takes the standard one when nothing answers, and the
shortcut, both `.bat` titles and the speed check's results file are named after what it installed ("Bonsai 2 27B" or
"Offrail 27B").

Agents on another machine or in WSL2: `setx BONSAI_HOST 0.0.0.0` and `setx BONSAI_API_KEY <your key>`, start it
again, then use `http://<this pc>:8899/v1` with that key. Without them it only listens on this PC.

On a card that is tight on VRAM, set NVIDIA Control Panel, Manage 3D settings, CUDA - Sysmem Fallback Policy to Prefer
No Sysmem Fallback, so an overflow fails instead of silently spilling into system RAM.

WSL2 still works: update the NVIDIA driver on Windows and do not install a Linux driver inside WSL,
`wsl --install -d Ubuntu-24.04`, check that `nvidia-smi` inside WSL shows the card, keep the model files in `~/`
(not `/mnt/c`, which is much slower for multi-GB files), then run the Linux line.

## Radeon (beta)

The same two lines install on an AMD Radeon when there is no NVIDIA card: Radeon cards with 8 GB or more (the RX 6000,
7000 and 9000 series) and Ryzen APUs with more than 16 GB of shared memory (Strix Halo class). It runs on Vulkan, so
there is no ROCm to install: Vulkan comes with the AMD driver on Windows and with Mesa on Linux. The build is PrismML's
own build of the same fork (release `prism-b10772-e8fd209`, Linux and Windows x64, pinned to its SHA256 and downloaded
from PrismML's GitHub release), with the same model files and the same MTP head. Our CUDA decode kernel is NVIDIA only;
on Vulkan, PrismML's own PTQ1_0 shader does the work.

Both builds install the same way on a Radeon: add `--model offrail` on Linux or set `$env:BONSAI_MODEL='offrail'` on
Windows. The memory steps below are the same for it, since its two files are the standard build's sizes; its speed on a
Radeon is not measured yet, like every row in the tables below.

Find your card:

| your card | VRAM | what you get |
| --- | --- | --- |
| RX 6600, 6600 XT, 6650 XT, 7600, 9060 XT 8GB | 8 GB | the lean MTP file, up to 64K: 64K when nothing else is on the card, 48K with your desktop on it |
| RX 6700 | 10 GB | the lean MTP file, 64K |
| RX 6700 XT, 6750 XT, 7700 XT | 12 GB | the MTP file, about 195K |
| RX 6800, 6800 XT, 6900 XT, 6950 XT, 7600 XT, 7800 XT, 7900 GRE, 9060 XT 16GB, 9070, 9070 XT | 16 GB | the MTP file with vision, the full 262K |
| RX 7900 XT, 7900 XTX, Radeon AI PRO R9700 | 20 to 32 GB | the MTP file with vision, the full 262K |
| Ryzen AI Max (Strix Halo) and other Ryzen APUs with more than 16 GB shared | APU | the MTP file with vision, the full 262K |

No desktop Radeon is measured yet. The windows are memory, and the memory a window takes is the same on any Radeon
running this build: it was measured below on a Radeon 8060S, counting only what a discrete card keeps on the card. The
speed is your card's, it follows its memory bandwidth and its generation, and only your card can tell it:
[send your row](#own-a-radeon).

What it picks: every tier runs the head drafting 2 tokens with K/V in q4_0 (on Vulkan `--spec-draft-n-max 2` was 15 to
16% faster than 1, and n-max 3 and K/V in q8_0 were both slower). 8 and 10 GB cards run the lean MTP file with ubatch
256 and take the biggest window their free memory allows: 64K needs 8,007 MiB free, or 7,727 MiB with the draft model's
cache in q4_0, which costs about 3% of decode and so only comes on when it buys the bigger window; then 48K at 7,546 or
7,403 MiB, 32K at 7,178 or 7,098 MiB, else 16K. 12 GB cards run the MTP file with ubatch 256, the q4_0 draft cache and
`--fit`, which picks about 195K (158K without the two, which decode 1% faster). 16 GB and up, and APUs, run the MTP file
with vision and `--fit`. Under 8 GB it stops and says why. The start script finds the Radeon among the Vulkan devices
by its memory every time and passes `--device`, so a desktop with a Ryzen iGPU and a Radeon never splits the model onto
the iGPU.

What you need: on Windows the AMD Adrenalin driver (it brings Vulkan) and the Microsoft Visual C++ Redistributable x64
(most gaming PCs have it, the installer checks and links it); on Linux Mesa's RADV driver
(`sudo apt install mesa-vulkan-drivers libvulkan1`), glibc 2.34 or newer (Ubuntu 22.04 or newer) and python3 for the
speed check. On Windows use the PowerShell line, not WSL2.

Measured so far on one machine: a Radeon 8060S, the Strix Halo APU (40 CUs, about 256 GB/s, 128 GB unified memory), on
Linux with Mesa 25.2.8, budgeted as an 8 GB and a 12 GB card by measuring what the server really allocates. It is an
APU, not a desktop card, so these are not RX 7600 or RX 6700 XT speeds. Greedy decode, 3 x 512 tokens, median, with the
head drafting 2 tokens; without the head every row decodes at 26.2 to 26.3 tok/s:

| run as | file and settings | window | with the head | memory |
| --- | --- | --- | ---: | ---: |
| 8 GB card, nothing else on it | lean MTP, ubatch 256 | 65,536 | 46.1 tok/s | 7,957 MiB on the card |
| 8 GB card, a little less free | lean MTP, ubatch 256, q4_0 draft cache | 65,536 | 44.1 tok/s | 7,677 MiB on the card |
| 8 GB card, a desktop on it | lean MTP, ubatch 256, q4_0 draft cache | 49,152 | 44.9 tok/s (one run, after the long prompt) | 7,353 MiB on the card |
| 12 GB card | MTP, ubatch 256, q4_0 draft cache, `--fit` | 194,816 | 46.6 tok/s | 10,894 MiB on the card |
| APU, 16 GB tier | MTP + vision, `--fit` | 262,144 | 47.0 tok/s | 15,082 MiB, all of the server |

The memory on the 8 and 12 GB rows is what a discrete card holds at the peak of a 12,842-token prompt: the server's
Vulkan buffers plus what the long prompt adds, with the 300 to 650 MiB of host-side buffers left out, since a discrete
card keeps those in system RAM. The installer's steps add 50 MiB to it. The APU row counts everything the server
allocated, and its speed is the Linux speed check run through the installer. The vision check reads the chart right. On
Vulkan the greedy text with the head is not the same as without it, there is no batch-invariant mode like
`GGML_CUDA_BATCH_INVARIANT` on CUDA: on our identity prompt the two agree for the first 1,040 of 1,131 characters, then a
near tie flips one token.

### Own a Radeon?

Run the speed check once, it takes 3 to 5 minutes: `bench-bonsai.bat` on Windows, `bench-bonsai.sh` on Linux, both in
the install folder (stop the chat first). It starts the model with the speed head and without it, runs the same prompts
as every row here, saves the full results next to itself and gives you one short line for X, on your clipboard when it
can. Post the line in a reply to [@sudoingX](https://x.com/sudoingX), or open a pull request with the full block in
`sweeps/`. 8 GB cards (RX 7600, 6600, 6650 XT) first: a real card shows how much free memory an 8 GB Radeon really
reports, and with it which window it gets.

## Changelog

- **v1.5** (Oct 2026): the uncensored build. Both installers take `--model offrail` on Linux or `BONSAI_MODEL=offrail`
  on Windows, and ask which build once when a terminal is attached; the default is the standard build, unchanged. The
  uncensored weights and their own SHA256SUMS come from the sibling repo `sudoingx/Offrail-27B-Uncensored`; the bundles,
  the vision file and the window steps stay where they are, and its chat model is `offrail-27b`, with the desktop
  shortcut, both `.bat` titles and the speed check's results file following it. The standard build's output is
  byte-identical to v1.4 on both platforms and both vendors (the CI compares it against `main` on every run), and the CI
  grew five uncensored rows per platform plus a step that runs the real download, verify and unpack code against two
  fake repos, because the test mode skips downloads. Measured on an RTX 3060 12GB: 50.8 tok/s with the head at 131K,
  the same greedy-text identity as the standard build.
- **v1.4** (Oct 2026): RTX 20 (Turing). Both installers route compute 7.5 cards with 8 GB or more to a new cuda12.4
  sm_75 build of the v1.1 code (a Linux bundle and a Windows zip on Hugging Face; Windows in beta until a real-card run):
  the head drafts 1 token, 8 GB cards get 48K, 32K or 16K by free VRAM with ubatch 256. A Linux speed check for NVIDIA
  cards (`bench-bonsai.sh`, the same checks as the Windows one and a short line to share) and `BONSAI_HEAD=off` in the
  Linux start script. The RTX 2070 Super 8GB rows. The RTX 30, 40 and 50 serve lines are unchanged.
- **v1.3** (Oct 2026): AMD Radeon, in beta. The same two lines install on a Radeon with 8 GB or more and on Ryzen APUs
  with more than 16 GB shared (Strix Halo class), on PrismML's own Vulkan build (`prism-b10772-e8fd209`), no ROCm: 8 GB
  cards get up to 64K (ubatch 256, and the draft model's cache in q4_0 when it buys the bigger window), 12 GB about 195K,
  16 GB and up the full 262K with vision, the head drafting 2 tokens on every tier; the start script pins the Radeon among
  the Vulkan devices; a Linux speed check (`bench-bonsai.sh`) and a short line to share from both speed checks; the
  Radeon 8060S rows; the repo renamed from `local-ai-on-your-gaming-rtx` (old links and one-liners still work). NVIDIA
  output is unchanged apart from the repo name.
- **v1.2** (Oct 2026): native Windows. Windows x64 zips built on GitHub Actions from the v1.1 code (RTX 30 and 40:
  CUDA 12.4; RTX 50: CUDA 13.3) with the CUDA and Microsoft C++ runtimes inside; one-line installers for Windows
  (`install.ps1`) and Linux (`install.sh`) that pick the build and the model file for your card and check every
  SHA256; `bench-bonsai.bat`; `16gb-vision.sh` at the full 262K (12,684 MiB on the RTX 5080 row); the RTX 5080 16GB
  and RTX 3000 Ada Laptop 8GB sweeps from their owners; @LamplighterPaul's PDL wait merged into `pr-ptq1-mmv`
  (PrismML-Eng/llama.cpp#218); the repo renamed from `bonsai2-small-gpu`.
- **v1.1** (Sep 2026): RTX 50 series. The PTQ1_0 mat-vec PDL wait and the flash-attention q4_0 V dequant fix
  (`kernel/blackwell.md`); `bonsai2` rebased onto `prism-b10743-adfffbe`; a cuda12.8 sm_120 bundle; the 16GB serve line
  with the head and the vision tower at 262K; the RTX 5060 Ti 16GB sweep; the serve scripts take `LLAMA_SERVER`; the
  install notes (the full stock tag, CUDA 12.8 for RTX 50, `build/bin` on `PATH`, port 8899); this Windows section.
- **v1.0** (Sep 2026): the PTQ1_0 mat-vec kernel, the MTP graft, the serve lines, the cuda12.4 sm_86 + sm_89 bundle.

## Licence

Apache 2.0. Ternary Bonsai 2 27B is PrismML's, Apache 2.0; the MTP head comes from Qwen3.8-27B, Apache 2.0. The
uncensored build ships OS-Software's Heretic weights of the same model, Apache 2.0, from
`sudoingx/Offrail-27B-Uncensored`.
