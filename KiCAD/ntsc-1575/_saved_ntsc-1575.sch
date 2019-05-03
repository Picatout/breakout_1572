EESchema Schematic File Version 4
LIBS:ntsc-1575-cache
EELAYER 26 0
EELAYER END
$Descr A4 11693 8268
encoding utf-8
Sheet 1 1
Title ""
Date ""
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
$EndDescr
$Comp
L power:GND #PWR012
U 1 1 5C76F026
P 3300 4700
F 0 "#PWR012" H 3300 4450 50  0001 C CNN
F 1 "GND" H 3305 4527 50  0000 C CNN
F 2 "" H 3300 4700 50  0001 C CNN
F 3 "" H 3300 4700 50  0001 C CNN
	1    3300 4700
	1    0    0    -1  
$EndComp
Text GLabel 3300 3900 1    50   Input ~ 0
+5v
$Comp
L device:POT RV1
U 1 1 5C76F0E5
P 6700 4400
F 0 "RV1" H 6631 4354 50  0000 R CNN
F 1 "2K (paddle)" H 6631 4445 50  0000 R CNN
F 2 "" H 6700 4400 50  0001 C CNN
F 3 "" H 6700 4400 50  0001 C CNN
	1    6700 4400
	-1   0    0    1   
$EndComp
$Comp
L device:R R11
U 1 1 5C76F165
P 6400 4400
F 0 "R11" V 6275 4400 50  0000 C CNN
F 1 "1K" V 6400 4400 50  0000 C CNN
F 2 "" V 6330 4400 50  0001 C CNN
F 3 "" H 6400 4400 50  0001 C CNN
	1    6400 4400
	0    1    1    0   
$EndComp
$Comp
L power:GND #PWR011
U 1 1 5C76F1C8
P 6700 4550
F 0 "#PWR011" H 6700 4300 50  0001 C CNN
F 1 "GND" H 6705 4377 50  0000 C CNN
F 2 "" H 6700 4550 50  0001 C CNN
F 3 "" H 6700 4550 50  0001 C CNN
	1    6700 4550
	1    0    0    -1  
$EndComp
Text GLabel 6700 3950 1    50   Input ~ 0
+5v
Text GLabel 5100 3850 1    50   Input ~ 0
+5v
$Comp
L power:GND #PWR08
U 1 1 5C76F233
P 6000 4100
F 0 "#PWR08" H 6000 3850 50  0001 C CNN
F 1 "GND" V 6005 3972 50  0000 R CNN
F 2 "" H 6000 4100 50  0001 C CNN
F 3 "" H 6000 4100 50  0001 C CNN
	1    6000 4100
	0    -1   -1   0   
$EndComp
Wire Wire Line
	6000 4100 6000 4300
Text Label 5850 4400 0    50   ~ 0
audio
$Comp
L conn:Conn_Coaxial J2
U 1 1 5C76F2F8
P 6600 3375
F 0 "J2" H 6699 3351 50  0000 L CNN
F 1 "audio_out" H 6699 3260 50  0000 L CNN
F 2 "" H 6600 3375 50  0001 C CNN
F 3 "" H 6600 3375 50  0001 C CNN
	1    6600 3375
	1    0    0    -1  
$EndComp
$Comp
L power:GND #PWR06
U 1 1 5C76F361
P 6600 3575
F 0 "#PWR06" H 6600 3325 50  0001 C CNN
F 1 "GND" H 6600 3450 50  0000 C CNN
F 2 "" H 6600 3575 50  0001 C CNN
F 3 "" H 6600 3575 50  0001 C CNN
	1    6600 3575
	1    0    0    -1  
$EndComp
$Comp
L device:R R9
U 1 1 5C76F376
P 6325 3525
F 0 "R9" V 6200 3525 50  0000 C CNN
F 1 "1K" V 6325 3525 50  0000 C CNN
F 2 "" V 6255 3525 50  0001 C CNN
F 3 "" H 6325 3525 50  0001 C CNN
	1    6325 3525
	-1   0    0    1   
$EndComp
$Comp
L power:GND #PWR07
U 1 1 5C76F3E4
P 6325 3675
F 0 "#PWR07" H 6325 3425 50  0001 C CNN
F 1 "GND" H 6330 3502 50  0000 C CNN
F 2 "" H 6325 3675 50  0001 C CNN
F 3 "" H 6325 3675 50  0001 C CNN
	1    6325 3675
	1    0    0    -1  
$EndComp
$Comp
L device:R R8
U 1 1 5C76F3FB
P 5975 3375
F 0 "R8" V 6050 3400 50  0000 C CNN
F 1 "6k8" V 5975 3375 50  0000 C CNN
F 2 "" V 5905 3375 50  0001 C CNN
F 3 "" H 5975 3375 50  0001 C CNN
	1    5975 3375
	0    -1   -1   0   
$EndComp
Wire Wire Line
	6325 3375 6450 3375
Connection ~ 6325 3375
Text Label 5825 3375 2    50   ~ 0
audio
Text Label 5850 4700 0    50   ~ 0
chroma0
Text Label 5850 4600 0    50   ~ 0
sync
Text Label 5850 4900 0    50   ~ 0
video_y0
$Comp
L switches:SW_Push_45deg SW2
U 1 1 5C76F596
P 4350 5125
F 0 "SW2" V 4396 4984 50  0000 R CNN
F 1 "start" V 4300 5075 50  0000 R CNN
F 2 "" H 4350 5125 50  0001 C CNN
F 3 "" H 4350 5125 50  0001 C CNN
	1    4350 5125
	0    -1   -1   0   
$EndComp
$Comp
L power:GND #PWR013
U 1 1 5C76F6D6
P 4250 5325
F 0 "#PWR013" H 4250 5075 50  0001 C CNN
F 1 "GND" H 4255 5152 50  0000 C CNN
F 2 "" H 4250 5325 50  0001 C CNN
F 3 "" H 4250 5325 50  0001 C CNN
	1    4250 5325
	1    0    0    -1  
$EndComp
$Comp
L conn:Conn_Coaxial J1
U 1 1 5C76F7FB
P 6575 2525
F 0 "J1" H 6674 2501 50  0000 L CNN
F 1 "video_out" H 6674 2410 50  0000 L CNN
F 2 "" H 6575 2525 50  0001 C CNN
F 3 "" H 6575 2525 50  0001 C CNN
	1    6575 2525
	1    0    0    -1  
$EndComp
$Comp
L power:GND #PWR02
U 1 1 5C76F8AD
P 6575 2725
F 0 "#PWR02" H 6575 2475 50  0001 C CNN
F 1 "GND" H 6580 2552 50  0000 C CNN
F 2 "" H 6575 2725 50  0001 C CNN
F 3 "" H 6575 2725 50  0001 C CNN
	1    6575 2725
	1    0    0    -1  
$EndComp
$Comp
L device:R R4
U 1 1 5C76F8CA
P 6150 2525
F 0 "R4" V 6050 2525 50  0000 C CNN
F 1 "150" V 6150 2525 50  0000 C CNN
F 2 "" V 6080 2525 50  0001 C CNN
F 3 "" H 6150 2525 50  0001 C CNN
	1    6150 2525
	0    -1   -1   0   
$EndComp
$Comp
L device:R R7
U 1 1 5C76F93C
P 6150 2975
F 0 "R7" V 6050 2975 50  0000 C CNN
F 1 "680" V 6150 2975 50  0000 C CNN
F 2 "" V 6080 2975 50  0001 C CNN
F 3 "" H 6150 2975 50  0001 C CNN
	1    6150 2975
	0    -1   -1   0   
$EndComp
$Comp
L device:R R3
U 1 1 5C76F9A1
P 6150 2300
F 0 "R3" V 6050 2300 50  0000 C CNN
F 1 "1k" V 6150 2300 50  0000 C CNN
F 2 "" V 6080 2300 50  0001 C CNN
F 3 "" H 6150 2300 50  0001 C CNN
	1    6150 2300
	0    -1   -1   0   
$EndComp
Wire Wire Line
	6300 2725 6300 2975
Connection ~ 6300 2525
Wire Wire Line
	6300 2525 6425 2525
Text Label 6000 2525 2    50   ~ 0
video_y1
Text Label 6000 2975 2    50   ~ 0
sync
$Comp
L device:Battery BT1
U 1 1 5C7703E9
P 3750 3300
F 0 "BT1" H 3858 3346 50  0000 L CNN
F 1 "6V" H 3858 3255 50  0000 L CNN
F 2 "" V 3750 3360 50  0001 C CNN
F 3 "~" V 3750 3360 50  0001 C CNN
	1    3750 3300
	1    0    0    -1  
$EndComp
$Comp
L device:D_ALT D1
U 1 1 5C770637
P 4400 3100
F 0 "D1" H 4400 3200 50  0000 C CNN
F 1 "1N4001" H 4425 3000 50  0000 C CNN
F 2 "" H 4400 3100 50  0001 C CNN
F 3 "" H 4400 3100 50  0001 C CNN
	1    4400 3100
	-1   0    0    1   
$EndComp
$Comp
L switches:SW_SPST SW1
U 1 1 5C770789
P 4050 3100
F 0 "SW1" H 4050 3335 50  0000 C CNN
F 1 "power" H 4050 3244 50  0000 C CNN
F 2 "" H 4050 3100 50  0001 C CNN
F 3 "" H 4050 3100 50  0001 C CNN
	1    4050 3100
	1    0    0    -1  
$EndComp
Wire Wire Line
	3750 3100 3850 3100
Text GLabel 4775 3100 2    50   Input ~ 0
+5v
$Comp
L power:GND #PWR05
U 1 1 5C77092A
P 3750 3500
F 0 "#PWR05" H 3750 3250 50  0001 C CNN
F 1 "GND" H 3755 3327 50  0000 C CNN
F 2 "" H 3750 3500 50  0001 C CNN
F 3 "" H 3750 3500 50  0001 C CNN
	1    3750 3500
	1    0    0    -1  
$EndComp
$Comp
L device:CP C4
U 1 1 5C770A3C
P 4650 3250
F 0 "C4" H 4768 3296 50  0000 L CNN
F 1 "10µF/25v" H 4768 3205 50  0000 L CNN
F 2 "" H 4688 3100 50  0001 C CNN
F 3 "" H 4650 3250 50  0001 C CNN
	1    4650 3250
	1    0    0    -1  
$EndComp
Wire Wire Line
	4550 3100 4650 3100
Wire Wire Line
	4650 3100 4775 3100
Connection ~ 4650 3100
$Comp
L power:GND #PWR04
U 1 1 5C770C55
P 4650 3400
F 0 "#PWR04" H 4650 3150 50  0001 C CNN
F 1 "GND" H 4655 3227 50  0000 C CNN
F 2 "" H 4650 3400 50  0001 C CNN
F 3 "" H 4650 3400 50  0001 C CNN
	1    4650 3400
	1    0    0    -1  
$EndComp
NoConn ~ 3000 4400
$Comp
L device:R R13
U 1 1 5C83F1D9
P 4125 4800
F 0 "R13" V 4225 4800 50  0000 C CNN
F 1 "10K" V 4125 4775 50  0000 C CNN
F 2 "" V 4055 4800 50  0001 C CNN
F 3 "" H 4125 4800 50  0001 C CNN
	1    4125 4800
	-1   0    0    1   
$EndComp
$Comp
L device:R R12
U 1 1 5C83F7B0
P 4450 4750
F 0 "R12" V 4550 4750 50  0000 C CNN
F 1 "470" V 4450 4725 50  0000 C CNN
F 2 "" V 4380 4750 50  0001 C CNN
F 3 "" H 4450 4750 50  0001 C CNN
	1    4450 4750
	1    0    0    -1  
$EndComp
Wire Wire Line
	4450 4900 4450 4950
$Comp
L device:C C6
U 1 1 5C83FD1B
P 5525 3925
F 0 "C6" V 5475 4025 50  0000 C CNN
F 1 "100nF" V 5575 4075 50  0000 C CNN
F 2 "" H 5563 3775 50  0001 C CNN
F 3 "" H 5525 3925 50  0001 C CNN
	1    5525 3925
	0    1    1    0   
$EndComp
Wire Wire Line
	5100 3850 5100 3925
Wire Wire Line
	5100 3925 5375 3925
Connection ~ 5100 3925
Wire Wire Line
	5675 3925 6000 3925
Wire Wire Line
	6000 3925 6000 4100
Connection ~ 6000 4100
$Comp
L device:C C9
U 1 1 5C84052A
P 4900 5100
F 0 "C9" H 4725 5125 50  0000 C CNN
F 1 "220nF" H 4775 5000 50  0000 C CNN
F 2 "" H 4938 4950 50  0001 C CNN
F 3 "" H 4900 5100 50  0001 C CNN
	1    4900 5100
	-1   0    0    1   
$EndComp
Wire Wire Line
	4900 4950 4450 4950
Connection ~ 4450 4950
Wire Wire Line
	4450 4950 4450 5025
Wire Wire Line
	4250 5225 4250 5325
Wire Wire Line
	4900 5250 4900 5325
Wire Wire Line
	4900 5325 4250 5325
Connection ~ 4250 5325
$Comp
L device:C C5
U 1 1 5C840FAE
P 6125 3525
F 0 "C5" H 6275 3525 50  0000 C CNN
F 1 "47nF" H 6275 3625 50  0000 C CNN
F 2 "" H 6163 3375 50  0001 C CNN
F 3 "" H 6125 3525 50  0001 C CNN
	1    6125 3525
	-1   0    0    1   
$EndComp
Connection ~ 6325 3675
Wire Wire Line
	6125 3375 6325 3375
Connection ~ 6125 3375
$Comp
L Oscillators:CXO_DIP8 X1
U 1 1 5C8529EE
P 3300 4400
F 0 "X1" H 3025 4675 50  0000 L CNN
F 1 "28.636Mhz" H 3400 4650 50  0000 L CNN
F 2 "Oscillators:Oscillator_DIP-8" H 3750 4050 50  0001 C CNN
F 3 "http://cdn-reichelt.de/documents/datenblatt/B400/OSZI.pdf" H 3200 4400 50  0001 C CNN
	1    3300 4400
	1    0    0    -1  
$EndComp
Wire Wire Line
	4125 4950 4450 4950
Wire Wire Line
	6125 3675 6325 3675
$Comp
L device:R R10
U 1 1 5C8D60BE
P 6700 4100
F 0 "R10" V 6575 4100 50  0000 C CNN
F 1 "100" V 6700 4100 50  0000 C CNN
F 2 "" V 6630 4100 50  0001 C CNN
F 3 "" H 6700 4100 50  0001 C CNN
	1    6700 4100
	-1   0    0    1   
$EndComp
$Comp
L device:C C8
U 1 1 5C8D6341
P 7250 4250
F 0 "C8" V 7200 4350 50  0000 C CNN
F 1 "220nF" V 7300 4400 50  0000 C CNN
F 2 "" H 7288 4100 50  0001 C CNN
F 3 "" H 7250 4250 50  0001 C CNN
	1    7250 4250
	0    1    1    0   
$EndComp
Wire Wire Line
	7100 4250 6700 4250
Connection ~ 6700 4250
$Comp
L power:GND #PWR09
U 1 1 5C8D6943
P 7700 4250
F 0 "#PWR09" H 7700 4000 50  0001 C CNN
F 1 "GND" H 7705 4077 50  0000 C CNN
F 2 "" H 7700 4250 50  0001 C CNN
F 3 "" H 7700 4250 50  0001 C CNN
	1    7700 4250
	1    0    0    -1  
$EndComp
Wire Wire Line
	7400 4250 7700 4250
$Comp
L Personal_KiCAD:PIC16F1575 U1
U 1 1 5CCA57A9
P 5550 4600
F 0 "U1" H 5575 5099 50  0000 C CNN
F 1 "PIC16F1575" H 5575 5016 39  0000 C CNN
F 2 "" H 5550 4600 50  0001 C CNN
F 3 "" H 5550 4600 50  0001 C CNN
	1    5550 4600
	1    0    0    -1  
$EndComp
Wire Wire Line
	5100 4300 5250 4300
Wire Wire Line
	6000 4300 5850 4300
Wire Wire Line
	3600 4400 5250 4400
Wire Wire Line
	5100 3925 5100 4300
Text GLabel 4125 4650 1    50   Input ~ 0
+5v
Wire Wire Line
	4450 4600 5250 4600
$Comp
L device:R R1
U 1 1 5CCA8C64
P 5200 2000
F 0 "R1" V 5100 2000 50  0000 C CNN
F 1 "100" V 5200 2000 50  0000 C CNN
F 2 "" V 5130 2000 50  0001 C CNN
F 3 "" H 5200 2000 50  0001 C CNN
	1    5200 2000
	0    1    1    0   
$EndComp
$Comp
L device:R R5
U 1 1 5CCA8E47
P 5425 2650
F 0 "R5" V 5325 2650 50  0000 C CNN
F 1 "100" V 5425 2650 50  0000 C CNN
F 2 "" V 5355 2650 50  0001 C CNN
F 3 "" H 5425 2650 50  0001 C CNN
	1    5425 2650
	-1   0    0    1   
$EndComp
$Comp
L device:C C3
U 1 1 5CCA8F37
P 5150 2500
F 0 "C3" V 4898 2500 50  0000 C CNN
F 1 "470p" V 4989 2500 50  0000 C CNN
F 2 "" H 5188 2350 50  0001 C CNN
F 3 "" H 5150 2500 50  0001 C CNN
	1    5150 2500
	0    1    1    0   
$EndComp
$Comp
L device:C C2
U 1 1 5CCA94EE
P 5425 2150
F 0 "C2" H 5310 2104 50  0000 R CNN
F 1 "470p" H 5310 2195 50  0000 R CNN
F 2 "" H 5463 2000 50  0001 C CNN
F 3 "" H 5425 2150 50  0001 C CNN
	1    5425 2150
	-1   0    0    1   
$EndComp
Wire Wire Line
	5350 2000 5425 2000
Wire Wire Line
	5300 2500 5425 2500
Wire Wire Line
	5425 2500 5625 2500
Wire Wire Line
	5625 2500 5625 2300
Wire Wire Line
	5625 2300 6000 2300
Connection ~ 5425 2500
$Comp
L power:GND #PWR01
U 1 1 5CCAAE93
P 5425 2300
F 0 "#PWR01" H 5425 2050 50  0001 C CNN
F 1 "GND" H 5425 2175 50  0000 C CNN
F 2 "" H 5425 2300 50  0001 C CNN
F 3 "" H 5425 2300 50  0001 C CNN
	1    5425 2300
	1    0    0    -1  
$EndComp
$Comp
L power:GND #PWR03
U 1 1 5CCAAF2F
P 5425 2800
F 0 "#PWR03" H 5425 2550 50  0001 C CNN
F 1 "GND" H 5425 2675 50  0000 C CNN
F 2 "" H 5425 2800 50  0001 C CNN
F 3 "" H 5425 2800 50  0001 C CNN
	1    5425 2800
	1    0    0    -1  
$EndComp
Text Label 4750 2000 2    50   ~ 0
chroma0
Text Label 5000 2500 2    50   ~ 0
chroma1
$Comp
L device:C C1
U 1 1 5CCAB2FE
P 4900 2000
F 0 "C1" V 4648 2000 50  0000 C CNN
F 1 "100n" V 4739 2000 50  0000 C CNN
F 2 "" H 4938 1850 50  0001 C CNN
F 3 "" H 4900 2000 50  0001 C CNN
	1    4900 2000
	0    1    1    0   
$EndComp
Connection ~ 5425 2000
Text Label 5850 4800 0    50   ~ 0
chroma1
Text Label 5250 4900 2    50   ~ 0
video_y1
$Comp
L device:R R6
U 1 1 5CCAC5B0
P 6150 2725
F 0 "R6" V 6050 2725 50  0000 C CNN
F 1 "330" V 6150 2725 50  0000 C CNN
F 2 "" V 6080 2725 50  0001 C CNN
F 3 "" H 6150 2725 50  0001 C CNN
	1    6150 2725
	0    -1   -1   0   
$EndComp
Text Label 6000 2725 2    50   ~ 0
video_y0
Wire Wire Line
	6300 2725 6300 2550
Connection ~ 6300 2725
Wire Wire Line
	6250 4400 6250 4500
Wire Wire Line
	6250 4500 5850 4500
$Comp
L device:D D2
U 1 1 5CCADB99
P 7475 5125
F 0 "D2" H 7475 4909 50  0000 C CNN
F 1 "D" H 7475 5000 50  0000 C CNN
F 2 "" H 7475 5125 50  0001 C CNN
F 3 "" H 7475 5125 50  0001 C CNN
	1    7475 5125
	-1   0    0    1   
$EndComp
$Comp
L switches:SW_Push_Dual_x2 SW3
U 1 1 5CCADDBD
P 7825 5125
F 0 "SW3" H 7825 5375 50  0000 C CNN
F 1 "UP" H 7825 5300 50  0000 C CNN
F 2 "" H 7825 5325 50  0001 C CNN
F 3 "" H 7825 5325 50  0001 C CNN
	1    7825 5125
	1    0    0    -1  
$EndComp
$Comp
L device:D D3
U 1 1 5CCADE3F
P 7475 5475
F 0 "D3" H 7475 5691 50  0000 C CNN
F 1 "D" H 7475 5600 50  0000 C CNN
F 2 "" H 7475 5475 50  0001 C CNN
F 3 "" H 7475 5475 50  0001 C CNN
	1    7475 5475
	1    0    0    -1  
$EndComp
$Comp
L device:D D5
U 1 1 5CCADEA7
P 7475 5950
F 0 "D5" H 7475 6166 50  0000 C CNN
F 1 "D" H 7475 6075 50  0000 C CNN
F 2 "" H 7475 5950 50  0001 C CNN
F 3 "" H 7475 5950 50  0001 C CNN
	1    7475 5950
	1    0    0    -1  
$EndComp
$Comp
L switches:SW_Push_Dual_x2 SW4
U 1 1 5CCADF15
P 7825 5475
F 0 "SW4" H 7825 5400 50  0000 C CNN
F 1 "DOWN" H 7825 5625 50  0000 C CNN
F 2 "" H 7825 5675 50  0001 C CNN
F 3 "" H 7825 5675 50  0001 C CNN
	1    7825 5475
	1    0    0    -1  
$EndComp
$Comp
L switches:SW_Push_Dual_x2 SW6
U 1 1 5CCADFB5
P 7825 5950
F 0 "SW6" H 7825 6175 50  0000 C CNN
F 1 "LEFT" H 7825 6100 50  0000 C CNN
F 2 "" H 7825 6150 50  0001 C CNN
F 3 "" H 7825 6150 50  0001 C CNN
	1    7825 5950
	1    0    0    -1  
$EndComp
$Comp
L device:D D4
U 1 1 5CCAE84B
P 6975 5950
F 0 "D4" H 6975 5734 50  0000 C CNN
F 1 "D" H 6975 5825 50  0000 C CNN
F 2 "" H 6975 5950 50  0001 C CNN
F 3 "" H 6975 5950 50  0001 C CNN
	1    6975 5950
	1    0    0    1   
$EndComp
$Comp
L switches:SW_Push_Dual_x2 SW5
U 1 1 5CCAE852
P 6625 5950
F 0 "SW5" H 6625 6175 50  0000 C CNN
F 1 "BTN_A" H 6625 6100 50  0000 C CNN
F 2 "" H 6625 6150 50  0001 C CNN
F 3 "" H 6625 6150 50  0001 C CNN
	1    6625 5950
	1    0    0    -1  
$EndComp
$Comp
L device:D D6
U 1 1 5CCAE859
P 6975 6300
F 0 "D6" H 6975 6516 50  0000 C CNN
F 1 "D" H 6975 6425 50  0000 C CNN
F 2 "" H 6975 6300 50  0001 C CNN
F 3 "" H 6975 6300 50  0001 C CNN
	1    6975 6300
	-1   0    0    -1  
$EndComp
$Comp
L device:D D7
U 1 1 5CCAE860
P 7475 6300
F 0 "D7" H 7475 6516 50  0000 C CNN
F 1 "D" H 7475 6425 50  0000 C CNN
F 2 "" H 7475 6300 50  0001 C CNN
F 3 "" H 7475 6300 50  0001 C CNN
	1    7475 6300
	-1   0    0    -1  
$EndComp
$Comp
L switches:SW_Push_Dual_x2 SW7
U 1 1 5CCAE867
P 6625 6300
F 0 "SW7" H 6600 6225 50  0000 C CNN
F 1 "BTN_B" H 6625 6475 50  0000 C CNN
F 2 "" H 6625 6500 50  0001 C CNN
F 3 "" H 6625 6500 50  0001 C CNN
	1    6625 6300
	1    0    0    -1  
$EndComp
$Comp
L switches:SW_Push_Dual_x2 SW8
U 1 1 5CCAE86E
P 7825 6300
F 0 "SW8" H 7825 6225 50  0000 C CNN
F 1 "RIGHT" H 7825 6475 50  0000 C CNN
F 2 "" H 7825 6500 50  0001 C CNN
F 3 "" H 7825 6500 50  0001 C CNN
	1    7825 6300
	1    0    0    -1  
$EndComp
Text Label 6425 5950 2    50   ~ 0
RA4
Text Label 8025 5125 0    50   ~ 0
RA4
Text Label 8025 5950 0    50   ~ 0
RC4
Text Label 7325 5950 2    50   ~ 0
RC5
Wire Wire Line
	7325 6300 7325 5950
Wire Wire Line
	8025 6300 8025 5950
Wire Wire Line
	7125 5950 7325 5950
Connection ~ 7325 5950
Wire Wire Line
	7125 6300 7325 6300
Connection ~ 7325 6300
Wire Wire Line
	6425 5950 6425 6300
Wire Wire Line
	8025 5125 8025 5475
Wire Wire Line
	7325 5125 7325 5475
Text Label 7325 5125 2    50   ~ 0
RC4
Text Label 5250 4500 2    39   ~ 0
RA4
Text Label 5250 4700 2    39   ~ 0
RC5
$Comp
L device:R R2
U 1 1 5CCB4511
P 6150 2000
F 0 "R2" V 6050 2000 50  0000 C CNN
F 1 "1k" V 6150 2000 50  0000 C CNN
F 2 "" V 6080 2000 50  0001 C CNN
F 3 "" H 6150 2000 50  0001 C CNN
	1    6150 2000
	0    -1   -1   0   
$EndComp
Wire Wire Line
	6300 2000 6300 2300
Connection ~ 6300 2300
Wire Wire Line
	6300 2300 6300 2525
Wire Wire Line
	5425 2000 6000 2000
Text Label 5250 4800 2    39   ~ 0
RC4
$Comp
L device:C C7
U 1 1 5CCB96D2
P 2650 4150
F 0 "C7" H 2765 4196 50  0000 L CNN
F 1 "100n" H 2765 4105 50  0000 L CNN
F 2 "" H 2688 4000 50  0001 C CNN
F 3 "" H 2650 4150 50  0001 C CNN
	1    2650 4150
	1    0    0    -1  
$EndComp
Wire Wire Line
	2650 4000 3300 4000
Wire Wire Line
	3300 3900 3300 4000
Connection ~ 3300 4000
Wire Wire Line
	3300 4000 3300 4100
$Comp
L power:GND #PWR010
U 1 1 5CCBA9C9
P 2650 4300
F 0 "#PWR010" H 2650 4050 50  0001 C CNN
F 1 "GND" H 2655 4127 50  0000 C CNN
F 2 "" H 2650 4300 50  0001 C CNN
F 3 "" H 2650 4300 50  0001 C CNN
	1    2650 4300
	1    0    0    -1  
$EndComp
$EndSCHEMATC
