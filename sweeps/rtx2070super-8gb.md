# Ternary Bonsai 2 27B + grafted Qwen 3.8 MTP head, RTX 2070 Super 8GB (Turing)

All numbers from one RTX 2070 Super 8GB (Turing, compute 7.5, 8,192 MiB, 215 W limit, no display attached), NVIDIA
driver 595.84, Ubuntu 22.04, Intel Core i7-7700K, Oct 12 2026. Live-stream = llama-server plus a streaming client, greedy
(temperature 0, top_k 1), thinking off, medians of 3 x 512 tokens. Memory = nvidia-smi memory.used minus the idle reading.
One GPU job at a time.

Builds:

- v1.1 for sm_75: github.com/sudoingX/llama.cpp `bonsai2` at `ff414120c` (tag `bonsai2-v1.1`), built with
  `-DCMAKE_CUDA_ARCHITECTURES=75`, CUDA 12.4, GCC 11.4. This is the bundle
  `bonsai2-small-gpu-linux-x64-cuda12.4-sm75-ff41412` on Hugging Face, the one the installers use.
- PrismML `prism-b10772-e8fd209`, for comparison: its Linux Vulkan build, and its Linux CUDA 12.4 build (it carries no
  sm_75 code, so the driver JIT-compiles it for Turing).

Files: `Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf` (the 8 GB line), `Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf`,
`Ternary-Bonsai-2-27B-PTQ1_0.gguf` (llama-bench), `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`, all sha256-checked against the
Hugging Face listings.

## Decode, the 8 GB line (lean file, 32K, ubatch 256, q4_0 K/V, flash attention on)

| build | head off | n-max 1 | n-max 2 | n-max 3 |
| --- | ---: | ---: | ---: | ---: |
| v1.1 sm_75, CUDA, `GGML_CUDA_BATCH_INVARIANT=1` | 42.56 | 52.63 (85% of drafts accepted) | 54.69 (73%) | 52.00 (63%) |
| PrismML b10772, Vulkan | 34.11 | 37.68 (79%) | 34.05 | 22.45 |
| PrismML b10772, CUDA (JIT for sm_75) | 46.43 | 59.48 | 58.95 | 55.04 |

The installer runs v1.1 at n-max 1: within 4% of n-max 2 and 150 MiB smaller, which buys the 48K window. PrismML's
b10772 decodes 13 to 15% faster on Turing, back to back, with byte-identical texts, but two of its flash-attention tests
fail on sm_75 (a missing kernel for one case, and an illegal memory access on another with the batch-invariance knob off),
so the installers stay on v1.1 for now.

## llama-bench (the plain file, head off, q4_0 K/V, r 3)

- v1.1: tg128 42.29 tok/s, pp512 446.69 tok/s (ubatch 256); at 16K / 64K depth tg128 33.41 / 18.99, pp512 385.85 / 251.07.
- Vulkan: tg128 35.73, pp512 283.48 (ubatch 256) and 356.54 (ubatch 512); at 16K / 64K depth tg128 30.62 / 21.90.

## Context window (v1.1, lean file, n-max 1, ubatch 256)

Memory at the peak of a 12,842-token prompt:

| card | window | memory |
| --- | --- | ---: |
| no display, 7,776 MiB free | 48K | 7,587 MiB |
| no display | 32K | 7,155 MiB |
| no display | 64K | does not load |
| about 700 MiB taken by a desktop | 16K | 6,720 MiB |
| about 700 MiB taken by a desktop | 32K | does not load |

n-max 2 adds about 150 MiB. The plain file with the head off fits 80K on a clean card (7,547 MiB) and 48K with a desktop
(6,824 MiB). The installers' steps on an RTX 20 8 GB card: 48K from 7,650 MiB free, 32K from 7,250, else 16K.

## Vision (mmproj Q8_0, n-max 1)

The repo's `prompts/vision_check.png` read right (25.0 / 39.8 / 50.1): at 8K with the full 3,002-token image (peak 7,749
MiB), and at 16K with `--image-max-tokens 1024` (prefill 321.0 tok/s, decode 50.11 tok/s, peak 7,679 MiB). 24K and up
fail in the image encoder.

## Correctness and identity

The fork's suites on sm_75 pass with and without `GGML_CUDA_BATCH_INVARIANT=1`: MUL_MAT ptq1_0 174/174,
MUL_MAT_VEC_FUSION 38/38, MUL_MAT_VEC_DEP 5/5, FLASH_ATTN_EXT q4_0 362/362, MUL_MAT_ID 83/83, FLASH_ATTN_EXT q8_0 375/375.

With the knob on, the greedy text with the head is not always byte-identical to the text without it on Turing: a near tie
flips one token late in 2 of 5 test prompts at n-max 1 (code and bash); the identity prompt matches at every setting and
the text stays clean. On the RTX 3060 and RTX 5060 Ti rows the same knob keeps the two texts identical.

## Through the installer

The Linux one-liner on this card: installed in 34 s, its speed check 52.8 / 41.9 tok/s with and without the head (+26%),
the 48K window from 7,776 MiB free, 7,578 MiB loaded.

## Power and heat

194 to 211 W of the 215 W limit, 81 to 84 C. After two hours under load the card ran about 4% slower, so builds were
compared back to back.
