;;;---------------------------------------------------------
;;;
;;; Generic Macros
;;;
;;;---------------------------------------------------------

.macro SaveRegisters
        pha
        txa
        pha
        tya
        pha
.endmacro

.macro RestoreRegisters
        pla
        tay
        pla
        tax
        pla
.endmacro
