; Copyright Jacques Deschênes 2019 
; This file is part of ntsc-1575.
;
;     ntsc-1575 is free software: you can redistribute it and/or modify
;     it under the terms of the GNU General Public License as published by
;     the Free Software Foundation, either version 3 of the License, or
;     (at your option) any later version.
;
;     ntsc-1575 is distributed in the hope that it will be useful,
;     but WITHOUT ANY WARRANTY; without even the implied warranty of
;     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;     GNU General Public License for more details.
;
;     You should have received a copy of the GNU General Public License
;     along with ntsc-1575.  If not, see <http://www.gnu.org/licenses/>.

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
 
COLOR_TEST equ 1
 
    include p16f1575.inc
    
    __config _CONFIG1, _FOSC_ECH & _WDTE_OFF & _MCLRE_OFF
    __config _CONFIG2, _PLLEN_OFF & _LVP_OFF
    
    radix dec

; constants
PROG_SIZE equ 2048  ; program words
EEPROM_SIZE equ 128 ; high endurance flash words
 
Fosc equ 28636000 ; external oscillator frequency
 
; NTSC signal 
Fhorz equ 15734 ; horizontal frequency
HPERIOD equ ((Fosc/Fhorz)-1)  ; PWM3PR count for horizontal period (63,55µS)
HSYNC  equ 134  ;  (4,7µS) PWM3DC count for horz. sync pulse
HEQUAL equ 65 ; PWM3DC count for 2,3µS equalization pulse
VSYNC_PULSE equ 776 ; PWM3PR count for 27,1µS vertical sync. pulse
HALF_LINE equ ((Fosc/Fhorz/2)-1) ; PWM3PR count for vsync lines,  half HPERIOD
; boolean flags 
F_BIT8 equ 0    ; bit 8 of scan line counter
F_EVEN equ 1    ; even field
F_SYNC equ 2    ; set during vertical synchronization phase
F_SOUND equ 3   ; sound enabled 
F_START equ 4   ; game started 
F_PAUSE equ 5   ; game paused after a ball lost
F_COOL equ 6    ; player got maximum score
F_BORDERS equ 7  ; draw borders
; video related data in this bank
VIDEO_BANK equ 0xA0
;pins assignment
AUDIO EQU RA0  ; PWM4, output for audio tones
PADDLE equ RA1 ;  analog input for potentiometer controlling paddle position
SYNC_OUT equ RA2  ; PWM3, NTSC signal synchronization
START_BTN equ RA3 ; start button input
; PPS functions
PWM1_OUT equ 3
PWM2_OUT equ 4
PWM3_OUT equ 5
PWM4_OUT equ 6
COLOR_TRIS equ TRISC 
CHROMA0 equ RC0  ; PWM1,  chroma -45deg signal output
CHROMA1 equ RC1  ; PWM2,  chroma +45deg signal output
VIDEO_Y0 equ RC2 ; video luminance bit 0
VIDEO_Y1 equ RC3 ; video luminance bit 1
CLKIN equ RA5     ; external oscillateur input.
 
    ; constants used in video display
; values are in pixels for x dimension.
; values are in number of scan lines for y dimension.
; Tcy are delay counted in MCU cycles.    
FIRST_VIDEO_LINE equ 30 ; first scan line displayed
FIRST_BRICK_Y equ 74 ; top of first brick row scan line
LAST_VIDEO_LINE	 equ 249 ; last scan line displayed
LEFT_MARGIN equ 69  ; Tcy delay before any display
PLAY_WIDTH equ 48 ; pixels
PIXEL_WIDTH equ 5; pixel width in Tcy 
BRICK_HEIGHT equ 8  ; scan lines
BRICK_WIDTH equ 4  ; pixels
BORDER_WIDTH equ 4  ; Tcy
BALL_WIDTH equ 2 ; pixels
BALL_MASK equ 0xC0 ;  applied to vbuffer to display ball
BALL_HEIGHT equ 8 ; scan lines 
BALL_LEFT_BOUND equ 0 ; pixels
BALL_RIGHT_BOUND equ (PLAY_WIDTH-BALL_WIDTH) ; pixels
BALL_TOP_BOUND equ 58  ; scan lines
BALL_BOTTOM_BOUND equ LAST_VIDEO_LINE ;scan line
PADDLE_WIDTH equ 8 ; pixels
PADDLE_THICKNESS equ 4 ; scan lines
PADDLE_LIMIT equ PLAY_WIDTH-PADDLE_WIDTH ; pixels
PADDLE_Y equ LAST_VIDEO_LINE-PADDLE_THICKNESS+1 ; scan line 
PADDLE_MASK equ 0xFF ; applied to vbuffer to display paddle
BRICKS_ROWS equ 6 ; number of bricks rows
ROW1_Y equ 74 ; row first scan line
ROW2_Y equ 82
ROW3_Y equ 90
ROW4_Y equ 98
ROW5_Y equ 106
ROW6_Y equ 114 
DIGIT_PIXEL_HEIGHT equ 4 ; scan lines
DIGIT_FONT_HEIGHT equ 5 ; 4x5 pixels font  
 
;;;;;;;;;;;;;;;;;;;;;;
;; assembler macros ;;
;;;;;;;;;;;;;;;;;;;;;;

; leave task by exiting interrupt service routine. 
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
    
    
; delay in machine cycle Tcy
; parameters:
;   mc   number of machine cycles (Tcy)   
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
    call _3ntcy ; Tcy=3+3*q
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


;;;;;;;;;;;;;;;;;;;;;;
;   colors macros
;   TRISC configuration    
;;;;;;;;;;;;;;;;;;;;;;;
OTHERS equ (1<<RC4)|(1<<RC5)
REF_COLOR equ (0<<CHROMA0)|(1<<CHROMA1)|(1<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
BLACK equ (1<<CHROMA0)|(1<<CHROMA1)|(1<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
DARK_GRAY equ (1<<CHROMA0)|(1<<CHROMA1)|(0<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
GRAY equ (1<<CHROMA0)|(1<<CHROMA1)|(1<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS
WHITE equ (1<<CHROMA0)|(1<<CHROMA1)|(0<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS
C1 equ (0<<CHROMA0)|(1<<CHROMA1)|(1<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
C2 equ (1<<CHROMA0)|(0<<CHROMA1)|(1<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
C3 equ (0<<CHROMA0)|(0<<CHROMA1)|(1<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
C4 equ (0<<CHROMA0)|(1<<CHROMA1)|(0<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
C5 equ (1<<CHROMA0)|(0<<CHROMA1)|(0<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
C6 equ (0<<CHROMA0)|(0<<CHROMA1)|(0<<VIDEO_Y0)|(1<<VIDEO_Y1)|OTHERS
C7 equ (0<<CHROMA0)|(1<<CHROMA1)|(1<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS
C8 equ (1<<CHROMA0)|(0<<CHROMA1)|(1<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS
C9 equ (0<<CHROMA0)|(0<<CHROMA1)|(1<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS
C10 equ (0<<CHROMA0)|(1<<CHROMA1)|(0<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS
C11 equ (1<<CHROMA0)|(0<<CHROMA1)|(0<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS
C12 equ (0<<CHROMA0)|(0<<CHROMA1)|(0<<VIDEO_Y0)|(0<<VIDEO_Y1)|OTHERS

    
    
; color palette selection
palette macro n ; n -> {0-3}
    banksel palnbr
    movlw n
    movwf palnbr
    banksel PWMEN
    if n==0
    bcf PWM1CON,POL  ; CHROMA0
    bcf PWM2CON,POL  ; CHROMA1
    banksel COLOR_TRIS
    exitm
    endif
    if n==1
    bsf PWM1CON,POL
    bcf PWM2CON,POL
    banksel COLOR_TRIS
    exitm
    endif
    if n==2
    bcf PWM1CON,POL
    bsf PWM2CON,POL
    banksel COLOR_TRIS
    exitm
    endif
    if n==3
    bsf PWM1CON,POL
    bsf PWM2CON,POL
    banksel COLOR_TRIS
    endif
    endm

    
; used for chroma reference signal
chroma_ref macro
    banksel PWMEN
    bcf PWM1CON,POL
    banksel COLOR_TRIS
    movlw REF_COLOR
    movwf COLOR_TRIS
    endm
    
; for the colors macros TRISC bank must be pre-selected 
;set video output to black    
black macro
    movlw BLACK
    movwf COLOR_TRIS
    endm

dark_gray macro
    movlw DARK_GRAY
    movwf COLOR_TRIS
    endm
    
gray macro
    movlw GRAY
    movwf COLOR_TRIS
    endm
    
; set video output to white    
white macro    
    movlw WHITE
    movwf COLOR_TRIS
    endm

colorn  macro n
    movlw n
    movwf COLOR_TRIS
    endm

color_bars macro
   colorn BLACK
   tdelay 4
   colorn C1
   tdelay 4
   colorn C2
   tdelay 4
   colorn C3
   tdelay 4
   colorn C4
   tdelay 4
   colorn C5
   tdelay 4
   colorn C6
   tdelay 4
   colorn C7
   tdelay 4
   colorn C8
   tdelay 4
   colorn C9
   tdelay 4
   colorn C10
   tdelay 4
   colorn C11
   tdelay 4
   colorn C12
;   tdelay 4
   endm
    
; set video output to mauve    
mauve macro
    movlw C2
    movwf COLOR_TRIS
    endm

; set video output to yellow   
yellow macro
    movlw C1
    movwf COLOR_TRIS
    endm
    
; set video output to blue
blue macro
    movlw C3
    movwf COLOR_TRIS
    endm
    
; set video output to dark green    
dark_green macro
    movlw C4
    movwf COLOR_TRIS
    endm

; draw borders
borders macro
    bsf flags,F_BORDERS
    endm
    
; no borders draw
no_borders macro    
    bcf flags,F_BORDERS
    endm
    
; shift out 1 bit    
display_bit macro n
    lslf vbuffer+n
    movlw BLACK
    skpnc
    movfw fg_color
    movwf COLOR_TRIS
    endm
    
; display a byte of pixels from vbuffer
; this macro expansion result in 8*5 -> 40 instructions    
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
STACK_SIZE equ 80 ; size of argument stack
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

; drop n elements from stack
dropn macro n
    addfsr T,n
    endm

; copy nth element of stack to WREG
;  n {0..31}, 0 is T   
pickn macro n
    moviw n[SP]
    endm
   
    
    
;;;;;;;;;;;;;;;;;;;;;;;;;;
;;    variables
;;;;;;;;;;;;;;;;;;;;;;;;;;
 
    
    udata 0x20 ; bank 0 
stack res STACK_SIZE ; arguments stack
 
; video display manipulate TRISC register
; to avoid banksel during video update
; place variables related to video in same bank as TRISC
v_array   udata 0xA0 ; bank 1
vbuffer res 6
temp3 res 1 ; to simplify mask application on last byte of vbuffer 
row1 res 6; brick wall row1
fill1 res 2 ; to simplify computation, faster to multiply and divide by 8 rather than 6.
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
ball_byte res 1 ; ball byte offset in vbuffer
ball_mask res 2 ; ball mask to put in vbuffer 
sound_timer res 1 ; sound duration in multiple of 16.7msec. 
balls res 1 ; number of recking balls available
palnbr res 1 ; active palette number
 
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
seed res 1 ; pseudo random number generator used by lfsr8
 
;; cpu reset entry point
RES_VECT  CODE    0x0000            
    goto    initialize  ; go to beginning of program
    
; delay = 3+3*n  (including the call)    
; SEE tdelay macro
;input:
;   WREG <- n {1..255}
_3ntcy
    decfsz WREG
    bra $-1
_4tcy
    return  

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    
; interrupt service routine triggered by PWM3 period rollover
; after initialization all processing in done inside 
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
; clear video buffer before each line display
    banksel COLOR_TRIS
    clrf vbuffer
    clrf vbuffer+1
    clrf vbuffer+2
    clrf vbuffer+3
    clrf vbuffer+4
    clrf vbuffer+5
    borders ; default to drawing borders
; generate chroma synchronization
    tdelay 14
    chroma_ref
    tdelay 16
    black
    movfw palnbr
    banksel PWMEN
    btfsc WREG,0
    bsf PWM1CON,POL
    banksel COLOR_TRIS
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
    goto collision ; task 8, check for collision with bricks.
    goto video_first ; task 9, wait FIRST_VIDEO line.
    goto draw_score ;task 10,  draw score en ball count
    goto draw_top_wall ;task 11,  draw top wall
    goto draw_sides ;task 12, draw play space with sides walls
    goto draw_bricks  ;task 13, draw bricks rows
    goto draw_empty;task 14, draw empty space with sides walls down to bottom
    goto draw_paddle ;task 15, draw paddle
    goto wait_field_end ;task 16, idle to end of video field
if COLOR_TEST
    goto color_bars_task ; task 17
endif    
    reset ; error trap, task out of range
isr_exit
    banksel TRISA
    btfsc flags, F_SOUND
    bcf TRISA,PADDLE
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
 ; divide lcount by 2 go get correct scan line count    
    lsrf lcount
    call lfsr8 ; update prng 60 times/sec.
if COLOR_TEST
    movlw 9 ; video_first
    movwf task
else    
    incf task
endif    
    leave

; task 4, read paddle potentiometer
read_paddle
    incf task
    btfsc flags, F_SOUND
    leave
    bsf TRISA, PADDLE
    movlw 3
    movwf ADCON0
    btfsc ADCON0,NOT_DONE
    bra $-1
    lsrf ADRESH,W
    movwf paddle_pos
    movlw PADDLE_LIMIT
    subwf paddle_pos,W
    movlw PADDLE_LIMIT
    skpnc
    movwf paddle_pos
    movlw 4<<CHS0
    movwf ADCON0
; create paddle mask
; paddle_mask and paddle_byte used when it is time to display paddle
; paddle_byte=paddle_pos/8
; paddle_mask=PADDLE_MASK>>(paddle_pos%8)   
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
    bra read_paddle_exit
    lsrf paddle_mask
    rrf paddle_mask+1
    decfsz WREG
    bra $-3
read_paddle_exit    
    btfsc flags, F_PAUSE
    call track_paddle
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
    banksel PWM4CON
    bcf PWM4CON,OE
    bcf PWM4CON,EN
    banksel TRISA
    bsf TRISA,PADDLE
    leave

; sound effect, low pitch to high-pitch    
sound_fx1
    btfss flags, F_EVEN
    return
    banksel PWM4CON
    lsrf PWM4PRH
    rrf PWM4PRL
    lsrf PWM4DCH
    rrf PWM4DCL
    bsf PWM4LDCON,LDA
    return
    
; initialize sound generation.
; input:
;   T = duration
;   WREG = index in frequency table    
; outpout:
;   none    
sound_init
    pushw  ; ( d i -- )
    bsf flags, F_SOUND
    banksel PWM4CON
    movfw T
    call frequency
    movwf PWM4PRH
    incf T,W
    call frequency
    movwf PWM4PRL
    lsrf PWM4PRH,W
    movwf PWM4DCH
    rrf PWM4PRL,W
    movwf PWM4DCL
    bsf PWM4LDCON,LDA
    bsf PWM4CON,OE
    bsf PWM4CON,EN
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
    banksel TRISA
    skpz
    leave
    btfsc flags, F_START
    bra resume_game
    call game_init
    leave
resume_game
    btfss flags, F_PAUSE
    leave
    call resume
    leave
    
; task 7, move recking ball.   
; also check for ball bounce on paddle
; and ball lost at bottom    
move_ball
    incf task
    decfsz ball_timer
    leave
    movfw ball_speed
    movwf ball_timer
    movfw ball_dx
    addwf ball_x
    movfw ball_dy
    addwf ball_y
; test x bounds
    clrw
    pushw
    movlw BALL_RIGHT_BOUND+1
    pushw
    movfw ball_x
    call between
    skpnc
    bra y_bounds
; ball_x out of bounds    
    comf ball_dx
    incf ball_dx
    movlw BALL_RIGHT_BOUND
    btfsc ball_x,7
    clrf ball_x
    skpz
    movwf ball_x
; test y bounds
y_bounds    
    movlw BALL_TOP_BOUND
    pushw
    movlw PADDLE_Y-BALL_HEIGHT
    pushw
    movfw ball_y
    call between
    skpnc
    bra move_ball_exit
; ball_y out of bound
    comf ball_dy
    incf ball_dy
    movlw BALL_TOP_BOUND
    btfss ball_y,7
    movwf ball_y
    btfss ball_y,7
    bra move_ball_exit
;ball at bottom
    call paddle_bounce
    skpnc
    bra move_ball_exit
ball_lost
    decfsz balls
    bra pause_game
    bcf flags, F_START
    bra freeze_ball
pause_game
    bsf flags, F_PAUSE
    movlw 8
    pushw
    movlw 2
    call sound_init
freeze_ball
    clrf ball_dx
    clrf ball_dy
    movlw 3
    addwf paddle_pos,W
    movwf ball_x
    movlw PADDLE_Y-BALL_HEIGHT-1
    movwf ball_y
move_ball_exit
    call create_ball_mask
    leave

; check if ball is bouncing on paddle
; input:
;   none
; output:
;   C set if bounced    
paddle_bounce
    movfw paddle_pos
    subwf ball_x,W
    skpc 
    return ; ball fall left of paddle
    movlw PADDLE_WIDTH-BALL_WIDTH+1
    addwf paddle_pos,W
    subwf ball_x,W
    skpc
    bra ball_bouncing
    clrc ; ball fall right of paddle
    return
ball_bouncing
; bounce direction depend where paddle was hit.    
    andlw 0x6
    brw
    movlw -1      ;0-1 paddle hit left, bounce left
    bra set_dx
    movfw ball_dx ;2-3 paddle hit at center mirror bounce
    bra set_dx
    movfw ball_dx ;4-5  mirror bounce
    bra set_dx
    movlw 1       ;6 paddle hit right, bounce right
set_dx    
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
    
; task 8, check collision with bricks
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
; design to take same number of Tcy whatever the path.
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
if COLOR_TEST
    movlw 17
    movwf task
else    
    incf task
endif    
    leave
   
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The following tasks are responsible to render video display.
; Each video line must be completed by setting color to black.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; check if ball is visible on this scan line    
; visible if ball_y <= lcount < ball_y+BALL_HEIGHT
; designed to use a constant number of Tcy    
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
    
    
; display vbuffer
; the 6 macros 'display_byte' unroll to 240 instructions    
display_vbuffer
    movlw WHITE
    btfss flags,F_BORDERS
    movlw BLACK
    movwf COLOR_TRIS
    tdelay BORDER_WIDTH-3
    display_byte 0
    display_byte 1
    display_byte 2
    display_byte 3
    display_byte 4
    display_byte 5
    movlw WHITE
    btfss flags,F_BORDERS
    movlw BLACK
    movwf COLOR_TRIS
    tdelay BORDER_WIDTH
    black
    return
 
; task 10, draw score en ball count
;  lcount 30-49    
draw_score 
    banksel COLOR_TRIS
    lsrf slice,W
    lsrf WREG
    movwf temp3
    movfw score
    call digits
    swapf WREG
    iorwf vbuffer
    swapf score+1,W
    call digits
    iorwf vbuffer
    movfw score+1
    call digits
    swapf WREG
    iorwf vbuffer+1
    movfw balls
    call digits
    iorwf vbuffer+4
    no_borders
    call display_vbuffer
score_exit
    next_task DIGIT_PIXEL_HEIGHT*DIGIT_FONT_HEIGHT ;4*5 

    
; task 11,  draw top wall, 8 screen lines 
; lcount 50-57    
draw_top_wall
;    banksel TRISA
    comf vbuffer
    comf vbuffer+1
    comf vbuffer+2
    comf vbuffer+3
    comf vbuffer+4
    comf vbuffer+5
    movlw WHITE
    movwf fg_color
    tdelay LEFT_MARGIN
;    white
    call display_vbuffer
;    white
;    tdelay BORDER_WIDTH
;    black
    next_task BRICK_HEIGHT

; put ball mask in video_buffer
; designed to take a constant number of Tcy    
; 38 Tcy    
put_ball_in_buffer
    call ball_visible ; +22 Tcy
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

empty_common    
    call put_ball_in_buffer
    movlw WHITE
    movwf fg_color
    tdelay LEFT_MARGIN-37
;    white
    call display_vbuffer
;    white
;    tdelay BORDER_WIDTH
;    black
    return
    
; task 12,  draw vertical sides over bricks.
; lcount 58-73    
draw_sides 
;    banksel TRISA
    tdelay 2
    call empty_common
    next_task 2*BRICK_HEIGHT
 
; copy a brick row in vbuffer
; FSR1 initialized to point row    
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

;common code to all bricks row display    
rows_common
    movwf fg_color
    clrf FSR1H
    call copy_row
    tdelay 1
;    white
    call display_vbuffer
;    white
;    tdelay BORDER_WIDTH
;    black
    next_task BRICKS_ROWS*BRICK_HEIGHT
    
; task 13, draw brick rows
; lcount 74-121   
draw_bricks
;    banksel vbuffer
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
    banksel COLOR_TRIS
    lsrf WREG
    lsrf WREG
    ; select color according to row index {0..5}
    brw
    movlw C1
    bra rows_common
    movlw C2
    bra rows_common
    movlw C3
    bra rows_common
    movlw C4
    bra rows_common
    movlw C5
    bra rows_common
    movlw C6
    bra rows_common
    
MSG_FIRST equ 40
MSG_HEIGHT equ 40
MSG_PIXELS_COUNT equ 16 
; task 14
; draw all rows below bricks down to paddle
; also display message when game over. 
; lcount 122-241 
draw_empty
;    banksel TRISA
    btfss flags, F_START
    bra print_msg
    call empty_common
    bra draw_empty_exit
print_msg    
    movlw C1 ; message color
    movwf fg_color
    movlw MSG_FIRST
    pushw
    movlw MSG_FIRST+MSG_HEIGHT
    pushw
    movfw slice
    call between
    skpc
    bra msg01
    movlw high end_msg
    movwf FSR1H
    movlw low end_msg
    movwf FSR1L
    clrc
    movlw 10
    btfsc flags,F_COOL
    addwf FSR1L
    skpnc
    incf FSR1H
; copy message bitmap in vbuffer
; message is  16 pixels wide
copy_msg
    movlw MSG_FIRST
    subwf slice,W
    andlw 0xf8
    lsrf WREG
    lsrf WREG
    addwf FSR1L
    skpnc
    incf FSR1H
    moviw FSR1++
    movwf vbuffer+1
    moviw FSR1++
    movwf vbuffer+2
    bra msg02
msg01
    tdelay 24
msg02
    tdelay LEFT_MARGIN-45
    call display_vbuffer
draw_empty_exit
    next_task PADDLE_Y-ROW6_Y-BRICK_HEIGHT

    
; task 15, draw paddle at bottom screen  
; lcount 242-249    
draw_paddle
;    banksel TRISA
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
 ;   white
    call display_vbuffer
;    white
;    tdelay BORDER_WIDTH
;    black
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

color_bars_task:
    tdelay 8
    white
    tdelay 4
    gray
    tdelay 4
    dark_gray
    palette 0
    color_bars
    palette 1
    color_bars
    palette 2
    color_bars
    palette 3
    color_bars
    black
    incf slice
    movlw 220
    xorwf slice,W
    skpz
    leave
    movlw 16
    movwf task
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
    bcf flags,F_START ; game over
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

; pseudo random number generator    
; REF: https://en.wikipedia.org/wiki/LFSR#Fibonacci_LFSRs  
POLY equ 0xb8 
lfsr8
    lsrf seed
    movlw POLY
    skpnc
    xorwf seed
; call here for 5 Tcy delay using a single instruction
; see tdelay macro 
_5tcy
    movfw seed
    return
    
; ball is sent at random direcction at serve.
set_ball_dx
    call lfsr8 ;random
    andlw 7
    lslf WREG
    brw
    movlw 1
    bra set_ball_dx_exit
    movlw -1
    bra set_ball_dx_exit
    movlw 1
    bra set_ball_dx_exit
    movlw -1
    bra set_ball_dx_exit
    movlw 1
    bra set_ball_dx_exit
    movlw -1
    bra set_ball_dx_exit
    movlw 1
    bra set_ball_dx_exit
    movlw 0
set_ball_dx_exit
    movwf ball_dx
    return

; compute ball_mask and ball_byte
; ball_mask= BALL_MASK>>(ball_x%8)
; ball_byte= ball_x/8     
create_ball_mask
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
    
game_init
    clrf score
    clrf score+1
    call brick_wall_init
    banksel balls
    movlw 2
    movwf ball_timer
    movlw 2
    movwf ball_speed
    movlw 3
    movwf balls
    bsf flags,F_START
resume
    bcf flags, F_PAUSE
    call set_ball_dx
    movlw -4
    movwf ball_dy
track_paddle
    movlw PADDLE_Y-BALL_HEIGHT-1
    movwf ball_y
    movlw 3
    addwf paddle_pos,W
    movwf ball_x
    call create_ball_mask
    return

;|----------------------|
;|  MCU initialization  |
;|----------------------|
MAIN_PROG CODE  ; let linker place main program

initialize
; peripherals to pin assignment
; output pins
    banksel RC0PPS
    movlw PWM1_OUT 
    movwf RC0PPS  ; CHROMA0, -45 degreee phase
    movlw PWM2_OUT
    movwf RC1PPS  ; CHROMA1   ; +45 degree phase
    movlw PWM3_OUT
    movwf RA2PPS  ; SYNC_OUT
    movlw PWM4_OUT
    movwf RA0PPS  ; AUDIO
    banksel PPSLOCK
    movlw 0x55
    movwf PPSLOCK
    movlw 0xAA
    movwf PPSLOCK
    bsf PPSLOCK,PPSLOCKED
; clear common RAM
    movlw 0x70
    movwf FSR0L
    clrw
    movwi FSR0++
    btfss FSR0L,7
    bra $-2
; initialize LFSR seed
    bsf seed,0
; disable analog inputs, except AN1
    banksel ANSELA
    clrf ANSELA
    clrf ANSELC
; paddle potentiometer input     
    bsf ANSELA,PADDLE
;   setup arguments stack pointer
    movlw low (stack+STACK_SIZE)
    movwf FSR0L
; adc clock Fosc/32    
    banksel ADCON1
    movlw (2<<ADCS0)
    movwf ADCON1
; pin setup
; video luminance output always set to 1.    
    banksel LATC
    bsf LATC, VIDEO_Y0
    bsf LATC, VIDEO_Y1
; nstc sync output
    banksel TRISA
    bcf TRISA,SYNC_OUT
;  clear all PWM special fonction registers
;  to start configuration in a clean state.
    movlw high PWMEN
    movwf FSR1H
    movlw low PWMEN
    movwf FSR1L
clr_pwm_sfr
    clrf INDF1
    incf FSR1L
    movlw 0xc1
    subwf FSR1L,W
    skpz
    bra clr_pwm_sfr
; PWM1,PWM2 chroma0/1 signal on RC0/1
    banksel PWM1CON
    movlw (1<<EN)|(1<<OE)
    movwf PWM1CON
    movwf PWM2CON
    movlw 7
    movwf PWM1PRL
    movwf PWM2PRL
    movlw 4
    movwf PWM1DCL
    movwf PWM2DCL
    bsf PWM1LDCON,7
    bsf PWM2LDCON,7
; PWM4 sound, clock source Fosc/8
    movlw 3<<PWM4PS0
    movwf PWM4CLKCON
; PWM3 set to horizontal period 15734 hertz, output on RA2
    movlw low HPERIOD
    movwf PWM3PRL
    movlw high HPERIOD
    movwf PWM3PRH
    movlw HSYNC
    movwf PWM3DCL
    movlw (1<<EN)|(1<<OE)|(1<<POL)
    movwf PWM3CON
    bsf PWM3LDCON,7
    bsf PWM3INTE,PRIE
; enbable interrupt
; only interrupt used is PWM3PR rollover    
    banksel PIR3
    bcf PIR3,PWM3IF
    banksel PIE3
    bsf PIE3,PWM3IE
    bsf INTCON,PEIE
    bsf INTCON,GIE
    palette 0
; test code
; all processing done in ISR    
    goto $

;digits character table
; input:
;   temp3 -> glyph row
;   WREG -> digit
; output:
;   WREG -> pixels
; 2 digits packed in 5 bytes
; high nibble even digit, low nibble odd digit    
digits
    movwf temp1
    andlw 0x0e
    movwf temp2
    lslf temp2
    lslf temp2
    addwf temp2
    lsrf temp2,W
    addwf temp3,W
    call digit_row
    btfss temp1,0
    swapf WREG
    andlw 0xf
    return
digit_row    
    brw
    dt  0x44,0xAC,0xA4,0xA4,0x4E ; 0, 1
    dt  0xEE,0x22,0xCC,0x82,0xEE ; 2, 3
    dt  0xAE,0xA8,0xEE,0x22,0x2E ; 4, 5
    dt  0xCE,0x82,0xE2,0xA2,0xE2 ; 6, 7
    dt  0xEE,0xAA,0xEE,0xA2,0xE6 ; 8, 9
    
; PWM2PR count for sound frequencies    
frequency
    brw
    dt high 35795, low 35795 ; 100 hertz
    dt high 3579, low 3579 ; 1000 hertz
  
; END! message bitmap
end_msg
;    brw
    data 0xf4,0x5c
    data 0x86,0x52
    data 0xe5,0x52
    data 0x84,0xd2
    data 0xf4,0x5c
  
; COOL message bitmap    
cool_msg
;    brw
    data 0xee,0xe8
    data 0x8a,0xa8
    data 0x8a,0xa8
    data 0x8a,0xa8
    data 0xee,0xef
    
    
eeprom org (PROG_SIZE-EEPROM_SIZE)
 
    END