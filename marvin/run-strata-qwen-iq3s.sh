#!/bin/sh
# Strata launcher for llama-swap's Strata-IQ3S entry (2026-10-03): Qwen3.8-Flash-Next
# GSQ-RCO IQ3_S on the marvin-tuned fork, engine config
# ~/Strata-marvin/strata-iq3_s-marvin.json (--resident-budget-gib 30, ~27.8 GiB pinned,
# --vram-reserve-mib 957 as the engine asked). Model files: /mnt/shared/models/
# Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S (shard 2 = a symlink to the IQ3_XXS shard 2: the PLE
# shard is the same file for every size).
#
# IQ3_S and IQ3_XXS need the same two cards (5070 Ti + 3090), so they cannot run at
# once. Strata-IQ3XXS is persistent and llama-swap will not evict it for this entry,
# so this asks llama-swap to unload it first (once it is idle); run-strata-qwen.sh then
# waits for the old engine to free the port and VRAM. The other way needs nothing: loading
# Strata-IQ3XXS (the `subagent` alias) evicts this non-persistent entry by itself.
set -eu
PORT="${1:?usage: run-strata-qwen-iq3s.sh PORT}"
# Unload Strata-IQ3XXS only once it is idle (no request running or queued), up to 8
# min (llama-swap's healthCheckTimeout is 600 s for the whole start): llama-swap's unload API stops it at once, which killed requests mid-answer
# (2026-10-03: four `subagent` requests died with "engine stopped (exit code -15)").
# llama-swap's own evictions wait for in-flight requests; this does the same.
(
    i=0
    while [ "$i" -lt 480 ]; do
        xport=$(curl -s -m 5 http://127.0.0.1:8033/running | python3 -c '
import json, sys
for m in json.load(sys.stdin).get("running", []):
    if m["model"] == "Strata-IQ3XXS":
        print(m["proxy"].rsplit(":", 1)[1])' 2>/dev/null || true)
        [ -z "$xport" ] && exit 0                       # not loaded: nothing to unload
        if curl -s -m 5 "http://127.0.0.1:$xport/metrics" | python3 -c '
import json, sys
live = json.load(sys.stdin)["live"]
sys.exit(0 if live.get("state") == "idle" and not live.get("queued") else 1)' 2>/dev/null; then
            curl -s -m 30 -X POST http://127.0.0.1:8033/api/models/unload/Strata-IQ3XXS >/dev/null 2>&1
            exit 0
        fi
        sleep 1
        i=$((i + 1))
    done
) &
export STRATA_WAIT_S=480
exec /home/jim/Strata/run-strata-qwen.sh "$PORT" /home/jim/Strata-marvin/strata-iq3_s-marvin.json
