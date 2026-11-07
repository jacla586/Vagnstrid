#!/usr/bin/env python3
"""Counts the Claude tokens used on this project, from Claude Code's session logs.

Claude Code keeps one .jsonl file per session (subagents included) in
~/.claude/projects/<path with / replaced by ->/. Every model reply there carries a
`usage` record; this sums them, once per request.

By default it reads the folders for this repository and for every folder below it
(e.g. geodata/), i.e. all ~/.claude/projects/<repo>* folders.

Usage:
    python3 tools/count_tokens.py                # this project, all dates
    python3 tools/count_tokens.py --since 2026-10-16 --until 2026-11-30
    python3 tools/count_tokens.py --daily        # also one line per day
    python3 tools/count_tokens.py --dir ~/.claude/projects/some-folder ...
"""

import argparse
import collections
import json
from pathlib import Path

KINDS = (
    ("input_tokens", "uncached input"),
    ("cache_creation_input_tokens", "cache write (new input)"),
    ("cache_read_input_tokens", "cache read (resent context)"),
    ("output_tokens", "output"),
)


def default_dirs() -> list[Path]:
    repo = Path(__file__).resolve().parent.parent
    base = Path.home() / ".claude" / "projects"
    prefix = str(repo).replace("/", "-")
    return sorted(p for p in base.glob(prefix + "*") if p.is_dir())


def count(folder: Path, since: str, until: str, seen: set) -> tuple:
    totals: collections.Counter = collections.Counter()
    daily: dict = collections.defaultdict(collections.Counter)
    models: collections.Counter = collections.Counter()
    requests = 0
    for path in sorted(folder.rglob("*.jsonl")):
        with path.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                message = entry.get("message")
                if not isinstance(message, dict) or not message.get("usage"):
                    continue
                if message.get("model") == "<synthetic>":
                    continue
                day = (entry.get("timestamp") or "")[:10]
                if (since and day < since) or (until and day > until):
                    continue
                # One reply is logged once per content block: count each request once.
                key = (message.get("id"), entry.get("requestId"))
                if key in seen:
                    continue
                seen.add(key)
                requests += 1
                models[message.get("model")] += 1
                for kind, _ in KINDS:
                    n = message["usage"].get(kind) or 0
                    totals[kind] += n
                    daily[day][kind] += n
    return requests, totals, daily, models


def fmt(n: int) -> str:
    return f"{n:>15,}".replace(",", " ")


def print_block(title: str, requests: int, totals: collections.Counter) -> None:
    print(f"\n{title}  ({requests} requests)")
    for kind, label in KINDS:
        print(f"  {label:<30}{fmt(totals[kind])}")
    print(f"  {'TOTAL':<30}{fmt(sum(totals.values()))}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", type=Path, nargs="+", help="session folders to read")
    parser.add_argument("--since", default="", help="first day, YYYY-MM-DD (UTC)")
    parser.add_argument("--until", default="", help="last day, YYYY-MM-DD (UTC)")
    parser.add_argument("--daily", action="store_true", help="print one line per day")
    args = parser.parse_args()

    folders = args.dir or default_dirs()
    if not folders:
        raise SystemExit("No Claude Code session folders found for this project.")

    seen: set = set()
    grand: collections.Counter = collections.Counter()
    grand_daily: dict = collections.defaultdict(collections.Counter)
    grand_models: collections.Counter = collections.Counter()
    grand_requests = 0
    for folder in folders:
        requests, totals, daily, models = count(folder.expanduser(), args.since, args.until, seen)
        print_block(folder.name, requests, totals)
        grand_requests += requests
        grand.update(totals)
        grand_models.update(models)
        for day, c in daily.items():
            grand_daily[day].update(c)

    print_block("ALL FOLDERS", grand_requests, grand)
    produced = grand["output_tokens"] + grand["input_tokens"] + grand["cache_creation_input_tokens"]
    print(f"  {'output + new input':<30}{fmt(produced)}")
    print("\nModels: " + ", ".join(f"{m} ({n})" for m, n in grand_models.most_common()))
    if grand_daily:
        days = sorted(grand_daily)
        print(f"Days: {days[0]} .. {days[-1]} ({len(days)} with activity)")
    if args.daily:
        print(f"\n{'day':<12}{'output':>15}{'new input':>15}{'cache read':>15}{'total':>15}")
        for day in sorted(grand_daily):
            c = grand_daily[day]
            new_input = c["input_tokens"] + c["cache_creation_input_tokens"]
            print(f"{day:<12}{fmt(c['output_tokens'])}{fmt(new_input)}"
                  f"{fmt(c['cache_read_input_tokens'])}{fmt(sum(c.values()))}")


if __name__ == "__main__":
    main()
