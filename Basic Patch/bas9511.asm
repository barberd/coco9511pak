; AM9511 Patch for Tandy Color Computer 3's Super Extended Basic
; By Don Barber, Copyright 2023
; Distributed at https://github.com/barberd/coco9511pak

; This code will patch Super Extended Basic to use the AMD 9511 
; Arithmetic Processing Unit for several of its float functions, including: 
; *, /, ^, SIN, ATN, COS, TAN, EXP, FIX, LOG, and SQR.
; Additionally, four new functions have been added: ACOS, ARCSIN, LG10, and APUPI.

; A CoCo 9511 Pak is required; see the distribution ; URL above for 
; the hardware design files.

; This patch is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

; This patch is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

; You should have received a copy of the GNU General Public License along with this patch. If not, see <https://www.gnu.org/licenses/>.

; Color Basic Floating Point Format
;Unpacked (FPA) 6 bytes
;  8 bits exponent, $80 biased.
;  32 bits mantissa
;  8 bit sign ($00 or $FF)
;Packed 5 bytes
;  8 bits exponent, $80 biased.
;  32 bits mantissa
;  bit 7 of the MSB of the mantissa is the sign.
;  when 'unpacking' always set this to '1' as it was always normalized to 1
;  before packing and then overwritten with the sign bit.

;AM9511 format
;  1 bit sign
;  7 bit exponent - unbiased 2's complement
;  24 bits mantissa

APUDR           EQU     $FF70           AM9511A Data Register   - store in APURR
APUSR           EQU     $FF71           AM9511A Status Register - store in APURR
APUCR           EQU     APUSR           AM9511A Command Register
APURR		EQU	$FF72		Real read register

OVERROR	SET	$BA92

FP0EXP	SET	$004F
FPA0	SET	$0050
FP0SGN	SET	$0054
FP1EXP	SET	$005C
FPA1	SET	$005D
FP1SGN	SET	$0061

V41	SET	$0041
V42	SET	$0042

PATCH2	SET	$B8D4
PATCH3	SET	$B7F3
PATCH5	SET	$816C

TXTTAB	SET	$0019
COMVEC	SET	$0120

		org	$2600		; Standard TXTTAB basic program 
					; location on coco3. Will update TXTTAB
					; to make room for this code.

;format FPA to APU
FP0TOAPU	LDX	#FP0EXP
;X is pointer to buffer to convert and send to APU
UNPACKEDTOAPU
		PSHS	A
		TST	,X
		BNE	notzero
makezero:	LDA	#5
zeroloop:	CLR	,X+		Clear all bytes if exp=0
		DECA
		BNE	zeroloop
		BRA	storeinapu
notzero:
		;check if 4th byte bit 7 is 0, then truncate (round down)
		;else round up
		LDA	4,X
		BPL	donemantissa	if 4th byte bit 7 is 0 then
					;truncate (round down) else round up
		LDB	#3
		LEAY	4,X
mantissaloop:	LDA	,-Y
		ADDA	#1
		STA	,Y
		BCC	donemantissa
		DECB
		BNE	mantissaloop
		BCC	donemantissa
		;rounding up's carry rippled all the way up
		;so now need to rotate down all the bytes
		;and increment the exponent - and check that for overflow
		ROR	1,X		Rotate in the carry bit
					;If we are here, then
					;FPA0+1,+2 are already 0
		LDA	,X
		ADDA	#1
		STA	,X
		LBCS	OVERROR		Overflow error
donemantissa:	CLR	4,X		clear last byte of mantissa
		;done with mantissa, now adjust exponent and bring in sign
		;check for exponent > 63 or < -63 then overflow or underflow
		LDA	,X
		CMPA	#$C0
		LBCC	OVERROR		Overflow error
notoverflow	CMPA	#$40
		BCS	makezero	Instead of underflow, make zero
notunderflow		
		;subtract 128 ($80) from exponent (must be 7 bits)
		ASLA			Subtract $80 and set up to rotate 
					;in mantissa sign
		LDB	5,X
		ASLB			set carry bit from sign
		RORA			rotate into mantissa sign
		STA	,X		and store
		;now store into APU
storeinapu:	LDB	#4
storeloop:	LDA	,X+
		STA	APUDR
		DECB
		BNE	storeloop
		PULS	A,PC


APUCOMMAND	STA	APUCR
		#JMP	skip			for debugging, bypass chip
						;this results in returning the
						;same number, but tests the
						;basic float to APU float
						;and back conversion routines
apuwaitloop:	LDA	APUSR
		LDA	APURR
		BMI	apuwaitloop		loop until done
		BITA	#$1E
		BNE	apuerrorhandler
;now down with command so 
;pull float out of APU and format to FPA
		LDB	#4
		LDX	#FP0EXP	
readloop:	LDA	APUDR
		LDA	APURR
		STA	,X+
		DECB
		BNE	readloop
skip:
		;add fourth $00 byte to mantissa
		CLR	FPA0+3
		;test for 0; set exp accordingly
		TST	FPA0
		BNE	amnotzero
		CLR	FP0EXP
		RTS
		;set sign byte to same as bit 7 of exponent byte
amnotzero:	CLR	FP0SGN
		LDA	FP0EXP
		BPL	donemsign
		COM	FP0SGN
		;add 128 ($80) to exponent
donemsign:	ANDA	#$7F		;convert exponent
		CMPA	#$40
		BCC	nobias		Add $80 if positive
		ORA	#$80
nobias:		STA	FP0EXP	
		RTS
apuerrorhandler:
		BITA	#$02		XX01 error
		LBNE	OVERROR		OV ERROR
		BITA	#$10		1000 error
		LBNE	$BC06		/0 ERROR
		BITA	#$08		0100 error
		LBNE	$B44A		FC ERROR (sqr of negative)
		BITA	#$18		1100 error
		LBNE	$BA92		OV ERROR
		;underflow is only error left
		;so just round down to 0 and return
		LDX	#FP0EXP
		LDA	#5
errzeroloop:	CLR	,X+		Clear all bytes if exp=0
		DECA
		BNE	errzeroloop
		RTS

APUFUNCTION
		LBSR	FP0TOAPU
		BRA	APUCOMMAND

SQR		LDA	#$01
		BRA	APUFUNCTION
SIN		LDA	#$02
		BRA	APUFUNCTION
COS		LDA	#$03
		BRA	APUFUNCTION
TAN		LDA	#$04
		BRA	APUFUNCTION
ASIN		LDA	#$05
		BRA	APUFUNCTION
ACOS		LDA	#$06
		BRA	APUFUNCTION
ATAN		LDA	#$07
		BRA	APUFUNCTION
LOG10		LDA	#$08
		BRA	APUFUNCTION
LOG		LDA	#$09
		BRA	APUFUNCTION
EXP		LDA	#$0A
		BRA	APUFUNCTION

PWR		LDA	#$0B			issue PWR command
		BRA	sendtwovars

PI		LDA	#$1A
		LBRA	APUCOMMAND

MUL		LDA	#$12			issue FMUL commmand
		BRA	sendtwovars
		
DIV		LDA	#$13			issue FDIV commmand
sendtwovars:	LDX	#FP1EXP			first exponent base 
		LBSR	UNPACKEDTOAPU
		BRA	APUFUNCTION

FIX		LDA	#$1E			FIXD command to
		LBSR	FP0TOAPU                convert to 32-bit fixed point
		STA	APUCR
fixwaitloop:	LDA	APUSR
		LDA	APURR
		BMI	fixwaitloop		loop until done
		LDA	#$1C                    FLTD command to convert
		LBRA	APUCOMMAND              back to float and return
		
#Patch into crunch/uncrunch/process same as super extended basic patch 2 and 3, and 5. See ALINK2 ALINK3 and ALINK5 in Super Extended Basic Unravelled

;crunches into tokens
AMLINK2:	TST	V41
		BEQ	alink2dest		not a function, move on
alink2token:	LDA	V42
		CMPA	#$29
		BLS	alink2dest		if super extended, move on
		CMPA	#$2E
		BHI	alink2dest		if already done, move on
		LDA	#$2E
		LDU	#amfunctiontable-10
		STA	V42
		JMP	$B89D			go process command table
alink2dest:	JMP	$E138

;uncrunch tokens
AMLINK3:	LEAU	10,U
		TST	,U
		LBNE	$B7F9			;if table has more, go back
		LDA	-1,X
		ANDA	#$7F
		CMPA	#$2E			if below AM tokens
		LBLO	$E180			then jump to super extended
		CMPA	#$31			if above AM tokens
		LBHI	$E180			then also jump to super extended
		SUBA	#$2E			this is a AM token
		LDU	#amfunctiontable-10	so process with this table
		BRA	AMLINK3

;process found tokens
AMLINK5:	CMPB	#2*46
		BCS	alink5dest
		CMPB	#2*49
		BLS	alink5cont
alink5dest:	JMP	$E1A6
alink5cont:	SUBB	#2*46
		CMPB	#2*3		; process paren expression
		BCC	alink5noparen   ; if ACOS, ASIN, LOG10
		PSHS	B               ; PI goes straight through
		JSR	$B262
		PULS	B
alink5noparen:	LDX	#amjumptable
		JMP	$B2CE

;function vector table
amfunctiontable:FCB	4
		FDB	amlookuptable
		FDB	AMLINK5
		FCB	$00,$00,$00,$00,$00,$00		dummy space

amlookuptable:	FCS	'ACOS'
		FCS	'ARCSIN'	; AS token in disk basic conflicts ASIN
		FCS	'LG10'		; LOG token in extended basic conflicts
		FCS	'APUPI'		; Calling this APU PI instead of just PI
					; as many programs use PI as a variable
					; name and it would slow things down
					; to always fetch it from the APU
					; instead of just setting it once

amjumptable:	FDB	ACOS		AE
		FDB	ASIN		AF
		FDB	LOG10		B0
		FDB	PI		B1

start:
		STA	$FFDF		make sure coco3 is in RAM mode

		;patch super extended basic for new secondary functions
		;ACOS,ASIN,LOG10, and PI.
		LDA	#$7E		change LDUs to JMP
		STA	PATCH2
		STA	PATCH3
		LDD	#AMLINK2		patch crunch routine
		STD	PATCH2+1
		LDD	#AMLINK3		patch uncrunch routine
		STD	PATCH3+1
		LDD	#AMLINK5		patch secondary command handler
		STD	PATCH5+1

		;replace color basic jump table for *, /, sin
		LDD	#MUL
		STD	$AA58
		LDD	#DIV
		STD	$AA5B
		LDD	#SIN
		STD	$AA33
		;replace 'expjmp' destination to new AM9511 function
		LDD	#PWR
		STD	$011E
		;replace extended basic jump table entries for functions
		LDX	#$8257
		LDD	#ATAN
		STD	,X++
		LDD	#COS
		STD	,X++
		LDD	#TAN
		STD	,X++
		LDD	#EXP
		STD	,X++
		LDD	#FIX
		STD	,X++
		LDD	#LOG
		STD	,X++
		LDD	#SQR
		STD	,X

		;set new basic location to start at this code's initialization
		;routine since thats no longer needed
		LDX	#start+1
		STX	TXTTAB		new beginning of basic program area
		JMP	$96EC		clear vars and do a NEW

		end	start

