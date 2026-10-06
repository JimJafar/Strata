#!/bin/sh
# Strata launcher for llama-swap's Strata-IQ3S entry (2026-10-03): Qwen3.8-Flash-Next
# GSQ-RCO IQ3_S on the marvin-tuned fork, engine config
# ~/Strata-marvin/strata-iq3_s-marvin.json (--resident-budget-gib 30, ~27.8 GiB pinned,
# --vram-reserve-mib 957 as the engine asked). Model files: /mnt/shared/models/
# Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S (shard 2 = a symlink to the IQ3_XXS shard 2: the PLE
# shard is the same file for every size).
#
# IQ3_S and IQ3_XXS need the same two cards (5070 Ti + 3090), so they cannot run at
# once. Both are persistent (so dictation requests cannot evict them), and each
# launcher unloads the other one once it is idle -- see run-strata-qwen.sh.
set -eu
PORT="${1:?usage: run-strata-qwen-iq3s.sh PORT}"
# run-strata-qwen.sh unloads Strata-IQ3XXS once it is idle (STRATA_OTHER), then waits
# up to STRATA_WAIT_S for it to free the port and VRAM.
export STRATA_OTHER=Strata-IQ3XXS
exec /home/jim/Strata/run-strata-qwen.sh "$PORT" /home/jim/Strata-marvin/strata-iq3_s-marvin.json
