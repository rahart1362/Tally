"""Regenerating twice (different hash seeds) must be byte-identical, and the
committed tree must equal a fresh generation."""
import filecmp
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
COMMITTED = os.path.join(HERE, "..", "..", "fixtures", "canvas")


def gen(dest, hashseed):
    env = dict(os.environ, PYTHONHASHSEED=str(hashseed))
    subprocess.run([sys.executable, "-m", "canvas_synth", "generate", "--out", dest], cwd=HERE, env=env,
                   check=True, capture_output=True)


def tree(root):
    out = {}
    for d, _, files in os.walk(root):
        for f in files:
            p = os.path.join(d, f)
            with open(p, "rb") as fh:
                out[os.path.relpath(p, root)] = fh.read()
    return out


class Determinism(unittest.TestCase):
    def test_two_generations_identical(self):
        with tempfile.TemporaryDirectory() as t:
            a, b = os.path.join(t, "a"), os.path.join(t, "b")
            gen(a, 1)
            gen(b, 98765)
            ta, tb = tree(a), tree(b)
            self.assertEqual(sorted(ta), sorted(tb))
            diff = [k for k in ta if ta[k] != tb[k]]
            self.assertEqual(diff, [])
            if os.path.isdir(COMMITTED):
                tc = tree(COMMITTED)
                self.assertEqual(sorted(tc), sorted(ta), "committed tree differs from a fresh generation")
                self.assertEqual([k for k in ta if ta[k] != tc[k]], [])


if __name__ == "__main__":
    unittest.main()
