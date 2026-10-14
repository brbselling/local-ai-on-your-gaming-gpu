# Ternary Bonsai 2 27B, RTX 5070 Ti 16GB (native Windows 10)

All numbers from one RTX 5070 Ti 16GB (Blackwell, sm_120) on native Windows 10 IoT Enterprise LTSC 21H2 (build 19044), one
machine, 2026-10-12 and 2026-10-13, driver 610.88 (CUDA 13.3), Intel Core i7-7700, 64 GB DDR4, PCIe link gen 3 x16 (the
platform limit), Resizable BAR off, power plan Balanced. Single slot, q4_0 K/V cache, flash attention on, `-ngl 99`. The card
also drives the desktop: about 700 to 1,340 MiB in use before each run (it varies; each table notes it). Everything below was run on this machine with
the Windows installer's own build and flags. Nothing was ported from another card.

This is the 5070 Ti row (the repo has no 5070 Ti sweep yet), run on native Windows.

## Short version

- **Installed as shipped, the speed head is worth about +8.5% decode** (84.7 against 78.1 tok/s, `probe.py` means), and the gain
  depends on the prompt: code +18% (91.8 against 78.1), bash about +8%, prose about 0 (acceptance 59%). Speculation costs
  nothing on prose but does not help.
- **Draft n-max 2 beat n-max 1 in the one window it was tried**: mean 91.3 against 84.7, but all of it from code (111.9 against
  91.8). On prose it was slower (71.7 against 76.8). One run set, so treat it as a lead.
- **Context size does not change speed while there is memory to spare.** The installer's `--fit` line and a pinned `-c 131072`
  decode within 0.2 tok/s of each other (84.8 and 84.7 with the head, 78.3 and 78.1 without).
- **The repo's `-c 262144` head plus vision line (`16gb-mtp-vision.sh`) is 13% to 20% slower on this card** (68.5 against 85.6
  tok/s in one session, 76.5 and 77.4 against 88.5 in a later one) and leaves only about 450 MiB of the 16 GB free, with
  Windows reporting 718 to 782 MiB of the process in shared (system) memory. Running it twice from different starting memory
  states gave the same speed, so the starting state is not the cause; pinning `-c 131072` or letting `--fit` choose avoids it.
  Details under "Anything odd".
- **The server decodes 6 to 9% slower than llama-bench** on this machine (cause not found), and no arm produced garbage output
  (the `!!!!` failure in the 5080 row did not appear with this build).
- Depth with no head runs to 242,577 tokens in the 262,144 window (26.0 tok/s decode there).

## Build and files

- Installer: the repo's root `install.ps1` (release `v1.2-windows`), run from a local copy. It writes the launcher
  `bonsai2.ps1` (CUDA card path, sets `GGML_CUDA_BATCH_INVARIANT=1`), tier 16gb, MTP file with vision, draft n-max 1.
- Build: `bonsai2-small-gpu-windows-x64-cuda13.3-sm120-ff41412`, `llama-server` 0.2.0-dev, build 10759 (commit `de947abc3`).
- `Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf`, 7,012,820,512 bytes, sha256 `83a396ee…78f70f0`.
- `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (plain, for llama-bench), 5,946,648,928 bytes, sha256 `53107f53…1fe33ee3`, equal to the hash
  in the 5080 and 3060 rows.
- `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`, sha256 `6807ede6…631903`.

The server line the installer writes (this is what "as shipped" means below; `--port 8765` was set with `BONSAI_PORT` for this
test, the installer's own default port differs):

```text
-ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --alias bonsai-2-27b --host 127.0.0.1 --port 8765 --mmproj <mmproj>
--fit on --fit-target 1024 --fit-ctx 16384 --spec-type draft-mtp --spec-draft-n-max 1 --reasoning-effort medium
--temp 1.0 --top-p 0.95 --top-k 20
```

`--fit` trades context for memory, so the head changes the window: **219,136 tokens with the head (n-max 2: 208,128), 262,144
without.** That context difference is not a speed difference (next section).

## A/B on the same card: decode with `probe.py`

The repo's `graft/probe.py`: 1 warm-up request, then 3 prompts (python function, mmap against read, bash watcher) x 3 runs, 400
tokens, thinking off. Medians of 3 per prompt, tok/s. The mean is the OVERALL line the script prints. Head arms use
`--spec-type draft-mtp`; the head-off arms use the same flags without it. `GGML_CUDA_BATCH_INVARIANT=1` in every arm.

| arm | context | code | prose | bash | mean | when |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `--fit` line as shipped, head n-max 1 | 219,136 | 91.8 | 76.8 | 84.3 | **84.7** | window 1 |
| same, repeated in a later window | 219,136 | 94.0 | 75.0 | 87.3 | 85.6 | window 3 |
| same, earlier window | 219,136 | 92.9 | 77.1 | 83.6 | 84.4 | window 0 |
| `--fit` line, head off | 262,144 | 78.1 | 78.3 | 78.0 | **78.1** | window 1 |
| same, earlier window | 262,144 | 77.7 | 78.0 | 77.5 | 77.6 | window 0 |
| pinned `-c 131072`, head n-max 1 | 131,072 | 92.8 | 76.4 | 86.6 | **84.8** | window 2 |
| pinned `-c 131072`, head n-max 1 | 131,072 | 94.3 | 78.9 | 84.0 | 86.1 | window 3 |
| pinned `-c 131072`, head off | 131,072 | 78.2 | 78.4 | 78.2 | **78.3** | window 2 |
| `--fit` line, head n-max 2 | 208,128 | 111.9 | 71.7 | 87.5 | **91.3** | window 1 |

Windows 0 to 3 are separate server sessions on separate days or hours, so the table doubles as a repeatability check: the
head-on mean ranged 84.4 to 86.1 (about ±1%) and head-off 77.6 to 78.3. The head's gain, mean against mean in the same window:
+8.5% (window 1), +8.3% (window 2, pinned), +8.8% (window 0).

`GGML_CUDA_BATCH_INVARIANT` unset (head on, `--fit`): 91.2 / 75.5 / 86.4, mean 84.5. The installer's knob made no measurable
difference to speed here (84.7 with it, 84.5 without, inside the window-to-window spread).

### Draft acceptance (pinned `-c 131072`, head n-max 1, from the server log)

| request | acceptance | mean accepted length |
| --- | ---: | ---: |
| warm-up | 0.538 | 1.54 |
| code, 3 runs | 0.949, 0.918, 0.886 (mean 0.918) | 1.95, 1.92, 1.89 |
| prose, 3 runs | 0.575, 0.570, 0.615 (mean 0.587) | 1.57, 1.57, 1.62 |
| bash, 3 runs | 0.785, 0.740, 0.769 (mean 0.765) | 1.78, 1.74, 1.77 |

Code accepts about 92% of drafted tokens and decodes 18% faster than head off; prose accepts about 59% and gains nothing. The
speed gain tracks the acceptance.

## Depth: decode at real context depth, head on against head off

`deep_probe.py` with a 181,385-byte corpus: the printed depth is the real token count from the server's `/tokenize`, 2 runs per
depth (run 1 prefills the new part, run 2 hits the cache and gives clean decode), 300 tokens. Server-reported tok/s, median of the
two runs. Both arms are the installer's `--fit` line (head on is the 219,136 window, head off is the 262,144 window).

| depth (tokens) | head off | head n-max 1 | head gain |
| ---: | ---: | ---: | ---: |
| 19,523 | 66.26 | 71.17 | +7.4% |
| 43,306 | 57.17 | 60.76 | +6.3% |
| 81,204 | 40.44 | 50.63 | +25.2% |
| 130,542 | 32.65 | 42.27 | +29.5% |
| 216,183 | 27.92 | 31.07 | +11.3% |
| 242,577 | **25.92** | n/a (window is 219,136) | |

At 242,577 tokens the first request prefilled 242,589 tokens in 409.4 s (about 593 tok/s, calculated from the log) and the cached
second request started in 0.5 s. The gain at 81K and 130K looks larger than the others; I did not repeat the depth runs, so I
would not read more into the shape than "the head still helps at depth".

llama-bench at depth (plain file) is below, and the server numbers sit below it as expected: e.g. 40.44 tok/s in the server at
81K against 52.43 at 65K and 38.39 at 131K in llama-bench.

## Served VRAM

Whole-board `memory.used` from `nvidia-smi` (per-process memory reads N/A under WDDM), measured when the server was healthy
(after load) and after the probe. The desktop's idle baseline was 1,286 to 1,336 MiB in those windows, so subtract about 1.3 GB
for the model, KV cache and compute buffers.

| arm | context | mmproj | card after load | card after probe |
| --- | ---: | :---: | ---: | ---: |
| pinned, head off | 131,072 | yes | 10,965 MiB | 11,071 MiB |
| pinned, head n-max 1 | 131,072 | yes | 12,847 MiB | 12,959 MiB |
| `--fit` line, head off | 262,144 | yes | 13,949 MiB | 14,055 MiB |
| `--fit` line, head n-max 1 | 219,136 | yes | 15,291 MiB | 15,407 MiB |
| `--fit` line, head n-max 2 | 208,128 | yes | 15,143 MiB | 15,259 MiB |
| head off, 242K depth run | 262,144 | yes | 13,909 MiB | 14,019 MiB |
| repo `-c 262144`, head n-max 1 | 262,144 | yes | 15,832 MiB | 15,864 MiB |

The head costs about 1.9 GB at a fixed context (10,965 to 12,847 MiB at 131,072), which is why `--fit` gives up 43K tokens of
window to keep it.

## Anything odd: the 262144 head line is 13% to 20% slower, with almost no free VRAM and some memory in the shared pool

`serve/16gb-mtp-vision.sh` uses `-c 262144` with the head and vision. On this card that setup ran slower in every session I
tried. Windows exposes per-process GPU memory through the performance
counters (`\GPU Process Memory(pid_<pid>_*)\Dedicated Usage` and `Shared Usage`), sampled once a second during `probe.py`.

**Session A** (three arms in one window, desktop baseline 1,286 MiB; "free" = 16,303 MiB total minus the board's memory after load):

| arm | context | card after load | free | process dedicated (max) | process shared (max) | probe mean tok/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pinned, head n-max 1 | 131,072 | 12,839 MiB | 3,464 MiB | 11,665 MiB | 398 MiB | 86.1 |
| `--fit` line, head n-max 1 | 219,136 | 15,247 MiB | 1,056 MiB | 14,073 MiB | 570 MiB | 85.6 |
| repo line | 262,144 | 15,832 MiB | 471 MiB | 15,122 MiB | 782 MiB | **68.5** (-20%) |

An even earlier window measured the same pair at 84.4 and 67.9 (-19.5%).

**Session B** (a later session after a reboot, the identical command twice, then the control; no flag changed between runs):

| run | baseline before | card after load | free | process shared (max) | code / prose / bash | probe mean tok/s |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| 262,144, first run | 977 MiB | 15,850 MiB | 453 MiB | 718 MiB | 83.2 / 68.8 / 77.6 | **76.5** |
| 262,144, same command again | 702 MiB | 15,839 MiB | 464 MiB | 718 MiB | 83.6 / 71.3 / 76.8 | **77.4** |
| pinned 131,072 (control) | 686 MiB | 12,239 MiB | 4,064 MiB | 398 MiB | 96.1 / 80.0 / 90.4 | **88.5** |

Both 262,144 runs had the same process dedicated maximum (15,186 MiB). The OVERALL lines are `mean 76.5 median 77.6`, `mean 77.4
median 76.8` and `mean 88.5 median 90.4`.

What this shows:

- **The starting memory state is not the cause.** The idle baseline fell from 977 to 702 MiB between the first run and the
  repeat (memory held by other apps was released after the first server stopped), yet the repeat ran only 1.2% faster (77.4
  against 76.5, inside the run-to-run spread) with the same free memory and the same shared figure.
- **The setting is the cause, or the free memory it leaves.** The same line pinned at 131,072 ran 88.5, 12.5% to 13.6% faster
  than the two 262,144 runs (session A: 20%). Speed held at 131,072 (3.5 to 4.1 GB free) and at the `--fit` window (about 1.1 GB
  free, the installer's `--fit-target 1024` margin) and fell when only 450 to 470 MiB was free. The installer's margin looks
  designed to keep that headroom. [inference]
- **The server flags it itself.** Only the 262,144 run logged `common_fit_params: failed to fit params to free device memory:
  n_gpu_layers already set by user to 99, abort` (the default `--fit` free-memory margin could not be met, and `-ngl 99` leaves
  it nothing to adjust). The 131,072 control did not log it.
- **Mostly each draft step takes longer, not fewer tokens per step.** From the server logs (session B, 262,144 first run against
  the control), time per draft step (ms per token times mean accepted length) was 22.8 against 20.2 ms for code, 22.3 against
  19.9 for prose and 22.6 against 20.0 for bash, a steady +12.4% to +12.7% on every prompt. Draft acceptance was also 4 to 7
  points lower at 262,144 (code 0.900 against 0.943, prose 0.534 against 0.580, bash 0.738 against 0.804; mean accepted length
  1.90 against 1.94, 1.53 against 1.57, 1.74 against 1.80), which accounts for 2 to 3.5% of the slowdown. A uniform step-time
  penalty across very different prompts fits a memory effect rather than a prompt effect. [inference]
- **The shared (system-memory) figure grows with the window** (398, 570, 718 to 782 MiB). Which allocations sit in the shared
  pool and whether that, or something else tied to near-full VRAM, costs the speed were not isolated.
- The slowdown was smaller after the reboot (13% against 20%); the cause of that difference is not known.

I did not set the CUDA Sysmem Fallback Policy (the NVIDIA Control Panel is not installed on this machine), so the Windows driver
default applies, and I could not test whether the 262,144 load would fail outright with fallback off. I did not run the optional
raised-baseline run, because the repeat already showed the baseline made no difference. Pinning `-c 131072` or letting `--fit`
choose (the installer does) avoids the slowdown; the README's note about `-c 131072` on a card that also drives a display matches
this.

Also seen: board idle memory fell after a large server stopped (977, then 702, then 686 MiB in session B; 1,286, then 821 MiB at
the end of session A) with nothing of mine running, so something releases memory after a large load. It did not change speed.

## Power and temperature

`nvidia-smi` every 0.4 to 0.5 s, "active" = board power 100 W or more (a utilization filter hides the head arms, whose bursts
are short). Board limit 300 W.

| arm | mean board power (active) | max board power | max GPU temp |
| --- | ---: | ---: | ---: |
| pinned 131,072, head n-max 1 (probe) | 176.3 W | 188.4 W | 60 C |
| pinned 131,072, head off (probe) | 188.8 W | 200.6 W | 59 C |
| 242K depth run, head off | 277.3 W | 295.1 W | 67 C |
| deep runs 19K to 216K, head n-max 1 (samples at 80% utilization or more) | 267.4 W | 286.7 W | 67 C |
| deep runs 19K to 216K, head off (same filter) | 263.2 W | 290.5 W | 66 C |

SM clock about 2,840 MHz under load (window 1 poll). The PCIe link stayed gen 3 x16 in every poll. The speed head draws about 7%
less board power than head off during the probe, at 8% higher decode.

## llama-bench lines verbatim

Command shape (the repo's CONTRIBUTING flags), one invocation per file:
`llama-bench.exe -m <file> -ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 -p 512 -n 128 -r 3`, and for the depth run the same with
`-d 0,16384,65536,131072`. The ± is llama-bench's spread over its 3 repeats. pp512 spread is wide on this machine (4% to
12%); tg128 spread is 0.3% to 1.6%.

### plain file

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |     1747.88 ± 207.58 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         79.80 ± 1.28 |

build: de947abc3 (10759)
```

### plain file, with depth

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |      1889.42 ± 71.19 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         80.93 ± 0.27 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d16384 |      1596.27 ± 51.65 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d16384 |         71.56 ± 0.64 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d65536 |       871.71 ± 19.44 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d65536 |         52.43 ± 0.24 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | pp512 @ d131072 |        548.53 ± 4.44 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | tg128 @ d131072 |         38.39 ± 0.34 |

build: de947abc3 (10759)
```

### MTP file

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   6.52 GiB |    28.59 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |     1766.92 ± 226.20 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   6.52 GiB |    28.59 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         80.70 ± 0.97 |

build: de947abc3 (10759)
```

llama-bench does no drafting, so the MTP file's extra 1.7 B parameters cost nothing in plain decode (80.70 against 79.80, inside
the spread).

## Reproduce

1. Run the Windows installer for the 16gb tier with `BONSAI_DIR` set to a fresh folder and `BONSAI_NO_START` so it does not start.
2. Start `llama-server` with the line in "Build and files" (or add `-c 131072` and drop the `--fit` flags for the pinned arm).
3. `python graft/probe.py http://127.0.0.1:8765` for the A/B table; stop the server and repeat without `--spec-type`.
4. Nothing else should be using the GPU; the idle baseline above was measured with other services stopped.
