; Netcode hook segment for PGA Golf (Mattel 1979).
;
; STATUS: M0 recon complete (spikes/NOTES.md).  Header relocation, both RNG
; wrapper flavours (8 sites: 4x X_RAND1, 4x X_RAND2), all seven timer-API
; shim sites, and the single polled-input operand are the declared patch
; map (tools/patches.py).
;
; The cart header's timer-table pointer ($5002) is patched to
; NEW_TIMER_TBL.  Golf's ORIGINAL table has a music entry (slot 0, stopped
; one-shot) exactly like Baseball/Auto Racing/Bowling/Sea Battle -- kept as
; the family's defensive placeholder (PORTING.md §4: if any EXEC path ever
; re-arms "the first table entry" for a note, it must land on a music
; slot, not on MASTER_TICK's countdown).  Entry 1 is our master dispatcher.
;
; The original three game entries (table $501C, slots 4 words apart):
;   slot 1  $54E6  int 1 (20 Hz)    ball-flight physics
;   slot 2  $5718  int 3 (6.66 Hz) putting/roll physics
;   slot 3  $525E  int 1 (20 Hz)   input wait / turn machinery (also where
;                                  the polled $011F/$0120 read lives)
; GF_GAME_TICK reproduces all three, in table order, each on its own
; virtualized arm flag; slot 2's countdown uses exact EXEC reload semantics
; (fire on 0, reload full interval -- PORTING.md §7.24; it paces the ball's
; visible roll, so fire-on-negative would be a 33% slowdown).
;
; Unlike Sea Battle, Golf's three entries are NOT left native: Sea Battle
; could park two of three real entries after MASTER_TICK in an unchanged
; table layout because it had exactly two entries left after the music
; placeholder + MASTER_TICK filled the first two slots.  Golf has three
; real entries and only two slots would remain after the same placeholder
; shape, so -- following the Bowling precedent (§7.23), which had five
; entries and virtualized all of them -- every entry here is fully
; virtualized instead.  This also sidesteps the §7.30 hardcoded-literal-
; countdown-address hazard class entirely: confirmed by grep (M0) that
; Golf has NO such sites, so there is nothing for a table-relocation to
; silently break.
;
; No X_SCAN self-call hazard: zero references to $14F1 anywhere in the ROM
; (M0), so $035D only needs nulling AFTER the tick, not before as well
; (unlike NASL Soccer, PORTING.md §7.26).
;
; No cart ISR dance: zero $0100/$0101 writes anywhere in the ROM (M0), so
; there is no RS_CLAMP_ISR-shaped hazard and no wall-tick-rate surprise
; (PORTING.md §7.28 does not apply -- the pass should measure a clean 3
; frames; confirm this at M2 before picking d).
;
; Golf is 2-4 SEATS, TURN-BASED, with controller-blind handlers (the $51D3
; table's handlers only ever read R0, the event value; the $525E poll
; accepts either $011F or $0120 interchangeably) -- ARB_COMPUTE picks the
; ONE controlling seat every tick from sim state ($016B, the game's own
; "whose turn" cell) and suppresses everyone else, Bowling-style.  While
; the EXEC's number-entry prompt ($1910, installed at boot via $504F) owns
; $035D, ARB_INJECT answers it deterministically from the room roster size
; instead of routing it to any seat.

        ORG     $6000

NEW_TIMER_TBL:
        DECLE   X_MUSIC_TICK AND $FF, X_MUSIC_TICK SHR 8
        DECLE   $01, $80                ; interval $8001: stopped, one-shot
        DECLE   MASTER_TICK AND $FF, MASTER_TICK SHR 8
        DECLE   $01, $00                ; every pass, always armed
        DECLE   $00, $00                ; terminator

; ---------------------------------------------------------------------------
; NET_START -- patched start-of-game vector ($5004, original target GF_START
; = $5034).  Runs after the title screen, before the EXEC main loop starts
; (the EXEC jumps here with R5 = $108F), so netcode RAM is initialized
; before the first MASTER_TICK.  Falls through to the original .START,
; which immediately STOP-alls the three slots (via GF_STOP_SHIM, the
; $503B loop) before running the (now dispatch-only, EXEC-driven)
; number-entry prompt -- so the arm flags here just need to be sane, and
; the countdown must hold its FULL interval (the frog-bog seeding lesson)
; so a later arm fires on the real cadence.
; ---------------------------------------------------------------------------
NET_START:
        PSHR    R5                      ; EXEC main-loop return
        MVII    #NET_RAM, R4
        MVII    #NET_RAM_SIZE, R1
        CLRR    R0
@@zero: MVO@    R0,     R4
        DECR    R1
        BNEQ    @@zero
        MVII    #GF_INT2, R0            ; slot 2's countdown starts full
        MVO     R0,     GF_CNT2
        MVII    #SPIKE_DELAY, R0        ; virt-dispatch delay depth (spike knob)
        MVO     R0,     DELAY_EN
        ; Seat defaults for local builds: seat 0 of a 2-player game.  The
        ; netplay path overwrites both from the START payload.
        MVII    #2,     R0
        MVO     R0,     NET_COUNT
    IF SPIKE_VIRT <> 0
        JSR     R5,     LS_RING_INIT    ; idle-fill the dispatch rings
    ENDI
    IF SPIKE_ECHO <> 0
        JSR     R5,     ECHO_TEST       ; parks with results; never returns
    ENDI
    IF NET_SESSION <> 0
        JSR     R5,     SES_MAIN        ; login/lobby; arms NET_ACTIVE or not
    ENDI
        PULR    R5
        J       GF_START

; NET_NULL_TBL: handed to the EXEC scan (via $035D) while dispatch is
; virtualized so its event dispatch resolves null pointers and never calls
; game code from real local input.  Zeros on both sides of the base cover
; negative slot indexes.
NET_NULL_TBL:
        DECLE   0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        DECLE   0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------------------------------------------------------------------------
; MASTER_TICK -- timer entry 1 of NEW_TIMER_TBL, dispatched by the EXEC
; every main-loop pass.  May clobber R0-R3.  Returns via the dispatcher's
; R5.
; ---------------------------------------------------------------------------
MASTER_TICK:
        PSHR    R5
    IF STALL_N <> 0
        ; Stall injector (spike c): every 64th pass, busy-spin ~STALL_N
        ; frames INSIDE the dispatch.  The ISR keeps firing but $0102 sits
        ; at 0 mid-pass, so it takes its skip path: display continues,
        ; game logic freezes.
        MVI     FRM_CTR, R0
        INCR    R0
        ANDI    #$3F,   R0
        MVO     R0,     FRM_CTR
        BNEQ    @@no_stall
        DIS
        MVI     $102,   R2
        CLRR    R0
        MVO     R0,     $102
        EIS
        MVII    #STALL_N * 3000, R1     ; ~15 cycles/iter, ~1 frame per 1000
@@spin: DECR    R1
        BNEQ    @@spin
        DIS
        MVO     R2,     $102
        EIS
@@no_stall:
    ENDI
    IF NET_SESSION <> 0
        MVI     NET_ACTIVE, R0
        TSTR    R0
        BEQ     @@mt_local
        JSR     R5,     LS_PASS         ; lockstep netplay path
        PULR    R7
@@mt_local:
    ENDI
        JSR     R5,     UPDATE_SHADOW
    IF SPIKE_RECORD <> 0
        JSR     R5,     REC_CAPTURE     ; log the live cells for this tick
    ENDI
    IF SPIKE_VIRT <> 0
        ; Turn-arbitered virtual dispatch, local-spike path (the netplay
        ; path's own copy lives in lockstep.asm's LS_PASS -- PORTING.md
        ; §7.20: SHADOW_FROM_RINGS must run there too, not just here).
        JSR     R5,     VIRT_CAPTURE
        JSR     R5,     LS_TBL_ADOPT
        MVI     GAME_TBL_HI, R1
        SWAP    R1,     1
        ADD     GAME_TBL_LO, R1
        BEQ     @@mt_no_tbl
        MVO     R1,     $35D
@@mt_no_tbl:
        JSR     R5,     ARB_COMPUTE     ; ARB_SEAT := controlling seat / $FF
        JSR     R5,     SHADOW_FROM_RINGS
        MVI     ARB_SEAT, R0
        CMPI    #$FF,   R0
        BEQ     @@mt_nodisp             ; injector owned this tick
        MVO     R0,     VD_SIDE
        JSR     R5,     LS_VDISPATCH    ; the ONE controlling seat
@@mt_nodisp:
    ENDI
        JSR     R5,     GF_GAME_TICK
    IF SPIKE_VIRT <> 0
        JSR     R5,     LS_TBL_ADOPT
        MVII    #NET_NULL_TBL+4, R0
        MVO     R0,     $35D
    ENDI
    IF SPIKE_TRACE <> 0
        JSR     R5,     TRACE_TICK
    ELSE
        ; sim tick counter (16-bit across two 8-bit cells)
        MVI     TICK_LO, R0
        INCR    R0
        MVO     R0,     TICK_LO
        CMPI    #$100,  R0
        BNEQ    @@mt_out
        MVI     TICK_HI, R0
        INCR    R0
        MVO     R0,     TICK_HI
    ENDI
@@mt_out:
        PULR    R7

; ---------------------------------------------------------------------------
; ARB_COMPUTE -- the turn arbiter.  Sets ARB_SEAT to the seat whose input
; reaches the sim this tick, from sim state only:
;   $035D == GF_HTBL_PROMPT (the EXEC number-entry prompt is up, at boot):
;     ARB_SEAT := $FF; ARB_INJECT answers it with NET_COUNT + ENTER
;   any other table (in-round play, game over):
;     ARB_SEAT := GF_CUR AND 3     (0-based golfer up)
; Clobbers R0/R1.
; ---------------------------------------------------------------------------
ARB_COMPUTE:
        PSHR    R5
        MVI     GAME_TBL_LO, R0
        CMPI    #GF_HTBL_PROMPT AND $FF, R0
        BNEQ    @@ac_play
        MVI     GAME_TBL_HI, R0
        CMPI    #GF_HTBL_PROMPT SHR 8, R0
        BNEQ    @@ac_play
        MVII    #$FF,   R0
        MVO     R0,     ARB_SEAT
        JSR     R5,     ARB_INJECT
        PULR    R7
@@ac_play:
        MVI     GF_CUR, R0
        ANDI    #3,     R0
        MVO     R0,     ARB_SEAT
        PULR    R7

; ---------------------------------------------------------------------------
; ARB_INJECT -- deterministic player-count answer for the EXEC number-entry
; prompt.  While GAME_TBL sits on GF_HTBL_PROMPT, a tick counter (ARB_INJ,
; sim state) paces two synthetic keypad events through the live handler,
; exactly as LS_VDISPATCH would deliver them:
;   tick 2: digit NET_COUNT  (event slot/encoding measured live at M2 --
;           placeholder VD_TMP slot below, confirm against a real scan
;           dump before trusting it)
;   tick 6: ENTER
; The step self-terminates once the prompt table changes (ARB_COMPUTE stops
; calling this once GAME_TBL != GF_HTBL_PROMPT).  ARB_INJ is CRC'd and in
; the resync image tail.  Clobbers R0/R1/R2.
; ---------------------------------------------------------------------------
ARB_INJECT:
        PSHR    R5
        MVI     ARB_INJ, R0
        INCR    R0
        MVO     R0,     ARB_INJ
        CMPI    #2,     R0
        BEQ     @@ai_digit
        CMPI    #6,     R0
        BEQ     @@ai_enter
        PULR    R7
@@ai_digit:
        MVII    #2,     R0              ; keypad events land on slot 2
                                        ;  (M2 TODO: confirm against a live
                                        ;  $035D-table decode before rig)
        MVO     R0,     VD_TMP
        MVI     NET_COUNT, R0           ; digit N = R0 value N (1-based)
        JSR     R5,     LS_VCALL
        PULR    R7
@@ai_enter:
        MVII    #2,     R0
        MVO     R0,     VD_TMP
        MVII    #$0B,   R0              ; ENTER event value (M2 TODO: confirm)
        JSR     R5,     LS_VCALL
        PULR    R7

; ---------------------------------------------------------------------------
; GF_GAME_TICK -- reproduces all three original timer entries at their own
; cadence, in the original table's order, with exact EXEC reload semantics
; (fire on countdown == 0, reload to full interval).  Shared by
; MASTER_TICK's local path and lockstep.asm's LS_PASS.  Also computes
; GF_QUIESCENT every tick (must run on BOTH paths -- Sea Battle's hard-won
; rule: NET_ACTIVE returns via LS_PASS before MASTER_TICK's local-only
; section is ever reached).
; Clobbers R0/R1.  Returns via the caller's R5.
; ---------------------------------------------------------------------------
GF_GAME_TICK:
        PSHR    R5
        ; Entry 1 ($54E6, interval 1) -- ball-flight physics
        MVI     GF_ARM1, R0
        TSTR    R0
        BEQ     @@gt_e1_off
        JSR     R5,     GF_TICK1
@@gt_e1_off:
        ; Entry 2 ($5718, interval 3) -- putting/roll physics
        MVI     GF_ARM2, R0
        TSTR    R0
        BEQ     @@gt_e2_off
        MVI     GF_CNT2, R0
        DECR    R0
        BNEQ    @@gt_e2_hold
        JSR     R5,     GF_TICK2
        MVII    #GF_INT2, R0
@@gt_e2_hold:
        MVO     R0,     GF_CNT2
@@gt_e2_off:
        ; Entry 3 ($525E, interval 1) -- input wait / turn machinery
        MVI     GF_ARM3, R0
        TSTR    R0
        BEQ     @@gt_e3_off
        JSR     R5,     GF_TICK3
@@gt_e3_off:
        ; GF_QUIESCENT: 1 iff neither physics entry is armed (ball at rest
        ; -- entry 3, the input-wait, may be armed or not: that is the
        ; NORMAL resting state between strokes, not a transition instant,
        ; so this window is wide and safe, not a single-tick pinch point
        ; -- PORTING.md's Sea Battle lesson about post-tick derived flags).
        MVI     GF_ARM1, R0
        TSTR    R0
        BNEQ    @@gt_not_q
        MVI     GF_ARM2, R0
        TSTR    R0
        BNEQ    @@gt_not_q
        MVII    #1,     R0
        MVO     R0,     GF_QUIESCENT
        B       @@gt_qout
@@gt_not_q:
        CLRR    R0
        MVO     R0,     GF_QUIESCENT
@@gt_qout:
        PULR    R7

; ---------------------------------------------------------------------------
; GF_RAND1 / GF_RAND2 -- canonical-RNG wrappers for the game's eight RAND
; call sites (4x X_RAND1, 4x X_RAND2; spikes/NOTES.md M0, both confirmed
; genuine JSR instructions).  The EXEC sound engine advances the shared
; LFSR at $035E from ISR context whenever noise SFX play (§5.2), so game
; logic must not read $035E directly: swap the canonical (sim-space) value
; in, call the EXEC routine with interrupts off, swap the advanced value
; back out.
; Preserves R1/R2 like the underlying EXEC routines; result in R0.
; ---------------------------------------------------------------------------
GF_RAND1:
        PSHR    R5
        DIS
        JSR     R5,     @@swap_in
        JSR     R5,     X_RAND1
        B       @@swap_out

GF_RAND2:
        PSHR    R5
        DIS
        JSR     R5,     @@swap_in
        JSR     R5,     X_RAND2
@@swap_out:
        PSHR    R1
        MVI     EXEC_RNG, R1
        MVO     R1,     RNG_LO
        SWAP    R1,     1
        MVO     R1,     RNG_HI
        PULR    R1
        EIS
        PULR    R7

@@swap_in:
        PSHR    R1
        PSHR    R2
        MVI     RNG_HI, R1
        SWAP    R1,     1
        MVI     RNG_LO, R2
        ADDR    R2,     R1
        MVO     R1,     EXEC_RNG
        PULR    R2
        PULR    R1
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; GF_ARM_SHIM / GF_STOP_SHIM -- wired into tools/patches.py at all seven
; original timer-API call sites.  Each site passes R1 = the ORIGINAL
; header table's slot address ($5020/$5024/$5028 -- stale once the table
; is relocated, since X_TIMER_ARM/X_TIMER_STOP resolve it against the
; header pointer, which now points at NEW_TIMER_TBL); the shims dispatch
; on R1 to flip the matching virtualized arm flag / countdown.
; MUST preserve R1 and R2: $503B's stop-all loop walks R1 across all three
; slots with R2 as its loop counter, through GF_STOP_SHIM once per slot.
; ARM seeds entry 2's countdown to the full interval (real ARM semantics:
; first fire GF_INT2 passes after arming).
; ---------------------------------------------------------------------------
GF_STOP_SHIM:
        CLRR    R0
        CMPI    #GF_SLOT1, R1
        BNEQ    @@st_2
        MVO     R0,     GF_ARM1
        MOVR    R5,     R7
@@st_2: CMPI    #GF_SLOT2, R1
        BNEQ    @@st_3
        MVO     R0,     GF_ARM2
        MOVR    R5,     R7
@@st_3: MVO     R0,     GF_ARM3         ; GF_SLOT3 (only remaining case)
        MOVR    R5,     R7

GF_ARM_SHIM:
        MVII    #1,     R0
        CMPI    #GF_SLOT1, R1
        BNEQ    @@sa_2
        MVO     R0,     GF_ARM1
        MOVR    R5,     R7
@@sa_2: CMPI    #GF_SLOT2, R1
        BNEQ    @@sa_3
        MVO     R0,     GF_ARM2
        MVII    #GF_INT2, R0
        MVO     R0,     GF_CNT2
        MOVR    R5,     R7
@@sa_3: MVO     R0,     GF_ARM3         ; GF_SLOT3 (only remaining case)
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; GF_REBASE_HOOK -- called from resync.asm's RS_REBASE (one added line;
; resync.asm is otherwise unchanged) after a state image has been applied.
; Clamps the two transported cells that index memory without a cart-side
; bounds check (PORTING.md §7.27 audit): GF_CUR/GF_ORDER_IDX index the
; 4-cell GF_ORDER/GF_STROKES arrays, GF_HOLE indexes the par lookup at
; $57AE+GF_HOLE.  Symmetric on both sides, so CRC-neutral when healthy.
; Clobbers R0.
; ---------------------------------------------------------------------------
GF_REBASE_HOOK:
        MVI     GF_CUR, R0
        CMPI    #3,     R0
        BLE     @@rh_cur_ok
        CLRR    R0
@@rh_cur_ok:
        MVO     R0,     GF_CUR
        MVI     GF_ORDER_IDX, R0
        CMPI    #3,     R0
        BLE     @@rh_idx_ok
        CLRR    R0
@@rh_idx_ok:
        MVO     R0,     GF_ORDER_IDX
        MVI     GF_HOLE, R0
        CMPI    #9,     R0
        BLE     @@rh_hole_ok
        CLRR    R0
@@rh_hole_ok:
        MVO     R0,     GF_HOLE
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; UPDATE_SHADOW -- feed the decoded-input shadow pair from the live EXEC
; cells.  LOAD-BEARING on this cart: a single walking-pointer read at
; $525F polls $011F then $0120 directly (M0) -- the patched operand at
; $5260 redirects it at SHADOW_CTRL.
; ---------------------------------------------------------------------------
UPDATE_SHADOW:
        MVI     EXEC_IN_L, R0
        MVO     R0,     SHADOW_CTRL
        MVI     EXEC_IN_R, R0
        MVO     R0,     SHADOW_CTRL_R
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; SHADOW_FROM_RINGS -- feed the shadow pair from the CONTROLLING seat's
; ring at the current tick.  PORTING.md §7.20: this must be called from
; BOTH MASTER_TICK's local path AND LS_PASS, or a real two-console rig
; sees this console's own idle second controller instead of the
; exchanged, delay-adjusted remote value.
;
; ** SEAT-ABSOLUTE, NOT SEAT-RELATIVE. ** Seat 0 always feeds SHADOW_CTRL
; (the cell the cart reads first off $011F) and seat 1 always feeds
; SHADOW_CTRL_R, on BOTH consoles, regardless of which seat we are --
; matching UPDATE_SHADOW's own mapping.  The turn arbiter guarantees only
; the controlling seat's actual events replay through LS_VDISPATCH; the
; shadow pair for every OTHER seat just needs to read as idle so the
; game's own (dead) poll of an inactive seat sees nothing.
;
; Clobbers R0/R3.
; ---------------------------------------------------------------------------
SHADOW_FROM_RINGS:
        MVII    #SEAT_RING, R3          ; seat 0
        ADD     TICK_LO, R3
        MVI@    R3,     R0
        MVO     R0,     SHADOW_CTRL
        MVII    #SEAT_RING + $100, R3   ; seat 1
        ADD     TICK_LO, R3
        MVI@    R3,     R0
        MVO     R0,     SHADOW_CTRL_R
        MOVR    R5,     R7
