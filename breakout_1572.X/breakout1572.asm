

    include p12f1572.inc
    
    __config _CONFIG1, _FOSC_ECH & _WDTE_OFF & _MCLRE_OFF
    __config _CONFIG2, _PLLEN_OFF
    
    radix dec

; constants
PROG_SIZE equ 2048  ; program words
EEPROM_SIZE equ 128 ; high endurance flash words
 
Fosc equ 28636000 ; external oscillator frequency
Fcy  equ (Fosc/4) ; cpu frequency, machine cycle  T=1/Fcy

 
; NTSC signal 
Fhorz equ 15734 ; horizontal frequency
HPERIOD equ ((Fosc/Fhorz)-1)  ; horizontal period pwm count(63,55�S)
HSYNC  equ 134  ;  (4,7�S) ; horz. sync. pwm pulse count
HEQUAL equ 65 ; 2,3�S equalization pwm pulse count
VSYNC_PULSE equ 776 ; 27,1�S vertical sync. pwm pulse count
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

; swap variable with WREG    
swap_var macro var
    xorwf var
    xorwf var,W
    xorwf var
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

; enable weak pull on VIDEO_OUT
; to create a porch
porch_on macro
    banksel WPUA
    bsf WPUA,VIDEO_OUT
    endm
    
; disable weak pull on VIDEO_OUT
; to remove porch
porch_off macro
    banksel WPUA
    bcf WPUA,VIDEO_OUT
    endm
    
; enable chroma output
chroma_on macro
    banksel TRISA
    bcf TRISA, CHROMA
    endm
    
;disable chroma output    
chroma_off macro
    banksel TRISA
    bsf TRISA,CHROMA
    endm
    
; output chroma reference    
chroma_ref macro
    banksel PWM1CON
    bcf PWM1CON,POL
    endm
    
; set chroma phase to 180 degree
chroma_invert macro
    banksel PWM1CON
    bsf PWM1CON,POL
    endm

;;;;;;;;;;;;;;;;;;;;;;
;   colors macros
; each one take 5 T 
;;;;;;;;;;;;;;;;;;;;;;
    
;set video output to black    
black macro
    banksel TRISA
    bsf TRISA,CHROMA
    bsf TRISA,VIDEO_OUT
;    goto $+1
    endm
    
; set video output to white    
white macro    
    banksel TRISA
    bsf TRISA,CHROMA
    bcf TRISA,VIDEO_OUT
;    goto $+1
    endm

; set video output to yellow    
yellow macro
;    chroma_ref
    banksel TRISA
    bcf TRISA,VIDEO_OUT
    bcf TRISA,CHROMA
    endm

; set video output to cyan   
cyan macro
;    chroma_invert
    banksel TRISA
    bcf TRISA,VIDEO_OUT
    bcf TRISA,CHROMA
    endm
    
; set video output to green
green macro
;    chroma_ref
    banksel TRISA
    bsf TRISA, VIDEO_OUT
    bcf TRISA,CHROMA
    endm
    
; set video output to dark blue    
dark_blue macro
;    chroma_invert
    banksel TRISA
    bsf TRISA, VIDEO_OUT
    bcf TRISA,CHROMA
    endm

    
; draw a brick
; use 6T+BRICK_WIDTH
; if carry is 1 draw in color else draw black    
BRICK_WIDTH equ 28   
draw_brick macro color
    local no_brick
    local brick_delay
    skpc
    bra no_brick
    color
    bra brick_delay
no_brick
    nop
    black
    bra brick_delay 
brick_delay    
    tdelay BRICK_WIDTH
    endm

; draw 8 bricks wall
;  parameter in temp
draw_wall macro color
    local next_brick
    movlw 8
    pushw
next_brick    
    lslf temp
    draw_brick color
    decfsz T
    bra next_brick
    dropn 1
    endm
    
    
; draw left and right borders
; parameters:
;   width delay determine width
;   width 5T+nT    
draw_border macro width
    banksel TRISA
    bsf TRISA,CHROMA
    bcf TRISA,VIDEO_OUT
    tdelay width
    bsf TRISA,VIDEO_OUT
    endm
    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  stack manipulation macros
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    
STACK_SIZE equ 16 ; size of argument stack
#define T INDF0 ; top of argument stack
#define SP FSR0 ; use FSR0 as stack pointer 
; push WREG on T
pushw  macro
    movwi --SP
    endm
  
; pop WREG from T
popw macro
    moviw SP++
    endm
    
; swap WREG with 
swapw  macro
    xorwf T
    xorwf T,W
    xorwf T
    endm

; drop n elements from stack
dropn macro n
    addfsr T,n
    endm

; copy nth element of stack to WREG
;  n {0..31}    
pickn macro n
    moviw n[SP]
    endm
   
; copy WREG to nth element of stack
; n {0..31}
pokew macro n
    movwi n[SP]
    endm
    
    
;;;;;;;;;;;;;;;;;;;;;;;;;;
;;    variables
;;;;;;;;;;;;;;;;;;;;;;;;;;
    
    udata 0x20
stack res 16 ; arguments stack
brick_wall res 0  ; bricks data 1 byte per brick row.
row1 res 1; brick wall row1
row2 res 1
row3 res 1
row4 res 1
row5 res 1

v_array   udata 0xA0
d1 res 1 ; score msd digit pixels
d2 res 1 ; score 2nd digit pixels
d3 res 1 ; score lsd digit pixels
balls res 1 ; number of recking balls available 
sound_timer res 1 ; duration in multiple of 16.7msec. 
  
    udata_shr
flags  res 1 ; boolean variables
lcount res 1 ; video field line counter
slice res 1 ; task slice counter, a task may use more than one slice.
task res 1 ; where in video phase 
temp res 2 ; temporary storage
paddle_pos res 1 
ball_x res 1
ball_y res 1
ball_dx res 1
ball_dy res 1
ball_speed res 1
score res 2 ; score stored in Binary Coded Decimal
ball_timer res 1 
 
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
    tdelay 30
    banksel TRISA
    bcf TRISA,CHROMA
    tdelay 16
    bsf TRISA,CHROMA
    porch_on
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
    goto draw_score ;task 8,  draw score en ball count, 6 slices
    goto draw_top_wall ;task 9,  draw top wall, 4 slices
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
    porch_off
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
PADDLE_WIDTH equ 32
PADDLE_LIMIT equ 93
BALL_LEFT_BOUND equ 0
BALL_RIGHT_BOUND equ 100
BALL_TOP_BOUND equ 54
BALL_BOTTOM_BOUND equ 240 ;(BALL_TOP_BOUND+7*BRICK_HEIGHT+118)
 
 
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
    movfw ADRESH
    movwf paddle_pos
    movlw PADDLE_LIMIT
    subwf paddle_pos,W
    skpc
    bra $+3
    movlw PADDLE_LIMIT
    movwf paddle_pos
    banksel TRISA
    bcf TRISA, AUDIO
    leave

; task 5,  sound timer
sound
    incf task
    incf lcount
    btfss flags, F_SOUND
    leave
    banksel sound_timer
    decfsz sound_timer
    leave
    bcf flags, F_SOUND
    banksel PWM2CON
    bcf PWM2CON,OE
    bcf PWM2CON,EN
    leave

   
; task 6, move recking ball and check collision    
move_ball
    
    incf task
    incf lcount
    leave

    
; task 7, wait for lcount==26, First visible video line is 27
video_first
    incf lcount
    movlw 26
    subwf lcount,W
    skpz
    leave
    clrf slice
    incf task
    leave
   
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The following tasks are responsible to render video display.
; Each video line must be completed by setting color to black.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
; constants used in video display
LEFT_MARGIN equ 24
COURT_WIDTH equ 304
BRICK_HEIGHT equ 8
BORDER_WIDTH equ 4
FIRST_VIDEO_LINE equ 26
 
; task 8, draw score en ball count
draw_score
    banksel TRISA
    movfw slice
    lsrf WREG
    lsrf WREG
    pushw
    movlw 0xf
    andwf score+1,W
    call digit_offset
    addwf T,W
    call digits
    movwf d3
    swapf score+1,W
    andlw 0xf
    call digit_offset
    addwf T,W
    call digits
    movwf d2
    movlw 0xf
    andwf score,W
    call digit_offset
    addwf T,W
    call digits
    call digit_row
    movfw d2
    call digit_row
    movfw d3
    call digit_row
    tdelay 60
    bcf TRISA,VIDEO_OUT
    tdelay 5
    bsf TRISA,VIDEO_OUT
    tdelay 30
    movfw balls
    call digit_offset
    addwf T,W
    call digits
    call digit_row
score_exit
    next_task 5*4

; display digit row    
digit_row
    rlf WREG
    skpnc
    bcf TRISA,VIDEO_OUT
    skpc
    bsf TRISA,VIDEO_OUT
    rlf WREG
    skpnc
    bcf TRISA,VIDEO_OUT
    skpc
    bsf TRISA,VIDEO_OUT
    rlf WREG
    skpnc
    bcf TRISA,VIDEO_OUT
    skpc
    bsf TRISA,VIDEO_OUT
    bra $+1
    bra $+1
    bsf TRISA,VIDEO_OUT
    return
    
; task 9,  draw top wall, 8 screen lines    
draw_top_wall
    btfss flags, F_EVEN
    bra top_wall_exit
    tdelay LEFT_MARGIN-2
    white
    tdelay COURT_WIDTH+3*BORDER_WIDTH+1
    black
top_wall_exit
    next_task BRICK_HEIGHT

; task 10,  only on even field draw vertical side bands.    
draw_void
    btfss flags, F_EVEN
    bra no_wall_draw
    movfw ball_y
    subwf lcount,W
    skpc
    bra no_ball_dly
    movlw 8
    addwf ball_y,W
    subwf lcount,W
    skpc
    bra yes_ball
    bra no_ball
no_ball_dly
    tdelay 6
no_ball    
    tdelay LEFT_MARGIN-13
    draw_border BORDER_WIDTH
    black
    tdelay COURT_WIDTH
    draw_border BORDER_WIDTH
    bra draw_void_exit
yes_ball
    tdelay LEFT_MARGIN-11
    banksel TRISA
    bcf TRISA, VIDEO_OUT
    movfw ball_x
    skpz
    bra ball_delayed
    tdelay 8
    bsf TRISA,VIDEO_OUT
    nop
    bra after_ball
ball_delayed
    bsf TRISA,VIDEO_OUT
    movfw ball_x
    decfsz WREG
    bra $-1
    bcf TRISA,VIDEO_OUT
    tdelay 8
    bsf TRISA, VIDEO_OUT
after_ball
;    movlw PADDLE_LIMIT
;    subwf ball_x,W
    movfw ball_x
    sublw BALL_RIGHT_BOUND-3
    skpnz
    bcf TRISA,VIDEO_OUT
    addlw 1
    decfsz WREG
    bra $-1
    nop
draw_border_no_dly    
    bcf TRISA, VIDEO_OUT
    tdelay 4
    bsf TRISA, VIDEO_OUT
draw_void_exit    
    incf slice
    incf lcount
    movlw 8*BRICK_HEIGHT+118
    subwf slice,W
    skpz
    leave
    movlw 18
    clrf slice
    movwf task
    leave
    ;    next_task 125*BRICK_HEIGHT
no_wall_draw
    next_task 2*BRICK_HEIGHT
    
; task 11, draw top brick row
draw_row1 ; yellow
    chroma_ref
    banksel row1
    movfw row1
    movwf temp
    tdelay LEFT_MARGIN-4
;    draw_border BORDER_WIDTH
    draw_wall yellow
    black
    tdelay 3
;    draw_border BORDER_WIDTH
    next_task BRICK_HEIGHT
    
; task 12, draw 2nd brick row    
draw_row2 ;cyan
    chroma_invert
    banksel row2
    movfw row2
    movwf temp
    tdelay LEFT_MARGIN-4
;    draw_border BORDER_WIDTH
    draw_wall cyan
    black
    tdelay 3
;    draw_border BORDER_WIDTH
    next_task BRICK_HEIGHT

; task 13, draw 3rd brick row    
draw_row3 ; green
;    btfss flags, F_EVEN
;    bra row3_exit
    chroma_ref
    banksel row3
    movfw row3
    movwf temp
    tdelay LEFT_MARGIN-4
;    draw_border BORDER_WIDTH
    draw_wall green
    black
    tdelay 3
;    draw_border BORDER_WIDTH
row3_exit    
    next_task BRICK_HEIGHT
    
; task 14, draw 4th brick row    
draw_row4 ; dark blue
    chroma_invert
    banksel row4
    movfw row4
    movwf temp
    tdelay LEFT_MARGIN-4
;    draw_border BORDER_WIDTH
    draw_wall dark_blue
    black
    tdelay 3
;    draw_border BORDER_WIDTH
    next_task BRICK_HEIGHT

; task 15, draw 5th brick row    
draw_row5 ; white
    banksel row5
    movfw row5
    movwf temp
    tdelay LEFT_MARGIN-3
;    draw_border BORDER_WIDTH
    draw_wall white
    black
    tdelay 3
;    draw_border BORDER_WIDTH
    black
    next_task BRICK_HEIGHT

; task 16,draw all rows between paddle and lower brick row    
draw_empty
    tdelay LEFT_MARGIN
;    draw_border BORDER_WIDTH
    tdelay 320
;    draw_border BORDER_WIDTH
    black
    next_task 118

    
; task 17, draw paddle at bottom screen    
draw_paddle
    tdelay LEFT_MARGIN+2
    movfw paddle_pos
    skpnz
    bra $+3
    decfsz WREG
    bra $-1
    banksel TRISA
    bcf TRISA,VIDEO_OUT
    tdelay PADDLE_WIDTH
    bsf TRISA,VIDEO_OUT
;    draw_border BORDER_WIDTH
;    movfw paddle_pos
;    skpnz
;    bcf TRISA,VIDEO_OUT
;    skpnz
;    bra at_left+2
;    decfsz WREG
;    bra $-1
;at_left
;    nop
;    bcf TRISA,VIDEO_OUT
;    tdelay PADDLE_WIDTH
;    movfw paddle_pos
;    sublw PADDLE_LIMIT
;    nop
;    skpnz
;    bra $+5
;    nop
;    bsf TRISA,VIDEO_OUT
;    decfsz WREG
;    bra $-1
;    draw_border BORDER_WIDTH
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

; helper functions

; add 2 BCD digits
; parameters:
;   WREG -> first digit
;   T -> second digit
;   C -> carry from previous digits add    
; output:
;   T -> sum
;   C -> overflow
bcd_add
    addwfc T
    movlw 10
    subwf T,W
    skpc
    return
    movlw 6
    addwf T
    movlw 15
    andwf T
    bsf STATUS,C
    return
    
; increment user score
; This is a BCD addition where a single digit is added to score.   
; score is stored as big indian
; argument: ( n -- )
;   WREG ->  bdc digit to add to score variable
inc_score
    pushw
    clrc
    movlw 15
    andwf score+1,W
    call bcd_add
    clrw 
    pushw
    swapf score+1,W
    andlw 15
    call bcd_add
    skpnc
    incf score
    popw
    swapf WREG
    iorwf T,W
    movwf score+1
    dropn 1
    return
    
;***********************************
; digit_offset, compute digit position in 'digits' table
;   position = digit * 5
; 
; input: WREG -> digit value {0..9}
;         
; output: WREG -> displacement in table
;***********************************
digit_offset    
    pushw 
    lslf WREG
    lslf WREG
    addwf T
    popw
    return
    
init_brick_wall
    movlw high brick_wall
    movwf FSR1H
    movlw low brick_wall
    movwf FSR1L
    movlw 5
    movwf temp
    movlw 0xff
ibw    
    movwi FSR1++
    decfsz temp
    bra ibw
    return

; delay by TIMER0
; parameter
;   WREG -> 2*Tcy+7cy    
t0delay 
    comf WREG
    movwf TMR0
    bcf INTCON,T0IF
    btfss INTCON,T0IF
    bra $-1
    return
    
MAIN_PROG CODE                      ; let linker place main program

START
; clear common RAM
    clrf FSR0H
    movlw 0x70
    movwf FSR0L
    clrw
    movwi FSR0++
    btfss FSR0L,7
    bra $-2
; clear banked RAM
    clrf FSR0L
    movlw 0x20
    movwf FSR0H
    clrw 
    movwi FSR0++
    btfss FSR0H,0
    bra $-2
    call init_brick_wall
;   setup arguments stack pointer
    movlw high (stack+STACK_SIZE)
    movwf FSR0H
    movlw low (stack+STACK_SIZE)
    movwf FSR0L
; setup OPTION register to enable weak pullup and prescale used by TIMER
; TIMER0 prescale 1:2
    movlw ~((1<<NOT_WPUEN)|(1<<TMR0CS)|(1<<PSA)|(7<<PS0_OPTION_REG))
    movwf OPTION_REG
; disable analog inputs, except AN0
    banksel ANSELA
    clrf ANSELA
; paddle potentiometer input     
    bsf ANSELA,PADDLE
    banksel ADCON1
    movlw (2<<ADCS0)
    movwf ADCON1
; pin setup
    banksel WPUA
    clrf WPUA
    bsf WPUA,START_BTN
    banksel TRISA
    bcf TRISA,SYNC_OUT
    banksel LATA
    bsf LATA, VIDEO_OUT
; PWM1 chroma signal on RA1
    banksel PWM1CON
    clrf PWM1LDCON
    clrf PWM1PHL
    clrf PWM1PHH
    clrf PWM1OFL
    clrf PWM1OFH
    clrf PWM1PRH
    movlw 7
    movwf PWM1PRL
    movlw 4
    movwf PWM1DCL
    clrf PWM1DCH
    bsf PWM1LDCON,7
    movlw (1<<EN)|(1<<OE)
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
; test code
    banksel balls
    movlw 3
    movwf balls
    movlw BALL_RIGHT_BOUND-3
    movwf ball_x
;    clrf ball_x
    movlw BALL_BOTTOM_BOUND-40
    movwf ball_y
test_loop
    movlw 60
    banksel sound_timer
    movwf sound_timer
    bsf flags, F_SOUND
    btfsc flags, F_SOUND
    bra $-1
    movlw 1
    call inc_score
    bra test_loop
; end test code    
 ; all processing done in ISR    
    goto $

; digits character table
digits
    brw
    dt  0x40,0xA0,0xA0,0xA0,0x40 ; 0
    dt  0x40,0xC0,0x40,0x40,0xE0 ; 1
    dt  0xE0,0x20,0xC0,0x80,0xE0 ; 2
    dt  0xE0,0x20,0xC0,0x20,0xE0 ; 3
    dt  0xA0,0xA0,0xE0,0x20,0x20 ; 4
    dt  0xE0,0x80,0xE0,0x20,0xE0 ; 5
    dt  0xC0,0x80,0xE0,0xA0,0xE0 ; 6
    dt  0xE0,0x20,0x20,0x20,0x20 ; 7
    dt  0xE0,0xA0,0xE0,0xA0,0xE0 ; 8
    dt  0xE0,0xA0,0xE0,0x20,0x60 ; 9
    
    
eeprom org (PROG_SIZE-EEPROM_SIZE)
max_score 
 
    END