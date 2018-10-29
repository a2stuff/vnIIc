;;;-------------------------------------------------------------------
;;;
;;; Serial port routines
;;;
;;; (based on ADTPro)
;;;
;;;-------------------------------------------------------------------

.proc SSC

;;;---------------------------------------------------------
.proc Init
;;;---------------------------------------------------------
;;; Initialize the SSC; slot passed in A
;;;---------------------------------------------------------
    asl                 ; Slot passed in A
    asl
    asl
    asl	    	        ; Now $S0
    adc #$88            ; Low byte of UADATA
    tax
    lda #CMND_NRDI      ; Command register: no parity, RTS on, DTR on, no interrupts
    sta $C002,X
    ldy PSPEED	        ; Control register: look up by baud rate (8 data bits, 1 stop bit)
    lda BPSCTRL,Y
    sta $C003,X
    stx MOD_UADATA_1+1	; Modify references to
    stx MOD_UADATA_2+1	; UADATA to point at
    stx MOD_UADATA_3+1	; correct slot (UADATA+S0)
    inx
    stx MOD_UASTAT_1+1	; Modify reference to
    stx MOD_UASTAT_2+1	; UASTAT to point at
    stx MOD_UASTAT_3+1  ; correct slot (UASTAT+S0)
    rts

.endproc


;;;---------------------------------------------------------
.proc Put
;;;---------------------------------------------------------
;;; Send accumulator out the serial port
;;;---------------------------------------------------------
    pha		    ; Push A onto the stack
MOD_UASTAT_1:
:   lda UASTAT	; Check status bits
    and #$70
    cmp #$10
    bne :-  	; Output register is full, so loop
    pla
MOD_UADATA_1:
    sta UADATA	; Put character
    rts
.endproc
        MOD_UASTAT_1 := Put::MOD_UASTAT_1
        MOD_UADATA_1 := Put::MOD_UADATA_1

;;;---------------------------------------------------------
.proc Get
;;;---------------------------------------------------------
;;; Read a character from the serial port to the accumulator
;;;---------------------------------------------------------
MOD_UASTAT_2:
	lda UASTAT	; Check status bits
    and #$68
    cmp #$8
    bne Get	; Input register empty, loop
MOD_UADATA_2:
	lda UADATA	; Get character
    rts
.endproc
        MOD_UASTAT_2 := Get::MOD_UASTAT_2
        MOD_UADATA_2 := Get::MOD_UADATA_2

;;;---------------------------------------------------------
.proc HasData
;;;---------------------------------------------------------
;;; Read a character from the serial port to the accumulator
;;;---------------------------------------------------------
MOD_UASTAT_3:
	lda UASTAT	; Check status bits
    and #$68
    cmp #$8
    rts
.endproc
        MOD_UASTAT_3 := HasData::MOD_UASTAT_3


;;;---------------------------------------------------------
.proc Reset
;;;---------------------------------------------------------
;;; Clean up serial port
;;;---------------------------------------------------------
MOD_UADATA_3:
	bit UADATA
    rts
.endproc
        MOD_UADATA_3 := Reset::MOD_UADATA_3

.endproc
