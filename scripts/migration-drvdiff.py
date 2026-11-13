#!/usr/bin/env python3
"""Classify why two derivations differ.

The migration promises no behaviour change, but it does reorder things: features
now arrive through the aggregator instead of being interleaved in each host's
imports list, so `home.packages` comes out in a different order. A reordered
buildEnv is a different derivation with identical contents, and drowning the
gate in those would make it useless for the changes that matter.

Given the derivations that differ between baseline and now, this pairs them by
name and classifies each pair:

  hash-only  identical once store hashes are erased — the difference is entirely
             a downstream rebuild caused by something else in this list
  order      same tokens, different order: a reordered path list
  CONTENT    a real difference — something was added, removed or changed
  UNPAIRED   a derivation name present on one side only

Exit 0 only if nothing is CONTENT or UNPAIRED.
"""
import json, re, subprocess, sys, collections, difflib

STORE = re.compile(r'/nix/store/[a-z0-9]{32}-')

def name_of(p):
    return p.split('/')[-1].split('-', 1)[1]

def show(drv):
    """The derivation JSON for one drv path.

    `nix derivation show` nests its result under the drv path. Unwrap until we
    reach the object that actually has an `env`, and refuse to return anything
    else: an earlier version of this returned the wrong level, which made every
    comparison see two empty envs and report "no difference". A classifier that
    cannot read its input must say so, not agree with you.
    """
    out = subprocess.run(["nix", "derivation", "show", drv],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"migration-drvdiff: cannot read {drv}: {out.stderr.strip()[:200]}")
    v = json.loads(out.stdout)
    for _ in range(3):
        if isinstance(v, dict) and "env" in v:
            return v
        if isinstance(v, dict) and v:
            v = list(v.values())[0]
        else:
            break
    sys.exit(f"migration-drvdiff: no `env` in the derivation JSON for {drv}")

def strip(s):
    return STORE.sub('/nix/store/', s)

def classify(a, b):
    """Compare two derivation JSON blobs. Returns (verdict, detail)."""
    da, db = show(a), show(b)
    ea, eb = da["env"], db["env"]
    if set(ea) != set(eb):
        return "CONTENT", f"env keys differ: {sorted(set(ea) ^ set(eb))}"
    real = []
    order = False
    for k in sorted(ea):
        if k in ("out", "outputs"):
            continue
        va, vb = strip(ea[k]), strip(eb[k])
        if va == vb:
            continue
        ta, tb = va.split(), vb.split()
        if collections.Counter(ta) == collections.Counter(tb):
            order = True
            continue
        real.append((k, va, vb))
    if real:
        k, va, vb = real[0]
        d = [l for l in difflib.unified_diff(va.split("\n"), vb.split("\n"),
                                             lineterm="", n=0)
             if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))]
        return "CONTENT", f"env `{k}` differs:\n" + "\n".join("      " + l[:200] for l in d[:12])
    return ("order" if order else "hash-only"), ""

def main():
    removed = [l.strip() for l in open(sys.argv[1]) if l.strip()]
    added = [l.strip() for l in open(sys.argv[2]) if l.strip()]
    by_name_old = collections.defaultdict(list)
    by_name_new = collections.defaultdict(list)
    for p in removed:
        by_name_old[name_of(p)].append(p)
    for p in added:
        by_name_new[name_of(p)].append(p)

    verdicts = collections.Counter()
    problems = []
    for n in sorted(set(by_name_old) | set(by_name_new)):
        o, w = by_name_old.get(n, []), by_name_new.get(n, [])
        if len(o) != len(w):
            verdicts["UNPAIRED"] += 1
            problems.append(f"    UNPAIRED  {n}: {len(o)} before, {len(w)} after")
            continue
        for x, y in zip(sorted(o), sorted(w)):
            v, detail = classify(x, y)
            verdicts[v] += 1
            if v == "CONTENT":
                problems.append(f"    CONTENT   {n}\n      {detail}")

    print("    " + ", ".join(f"{v}: {c}" for v, c in sorted(verdicts.items())))
    for p in problems:
        print(p)
    return 1 if (verdicts["CONTENT"] or verdicts["UNPAIRED"]) else 0

sys.exit(main())
