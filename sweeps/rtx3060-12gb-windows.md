# Ternary Bonsai 2 27B, RTX 3060 12GB (native Windows 10)

All numbers from one NVIDIA GeForce RTX 3060 (12 GB, sm_86) on native Windows 10 IoT Enterprise LTSC
(build 19044.7725, no WSL2, Hyper-V enabled), one machine, 2026-10-12, 2026-10-13 and 2026-10-14. AMD
Ryzen 7 5800XT, 32 GB DDR4-3200, driver 581.80 (CUDA 13.0 as shown by `nvidia-smi`), PCIe link gen 3 x16
(read under load), power limit 170 W (the default), Windows power plan Ultimate Performance. Single slot,
q4_0 K/V cache, flash attention on, `-ngl 99`. The card also drives the desktop: 300 to 365 MiB in use
before most runs, about 900 MiB in the first four steps of the repo-line pass, and 436 and 930 MiB in two
of the evening runs on 2026-10-14 (a minimized browser had memory on the card; see "Anything odd").

`rtx3060.md` covers this card on Linux; this is a native Windows 10 row.

Two passes on this machine, plus a repeat set. The first pass (2026-10-12) used the Windows installer's own
launcher. The second (2026-10-13 and 2026-10-14) ran the repo's two 12gb `serve/` lines by hand on the same
installer build, with the repo's `probe.py` and `deep_probe.py`. Nothing was ported from another card. The
repeat set (evening of 2026-10-14) re-ran the head arms and the plain 262,144 line with the same files and
lines; it adds windows 3 and 4 in the table below and the follow-up in "Anything odd".

## Short version

- **The speed head (draft-mtp, n-max 1) at `-c 131072` decodes 48.6 tok/s against 39.5 with the head
  off, +23%** (`probe.py` means, same window). A repeat, with the two arms run 51 minutes apart, gave 48.8
  against 39.8, also +23%. The gain depends on the prompt: code +35% (53.3 against 39.5), bash +23% (48.6
  against 39.5), prose +11% (44.1 against 39.7); in the repeat, code +36%, bash +25%, prose +8%.
  Acceptance follows it: 93%, 74% and 57%.
- **Draft n-max 2 was not better overall in either of the two windows it was tried**: mean 46.5 against
  48.6, then 46.7 against 48.8. It wins on code (55.9 against 53.3, then 57.3 against 54.1) and loses on
  prose (36.7 and 36.0, below head off at 39.7 and 40.0), where it accepted only 39% of drafted tokens in
  the first window (acceptance was not read in the second).
- **Context size does not change speed on the plain file once the card has room**: `-c 131072` gave 39.5
  tok/s and four runs of the repo's `-c 262144` line gave 39.3 to 39.5 (all with 325 to 342 MiB idle on
  the card). The next bullet is the case where it is slower.
- **The `-c 262144` line is 8 to 9% slower when the card has about 260 MiB free after load**: 35.9 to 36.1
  tok/s with 259 to 273 MiB free (three runs) against 39.3 to 39.5 with 344 to 364 MiB free (four runs).
  It reversed within one session when an extra browser was closed. Idle memory and free memory after load
  move together here, so I cannot separate them; the step falls between 273 and 344 MiB free. A small rise
  in the server's shared memory (16 to 24 MiB) goes with the slow runs. Mechanism not shown (see "Anything
  odd").
- **Depth**: decode at 42K, 119K and 255K tokens is 22.9, 12.8 and 7.1 tok/s on the plain file in the
  262,144 window. The head adds +18%, +17% and +14% at 42K, 76K and 119K (131,072 window).
- **The server decodes within about 1% of llama-bench** on the plain file (llama-bench tg128 39.58;
  server 39.4 to 39.5).

## Build and files

- Installer: the repo's root `install.ps1` (release `v1.2-windows`), run from a local copy, tier 12gb
  (MTP file, no vision projector, `--spec-draft-n-max 1`). It writes a launcher, `bonsai2.ps1`, into the
  install folder; that launcher served the first pass, and the repo's `serve/` lines were run by hand on
  the same build for the second pass.
- Build: `bonsai2-small-gpu-windows-x64-cuda12.4-sm86-sm89-ff41412`; `llama-server` reports version
  0.2.0-dev, build 10759, commit `de947abc3`, built with MSVC 19.44.35229.0. The zip tag and the
  binary's commit differ; I do not know why.
- `Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf`, 6.53 GiB, sha256
  `83a396ee218c36e5ed88205eccb940a71549d9a72a3d020cc2713f94a78f70f0` (checked by the installer
  against `SHA256SUMS` on Hugging Face).
- `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (plain, used for llama-bench), 5,946,648,928 bytes, sha256
  `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3` (matches the hash Hugging Face
  publishes for the file).
- Server bind: `127.0.0.1` only.

The two repo lines as run (model path removed). Only changes from `serve/12gb-mtp.sh` and `serve/12gb.sh`:
`--port 8765` instead of 8899, and `--alias bonsai-2-27b` added.

```text
GGML_CUDA_BATCH_INVARIANT=1 llama-server -m Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf -c 131072 --spec-type draft-mtp --spec-draft-n-max 1 -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --alias bonsai-2-27b --host 127.0.0.1 --port 8765 --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20

llama-server -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -c 262144 -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --alias bonsai-2-27b --host 127.0.0.1 --port 8765 --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20
```

The other arms are those lines with one change each: head off = the first line without the two
`--spec-*` flags (MTP file, knob set); n-max 2 = the first line with `--spec-draft-n-max 2`; pinned plain =
the second line with `-c 131072`. `GGML_CUDA_BATCH_INVARIANT=1` was set for every MTP-file arm and not for
the plain-file arms or llama-bench; I did not run the knob on its own.

The installer's own server line from the first pass (speed check, bench mode of its launcher):

```text
llama-server -m Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --alias bonsai-2-27b --host 127.0.0.1 --port 8091 --fit on --fit-target 1024 --fit-ctx 16384 --spec-type draft-mtp --spec-draft-n-max 1
```

`--fit` trades context for memory: 110,336 tokens with the head and 197,888 without. Its numbers
(median 50.8 tok/s with the head, 39.4 without, +29%, one prompt, 365 MiB idle) are from a different
method and context, so they are kept out of the tables below.

## A/B on the same card: decode with `probe.py`

The repo's `graft/probe.py`: 1 warm-up request, then 3 prompts (python function, mmap against read,
bash watcher) x 3 runs, 400 tokens, thinking off. Medians of 3 per prompt, tok/s; the mean is the OVERALL
line the script prints. Window 0 is a single-arm check on 2026-10-13 22:04; window 1 is the full pass on
2026-10-13 22:13; window 2 is 2026-10-14 08:25; window 3 is 2026-10-14 19:52 (n-max 1 and n-max 2);
window 4 is 2026-10-14 20:43 (head off). "Idle" is whole-board `memory.used` before the server started.

| arm | context | code | prose | bash | mean | when |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| head n-max 1 (`12gb-mtp.sh`) | 131,072 | 53.3 | 44.1 | 48.6 | **48.6** | window 1, idle 901 MiB |
| head n-max 1, repeated | 131,072 | 54.1 | 43.2 | 49.7 | **48.8** | window 3, idle 327 MiB |
| head n-max 2 | 131,072 | 55.9 | 36.7 | 47.3 | **46.5** | window 1, idle 302 MiB |
| head n-max 2, repeated | 131,072 | 57.3 | 36.0 | 45.5 | **46.7** | window 3, idle 328 MiB |
| head off | 131,072 | 39.5 | 39.7 | 39.5 | **39.5** | window 1, idle 901 MiB |
| head off, repeated | 131,072 | 39.1 | 39.2 | 39.2 | 39.1 | window 0, idle about 900 MiB |
| head off, repeated | 131,072 | 39.7 | 39.9 | 38.7 | 39.3 | window 2, idle 324 MiB |
| head off, repeated | 131,072 | 39.8 | 40.0 | 39.7 | 39.8 | window 4, idle 324 MiB |
| plain file (`12gb.sh`) | 262,144 | 36.1 | 36.3 | 36.1 | **35.9** | window 1, idle 904 MiB |
| plain file, repeated | 262,144 | 39.4 | 39.5 | 39.3 | **39.4** | window 2, idle 325 MiB |
| plain file, pinned | 131,072 | 39.6 | 39.4 | 39.4 | **39.5** | window 2, idle 342 MiB |

The `12gb.sh` line was run five more times on the evening of 2026-10-14; those runs are in the table under
"Anything odd".

Head off ranged 39.1 to 39.8 across four runs (about 2%). The head's gain, mean against mean in the same
window: +23%; and +22.6% between window 3's n-max 1 (48.8) and window 4's head off (39.8), which ran 51
minutes apart at idle baselines of 327 and 324 MiB. The head-on arms never ran within about 700 MiB of the
card's 12,288 MiB.

### Draft acceptance (from the server log, per request)

These are from window 1; acceptance in the repeat windows was not read.

n-max 1 (`12gb-mtp.sh`):

| request | acceptance | mean accepted length |
| --- | ---: | ---: |
| warm-up | 0.773 | 1.77 |
| code, 3 runs | 0.923, 0.936, 0.928 (mean 0.929) | 1.92, 1.94, 1.93 |
| prose, 3 runs | 0.579, 0.633, 0.506 (mean 0.573) | 1.58, 1.63, 1.51 |
| bash, 3 runs | 0.750, 0.706, 0.769 (mean 0.742) | 1.75, 1.71, 1.77 |

n-max 2 (maximum length 3):

| request | acceptance | mean accepted length |
| --- | ---: | ---: |
| warm-up | 0.667 | 2.29 |
| code, 3 runs | 0.801, 0.869, 0.856 (mean 0.842) | 2.60, 2.73, 2.71 |
| prose, 3 runs | 0.421, 0.386, 0.355 (mean 0.388) | 1.84, 1.77, 1.71 |
| bash, 3 runs | 0.648, 0.615, 0.688 (mean 0.650) | 2.29, 2.23, 2.38 |

Speed follows acceptance. Prose answers were short (119 to 236 generated tokens against 400 for code and
bash). In the depth runs below the head accepted 0.66 to 0.75.

## Depth: decode at real context depth

`deep_probe.py` with a 181,385-byte plain-text corpus. Prompt sizes were set by tokenizing against the
running server (`/tokenize`), so the depths shown are the real token counts. 3 runs at the first depth,
2 beyond, 300 generated tokens, server-reported tok/s, median of the runs (run 1 prefills the new part,
later runs hit the cache).

| depth (tokens) | head off (131,072 window) | head n-max 1 (131,072) | head gain | plain file (262,144 window) |
| ---: | ---: | ---: | ---: | ---: |
| 41,990 | 22.92 | 27.14 | +18% | 22.91 |
| 76,004 | 17.01 | 19.85 | +17% | not run |
| 119,093 | 12.78 | 14.60 | +14% | 12.76 |
| 199,739 | not run | not run | | 8.65 |
| 254,758 | not run | not run | | **7.06** |

Each depth shares its first part with the one before it, so after the first depth the server's cache
reused that part: first-request times only cover the new tokens and are not full-prompt prefill times. The
new part prefilled at 459, 292, 196 and 153 tok/s at the four depths of the plain-file arm (41,990 tokens
from empty cache, then 77,619, 81,162 and 55,535 new tokens). No out-of-memory and no failed request at
any depth.

## Served VRAM

Whole-board `memory.used` from `nvidia-smi --query-gpu=memory.used --format=csv,noheader` (per-process
memory reads N/A under WDDM). The process columns come from the Windows counters
`\GPU Process Memory(pid_<pid>_*)\Dedicated Usage` and `Shared Usage`, read after each probe.

| arm | context | idle before | card after load | card after probe | process dedicated | process shared |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| head off | 131,072 | 901 MiB | 9,625 MiB | 9,643 MiB | 8,740 MiB | 218 MiB |
| head off, repeat window | 131,072 | 324 MiB | 9,048 MiB | 9,061 MiB | 8,740 MiB | 218 MiB |
| plain file, pinned | 131,072 | 342 MiB | 9,062 MiB | 9,067 MiB | 8,740 MiB | 218 MiB |
| head n-max 1 | 131,072 | 901 MiB | 11,509 MiB | 11,527 MiB | 10,624 MiB | 402 MiB |
| head n-max 1, repeat window | 131,072 | 327 MiB | 10,940 MiB | 10,954 MiB | 10,624 MiB | 402 MiB |
| head n-max 2 | 131,072 | 302 MiB | 11,059 MiB | 11,077 MiB | 10,774 MiB | 404 MiB |
| head n-max 2, repeat window | 131,072 | 328 MiB | 11,086 MiB | 11,100 MiB | 10,774 MiB | 404 MiB |
| plain file, first run | 262,144 | 904 MiB | 12,029 MiB | 11,906 MiB | 11,604 MiB | 426 MiB |
| plain file, repeated | 262,144 | 325 MiB | 11,924 MiB | 11,942 MiB | 11,620 MiB | 410 MiB |

The head costs about 1.9 GB at a fixed context (9,625 to 11,509 MiB at 131,072; 9,048 to 10,940 MiB in the
repeat windows at a lower idle). The process figures in the repeat windows matched the first windows to the
MiB for all three MTP-file arms. The poll peak was 12,056 MiB of 12,288 on the first plain-file run and
11,942 MiB on the repeat. The first pass measured 10,396 MiB at the installer's 110,336 window with the
head (365 MiB idle).

## Anything odd: the 262,144 plain line is 8 to 9% slower with about 260 MiB free

`serve/12gb.sh` (plain file, `-c 262144`) decoded 36.1 tok/s the first time I ran it and 39.4 when I ran
the identical command again about 10 hours later. The first run started with about 900 MiB of other apps'
memory on the card (a minimized browser) and finished loading at 12,029 of 12,288 MiB, 259 MiB free. After
that run the idle baseline fell to about 302 MiB and stayed near 300 to 340 MiB; the repeat loaded to
11,924 MiB with 364 MiB free. The same file pinned at `-c 131072` (about 3.2 GB free) gave 39.5, so the
window size alone is not the cause. Power, temperature and clocks matched between the two runs.

I then repeated the identical line on the evening of 2026-10-14: five fresh server starts, each followed by
`probe.py`, with the server process's dedicated and shared memory sampled once per second during the probe.
Nothing else changed except the apps' memory on the card.

| run | idle before | free after load | min free during probe | process dedicated / shared, max | mean tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 334 MiB | 348 MiB | 336 MiB | 11,620 / 410 MiB | 39.5 |
| 2 | 329 MiB | 355 MiB | 337 MiB | 11,620 / 410 MiB | 39.3 |
| 3 (a minimized browser raised the idle level) | 930 MiB | 273 MiB | 255 MiB | 11,604 / 426 MiB | 36.0 |
| 4 (the same browser still partly resident) | 436 MiB | 265 MiB | 255 MiB | 11,596 / 434 MiB | 35.9 |
| 5 (that browser closed) | 340 MiB | 344 MiB | 324 MiB | 11,620 / 410 MiB | 39.5 |

Across all runs, the three with 259 to 273 MiB free after load (the first run above and runs 3 and 4) were
8 to 9% slower than the four with 344 to 364 MiB free, and flat across all three prompts. The change
reversed within one session when the extra browser was closed. Idle memory and free memory after load
cannot be told apart here, because the server's own footprint is almost constant (11,586 to 11,620 MiB
dedicated), so they move together. A starting level of 436 MiB was already enough for the slow value, so
about 900 MiB of other memory is not needed. The step falls between 273 and 344 MiB free. In the slow runs
the server's dedicated memory was 16 to 24 MiB lower and its shared memory 16 to 24 MiB higher (426 to 434
against 410 MiB); that is the one reading that moved with the slowdown, but it is a small amount and I
cannot show it is the cause. Mechanism not shown. The CUDA Sysmem Fallback Policy was left at the driver
default.

## Power and temperature

`nvidia-smi` every 0.4 to 0.5 s; "active" = board power 100 W or more. Board limit 170 W.

| step | mean board power (active) | max board power | max GPU temp | mean SM clock |
| --- | ---: | ---: | ---: | ---: |
| llama-bench, plain file | 164.9 W | 170.4 W | 65 C | 1,858 MHz |
| probe, head n-max 1 | 165.8 W | 170.3 W | 73 C | 1,819 MHz |
| probe, head off | 167.1 W | 170.2 W | 74 C | 1,815 MHz |
| probe, plain file, 262,144 | 167.5 W | 170.2 W | 74 C | 1,854 MHz |
| probe, head n-max 2 | 166.9 W | 170.1 W | 75 C | 1,842 MHz |
| depth, head n-max 1 | 167.6 W | 170.5 W | 76 C | 1,769 MHz |
| depth, head off | 168.1 W | 170.5 W | 76 C | 1,767 MHz |
| depth, plain file, 262,144 | 168.1 W | 170.7 W | 76 C | 1,750 MHz |

The card sits at its 170 W limit in every step; the clock settles lower as the temperature rises over the
longer depth runs. The PCIe link read gen 3 x16 under load in every step (one query about 25 s into each
run). These rows are from the first windows; the repeat windows read the same range (166 to 167 W mean
active, 71 to 73 C).

## llama-bench lines verbatim

Command shape (the repo's CONTRIBUTING flags), plain file, run 2026-10-13 with the card at about 900 MiB
idle:
`llama-bench -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 -p 512 -n 128 -r 3`.
The ± is llama-bench's spread over its 3 repeats.

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |        577.83 ± 5.76 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         39.58 ± 0.84 |

build: de947abc3 (10759)
```

The first pass (2026-10-12, idle 365 MiB) used `-fa on` (this build's help lists `on|off|auto`; the table
prints `fa` as 1) and added `-d 0,16384,65536,131072`. One run, 11 min 45 s:

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |        581.67 ± 4.12 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         40.02 ± 0.29 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d16384 |        476.25 ± 3.13 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d16384 |         31.01 ± 0.07 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d65536 |        319.75 ± 1.29 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d65536 |         18.66 ± 0.12 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | pp512 @ d131072 |        221.93 ± 0.48 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | tg128 @ d131072 |         12.03 ± 0.02 |

build: de947abc3 (10759)
```

Decode at depth, as a share of the fresh figure: 77% at 16384, 47% at 65536, 30% at 131072. Prefill: 82%,
55%, 38%. Two more first-pass runs of the same command without `-d`:

```text
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |        578.45 ± 3.79 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         40.07 ± 0.07 |

| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |        582.28 ± 3.50 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         39.90 ± 0.33 |
```

tg128 across the four clean runs: 39.58, 40.02, 40.07 and 39.90 (about 1%); pp512: 577.83, 581.67, 578.45
and 582.28.

## Not run

Vision (the 12 GB tier has no projector), draft n-max 3, the env knob on its own, a change to the CUDA
Sysmem Fallback Policy, WSL2, and any build other than the installer's.

## Reproduce

1. Run the Windows installer for the 12gb tier with `BONSAI_DIR` set to a fresh folder.
2. Start `llama-server` with either line in "Build and files" (the model files are in the install's
   `models` folder).
3. `python graft/probe.py http://127.0.0.1:8765` for the A/B table; stop the server and repeat with the
   `--spec-*` flags removed. Note the idle `memory.used` before each start.
4. For depth, `deep_probe.py` against the same server with prompt sizes found by tokenizing; the real
   token count is printed.
