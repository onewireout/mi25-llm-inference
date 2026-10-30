#!/bin/bash
# FN Q2_0 on the 6800 XT (Vulkan) with the MoE expert cache, Grid's preset flags.
# Usage: bench-fn-cache.sh <cache-mib>
MIB=${1:-12000}
D=$(dirname "$0")
BIN=/home/user/Documents/Personal/Projects/llama.cpp-expert-cache/build-vulkan/bin/llama-server
OUT=$D/results-desktop/fn-cache-$MIB
mkdir -p "$OUT"

$BIN -m ~/Downloads/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00001-of-00002.gguf \
  -dev Vulkan0 -ngl 99 --n-cpu-moe 99 --moe-cache-mib "$MIB" \
  -c 32768 -ctk q8_0 -ctv q4_0 -fa on -np 1 --port 8099 > "$OUT/server.log" 2>&1 &
PID=$!
until curl -sf localhost:8099/health >/dev/null; do
  kill -0 $PID 2>/dev/null || { echo "server died"; tail -20 "$OUT/server.log"; exit 1; }
  sleep 2
done

for i in 1 2 3; do
  curl -s localhost:8099/v1/chat/completions -H 'Content-Type: application/json' -d '{
    "messages":[{"role":"user","content":"Write a Python function that parses an nginx access log line into a dict, with a short explanation."}],
    "max_tokens":400,"temperature":0.4,"top_p":0.8,"top_k":20,"chat_template_kwargs":{"enable_thinking":false}}' \
    > "$OUT/run$i.json"
  python -c "import json,sys;t=json.load(open('$OUT/run$i.json'))['timings'];print(f\"run$i: pp {t['prompt_per_second']:.1f} t/s, tg {t['predicted_per_second']:.1f} t/s ({t['predicted_n']} tok)\")"
done
grep -iE 'vram|moe.cache' "$OUT/server.log" | tail -5
kill $PID; wait $PID 2>/dev/null
