"""Seeded, version-independent PRNG (SplitMix64).

Python's ``random`` is avoided on purpose so the output is byte-identical on
any Python 3 build. Sub-streams are derived from a label with SHA-256, so the
order in which personas or courses are generated never changes their data.
"""
from __future__ import annotations

import hashlib

MASK = (1 << 64) - 1
ALNUM = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"


class Rng:
    def __init__(self, seed: int):
        self.state = seed & MASK

    @classmethod
    def from_label(cls, root_seed: int, label: str) -> "Rng":
        h = hashlib.sha256(f"{root_seed}:{label}".encode()).digest()
        return cls(int.from_bytes(h[:8], "big"))

    def fork(self, label: str) -> "Rng":
        return Rng.from_label(self.state, label)

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return z ^ (z >> 31)

    def random(self) -> float:
        return (self.next_u64() >> 11) / float(1 << 53)

    def randint(self, a: int, b: int) -> int:
        return a + self.next_u64() % (b - a + 1)

    def uniform(self, a: float, b: float) -> float:
        return a + (b - a) * self.random()

    def choice(self, seq):
        return seq[self.next_u64() % len(seq)]

    def alnum(self, n: int) -> str:
        return "".join(ALNUM[self.next_u64() % 62] for _ in range(n))

    def hex(self, n: int) -> str:
        return "".join("0123456789abcdef"[self.next_u64() % 16] for _ in range(n))

    def uuid4(self) -> str:
        h = self.hex(32)
        h = h[:12] + "4" + h[13:16] + "89ab"[self.next_u64() % 4] + h[17:]
        return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"
