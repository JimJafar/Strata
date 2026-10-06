#!/bin/sh
# Strata launcher for llama-swap: Qwen3.8-Flash-Next (base, ISTA-DASLab GSQ-RCO) / IQ3_XXS.
# Replaced Swift 1.5 IQ3_XXS on 2026-10-01 (Swift fell into long thinking loops).
#
# Engine config: strata-iq3_xxs.json. Setup was run with
#   ./setup.sh --family qwen --model IQ3_XXS \
#       --gguf-dir /mnt/models/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS \
#       --context 131072 --kv int8 --vision no --gpus 2,1 --layer-split auto \
#       --low-ram off --yes --no-start
# and then edited BY HAND (setup would undo these; the untouched output is kept as
# strata-iq3_xxs.json.setup-orig):
#   --max-context 262144  setup caps IQ3_XXS at 128K on 62 GB (its 24 GB headroom rule)
#   --kv-resident 32768   KV streaming; setup's RAM rule left it out
#   --mmap-experts        experts read from the GGUF files in place (engine 0.1.31: no
#                         experts.bin needed for a native pack) through the page cache,
#                         so the RAM is reclaimable. setup's own low-RAM mode would force
#                         ONE GPU, so it is added here instead.
#   "fit_max_tokens": true  clamp max_tokens to the room left instead of a 400
# Defaults for clients that send none: strata-iq3_xxs.shared-settings.json
# (reasoning_effort medium, max_tokens 16384). Strata fills max_tokens only when the
# request has neither max_tokens nor max_completion_tokens; llama-swap's `max_tokens?`
# filter checks max_tokens alone, so it also tags requests that send max_completion_tokens.
#
# Unlike Swift, this release keeps the PLE table in shard 2, so --native (shard 1)
# and --ple-gguf (shard 2) are different files.
set -eu
PORT="${1:?usage: run-strata-qwen.sh PORT [ENGINE_CONFIG]}"
BASE=/home/jim/Strata
CONFIG="$BASE/strata-iq3_xxs.json"
# 2026-10-03: upgraded to 0.1.37, and PRODUCTION now runs the marvin-tuned fork through
# variant.env (~/Strata-marvin, see its MARVIN.md): prompts +44..+115%, decode +12..+20%
# vs official 0.1.37 here, ~20 GiB pinned, ~25 GiB RAM left available.
# A/B switch: /home/jim/Strata/variant.env, when present, may set
# STRATA_DIR (the checkout whose serve/ to run), CONFIG, and any engine env vars
# (exported). Absent = the official checkout and config above.
STRATA_DIR="$BASE"
if [ -f "$BASE/variant.env" ]; then
    set -a
    . "$BASE/variant.env"
    set +a
fi
# An explicit engine config (2nd argument) beats variant.env's CONFIG: the
# Strata-IQ3S entry runs the fork with its IQ3_S config this way.
if [ -n "${2:-}" ]; then
    CONFIG="$2"
fi
cd "$STRATA_DIR"
# THE OTHER STRATA (2026-10-03). Strata-IQ3XXS and Strata-IQ3S need the same two cards,
# and BOTH are persistent in llama-swap (a non-persistent IQ3S was evicted by every
# dictation request: llama-swap applies the resident group's `exclusive` on each
# request to a member). Persistent models are never evicted for each other, so the
# launcher unloads the other one itself -- only once it is idle (no request running
# or queued), up to STRATA_WAIT_S: llama-swap's unload API stops a model at once,
# which killed requests mid-answer. STRATA_OTHER names it; the default (no engine
# config argument = Strata-IQ3XXS's launch) is Strata-IQ3S.
if [ -z "${STRATA_OTHER:-}" ] && [ -z "${2:-}" ]; then
    STRATA_OTHER=Strata-IQ3S
fi
WAIT_S=${STRATA_WAIT_S:-480}
if [ -n "${STRATA_OTHER:-}" ]; then
    (
        i=0
        while [ "$i" -lt "$WAIT_S" ]; do
            oport=$(curl -s -m 5 http://127.0.0.1:8033/running | python3 -c '
import json, sys
for m in json.load(sys.stdin).get("running", []):
    if m["model"] == sys.argv[1]:
        print(m["proxy"].rsplit(":", 1)[1])' "$STRATA_OTHER" 2>/dev/null || true)
            [ -z "$oport" ] && exit 0                   # not loaded: nothing to unload
            if curl -s -m 5 "http://127.0.0.1:$oport/metrics" | python3 -c '
import json, sys
live = json.load(sys.stdin)["live"]
sys.exit(0 if live.get("state") == "idle" and not live.get("queued") else 1)' 2>/dev/null; then
                curl -s -m 30 -X POST "http://127.0.0.1:8033/api/models/unload/$STRATA_OTHER" >/dev/null 2>&1
                exit 0
            fi
            sleep 1
            i=$((i + 1))
        done
    ) &
fi
# A llama-swap config reload stops the old Strata and starts this one at once, on
# the same port: the old one is still freeing port and VRAM, so the new one exited
# ("upstream command exited prematurely", 2026-10-01). Wait up to 60 s for it.
# STRATA_WAIT_S (default 480, inside llama-swap's 600 s healthCheckTimeout) sets the
# limit, since the other Strata may first finish a running request.
i=0
WAIT_TICKS=$(( WAIT_S * 2 ))
while pgrep -f "serve/server.py --engine strata --config" >/dev/null \
        && [ "$i" -lt "$WAIT_TICKS" ]; do
    sleep 0.5
    i=$((i + 1))
done
exec "$BASE/.venv/bin/python" "$STRATA_DIR/serve/server.py" \
    --engine strata \
    --config "$CONFIG" \
    --host 127.0.0.1 \
    --port "$PORT"
