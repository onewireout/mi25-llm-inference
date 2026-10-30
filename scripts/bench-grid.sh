#!/bin/bash
# Bench Grid (MI25, Vulkan) models with the same flags as the desktop run.
# Usage: bench-grid.sh name [name...]   (names below)
M=~/models
BIN=~/llama.cpp/build/bin
OUT=~/bench-results
mkdir -p "$OUT"
KV="-fa 1 -ctk q8_0 -ctv q4_0"
B="-ngl 99 -p 512 -n 128 -r 3 -dev Vulkan0"

run() { name=$1; shift; echo "== $name"; $BIN/llama-bench "$@" -o md > "$OUT/$name.md" 2> "$OUT/$name.err"; tail -3 "$OUT/$name.md"; }

for n in "$@"; do case $n in
  qwen3.8-27b-gsq)   run $n -m "$M/qwen3.8:27B-3bit-GSQ.gguf" $B $KV ;;
  qwen3.6-35b-a3b)   run $n -m "$M/qwen3.6:35B-A3B-IQ3_S.gguf" $B $KV ;;
  gpt-oss-20b)       run $n -m "$M/gpt-oss:20B-Q8_0.gguf" $B -fa 1 ;;
  gemma4-26b-a4b)    run $n -m "$M/gemma-4-26B-A4B-it-UD-IQ4_XS.gguf" $B $KV ;;
  nemotron3-nano-4b) run $n -m "$M/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf" $B -fa 1 ;;
esac; done
