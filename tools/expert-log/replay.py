#!/usr/bin/env python3
"""Replay an expert-log file against simulated GPU expert caches and report hit rates."""

import argparse
import heapq
from collections import OrderedDict, defaultdict


def load(path):
    picks = defaultdict(list)  # pos -> [(layer, expert), ...]
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) < 3:
                continue
            pos, layer = int(parts[0]), int(parts[1])
            picks[pos].extend((layer, int(e)) for e in parts[2:])
    return [picks[p] for p in sorted(picks)]


def static_best(tokens, cap):
    # best fixed set, chosen knowing the whole log: an upper bound for any fixed cache
    counts = defaultdict(int)
    for tok in tokens:
        for k in tok:
            counts[k] += 1
    cache = set(heapq.nlargest(cap, counts, key=counts.get))
    return [sum(k in cache for k in tok) / len(tok) for tok in tokens], 0


def lru(tokens, cap):
    cache = OrderedDict()
    hits, loads = [], 0
    for tok in tokens:
        h = 0
        for k in tok:
            if k in cache:
                cache.move_to_end(k)
                h += 1
            else:
                loads += 1
                cache[k] = None
                if len(cache) > cap:
                    cache.popitem(last=False)
        hits.append(h / len(tok))
    return hits, loads


def periodic_freq(tokens, cap, every, decay):
    # count picks with decay, refill the cache with the top experts every N tokens
    score = defaultdict(float)
    cache, hits, loads = set(), [], 0
    for i, tok in enumerate(tokens):
        hits.append(sum(k in cache for k in tok) / len(tok))
        for k in tok:
            score[k] += 1.0
        if (i + 1) % every == 0:
            new = set(heapq.nlargest(cap, score, key=score.get))
            loads += len(new - cache)
            cache = new
            for k in score:
                score[k] *= decay
    return hits, loads


def bar(frac, width=40):
    n = round(frac * width)
    return "#" * n + "." * (width - n)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log", nargs="+", help="expert-log output, several files are replayed back to back")
    ap.add_argument("--cap", default="4000,7000,10000", help="cache sizes in experts, comma separated")
    ap.add_argument("--skip", type=int, default=128, help="tokens to ignore at the start while caches fill")
    ap.add_argument("--every", type=int, default=64, help="refill interval for the periodic policy")
    ap.add_argument("--decay", type=float, default=0.9, help="score decay per refill for the periodic policy")
    ap.add_argument("--expert-mb", type=float, default=1.4, help="size of one expert, for the copy traffic")
    ap.add_argument("--window", type=int, default=256, help="tokens per row in the timeline")
    args = ap.parse_args()

    tokens = []
    for path in args.log:
        part = load(path)
        print(f"{path}: {len(part)} tokens")
        tokens.extend(part)

    layers = {l for tok in tokens for l, _ in tok}
    used = {k for tok in tokens for k in tok}
    print(f"total {len(tokens)} tokens, {len(layers)} layers, {len(tokens[0]) // len(layers)} experts per layer per token, {len(used)} different experts used\n")

    caps = [int(c) for c in args.cap.split(",")]
    policies = {
        "static (best case)": lambda c: static_best(tokens, c),
        "lru": lambda c: lru(tokens, c),
        f"periodic/{args.every}": lambda c: periodic_freq(tokens, c, args.every, args.decay),
    }

    print(f"{'cache':>7}  {'policy':<20} {'hit rate':>8}  {'copy MB/token':>13}")
    timeline = None
    for cap in caps:
        for name, run in policies.items():
            hits, loads = run(cap)
            tail = hits[args.skip:] or hits
            rate = sum(tail) / len(tail)
            mb = loads * args.expert_mb / len(tokens)
            print(f"{cap:>7}  {name:<20} {rate:>7.1%}  {mb:>13.1f}")
            if name.startswith("periodic"):
                timeline = (cap, hits)
        print()

    cap, hits = timeline
    print(f"timeline, periodic policy, cache {cap}, {args.window} tokens per row:")
    for i in range(0, len(hits), args.window):
        w = hits[i:i + args.window]
        r = sum(w) / len(w)
        print(f"{i:>7}  {bar(r)} {r:.0%}")


if __name__ == "__main__":
    main()
