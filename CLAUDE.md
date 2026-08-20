# Claude guidance for fujinet-intv-golf

Tenth FujiNet netplay port (PGA Golf, Mattel 1979), the second 2-4 player
one (after Bowling). **Read `PORTING.md` before touching anything** — it
is the accumulated methodology of all ten ports; `spikes/NOTES.md` has
this cart's evidence trail (the timer-virtualization vs native-dispatch
decision, the recon false-positive that still needed patching, the
TRACE_RING-based lagcheck redesign, the server_diff.py 4-seat fix).

**Working. Every automated gate in the ladder passes, run for real this
session**: `verify-org` → `verify-patch` (36 words) → `check-7000` →
every build variant assembles clean → live boot-dump matches the
recon-predicted state (§7.31) → `lagcheck` (peak 202/209 at shift=20) →
`det` (256/256 under stall, destination-phase asserted) → `echo-test`
(100 clean rounds) → `server-diff` (6/6 `--strict` clean) → `rig
PLAYERS=2` and `PLAYERS=4` (0 CRC mismatches) → `m4 PLAYERS=2`/`4`, both
ordinary and `QUIESCE=1` (fault genuinely repaired, not just CRC-clean)
→ `peerleft PLAYERS=2`/`4`, both leave modes → hardware images built
(`build/golf_net.rom`, `build/golf_nethud.rom`). **Not yet run on real
hardware** — that needs the user.

Hard rules, most of them learned the expensive way elsewhere:

- Never let any segment map `$7000`: the EXEC boot EXECUTES the word
  there. `make check-7000` guards it; the `NET_SESSION` block ORGs at
  `$D000`.
- Never put netcode RAM below `$8080` (STIC alias).
- Golf's three real timer entries are FULLY VIRTUALIZED (Bowling's
  model, not Sea Battle's native-dispatch shortcut — three real entries
  don't fit the "music placeholder + MASTER_TICK + native tail" shape
  that only has two slots free). `GF_ARM1/2/3` + `GF_CNT2` (only entry 2,
  interval 3, needs a countdown) are sim state: `LS_CKSUM` tail +
  `debug.asm TRACE_RANGES` + `resync.asm RS_TAILTBL` must stay in
  agreement, and any `IMG_*` change requires the §7.16 bounds sweep.
- The turn arbiter (`ARB_COMPUTE`, `src/hook.asm`) picks the ONE seat
  whose input reaches the sim each tick from `GF_CUR` ($016B, the game's
  own "whose turn" cell) — or hands the tick to `ARB_INJECT` while the
  EXEC's number-entry prompt (`GAME_TBL == GF_HTBL_PROMPT`) is up.
  Golf's handlers are controller-blind (only ever read R0, the event
  value), so suppression is a correctness requirement.
- Golf DOES poll (`$011F`/`$0120`, one walking-pointer site) — unlike
  Bowling, which polls nothing. Patching the walking pointer's BASE
  address without also patching its LOOP TERMINATOR (`$526D`'s
  `CMPI #$0121,R4`, `$011F`-relative) would walk the read off into
  unrelated RAM. Both are in the patch map.
- `r N` in jzIntv scripts counts INSTRUCTIONS (~200k/emulated second);
  breakpoint-forced injection is exploration-only (§7.17); exact-tick
  gates use the in-ROM `SCRIPT_TBL` or `TRACE_DONE` parks, never a
  breakpoint count.
- Rig scripts pkill `fujinet -u 127.0.0.1:1808` — never type that
  pattern in an interactive shell command line (`pkill -f` matches your
  own shell and kills it).
- The default FujiNet-workspace BOIP port (9995) may already be held by
  an unrelated project's long-running `fujinet-pc-rs232` instance on a
  shared workstation — `make echo-test` needs `FN_BOIP=` pointed at a
  free port with a matching `fnconfig.ini` edit if so; this is not a
  Golf-specific defect.

Gate ladder (each must pass before the next): verify-org → verify-patch
→ check-7000 → every build variant assembles → live boot-dump (§7.31) →
lagcheck → det (+ dest-phase) → echo-test → server-diff → rig
PLAYERS=2|4 → m4 (+ QUIESCE=1) PLAYERS=2|4 → peerleft PLAYERS=2|4 (both
leave modes) → hardware.

Assignments: production port 9111, FujiNet Lobby appkey 19, maxplayers 4.
The server (`server/intv_relay_server.py`) is protocol v2 (seat-tagged,
rooms), `MAX_SEATS=4`; `server/c/` is the generic C relay, held to
byte-for-byte equality by `tools/server_diff.py --seats 4` (this repo's
Python is pinned at 4, unlike Sea Battle's 2 — the tool's default/guard
had to be updated, see spikes/NOTES.md M3).

Known open item (not blocking): the exact swing/aim/power mechanic at
`$525E` was never fully reverse-engineered — real gameplay progression,
determinism, and multi-console lockstep are all confirmed working
regardless, but `SCRIPT_TBL` (`src/vdispatch.asm`) drives varied disc
holds rather than a claimed shot sequence, and the HUD/manual write-up
of "how it feels to actually play" is future work.
