"""Summary of the dedicated server's log (server_log.jsonl, DedicatedServer).

python3 tools/server/vote_stats.py [path to server_log.jsonl]
(default: ~/.local/share/godot/app_userdata/Vagnstrid/server_log.jsonl)
Votes per scenario and per mode, how often each won, matches played and how long, and
how many players were on.
"""
import collections
import json
import pathlib
import sys

DEFAULT = pathlib.Path.home() / ".local/share/godot/app_userdata/Vagnstrid/server_log.jsonl"
MODES = (("_koth", "King of the Hill"), ("_thunder", "Thunder Road"), ("_free", "Free fight"))


def mode_of(scenario: str) -> str:
    return next((name for tag, name in MODES if tag in scenario), "Other")


def main() -> None:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    events = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    votes, mode_votes, wins = collections.Counter(), collections.Counter(), collections.Counter()
    played, lengths, players = collections.Counter(), collections.defaultdict(list), []
    names = set()
    for e in events:
        if e["ev"] == "vote":
            for s, n in e.get("votes", {}).items():
                votes[s] += n
                mode_votes[mode_of(s)] += n
            wins[e["winner"]] += 1
        elif e["ev"] == "match_end":
            played[e["scenario"]] += 1
            lengths[e["scenario"]].append(e["length_s"])
            players.append(e["players"])
        elif e["ev"] == "match_start":
            names.update(e.get("names", []))
    print(f"{path}: {len(events)} events, {sum(played.values())} matches, {len(names)} different players")
    if players:
        print(f"players per match: average {sum(players) / len(players):.1f}, most {max(players)}")
    print("\nVotes per mode:")
    for m, n in mode_votes.most_common():
        print(f"  {m:20} {n}")
    print("\nScenario               votes  won  played  average length")
    for s in sorted(set(votes) | set(played) | set(wins), key=lambda s: -votes[s]):
        ls = lengths[s]
        avg = f"{sum(ls) / len(ls) / 60:.0f} min" if ls else "-"
        print(f"  {s:22} {votes[s]:5} {wins[s]:4} {played[s]:7}  {avg}")


if __name__ == "__main__":
    main()
