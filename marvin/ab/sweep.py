#!/usr/bin/env python3
"""Sweep engine args on top of a base config, through llama-swap's Strata slot.

usage: sweep.py BASE.json STRATA_DIR name:"--arg v --arg2 v" [name:"..."] ...
Each point: write strata-sw-<name>.json, point variant.env at it, restart Strata
when idle, run the decode cases + agent20k (2 reps), restore nothing (the last
point stays loaded).
"""
import json, sys, subprocess, time, urllib.request, shlex, shutil, pathlib

AB = pathlib.Path("/home/jim/strata-ab")
VENV = pathlib.Path("/home/jim/Strata/variant.env")

def running_port():
    r = json.load(urllib.request.urlopen("http://127.0.0.1:8033/running", timeout=10))
    for m in r["running"]:
        if m["model"] == "Strata-IQ3XXS" and m["state"] == "ready":
            return m["proxy"].rsplit(":", 1)[1]

def wait_idle():
    while True:
        p = running_port()
        if not p:
            return
        try:
            live = json.load(urllib.request.urlopen(f"http://127.0.0.1:{p}/metrics", timeout=10))["live"]
            if live.get("state") == "idle" and not live.get("queued"):
                return
        except Exception:
            pass
        time.sleep(2)

def restart():
    wait_idle()
    urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8033/api/models/unload/Strata-IQ3XXS",
                                                  method="POST"), timeout=60).read()
    while subprocess.run(["pgrep", "-x", "strata"], capture_output=True).returncode == 0:
        time.sleep(1)
    body = json.dumps({"model": "Strata-IQ3XXS", "messages": [{"role": "user", "content": "hi"}],
                       "max_tokens": 8, "reasoning_effort": "none"}).encode()
    d = json.load(urllib.request.urlopen(urllib.request.Request(
        "http://127.0.0.1:8033/v1/chat/completions", body, {"content-type": "application/json"}), timeout=900))
    assert d.get("choices"), d

def main():
    base, sdir = sys.argv[1], sys.argv[2]
    for spec in sys.argv[3:]:
        name, args = spec.split(":", 1)
        c = json.load(open(base))
        extra = shlex.split(args)
        # an arg given here replaces the base's value for it
        a = c["args"]
        i = 0
        while i < len(extra):
            k = extra[i]
            has_val = i + 1 < len(extra) and not extra[i + 1].startswith("--")
            if k.startswith("ENV:"):
                kk, vv = k[4:].split("=", 1)
                c.setdefault("env", {})[kk] = vv
                i += 1
                continue
            if k in a:
                j = a.index(k)
                if has_val and j + 1 < len(a) and not a[j + 1].startswith("--"):
                    a[j + 1] = extra[i + 1]
            else:
                a.append(k)
                if has_val:
                    a.append(extra[i + 1])
            i += 2 if has_val else 1
        cfg = AB / f"strata-sw-{name}.json"
        json.dump(c, open(cfg, "w"), indent=1)
        shutil.copy(AB / "strata-B1.shared-settings.json", AB / f"strata-sw-{name}.shared-settings.json")
        VENV.write_text(f"# sweep point {name}: {args}\nSTRATA_DIR={sdir}\nCONFIG={cfg}\n")
        print(f"=== {name}: {args}", flush=True)
        restart()
        subprocess.run([sys.executable, str(AB / "bench.py"), f"sw-{name}", "--reps", "2",
                        "--cases", "code,prose,explain,agent20k"], check=False)

main()
