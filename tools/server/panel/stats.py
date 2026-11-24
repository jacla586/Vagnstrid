#!/usr/bin/env python3
"""Popularity statistics from the dedicated server's log (server_log.jsonl).

Players are told apart by name (case-insensitive; there are no accounts). A session runs
from a player's "hello" to their "leave"; a server restart ("server_start") or the end of
the log closes open sessions at the last line seen before it ("online" lines every 2
minutes keep that close). Only humans are ranked: bots' kills of each other are counted,
nothing more.

  python3 stats.py <server_log.jsonl> [--since 2026-11-28T08:00] [--until ...]   # JSON out
"""
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

BUCKET_MIN = 5          # players-online series: one point per this many minutes
MIN_SHOTS_FOR_ACCURACY = 10


def parse_time(text):
    """ISO time (the log's "...Z", or a local "2026-11-28T08:00" from the panel) -> aware UTC."""
    if not text:
        return None
    text = text.strip().replace("Z", "+00:00")
    t = datetime.fromisoformat(text)
    if t.tzinfo is None:
        t = t.astimezone()   # local time on this machine
    return t.astimezone(timezone.utc)


def iso(t):
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if t else None


def read_events(path):
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                    e["_t"] = parse_time(e.get("t"))
                except (ValueError, TypeError):
                    continue
                if e["_t"] is not None:
                    out.append(e)
    except FileNotFoundError:
        pass
    out.sort(key=lambda e: e["_t"])
    return out


def key_of(name):
    return (name or "").strip().lower()


def sessions_of(events):
    """[(name, start, end)] from hello/leave, closed by restarts and the log's end."""
    open_by_peer = {}     # peer -> (name, start)
    done = []
    last_t = None
    for e in events:
        ev = e.get("ev")
        t = e["_t"]
        if ev == "server_start":
            for name, start in open_by_peer.values():
                done.append((name, start, max(start, last_t or start)))
            open_by_peer.clear()
        elif ev == "hello" and e.get("name"):
            open_by_peer[e.get("peer")] = (e["name"], t)
        elif ev == "leave":
            s = open_by_peer.pop(e.get("peer"), None)
            if s:
                done.append((s[0], s[1], t))
        last_t = t
    for name, start in open_by_peer.values():
        done.append((name, start, max(start, last_t or start)))
    return done


def clip(sessions, since, until):
    out = []
    for name, a, b in sessions:
        if since:
            a = max(a, since)
        if until:
            b = min(b, until)
        if b > a:
            out.append((name, a, b))
    return out


def online_series(sessions, since, until):
    """Players online: the most at once in each BUCKET_MIN bucket, plus the peak."""
    if not sessions:
        return [], 0, None
    edges = []
    for _, a, b in sessions:
        edges.append((a, 1))
        edges.append((b, -1))
    edges.sort(key=lambda x: (x[0], x[1]))   # a leave before a join at the same instant
    start = since or edges[0][0]
    end = until or edges[-1][0]
    start = start.replace(second=0, microsecond=0)
    start -= timedelta(minutes=start.minute % BUCKET_MIN)
    step = timedelta(minutes=BUCKET_MIN)
    n_buckets = max(1, int((end - start) / step) + 1)
    if n_buckets > 2000:   # very long ranges: wider buckets
        step = (end - start) / 2000
        n_buckets = 2001
    peaks = [0] * n_buckets
    now = 0
    peak, peak_t = 0, None
    i = 0
    for t, d in edges:
        # the level held until t counts for every bucket it spans
        bi = min(n_buckets - 1, max(0, int((t - start) / step)))
        while i < bi:
            peaks[i] = max(peaks[i], now)
            i += 1
        peaks[bi] = max(peaks[bi], now)
        now += d
        peaks[bi] = max(peaks[bi], now)
        if now > peak:
            peak, peak_t = now, t
    while i < n_buckets:
        peaks[i] = max(peaks[i], now)
        i += 1
    series = [{"t": iso(start + step * k), "players": peaks[k]} for k in range(n_buckets)]
    return series, peak, peak_t


def minutes_by_hour(sessions):
    """Person-minutes per hour of day (local time of this machine)."""
    hours = [0.0] * 24
    for _, a, b in sessions:
        t = a
        while t < b:
            local = t.astimezone()
            nxt = (local.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)).astimezone(timezone.utc)
            seg_end = min(b, nxt)
            hours[local.hour] += (seg_end - t).total_seconds() / 60.0
            t = seg_end
    return [round(h, 1) for h in hours]


def minutes_by_day(sessions):
    days = defaultdict(float)
    players = defaultdict(set)
    for name, a, b in sessions:
        t = a
        while t < b:
            local = t.astimezone()
            nxt = (local.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)).astimezone(timezone.utc)
            seg_end = min(b, nxt)
            d = local.strftime("%Y-%m-%d")
            days[d] += (seg_end - t).total_seconds() / 60.0
            players[d].add(key_of(name))
            t = seg_end
    return [{"day": d, "minutes": round(days[d], 1), "players": len(players[d])} for d in sorted(days)]


def compute(events, since=None, until=None, now=None):
    now = now or datetime.now(timezone.utc)
    sessions = clip(sessions_of(events), since, until)
    in_range = [e for e in events if (not since or e["_t"] >= since) and (not until or e["_t"] <= until)]

    # --- People and time ---
    display = {}          # key -> the name as last written
    minutes = Counter()
    session_count = Counter()
    longest = None
    for name, a, b in sessions:
        k = key_of(name)
        display[k] = name
        m = (b - a).total_seconds() / 60.0
        minutes[k] += m
        session_count[k] += 1
        if longest is None or m > longest[1]:
            longest = (name, m, a)
    series, peak, peak_t = online_series(sessions, since, until)
    person_minutes = sum(minutes.values())
    lengths = sorted((b - a).total_seconds() / 60.0 for _, a, b in sessions)

    # --- Fighting ---
    p = defaultdict(lambda: Counter())     # key -> counters
    pairs = Counter()                      # (killer key, victim key) among humans
    weapons = Counter()
    killer_tanks = Counter()
    bot_tanks_killing = Counter()
    first_blood = None
    totals = Counter()
    for e in in_range:
        ev = e.get("ev")
        if ev == "kill":
            kh, vh = e.get("killer_human"), e.get("victim_human")
            kk, vk = key_of(e.get("killer")), key_of(e.get("victim"))
            if kh:
                display.setdefault(kk, e.get("killer"))
                p[kk]["kills"] += 1
                p[kk]["human_kills" if vh else "bot_kills"] += 1
                weapons[e.get("weapon") or "gun"] += 1
                if e.get("killer_tank"):
                    killer_tanks[e["killer_tank"]] += 1
                totals["humans_killed_by_humans" if vh else "bots_killed_by_humans"] += 1
                if vh:
                    pairs[(kk, vk)] += 1
                if first_blood is None:
                    first_blood = {"killer": e.get("killer"), "victim": e.get("victim"),
                                   "victim_human": bool(vh), "tank": e.get("killer_tank"),
                                   "scenario": e.get("scenario"), "t": e.get("t")}
            if vh:
                display.setdefault(vk, e.get("victim"))
                p[vk]["deaths"] += 1
                if not kh:
                    p[vk]["deaths_by_bots" if e.get("killer") == "Bot" else "deaths_other"] += 1
                    if e.get("killer") == "Bot":
                        totals["humans_killed_by_bots"] += 1
                        if e.get("killer_tank"):
                            bot_tanks_killing[e["killer_tank"]] += 1
            for a in e.get("assists") or []:
                p[key_of(a)]["assists"] += 1
                display.setdefault(key_of(a), a)
        elif ev == "match_end":
            totals["bot_vs_bot_kills"] += int(e.get("bot_kills") or 0)
            for name, g in (e.get("gunnery") or {}).items():
                k = key_of(name)
                for f in ("shots", "hits", "pens", "ricochets"):
                    p[k][f] += int(g.get(f, 0))
            winner = e.get("winner", -2)
            for row in e.get("humans") or []:
                if not isinstance(row, list) or len(row) < 2:
                    continue
                k = key_of(str(row[0]))
                p[k]["matches"] += 1
                if isinstance(winner, (int, float)) and winner >= 0 and int(row[1]) == int(winner):
                    p[k]["wins"] += 1

    players = []
    for k in set(minutes) | set(p):
        c = p[k]
        shots = c["shots"]
        players.append({
            "name": display.get(k, k),
            "minutes": round(minutes[k], 1),
            "sessions": session_count[k],
            "kills": c["kills"], "human_kills": c["human_kills"], "bot_kills": c["bot_kills"],
            "deaths": c["deaths"], "deaths_by_bots": c["deaths_by_bots"], "assists": c["assists"],
            "kd": round(c["kills"] / c["deaths"], 2) if c["deaths"] else None,
            "shots": shots, "hits": c["hits"], "pens": c["pens"], "ricochets": c["ricochets"],
            "accuracy": round(c["hits"] / shots, 3) if shots >= MIN_SHOTS_FOR_ACCURACY else None,
            "matches": c["matches"], "wins": c["wins"],
            "kills_per_hour": round(c["kills"] / (minutes[k] / 60.0), 1) if minutes[k] >= 10 else None,
        })
    players.sort(key=lambda r: (-r["kills"], -r["assists"], r["deaths"], -r["minutes"]))

    # --- Tanks, maps, matches ---
    deploys = Counter()
    fav = defaultdict(Counter)
    matches = Counter()
    match_minutes = Counter()
    votes = Counter()
    human_matches = 0
    for e in in_range:
        ev = e.get("ev")
        if ev == "deploy":
            deploys[e.get("tank") or "?"] += 1
            fav[key_of(e.get("name"))][e.get("tank") or "?"] += 1
        elif ev == "match_end" and int(e.get("players") or 0) > 0:
            human_matches += 1
            matches[e.get("scenario")] += 1
            match_minutes[e.get("scenario")] += (e.get("length_s") or 0) / 60.0
        elif ev == "vote":
            for s, n in (e.get("votes") or {}).items():
                votes[s] += int(n)
    for r in players:
        f = fav.get(key_of(r["name"]))
        r["favourite_tank"] = f.most_common(1)[0][0] if f else None

    # --- Fun facts ---
    def best(field, min_field=None, minimum=0, reverse=True):
        rows = [r for r in players if r.get(field) is not None and (not min_field or r[min_field] >= minimum)]
        if not rows:
            return None
        r = (max if reverse else min)(rows, key=lambda r: r[field])
        return {"name": r["name"], "value": r[field]} if r[field] else None

    nemesis = None
    if pairs:
        (kk, vk), n = pairs.most_common(1)[0]
        nemesis = {"killer": display.get(kk, kk), "victim": display.get(vk, vk), "kills": n}
    facts = {
        "first_blood": first_blood,
        "nemesis": nemesis,
        "longest_session": {"name": longest[0], "minutes": round(longest[1], 1), "t": iso(longest[2])} if longest else None,
        "most_played": best("minutes"),
        "sharpshooter": best("accuracy"),
        "ricochet_king": best("ricochets"),
        "bot_hunter": best("bot_kills"),
        "team_player": best("assists"),
        "most_killed_by_bots": best("deaths_by_bots"),
        "deadliest_bot_tank": ({"tank": bot_tanks_killing.most_common(1)[0][0],
                                "kills": bot_tanks_killing.most_common(1)[0][1]} if bot_tanks_killing else None),
    }

    return {
        "ok": True,
        "range": {"since": iso(since), "until": iso(until), "now": iso(now),
                  "first_event": iso(events[0]["_t"]) if events else None,
                  "last_event": iso(events[-1]["_t"]) if events else None},
        "totals": {
            "unique_players": len(minutes),
            "peak_concurrent": peak, "peak_at": iso(peak_t),
            "person_minutes": round(person_minutes, 1),
            "sessions": len(sessions),
            "median_session_min": round(lengths[len(lengths) // 2], 1) if lengths else 0,
            "matches_with_players": human_matches,
            "human_kills": sum(r["kills"] for r in players),
            "bots_killed_by_humans": totals["bots_killed_by_humans"],
            "humans_killed_by_humans": totals["humans_killed_by_humans"],
            "humans_killed_by_bots": totals["humans_killed_by_bots"],
            "bot_vs_bot_kills": totals["bot_vs_bot_kills"],
            "shots": sum(r["shots"] for r in players),
            "ricochets": sum(r["ricochets"] for r in players),
        },
        "online": series,
        "minutes_by_hour": minutes_by_hour(sessions),
        "by_day": minutes_by_day(sessions),
        "players": players,
        "tanks": [{"tank": t, "deploys": n, "kills": killer_tanks.get(t, 0)} for t, n in deploys.most_common()]
                 + [{"tank": t, "deploys": 0, "kills": n} for t, n in killer_tanks.items() if t not in deploys],
        "scenarios": [{"scenario": s, "matches": matches.get(s, 0), "minutes": round(match_minutes.get(s, 0), 1),
                       "votes": votes.get(s, 0)} for s in sorted(set(matches) | set(votes),
                                                                  key=lambda s: (-matches.get(s, 0), -votes.get(s, 0)))],
        "weapons": dict(weapons),
        "facts": facts,
    }


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    since = until = None
    if "--since" in argv:
        since = parse_time(argv[argv.index("--since") + 1])
    if "--until" in argv:
        until = parse_time(argv[argv.index("--until") + 1])
    print(json.dumps(compute(read_events(argv[0]), since, until), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
