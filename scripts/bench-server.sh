#!/bin/bash
# Warm-prompt bench through llama-server, for setups llama-bench can't run (MoE cache, MTP).
# Usage: bench-server.sh <name> <llama-server args...>
NAME=$1; shift
OUT=~/bench-results/$NAME
mkdir -p "$OUT"
~/llama.cpp/build/bin/llama-server "$@" -dev Vulkan0 --port 8099 > "$OUT/server.log" 2>&1 &
PID=$!
until curl -sf localhost:8099/health >/dev/null; do
  kill -0 $PID 2>/dev/null || { echo "server died"; tail -20 "$OUT/server.log"; exit 1; }
  sleep 2
done
echo "== $NAME"
for i in 1 2 3; do
  curl -s localhost:8099/v1/chat/completions -H 'Content-Type: application/json' -d '{
    "messages":[{"role":"user","content":"Write a Python function that parses an nginx access log line into a dict, with a short explanation."}],
    "max_tokens":400,"temperature":0.4,"top_p":0.8,"top_k":20,"chat_template_kwargs":{"enable_thinking":false}}' \
    > "$OUT/run$i.json"
  python -c "import json;t=json.load(open('$OUT/run$i.json'))['timings'];print(f\"run$i: pp {t['prompt_per_second']:.1f} t/s, tg {t['predicted_per_second']:.1f} t/s ({t['predicted_n']} tok), draft {t.get('draft_n_accepted','-')}/{t.get('draft_n','-')}\")"
done
kill $PID; wait $PID 2>/dev/null
