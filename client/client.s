;;;-------------------------------------------------------------------
;;;
;;; vnIIc Client Application
;;;
;;;-------------------------------------------------------------------

        PADDLE_SUPPORT = 1
;;; MOUSE_SUPPORT  = 1

        .include "apple2.inc"

        .include "macros.inc"

;;;---------------------------------------------------------
;;; Hi-res graphics constants/locations
;;;---------------------------------------------------------

PAGE    := $E6                  ; Active hires plotting page (Applesoft)
PAGE1   := $20
PAGE2   := $40

PAGESIZE        := $20            ; Size of hi-res screen in pages

;;;---------------------------------------------------------
;;; ROM routines
;;;---------------------------------------------------------

PREAD   := $FB1E                 ; Monitor paddle reading routine, call
                                ; with paddle # in X, returns value in Y

HCLR    := $F3F2                     ; Clear current hires screen to black

;;;---------------------------------------------------------
;;; Other
;;;---------------------------------------------------------

MAX_SLOT        := 7             ; Maximum slot # on an Apple II

ZP_PTR  := $FA                   ; Write cursor location on zero page


;;;-------------------------------------------------------------------
;;;
;;; Client Code
;;;
;;;-------------------------------------------------------------------

        .org $6000
        jmp     AppEntry

        .include "ssc.inc"

    .ifdef MOUSE_SUPPORT
        .include "mouse.inc"
    .endif


;;;-------------------------------------------------------------------
;;; Variables
;;;-------------------------------------------------------------------

;;; Application configuration
PSPEED: .byte   SSC::BPS_115k   ; Hardcoded for Apple IIc (TODO: Allow configuration)
PSLOT:  .byte   2               ; Hardcoded for Apple IIc (TODO: Allow configuration)
PEXIT:  .byte   0               ; Set when it's time to exit (Not Yet Implemented)

;;; Keyboard state
LASTKB: .byte   0
LASTOA: .byte   0
LASTCA: .byte   0

    .ifdef PADDLE_SUPPORT

;;; Paddle state
LASTP0: .byte   0
LASTP1: .byte   0

    .endif                      ; PADDLE_SUPPORT


;;;---------------------------------------------------------
;;; Initialize the application, and enter the main loop

.proc AppEntry
        lda     PSLOT           ; Use slot 2
        jsr     SSC::Init       ; Initialize Super Serial Card
        jsr     InitHires       ; Initialize Hi-Res graphics
        jsr     InitInput       ; Initialize input devices
        jsr     MainLoop

                                ; fall through
.endproc

;;;---------------------------------------------------------
;;; Clean up and exit app

.proc AppExit
        jsr     SSC::Reset
        sta     LOWSCR
        sta     TXTSET
        rts
.endproc


;;;-------------------------------------------------------------------
;;;
;;; Main loop functionality
;;;
;;;-------------------------------------------------------------------


;;;---------------------------------------------------------
.proc MainLoop

;;; TODO: Sort out the protocol - should be able to send
;;; input state without receiving data
;;;    jsr SSC::HasData      ; Anything to read?
;;;    bne :+              ; Nope

:       jsr     ReceivePage
        jsr     FlipHires
        jmp     :-              ; TODO: define an exit trigger
        rts
.endproc


;;;---------------------------------------------------------
;;; Pull a hi-res page down over serial
;;;
;;; Protocol is:
;;;  * Recieve 256 bytes (graphic data)
;;;  * Send 1 byte (input state)

.proc ReceivePage
        lda     #0              ; set up write pointer
        sta     ZP_PTR
        lda     PAGE
        sta     ZP_PTR+1
        ldx     #PAGESIZE       ; plan to receive this many pages
        ldy     #0

:       jsr     SSC::Get        ; TODO: look for escape codes in the sequence
        sta     (ZP_PTR),Y
        iny
        bne     :-              ; Do a full page...

        jsr     SendInputState  ; brief moment to send data back upstream

        inc     ZP_PTR+1
        dex
        bne     :-              ; ...as many pages as we need
        rts
.endproc


;;;-------------------------------------------------------------------
;;;
;;; Input device routines
;;;
;;;-------------------------------------------------------------------
;;; Protocol:
;;;  $7f - $ff - key down, ASCII code + $80
;;;  otherwise, a transition:
;;;
        SIS_KBUP = $00          ; Key up
        SIS_OADOWN = $01        ; Open Apple transitioned to down
        SIS_OAUP = $02          ; Open Apple transitioned to up
        SIS_CADOWN = $03        ; Closed Apple transitioned to down
        SIS_CAUP = $04          ; Closed Apple transitioned to up
;;;
;;;  $05 - $0f : reserved
;;;
        SIS_MX = $10            ; Mouse X high nibble
        SIS_MY = $20            ; Mouse Y high nibble
        SIS_PDL0 = $30          ; Paddle 0 high nibble
        SIS_PDL1 = $40          ; Paddle 1 high nibble
;;;
;;;  $50 - $7e : reserved
;;;
        SIS_SYNC = $7f

;;;---------------------------------------------------------
;;; Initialize input devices and storage for detecting
;;; state transitions

.proc InitInput

;;; Init keyboard state
        lda     #SIS_KBUP
        sta     LASTKB

;;; Init Open/Closed Apple states
        lda     #SIS_OAUP       ; NOTE: Don't store OA state as it fluctuates
        sta     LASTOA
        lda     #SIS_CAUP       ; NOTE: Don't store CA state as it fluctuates
        sta     LASTCA

    .ifdef PADDLE_SUPPORT
;;; Init Paddle state
        lda     #SIS_PDL0
        ora     #8              ; Middle of range 0...15
        sta     LASTP0
        lda     #SIS_PDL1
        ora     #8              ; Middle of range 0...15
        sta     LASTP1
    .endif

    .ifdef MOUSE_SUPPORT
        jsr     Mouse::FindMouse
    .endif

        rts
.endproc


;;;---------------------------------------------------------
;;; Send keyboard joystick and/or mouse state over the
;;; serial port
;;;
;;; Algorithm:
;;; - Send key state (if it changed)
;;; - otherwise send open-apple state (if it changed)
;;; - otherwise send closed-apple state (if it changed)
;;; - otherwise send paddle 0 state (if it changed)
;;; - (TODO: Mouse state)
;;; - otherwise send sync byte

.proc SendInputState

        SaveRegisters           ; Store registers
        clc

;;;--------------------------------------
;;; Send key state, if it changed

;;; NOTE: Can't use KBDSTRB to detect key up -> key down transition
;;; since the msb can change before the key code. Instead, consider
;;; these cases:
;;;
;;;  OLD STATE    KBD       KBDSTRB    RESULT
;;;   Up           Up        -          No-op
;;;   Up           Down      -          Save and send key down
;;;   Down         -         Up         Save and send key up
;;;   Down         -         Down       Save and send key ONLY if different
;;;

        lda     LASTKB
        bne     KEY_WAS_DOWN

KEY_WAS_UP:
        lda     KBD             ; Read keyboard
        bpl     END_KEY         ; - still up
        sta     LASTKB          ; Down, so save it
        jsr     SSC::Put        ; and send it
        jmp     DONE

KEY_WAS_DOWN:
                                ; key was down - strobe should match
                                ; unless the key changed or was released
        lda     KBDSTRB
        bmi     KBDSTRB_DOWN
KBDSTRB_UP:
        lda     #SIS_KBUP       ; Key was released
        sta     LASTKB          ; so save it
        jsr     SSC::Put        ; and send it
        jmp     DONE
KBDSTRB_DOWN:
        cmp     LASTKB          ; Same key as last time?
        beq     END_KEY         ; - no change
        sta     LASTKB          ; New key, so save it
        jsr     SSC::Put        ; and send it
        jmp     DONE

END_KEY:

;;;--------------------------------------
;;; Send Open Apple state, if it changed

;;; TODO: Can simplify this code if we make the high bits the same
;;; for both OA states and bit = 0 down: lda BUTN0 ; ROL ; LDA #0 ; ROL ; ORA #signature

TEST_OA:
        lda     BUTN0           ; Test Open Apple state
        bmi     OA_IS_DOWN
OA_IS_UP:
        lda     #SIS_OAUP
        cmp     LASTOA          ; Changed?
        beq     END_OA          ; Nope
        sta     LASTOA          ; Yes, save it / send it!
        jsr     SSC::Put
        jmp     DONE
OA_IS_DOWN:
        lda     #SIS_OADOWN
        cmp     LASTOA          ; Changed?
        beq     END_OA          ; Nope
        sta     LASTOA          ; Yes, save it / send it!
        jsr     SSC::Put
        jmp     DONE

END_OA:

;;;--------------------------------------
;;; Send Closed Apple state, if it changed

TEST_CA:
        lda     BUTN1           ; Has the Open Apple/Button 1 value changed?
        bmi     CA_IS_DOWN
CA_IS_UP:
        lda     #SIS_CAUP
        cmp     LASTCA          ; Changed?
        beq     END_CA          ; Nope
        sta     LASTCA          ; Yes, save it
        jsr     SSC::Put        ; and send it
        jmp     DONE
CA_IS_DOWN:
        lda     #SIS_CADOWN
        cmp     LASTCA          ; Changed?
        beq     END_CA          ; Nope
        sta     LASTCA          ; Yes, save it
        jsr     SSC::Put        ; and send it
        jmp     DONE

END_CA:

    .ifdef PADDLE_SUPPORT

;;;--------------------------------------
;;; Send Paddle 0 state, if it changed
TEST_PDL0:
        ldx     #0
        jsr     PREAD
        tya
        lsr                     ; Shift to low nibble
        lsr
        lsr
        lsr
        ora     #SIS_PDL0       ; And mark it with the signature
        cmp     LASTP0          ; Change?
        beq     END_PDL0        ; Nope
        sta     LASTP0          ; Yes, save it
        jsr     SSC::Put        ; and send it
        jmp     DONE
END_PDL0:
                                ; Chew up time so next paddle read will be correct
                                ; TODO: Replace this with a "read both" strobes
                                ; routine
:       .repeat 11              ; By experiment, need 11 NOPs.
        nop
        .endrep
        iny
        bne     :-

;;;--------------------------------------
;;; Send Paddle 1 state, if it changed
TEST_PDL1:
        ldx     #1
        jsr     PREAD
        tya
        lsr                     ; Shift to low nibble
        lsr
        lsr
        lsr
        ora     #SIS_PDL1       ; And mark it with the signature
        cmp     LASTP1          ; Change?
        beq     END_PDL1        ; Nope
        sta     LASTP1          ; Yes, save it
        jsr     SSC::Put        ; and send it
        jmp     DONE
END_PDL1:
                                ; NOTE: No need to chew time like PDL0
                                ; since data receive will make up for it; if we
                                ; loop in SendInputState need to add it here

    .endif


;;;--------------------------------------
;;; No state changes so send sync byte

        lda     #SIS_SYNC
        jsr     SSC::Put

DONE:
        RestoreRegisters
        rts

.endproc


;;;-------------------------------------------------------------------
;;;
;;; Hi-res graphics routines
;;;
;;;-------------------------------------------------------------------

;;;---------------------------------------------------------
;;; Set up the graphics display and pointers

.proc InitHires
        lda     #PAGE1          ; clear page 1
        sta     PAGE
        jsr     HCLR

        jsr     FlipHires       ; then show it and flip to 2
        sta     HIRES
        sta     TXTCLR
        sta     MIXCLR
        sta     LOWSCR

        rts
.endproc


;;;---------------------------------------------------------
;;; Call when done with the current plotting page
;;; (selected in PAGE) and it will be shown and the
;;; other page will be shown.

.proc FlipHires
        lda     PAGE            ; plotting on which page?
        cmp     #PAGE1
        beq     :+

        sta     HISCR           ; page 2 - so show it
        lda     #PAGE1          ; and plot on page 1
        sta     PAGE
        rts

:       sta     LOWSCR          ; page 1 - so show it
        lda     #PAGE2          ; and plot on page 2
        sta     PAGE
        rts
.endproc
