#!/bin/sh
# M8 recovery test: the N-player rig with a fault injection -- console 2's
# GF_STROKES seat-0 cell ($0162, current hole's stroke count for the
# player at roster index 0) is corrupted mid-run via the debugger.
# Expected: CRC mismatch detected, the host pushes the state image
# (broadcast), ALL consoles re-baseline together, CRC rounds go back to
# matching, nobody drops.  PLAYERS=2..4 (default 2).
set -e
. "$(dirname "$0")/serverlib.sh"
BUILD=build
RIG="$BUILD/rig"
JZINTV="${JZINTV:-$HOME/Workspace/jzintv-20200712-src/bin/jzintv}"
RUN_SECS="${RUN_SECS:-100}"
PLAYERS="${PLAYERS:-2}"

i=1
while [ "$i" -le "$PLAYERS" ]; do
    [ -d "$RIG/fn$i" ] || { echo "run 'make rig PLAYERS=$PLAYERS' once first"; exit 1; }
    i=$((i+1))
done

# Same guard as run_rig.sh: never point fuzz clients at production.
if ! grep -q '127\.0\.0\.1' "$BUILD/srv_endpoint.asm" 2>/dev/null; then
    echo "run_m4.sh: build/srv_endpoint.asm is not 127.0.0.1 -- rebuild first"
    exit 1
fi

# Stale rig fujinet instances hold the BOIP ports and make every later
# launch a silent no-op (the fresh copy fails to bind and dies).
pkill -f 'fujinet -u 127.0.0.1:1808' 2>/dev/null || true
sleep 0.5
FNS=""
i=1
while [ "$i" -le "$PLAYERS" ]; do
    ( cd "$RIG/fn$i" && exec ./fujinet -u 127.0.0.1:1808$i ) > "$RIG/fn$i.log" 2>&1 &
    FNS="$FNS $!"
    i=$((i+1))
done
( relay_server --port 9111 --auto-go "$PLAYERS" ) \
    > "$RIG/m4_server.log" 2>&1 &
SRV=$!
trap 'kill $FNS $SRV 2>/dev/null || true' EXIT
sleep 1.5

# The debugger's `r N` counts INSTRUCTIONS (~4.6 cycles each on average),
# so ~200000 instructions per emulated second.  Console 2 gets the fault
# poke at ~40s (well past matchmaking at any player count); every console
# gets the stagger-compensated run length so all quit together.
CONS=""
i=1
while [ "$i" -le "$PLAYERS" ]; do
    SECS=$(( RUN_SECS - 2 * (i - 1) ))
    {
        printf 'b 14D5\nr 10000000\n'
        j=1
        while [ "$j" -lt "$i" ]; do
            printf 'n 14D5\nr %d\nb 14D5\nr 10000000\n' $((0x49BF0 + i * 4369))
            j=$((j+1))
        done
        printf 'g 7 14D7\nn 14D5\n'
        if [ "$i" = 1 ] && [ -n "$QUIESCE" ]; then
            # QUIESCE=1: starting when the fault lands (matching console
            # 2's timing below), keep FORCING the HOST's GF_ARM1/GF_ARM2
            # ($8102/$8199 -- entries 1/2, ball flight and roll) to 0
            # repeatedly across a wide window.  GF_GAME_TICK (src/hook.asm)
            # recomputes GF_QUIESCENT every tick as "neither physics entry
            # armed" -- forcing the two ARM flags off makes that condition
            # true on every recomputation during the window, exactly the
            # same shape as the family precedent (Sea Battle's forced
            # $0164/$01D9 pair): a one-shot poke does not reliably land,
            # because CRC comparison (and therefore RS_PENDING actually
            # polling) only happens on 64-tick boundaries and RS_PEND_MAX
            # is only 60 ticks, so a narrow window can miss it entirely.
            # RS_PENDING checks SC_PHASE/SC_PHASE_DEAD FIRST and pushes
            # IMMEDIATELY if quiescent -- forcing the flags continuously
            # guarantees any push that becomes pending during the window
            # takes the quiescent branch.  Bounded to ~15s (well past the
            # RS_PEND_MAX cap) rather than the whole run: forcing forever
            # would hold console 1 in an artificial state relative to the
            # others forever, manufacturing its own endless mismatches and
            # never letting the session demonstrate a genuinely clean
            # recovered end state (the Sea Battle precedent's own hard-won
            # lesson).
            printf 'r 8000000\n'
            k=0
            while [ "$k" -lt 60 ]; do
                printf 'e 8102 0\ne 8199 0\nr 50000\n'
                k=$((k+1))
            done
            # Capture RS_GATE right here, before any LATER (organic)
            # push has a chance to overwrite it -- it is a single cell
            # holding only the reason for the MOST RECENT push.
            printf 'm 818A 1\n'
            printf 'r %d\n' $(( (SECS - 40 - 15) * 200000 ))
        elif [ "$i" = 2 ]; then
            # Fault: rewrite console 2's GF_STROKES seat-0 stroke count
            # ($0162).  It is inside the CRC range $015D-$01EF, it is
            # unambiguously game state (a scoreboard number) rather than
            # scratch, and a divergence in it is exactly the kind a
            # player would notice -- so recovery here is meaningful.
            printf 'r 8000000\ne 162 77\nr %d\n' $(( (SECS - 40) * 200000 ))
        else
            printf 'r %d\n' $(( SECS * 200000 ))
        fi
        printf 'm 8100 20\nm 8150 60\nm 80C0 2\nm 8180 10\nm 8090 10\nm 0160 20\n'
        printf 'q\n'
    } > "$RIG/m4c$i.scr"
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        timeout $((RUN_SECS + 200)) "$JZINTV" -d --script="$RIG/m4c$i.scr" \
        --fujinet=localhost:1985$i -e rom/exec.bin -g rom/grom.bin \
        "$BUILD/golf_net$i.bin" > "$RIG/m4c$i.out" 2>&1 &
    CONS="$CONS $!"
    sleep 2
    i=$((i+1))
done
wait $CONS || true

PLAYERS=$PLAYERS python3 - "$RIG" <<'EOF'
import os, re, sys
rig = sys.argv[1]
players = int(os.environ["PLAYERS"])
GF_HTBL_PROMPT = 0x51DD

def cells(path):
    mem = {}
    for m in re.finditer(r"^([0-9A-F]{4}):((?:\s+[0-9A-F]{4}\*?){1,8})\s*#",
                         open(path).read(), re.M):
        a = int(m.group(1), 16)
        for i, w in enumerate(m.group(2).split()):
            mem[a + i] = int(w.rstrip("*"), 16)
    return mem

def first_reading(path, addr):
    """The FIRST time `addr` was dumped in `path`, not the last -- for
    cells like RS_GATE ($818A) that get overwritten by a later, unrelated
    push before the run ends."""
    for m in re.finditer(r"^([0-9A-F]{4}):((?:\s+[0-9A-F]{4}\*?){1,8})\s*#",
                         open(path).read(), re.M):
        a = int(m.group(1), 16)
        for i, w in enumerate(m.group(2).split()):
            if a + i == addr:
                return int(w.rstrip("*"), 16)
    return None

ok = True
for n in range(1, players + 1):
    m = cells(f"{rig}/m4c{n}.out")
    tick = m.get(0x8108, 0) | (m.get(0x8109, 0) << 8)
    active, dropped, hold = m.get(0x8162, 0), m.get(0x8163, 0), m.get(0x8090, 9)
    diag = [m.get(0x8180 + i, 0) for i in range(4)]
    pend, waited = m.get(0x8187, 0), m.get(0x8189, 0)
    seat = m.get(0x8160, 9)
    why = m.get(0x818A, 0)
    gtbl = m.get(0x80C0, 0) | (m.get(0x80C1, 0) << 8)
    gate = "n/a (guest)" if seat else {
        0: "never pushed",
        1: f"QUIESCENT (neither physics entry armed) after {waited} ticks",
        2: f"cap expired at {waited} ticks (pushed mid-motion)"}.get(why, "?")
    print(f"console {n}: seat={seat} active={active} dropped={dropped} "
          f"hold={hold} tick={tick} diag(slip,rej,tmo,err)={diag}")
    print(f"           resync gate: pending={pend} GAME_TBL=${gtbl:04X} -> {gate}")
    ok &= (active == 1 and dropped == 0 and hold == 0 and tick > 400
           and diag == [0, 0, 0, 0])
    # Destination-phase assertion (§7.25): same signals as
    # check_dest_phase.py and the rig verdict -- the player-count prompt
    # was answered and GAME_TBL moved off it.
    pcount = m.get(0x161, 0)
    hole = m.get(0x16C, 0)
    print(f"           pcount={pcount} hole={hole}")
    if gtbl == GF_HTBL_PROMPT:
        print(f"console {n}: PARKED ON THE PLAYER-COUNT PROMPT -- every "
              f"dump agrees trivially")
        ok = False
    if not (1 <= pcount <= 4):
        print(f"console {n}: PCOUNT ${pcount:02X} OUT OF RANGE -- no real "
              f"gameplay covered")
        ok = False
    # The fault itself: console 2's $0162 was poked to $77 mid-run.  By the
    # end of a successful recovery it must NOT still read $77 on EITHER
    # console -- a resync that only fixed the CRC bookkeeping but left the
    # actual corrupted byte in place would be a false pass.
    strokes0 = m.get(0x162)
    if strokes0 == 0x77:
        print(f"console {n}: GF_STROKES[0] is still the fault value $77 -- "
              f"not actually repaired")
        ok = False

# QUIESCE=1 exists to prove the quiescent branch works at all; require it.
if os.environ.get("QUIESCE"):
    host_why = first_reading(f"{rig}/m4c1.out", 0x818A)
    if host_why != 1:
        print(f"QUIESCE run: host RS_GATE={host_why}, expected 1 (quiescent) "
              f"-- the dead-ball branch of RS_PENDING did not fire")
        ok = False
    else:
        print("QUIESCE run: the dead-ball branch of RS_PENDING fired as intended")

lines = open(f"{rig}/m4_server.log").read().splitlines()
mm = [i for i, l in enumerate(lines) if "CRC MISMATCH" in l]
oks = [i for i, l in enumerate(lines) if "crc ok" in l]
recovered = bool(mm) and bool(oks) and max(oks) > max(mm)
print(f"server: mismatches={len(mm)} crc-ok-lines={len(oks)} "
      f"recovered-after-fault={recovered}")
ok &= recovered
print(f"M4 PASS ({players} players)" if ok else "M4 FAIL")
sys.exit(0 if ok else 1)
EOF
