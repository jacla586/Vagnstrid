"""python3 -m unittest discover tools/server/panel/tests"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import stats  # noqa: E402

LOG = [
    {"ev": "server_start", "t": "2026-11-28T09:59:00Z"},
    {"ev": "hello", "peer": 1, "name": "Anna", "t": "2026-11-28T10:00:00Z"},
    {"ev": "hello", "peer": 2, "name": "Bertil", "t": "2026-11-28T10:10:00Z"},
    {"ev": "deploy", "name": "Anna", "team": 0, "tank": "T-34", "t": "2026-11-28T10:00:30Z"},
    {"ev": "deploy", "name": "bertil", "team": 1, "tank": "KV-2", "t": "2026-11-28T10:10:30Z"},
    {"ev": "kill", "killer": "Anna", "killer_human": True, "killer_tank": "T-34", "victim": "Bot",
     "victim_human": False, "victim_tank": "BT-7", "weapon": "gun", "assists": [], "t": "2026-11-28T10:05:00Z"},
    {"ev": "kill", "killer": "Anna", "killer_human": True, "killer_tank": "T-34", "victim": "Bertil",
     "victim_human": True, "victim_tank": "KV-2", "weapon": "gun", "assists": [], "t": "2026-11-28T10:12:00Z"},
    {"ev": "kill", "killer": "Bot", "killer_human": False, "killer_tank": "Pz IV", "victim": "Bertil",
     "victim_human": True, "victim_tank": "KV-2", "weapon": "Bazooka", "assists": ["Anna"], "t": "2026-11-28T10:15:00Z"},
    {"ev": "match_end", "scenario": "campus_koth", "players": 2, "length_s": 1200, "winner": 0, "bot_kills": 7,
     "humans": [["Anna", 0, 2, 0, 100, 0], ["Bertil", 1, 0, 2, 10, 0]],
     "gunnery": {"Anna": {"shots": 12, "hits": 6, "pens": 4, "ricochets": 1},
                 "Bertil": {"shots": 3, "hits": 0, "pens": 0, "ricochets": 0}}, "t": "2026-11-28T10:18:00Z"},
    {"ev": "vote", "votes": {"linghem_free": 2}, "ballots": {"Anna": "linghem_free", "Bertil": "linghem_free"},
     "voters": 2, "players": 2, "winner": "linghem_free", "tie": False, "no_votes": False, "t": "2026-11-28T10:18:30Z"},
    {"ev": "vote", "votes": {"campus_koth": 1, "vidingsjo_thunder_red": 1},
     "ballots": {"Anna": "campus_koth", "Bertil": "vidingsjo_thunder_red"}, "voters": 2, "players": 3,
     "winner": "campus_koth", "tie": True, "no_votes": False, "t": "2026-11-28T10:19:30Z"},
    {"ev": "leave", "peer": 1, "name": "Anna", "t": "2026-11-28T10:20:00Z"},
    {"ev": "leave", "peer": 2, "name": "Bertil", "t": "2026-11-28T10:30:00Z"},
    {"ev": "hello", "peer": 3, "name": "Cecilia", "t": "2026-11-28T11:00:00Z"},
    {"ev": "online", "players": 1, "names": ["Cecilia"], "t": "2026-11-28T11:04:00Z"},
    {"ev": "server_start", "t": "2026-11-28T12:00:00Z"},
]


def events():
    out = []
    for e in LOG:
        e = dict(e)
        e["_t"] = stats.parse_time(e["t"])
        out.append(e)
    return out


class StatsTest(unittest.TestCase):
    def test_people_and_time(self):
        s = stats.compute(events())
        t = s["totals"]
        self.assertEqual(t["unique_players"], 3)
        self.assertEqual(t["peak_concurrent"], 2)
        self.assertEqual(t["peak_at"], "2026-11-28T10:10:00Z")
        self.assertAlmostEqual(t["person_minutes"], 44.0)   # 20 + 20 + 4 (crash: last line 11:04)
        self.assertEqual(t["sessions"], 3)
        self.assertEqual(max(p["players"] for p in s["online"]), 2)
        self.assertAlmostEqual(sum(s["minutes_by_hour"]), 44.0)

    def test_fighting(self):
        s = stats.compute(events())
        t = s["totals"]
        self.assertEqual(t["bots_killed_by_humans"], 1)
        self.assertEqual(t["humans_killed_by_humans"], 1)
        self.assertEqual(t["humans_killed_by_bots"], 1)
        self.assertEqual(t["bot_vs_bot_kills"], 7)
        rows = {r["name"]: r for r in s["players"]}
        anna, bertil = rows["Anna"], rows["Bertil"]
        self.assertEqual(s["players"][0]["name"], "Anna")
        self.assertEqual((anna["kills"], anna["human_kills"], anna["bot_kills"], anna["assists"]), (2, 1, 1, 1))
        self.assertEqual((bertil["deaths"], bertil["deaths_by_bots"], bertil["kills"]), (2, 1, 0))
        self.assertEqual(anna["accuracy"], 0.5)
        self.assertIsNone(bertil["accuracy"])          # under 10 shots
        self.assertEqual((anna["wins"], anna["matches"], bertil["wins"]), (1, 1, 0))
        self.assertEqual(anna["favourite_tank"], "T-34")
        self.assertEqual(bertil["favourite_tank"], "KV-2")   # deploy name case differs
        f = s["facts"]
        self.assertEqual(f["first_blood"]["killer"], "Anna")
        self.assertEqual(f["nemesis"], {"killer": "Anna", "victim": "Bertil", "kills": 1})
        self.assertEqual(f["deadliest_bot_tank"]["tank"], "Pz IV")
        self.assertEqual(s["weapons"], {"gun": 2})

    def test_votes(self):
        s = stats.compute(events())
        mv = s["map_votes"]
        self.assertEqual((mv["rounds"], mv["votes"]), (2, 4))
        self.assertAlmostEqual(mv["turnout"], 4 / 5)
        maps = {m["scenario"]: m for m in mv["maps"]}
        self.assertEqual(mv["maps"][0]["scenario"], "linghem_free")
        self.assertEqual((maps["linghem_free"]["votes"], maps["linghem_free"]["won"], maps["linghem_free"]["fans"]), (2, 1, 2))
        self.assertEqual((maps["campus_koth"]["won"], maps["campus_koth"]["won_by_lot"]), (0, 1))
        self.assertEqual({m["mode"]: m["votes"] for m in mv["modes"]},
                         {"Free fight": 2, "King of the Hill": 1, "Thunder Road": 1})
        rows = {r["name"]: r for r in s["players"]}
        self.assertEqual((rows["Anna"]["favourite_map"], rows["Anna"]["votes"]), ("linghem_free", 2))

    def test_range(self):
        s = stats.compute(events(), since=stats.parse_time("2026-11-28T10:15:00Z"),
                          until=stats.parse_time("2026-11-28T10:25:00Z"))
        self.assertAlmostEqual(s["totals"]["person_minutes"], 15.0)   # Anna 5 + Bertil 10
        self.assertEqual(s["totals"]["humans_killed_by_humans"], 0)
        self.assertEqual(s["totals"]["humans_killed_by_bots"], 1)

    def test_empty(self):
        s = stats.compute([])
        self.assertEqual(s["totals"]["unique_players"], 0)
        self.assertEqual(s["online"], [])


if __name__ == "__main__":
    unittest.main()
