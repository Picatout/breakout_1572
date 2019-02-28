

    include p12f1572.inc
    
    __config _CONFIG1, _FOSC_ECH & _WDTE_OFF  & _MCLRE_OFF
    __config _CONFIG2, _PLLEN_OFF
    
    radix dec

; constants
PROG_SIZE equ 2048  ; program words
EEPROM_SIZE equ 128 ; high endurance flash words
 
Fosc equ 14318000 ; external oscillator frequency
Fcy  equ (Fosc/4) ; cpu frequency, machine cycle  T=1/Fcy

 
; NTSC signal 
Fhorz equ 15734 ; horizontal frequency
HPERIOD equ ((Fosc/Fhorz)-1)  ; horizontal period pwm count(63,55µS)
HSYNC  equ 66  ;  (4,7µS) ; horz. sync. pwm pulse count
HEQUAL equ 32 ; 2,3µS equalization pwm pulse count
VSYNC_PULSE equ 387 ; 27,1µS vertical sync. pwm pulse count
HALF_LINE equ ((Fosc/Fhorz/2)-1) 
; boolean flags 
F_HI_LINE equ 0 ; lcount > 255
F_EVEN equ 1    ; even field
F_START equ 2   ; game started 
F_OVER equ 3    ; game over
F_SOUND equ 4   ; sound enabled 
F_SYNC equ 5    ; vertical synchronization phase
 
;pins assignment
AUDIO EQU RA0
PADDLE equ RA0
CHROMA equ RA1
SYNC_OUT equ RA2
START_BTN equ RA3 
VIDEO_OUT equ RA4
CLKIN equ RA5
 
;colors
BLACK EQU 0
YELLOW EQU 1
BLUE EQU 2
WHITE EQU 3
MAGENTA EQU 4
GREEN EQU 5

;;;;;;;;;;;;;;;;;;;;;;
;; assembler macros ;;
;;;;;;;;;;;;;;;;;;;;;;

; leave task 
leave macro
    goto isr_exit
    endm
    
; move to next task on slice limit
; parameters:
;   s  nomber of slices used by the task    
next_task macro s    
    incf slice
    movlw s
    subwf slice,W
    skpz
    leave
    clrf slice
    incf task
    movlw s
    addwf lcount
    leave
    endm
    
    
; case switch
; parameters:
;   var is control variable
;   n  is constant to compare to var
;   adr  is goto address if var==n 
case macro var, n, adr
    movlw n
    subwf var,W
    skpnz
    goto adr
    endm

; delay in machine cycle T
; parameters:
;   T   number of machine cycles    
tdelay macro T
    variable q=(T)/3
    variable r=(T)%3
    if (q)
    movlw q
    decfsz WREG
    goto $-1
    endif
    if (r==2)
    goto $+1
    endif 
    if (r==1)
    nop
    endif
    endm

    
set_color macro color
    if color==BLACK
    banksel LATA
    bcf LATA, VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,OE
    nop
    endif  
    if color==YELLOW
    banksel LATA
    bsf LATA,VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,POL
    bsf PWM1CON,OE
    endif
    if color==BLUE
    banksel LATA
    bcf LATA,VIDEO_OUT
    banksel PWM1CON
    bsf PWM1CON,POL
    bsf PWM1CON,OE
    endif
    if color==WHITE
    banksel LATA
    bsf LATA, VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,OE
    nop
    endif
    if color==MAGENTA
    banksel LATA
    bsf LATA,VIDEO_OUT
    banksel PWM1CON
    bsf PWM1CON,POL
    bsf PWM1CON,OE
    endif
    if color==GREEN
    banksel LATA
    bcf LATA,VIDEO_OUT
    banksel PWM1CON
    bcf PWM1CON,POL
    bsf PWM1CON,OE
    endif
    endm

    
; variables
    udata_shr
flags  res 1 ; boolean variables
lcount res 1 ; video field line counter
slice res 1 ; task slice counter, a task may use more than one slice.
task res 1 ; where in video phase 
temp res 1 ; temporary storage
sound_timer res 1 ; duration in multiple of 16.7msec. 
 
;; code 
RES_VECT  CODE    0x0000            ; processor reset vector
    GOTO    START                   ; go to beginning of program
    reset
    reset
    reset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    
; interrupt service routine triggered by PWM3 period rollover
ISR CODE 0x0004
isr
    btfsc flags, F_SYNC
    goto task_switch
 ; chroma sync
    tdelay 10
    banksel PWM1CON
    bsf PWM1CON,OE
    tdelay 5
    bcf PWM1CON,OE
task_switch    
    clrf PCLATH
    movfw task
    addwf PCL
    goto pre_vsync ;task 0, vertical pre-equalization pulses, 6 slices
    goto vsync ;task 1, vertical sync pulses, 6 slices
    goto post_vsync ;task 2, vertical post-equalization pulses, 6 slices
    goto vsync_end ;task 3, return to normal video line, 1 slice
    goto user_input ;task 4,  read button and paddle, 1 slice
    goto sound ;task 5, check sound timer expiration, 1 slice
    goto move_ball ;task 6, move recking ball and check collision, etc, 1 slice
    goto video_first ; task 7, wait up to lcount==19
    goto score ;task 8,  draw score en ball count, 6 slices
    goto top_wall ;task 9,  draw top wall, 4 slices
    goto draw_void ;task 10 draw void space between top wall and top brick row, 8 slices
    goto draw_row1 ;task 11, 4 slices
    goto draw_row2 ;task 12, 4 slices
    goto draw_row3 ;task 13,  4 slices
    goto draw_row4 ;task 14,  4 slices
    goto draw_row5 ;task 15, 4 slices
    goto draw_empty;task 16, 188 slices
    goto draw_paddle ;task 17, 4 slices
    goto wait_field_end ;task 18, player used all the available recking balls, 12/13 slices
    reset ; error trap, task out of range
isr_exit  
    banksel PWM3INTF
    bcf PWM3INTF,PRIF
    retfie

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  all tasks routine are here            ;;
;;  each must be terminate by leave macro ;;    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
; task 0, vertical synchronization pre equalization
pre_vsync
    movfw slice
    skpnz
    goto set_presync
    next_task 6
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
    incf slice
    leave
    
; task 1, vertical synchronization pulses
vsync 
    movfw slice
    skpnz
    goto set_vsync
    next_task 6
set_vsync
    banksel PWM3DC
    movlw low VSYNC_PULSE
    movwf PWM3DCL
    movlw high VSYNC_PULSE
    movwf PWM3DCH
    bsf PWM3LDCON,7
    incf slice
    leave
    
; task 2, vertical synchronisation post equalization pulses
post_vsync
    movfw slice
    skpnz
    goto set_presync
    movlw 6
    subwf slice,W
    skpnz
    goto post_last
    incf slice
    leave
post_last    
    incf task
    clrf slice
    btfss flags, F_EVEN
    leave
    
; task 3, vertical synchronization completed, return to normal line
vsync_end
    bcf flags, F_SYNC
    banksel PWM3DC
    movlw HSYNC
    movwf PWM3DCL
    clrf PWM3DCH
    movlw high HPERIOD
    movwf PWM3PRH
    movlw low HPERIOD
    movwf PWM3PRL
    bsf PWM3LDCON,7
    incf task
    movlw 9
    movwf lcount
    leave
    
;task 4, read button and paddle position
user_input
    incf task
    incf lcount
    btfsc flags, F_START
    goto read_paddle
; read start button
    banksel LATA
    btfss LATA,START_BTN
    bsf flags, F_START
    leave
read_paddle
    banksel TRISA
    bsf TRISA, PADDLE
    banksel ADCON0
    movlw 3
    movwf ADCON0
    btfsc ADCON0,NOT_DONE
    goto $-1
    bcf ADCON0,ADON
    banksel TRISA
    bcf TRISA, AUDIO
    leave

; task 5,  sound timer
sound
    incf task
    incf lcount
    btfss flags, F_SOUND
    leave
    decfsz sound_timer
    leave
    banksel PWM2CON
    bcf PWM2CON,OE
    bcf PWM2CON,EN
    leave

   
; task 6, move recking ball and check collision    
move_ball
    incf task
    incf lcount
    leave

    
; task 7, increment lcount up to 26
video_first
    incf lcount
    movlw 26
    subwf lcount,W
    skpz
    leave
    clrf slice
    incf task
    leave
    
; task 8, draw score en ball count, 6 slices    
score
    tdelay 10
    set_color BLACK
    tdelay 164
    set_color BLACK
    
score_exit
    next_task 6*4
    
; task 9,  draw top wall, 8 screen lines    
top_wall
    tdelay 10
    set_color WHITE
    tdelay 164
    set_color BLACK
top_wall_exit
    next_task 8

; task 10,  draw void space between top wall and top brick row, 8 slices    
draw_void
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 150
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 16

; task 11, draw top brick row
draw_row1
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 150
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 8
    
; task 12, draw 2nd brick row    
draw_row2
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 150
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 8

; task 13, draw 3rd brick row    
draw_row3
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 150
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 8
    
; task 14, draw 4th brick row    
draw_row4
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 150
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 8

; task 15, draw 5th brick row    
draw_row5
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 150
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 8

; task 16,draw all rows between paddle and lower brick row    
draw_empty
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 150
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 118
    
; task 17, draw paddle at bottom screen    
draw_paddle
    tdelay 10
    set_color WHITE
    tdelay 2
    set_color BLACK
    tdelay 60
    set_color YELLOW
    tdelay 12
    set_color BLACK
    tdelay 68
    set_color WHITE
    tdelay 2
    set_color BLACK
    next_task 8

; task 18,  wait end of this field, reset task to zero    
wait_field_end
    incf lcount
    skpnz
    bsf flags, F_HI_LINE
    btfsc flags, F_HI_LINE
    goto hi_line
    leave
hi_line
    btfsc flags,F_EVEN
    goto even_field
    movlw 5
    subwf lcount,W
    skpz
    leave
    goto field_end
even_field
    movlw 6
    subwf lcount,W
    skpz
    leave
; even field last line is half_line    
; set PWM3 for line 263 half-line
    banksel PWM3DC
    movlw high HALF_LINE
    movwf PWM3PRH
    movlw low HALF_LINE
    movwf PWM3PRL
    bsf PWM3LDCON,7
field_end
    clrf task
    clrf slice
    clrf lcount
    bcf flags, F_HI_LINE
    bsf flags, F_SYNC
; toggle odd/even field flag    
    movlw 1<<F_EVEN
    xorwf flags
    leave
    
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
; disable analog inputs, except AN0
    banksel ANSELA
    clrf ANSELA
; paddle potentiometer input     
    bsf ANSELA,PADDLE
    banksel ADCON1
    movlw (2<<ADCS0)
    movwf ADCON1
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
    bsf flags, F_SYNC
    
 ; all processing done in ISR    
    goto $

; delay for each position    
; there is 18 horizontal position
PIXEL_DLY equ 4
delay_table
    movwf temp
    movlw high delay_table
    movwf PCLATH
    movfw temp
    addwf PCL
    dt 0*PIXEL_DLY
    dt 1*PIXEL_DLY
    dt 2*PIXEL_DLY
    dt 3*PIXEL_DLY
    dt 4*PIXEL_DLY
    dt 5*PIXEL_DLY
    dt 6*PIXEL_DLY
    dt 7*PIXEL_DLY
    dt 8*PIXEL_DLY
    dt 9*PIXEL_DLY
    dt 10*PIXEL_DLY
    dt 11*PIXEL_DLY
    dt 12*PIXEL_DLY
    dt 13*PIXEL_DLY
    dt 14*PIXEL_DLY
    dt 15*PIXEL_DLY
    dt 16*PIXEL_DLY
    dt 17*PIXEL_DLY
    
eeprom org (PROG_SIZE-EEPROM_SIZE)
max_score 
 
    END