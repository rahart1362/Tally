import os
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from canvas_synth.rebase import day_offset, rebase  # noqa: E402

UTC = timezone.utc


class Rebase(unittest.TestCase):
    def test_day_offset_uses_local_date(self):
        # 2026-10-05T03:00Z is still Oct 4 in Chicago -> +6 days, not +7.
        self.assertEqual(day_offset(datetime(2026, 10, 5, 3, 0, tzinfo=UTC), "America/Chicago"), 6)
        self.assertEqual(day_offset(datetime(2026, 9, 28, 13, 0, tzinfo=UTC), "America/Chicago"), 0)

    def test_wall_clock_preserved_across_dst(self):
        # 11:59:59 pm CDT on Oct 30 -> +7 days is Nov 6, 11:59:59 pm CST (DST ends Nov 1).
        self.assertEqual(rebase("2026-10-31T04:59:59Z", 7, "America/Chicago"), "2026-11-07T05:59:59Z")

    def test_dates_ids_urls_untouched_or_shifted(self):
        doc = {"id": "51842", "all_day_date": "2026-10-19", "html_url": "https://x.example/c?d=2026-09-28",
               "seconds_late": 3600, "due_at": None, "list": ["2026-09-28T13:00:00Z"]}
        out = rebase(doc, 2, "America/Chicago")
        self.assertEqual(out["id"], "51842")
        self.assertEqual(out["all_day_date"], "2026-10-21")
        self.assertEqual(out["html_url"], doc["html_url"])
        self.assertEqual(out["seconds_late"], 3600)
        self.assertIsNone(out["due_at"])
        self.assertEqual(out["list"], ["2026-09-30T13:00:00Z"])


if __name__ == "__main__":
    unittest.main()
