
PADDLE_SUPPORT = 1
;MOUSE_SUPPORT  = 1   ; NOTE: tests for ifdef

;---------------------------------------------------------
; Super Serial constants/locations
;---------------------------------------------------------

; These get incremented by the slot where they appear
UACTRL   = $C08B   ; Control Register
UACMND   = $C08A   ; Command Register
UASTAT   = $C089   ; Status Register
UADATA   = $C088   ; Data Register - incoming and outgoing data


;---------------------------------------------------------
; Hi-res graphics constants/locations
;---------------------------------------------------------

PLOTPAGE  = $E6 ; Active hires plotting page (Applesoft)
PLOTPAGE1 = $20
PLOTPAGE2 = $40
PAGESIZE  = $20 ; Size of hi-res screen in pages


CLRTEXT  = $C050 ;display graphics
SETTEXT  = $C051 ;display text
CLRMIXED = $C052 ;clear mixed mode- enable full graphics
SETMIXED = $C053 ;enable graphics/text mixed mode
PAGE1    = $C054 ;select text/graphics page1
PAGE2    = $C055 ;select text/graphics page2
CLRHIRES = $C056 ;select Lo-res
SETHIRES = $C057 ;select Hi-res 


;---------------------------------------------------------
; Keyboard input constants/locations
;---------------------------------------------------------

KEYBD     =   $C000 ; key down in bit 7; key code in lower bits
STROBE    =   $C010 ; write to clear key down state
OPNAPPLE  =   $C061 ; open apple (command) key data (read)
CLSAPPLE  =   $C062 ; closed apple (option) key data (read)
PB2       =   $C063 ; Paddle button 2 (read) 
PB3       =   $C060 ; Paddle button 3 (read) 


;---------------------------------------------------------
; Paddle/Joystick constants/locations/routines
;---------------------------------------------------------

PADDLE0 =  $C064    ; bit 7 = status of pdl-0 timer (read) 
PADDLE1 =  $C065    ; bit 7 = status of pdl-1 timer (read)
PADDLE2 =  $C066    ; bit 7 = status of pdl-2 timer (read)
PADDLE3 =  $C067    ; bit 7 = status of pdl-3 timer (read)
PDLTRIG =  $C070    ; trigger paddles 

PREAD   =  $FB1E    ; Monitor paddle reading routine, call
                    ; with paddle # in X, returns value in Y


;--------------------------------------------------
; Mouse locations and constants
;--------------------------------------------------

; For READMOUSE and POSMOUSE
    
MOUSE_X_LSB = $0478     ; + slot        Low byte of absolute X position
MOUSE_X_MSB = $0578     ; + slot        High byte of absolute X position
MOUSE_Y_LSB = $04F8     ; + slot        Low byte of absolute Y position
MOUSE_Y_MSB = $05F8     ; + slot        High byte of absolute Y position
MOUSE_RSV1  = $0678     ; + slot        Reserved and used by the firmware
MOUSE_RSV2  = $06F8     ; + slot        Reserved and used by the firmware
MOUSE_BTN   = $0778     ; + slot        Button 0/1 interrupt status byte
MOUSE_MODE  = $07F8     ; + slot        Mode byte

; For CLAMPMOUSE:
                        
MOUSE_CMIN_LSB = $0478   ; low byte of low clamp
MOUSE_CMIN_MSB = $0578   ; high byte of low clamp
MOUSE_CMAX_LSB = $04F8   ; low byte of high clamp
MOUSE_CMAX_MSB = $05F8   ; high byte of high clamp

MOUSE_CLAMP_X   = 0     ; Value for A when setting X clamp with CLAMPMOUSE
MOUSE_CLAMP_Y   = 1     ; Value for A when setting X clamp with CLAMPMOUSE


;---------------------------------------------------------
; Other
;---------------------------------------------------------

SLOT_CASE =   $c000 ; Firmware for slots are at $cx00
MAX_SLOT  =   7     ; Maximum slot # on an Apple II

ZP        =   $FA   ; Write cursor location on zero page
ESCAPE    =   $80   ; Unused image data byte (all black2)
ESCAPE2   =   $FF   ; Unused image data byte (all white2)


;---------------------------------------------------------
; Generic Macros
;---------------------------------------------------------

;----------------------------------------
.macro SaveRegisters
;----------------------------------------
    pha
    txa
    pha
    tya
    pha
.endmacro

;----------------------------------------
.macro RestoreRegisters
;----------------------------------------
    pla
    tay
    pla
    tax
    pla
.endmacro


;-------------------------------------------------------------------
; 
; Application-level logic
;
;-------------------------------------------------------------------


.ORG $6000

;---------------------------------------------------------
.proc APP_ENTRY
;---------------------------------------------------------
; Initialize the application, and enter the main loop
;---------------------------------------------------------
    lda PSLOT          ; Use slot 2
    jsr INITSSC        ; Initialize Super Serial Card
    jsr INITHIRES      ; Initialize Hi-Res graphics 
    jsr INITINPUT      ; Initialize input devices
    jsr MAINLOOP

    ; fall through
.endproc
    
;---------------------------------------------------------
.proc APP_EXIT
;---------------------------------------------------------
; Clean up and exit app
;---------------------------------------------------------
    jsr RESETSSC
    sta PAGE1
    sta SETTEXT
    rts
.endproc


;-------------------------------------------------------------------
; 
; Main loop functionality
;
;-------------------------------------------------------------------


;---------------------------------------------------------
.proc MAINLOOP
;---------------------------------------------------------

; TODO: Sort out the protocol - should be able to send
; input state without receiving data
;    jsr SSCHASDATA      ; Anything to read?
;    bne :+              ; Nope

:   jsr RECEIVEPAGE
    jsr FLIPHIRES
    jmp :-              ; TODO: define an exit trigger
    rts
.endproc

    
;---------------------------------------------------------
.proc RECEIVEPAGE
;---------------------------------------------------------
; Pull a hi-res page down over serial
;
; Protocol is:
;  * Recieve 256 bytes (graphic data)
;  * Send 1 byte (input state)
;---------------------------------------------------------
    
    lda #0        ; set up write pointer
    sta ZP
    lda PLOTPAGE
    sta ZP+1
    ldx #PAGESIZE ; plan to receive this many pages
    ldy #0
    
:   jsr SSCGET   ; TODO: look for escape codes in the sequence
    sta (ZP),Y
    iny
    bne :-       ; Do a full page...

    jsr SENDINPUTSTATE ; brief moment to send data back upstream

    inc ZP+1
    dex
    bne :-       ; ...as many pages as we need
    rts
.endproc


;-------------------------------------------------------------------
; 
; Input device routines
;
;-------------------------------------------------------------------
; Protocol:
;  $7f - $ff - key down, ASCII code + $80
;  otherwise, a transition:
;
    SIS_KBUP    = $00   ; Key up
    SIS_OADOWN  = $01   ; Open Apple transitioned to down
    SIS_OAUP    = $02   ; Open Apple transitioned to up
    SIS_CADOWN  = $03   ; Closed Apple transitioned to down
    SIS_CAUP    = $04   ; Closed Apple transitioned to up
;   
;  $05 - $0f : reserved
;
    SIS_MX      = $10   ; Mouse X high nibble
    SIS_MY      = $20   ; Mouse Y high nibble
    SIS_PDL0    = $30   ; Paddle 0 high nibble
    SIS_PDL1    = $40   ; Paddle 1 high nibble
;   
;  $50 - $7e : reserved
;
    SIS_SYNC    = $7f

;---------------------------------------------------------
.proc INITINPUT
;---------------------------------------------------------
; Initialize input devices and storage for detecting
; state transitions
;---------------------------------------------------------

; Init keyboard state    
    lda #SIS_KBUP
    sta LASTKB

; Init Open/Closed Apple states
    lda #SIS_OAUP       ; NOTE: Don't store OA state as it fluctuates
    sta LASTOA
    lda #SIS_CAUP       ; NOTE: Don't store CA state as it fluctuates
    sta LASTCA

.ifdef PADDLE_SUPPORT
; Init Paddle state
    lda #SIS_PDL0
    ora #8              ; Middle of range 0...15
    sta LASTP0
    lda #SIS_PDL1
    ora #8              ; Middle of range 0...15
    sta LASTP1
.endif

.ifdef MOUSE_SUPPORT
    jsr FINDMOUSE
.endif    

    rts
.endproc


;---------------------------------------------------------
.proc SENDINPUTSTATE
;---------------------------------------------------------
; Send keyboard joystick and/or mouse state over the 
; serial port
;
; Algorithm:
; - Send key state (if it changed)
; - otherwise send open-apple state (if it changed)
; - otherwise send closed-apple state (if it changed)
; - otherwise send paddle 0 state (if it changed)
; - (TODO: Mouse state)
; - otherwise send sync byte
;---------------------------------------------------------

    SaveRegisters       ; Store registers
    clc
    
;--------------------------------------
; Send key state, if it changed

; NOTE: Can't use STROBE to detect key up -> key down transition
; since the msb can change before the key code. Instead, consider
; these cases:
;
;  OLD STATE    KEYBD     STROBE     RESULT
;   Up           Up        -          No-op
;   Up           Down      -          Save and send key down
;   Down         -         Up         Save and send key up
;   Down         -         Down       Save and send key ONLY if different
;

    lda LASTKB
    bne KEY_WAS_DOWN

KEY_WAS_UP:
    lda KEYBD           ; Read keyboard
    bpl END_KEY         ; - still up 
    sta LASTKB          ; Down, so save it
    jsr SSCPUT          ; and send it
    jmp DONE
    
KEY_WAS_DOWN:
    ; key was down - strobe should match
    ; unless the key changed or was released
    lda STROBE
    bmi STROBE_DOWN
STROBE_UP:
    lda #SIS_KBUP       ; Key was released
    sta LASTKB          ; so save it
    jsr SSCPUT          ; and send it
    jmp DONE
STROBE_DOWN:    
    cmp LASTKB          ; Same key as last time?
    beq END_KEY         ; - no change
    sta LASTKB          ; New key, so save it
    jsr SSCPUT          ; and send it        
    jmp DONE
    
END_KEY:

;--------------------------------------
; Send Open Apple state, if it changed

; TODO: Can simplify this code if we make the high bits the same
; for both OA states and bit = 0 down: lda OPNAPPLE ; ROL ; LDA #0 ; ROL ; ORA #signature

TEST_OA:    
    lda OPNAPPLE        ; Test Open Apple state
    bmi OA_IS_DOWN
OA_IS_UP:   
    lda #SIS_OAUP           
    cmp LASTOA          ; Changed?
    beq END_OA          ; Nope
    sta LASTOA          ; Yes, save it / send it!
    jsr SSCPUT
    jmp DONE
OA_IS_DOWN:
    lda #SIS_OADOWN
    cmp LASTOA          ; Changed?
    beq END_OA          ; Nope
    sta LASTOA          ; Yes, save it / send it!
    jsr SSCPUT
    jmp DONE

END_OA:

;--------------------------------------
; Send Closed Apple state, if it changed

TEST_CA:    
    lda CLSAPPLE        ; Has the Open Apple/Button 1 value changed?
    bmi CA_IS_DOWN
CA_IS_UP:   
    lda #SIS_CAUP
    cmp LASTCA          ; Changed?
    beq END_CA          ; Nope
    sta LASTCA          ; Yes, save it
    jsr SSCPUT          ; and send it
    jmp DONE
CA_IS_DOWN:
    lda #SIS_CADOWN
    cmp LASTCA          ; Changed?
    beq END_CA          ; Nope
    sta LASTCA          ; Yes, save it
    jsr SSCPUT          ; and send it
    jmp DONE

END_CA:

.ifdef PADDLE_SUPPORT

;--------------------------------------
; Send Paddle 0 state, if it changed
TEST_PDL0:
    ldx #0
    jsr PREAD
    tya
    lsr                 ; Shift to low nibble
    lsr
    lsr
    lsr
    ora #SIS_PDL0       ; And mark it with the signature
    cmp LASTP0          ; Change?
    beq END_PDL0        ; Nope
    sta LASTP0          ; Yes, save it
    jsr SSCPUT          ; and send it
    jmp DONE
END_PDL0:    
    ; Chew up time so next paddle read will be correct
    ; TODO: Replace this with a "read both" strobes
    ; routine
:   .repeat 11          ; By experiment, need 11 NOPs. 
    nop
    .endrep
    iny
    bne :-

;--------------------------------------
; Send Paddle 1 state, if it changed
TEST_PDL1:
    ldx #1
    jsr PREAD
    tya
    lsr                 ; Shift to low nibble
    lsr
    lsr
    lsr
    ora #SIS_PDL1       ; And mark it with the signature
    cmp LASTP1          ; Change?
    beq END_PDL1        ; Nope
    sta LASTP1          ; Yes, save it
    jsr SSCPUT          ; and send it
    jmp DONE
END_PDL1:    
    ; NOTE: No need to chew time like PDL0 
    ; since data receive will make up for it; if we
    ; loop in SENDINPUTSTATE need to add it here
    
.endif    

   
;--------------------------------------
.ifdef MOUSE_SUPPORT
    .error "Mouse support not fully implemented"
.endif

;--------------------------------------
; No state changes so send sync byte

    lda #SIS_SYNC
    jsr SSCPUT

DONE:
    RestoreRegisters
    rts
    
.endproc


;-------------------------------------------------------------------
; 
; Hi-res graphics routines
;
;-------------------------------------------------------------------

;---------------------------------------------------------
.proc INITHIRES
;---------------------------------------------------------
; Set up the graphics display and pointers
;---------------------------------------------------------
    lda #PLOTPAGE1   ; clear page 1
    sta PLOTPAGE
    jsr CLEARHIRES

    jsr FLIPHIRES    ; then show it and flip to 2
    sta SETHIRES
    sta CLRTEXT      
    sta CLRMIXED  
    sta PAGE1   

    rts
.endproc


;---------------------------------------------------------
.proc FLIPHIRES
;---------------------------------------------------------
; Call when done with the current plotting page 
; (selected in PLOTPAGE) and it will be shown and the 
; other page will be shown.
;---------------------------------------------------------
    lda PLOTPAGE        ; plotting on which page?
    cmp #PLOTPAGE1
    beq :+

    sta PAGE2           ; page 2 - so show it
    lda #PLOTPAGE1      ; and plot on page 1
    sta PLOTPAGE
    rts

:   sta PAGE1           ; page 1 - so show it
    lda #PLOTPAGE2      ; and plot on page 2
    sta PLOTPAGE
    rts
.endproc
    

;---------------------------------------------------------
.proc CLEARHIRES
;---------------------------------------------------------
; Clear hires plotting page (selected in PLOTPAGE) to
; black uses ZP; not terribly efficient
;---------------------------------------------------------
   lda #0           ; Set up ZP as a pointer into the hires page
   sta ZP
   lda PLOTPAGE
   sta ZP+1
   ldx #PAGESIZE    ; Clear this many pages
   lda #0           ; with black!
   tay
:  sta (ZP),Y 
   iny
   bne :-
   inc ZP+1
   dex
   bne :-
   rts 
.endproc



;-------------------------------------------------------------------
; 
; Serial port routines
;
;-------------------------------------------------------------------


;---------------------------------------------------------
.proc INITSSC
;---------------------------------------------------------
; Initialize the SSC; slot passed in A
; [based on ADTPro]
;---------------------------------------------------------
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


;---------------------------------------------------------
SSCPUT:
;---------------------------------------------------------
; Send accumulator out the serial port
; (this is a blocking call)
; [based on ADTPro]
;---------------------------------------------------------
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


;---------------------------------------------------------
SSCGET:
;---------------------------------------------------------
; Read a character from the serial port to the accumulator
; (this is a blocking call)
; [based on ADTPro]
;---------------------------------------------------------
MOD_UASTAT_2:
	lda UASTAT	; Check status bits
    and #$68
    cmp #$8
    bne SSCGET	; Input register empty, loop
MOD_UADATA_2:
	lda UADATA	; Get character
    rts


;---------------------------------------------------------
SSCHASDATA:
;---------------------------------------------------------
; Read a character from the serial port to the accumulator
; (this is a blocking call)
; [based on ADTPro]
;---------------------------------------------------------
MOD_UASTAT_3:
	lda UASTAT	; Check status bits
    and #$68
    cmp #$8
    rts


;---------------------------------------------------------
RESETSSC:
;---------------------------------------------------------
; Clean up serial port
; [based on ADTPro]
;---------------------------------------------------------
MOD_UADATA_3:
	bit UADATA
    rts



.ifdef MOUSE_SUPPORT
;-------------------------------------------------------------------
; 
; Mouse routines
;
;-------------------------------------------------------------------

MOUSEPTR = $EB              ; Zero page location

MOUSE_MIN_X    = $10
MOUSE_MAX_X    = $1f
MOUSE_CENTER_X = $17
MOUSE_MIN_Y    = $20
MOUSE_MAX_Y    = $2f
MOUSE_CENTER_Y = $2f


;--------------------------------------------------
; Macros for common mouse operations
;--------------------------------------------------

;----------------------------------------
.macro ClampMouse   axis, min, max
;----------------------------------------
; axis: MOUSE_CLAMP_X or MOUSE_CLAMP_Y
; min:  minimum value (2 byte)
; max:  maximum value (2 byte)
;----------------------------------------
    ; Clamp X to 0...255
    lda #<min
    sta MOUSE_CMIN_LSB
    lda #>min
    sta MOUSE_CMIN_MSB
    lda #<max
    sta MOUSE_CMAX_LSB
    lda #>max
    sta MOUSE_CMAX_MSB
    lda #axis
    jsr CLAMPMOUSE
.endmacro

;----------------------------------------
.macro PosMouse   px, py
;----------------------------------------
    ldx MOUSE_SLOT
    lda #<px
    sta MOUSE_X_LSB,X
    lda #>px
    sta MOUSE_X_MSB,X
    lda #<py
    sta MOUSE_Y_LSB,X
    lda #>py
    sta MOUSE_Y_MSB,X
    jsr POSMOUSE    
.endmacro


;---------------------------------------------------------
.proc FINDMOUSE
;---------------------------------------------------------
; Find and initialize the mouse port
;---------------------------------------------------------

; Reference: http://home.swbell.net/rubywand/R034MOUSEPRG.TXT

    sei                     ; No interrupts while we're getting set up
;
; Step 1: Find the mouse card by scanning slots for ID bytes
;

    ldy #MAX_SLOT           ; Start search in slot 7
    
TESTSLOT:
    sty MOUSE_SLOT          ; Save for later
    tya
    clc
    adc #>SLOT_BASE         ; Firmware is $c0 + slot
    sta MOD_MOUSE_ID + 2    ; Update msb of signature test
    ldx #MOUSEID_MAX        ; This many signature bytes

TESTID:
    lda MOUSEID_ADDR,x
    sta MOD_MOUSE_ID + 1    ; Update lsb of signature test
MOD_MOUSE_ID: 
    lda SLOT_BASE
    cmp MOUSEID_VAL,x       ; Does it match the signature?
    bne NOMATCH             ; Nope - try the next slot
    dex                     ; Yes! Keep testing
    bpl TESTID              ; Fall through if all done
    jmp FOUND_MOUSE
    
NOMATCH:
    dey                     ; Didn't match
    bne TESTSLOT            ; Keep looking until slot 0
    sty MOUSE_SLOT          ; Oops, no mouse - make a note
    rts                     ; and bail

;
; Step 2: Set up indirect calling routines
;
    
FOUND_MOUSE:    
    ; Slot is in y

    tya                     
    ora #>SLOT_BASE         ; Compute $Cn - needed for 
    sta MOUSEPTR+1          ; MSB of MOUSEPTR ($Cn00)
    sta TOMOUSE_Cn          ; X register before firmware calls
    sta TOMOUSE_msb         ; MSB of firmware calls

    lda #0
    sta MOUSEPTR            ; LSB of MOUSEPTR ($Cn00)

    tya
    asl                     ; Compute $n0 - needed for
    asl
    asl
    asl
    sta TOMOUSE_n0          ; Y register before firmware calls
    
;
; Step 3: Configure the mouse card
;

; Initialize the mouse for use
    jsr INITMOUSE       ; reset, clamp to 0-1023 x/y
    lda #1              ; mouse on, no interrupts
    jsr SETMOUSE        ; TODO: test carry bit result (set = error)
;
; Since we want deltas, clamp and center
;
    ClampMouse  MOUSE_CLAMP_X, MOUSE_MIN_X, MOUSE_MAX_X
    ClampMouse  MOUSE_CLAMP_Y, MOUSE_MIN_Y, MOUSE_MAX_Y
    PosMouse MOUSE_CENTER_X, MOUSE_CENTER_Y

    cli                 ; Enable interrupts so mouse can function
    
    rts

.endproc 


;--------------------------------------------------
; Indirect jump table for mouse firmware routines
;--------------------------------------------------

SETMOUSE:       ldy #$12
                jmp GOMOUSE
SERVEMOUSE:     ldy #$13
                jmp GOMOUSE
READMOUSE:      ldy #$14
                jmp GOMOUSE
CLEARMOUSE:     ldy #$15
                jmp GOMOUSE
POSMOUSE:       ldy #$16
                jmp GOMOUSE
CLAMPMOUSE:     ldy #$17
                jmp GOMOUSE
HOMEMOUSE:      ldy #$18
                jmp GOMOUSE
INITMOUSE:      ldy #$19
                jmp GOMOUSE

;--------------------------------------------------
.proc GOMOUSE
;--------------------------------------------------
    tax                 ; Preserve the value in A
    lda (MOUSEPTR),Y    ; Get the routine entry point
    sta TOMOUSE_lsb     ; Patch the JMP instruction
    txa                 ; Restore the value in A
.endproc
    ; fall through
        
; The following operand bytes must be patched by the
; initialization code which detects the mouse.

BANK       = $C054

TOMOUSE:
    ldx #$C1            ; Set up slot in $Cn form in X
    ldy #$10            ; Set up slot in $n0 form in Y
    php                 ; Save interrupt state
    sei                 ; No interrupts while calling
    bit BANK
    jsr SLOT_BASE       ; Go to the mouse routine
    plp                 ; Restore interrupt state
    rts
    
TOMOUSE_Cn   = TOMOUSE + 1    
TOMOUSE_n0   = TOMOUSE + 3    
TOMOUSE_lsb  = TOMOUSE + 10
TOMOUSE_msb  = TOMOUSE + 11
    

; TODO: Turn this into a proper delta-sending routine

;--------------------------------------------------
.proc FOOMOUSE
;--------------------------------------------------
; 
;--------------------------------------------------
    txa                 ; save x
    pha
    tya                 ; save y
    pha
    
    jsr READMOUSE
    
    jmp DONE
    
    ldx MOUSE_SLOT
    
    lda MOUSE_X_LSB,x
    sta LAST_MX

    lda MOUSE_Y_LSB,x
    sta LAST_MY
    
    lda LAST_MX
    cmp #MOUSE_CENTER_X    
    bne SEND

    lda LAST_MY
    cmp #MOUSE_CENTER_Y
    beq DONE
    
SEND:
    lda LAST_MX
    ora #SIS_MX
    jsr SSCPUT    
    lda LAST_MY
    ora #SIS_MY
    jsr SSCPUT    
    
    PosMouse MOUSE_CENTER_X, MOUSE_CENTER_Y

DONE:
    pla                 ; restore y
    tay
    pla                 ; restore x
    tax
    rts
    
.endproc

.endif ; MOUSE_SUPPORT


;-------------------------------------------------------------------
; 
; Lookup Tables and Variable Storage
;
;-------------------------------------------------------------------

; Lookup table for UACTRL register, by baud rate

BPSCTRL:	.byte $16,$1E,$1F,$10	; 300, 9600, 19200, 115k (with 8 data bits, 1 stop bit, no echo)
.enum
    BPS_300  
    BPS_9600 
    BPS_19200
    BPS_115k 
.endenum
CMND_NRDI    = $0B    ; Command: no parity, RTS on, DTR on, no interrupts


; Application configuration
PSPEED:     .byte BPS_115k  ; Hardcoded for Apple IIc (TODO: Allow configuration)
PSLOT:      .byte 2         ; Hardcoded for Apple IIc (TODO: Allow configuration)
PEXIT:      .byte 0         ; Set when it's time to exit (Not Yet Implemented)


; Keyboard state
LASTKB:     .byte 0
LASTOA:     .byte 0
LASTCA:     .byte 0

.ifdef PADDLE_SUPPORT

; Paddle state
LASTP0:     .byte 0
LASTP1:     .byte 0

.endif ; PADDLE_SUPPORT


.ifdef MOUSE_SUPPORT

; Mouse
MOUSE_SLOT: .byte 0         ; mouse slot, or 0 if none
LAST_MX:    .byte $7f
LAST_MY:    .byte $7f

; Mouse ID bytes
MOUSEID_MAX     = 4
MOUSEID_ADDR:   .byte $05, $07, $0b, $0c, $fb
MOUSEID_VAL:    .byte $38, $18, $01, $20, $d6

.endif ; MOUSE_SUPPORT

