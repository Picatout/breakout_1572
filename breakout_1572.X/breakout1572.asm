; TODO INSERT CONFIG CODE HERE USING CONFIG BITS GENERATOR

    include p12f1572.inc
    
    __config _CONFIG1, _FOSC_ECH & _WDTE_OFF  & _MCLRE_OFF
    __config _CONFIG2, _PLLEN_OFF
    
    radix dec

; constants    
Fosc equ 14318000
Fcy  equ (Fosc/4)
; NTSC signal 
Fhorz equ 15734 ; horizontal frequency
HPERIOD equ ((Fosc/Fhorz)-1)  ; horizontal period pwm count(63,55µS)
HSYNC  equ 66  ;  (4,7µS) ; horz. sync. pwm pulse count
HEQUAL equ 32 ; 2,3µS equalization pwm pulse count
VSYNC_PULSE equ 387 ; 27,1µS vertical sync. pwm pulse count
HALF_LINE equ ((Fosc/Fhorz/2)-1) 
; boolean flags 
F_HI_LINE equ 0 ; horz. line > 255
F_EVEN equ 1    ; even field

;pins assignment
CLKIN equ RA5
CHROMA equ RA1
SYNC_OUT equ RA2
AUDIO EQU RA0
VIDEO_OUT equ RA4
 
;colors
BLACK EQU 0
YELLOW EQU 1
BLUE EQU 2
WHITE EQU 3
MAUVE EQU 4
GREEN EQU 5
 
;; macros 
case macro n, adr
    xorlw n
    skpnz
    goto adr
    xorlw n
    endm

; delay in machine cycle T
tdelay macro t
    variable q=(t)/3
    variable r=(t)%3
    if (q)
    movlw q
    decfsz WREG
    goto $-1
    endif
    if (r==2)
    goto $+1
    else 
    if (r==1)
    nop
    endif
    endif
    endm

    
set_pixel macro color
    if color==BLACK
    banksel LATA
    bcf LATA, VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,OE
    goto $+1
    endif  
    if color==YELLOW
    banksel LATA
    bsf LATA,VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,POL
    bsf PWM1CON,OE
    nop
    endif
    if color==BLUE
    banksel LATA
    bcf LATA,VIDEO_OUT
    banksel PWM1CON
    bsf PWM1CON,POL
    bsf PWM1CON,OE
    goto $+1
    endif
    if color==WHITE
    banksel LATA
    bsf LATA, VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,OE
    goto $+1
    goto $+1
    endif
    if color==MAUVE
    banksel LATA
    bsf LATA,VIDEO_OUT
    banksel PWM1CON
    bsf PWM1CON,POL
    bsf PWM1CON,OE
    nop
    endif
    if color==GREEN
    banksel LATA
    bcf LATA,VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,POL
    bsf PWM1CON,OE
    goto $+1
    endif
    endm
    
; variables
    udata_shr
flags  res 1 ; boolean variables
lcount res 1 ; video field line counter
vsync_count res 1 ; vertical sync seration counter
state res 1 ; where in video phase 
   
;; code 
RES_VECT  CODE    0x0000            ; processor reset vector
    GOTO    START                   ; go to beginning of program
    reset
    reset
    reset
    
; interrupt service routine triggered by PWM3 period rollover
ISR CODE 0x0004
isr clrf PCLATH
    movfw state
    addwf PCL
    goto pre_equalization ; vertical pre-equalization pulses
    goto vsync ; vertical sync pulses
    goto post_equalization ; vertical post-equalization pulses
    goto vsync_completed ; return to normal video line
    goto video_lines ; in video normal lines
    goto 1 ; error trap
; set PWM3 to generate HALF_LINE with narrow pulse
pre_equalization
    incf vsync_count
    movfw vsync_count
    addwf PCL
    nop
    goto set_presync
    goto isr_exit
    goto isr_exit
    goto isr_exit
    goto isr_exit
;vsync_count==6    
    clrf vsync_count
    incf state
    goto isr_exit
set_presync    
    banksel PWM3DC
    movlw HEQUAL
    movwf PWM3DCL
    clrf PWM3DCH
    movlw high HALF_LINE
    movwf PWM3PRH
    movlw low HALF_LINE
    movwf PWM3PRL
    bsf PWM3LDCON,7
    goto isr_exit
; set PWM3 to generate wide sync pulses
vsync 
    incf vsync_count
    movfw vsync_count
    addwf PCL
    nop
    goto set_vsync
    goto isr_exit
    goto isr_exit
    goto isr_exit
    goto isr_exit
 ; vsync_count==6    
    clrf vsync_count
    incf state
    goto isr_exit
set_vsync
    banksel PWM3DC
    movlw low VSYNC_PULSE
    movwf PWM3DCL
    movlw high VSYNC_PULSE
    movwf PWM3DCH
    bsf PWM3LDCON,7
    goto isr_exit
; set PWM3 for post equalization pulses    
post_equalization
    incf vsync_count
    movfw vsync_count
    addwf PCL
    nop
    goto set_presync
    goto isr_exit
    goto isr_exit
    goto isr_exit
    goto isr_exit
    btfsc flags, F_EVEN
    goto pe_last
    banksel PWM3DC
    movlw high HPERIOD
    movlw high HPERIOD
    movwf PWM3PRH
    movlw low HPERIOD
    movwf PWM3PRL
    bsf PWM3LDCON,7
    incf state
pe_last
    clrf vsync_count
    incf state
    goto isr_exit
; return to normal line
vsync_completed
    banksel PWM3DC
    movlw HSYNC
    movwf PWM3DCL
    clrf PWM3DCH
    movlw high HPERIOD
    movwf PWM3PRH
    movlw low HPERIOD
    movwf PWM3PRL
    bsf PWM3LDCON,7
    incf state
    movlw 9
    movwf lcount
    goto isr_exit
video_lines
; chroma sync
    tdelay 6
    banksel PWM1CON
    bsf PWM1CON,OE
    tdelay 5
    bcf PWM1CON,OE
    incf lcount
    skpnz
    bsf flags, F_HI_LINE
    btfsc flags, F_HI_LINE
    goto hi_line
    movlw 20
    subwf lcount,W
    skpc
    goto isr_exit
    movlw 251
    subwf lcount,W
    skpnc
    goto isr_exit
    movlw 20
    subwf lcount,W
    skpz
    goto try_250
    banksel LATA
    bsf LATA,VIDEO_OUT
    movlw 56
    decfsz WREG
    goto $-1
    bcf LATA,VIDEO_OUT
    goto isr_exit
try_250
    movlw 250
    subwf lcount,W
    skpz
    goto vertical_bars
    banksel LATA
    bsf LATA, VIDEO_OUT
    movlw 54
    decfsz WREG
    goto $-1
    bcf LATA,VIDEO_OUT
    goto isr_exit
vertical_bars    
; video output
    set_pixel BLUE
    tdelay 4
    set_pixel YELLOW
    tdelay 4
    set_pixel MAUVE
    tdelay 4
    set_pixel GREEN
    tdelay 4
    set_pixel WHITE
    tdelay 4
    set_pixel BLACK
;    banksel LATA
;    bsf LATA, VIDEO_OUT
;    banksel PWM1CON
;    bsf PWM1CON,OE
;    banksel PWM1CON
;    bcf PWM1CON,OE
;    banksel PWM1CON
;    bsf PWM1CON,OE
;    banksel PWM1CON
;    bcf PWM1CON,OE
;    banksel PWM1CON
;    bsf PWM1CON,OE
;    tdelay 6
;    banksel LATA
;    bcf LATA, VIDEO_OUT
;    banksel PWM1CON
;    bsf PWM1CON,POL
;    tdelay 6
;    banksel PWM1CON
;    bcf PWM1CON,OE
;    bcf PWM1CON,POL
;    banksel LATA
;    bsf LATA,VIDEO_OUT
;    tdelay 6
;    bcf LATA,VIDEO_OUT
    goto isr_exit
hi_line
    btfsc flags,F_EVEN
    goto even_field
    movlw 5
    subwf lcount,W
    skpz
    goto isr_exit
    goto field_end
even_field
    movlw 6
    subwf lcount,W
    skpz
    goto isr_exit
; even field last line is half_line    
; set PWM3 for line 263 half-line
    banksel PWM3DC
    movlw high HALF_LINE
    movwf PWM3PRH
    movlw low HALF_LINE
    movwf PWM3PRL
    bsf PWM3LDCON,7
field_end
    clrf state
    clrf lcount
    bcf flags, F_HI_LINE
; toggle odd/even field flag    
    movlw 1<<F_EVEN
    xorwf flags
isr_exit  
    banksel PWM3INTF
    bcf PWM3INTF,PRIF
    banksel PIR3
    bcf PIR3,PWM3IF
    retfie
    
MAIN_PROG CODE                      ; let linker place main program

START
; reset common ram 0x70-0x7f
    movlw 0x70
    movwf FSR0L
    clrf FSR0H
    clrf INDF0
    incf FSR0L
    btfss FSR0L,7
    goto $-3
; disable analog inputs
    banksel ANSELA
    clrf ANSELA
; pin setup   
    banksel TRISA
    bcf TRISA,CHROMA
    bcf TRISA,SYNC_OUT
    bcf TRISA,VIDEO_OUT
    banksel LATA
    bcf LATA, VIDEO_OUT
    bsf LATA, SYNC_OUT
; PWM1 chroma signal on RA1
    banksel PWM1CON
    clrf PWM1LDCON
    clrf PWM1PHL
    clrf PWM1PHH
    clrf PWM1OFL
    clrf PWM1OFH
    clrf PWM1PRH
    movlw 3
    movwf PWM1PRL
    movlw 2
    movwf PWM1DCL
    clrf PWM1DCH
    bsf PWM1LDCON,7
    movlw (1<<EN)
    movwf PWM1CON
; PWM3 set to horizontal period 15734 hertz, output on RA2
    banksel PWM3CON
    clrf PWM3LDCON
    clrf PWM3PHL
    clrf PWM3PHH
    clrf PWM3OFL
    clrf PWM3OFH
    movlw low HPERIOD
    movwf PWM3PRL
    movlw high HPERIOD
    movwf PWM3PRH
    movlw HSYNC
    movwf PWM3DCL
    clrf PWM3DCH
    movlw (1<<EN)|(1<<OE)|(1<<POL)
    movwf PWM3CON
    bsf PWM3LDCON,7
    bsf PWM3INTE,PRIE
    banksel PIR3
    bcf PIR3,PWM3IF
    banksel PIE3
    bsf PIE3,PWM3IE
    bsf INTCON,PEIE
    bsf INTCON,GIE
    bsf flags, F_EVEN
 ; all processing done in ISR    
    goto $
    
    
    END