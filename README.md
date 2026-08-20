# PGA Golf (Mattel, 1979) — FujiNet netplay, 2-4 players

The tenth FujiNet netplay port of an EXEC-era Intellivision cart, and the
second with **more than two players** (after Bowling): 2-4 consoles run
the whole original PGA Golf in delay-based lockstep, matched through a
room-based lobby (first player hosts, others join their entry, host
presses ENTER to start with whoever is there). During the round the
**turn arbiter** ensures only the golfer whose turn it actually is can
affect the sim — Golf's own handlers only ever read the event value, not
which controller sent it, so an off-turn disc press would otherwise
silently steer the active golfer's shot. The player-count prompt at boot
is answered automatically from the room's size, on every console, from
sim state — no console has to guess or race to type it first.

## Status

All emulated gates PASS (2026-08-20):

| gate | result |
|---|---|
| `make verify-org` | byte-identical rebuild |
| `make verify-patch` | exactly the 36 declared words differ |
| `make check-7000` | no build maps `$7000` |
| live boot-dump (§7.31) | `GAME_TBL` moves off the boot prompt, player count lands correctly, hole number advances |
| `make lagcheck` | TRACE_RING cross-correlation peaks at shift=20 (202/209 agree vs a 105/209 baseline) |
| `make det` | 256/256 tick checksums identical under stall injection, dest-phase asserted |
| `make echo-test` | 100 clean transport rounds |
| `make server-diff` | 6/6 scenarios, `--strict` clean, 4 seats |
| `make lobby` | interactive lobby/room UI, guest AND host flows |
| `make rig PLAYERS=2\|4` | live lockstep, N-way CRC rounds verified, 0 mismatches |
| `make m4 PLAYERS=2\|4` (+ `QUIESCE=1`) | desync injected, host broadcast push, whole room rebases, fault value confirmed gone |
| `make peerleft PLAYERS=2\|4` | drop ends match for all, both leave modes, survivors name the leaver |

Not yet done: real-hardware bring-up (`make rom SRV_HOST=...`, PiRTO II,
HUD on, tune `d` from the L/S/T/R/H row) and a human `make run-hook` feel
playtest. The exact swing/aim/power control mechanic was not
reverse-engineered this session (see `spikes/NOTES.md`'s open items) —
real gameplay progression, determinism, and multi-console lockstep are
all confirmed working regardless.

## Build & run

Prereqs: as1600/dis1600/bin2rom (jzIntv SDK), jzIntv with `--fujinet`,
fujinet-pc-rs232 dist, Python 3.

```sh
make verify-org          # gate 0: the dump reassembles byte-identical
make run-hook             # play the patched-but-local build (feel test)
make rig PLAYERS=4        # full 4-console local netplay rig, headless
make rom SRV_HOST=fujinet.online   # hardware image -> build/golf_net.rom
make rom-hud              # same with the live HUD row (bring-up)
server/run_production.sh  # relay on :9111, registered on the FujiNet Lobby
```

Port 9111 / Lobby appkey 19 are Golf's assignments on the shared host.
The lobby username comes from the FujiNet Lobby appkey (creator 1/app
1/key 0), falling back to `GUESTnn`.

## What is different from the eight 2-player ports

- **Protocol v2** (`server/intv_relay_server.py`, seat-tagged), same as
  every 2-4 player port: INPUT and CRC frames carry the sender's seat;
  START carries seat + count + a 4-name roster; ROOM (membership
  broadcast) and GO (host start) frames; the relay fans every game frame
  out to all other room members and does the CRC compare N-way.
- **Seat-generalized engine**: one 256-cell ring page per seat, per-seat
  watermarks, gate = min over remote seats, `NET_SEAT`/`NET_COUNT`
  replace the binary role. N=2 runs the identical code path.
- **Turn arbiter** (`src/hook.asm ARB_COMPUTE`): the controlling seat is
  computed from sim state every tick — `GF_CUR` ($016B, the game's own
  0-based "whose turn" cell) — and ONLY that seat's events replay. While
  the EXEC's own number-entry prompt is up at boot, the tick instead goes
  to `ARB_INJECT`, which answers it deterministically from the room's
  player count.
- **Polled input, unlike Bowling**: Golf reads `$011F`/`$0120` directly
  (one walking-pointer site), so — like the 2-player ports — it needs a
  shadow-pair patch. Unlike them, the patch has to move BOTH the poll's
  starting address and its loop terminator together, since the
  terminator is expressed relative to the original base address.
- **Fully virtualized timer entries, unlike Sea Battle**: Sea Battle
  could leave two of its three entries dispatching natively because
  exactly two table slots remained free after the standard music
  placeholder + `MASTER_TICK`. Golf has three real entries, so — like
  Bowling — every entry is hand-reproduced in `GF_GAME_TICK` with its own
  virtualized arm flag (and, for the one entry with interval > 1, a
  countdown), all exact EXEC reload semantics.
- **`lagcheck` via the state-checksum ring, not a hand-picked cell**:
  most ports prove the delay ring by watching one game cell (a MOB
  velocity field, a fleet position). Golf's exact input-consuming field
  was not identified this session, so `make lagcheck` instead
  cross-correlates the SAME per-tick state checksum `make det` uses
  (`src/debug.asm`'s `TRACE_RING`) between a d=0 and a d=20 build — a
  more robust, cart-agnostic signal that doesn't require knowing what
  changed, only that the whole timeline shifts.

## Layout

Same tree as the sibling ports (see `PORTING.md`, the canonical
methodology, now carrying this port's lessons too: the recon
false-positive whose classification was right but whose patch necessity
wasn't, the TRACE_RING lagcheck redesign, and the `server_diff.py`
4-seat fix). `spikes/NOTES.md` holds the full per-milestone evidence
trail.
