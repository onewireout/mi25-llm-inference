# MI25 notes

Everything I measured running LLMs on a Radeon Instinct MI25 with llama.cpp, Oct 2026. Numbers only.

## Card

- Radeon Instinct MI25, 16 GB HBM2, Vega 10, gfx900
- Flashed with the WX 9100 BIOS (TechPowerUp #218718), shows up as 1002:6861, 170 W cap
- Stock BIOS was the "VIRTUAL"/MxGPU one (113-D0513500, 110 W), which failed with a PSP load error
- Flashed with amdvbflash 4.69 (`-fs -fp -fv`). 4.104 can't force-flash.
- Two setups:
  - **test bench**: secondary x4 chipset slot in my desktop (Oct 3-10)
  - **node**: Ryzen 5 3600, 32 GB DDR4-3200, PCIe 3.0 x16, headless (Oct 22 on)

## Setup issues

- CSM on in the BIOS silently disables Above 4G Decoding and ReBAR. BAR 0 was 256 MB.
  - first llama-server start after boot: ~24 t/s, ~180 MB spilled to GTT
  - restarts: 64 t/s
  - CSM off, BAR 0 = 16 GB: 66 t/s on a cold start
  - (qwen3.6 35B-A3B IQ3_S)
- llama-server rewrites preset names: the tag after `:` gets cut to its last `-`/`.` part and uppercased, so `model:27b-3bit-gsq-mtp` becomes `model:MTP`. The web UI treats `:MTP` (and mmproj/dflash/eagle3/dspark) as a sidecar file and hides it from the model picker.
- hwmon numbers and card order change between boots. Look the card up by PCI id (0x6861).

## Backend

| | 27B 3-bit GSQ tg |
|---|---|
| ROCm (gfx900, 7.2.4) | 10.9 t/s |
| Vulkan / RADV | 16.4 t/s (+51%) |
| Vulkan / AMDVLK | about -50% vs RADV |

- gfx900 has no dp4a (added in gfx906), so ROCm's quant inner loop runs 6 instructions where gfx906+ runs 1. ROCm already uses wave64 on GCN.

## Bandwidth and clocks

- clpeak global memory bandwidth: Vulkan ~367 GB/s, OpenCL ~362 GB/s (spec 484). Raw output in `data/clpeak-mi25.json`.
- `freq1_input` reads ~0.82x the real clock. Forced-state sweep: every state 3-7 read 0.83x nominal. clpeak fp32 = 10.2 TFLOPS, which needs ≥1245 MHz, while freq1_input showed ~1015 at the 170 W cap. Real load clock at 170 W ≈ 1300 MHz.
- `pp_dpm_sclk` `*` state is accurate.

## Power

All of this is sysfs and resets on reboot.

- Raising the cap past 170 W needs the pp_table patched first. The field is `/PowerTuneTable/SocketPowerLimit` (not `TDP`, not `smc_pptable/PowerControlLimit/0`).
- Needs `amdgpu.ppfeaturemask=0xfff7ffff` on the kernel cmdline.

```
cat /sys/class/drm/card0/device/pp_table > /tmp/radeon.pp_table
upp --pp-file=/tmp/radeon.pp_table set /PowerTuneTable/SocketPowerLimit=300 -w
sudo sh -c 'cat /tmp/radeon.pp_table > /sys/class/drm/card0/device/pp_table'
```

- After the write, idle draw went 4 W → 19 W.

170 W vs 300 W (test bench, llama-bench, Vulkan, -ngl 99, Oct 10):

| model | test | 170 W | 300 W | |
|---|---|---|---|---|
| Nemotron3 Nano 4B Q4_K_M | pp512 | 597.7 | 700.6 | +17% |
| | tg128 | 66.5 | 73.2 | +10% |
| gpt-oss 20B Q8_0 | pp512 | 596.4 | 703.3 | +18% |
| | tg128 | 63.5 | 66.2 | +4% |
| qwen3.6 35B-A3B IQ3_S | pp512 | 411.5 | 486.6 | +18% |
| | tg128 | 52.5 | 52.9 | ~0% |
| qwen3.8 27B 3-bit GSQ | tg | ~17 | ~19 | +12% |

DPM at the 170 W cap:
- sclk sits in state 3/4, ~11% of the time in 1-2, ~320 down-steps/s. mclk follows sclk.
- forcing mclk state 3: 17.61 t/s (no change)
- COMPUTE power profile (`pp_power_profile_mode 5`): 17.59 (no change)
- cap at 150 W: states shift down to 2/3, 967 MHz, 16.24 t/s

Undervolt at 170 W (`pp_od_clk_voltage` -50 mV on states 3-7): accepted, but real vddgfx only went 989 → 976 mV, 17.51 → 17.50 t/s. AVFS overrides the OD table.

## Qwen3.8 27B 3-bit GSQ-RCO (test bench)

This "3-bit" file is a mix of ~10 formats: iq3_s, iq3_xxs, iq4_xs, iq2_s/xs/xxs, q4_K, q2_K, iq1_m, bf16.

Per-op breakdown (`GGML_VK_PERF_LOGGER=1`), one token ≈ 59 ms:
- weight matmuls 51.5 ms (401 ops), ~246 GB/s
- everything else 14.7 ms over 1234 small ops, ~8-12 µs each (logger adds ~7 ms)
- iq3_s is only ~21 ms of the token
- 17408x5120 matvec: iq3_s 203 µs (~189 GB/s), iq3_xxs 169, iq4_xs 167 (~284 GB/s)
- 1024-row matvecs: 35-44 µs (underfilled)
- q4_K output head (248320x5120): 715 MB in 2.04 ms ≈ 350 GB/s
- iq2_s/xs/xxs: 128-146 GB/s, ~4.1 ms total

iq3_s matvec ISA (`RADV_DEBUG=shaders`):
- 64 VGPRs → 4 waves/SIMD (of 10)
- weights read as 5 narrow loads per chunk, 32 ubyte loads total, 16x `s_waitcnt vmcnt(0)`
- 110-byte blocks (not a multiple of 4)

Shader experiments (baseline 16.81 t/s, runs drift ~3% between rebuilds):

| change | VGPRs | result |
|---|---|---|
| preload all 8 rows' weights before math | 256 | 15.96 (-5%) |
| preload 2 rows, preload only on full-rows path | 84 | 17.04 |
| preload 8 rows | 128 | 16.67 |
| preload 3 rows | 84 | 16.56 |
| fake repacked layout (one 12 B + one 16 B read per lane) | 64 | 17.29 (+2.9%) |
| free decode ("speed of light") | | +6.5% |
| packed fp16 v1 (bit-trick convert + ALU sign masks) | | 15.78 |
| **packed fp16 v3** (iq3s grid as fp16 pairs in shared, sign LUT, `v_pk_fma_f16`) | 64 | 17.28 |
| packed fp16 on iq3_s + iq3_xxs + iq4_xs | 64 | **17.49** |
| q4_K: hoist smin sums out of row loop | | 4.98 vs 5.06 ms/token |

- Packed fp16 v3: main loop 1716 → 1295 instructions (-25%), iq3_s 19.7 → 16.3 ms/token. iq3_xxs 9.6 → 9.0, iq4_xs 11.1 → 10.0.
- Alternating A/B, 45 s rest, -r 3: original 16.66 / 16.61, packed 17.45 / 17.44 → **+4.9%**
- Perplexity (`-c 512 --chunks 1 -ub 1`): original 3.1713, packed 3.1717
- Patch: `patches/vulkan-packed-fp16-iq-matvec.patch` (against llama.cpp 836d571, `#define PACKED 1`). Also has the preload/speed-of-light/q4_K switches.

Other dials:

| dial | result |
|---|---|
| fusion on (default) vs `GGML_VK_DISABLE_FUSION=1` | 16.68 (~1635 jobs/token) vs 15.60 (~2100), ~9 µs per job |
| tiny-op floor (test-backend-ops ADD 4096) | 4.3 µs |
| `GGML_VK_ALLOW_GRAPHICS_QUEUE=1` | 17.53/17.50 → 17.79/17.75 (+1.5%) |
| `GGML_VK_MAX_NODES_PER_SUBMIT` 100 / 25 / 400 / 2000 | 17.82 / 17.52 / 17.85 / 17.83 |
| GCN rows/workgroup knobs | defaults fastest |

MTP on the node (draft-mtp):
- spec-draft-n-max 1: ~23 t/s peak, 94% acceptance, drops on long replies
- spec-draft-n-max 3: 16-19 t/s
- plain: 17-18 t/s

## Qwen3.8-Flash-Next 125B MoE on the node

GSQ-RCO Q2_0: 37.6 GB shard 1 + 29 GB n-gram table shard 2. 48 layers, 10 experts per token. Needs mmap: experts are ~34 GB and RAM is 31 GB.

Plain llama.cpp (Vulkan, experts on CPU):

| n-cpu-moe | warm tg | VRAM |
|---|---|---|
| 99 | 9.5 t/s | |
| 38 | 11.4 | 11.5 GB |
| 32 | 12.0 | |

Expert-pick replay (`tools/expert-log`: logs the router's top-k per layer, then simulates a GPU cache):
- ~7000-expert cache → 90-93% hit rate
- topic switches recover in ~500 tokens

Upstream SLRU expert cache, `--n-cpu-moe 99 --moe-cache-mib N`:

| moe-cache-mib | warm tg | VRAM |
|---|---|---|
| 9500 | 15.2 t/s | 14.3 GB |
| 11000 | 17.9 | |
| 12000 | 18.3 | |

- Full flags: `-ngl 99 --n-cpu-moe 99 --moe-cache-mib 12000 -fa on -ctk q8_0 -ctv q4_0 -c 32768`
- Needs ~8 warm prompts to settle at ~17 t/s. Raw runs in `data/fn-cache-12000*`.
- Prompt: cold first long prompt (~3k tokens) 22 t/s pp / 9.8 tg, disk 40-80 MB/s, CPU 93% idle. Warm: 62 pp / 17 tg, GPU 75-85% busy.

Where one token goes (~57 ms, timing patch `patches/flash-next/0002`):
- ~10 ms expert uploads: 13-18 misses, 17-23 MiB per token, ~2 GB/s (PCIe 3.0 x16 is ~12)
- ~10 ms q2_0 expert MUL_MAT_ID, ~30% of HBM bandwidth
- ~9 ms bf16 hyper-connection mat-vecs
- ~10 ms across ~2000 tiny ops, ~5 µs each
- GPU swings between 80% and 40%. Junction ~71 °C.

Dials:

| dial | result |
|---|---|
| MTP speculative | 9.3 t/s, 48% acceptance |
| temp 0.4 vs defaults | 17.41 vs 17.35 t/s (11-21 vs 12-28 misses/token) |
| context 32K → 16K | saves ~250 MB |
| q2_0 mat-vec: one 16-bit load instead of two byte loads | 34.7 / 55.4 µs, -10% kernel time (`patches/flash-next/0004`) |

"Coder" variant (`GSQ-RCO-IQ1_M`): half the experts pruned, kept weights 3.5 bpw ("1.89 bpw" is over the original size). 9.6 t/s vs Q2_0's 18.

## Other models on the node

Vulkan/RADV build 11829, 170 W, llama-bench pp512/tg128, 3 reps, `-ngl 99 -fa 1`:

| model | quant | size | tg | pp |
|---|---|---|---|---|
| gpt-oss 20B | Q8_0 | 11.3 GB | 89 | 858 |
| Nemotron3 Nano 4B | Q4_K_M | 2.6 GB | 77 | 783 |
| Qwen3.6 35B-A3B | UD IQ3_S | 12.7 GB | 68 | 586 |
| Gemma 4 26B-A4B | UD-IQ4_XS | 12.7 GB | 57 | 678 |
| Qwen3.8 27B | 3-bit GSQ-RCO | 11 GB | 17 | 134 |

35B-A3B and Gemma also ran with `-ctk q8_0 -ctv q4_0 -c 32768`. Raw output in `data/`.

## Files

- `data/`: raw llama-bench and llama-server runs from the node, clpeak output
- `scripts/`: bench scripts, `inspect-iq3s.sh` (VGPRs + load placement from a RADV shader dump)
- `patches/vulkan-packed-fp16-iq-matvec.patch`: packed fp16 matvec shaders
- `patches/flash-next/`: llama.cpp commits on top of 7894e8b (skip negative expert ids on CPU, expert upload timing, q2_0 perf test cases, q2_0 16-bit load)
- `tools/expert-log/`: router pick logger + cache replay simulator
