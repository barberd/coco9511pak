; AM9511 Patch for Tandy Color Computer 3's Super Extended Basic
; By Don Barber, Copyright 2023
; Distributed at https://github.com/barberd/coco9511pak

; This code will patch Super Extended Basic to use the AMD 9511 
; Arithmetic Processing Unit for several of its float functions, including: 
; *, /, ^, SIN, ATN, COS, TAN, EXP, LOG, and SQR.
; Additionally, four new functions have been added: ACOS, ARCSIN, LG10, and APUPI.

; A CoCo 9511 Pak is required; see the distribution URL above for 
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

APUDR           EQU     $FF70           AM9511A Data Register   - loads stored in APURR
APUSR           EQU     $FF71           AM9511A Status Register - loads stored in APURR
APUCR           EQU     APUSR           AM9511A Command Register
APURR		EQU	$FF72		Real read register

; Note: Calls to basic errors will reset the stack
; so it is probably ok that we don't clean up before aborting
OVERROR	SET	$BA92
FCERROR	SET	$B44A
DZERROR	SET	$BC06
PIXMASK	SET	$92DD

CHARAC	SET	$0001			; temp location
RSTFLG	SET	$0071

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

COMVEC	SET	$0120

		org	$FB00

;format FPA to APU
FP0TOAPU	LDX	#FP0EXP
;X is pointer to buffer to convert and send to APU
UNPACKEDTOAPU
		PSHS	A
		TST	,X
		BNE	notzero
makezero:	PSHS	X
		LDA	#5
zeroloop:	CLR	,X+		Clear all bytes if exp=0
		DECA
		BNE	zeroloop
		PULS	X
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
		;check for exponent > 63 or < -64 then overflow or underflow
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
storeinapu:	
		LEAX	4,X
		LDB	#4
storeloop:	LDA	,-X
		STA	APUDR
		DECB
		BNE	storeloop
		PULS	A,PC

APUCOMMAND	STA	CHARAC			; save copy of flag (in SR bit) in a scratch location.
		ANDA	#$7F			; strip off SR bit.
sendcmd		STA	APUCR
		#JMP	skip			for debugging, bypass chip
						;this results in returning the
						;same number, but tests the
						;basic float to APU float
						;and back conversion routines
apuwaitloop:	LDA	APUSR
		LDA	APURR
		BMI	apuwaitloop		loop until done
		ANDA	#$1E
		BNE	apuerrorhandler
;now done with command so 
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

		LDA	CHARAC		; check for special case of (-A) ^ X where INT(X) and odd
		BPL	1$		; (zero result is handled above, which we can ignore).
		COM	FP0SGN		; if so, flip resulting sign (from positive to negative).
1$		RTS

apuerrorhandler:
		TFR	A,B
		ANDB	#$06
		CMPB	#$04		;XX10 error (Underflow) - only non-fatal error
		BEQ	retzero
		CMPB	#$02		;XX01 error (Overflow)
		LBEQ	OVERROR
		CMPA	#$10		;1000 error (division by zero)
		LBEQ	DZERROR
		CMPA	#$18		;1100 error (arg too large)
		LBEQ	OVERROR		
		LBRA	FCERROR		;Else 0100 error (sqr of negative) or some undefined value

retzero:	LDX	#FP0EXP		;silently just round down to 0 and return
		LDA	#5
1$		CLR	,X+
		DECA
		BNE	1$
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

PI		LDA	#$1A
		LBRA	APUCOMMAND

MUL		LDA	#$12			issue FMUL commmand
		BRA	sendtwovars
		
DIV		LDA	#$13			issue FDIV commmand
sendtwovars:	LDX	#FP1EXP			first exponent base 
		LBSR	UNPACKEDTOAPU
		BRA	APUFUNCTION

; Compute: A^X, where X -> FP0, A -> FP1
; Equivalent to: e ^ (X * LN(A))
; This won't work when A is 0, or when A < 0 AND X is an integer
; (e.g. 0^X should return 0 and -2 ^ 2  should return 4).
; also, due to special case code, we need to explictly handle when X is 0.
; handle these special cases in a similar way as extended basic
; for compatibility with existing program behaviors.
PWR
		LDA	FP0EXP			; first check if X is 0
		BEQ	EXP			; then return e^0, which should be 1 (for all A).
		LDA	FP1EXP			; check if A is 0, since LN(0) isn't defined.
		BEQ	retzero			; 0^X should be 0, for all X except 0

		LDA	FP1SGN			; if A > 0, we can computer PWR normally.
		BEQ	DOPWR
						; ok, A < 0, now check if X is an integer
						; if X isn't an INT, return FC ERROR (since A < 0)
		LDA	FP0EXP
		SUBA	#$81
		LBCS	FCERROR			; if ABS(X) < 1.0; then return FC ERROR
		CLRB				; clear LSB flag in case we branch
		CMPA	#$20			; if decimal point > 32bits (exp >= $A1) then
		BCC	CHKLSB			; X must be an int (and implicitly even).
						; If exp $A0, then X still is always an int, but we need
						; to check LSB for even/odd.
						; rA now has the bit# of the LSB in the mantissa
						; (e.g. between 0 and 0x1f) counting from MSB to LSB.

						; Convert rA to the offset and masks we
						; need to check if any bits are set in
						; any fractional part (right of the decimal point)
						; in the mantissa.

		TFR	A,B			; save an extra copy of rA in rB

		LDX	#FPA0
		LSRB				; set rX to the byte in the mantissa
		LSRB				; containing the decimal point
		LSRB
		ABX

		ANDA	#$7			; calc mask of bits to the right of decimal pt
		LDU	#PIXMASK		; use 2-color bit mask lookup table
		LDB	A,U
		DECB
		ANDB	,X
		LBNE	FCERROR			; if any bits are 1, then X isn't an int

		LDB	A,U			; get mask of LSB
		ANDB	,X+			; save LSB in rB for later, advance rX to next mant byte

		BRA	2$			; finally, check rest of mantissa (whole bytes) for zero
1$		LDA	,X+
		LBNE	FCERROR			; if any bits are 1, then X isn't an int
2$		CMPX	#FP0SGN
		BNE	1$

; rB should contain saved LSB for the test below.
;
; Now, while we know X is an int, it still may requires > 24 bits.
; We could check FPA0+3 (for zero), and do something
; like return OVERROR...
;
; However, this is likely pointless as an exponent this
; large (positive or negative) will almost certainly
; underflow the result to 0 or overflow.  Even with
; 1^X, LN(1) isn't precisely 0 and any exp (> 31) will
; overflow the APU's precision (1^6e8 for example).
; So to avoid these problems, ignore the fact that
; the integer exponent may get truncated and let apu error
; handler return the right result.  This also avoids
; any potential inconsistency in handling the positive and negative
; argument cases differently.

CHKLSB						; Now check saved odd/even (LSB) to determine final result sign
		CLR	FP1SGN			; First, force A positive before sending to APU
		LDA	#($B|$80)		; if X is odd (rB != 0), need to flip sign back after PWR is computed
						; Hack: use SR bit as a flag since we aren't using it.
		TSTB				; if X is even, no need to restore sign, can just calc PWR
		BNE	sendtwovars		; issue special PWR command and flip sign.
DOPWR
		LDA	#$0B			; issue normal PWR command
		BRA	sendtwovars

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
		CLR	RSTFLG		; due to code in high memory, reset can't recover

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
		LEAX	2,X		skip over FIX
		LDD	#LOG
		STD	,X++
		LEAX	2,X		skip over POS
		LDD	#SQR
		STD	,X
		RTS

		end	start
