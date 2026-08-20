# In-place patch map for PGAGolf.bin (word address -> as1600 expression).
# Symbols are defined in src/hook.asm / src/ram.asm / src/exec_equ.asm.
# Building with tools/dump_rom.py and NO patch file must stay byte-identical
# to the original (make verify-org -- verified).
#
# STATUS (see spikes/NOTES.md M0 for the evidence trail): header relocation,
# both RNG wrapper flavours (8 sites), all seven timer-API shim sites, and
# the polled-input walking-pointer pair (base AND its loop terminator) are
# decoded and confirmed in the dis1600 listing.  `make verify-patch` proves
# exactly the 36 words below differ from the original ROM.
{
    # --- Cart header ---
    # $5002/$5003: EXEC timer table pointer -> relocated table in $6000 seg.
    0x5002: "NEW_TIMER_TBL AND $FF",
    0x5003: "NEW_TIMER_TBL SHR 8",
    # $5004/$5005: start-of-game vector -> netcode init shim (falls through
    # to the original .START at $5034).
    0x5004: "NET_START AND $FF",
    0x5005: "NET_START SHR 8",

    # --- RNG call sites -> canonical-RNG wrappers ---
    # X_RAND1 ($167D), 4 sites.  Each JSR R5,target is the 3-word form
    # (opcode word unpatched; the following two words encode the target as
    # ((target SHR 10) SHL 2) OR $0100, target AND $3FF).
    0x55FF: "((GF_RAND1 SHR 10) SHL 2) OR $0100",
    0x5600: "GF_RAND1 AND $3FF",
    0x5607: "((GF_RAND1 SHR 10) SHL 2) OR $0100",
    0x5608: "GF_RAND1 AND $3FF",
    0x564B: "((GF_RAND1 SHR 10) SHL 2) OR $0100",
    0x564C: "GF_RAND1 AND $3FF",
    0x5653: "((GF_RAND1 SHR 10) SHL 2) OR $0100",
    0x5654: "GF_RAND1 AND $3FF",
    # X_RAND2 ($169E), 4 sites.
    0x52FA: "((GF_RAND2 SHR 10) SHL 2) OR $0100",
    0x52FB: "GF_RAND2 AND $3FF",
    0x55A2: "((GF_RAND2 SHR 10) SHL 2) OR $0100",
    0x55A3: "GF_RAND2 AND $3FF",
    0x55C5: "((GF_RAND2 SHR 10) SHL 2) OR $0100",
    0x55C6: "GF_RAND2 AND $3FF",
    0x5BEF: "((GF_RAND2 SHR 10) SHL 2) OR $0100",
    0x5BF0: "GF_RAND2 AND $3FF",

    # --- Timer-arm/stop sites -> virtualized-flag shims ---
    # All seven sites call the REAL EXEC entry point (X_TIMER_ARM=$181E or
    # X_TIMER_STOP=$1838) with R1 = the ORIGINAL header table's slot address
    # ($5020/$5024/$5028).  Both entry points resolve R1 against the header
    # table pointer, which now points at NEW_TIMER_TBL -- so calling through
    # computes garbage post-relocation regardless of table layout.
    # Retargeted to GF_ARM_SHIM/GF_STOP_SHIM, which dispatch on the still-
    # meaningful stale R1 value to flip the matching virtualized flag.
    #
    # ARM sites (target $181E): $525A (re-arm slot 3, turn-wait, after a
    # stroke), $5352 (arm slot 1, ball flight, when a shot is taken), $535E
    # (arm slot 2, roll, when the ball lands).
    0x525B: "((GF_ARM_SHIM SHR 10) SHL 2) OR $0100",
    0x525C: "GF_ARM_SHIM AND $3FF",
    0x5353: "((GF_ARM_SHIM SHR 10) SHL 2) OR $0100",
    0x5354: "GF_ARM_SHIM AND $3FF",
    0x535F: "((GF_ARM_SHIM SHR 10) SHL 2) OR $0100",
    0x5360: "GF_ARM_SHIM AND $3FF",
    # STOP sites (target $1838): $503B (.START's stop-all loop, walks R1
    # across all three slots via ONE call site -- the shim must preserve
    # R1/R2), $527B (stop slot 3 once a stroke is taken), $53CE (stop slot
    # 1 once the ball lands), $53D5 (stop slot 2 once the roll settles).
    0x503C: "((GF_STOP_SHIM SHR 10) SHL 2) OR $0100",
    0x503D: "GF_STOP_SHIM AND $3FF",
    0x527C: "((GF_STOP_SHIM SHR 10) SHL 2) OR $0100",
    0x527D: "GF_STOP_SHIM AND $3FF",
    0x53CF: "((GF_STOP_SHIM SHR 10) SHL 2) OR $0100",
    0x53D0: "GF_STOP_SHIM AND $3FF",
    0x53D6: "((GF_STOP_SHIM SHR 10) SHL 2) OR $0100",
    0x53D7: "GF_STOP_SHIM AND $3FF",

    # --- Polled controller read -> the shadow pair ---
    # A single walking-pointer read at $525F-$526D: `MVII #$011F,R4` then a
    # loop that MVI@-reads R4 (auto-incrementing it) and tests for a disc
    # event, terminating when R4 reaches $0121 (i.e. after exactly two
    # cells: $011F then $0120).  Both the BASE and the LOOP TERMINATOR are
    # $011F-relative, so both operands must move together -- patching only
    # the base (as recon's own per-site labels first suggested) would leave
    # the terminator comparing the NEW base against the OLD $0121 sentinel,
    # walking R4 off into unrelated RAM until it happened to collide with
    # $0121 by chance. recon.py's own generic label for $526E ("keypad/
    # action state") is a false positive of PORTING.md §3 class 2 (a
    # CMPI against a hot-cell-shaped constant) -- but the ADDRESS it found
    # is exactly right; the label just described the wrong role.
    0x5260: "SHADOW_CTRL",          # $525F operand: MVII #$011F,R4
    0x526E: "SHADOW_CTRL + 2",      # $526D operand: CMPI #$0121,R4 (loop end)
}
