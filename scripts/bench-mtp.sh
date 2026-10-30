#!/bin/bash
# 27B GSQ MTP on the 6800 XT (ROCm system build) with the desktop preset's flags.
# Usage: bench-mtp.sh <spec-draft-n-max>
N=${1:-3}
D=$(dirname "$0")
OUT=$D/results-desktop/mtp-n$N
mkdir -p "$OUT"

llama-server -m /var/lib/llama-cpp/qwen3.8:27B-3bit-GSQ-MTP.gguf \
  -dev ROCm0 -ngl 99 -c 65536 -ctk q8_0 -ctv q4_0 -fa on -np 1 \
  --spec-type draft-mtp --spec-draft-n-max "$N" --port 8099 > "$OUT/server.log" 2>&1 &
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
  python -c "import json,sys;t=json.load(open('$OUT/run$i.json'))['timings'];print(f\"run$i: pp {t['prompt_per_second']:.1f} t/s, tg {t['predicted_per_second']:.1f} t/s ({t['predicted_n']} tok), draft accepted {t.get('draft_n_accepted','?')}/{t.get('draft_n','?')}\")"
done
kill $PID; wait $PID 2>/dev/null
