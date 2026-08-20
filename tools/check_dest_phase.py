#!/usr/bin/env python3
"""Destination-phase assertion (PORTING.md §5.5, §7.25).

A CRC gate PASS can be two consoles identically stuck in the same wrong
place -- the checksum compare cannot see that. Golf's boot state is the
EXEC's own number-entry prompt, which masked ($3F, disc-only) fuzz can
NEVER answer on its own; the only way past it is ARB_INJECT (a keypad
digit + ENTER, driven from sim state -- src/hook.asm). A run that somehow
never got the injector wired up correctly would park on the prompt
forever, with $0161 stuck at 0 and every checksum agreeing trivially.

** CONFIRMED LIVE (spikes/NOTES.md M1): ** a run with NO script content
driving the prompt still landed $0161 (GF_PCOUNT) at NET_COUNT, moved off
GF_HTBL_PROMPT ($51DD) onto GF_HTBL_LIVE ($51D3), and advanced $016C
(GF_HOLE) from its boot value of 0 -- the strongest "real gameplay ran"
signal available without a live-scan measurement session for the exact
swing/aim mechanic (M2 TODO).

Usage: check_dest_phase.py build/det_a.out [...]
"""
import re
import sys

DUMP_RE = re.compile(r"^([0-9A-F]{4}):((?:\s+[0-9A-F]{4}\*?){1,8})\s*#", re.M)

GF_HTBL_PROMPT = 0x51DD
GF_HTBL_LIVE = 0x51D3


def check(path):
    text = open(path).read()
    mem = {}
    for m in DUMP_RE.finditer(text):
        addr = int(m.group(1), 16)
        for i, w in enumerate(m.group(2).split()):
            mem[addr + i] = int(w.rstrip("*"), 16)

    fail = []
    if not mem:
        return [f"{path}: no memory dumps found"]

    pcount = mem.get(0x161)
    hole = mem.get(0x16C)
    tbl_lo = mem.get(0x80C0)
    tbl_hi = mem.get(0x80C1)
    table = None
    if tbl_lo is not None and tbl_hi is not None:
        table = tbl_lo | (tbl_hi << 8)

    if pcount is None:
        fail.append("no $0161 dump found (the run script must dump $0160-$016F)")
    elif not (1 <= pcount <= 4):
        fail.append(f"GF_PCOUNT ($0161) = {pcount}, expected 1-4 -- the "
                    f"player-count prompt was never answered (ARB_INJECT "
                    f"never fired, or fired with a wrong event code)")

    if table == GF_HTBL_PROMPT:
        fail.append("GAME_TBL still points at GF_HTBL_PROMPT ($51DD) -- "
                    "parked on the player-count prompt; every checksum "
                    "agrees trivially")

    if hole is None:
        fail.append("no $016C dump found (the run script must dump $0160-$016F)")
    elif hole == 0 and table != GF_HTBL_LIVE:
        fail.append("GF_HOLE ($016C) still 0 and GAME_TBL is not "
                    "GF_HTBL_LIVE -- no real gameplay progress observed")

    if not any(mem.get(a, 0) for a in range(0x31D, 0x35D)):
        fail.append("object table $031D-$035C all zero -- nothing was ever "
                    "populated")

    if fail:
        return [f"{path}: {f}" for f in fail]

    tbl_note = f" (GAME_TBL=${table:04X})" if table is not None else ""
    print(f"DEST-PHASE OK ({path}): player count = {pcount}, "
          f"hole = {hole}{tbl_note}")
    return []


problems = []
for arg in sys.argv[1:] or ["build/det_a.out"]:
    problems += check(arg)

if problems:
    print("DEST-PHASE FAIL:")
    for p in problems:
        print("  -", p)
    sys.exit(1)
