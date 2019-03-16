;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;	         BREAKOUT game
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;             IMPLEMENTATION NOTES
;  PWM3 is used to generate NTSC synchronization signal.
;  An interrupt is triggered at begin of each horizontal scan line.
;  Inside this interrupt there is a round robin task scheduler.
;  All video display and game logic is done inside these tasks.
;  After MCU initialization the main() procedure is an empty loop.
;  The PIC12F1572 is clocked by an external oscillator running at
;  8 times NTSC chroma frequency  28.636Mhz.    
;  The CPU Fcy is 2*NTSC chroma frequency 7.159Mhz. This give a Tcy
;  short of 140 nanoseconds.
;  NTSC horizontal frequency being 15734 Hertz code inside the ISR
;  must execute in less than 454 Tcy.    
;  The overhead before entering a task in at most 58Tcy.
;  The 'next_task' macro and the 'isr_exit' code use 17Tcy at most.
;  To play safe any task should execute in less than 379Tcy.
;  VISIBLE video lines:
;   For the visibles video lines tasks some delay is introduce
;   before any display attempt to ensure the game left side is
;   inside visible part of the scan line.
;   Each visible line must be terminate by returning video_output to black
;   otherwise the sync signal will be mangled. 
;    
;  VIDEO DISPLAY ZONES
;  scan lines     display
;  =======================    
;    30-49     |   score and balls count
;    50-57     |   top wall
;    58-250    |   play ground
;    58-73     |   empty zone
;    74-81     |   mauve bricks
;    82-89     |   yellow bricks
;    90-97     |   blue bricks
;    98-105    |   dark green bricks
;    106-113   |   gray bricks
;    114-250   |   empty zone
;    243-250   |   paddle zone    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
 
    
    include p12f1572.inc
    
    __config _CONFIG1, _FOSC_ECH & _WDTE_OFF & _MCLRE_OFF
    __config _CONFIG2, _PLLEN_OFF & _LVP_OFF
    
    radix dec

; constants
PROG_SIZE equ 2048  ; program words
EEPROM_SIZE equ 128 ; high endurance flash words
 
Fosc equ 28636000 ; external oscillator frequency
Fcy  equ (Fosc/4) ; cpu frequency, machine cycle  T=1/Fcy
Tcy equ 140 ; CPU cycle in nanoseconds (139.683nS)
 
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
F_SYNC equ 2    ; vertical synchronization phase
F_SOUND equ 3   ; sound enabled 
F_START equ 4   ; game started 
F_PAUSE equ 5   ; game pause after a ball lost
F_OVER equ 6    ; game over
 
;pins assignment
AUDIO EQU RA0
PADDLE equ RA0
CHROMA equ RA1
SYNC_OUT equ RA2
START_BTN equ RA3 
VIDEO_OUT equ RA4
CLKIN equ RA5
 
    ; constants used in video display
; values are in Tcy for x dimension.
; values are in scan lines for y dimension.    
FIRST_VIDEO_LINE equ 30 ; first video line displayed
LAST_VIDEO_LINE	 equ 250 ; last video line displayed
LEFT_MARGIN equ 52  ;  delay Tcy before any display
COURT_WIDTH equ 248 ; Tcy
BRICK_HEIGHT equ 8  ; scan lines
BRICK_WIDTH equ 16  ; Tcy
BORDER_WIDTH equ 4  ; Tcy
PADDLE_WIDTH equ 32 ; Tcy
PADDLE_THICKNESS equ 8 ; scan lines
PADDLE_LIMIT equ 74 ; Tcy
BALL_WIDTH equ 8 ; Tcy
BALL_HEIGHT equ 8 ; scan lines 
BALL_LEFT_BOUND equ 0 ; Tcy
BALL_RIGHT_BOUND equ 82 ; Tcy
BALL_TOP_BOUND equ 58  ; scan lines
BALL_BOTTOM_BOUND equ LAST_VIDEO_LINE;-BRICK_HEIGHT ;
PADDLE_Y equ LAST_VIDEO_LINE-PADDLE_THICKNESS+1 ; 
BRICKS_ROWS equ 5 ; number of bricks rows
ROW1_Y equ 74
ROW2_Y equ 82
ROW3_Y equ 90
ROW4_Y equ 98
ROW5_Y equ 106
 

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
OTHERS equ (0<<SYNC_OUT)|(0<<AUDIO)|(1<<START_BTN)    
BLACK equ (1<<CHROMA)|(1<<VIDEO_OUT)|OTHERS
WHITE equ (1<<CHROMA)|(0<<VIDEO_OUT)|OTHERS
MAUVE equ (0<<CHROMA)|(0<<VIDEO_OUT)|OTHERS
YELLOW equ (0<<CHROMA)|(0<<VIDEO_OUT)|OTHERS
BLUE equ (0<<CHROMA)|(1<<VIDEO_OUT)|OTHERS
DARK_GREEN equ (0<<CHROMA)|(1<<VIDEO_OUT)|OTHERS
 
;set video output to black    
black macro
    movlw BLACK
    movwf TRISA
;    goto $+1
    endm
    
; set video output to white    
white macro    
    movlw WHITE
    movwf TRISA
    endm

#define gray white
    
; set video output to mauve    
mauve macro
;    chroma_ref
;    banksel TRISA
    movlw MAUVE
    movwf TRISA
    endm

; set video output to yellow   
yellow macro
    movlw YELLOW
    movwf TRISA
    endm
    
; set video output to blue
blue macro
    movlw BLUE
    movwf TRISA
    endm
    
; set video output to dark blue    
dark_green macro
    movlw DARK_GREEN
    movwf TRISA
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
seed res 4 ; prng seed
 
v_array   udata 0xA0
row1 res 2; brick wall row1
row2 res 2
row3 res 2
row4 res 2
row5 res 2
row6 res 2
mask res 1 
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
temp1 res 1 ; temporary storage
temp2 res 1 ; 
paddle_pos res 1 
ball_x res 1
ball_y res 1
ball_dx res 1
ball_dy res 1
ball_speed res 1
score res 2 ; score stored in Binary Coded Decimal
ball_timer res 1 
;heading res 1 ; ball direction:0=N,2=NW,3=NE,4=S,6=SW,7=SE 
 
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
    tdelay 28
    chroma_ref
    banksel TRISA
    bcf TRISA,CHROMA
    tdelay 16
    bsf TRISA,CHROMA
    porch_on
task_switch ; horizontal scan line used as round robin task scheduler   
    movfw task
    brw
    goto pre_vsync ;task 0, vertical pre-equalization pulses
    goto vsync ;task 1, vertical sync pulses
    goto post_vsync ;task 2, vertical post-equalization pulses
    goto vsync_end ;task 3, return to normal video line
    goto sound ;task 4, check sound timer expiration
    goto user_input ;task 5,  read button and paddle
    goto move_ball ;task 6, move recking ball.
    goto collision ; task 7, check for collision with brick wall and paddle
    goto video_first ; task 8, wait FIRST_VIDEO line.
    goto draw_score ;task 9,  draw score en ball count
    goto draw_top_wall ;task 10,  draw top wall
    goto draw_void ;task 11, draw play space
    goto draw_row1 ;task 12, draw top bricks row
    goto draw_row2 ;task 13, draw second bricks row
    goto draw_row3 ;task 14,  draw third bricks row
    goto draw_row4 ;task 15,  draw fourth bricks row
    goto draw_row5 ;task 16, draw fifth bricks row
    goto draw_empty;task 17, draw empty space down to bottom
    goto draw_paddle ;task 18, draw paddle
    goto wait_field_end ;task 19, idle to end of video field
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

; task 4,  sound timer
sound
    incf task
    incf lcount
    btfss flags, F_SOUND
    leave
    btfsc flags, F_PAUSE
    call sound_fx1
    banksel sound_timer
    decfsz sound_timer
    leave
    bcf flags, F_SOUND
    banksel PWM2CON
    bcf PWM2CON,OE
    bcf PWM2CON,EN
    leave

; low pitch to high-pitch    
sound_fx1
    btfss flags, F_SOUND
    return
    btfss flags, F_EVEN
    return
    banksel PWM2CON
    lsrf PWM2PRH
    rrf PWM2PRL
    lsrf PWM2DCH
    rrf PWM2DCL
    bsf PWM2LDCON,LDA
    return
    
; high pitch to low-pitch    
sound_fx2
    btfss flags, F_SOUND
    return
    btfss flags, F_EVEN
    return
    banksel PWM2CON
    lslf PWM2PRL
    rlf PWM2PRH
    lslf PWM2DCL
    rlf PWM2DCH
    bsf PWM2LDCON,LDA
    return
    
; produce a pong sound
; input: ( d i -- )
;   d duration
;   i index frequency table    
pong
    bsf flags, F_SOUND
    banksel PWM2CON
    movfw T
    call frequency
    movwf PWM2PRH
    incf T,W
    call frequency
    movwf PWM2PRL
    lsrf PWM2PRH,W
    movwf PWM2DCH
    rrf PWM2PRL,W
    movwf PWM2DCL
    bsf PWM2LDCON,LDA
    bsf PWM2CON,OE
    bsf PWM2CON,EN
    banksel sound_timer
    pickn 1
    movwf sound_timer
    dropn 2
    return
    
;task 5, read button and paddle position
user_input
    incf task
    incf lcount
    call read_paddle
    btfsc flags, F_OVER
    bra game_over
    btfsc flags,F_START
    bra game_running
; game not running
    call read_button
    skpz
    bra skip_2_tasks
; start game    
    call game_init
    leave
game_running
    btfss flags, F_PAUSE
    leave
; game on pause    
wait_trigger
    call read_button
    skpz
    bra skip_2_tasks
    bcf flags,F_PAUSE
    call set_ball_dx
    leave
; game over
game_over
    call read_button
    skpz
    bra skip_2_tasks
    bcf flags,F_OVER
    call game_init
    incf task
    incf lcount
    leave
; while game not running skip 'move_ball' and 'collision' tasks    
skip_2_tasks
    movfw paddle_pos
    addlw 4
    movwf ball_x
    incf task
    incf task
    call lfsr16
    leave

    
read_button
    banksel PORTA
    movfw PORTA
    andlw 1<<START_BTN
    return
    
read_paddle
    banksel PWM2CON
    bcf PWM2CON,EN
    banksel TRISA
    bsf TRISA, PADDLE
    banksel ADCON0
    movlw 3
    movwf ADCON0
    btfsc ADCON0,NOT_DONE
    goto $-1
    movlw 4<<CHS0
    movwf ADCON0
    movfw ADRESH
    btfss flags, F_SOUND
    bra $+3
    banksel PWM2CON
    bsf PWM2CON,EN
    movwf paddle_pos
    movlw PADDLE_LIMIT
    subwf paddle_pos,W
    skpc
    bra $+3
    movlw PADDLE_LIMIT
    movwf paddle_pos
    banksel TRISA
    bcf TRISA, AUDIO
    return
    
   
; task 6, move recking ball.   
move_ball
    decfsz ball_timer
    bra move_ball_exit
    movfw ball_speed
    movwf ball_timer
    movfw ball_dx
    addwf ball_x
    skpz
    bra right_bound
    incf ball_x
    comf ball_dx
    incf ball_dx
    bra move_y
right_bound    
    movfw ball_x
    sublw BALL_RIGHT_BOUND
    skpnc
    bra move_y
    decf ball_x
    comf ball_dx
    incf ball_dx
move_y
    movfw ball_dy
    addwf ball_y
    movlw BALL_TOP_BOUND
    subwf ball_y,W
    skpnc
    bra bottom_bound
    comf ball_dy
    incf ball_dy
    bra move_ball_exit
bottom_bound
    movfw ball_y
    sublw BALL_BOTTOM_BOUND
    skpnc
    bra move_ball_exit
    comf ball_dy
    incf ball_dy
move_ball_exit    
    incf task
    incf lcount
    leave

; task 7, collision detection
collision
    movlw high row1
    movwf FSR1H
    movlw low row1
    movwf FSR1L
    banksel mask
; pre-compute ball column and compute brick mask
; column = 3*ball_x/16
    lslf ball_x,W
    addwf ball_x,W
    swapf WREG
    andlw 15
    movwf temp1
    movlw 8
    subwf temp1,W
    skpc
    bra $+3
    movwf temp1
    addfsr FSR1,1
; create mask    
    movlw 0x80
    movwf mask
    movfw temp1
    skpnz
    bra $+4
    lsrf mask
    decfsz temp1
    bra $-2
    btfsc ball_dy,7
    bra wall_test ; ball going up
fallout_test
; if ball_y > LAST_VIDEO_LINE-BALL_HEIGTH/2 then ball lost
    movlw LAST_VIDEO_LINE-BALL_HEIGHT/2
    subwf ball_y,W
    skpc
    bra paddle_test
ball_lost    
    bsf flags, F_PAUSE ; pause game
    decfsz balls
    bra $+2
    bcf flags, F_START
    movlw 4
    addwf paddle_pos,W
    movwf ball_x
    movlw PADDLE_Y-BRICK_HEIGHT
    movwf ball_y
    movlw -4
    movwf ball_dy
    movlw 8
    pushw
    movlw 2
    pushw
    call pong
    bra collision_exit
paddle_test    
; paddle bounce test
    movlw PADDLE_Y-BALL_HEIGHT+1
    subwf ball_y,W
    skpc
    bra wall_test
; if ball_x over paddle bounce ball
check_paddle_bounce
    movfw paddle_pos
    pushw
    movlw (PADDLE_WIDTH-BALL_WIDTH)/3+2
    addwf paddle_pos,W
    pushw
    movfw ball_x
    call between
    skpc
    bra collision_exit
    movlw -4
    movwf ball_dy
    call set_ball_dx
    movlw 2
    pushw
    pushw
    call pong
    bra collision_exit
; brick wall collision test    
wall_test
    movlw ROW1_Y
    movwf temp1
    movlw ROW5_Y+BRICK_HEIGHT
    movwf temp2
    movlw BALL_HEIGHT-1
    btfss ball_dy,7
    bra going_down
    addwf temp1
    addwf temp2
    bra $+3
going_down
    subwf temp1
    subwf temp2
    movfw temp1
    pushw
    movfw temp2
    pushw
    movfw ball_y
    call between
    skpc
    bra collision_exit
    movfw temp1
    subwf ball_y,W
    lsrf WREG
    lsrf WREG
    lsrf WREG
    brw
    bra row1_test
    bra row2_test
    bra row3_test
    bra row4_test
    bra row5_test
    reset
row1_test
    movfw mask
    andwf INDF1,W
    skpnz
    bra collision_exit
    comf mask,W
    andwf INDF1
    movlw 9
    call inc_score
    bra brick_bounce
row2_test
    addfsr FSR1,2
    movfw mask
    andwf INDF1, W
    skpnz
    bra collision_exit
    comf mask,W
    andwf INDF1
    movlw 6
    call inc_score
    bra brick_bounce
row3_test
    addfsr FSR1,4
    movfw mask
    andwf INDF1,W
    skpnz
    bra collision_exit
    comf mask,W
    andwf INDF1
    movlw 3
    call inc_score
    bra brick_bounce
row4_test
    addfsr FSR1,6
    movfw mask
    andwf INDF1,W
    skpnz
    bra collision_exit
    comf mask,W
    andwf INDF1
    movlw 2
    call inc_score
    bra brick_bounce
row5_test    
    addfsr FSR1,8
    movfw mask
    andwf INDF1,W
    skpnz
    bra collision_exit
    comf mask,W
    andwf INDF1
    movlw 1
    call inc_score
brick_bounce
    comf ball_dy
    incf ball_dy
    ;call set_ball_dx
    movlw 1
    pushw
    movlw 0
    pushw
    call pong
collision_exit
    incf task
    incf lcount
    leave

; check if  lb <= x < hb
; input:
;    WREG  x
;    stack ( lb hb -- )     
; output:
;   Carry bit set if true    
between
    movwf temp2
    pickn 1
    subwf temp2,W
    skpc
    bra between_exit
    movfw T
    subwf temp2
    movfw STATUS
    xorlw 1
    movwf STATUS
between_exit    
    dropn 2
    return
    
; task 8, wait for first video line
video_first
    incf lcount
    movlw FIRST_VIDEO_LINE
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
    
 
; task 9, draw score en ball count
draw_score ; lcount enter at 30 leave at 50
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

; display digit row pixels   
digit_row
    pushw
    rlf T
    movlw BLACK
    skpnc
    movlw WHITE
    movwf TRISA
    rlf T
    movlw BLACK
    skpnc
    movlw WHITE
    movwf TRISA
    rlf T
    movlw BLACK
    skpnc
    movlw WHITE
    movwf TRISA
    tdelay 3
    dropn 1
    bsf TRISA,VIDEO_OUT
    return
    
; task 10,  draw top wall, 8 screen lines    
draw_top_wall ;lcount enter at 50 leave at 58
    btfss flags, F_EVEN
    bra top_wall_exit
    banksel TRISA
    tdelay LEFT_MARGIN -2
    white
    tdelay COURT_WIDTH+3*BORDER_WIDTH+1
    black
top_wall_exit
    next_task BRICK_HEIGHT

; task 11,  only on even field draw vertical side bands.    
draw_void ;enter at 58 leave at 74| 255-58
    btfss flags, F_EVEN
    bra no_wall_draw
    movfw ball_y
    subwf lcount,W
    skpc
    bra no_ball_dly
    movlw BALL_HEIGHT
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
    banksel TRISA
    movfw ball_x
    skpnz
    bra ball_at_left
    sublw BALL_RIGHT_BOUND
    skpnz
    bra ball_at_right
ball_in_middle    
    movlw 1
    subwf ball_x,W
    skpnz
    addlw 1
    movwf temp1
    tdelay LEFT_MARGIN-22
    bcf TRISA,VIDEO_OUT
    tdelay 3
    movfw temp1
    bsf TRISA,VIDEO_OUT
    decfsz WREG
    bra $-1
    bcf TRISA, VIDEO_OUT
    tdelay BALL_WIDTH-1
    movfw ball_x
    bsf TRISA,VIDEO_OUT
    sublw BALL_RIGHT_BOUND
    decfsz WREG
    bra $-1
    bcf TRISA,VIDEO_OUT
    tdelay 4
    bsf TRISA,VIDEO_OUT
    bra draw_void_exit
ball_at_left
    tdelay LEFT_MARGIN-15
    bcf TRISA,VIDEO_OUT
    tdelay 12
    bsf TRISA,VIDEO_OUT
    tdelay COURT_WIDTH-6
    nop
    bcf TRISA,VIDEO_OUT
    tdelay 4
    bsf TRISA,VIDEO_OUT
    bra draw_void_exit
ball_at_right
    tdelay LEFT_MARGIN-18
    bcf TRISA,VIDEO_OUT
    tdelay 4
    bsf TRISA,VIDEO_OUT
    tdelay COURT_WIDTH-2
    bcf TRISA,VIDEO_OUT
    tdelay 10
    bsf TRISA,VIDEO_OUT
draw_void_exit    
    incf slice
    incf lcount
    movlw LAST_VIDEO_LINE+1
    subwf lcount,W
    skpz
    leave
    clrf slice
    movlw 19
    movwf task
    leave
no_wall_draw
    next_task 2*BRICK_HEIGHT

; draw 16 bricks wall
; input:
;   row in temp1,temp2
;   color in WREG
; output:
;   none    
draw_wall; macro color
;    local next_brick
    pushw
    movlw 16
    pushw
next_brick
    lslf temp2
    rlf temp1
    movlw BLACK
    skpnc
    pickn 1 ;movlw color
    movwf TRISA
    tdelay BRICK_WIDTH-9
    decfsz T
    bra next_brick
    dropn 2
    ;endm
    return
    
; task 12, draw top brick row
draw_row1 ; lcount enter at 74 leave at 82
    chroma_ref
    banksel TRISA
    movfw row1
    movwf temp1
    movfw row1+1
    movwf temp2
    tdelay LEFT_MARGIN-11
    movlw YELLOW
    call draw_wall
    black
    tdelay 3
    next_task BRICK_HEIGHT
    
; task 13, draw 2nd brick row    
draw_row2 ;lcount enter at 82 leave at 90
    chroma_invert
    banksel TRISA
    movfw row2
    movwf temp1
    movfw row2+1
    movwf temp2
    tdelay LEFT_MARGIN-11
    movlw MAUVE
    call draw_wall
    black
    tdelay 3
    next_task BRICK_HEIGHT

; task 14, draw 3rd brick row    
draw_row3 ; lcount enter at 90 leave at 98
    chroma_invert
    banksel TRISA
    movfw row3
    movwf temp1
    movfw row3+1
    movwf temp2
    tdelay LEFT_MARGIN-11
    movlw BLUE
    call draw_wall
    black
    tdelay 3
row3_exit    
    next_task BRICK_HEIGHT
    
; task 15, draw 4th brick row    
draw_row4 ; lcount enter at 98 leave at 106
    chroma_ref
    banksel TRISA
    movfw row4
    movwf temp1
    movfw row4+1
    movwf temp2
    tdelay LEFT_MARGIN-11
    movlw YELLOW
    call draw_wall
    black
    tdelay 3
    next_task BRICK_HEIGHT

; task 16, draw 5th brick row    
draw_row5 ; lcount enter at 106 leave at 114
    chroma_invert
    banksel TRISA
    movfw row5
    movwf temp1
    movfw row5+1
    movwf temp2
    tdelay LEFT_MARGIN-11
    movlw MAUVE
    call draw_wall
    black
    tdelay 3
    black
    next_task BRICK_HEIGHT

; task 17,draw all rows between paddle and lower brick row    
draw_empty ; lcount enter at 114 leave at LAST_VIDEO_LINE-PADDLE_THICKNESS+1
    tdelay LEFT_MARGIN
    tdelay 320
    black
    incf lcount
    movlw LAST_VIDEO_LINE-PADDLE_THICKNESS+1
    subwf lcount,W
    skpz
    leave
    clrf slice
    incf task
    leave

    
; task 18, draw paddle at bottom screen    
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
    next_task PADDLE_THICKNESS

; task 19,  wait end of this field, reset task to zero    
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

    
; increment user score
; This is a BCD addition where a single digit is added to score.   
; score is stored as big indian
; argument: 
;   WREG ->  bdc digit to add to score variable
inc_score
    addwf score+1
    btfsc STATUS,DC
    bra $+6
    movlw 15
    andwf score+1,W
    sublw 9
    skpnc
    bra $+3
    movlw 6
    addwf score+1
    swapf score+1,W
    andlw 15
    sublw 9
    skpnc
    bra game_over_test
    movlw 0x60
    addwf score+1
    incf score
    movlw 1
    movwf ball_speed
game_over_test ; all bricks destroyed?
    movlw 3
    subwf score,W
    skpz
    return
    movlw 0x36
    subwf score+1,W
    skpnz
    bsf flags,F_OVER
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
    
brick_wall_init
    movlw high row1
    movwf FSR1H
    movlw low row1
    movwf FSR1L
    movlw 12
    movwf temp1
    movlw 0xff
bw_init
    movwi FSR1++
    decfsz temp1
    bra bw_init
    return

; REF: https://en.wikipedia.org/wiki/LFSR#Fibonacci_LFSRs    
lfsr16
    banksel seed
    movfw seed+1
    movwf temp1
    lslf WREG
    lslf WREG
    movwf temp2
    xorwf temp1
    lslf temp2
    movfw temp2
    xorwf temp1
    lslf temp2
    lslf temp2,W
    xorwf temp1
    lslf temp1
    rlf seed
    rlf seed+1
    movfw seed
    return
    

set_ball_dx
    call lfsr16 ;random
    movlw 7
    andwf seed,W
    lslf WREG
    brw
    movlw 0
    bra set_ball_dx_exit
    movlw 1
    bra set_ball_dx_exit
    movlw -1
    bra set_ball_dx_exit
    movlw 0
    bra set_ball_dx_exit
    movlw 1
    bra set_ball_dx_exit
    movlw -1
    bra set_ball_dx_exit
    movlw -1
    bra set_ball_dx_exit
    movlw 1
set_ball_dx_exit
    movwf ball_dx
    return
    
game_init
    clrf score
    clrf score+1
    call brick_wall_init
    banksel balls
    movlw 3
    movwf balls
    clrf ball_timer
    incf ball_timer
    movlw PADDLE_Y-BRICK_HEIGHT
    movwf ball_y
    call set_ball_dx
    movlw -4
    movwf ball_dy
    movlw 2
    movwf ball_speed
    bsf flags, F_START
    bcf flags, F_PAUSE
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
; initialize LFSR seed
    banksel seed
    comf seed
    comf seed+1
    comf seed+2
    comf seed+3
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
    banksel TRISA
    bcf TRISA,SYNC_OUT
    bcf TRISA,AUDIO
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
; PWM2 sound
    banksel PWM2CON
    clrf PWM2PHL
    clrf PWM2PHH
    clrf PWM2OFL
    clrf PWM2OFH
    movlw 3<<PWM2PS0 ; clock source FOSC/8
    movwf PWM2CLKCON
    movlw high 3578;7
    movwf PWM2PRH
    movlw low 3578;7
    movwf PWM2PRL
    lsrf PWM2PRH,W
    movwf PWM2DCH
    rrf PWM2PRL,W
    movwf PWM2DCL
    bsf PWM2LDCON,LDA
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
; enbable interrupt    
    banksel PIR3
    bcf PIR3,PWM3IF
    banksel PIE3
    bsf PIE3,PWM3IE
    bsf INTCON,PEIE
    bsf INTCON,GIE
    clrf flags
    bsf flags, F_SYNC
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
    reset
    
frequency
    brw
    dt high 35795, low 35795 ; 100 hertz
    dt high 3579, low 3579 ; 1000 hertz
    reset
    
eeprom org (PROG_SIZE-EEPROM_SIZE)
max_score 
 
    END