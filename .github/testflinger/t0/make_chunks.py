#!/usr/bin/env python3
"""Pack test files into chunks of about TARGET seconds, longest first.

usage: make_chunks.py <file list> <durations.json> <out dir> [target seconds|auto] [default seconds] [testbeds]
"""
import json
import os
import sys


def auto_target(files, durations, testbeds, rounds=2, default=480.0):
    return sum(float(durations.get(f, default)) for f in dict.fromkeys(files)) / (max(1, testbeds) * rounds)


def pack(files, durations, target=3000.0, default=480.0):
    est = {f: float(durations.get(f, default)) for f in files}
    chunks = []
    for f in sorted(dict.fromkeys(files), key=lambda f: (-est[f], f)):
        best = None
        for chunk in chunks:
            if chunk["t"] + est[f] <= target and (best is None or chunk["t"] > best["t"]):
                best = chunk
        if best is None:
            best = {"t": 0.0, "files": []}
            chunks.append(best)
        best["files"].append(f)
        best["t"] += est[f]
    chunks.sort(key=lambda c: -c["t"])
    return [c["files"] for c in chunks]


def main(argv):
    with open(argv[1]) as fh:
        files = [line.strip() for line in fh if line.strip()]
    durations = {}
    if os.path.exists(argv[2]):
        with open(argv[2]) as fh:
            durations = json.load(fh)
    default = float(argv[5]) if len(argv) > 5 else 480.0
    if len(argv) > 4 and argv[4] == "auto":
        target = auto_target(files, durations, int(argv[6]), default=default)
    else:
        target = float(argv[4]) if len(argv) > 4 else 3000.0
    chunks = pack(files, durations, target, default)
    os.makedirs(argv[3], exist_ok=True)
    for i, chunk in enumerate(chunks):
        with open(os.path.join(argv[3], "%03d" % i), "w") as fh:
            fh.write("\n".join(chunk) + "\n")
    print("%d files -> %d chunks of about %d s" % (len(set(files)), len(chunks), target))


if __name__ == "__main__":
    main(sys.argv)
