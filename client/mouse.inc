;;;-------------------------------------------------------------------
;;;
;;; Mouse
;;;
;;;-------------------------------------------------------------------
        .error "Mouse support not fully implemented"

.proc Mouse

;;;--------------------------------------------------
;;; Locations and constants
;;;--------------------------------------------------

;;; For READMOUSE and POSMOUSE

MOUSE_X_LSB     := $0478        ; + slot        Low byte of absolute X position
MOUSE_X_MSB     := $0578        ; + slot        High byte of absolute X position
MOUSE_Y_LSB     := $04F8        ; + slot        Low byte of absolute Y position
MOUSE_Y_MSB     := $05F8        ; + slot        High byte of absolute Y position
MOUSE_RSV1      := $0678        ; + slot        Reserved and used by the firmware
MOUSE_RSV2      := $06F8        ; + slot        Reserved and used by the firmware
MOUSE_BTN       := $0778        ; + slot        Button 0/1 interrupt status byte
MOUSE_MODE      := $07F8        ; + slot        Mode byte

;;; For CLAMPMOUSE:

MOUSE_CMIN_LSB  := $0478        ; low byte of low clamp
MOUSE_CMIN_MSB  := $0578        ; high byte of low clamp
MOUSE_CMAX_LSB  := $04F8        ; low byte of high clamp
MOUSE_CMAX_MSB  := $05F8        ; high byte of high clamp

MOUSE_CLAMP_X   := 0            ; Value for A when setting X clamp with CLAMPMOUSE
MOUSE_CLAMP_Y   := 1            ; Value for A when setting X clamp with CLAMPMOUSE

;;; Mouse ID bytes
MOUSEID_MAX     := 4
MOUSEID_ADDR:   .byte   $05, $07, $0b, $0c, $fb
MOUSEID_VAL:    .byte   $38, $18, $01, $20, $d6

SLOT_BASE       := $C000

;;;--------------------------------------------------
;;; Data
;;;--------------------------------------------------

;;; Mouse
MOUSE_SLOT:     .byte   0       ; mouse slot, or 0 if none
LAST_MX:        .byte   $7f
LAST_MY:        .byte   $7f


;;;--------------------------------------------------
;;; Routines
;;;--------------------------------------------------

MOUSEPTR        := $EB           ; Zero page location

MOUSE_MIN_X     := $10
MOUSE_MAX_X     := $1f
MOUSE_CENTER_X  := $17
MOUSE_MIN_Y     := $20
MOUSE_MAX_Y     := $2f
MOUSE_CENTER_Y  := $2f


;;;--------------------------------------------------
;;; Macros for common mouse operations
;;;--------------------------------------------------

;;;----------------------------------------
.macro ClampMouse   axis, min, max
;;;----------------------------------------
;;; axis: MOUSE_CLAMP_X or MOUSE_CLAMP_Y
;;; min:  minimum value (2 byte)
;;; max:  maximum value (2 byte)
;;;----------------------------------------
        lda     #<min
        sta     MOUSE_CMIN_LSB
        lda     #>min
        sta     MOUSE_CMIN_MSB
        lda     #<max
        sta     MOUSE_CMAX_LSB
        lda     #>max
        sta     MOUSE_CMAX_MSB
        lda     #axis
        jsr     CLAMPMOUSE
.endmacro

;;;----------------------------------------
.macro PosMouse   px, py
;;;----------------------------------------
        ldx     MOUSE_SLOT
        lda     #<px
        sta     MOUSE_X_LSB,X
        lda     #>px
        sta     MOUSE_X_MSB,X
        lda     #<py
        sta     MOUSE_Y_LSB,X
        lda     #>py
        sta     MOUSE_Y_MSB,X
        jsr     POSMOUSE
.endmacro


;;;---------------------------------------------------------
;;; Find and initialize the mouse port

.proc FindMouse

;;; Reference: http://home.swbell.net/rubywand/R034MOUSEPRG.TXT

        sei                     ; No interrupts while we're getting set up
                                ;
;;; Step 1: Find the mouse card by scanning slots for ID bytes
                                ;

        ldy     #MAX_SLOT       ; Start search in slot 7

TESTSLOT:
        sty     MOUSE_SLOT      ; Save for later
        tya
        clc
        adc     #>SLOT_BASE     ; Firmware is $c0 + slot
        sta     slot_addr + 1   ; Update msb of signature test
        ldx     #MOUSEID_MAX    ; This many signature bytes

TESTID:
        lda     MOUSEID_ADDR,x
        sta     MOD_MOUSE_ID + 1 ; Update lsb of signature test
slot_addr       := *+1
        lda     SLOT_BASE       ; Self-modified
        cmp     MOUSEID_VAL,x   ; Does it match the signature?
        bne     NOMATCH         ; Nope - try the next slot
        dex                     ; Yes! Keep testing
        bpl     TESTID          ; Fall through if all done
        jmp     FOUND_MOUSE

NOMATCH:
        dey                     ; Didn't match
        bne     TESTSLOT        ; Keep looking until slot 0
        sty     MOUSE_SLOT      ; Oops, no mouse - make a note
        rts                     ; and bail

                                ;
;;; Step 2: Set up indirect calling routines
                                ;

FOUND_MOUSE:
                                ; Slot is in y

        tya
        ora     #>SLOT_BASE     ; Compute $Cn - needed for
        sta     MOUSEPTR+1      ; MSB of MOUSEPTR ($Cn00)
        sta     TOMOUSE_Cn      ; X register before firmware calls
        sta     TOMOUSE_msb     ; MSB of firmware calls

        lda     #0
        sta     MOUSEPTR        ; LSB of MOUSEPTR ($Cn00)

        tya
        asl                     ; Compute $n0 - needed for
        asl
        asl
        asl
        sta     TOMOUSE_n0      ; Y register before firmware calls

                                ;
;;; Step 3: Configure the mouse card
                                ;

;;; Initialize the mouse for use
        jsr     INITMOUSE       ; reset, clamp to 0-1023 x/y
        lda     #1              ; mouse on, no interrupts
        jsr     SETMOUSE        ; TODO: test carry bit result (set = error)
                                ;
;;; Since we want deltas, clamp and center
                                ;
        ClampMouse MOUSE_CLAMP_X, MOUSE_MIN_X, MOUSE_MAX_X
        ClampMouse MOUSE_CLAMP_Y, MOUSE_MIN_Y, MOUSE_MAX_Y
        PosMouse MOUSE_CENTER_X, MOUSE_CENTER_Y

        cli                     ; Enable interrupts so mouse can function

        rts

.endproc


;;;--------------------------------------------------
;;; Indirect jump table for mouse firmware routines
;;;--------------------------------------------------

SETMOUSE:       ldy     #$12
        jmp     GoMouse
SERVEMOUSE:     ldy     #$13
        jmp     GoMouse
READMOUSE:      ldy     #$14
        jmp     GoMouse
CLEARMOUSE:     ldy     #$15
        jmp     GoMouse
POSMOUSE:       ldy     #$16
        jmp     GoMouse
CLAMPMOUSE:     ldy     #$17
        jmp     GoMouse
HOMEMOUSE:      ldy     #$18
        jmp     GoMouse
INITMOUSE:      ldy     #$19
        jmp     GoMouse

;;;--------------------------------------------------

.proc GoMouse
        tax                     ; Preserve the value in A
        lda     (MOUSEPTR),Y    ; Get the routine entry point
        sta     TOMOUSE_lsb     ; Patch the JMP instruction
        txa                     ; Restore the value in A

;;; The following operand bytes must be patched by the
;;; initialization code which detects the mouse.

BANK    := $C054

TOMOUSE:
TOMOUSE_Cn      := *+1
        ldx     #$C1            ; Set up slot in $Cn form in X
TOMOUSE_n0      := *+1
        ldy     #$10            ; Set up slot in $n0 form in Y
        php                     ; Save interrupt state
        sei                     ; No interrupts while calling
        bit     BANK
TOMOUSE_slot    := *+1
        jsr     0               ; Go to the mouse routine
        plp                     ; Restore interrupt state
        rts
.endproc

TOMOUSE_Cn      := GoMouse::TOMOUSE_Cn
TOMOUSE_n0      := GoMouse::TOMOUSE_n0
TOMOUSE_lsb     := GoMouse::TOMOUSE_slot
TOMOUSE_msb     := GoMouse::TOMOUSE_slot+1


;;; TODO: Turn this into a proper delta-sending routine

;;;--------------------------------------------------
.proc FOOMOUSE

        txa                     ; save x
        pha
        tya                     ; save y
        pha

        jsr     READMOUSE

        jmp     DONE

        ldx     MOUSE_SLOT

        lda     MOUSE_X_LSB,x
        sta     LAST_MX

        lda     MOUSE_Y_LSB,x
        sta     LAST_MY

        lda     LAST_MX
        cmp     #MOUSE_CENTER_X
        bne     SEND

        lda     LAST_MY
        cmp     #MOUSE_CENTER_Y
        beq     DONE

SEND:
        lda     LAST_MX
        ora     #SIS_MX
        jsr     SSC::Put
        lda     LAST_MY
        ora     #SIS_MY
        jsr     SSC::Put

        PosMouse MOUSE_CENTER_X, MOUSE_CENTER_Y

DONE:
        pla                     ; restore y
        tay
        pla                     ; restore x
        tax
        rts

.endproc

.endproc
