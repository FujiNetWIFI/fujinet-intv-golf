# PGA Golf — cart-specific evidence trail

Tenth FujiNet netplay port (PGA Golf, Mattel 1979), and the second 2–4
player one (after Bowling). Scaffolded from the Sea Battle tree (newest
server/tooling) with Bowling's turn-arbiter/4-player machinery re-imported.
Read `PORTING.md` first; this file is the cart-specific trail only.

## M0 — recon + scaffold

`tools/recon.py` against `rom/PGA Golf.bin` (renamed `rom/PGAGolf.bin`,
single-segment `$0000-$0FFF = $5000` cfg — the collection ROM's original
3-segment cfg was wrong for this 4K-word image) plus a `dis1600` pass.

- Header: timer table `$501C`, start-of-game `$5034`, `$500E=$01`
  (foreground/background — copied Auto Racing's `src/ui/text.asm` variant,
  not Sea Battle's colour-stack one).
- Timer table, 4 entries: slot 0 `$1A71` (music, stopped, `$8001`), slot 1
  `$54E6` int 1 (ball flight), slot 2 `$5718` int 3 (putting/roll), slot 3
  `$525E` int 1 (input wait / turn machinery — also where the polled
  `$011F`/`$0120` read lives).
- All 7 timer-API sites decoded: 3 ARM (`$525A`,`$5352`,`$535E`, all
  through `$181E` — recon's own generic "set timer countdown := interval"
  label, NOT the `$1844` `X_TIMER_START` other ports used) and 4 STOP
  (`$503B` the `.START` stop-all loop walking R1 across all 3 slots
  through one call site, plus `$527B`/`$53CE`/`$53D5` single-shot). No
  `$1831` SETCNT sites. **Grepped for hardcoded-literal countdown
  addresses ($0125-$013F in instruction context) — negative.** No §7.30
  hazard on this cart.
- RNG: 8 sites, both flavours — 4× `X_RAND1` (`$55FE`,`$5606`,`$564A`,
  `$5652`), 4× `X_RAND2` (`$52F9`,`$55A1`,`$55C4`,`$5BEE`).
- Input: ONE polled surface, a walking-pointer read at `$525F`
  (`MVII #$011F,R4`) draining `$011F` then `$0120`. `$035D` installs:
  `$506E`→`$51D3` (live table, boot) and `$5120`→`$1906` (EXEC null,
  game-over). Zero `$14F1` references (no cart `X_SCAN` self-call — §7.26
  doesn't apply). Zero `$0100`/`$0101` writes (no cart ISR dance — §7.10/
  §7.28 don't apply).
- Display: recon's 13 "STIC writes" are ALL class-1 false positives
  (`$50BF` is the middle of a 3-word JSR; `$5C20-$5D50` is graphics data
  dis1600 mis-decodes as instructions). Confirmed zero real STIC writes —
  fully static display, Baseball/Bowling-form `RS_DISPLAY_RESET` applies.

**A second recon false-positive nearly cost a real bug, not just a label
mixup**: `$526D`'s `CMPI #$0121,R4` looked like recon's class-2 "loop-bound
compare, not a read" false positive (correctly so — it IS a loop
terminator, not a keypad read), and the plan's first draft dismissed it
as "nothing to patch there." Wrong: the terminator is `$011F`-RELATIVE
(base `+2`), so patching the walking pointer's start address without
ALSO patching this terminator would walk R4 through unrelated shadow RAM
until it happened to collide with the literal `$0121` by chance — a
correctly-classified false positive whose ADDRESS still needed patching,
just not for the reason recon's generic label suggested. Caught before
building anything, by re-deriving what the loop actually does rather than
trusting the label. **Both `$5260` (base) and `$526E` (terminator) are in
the patch map** (36 words total, `tools/patches.py`).

## M1 — patch map + hook, live boot-dump confirmation (§7.31)

Golf's three real timer entries are FULLY VIRTUALIZED (Bowling's model),
not native-dispatched (Sea Battle's model): Sea Battle could leave two
entries native because exactly two slots remained after the music
placeholder + `MASTER_TICK`; Golf has THREE real entries and only two
slots would remain under the same shape. `NEW_TIMER_TBL` is the minimal
2-entry form (music placeholder, `MASTER_TICK`) and `GF_GAME_TICK`
hand-reproduces all three in original table order with exact EXEC reload
semantics. This also sidesteps §7.30 entirely (confirmed no hardcoded
countdown writes exist to relocate).

`make verify-patch` reports exactly 36 declared sites. `make hook`/`virt`/
`lag`/`lag0`/`det_a`/`det_b`/`echo`/`rec`/`net`/`net1-4`/`nethud` all
assembled clean on the FIRST attempt after two symbol-availability fixes
(`EXEC_KP_L/R`, `SC_ISR_SAVE`/`SC_ISR_BODY` needed by the shared
`vdispatch.asm`/`resync.asm` even though this cart doesn't use keypad
polling or a cart ISR — Sea Battle's own precedent: harmless structural
no-ops, not custom code) and one hardcoded filename (`src/core.asm`'s
`INCLUDE "build/seabattle_patched.asm"` → `golf_patched.asm`).

**§7.31 live boot-dump check, run for real** (mandatory per the Sea Battle
lesson: a green `make det` on a build that never advances proves
nothing). A `det_a` build with SPIKE_SCRIPT driving Sea Battle's OWN
leftover `SCRIPT_TBL` content (still assembled at that point, not yet
rewritten for Golf) was run to `TRACE_DONE`:

```
GAME_TBL = $51D3   (GF_HTBL_LIVE, NOT the boot prompt table $51DD)
$0161    = $0002   (GF_PCOUNT — exactly NET_COUNT's local-build default)
$016C    = $0001   (GF_HOLE — advanced from its 0 boot value)
$0183/84 = $0001   (GF_LIE/GF_LIE_PREV — real terrain codes, not boot-zero)
ARB_INJ ($819F) = $0006  (frozen exactly at the ENTER tick — the injector
                           fired digit-then-ENTER and then correctly
                           stopped being invoked once GAME_TBL moved off
                           the prompt)
GF_ARM1/2/3, GF_CNT2 all sane (0/0/0 armed, CNT2=3 freshly reloaded)
```

This is strong, first-attempt confirmation that `NEW_TIMER_TBL` +
`GF_GAME_TICK` + `ARB_COMPUTE` + `ARB_INJECT` all work end to end. The
event-code guess for `ARB_INJECT` (digit N → raw value N, ENTER → `$0B`,
both landing on VD_TMP slot 2) was NOT arbitrary: Sea Battle's own
`SCRIPT_TBL` comments record a LIVE-MEASURED confirmation of the
identical encoding (`$81` = fresh key "1", `$8B` = ENTER, both dispatched
through slot 2) on a DIFFERENT cart, because the number-entry prompt and
`LS_VDISPATCH`'s decode are EXEC-standard, not cart-derived — this is the
first port where a keypad-injection encoding could be inherited from a
sibling's measurement instead of purely guessed, and it worked first try.

## M2 — interception + timing measurement

Two-point cycle sample at `MASTER_TICK` (built `hook` ROM, three
consecutive breakpoint hits): 230547 → 275349 → 320151 cycles. Delta
44802 cycles = **exactly 3.000 NTSC frames = 20.0 Hz**, matching Armor
Battle's "cleanest cadence" calibration point — no ISR-dance surprise
(consistent with the M0 finding of zero `$0100`/`$0101` writes). `d=3`
costs 150 ms, the family default already baked into
`server/intv_relay_server.py`'s `DEFAULT_DELAY`.

**`run_lagcheck.sh` rewritten around the TRACE_RING checksum, not a
hand-picked game cell** — a new approach for this family. Golf's exact
swing/aim field offsets were not reverse-engineered this session (the
`$525E` poll's SWAP/SLLC/CMPI pattern near `$5261`/`L_527E` didn't yield
to a quick read, and the M1 result already showed generic disc variation
is enough to drive real progress without knowing the exact mechanic), so
picking a Sea-Battle-style "MOB velocity field" address by analogy would
have been a guess dressed as measurement. Instead `main_lag.asm`/
`main_lag0.asm` both carry `SPIKE_TRACE` (previously off for lag builds
family-wide) with `TRACE_STOP=250` — under 256 so the ring never wraps
and index *i* is tick *i* directly, no lap ambiguity. Cross-correlating
the FULL per-tick state checksum sequence between the d=0 and d=20 builds
doesn't require knowing WHAT input does, only that the whole timeline is
a d-tick-later copy of itself. First attempt with `TRACE_STOP=300` (over
256, so the dumped "last lap" silently dropped the first ~44 ticks
including the entire settle row) scored a false peak at shift=0;
dropping to 250 fixed it immediately. Result: **peak agreement 202/209 at
shift=20, vs a 105/209 median baseline and 40/209 at shift=0** — a sharp,
isolated peak, unambiguous PASS.

**Generalize**: for any future cart where the swing/aim/action field
isn't independently known, the TRACE_RING cross-correlation is a strictly
more robust `lagcheck` signal than a guessed game cell, and it's already
proven cart-agnostic machinery (the same ring `make det` uses) — consider
making it the DEFAULT `lagcheck` design for new ports, not a Golf-only
fallback.

## M3 — determinism, arbiter, RNG, server tooling

`GF_RAND1`/`GF_RAND2` (both flavours, Frog-Bog-shaped shared swap-in/
swap-out) wrap all 8 sites. `ARB_COMPUTE` is simpler than Bowling's (one
prompt table to check, one "whose turn" cell to read — no per-step
registration state machine): `GAME_TBL == GF_HTBL_PROMPT` → injector owns
the tick; otherwise `ARB_SEAT := GF_CUR AND 3`.

`make det`: **256/256 ticks identical under stall injection (9 frames/64,
`main_det_b.asm`), with the destination-phase assertion passing** (player
count 1-4, hole > 0 or `GAME_TBL == GF_HTBL_LIVE`) — real gameplay
coverage, not two runs stuck in the same wrong place.

`make echo-test`: **100 clean rounds**, `$8120 = $AA` (pass marker),
through `jzintv --fujinet` → an isolated `fujinet-pc-rs232` copy (BOIP
port had to be moved off the default 9995 — already held by an unrelated
long-running instance from another project on this machine; not a Golf
defect, just a shared-workstation collision, fixed with a per-run
`fnconfig.ini` port edit and `FN_BOIP=`).

`make server-diff`: **6/6 scenarios PASS, `--strict` clean** — but only
after fixing the tool itself. `tools/server_diff.py` (Sea-Battle-authored,
this repo's first use of it in a 4-seat context) defaulted to
`--seats 2` and HARD-REFUSED anything else with a comment asserting "this
repo's Python is pinned at MAX_SEATS=2" — stale the moment Golf's
`server/intv_relay_server.py` was retargeted to `MAX_SEATS=4`. The
`s2_rooms` scenario already had a `seats >= 3` branch (redirect into a
forming room) written in anticipation of exactly this need — Bowling
never exercised it because Bowling predates `server_diff.py`. Fixed by
changing the default/guard to 4; no scenario code needed to change. **A
real, if narrow, first-of-its-kind integration bug**: the C-relay-diff
tooling (introduced in Sea Battle, the 9th port) and 4-player seating
(introduced in Bowling, the 7th port) had never been exercised together
before this port.

## M4 — rig, both player counts

`make rig PLAYERS=2`: **PASS** — both seats correct, `NET_ACTIVE=1`,
`DIAG` all zero, `GAME_TBL=$51D3` (past the prompt) on both, player count
correctly 2 on both, 40 CRC rounds, 0 mismatches.

`make rig PLAYERS=4`: **PASS** — all four seats correct (0-3), full
4-name roster identical on every console, player count correctly 4
everywhere, 32 CRC rounds, 0 mismatches. The turn arbiter, the injector,
and the seat-generalized engine all work at a real 4-console fan-out on
the first attempt.

`test/run_rig.sh`'s verdict was rewritten from Sea Battle's own
`$0164`-keyed phase logic (meaningless for Golf) to the same player-
count/`GAME_TBL` destination-phase check used everywhere else in this
port — one shared assertion shape across `check_dest_phase.py`,
`run_rig.sh`, and `run_m4.sh`, instead of three cart-specific ones.

`make lobby`: **PASS, both guest and host flows** — but only after a real
user-visible bug caught by actually reading the decoded screen output,
not just the PASS/FAIL lines. `src/netcode/session.asm` is "copy
unchanged" per PORTING §4 except for a handful of literal UI strings, and
three of them were still Soccer's: the title said `SOCCER NETPLAY`, the
matched-screen seat line said `YOU ARE TEAM n`, and the start hint said
`KICK OFF`. A fourth, `WAITING ROOM   OF 2`, was subtler: it is a
compile-time-constant template (the member count gets written into one
column; the "OF n" trailing text never changes at runtime), so `OF 2` was
simply WRONG for a 4-seat game regardless of how many players actually
joined — confirmed against Bowling's own `session.asm`, which uses the
literal `OF 4` for exactly this reason. All four fixed (`GOLF NETPLAY`,
`YOU ARE PLAYER n`, `TEE OFF`, `OF 4`), `test/run_lobby.sh`'s string
assertions updated to match, hardware images rebuilt. **Generalize**: a
file being "copy unchanged" at the CODE level does not mean its literal
UI STRINGS are cart-agnostic — grep every `STRING` in a copied file for
the donor cart's own name/terminology/constants, not just the symbols.

## M5 — desync recovery + drop, both player counts

Fault target: `GF_STROKES` seat 0 (`$0162`, current hole's stroke count)
— inside the CRC range, unambiguously a scoreboard number a player would
notice, poked to `$77` on console 2 mid-run.

`make m4 PLAYERS=2`/`PLAYERS=4`, ordinary runs: **PASS**, and BOTH runs'
host reported `RS_GATE=1` (quiescent) **organically**, after only 1 tick
of `RS_PTMO` — Golf's quiescent condition (`GF_ARM1==0 AND GF_ARM2==0`,
"neither physics entry armed": a wide, frequent resting window between
strokes, not a narrow transition instant) turns out to be true so often
in ordinary play that the deliberate `QUIESCE=1` forcing mode almost
wasn't needed to prove the branch. Ran it anyway (both player counts) per
PORTING.md §7.29 — **PASS**, `RS_GATE=1` confirmed under forced
`GF_ARM1:=0`/`GF_ARM2:=0` (repeated across a 60×50000-instruction window,
not a one-shot poke — the derived flag is recomputed every tick in
`GF_GAME_TICK`, so a single force is overwritten within one tick, the
same lesson every prior port's forcing mode already learned). The fault
value was confirmed GONE (not just CRC-clean) on every console after
recovery.

`make peerleft PLAYERS=2`/`PLAYERS=4`, both `LEAVE_MODE=clean` and
`=timeout`: **PASS, unchanged from the copied script** — `test/
run_peerleft.sh` needed ZERO cart-specific edits. Every cell it reads
(`PEER_SCR`, `PEER_WHY`, `DIAG_*`, `LEFT_NAME`, the BACKTAB decode
formula) is family-standard, and the fg/bg `text.asm` variant's GRAM
layout matches the shared decode convention exactly — "PLAYER LEFT" /
"CONNECTION LOST" / "PRESS RESET" / the leaver's name all decoded
correctly first try, at both player counts.

## M6 — hardware images

`make rom SRV_HOST=fujinet.online SRV_PORT=9111` → `build/golf_net.rom`
and `make rom-hud` → `build/golf_nethud.rom`, both built clean. Segments:
`$5000` (patched original, 4K), `$6000` (hook/vdispatch/mailbox, ~$3C5
words), `$D000` (session/lockstep/resync/hud/text, ~$C3F words) — nowhere
near `$7000`, `make check-7000` clean throughout every build in this
session. **Not yet handed to real hardware** — that step needs the user.

## Open items for a future session

- The exact swing/aim/power mechanic at `$525E` (the `$011F`/`$0120`
  poll's SWAP/SLLC/CMPI-`$002C` pattern near `$5261`) was never fully
  decoded. Everything downstream still works (real hole progression,
  correct lie codes, clean `det`/`rig`/`m4` under both plain fuzz AND a
  hand-written varied-disc script), so this is a POLISH item (knowing the
  exact control feel for the HUD/manual write-up), not a correctness gap
  — but PORTING.md §5.5 says measure before trusting further, so
  `SCRIPT_TBL`'s current content is deliberately conservative (varied
  disc holds, not a claimed shot sequence) and the injector's event-code
  choice, while independently confirmed via a sibling cart's live
  measurement, has not been re-confirmed by forcing raw port reads on
  THIS cart's own live scan.
- BACKTAB-as-physics-input ($553B reads the course card back from
  `$0200+n` to decide `GF_LIE`) is NOT in `TRACE_RANGES`/`LS_CKSUM`
  directly, matching every prior port's BACKTAB-is-display-only
  assumption. It converged cleanly through `make det`'s stall injection
  regardless (GF_LIE, which IS checksummed, matched exactly across both
  runs), which is decent indirect evidence the read-back is
  deterministic, but a dedicated audit (does the ISR ever touch
  `$0200-$02EF` outside of BACKTAB's normal scroll-free static case; does
  the read-back happen at a fixed point in the tick) was not done. Worth
  writing up as a new PORTING.md hazard class regardless of outcome —
  BACKTAB has never before been anything but pure display for this
  family.
- Real hardware confirmation (two PiRTO IIs, HUD numbers) is still
  outstanding, same as every port's final step.
