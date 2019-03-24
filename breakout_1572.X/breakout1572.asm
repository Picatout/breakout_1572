/*
* Copyright Jacques Deschênes 2019 
* This file is part of breakout_1572.
*
*     breakout_1572 is free software: you can redistribute it and/or modify
*     it under the terms of the GNU General Public License as published by
*     the Free Software Foundation, either version 3 of the License, or
*     (at your option) any later version.
*
*     breakout_1572 is distributed in the hope that it will be useful,
*     but WITHOUT ANY WARRANTY; without even the implied warranty of
*     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*     GNU General Public License for more details.
*
*     You should have received a copy of the GNU General Public License
*     along with breakout_1572.  If not, see <http://www.gnu.org/licenses/>.
*/

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
;  SCHEDULER
;  scan lines  | slices  |   usage
;  =================================
;    1-3       |  6      | task 0, vertical pre-equalization
;    4-6       |  6      | task 1, vertical sync
;    7-9       |  6      | task 2, vertical post-equalization
;    10        |  1      | task 3, synchronization end
;    11        |  1      | task 4, reserved slot, do nothing    
;    12        |  1      | task 5, sound timer
;    13        |  1      | task 6, user input
;    14        |  1      | task 7, move ball
;    15        |  1      | task 8, collision control
;    16-29     |  14     | task 9, do nothing until first visible line    
;    30-49     |  20     | task 10, display score and balls count
;    50-57     |  8      | task 11, draw top border
;    58-73     |  16     | task 12, draw space over bricks rows
;    74-121    |  48     | task 13, draw 6 bricks rows
;    122-241   |  120	 | task 14, draw space below bricks rows
;    242-249   |  8      | task 15, draw paddle
;    250-262/3 |  11/12  | task 16, wait end of field    
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
Tcy equ 140 ; CPU cycle in nanoseconds (139.683 nanosecond)
 
; NTSC signal 
Fhorz equ 15734 ; horizontal frequency
HPERIOD equ ((Fosc/Fhorz)-1)  ; horizontal period pwm count(63,55µS)
HSYNC  equ 134  ;  (4,7µS) ; horz. sync. pwm pulse count
HEQUAL equ 65 ; 2,3µS equalization pwm pulse count
VSYNC_PULSE equ 776 ; 27,1µS vertical sync. pwm pulse count
HALF_LINE equ ((Fosc/Fhorz/2)-1) 
; boolean flags 
F_BIT8 equ 0    ; bit 8 of line counter
F_EVEN equ 1    ; even field
F_SYNC equ 2    ; vertical synchronization phase
F_SOUND equ 3   ; sound enabled 
F_START equ 4   ; game started 
F_PAUSE equ 5   ; game pause after a ball lost
F_OVER equ 6    ; game over
F_COOL equ 7    ; player got maximum score
 
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
FIRST_BRICK_Y equ 74 ; lcount first brick scan line
LAST_VIDEO_LINE	 equ 249 ; last video line displayed
LEFT_MARGIN equ 69  ; tcy delay before any display
PLAY_WIDTH equ 48 ; pixels
PIXEL_WIDTH equ 5; pixel width in tcy 
BRICK_HEIGHT equ 8  ; scan lines
BRICK_WIDTH equ 4  ; pixels
BORDER_WIDTH equ 4  ; Tcy
BALL_WIDTH equ 2 ; pixels
BALL_MASK equ 0xC0 ;  
BALL_HEIGHT equ 8 ; scan lines 
BALL_LEFT_BOUND equ 0 ; pixel
BALL_RIGHT_BOUND equ (PLAY_WIDTH-BALL_WIDTH) ; pixels
BALL_TOP_BOUND equ 58  ; scan lines
BALL_BOTTOM_BOUND equ LAST_VIDEO_LINE
PADDLE_WIDTH equ 8 ; pixels
PADDLE_THICKNESS equ 4 ; scan lines
PADDLE_LIMIT equ PLAY_WIDTH-PADDLE_WIDTH ; pixels
PADDLE_Y equ LAST_VIDEO_LINE-PADDLE_THICKNESS+1 ; 
PADDLE_MASK equ 0xFF 
BRICKS_ROWS equ 6 ; number of bricks rows
ROW1_Y equ 74
ROW2_Y equ 82
ROW3_Y equ 90
ROW4_Y equ 98
ROW5_Y equ 106
ROW6_Y equ 114 

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
    leave
    endm
    
    
; swap variable with WREG    
swap_var macro var
    xorwf var
    xorwf var,W
    xorwf var
    endm
    

; delay in machine cycle T
; parameters:
;   mc   number of machine cycles    
tdelay macro mc 
    if mc==0
    exitm
    endif
    if mc==1
    nop
    exitm
    endif
    if mc==2
    bra $+1
    exitm
    endif
    if mc==3
    nop
    bra $+1
    exitm
    endif
    if mc==4
    call _4tcy
    exitm
    endif
    if mc==5
    call _5tcy
    exitm
    endif
    if mc>5
    variable q=(mc-3)/3
    variable r=mc-3-3*q
    movlw q
    call _3ntcy ; tcy=3+3*q
    if (r==2)
    bra $+1
    exitm
    endif 
    if (r==1)
    nop
    exitm
    endif
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
;   TRISA configuration    
;;;;;;;;;;;;;;;;;;;;;;;
OTHERS equ (0<<SYNC_OUT)|(1<<PADDLE)|(1<<START_BTN)    
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
    endm
    
; set video output to white    
white macro    
    movlw WHITE
    movwf TRISA
    endm

#define gray white
    
; set video output to mauve    
mauve macro
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

; shift out 1 bit    
display_bit macro n
    lslf vbuffer+n
    movlw BLACK
    skpnc
    movfw fg_color
    movwf TRISA
    endm
    
; display a byte of pixels    
; input:
;   n is byte number {0..5}    
display_byte macro n
    display_bit n
    display_bit n
    display_bit n
    display_bit n
    display_bit n
    display_bit n
    display_bit n
    display_bit n
    endm
    
   
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  stack manipulation macros
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    
STACK_SIZE equ 16 ; size of argument stack
#define T INDF0 ; indirect access to top of argument stack
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
;  n {0..31}, 0 is T   
pickn macro n
    moviw n[SP]
    endm
   
; copy WREG to nth element of stack
; n {0..31}, 0 is T
pokew macro n
    movwi n[SP]
    endm
    
    
;;;;;;;;;;;;;;;;;;;;;;;;;;
;;    variables
;;;;;;;;;;;;;;;;;;;;;;;;;;
 
    
    udata 0x20 ; bank 0
stack res 16 ; arguments stack
seed res 2 ; prng seed used by lfsr16
 
; video display manipulate TRISA register
; to avoid banksel during video update
; place variables related to video in same bank as TRISA 
v_array   udata 0xA0 ; bank 1
vbuffer res 6
temp3 res 1
row1 res 6; brick wall row1
fill1 res 2 
row2 res 6
fill2 res 2 
row3 res 6
fill3 res 2 
row4 res 6
fill4 res 2 
row5 res 6
fill5 res 2
row6 res 6
fill6 res 2 
fg_color res 1
paddle_byte res 1 ; paddle offset in vbuffer
paddle_mask res 2 ; paddle mask to put in vbuffer 
ball_byte res 1 ; byte offset in vbuffer
ball_mask res 2 ; ball mask to put in vbuffer 
sound_timer res 1 ; sound duration in multiple of 16.7msec. 
balls res 1 ; number of recking balls available
 
; common 16 bytes RAM accessible whatever the selected bank 
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
odd_fld_pread res 1 ; value of paddle read during odd field
 
;; cpu reset entry point
RES_VECT  CODE    0x0000            
    goto    initialize  ; go to beginning of program
    reset   
    reset
    reset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    
; interrupt service routine triggered by PWM3 period rollover
; after initialization is done all processing in done inside 
; this interrupt.
; It is designed as a round robin scheduler.    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    
ISR CODE 0x0004
isr
    incf lcount
    skpnz
    bsf flags, F_BIT8
    btfsc flags, F_SYNC
    goto task_switch
    banksel vbuffer
    clrf vbuffer
    clrf vbuffer+1
    clrf vbuffer+2
    clrf vbuffer+3
    clrf vbuffer+4
    clrf vbuffer+5
; generate chroma sync
    tdelay 18
    chroma_ref
    banksel TRISA
    bcf TRISA,CHROMA
    tdelay 16
    bsf TRISA,CHROMA
    porch_on
task_switch ; round robin task scheduler   
    movfw task
    brw
    goto pre_vsync ;task 0, vertical pre-equalization pulses
    goto vsync ;task 1, vertical sync pulses
    goto post_vsync ;task 2, vertical post-equalization pulses
    goto vsync_end ;task 3, return to normal video line
    goto read_paddle; task 4, read paddle potentiometer
    goto sound ;task 5, check sound timer expiration
    goto read_button ;task 6,  read button
    goto move_ball ;task 7, move recking ball.
    goto collision ; task 8, check for collision with brick wall and paddle
    goto video_first ; task 9, wait FIRST_VIDEO line.
    goto draw_score ;task 10,  draw score en ball count
    goto draw_top_wall ;task 11,  draw top wall
    goto draw_sides ;task 12, draw play space
    goto draw_bricks  ;task 13, draw bricks rows
    goto draw_empty;task 14, draw empty space down to bottom
    goto draw_paddle ;task 15, draw paddle
    goto wait_field_end ;task 16, idle to end of video field
    reset ; error trap, task out of range
isr_exit
    banksel TRISA
    btfsc flags, F_SOUND
    bcf TRISA,AUDIO
    porch_off
    banksel PWM3INTF
    bcf PWM3INTF,PRIF
    retfie

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  all tasks routine are here            ;;
;;  each must be terminate by leave macro ;;    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
; task 0, vertical synchronization pre equalization
; 6 half horizontal scan lines    
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
; 6 half horizontal scan lines    
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
; 6 half horizontal scan lines    
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
; rest horizonal line to its normal length.
; set lcount to 9.    
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
    lsrf lcount
    leave

; task 4, read paddle potentiometer
; paddle_pos is mean between 2 reading
; first reading during odd field is saved
; in 'odd_fld_pread' variable
; second reading during even field
; is added to first and result divided by 4
; to get paddle_pos    
read_paddle
    incf task
    btfsc flags, F_SOUND
    leave
    banksel TRISA
    bsf TRISA, PADDLE
    banksel ADCON0
    movlw 3
    movwf ADCON0
    btfsc ADCON0,NOT_DONE
    bra $-1
    movfw ADRESH
    pushw
    movlw 4<<CHS0
    movwf ADCON0
    btfss flags, F_EVEN
    bra even_field_read
    popw
    movwf odd_fld_pread
    leave
; potentiometer read during even field
even_field_read    
    popw
    addwf odd_fld_pread
    rrf odd_fld_pread
    lsrf odd_fld_pread,W
    movwf paddle_pos
    movlw PADDLE_LIMIT
    subwf paddle_pos,W
    movlw PADDLE_LIMIT
    skpnc
    movwf paddle_pos
; create paddle mask
    call compute_paddle_mask
    banksel TRISA
    leave

    
; task 5,  sound timer
; if sound active process it.    
sound
    incf task
    btfss flags, F_SOUND
    leave
    btfsc flags, F_PAUSE
    call sound_fx1
    banksel sound_timer
    decfsz sound_timer
    leave
sound_off    
    bcf flags, F_SOUND
    banksel PWM2CON
    bcf PWM2CON,OE
    bcf PWM2CON,EN
    banksel TRISA
    bsf TRISA,PADDLE
    leave

; sound effect, low pitch to high-pitch    
sound_fx1
    btfss flags, F_EVEN
    return
    banksel PWM2CON
    lsrf PWM2PRH
    rrf PWM2PRL
    lsrf PWM2DCH
    rrf PWM2DCL
    bsf PWM2LDCON,LDA
    return
    
;; sound effect, high pitch to low-pitch    
;sound_fx2
;    btfss flags, F_EVEN
;    return
;    banksel PWM2CON
;    lslf PWM2PRL
;    rlf PWM2PRH
;    lslf PWM2DCL
;    rlf PWM2DCH
;    bsf PWM2LDCON,LDA
;    return
    
; initialize sound generation.
; input:
;   T = duration
;   WREG = index in frequency table    
; outpout:
;   none    
sound_init
    pushw  ; ( d i -- )
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
    banksel TRISA
    bcf TRISA,AUDIO
    return
    
;task 6, read button and paddle position
read_button
    incf task
    banksel PORTA
    movfw PORTA
    andlw 1<<START_BTN
    movwf temp1
    btfsc flags, F_OVER
    bra game_over
    btfsc flags,F_START
    bra game_running
; game not running
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
    skpz
    bra skip_2_tasks
    bcf flags,F_PAUSE
    call set_ball_dx
    leave
; game over
game_over
    skpz
    bra skip_2_tasks
    call game_init
;    incf task
    leave
; while game not running skip 'move_ball' and 'collision' tasks    
skip_2_tasks
    movfw paddle_pos
    addlw 2
    movwf ball_x
    call compute_ball_mask
    incf task ; skip move_ball
    incf task ; skip collision
    call lfsr16
    leave

    
    

; paddle_mask and paddle_byte used when it is time to display paddle
; paddle_byte=paddle_pos/8
; paddle_mask=PADDLE_MASK>>(paddle_pos%8)    
compute_paddle_mask
    lsrf paddle_pos,W
    lsrf WREG
    lsrf WREG
    movwf paddle_byte
    movlw PADDLE_MASK
    movwf paddle_mask
    clrf paddle_mask+1
    movlw 7
    andwf paddle_pos,W
    skpnz
    return
    lsrf paddle_mask
    rrf paddle_mask+1
    decfsz WREG
    bra $-3
    return
    
    
    
    
; task 7, move recking ball.   
move_ball
    decfsz ball_timer
    bra move_ball_exit
    movfw ball_speed
    movwf ball_timer
    movfw ball_dx
    addwf ball_x
    btfss ball_dx,7
    bra right_bound
left_bound
    btfss ball_x,7
    bra move_y
    clrf ball_x
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
    btfss ball_dy,7
    bra bottom_bound
top_bound    
    movlw BALL_TOP_BOUND
    subwf ball_y,W
    skpnc
    bra move_ball_exit
    movlw BALL_TOP_BOUND
    movwf ball_y
    comf ball_dy
    incf ball_dy
    bra move_ball_exit
bottom_bound
    movfw ball_y
    sublw PADDLE_Y-BALL_HEIGHT-1
    skpnc
    bra move_ball_exit
    call paddle_bounce
    skpnc
    bra move_ball_exit
ball_lost
    bsf flags, F_PAUSE ; pause game
    banksel balls
    decfsz balls
    bra $+3
    bcf flags, F_START
    bsf flags, F_OVER
    movlw 2
    addwf paddle_pos,W
    movwf ball_x
    movlw PADDLE_Y-BALL_HEIGHT+1
    movwf ball_y
    movlw -4
    movwf ball_dy
    movlw 8
    pushw
    movlw 2
    call sound_init
    incf task ; skip collision task
move_ball_exit
    call compute_ball_mask
    incf task
    leave

; check if ball is bouncing on paddle
; input:
;   none
; output:
;   C set if bounced    
paddle_bounce
; if ball_x over paddle bounce ball
    movfw paddle_pos
    pushw
    skpnz
    decf T
    addlw PADDLE_WIDTH
    pushw
    movfw ball_x
    call between
    skpnc
    bra bouncing
    bcf STATUS,C
    return
bouncing
    movlw PADDLE_Y-BALL_HEIGHT
    movwf ball_y
    comf ball_dy
    incf ball_dy
; bounce direction depend where paddle was hit.    
    movfw paddle_pos
    subwf ball_x,W
    skpc
    bra bounce_left
    skpnz
    bra bounce_left
    movlw PADDLE_WIDTH-2
    addwf paddle_pos,W
    subwf ball_x,W
    movlw 1
    skpnc
    movwf ball_dx ; bounce right
    bra paddle_sound
bounce_left
    movlw -1
    movwf ball_dx
paddle_sound    
    movlw 2
    pushw
    call sound_init
; skip collision task
    incf task
; report bounce    
    bsf STATUS,C
    return
    
    
; compute ball_mask and ball_byte
; ball_mask= BALL_MASK>>(ball_x%8)
; ball_byte= ball_x/8     
compute_ball_mask
    banksel vbuffer
    lsrf ball_x,W
    lsrf WREG
    lsrf WREG
    movwf ball_byte
    movlw BALL_MASK
    movwf ball_mask
    clrf ball_mask+1
    movlw 7
    andwf ball_x,W
    skpnz
    return
    lsrf ball_mask
    rrf ball_mask+1
    decfsz WREG
    bra $-3
    return
    
; task 8, collision detection
collision
    movlw ROW1_Y
    pushw
    movlw ROW6_Y+BRICK_HEIGHT
    pushw
    movfw ball_y
    call between
    skpc
    bra collision_exit
    banksel row1
    clrf FSR1H
    movlw low row1
    movwf FSR1L
    movlw ROW1_Y
    subwf ball_y,W
    andlw 0xf8
    pushw
    addwf FSR1L
    movfw ball_byte
    addwf FSR1L
    movlw 0xf0
    btfsc ball_x,2
    swapf WREG
    andwf INDF1,W
    skpnz
    bra collision_exit
    movlw 0x0f
    btfsc ball_x,2
    swapf WREG
    andwf INDF1
    comf ball_dy
    incf ball_dy
    movfw ball_dy
    addwf ball_y
    popw
    lsrf WREG
    lsrf WREG
    brw
    movlw 9
    bra add_score
    movlw 9
    bra add_score
    movlw 7
    bra add_score
    movlw 5
    bra add_score
    movlw 3
    bra add_score
    movlw 1
add_score    
    call inc_score
pong_sound
    movlw 1
    pushw
    movlw 0
    call sound_init
collision_exit
    incf task
    leave

    
    
; check if  lb <= x < hb
; 13 tcy    
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
    bra between_exit2
    movfw T
    subwf temp2
    movfw STATUS
    xorlw 1
    movwf STATUS
between_exit    
    dropn 2
    return  ; 13 tcy
; add tcy to have constant tcy for this routine whatever the path    
between_exit2
    bra $+1
    bra between_exit
    
; task 9, wait for first video line
video_first
    movlw FIRST_VIDEO_LINE-1
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

; check if ball is visible on this scan line    
; visible if ball_y <=lcount<ball_y+BALL_HEIGHT    
;  22 tcy   
;  input:
;	none    
;  output:
;	C set if true   
ball_visible
    movfw ball_y
    pushw
    addlw BALL_HEIGHT
    pushw
    movfw lcount
    call between ; +13 tcy
    return
    
    
    
display_vbuffer
    display_byte 0
    display_byte 1
    display_byte 2
    display_byte 3
    display_byte 4
    display_byte 5
    return
 
; task 10, draw score en ball count
;  lcount 30-49    
draw_score 
    banksel TRISA
    movfw slice
    lsrf WREG
    lsrf WREG
    pushw
    movlw 0xf
    andwf score,W
    call digits
    iorwf vbuffer
    swapf score+1,W
    andlw 0xf
    call digits
    swapf WREG
    iorwf vbuffer
    movlw 0xf
    andwf score+1,W
    call digits
    iorwf vbuffer+1
    movfw balls
    call digits
    iorwf vbuffer+5
    tdelay 9
    call display_vbuffer
    dropn 1
score_exit
    next_task 5*4

    
; task 11,  draw top wall, 8 screen lines 
; lcount 50-57    
draw_top_wall
    banksel TRISA
    comf vbuffer
    comf vbuffer+1
    comf vbuffer+2
    comf vbuffer+3
    comf vbuffer+4
    comf vbuffer+5
    movlw WHITE
    movwf fg_color
    tdelay LEFT_MARGIN
    white
    call display_vbuffer
    white
    tdelay BORDER_WIDTH
    black
    next_task BRICK_HEIGHT

; put ball mask in video_buffer
; 38 tcy    
put_ball_in_buffer
    call ball_visible ; +22tcy
    skpc
    bra kill_time
    clrf FSR1H
    movlw low vbuffer
    movwf FSR1L
    movfw ball_byte
    addwf FSR1L
    movfw ball_mask
    movwi FSR1++
    movfw ball_mask+1
    movwi [FSR1]
    return ; 37 tcy
kill_time 
    tdelay 7
    return ; 37 tcy
    
; task 12,  only on even field draw vertical sides and ball.
; lcount 58-73    
draw_sides 
    banksel TRISA
    call put_ball_in_buffer
    tdelay LEFT_MARGIN-31
    white
    call display_vbuffer
    white
    tdelay BORDER_WIDTH
    black
    next_task 2*BRICK_HEIGHT
 
copy_row
    moviw FSR1++
    iorwf vbuffer
    moviw FSR1++
    iorwf vbuffer+1
    moviw FSR1++
    iorwf vbuffer+2
    moviw FSR1++
    iorwf vbuffer+3
    moviw FSR1++
    iorwf vbuffer+4
    moviw FSR1++
    iorwf vbuffer+5
    return    

rows_common
    movwf fg_color
    clrf FSR1H
    call copy_row
    tdelay 1
    white
    call display_vbuffer
    white
    tdelay BORDER_WIDTH
    black
    next_task BRICKS_ROWS*BRICK_HEIGHT
    
; task 13, draw brick rows
; lcount 74-121   
draw_bricks
    banksel vbuffer
    call put_ball_in_buffer
    movlw low row1
    movwf FSR1L
    movlw 0xf8
    andwf slice,W
    addwf FSR1L
    banksel PWM1CON
    pushw
    movlw 2<<3
    subwf T,W
    skpnc
    bsf PWM1CON,POL
    popw
    banksel TRISA
    lsrf WREG
    lsrf WREG
    brw
    movlw YELLOW
    bra rows_common
    movlw YELLOW
    bra rows_common
    movlw MAUVE
    bra rows_common
    movlw MAUVE
    bra rows_common
    movlw BLUE
    bra rows_common
    movlw BLUE
    bra rows_common
    
MSG_FIRST equ 40
MSG_HEIGHT equ 40
MSG_PIXELS_COUNT equ 16 
; task 14
; draw all rows below bricks to paddle
; lcount 122-241 
draw_empty
    banksel TRISA
    btfsc flags, F_OVER
    bra print_msg
    call put_ball_in_buffer
    movlw WHITE
    movwf fg_color
    tdelay LEFT_MARGIN-35
    white
    call display_vbuffer
    white
    tdelay BORDER_WIDTH
    black
    bra draw_empty_exit
print_msg    
    movlw YELLOW ; message color
    movwf fg_color
    movlw MSG_FIRST
    pushw
    movlw MSG_FIRST+MSG_HEIGHT
    pushw
    movfw slice
    call between
    skpc
    bra msg
    btfss flags, F_COOL
    bra display_end
; perfect score display 'COOL' message
    movlw high cool_msg
    movwf FSR1H
    movlw low cool_msg
    movwf FSR1L
    call display_msg
    bra msg
; display 'END!' message    
display_end
    movlw high end_msg
    movwf FSR1H
    movlw low end_msg
    movwf FSR1L
    call display_msg
msg
    call display_vbuffer
draw_empty_exit
    next_task PADDLE_Y-ROW6_Y-BRICK_HEIGHT
;    incf slice
;    movlw LAST_VIDEO_LINE-PADDLE_THICKNESS+1
;    subwf lcount,W
;    skpz
;    leave
;    clrf slice
;    incf task
;    leave

; display end message
; message as a maximum of 24 vbuffer    
display_msg
    movlw MSG_FIRST
    subwf slice,W
    lsrf WREG
    lsrf WREG
    lsrf WREG
    movwf temp1
    lslf WREG
    addwf temp1,W
    addwf FSR1L
    skpnc
    incf FSR1H
    moviw FSR1++
    movwf vbuffer+1
    moviw FSR1++
    movwf vbuffer+2
    moviw FSR1++
    movwf vbuffer+3
    return
    
; task 15, draw paddle at bottom screen  
; lcount 242-249    
draw_paddle
    banksel TRISA
    clrf FSR1H
    movlw low vbuffer
    movwf FSR1L
    movfw paddle_byte
    addwf FSR1L
    movfw paddle_mask
    movwi FSR1++
    movfw paddle_mask+1
    movwi  [FSR1]
    movlw WHITE
    movwf fg_color
    tdelay LEFT_MARGIN-3
    white
    call display_vbuffer
    white
    tdelay BORDER_WIDTH
    black
    next_task PADDLE_THICKNESS

; task 16,  wait end of this field, reset task to zero    
; lcount 251-262/3    
wait_field_end
    btfsc flags, F_BIT8
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
    bcf flags, F_BIT8
    bsf flags, F_SYNC
; toggle odd/even field flag    
    movlw 1<<F_EVEN
    xorwf flags
    leave

; helper functions

; delay = 4+(n-1)*3    
;input:
;   WREG <- n {1..255}
_3ntcy
    decfsz WREG
    bra $-1
    return
_5tcy ; call here for 5*tcy delay using a single instruction
    nop
_4tcy ; call here for 4*Tcy delay using a single instruction    
    return

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
; double ball speed if score >=200
    movlw 2
    subwf score,W
    skpc
    return
    movlw 1
    movwf ball_speed
game_over_test ; all bricks destroyed?
    movlw 4
    subwf score,W
    skpz
    return
    movlw 0x08
    subwf score+1,W
    skpz
    return
    bsf flags,F_OVER ; game over
    bsf flags,F_COOL ; with maximum score.
    return
    
    
brick_wall_init
    movlw high row1
    movwf FSR1H
    movlw low row1
    movwf FSR1L
    movlw BRICKS_ROWS*8
    movwf temp1
    movlw 0xff
bw_init
    movwi FSR1++
    decfsz temp1
    bra bw_init
    return

; compute tcy delay from pixel coordinateur
;  1 pixel is 5 tcy wide.
; input:
;   WREG  px
; output
;   WREG  tcy    
px2tcy
   pushw
   lslf WREG
   lslf WREG
   addwf T
   popw
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
    movlw PADDLE_Y-BALL_HEIGHT+1
    movwf ball_y
    call set_ball_dx
    movlw -4
    movwf ball_dy
    movlw 2
    movwf ball_speed
    clrf flags
    bsf flags, F_START
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

initialize
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
    call game_init
    clrf flags
    bsf flags, F_SYNC
; test code
    bsf flags, F_START
; all processing done in ISR    
    goto $

;digits character table
; input:
;   T -> glyph row
;   WREG -> digit
; output:
;   WREG -> pixels
;   T -> glyph row    
digits
    pushw 
    lslf WREG
    lslf WREG
    addwf T
    popw
    addwf T,W
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
  
;display END! when game is over    
end_msg
;    brw
    data 0xe8,0xc8,0
    data 0x8e,0xa8,0
    data 0xea,0xa8,0
    data 0x8a,0xa0,0
    data 0xea,0xc8,0
  
cool_msg
;    brw
    data 0xee,0xe8,0
    data 0x8a,0xa8,0
    data 0x8a,0xa8,0
    data 0x8a,0xa8,0
    data 0xee,0xee,0
    
eeprom org (PROG_SIZE-EEPROM_SIZE)
max_score 
 
    END