; Rig console 4: auto-join + fuzz + HUD, same as console 2 (seat from the
; server's START; the script columns are shared by seat parity).
SPIKE_DELAY     EQU     0
SPIKE_SCRIPT    EQU     0
SPIKE_TRACE     EQU     0
STALL_N         EQU     0
SPIKE_ECHO      EQU     0
SPIKE_RECORD    EQU     0
SPIKE_REPLAY    EQU     0
NET_SESSION     EQU     1
AUTO_JOIN       EQU     1
NET_FUZZ        EQU     1
NET_HUD         EQU     1
SPIKE_VIRT      EQU     0
        INCLUDE "src/core.asm"
