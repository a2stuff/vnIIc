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

PREAD   := $FB1E                  ; Monitor paddle reading routine, call
                                ; with paddle # in X, returns value in Y

HCLR    := $F3F2                      ; Clear current hires screen to black

;;;---------------------------------------------------------
;;; Other
;;;---------------------------------------------------------

MAX_SLOT        := 7             ; Maximum slot # on an Apple II

ZP_PTR  := $FA                   ; Write cursor location on zero page

;;;-------------------------------------------------------------------
;;; Protocol:
;;;-------------------------------------------------------------------

.proc Protocol
        Keyboard := $00

        Button0  := $10
        Button1  := $11

        Paddle0  := $20
        Paddle1  := $21

        MouseX   := $30
        MouseY   := $31
        MouseBtn := $32

        Screen   := $80
.endproc


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


;;;---------------------------------------------------------
;;; Initialize the application, and enter the main loop

.proc AppEntry
        lda     PSLOT           ; Use slot 2
        jsr     SSC::Init       ; Initialize Super Serial Card
        jsr     InitHires       ; Initialize Hi-Res graphics
        jsr     InitInput       ; Initialize input devices
        jsr     MainLoop
        ;; fall through
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
        ;; Input is sent every 256 bytes (32 times per page)
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
        lda     #Protocol::Screen
        jsr     SSC::Put
        lda     #0              ; data size
        jsr     SSC::Put


        lda     #0              ; set up write pointer
        sta     ZP_PTR
        lda     PAGE
        sta     ZP_PTR+1
        ldx     #PAGESIZE       ; plan to receive this many pages
        ldy     #0

:       jsr     SSC::Get
        sta     (ZP_PTR),Y
        iny
        bne     :-              ; Do a full page...

        ;; Interleave to maintain responsiveness
        jsr     SendInputState

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

;;;---------------------------------------------------------
;;; Initialize input devices and storage for detecting
;;; state transitions

.proc InitInput

    .ifdef MOUSE_SUPPORT
        jsr     Mouse::FindMouse
    .endif

        rts
.endproc


;;;---------------------------------------------------------
;;; Send a full set of input state updates.

;;; Assumes time to transmit is roughly comparable to time
;;; to measure input state, therefore only sending changes is
;;; not worthwhile in most cases.

.proc SendInputState
        jsr     MaybeSendKeyboard
        jsr     SendButtons

    .ifdef PADDLE_SUPPORT
        jsr     SendPaddles
    .endif

    .ifdef MOUSE_SUPPORT
        jsr     SendMouse
    .endif

.endproc


;;;------------------------------------------------------------
;;; Keyboard

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

last_kb:        .byte   0

.proc MaybeSendKeyboard
        lda     last_kb
        bne     key_was_down

key_was_up:
        ;; Key was up - send only if now down.
        lda     KBD             ; Read keyboard
        bpl     done            ; Do nothing if it is still up.
        jmp     send            ; Otherwise send.

key_was_down:
        ;; Key was down - strobe should match
        ;; unless the key changed or was released.
        lda     KBDSTRB
        bmi     kbdstrb_down

kbdstrb_up:
        lda     #0              ; Now released
        jmp     send

kbdstrb_down:
        cmp     last_kb         ; Same key as last time?
        beq     done            ; - no change, don't send.
        jmp     send

send:   sta     last_kb
        lda     Protocol::Keyboard
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put
        lda     last_kb
        jsr     SSC::Put

done:   rts
.endproc

;;;------------------------------------------------------------
;;; Buttons

.proc SendButtons

        lda     Protocol::Button0
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put
        lda     BUTN0
        jsr     SSC::Put

        lda     Protocol::Button1
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put
        lda     BUTN1
        jsr     SSC::Put

        rts
.endproc

;;;------------------------------------------------------------
;;; Paddles

    .ifdef PADDLE_SUPPORT
.proc SendPaddles

        lda     Protocol::Paddle0
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put

        ldx     #0
        jsr     PREAD
        tya
        jsr     SSC::Put

        ;; Assumes at least 11 cycles to send, so
        ;; timer has a chance to reset.

        lda     Protocol::Paddle1
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put

        ldx     #1
        jsr     PREAD
        tya
        jsr     SSC::Put

        rts
.endproc
    .endif

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
