; EXEC ROM entry points and RAM locations used by the netcode patch.
; Addresses are the shared EXEC's (identical across every port so far --
; confirmed for this cart in build/golf.dis, spikes/NOTES.md M0).

X_MUSIC_TICK    EQU     $1A71   ; music note-timer routine; Golf's own timer
                                ;  table slot 0 target, interval $8001
                                ;  (stopped/one-shot) -- kept as the family's
                                ;  defensive placeholder (PORTING.md §4)
X_RAND1         EQU     $167D   ; LFSR random entry, flavour 1 (4 sites)
X_RAND2         EQU     $169E   ; LFSR random entry, flavour 2 (4 sites)
X_SCAN          EQU     $14F1   ; controller scan (EXEC main loop only --
                                ;  Golf never calls it itself: zero $14F1
                                ;  references anywhere in the ROM, M0)
X_TIMER_STOP    EQU     $1838   ; disarm a timer-table entry, R1 = slot addr
X_TIMER_ARM     EQU     $181E   ; "set timer countdown := interval" -- this
                                ;  cart's 3 ARM sites call this lower-level
                                ;  reload entry point directly (confirmed in
                                ;  recon.py's own TIMER_CALLS table), NOT the
                                ;  higher-level $1844 X_TIMER_START other
                                ;  ports use -- M0

EXEC_RNG        EQU     $035E   ; 16-bit LFSR state (System RAM)
EXEC_ISR_DEF    EQU     $1126   ; the EXEC's default game-time ISR (Golf
                                ;  never writes $0100/$0101 -- M0 confirmed
                                ;  no cart ISR dance -- so nothing in this
                                ;  port ever needs to clamp to this)

; EXEC decoded per-controller input cells, rewritten by the scan each pass.
EXEC_IN_L       EQU     $011F   ; left controller decoded input
EXEC_IN_R       EQU     $0120   ; right controller decoded input
EXEC_KP_L       EQU     $0121   ; left keypad event/state cell (vdispatch.asm
EXEC_KP_R       EQU     $0122   ;  references these unconditionally; Golf's
                                ;  own $0121 site is a loop terminator, not a
                                ;  read -- M0 -- so these are engine-shaped
                                ;  only, never a cart patch target)
EXEC_HTBL       EQU     $035D   ; input-handler table pointer (game-managed)
EXEC_RAW_L      EQU     $0123   ; left controller raw (inverted port) value
EXEC_RAW_R      EQU     $0124

; SC_ISR_SAVE: RS_CLAMP_ISR (src/netcode/resync.asm, copied unchanged) runs
; unconditionally from RS_REBASE.  Golf has NO cart ISR at all (zero
; $0100/$0101 writes anywhere in the ROM, M0) -- there is no vector for the
; game to stash, so this points at a harmless netcode-RAM spare (zeroed by
; NET_START) rather than a game-scratch cell.  Structural no-op by
; construction, matching the Sea Battle precedent exactly.
SC_ISR_SAVE     EQU     $81AD   ; harmless spare pair, zeroed by NET_START

; DANCE_SETTLE (src/vdispatch.asm, copied unchanged) unconditionally checks
; $0101 against SC_ISR_BODY's page before repainting a terminal screen --
; PORTING.md §7.10.  Golf never installs a cart ISR, so $0101 is always the
; EXEC default's high byte ($11).  Any page that can never equal $11 makes
; the check a structural no-op (falls through on the very first read).
SC_ISR_BODY     EQU     $0000

; Original game timer entries, re-dispatched from the master tick in
; original table order.  Original table at $501C, FOUR words per entry
; (addr lo/hi, interval lo/hi), slots at $501C+4k.  All three are
; start/stopped by the cart (7 API sites -- spikes/NOTES.md M0 table).
GF_TICK1        EQU     $54E6   ; slot 1, interval 1 (20 Hz): ball flight
GF_TICK2        EQU     $5718   ; slot 2, interval 3 (6.66 Hz): putting/roll
GF_TICK3        EQU     $525E   ; slot 3, interval 1 (20 Hz): input wait /
                                ;  turn machinery (the polled-input site)
GF_START        EQU     $5034   ; original start-of-game vector target

; Original header-table slot addresses -- what all seven timer-API call
; sites pass in R1 (stale absolute addresses after relocation).  The shims
; dispatch on these to flip virtualized GF_ARMn flags / countdown.
GF_SLOT1        EQU     $5020
GF_SLOT2        EQU     $5024
GF_SLOT3        EQU     $5028

; Original entry intervals in passes (used to seed/reload the virtualized
; countdown -- seed to the FULL interval at NET_START, the frog-bog lesson).
GF_INT1         EQU     1
GF_INT2         EQU     3
GF_INT3         EQU     1

; The $035D handler-table values (M0-traced): the live 5-slot dispatch
; table Golf installs once at boot ($506E) and never changes thereafter --
; $51DD (row 0, the number-entry prompt continuation address the EXEC's
; own $1910 routine hands back control through) doubles as the live
; GAME_TBL value while the prompt is up, since $1910 installs it into
; $035D directly.  $1906 is the EXEC null table Golf installs at game-over
; ($5120).  GAME_TBL == GF_HTBL_PROMPT is what the turn arbiter keys off to
; hand the tick to the injector instead of a seat.
GF_HTBL_LIVE    EQU     $51D3   ; live in-round handler table
GF_HTBL_PROMPT  EQU     $51DD   ; number-entry prompt table (EXEC $1910)
GF_HTBL_NULL    EQU     $1906   ; EXEC null table (game-over)

; Game-state cells the arbiter and injector read (all inside $015D-$01EF,
; the block .START zero-fills = the engine CRC range; full map in
; spikes/NOTES.md M0).
GF_PCOUNT       EQU     $0161   ; player count, 1-4 (from the EXEC prompt)
GF_STROKES      EQU     $0162   ; per-player stroke count this hole, 4 cells
                                ;  ($0162-$0165), indexed by player number
GF_CUR          EQU     $016B   ; current player, 0-BASED (whose turn)
GF_HOLE         EQU     $016C   ; hole number (0-9; game over at 10)
GF_ORDER        EQU     $0179   ; play order -> player number, 4 cells
                                ;  ($0179-$017C), sorted by the "away" rule
GF_ORDER_IDX    EQU     $017D   ; index into GF_ORDER for whose turn is next
GF_WRAP         EQU     $0177   ; order-wrapped-this-hole flag
GF_LIE          EQU     $0183   ; terrain/lie code, current
GF_LIE_PREV     EQU     $0184   ; terrain/lie code, previous
GF_PASSLEN      EQU     $0103   ; EXEC pass length -- GAME-WRITTEN ($5085
                                ;  writes 3): goes in the resync image tail
