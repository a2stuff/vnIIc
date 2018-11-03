;;;-------------------------------------------------------------------
;;;
;;; Mouse
;;;
;;;-------------------------------------------------------------------
        ;;         .error "Mouse support not fully implemented"

.proc Mouse

;;;--------------------------------------------------
;;; Mouse Screen Holes
;;;--------------------------------------------------

;;; For ReadMouse and PosMouse

MOUSE_X_LSB     := $0478        ; + slot        Low byte of X coordinate
MOUSE_Y_LSB     := $04F8        ; + slot        Low byte of Y coordinate
MOUSE_X_MSB     := $0578        ; + slot        High byte of X coordinate
MOUSE_Y_MSB     := $05F8        ; + slot        High byte of Y coordinate
MOUSE_RSV1      := $0678        ; + slot        Reserved
MOUSE_RSV2      := $06F8        ; + slot        Reserved
MOUSE_STATUS    := $0778        ; + slot        Status byte
        ;; 7    Button down
        ;; 6    Button was down on last read and still down
        ;; 5    Movement since last read
        ;; 4    Reserved
        ;; 3    Interrupt from VBlInt
        ;; 2    Interrupt from button
        ;; 1    Interrupt from movement
        ;; 0    Reserved
MOUSE_MODE      := $07F8        ; + slot        Mode byte
        ;; 7-4  Reserved
        ;; 3    VBlInt active
        ;; 2    VBL interrupt on button
        ;; 1    VBL interrupt on movement
        ;; 0    Mouse active

;;; Scratch area for ClampMouse:

MOUSE_CMIN_LSB  := $0478        ; Low byte of clamping minimum
MOUSE_CMAX_LSB  := $04F8        ; Low byte of clamping maximum
MOUSE_CMIN_MSB  := $0578        ; High byte of clamping minimum
MOUSE_CMAX_MSB  := $05F8        ; High byte of clamping maximum

;;;--------------------------------------------------
;;; Mouse Constants
;;;--------------------------------------------------

MOUSE_CLAMP_X   := 0            ; Value for A when setting X clamp with ClampMouse
MOUSE_CLAMP_Y   := 1            ; Value for A when setting X clamp with ClampMouse

;;; Mouse ID bytes
MOUSEID_MAX     := 4
MOUSEID_ADDR:   .byte   $05, $07, $0b, $0c, $fb
MOUSEID_VAL:    .byte   $38, $18, $01, $20, $d6

SLOT_BASE       := $C000

;;;--------------------------------------------------
;;; Mouse firmware routine
;;;--------------------------------------------------

SetMouse        := $12          ; A=mode; C=0 on success
ServeMouse      := $13          ; C=0 mouse interrupt, C=1 other
ReadMouse       := $14
ClearMouse      := $15
PosMouse        := $16
ClampMouse      := $17
HomeMouse       := $18
InitMouse       := $19

.macro MOUSE_CALL routine
        ldy     routine
        jmp     CallMouse
.endmacro

;;;--------------------------------------------------
;;; Data
;;;--------------------------------------------------

;;; Mouse
mouse_slot:     .byte   0       ; mouse slot, or 0 if none
mouse_fw_hi:    .byte   0       ; mouse slot as $Cn
mouse_op:       .byte   0       ; mouse slot as $n0

mouse_ptr       := $EB          ; Zero page location

;;;--------------------------------------------------
;;; Routines
;;;--------------------------------------------------


MOUSE_CLAMP_MIN := $10
MOUSE_CLAMP_MAX := $1F
MOUSE_CENTER    := $17
MOUSE_POS_MASK  := $0F


;;;--------------------------------------------------
;;; Macros for common mouse operations
;;;--------------------------------------------------

;;;----------------------------------------
.macro DoClampMouse   axis, min, max
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
        MOUSE_CALL ClampMouse
.endmacro

;;;----------------------------------------
.macro DoPosMouse   px, py
;;;----------------------------------------
        ldx     mouse_slot
        lda     #<px
        sta     MOUSE_X_LSB,x
        lda     #>px
        sta     MOUSE_X_MSB,x
        lda     #<py
        sta     MOUSE_Y_LSB,x
        lda     #>py
        sta     MOUSE_Y_MSB,x
        MOUSE_CALL PosMouse
.endmacro

;;;----------------------------------------
.macro DoSetMouse   mode
;;;----------------------------------------
        lda     #mode
        MOUSE_CALL SetMouse
.endmacro


;;;---------------------------------------------------------
;;; Find and initialize the mouse port

.proc FindMouse

;;; Reference: http://home.swbell.net/rubywand/R034MOUSEPRG.TXT

        sei                     ; No interrupts while we're getting set up

        ;; Find mouse card by scanning slots for ID bytes

        ldy     #MAX_SLOT       ; Start search in slot 7

slot_loop:
        sty     mouse_slot      ; Save for later
        tya
        clc
        adc     #>SLOT_BASE     ; Firmware is $Cn
        sta     slot_addr + 1   ; Update msb of signature test
        ldx     #MOUSEID_MAX    ; This many signature bytes

:       lda     MOUSEID_ADDR,x
        sta     slot_addr       ; Update lsb of signature test

slot_addr       := *+1
        lda     SLOT_BASE       ; Self-modified
        cmp     MOUSEID_VAL,x   ; Does it match the signature?
        bne     no_match        ; Nope - try the next slot
        dex                     ; Yes! Keep testing
        bpl     :-              ; Fall through if all done
        jmp     found

no_match:
        dey                     ; Didn't match
        bne     slot_loop       ; Keep looking until slot 0
        sty     mouse_slot      ; Oops, no mouse - make a note
        rts                     ; and bail

        ;; Store results needed for call ($Cn and $n0)

found:  tya                     ; Slot is in y
        ora     #>SLOT_BASE     ; Compute $Cn - needed for calls
        sta     mouse_fw_hi

        tya
        asl                     ; Compute $n0 - needed for calls
        asl
        asl
        asl
        sta     mouse_op

        ;; Initialize and configure mouse card

        MOUSE_CALL InitMouse    ; reset, clamp to 0-1023 x/y

        DoSetMouse $01          ; mouse on, no interrupts
                                ; TODO: test carry bit result (set = error)

        ;; Clamp for deltas
        DoClampMouse MOUSE_CLAMP_X, MOUSE_CLAMP_MIN, MOUSE_CLAMP_MAX
        DoClampMouse MOUSE_CLAMP_Y, MOUSE_CLAMP_MIN, MOUSE_CLAMP_MAX

        DoPosMouse MOUSE_CENTER, MOUSE_CENTER

        cli                     ; Enable interrupts so mouse can function

        rts
.endproc

;;;--------------------------------------------------
;;; Call mouse firmware, param in A, routine in Y

.proc CallMouse
        pha                     ; Save A (param)
        ldx     mouse_fw_hi     ; $Cn
        stx     mouse_ptr+1
        lda     #0
        sta     mouse_ptr
        lda     (mouse_ptr),y  ; Look up routine offset
        sta     mouse_ptr

        pla                     ; param in A
        ldy     mouse_op        ; $n0 in Y

        php
        sei
        jsr     call
        plp
        rts

call:   jmp     (mouse_ptr)
.endproc

;;;--------------------------------------------------
;;; Read mouse pos, send deltas, and recenter

.proc SendMouse
        SaveRegisters
        lda     mouse_slot
        beq     done

        MOUSE_CALL ReadMouse

        lda     Protocol::MouseX
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put
        ldx     mouse_slot
        lda     MOUSE_X_LSB,x
        ora     MOUSE_POS_MASK
        jsr     SSC::Put

        lda     Protocol::MouseY
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put
        ldx     mouse_slot
        lda     MOUSE_Y_LSB,x
        ora     MOUSE_POS_MASK
        jsr     SSC::Put

        lda     Protocol::MouseBtn
        jsr     SSC::Put
        lda     #1              ; Data size
        jsr     SSC::Put
        ldx     mouse_slot
        lda     MOUSE_STATUS,x
        jsr     SSC::Put

        DoPosMouse MOUSE_CENTER, MOUSE_CENTER

done:   RestoreRegisters
        rts
.endproc

.endproc
