;;;-------------------------------------------------------------------
;;;
;;; Serial port routines
;;;
;;; (based on ADTPro)
;;;
;;;-------------------------------------------------------------------

.proc SSC

;;;---------------------------------------------------------
;;; Super Serial constants/locations
;;;---------------------------------------------------------

;;; These get incremented by the slot where they appear
        UACTRL = $C08B          ; Control Register
        UACMND = $C08A          ; Command Register
        UASTAT = $C089          ; Status Register
        UADATA = $C088          ; Data Register - incoming and outgoing data

;;; Lookup table for UACTRL register, by baud rate

BPSCTRL:        .byte   $16,$1E,$1F,$10 ; 300, 9600, 19200, 115k (with 8 data bits, 1 stop bit, no echo)
        .enum
        BPS_300
        BPS_9600
        BPS_19200
        BPS_115k
        .endenum

        CMND_NRDI = $0B         ; Command: no parity, RTS on, DTR on, no interrupts


;;;---------------------------------------------------------
;;; Initialize the SSC; slot passed in A

.proc Init
        asl                     ; Slot passed in A
        asl
        asl
        asl                     ; Now $S0
        adc     #$88            ; Low byte of UADATA
        tax
        lda     #CMND_NRDI      ; Command register: no parity, RTS on, DTR on, no interrupts
        sta     $C002,X
        ldy     PSPEED          ; Control register: look up by baud rate (8 data bits, 1 stop bit)
        lda     BPSCTRL,Y
        sta     $C003,X
        stx     MOD_UADATA_1    ; Modify references to
        stx     MOD_UADATA_2    ; UADATA to point at
        stx     MOD_UADATA_3    ; correct slot (UADATA+S0)
        inx
        stx     MOD_UASTAT_1    ; Modify reference to
        stx     MOD_UASTAT_2    ; UASTAT to point at
        stx     MOD_UASTAT_3    ; correct slot (UASTAT+S0)
        rts
.endproc


;;;---------------------------------------------------------
;;; Send accumulator out the serial port

.proc Put
        pha                     ; Push A onto the stack
MOD_UASTAT_1    := *+1
:       lda     UASTAT          ; Check status bits
        and     #$10
        beq     :-              ; Output register is full, so loop
        pla
MOD_UADATA_1    := *+1
        sta     UADATA          ; Put character
        rts
.endproc
MOD_UASTAT_1    := Put::MOD_UASTAT_1
MOD_UADATA_1    := Put::MOD_UADATA_1

;;;---------------------------------------------------------
;;; Read a character from the serial port to the accumulator

.proc Get
MOD_UASTAT_2    := *+1
        lda     UASTAT          ; Check status bits
        and     #$8
        beq     Get             ; Input register empty, loop
MOD_UADATA_2    := *+1
        lda     UADATA          ; Get character
        rts
.endproc
MOD_UASTAT_2    := Get::MOD_UASTAT_2
MOD_UADATA_2    := Get::MOD_UADATA_2

;;;---------------------------------------------------------
;;; Check if the serial port has pending data

.proc HasData
MOD_UASTAT_3    := *+1
        lda     UASTAT          ; Check status bits
        and     #$68
        cmp     #$8
        rts
.endproc
MOD_UASTAT_3    := HasData::MOD_UASTAT_3


;;;---------------------------------------------------------
;;; Clean up serial port

.proc Reset
MOD_UADATA_3    := *+1
        bit     UADATA
        rts
.endproc
MOD_UADATA_3    := Reset::MOD_UADATA_3

.endproc
