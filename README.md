# CoCo AM9511 Pak

## Description

This board is a cartridge for the Tandy Radio Shack TRS-80 Color Computer (CoCo), an 8 bit computer produced between 1980 and 1991. It provides an Arithmetic Processor Unit (APU), the AMD 9511, to the CoCo.

Note the specific component values for C16, R2, and X1 on the board's markings and the bill of materials is for the AM9511-4DC; see below if you have a different chip.

Schematic is available [here](kicad/coco9511pak.pdf).

A software patch for the Color Computer 3's BASIC can be found in the [Basic Patch](Basic%20Patch/) directory.

## How to order for fabrication

Download [kicad/coco9511pak-fabrication.zip](coco9511pak-fabrication.zip), then upload it to your PCB manufacturer of choice when asked to provide Gerber files. Usually this is found under a 'Quote' option on the website. Search "pcb manufacturing" on any major search engine to get several manufacturers.

Some may have ordered boards and have extra available. Reach out to don &#x40; dgb3.net to explore this.

## Source and License

Design maintained at [https://github.com/barberd/coco9511pak](https://github.com/barberd/coco9511pak). [Kicad](https://www.kicad.org/) and [Freerouting](https://github.com/freerouting/freerouting/) were used to design the board.

The design is copyright 2023 by Don Barber. The design is open source, distributed via the GNU GPL version 3 license. Please see the COPYING file for details.

## Why

The AM9511 chip provides 16 bit and 32 bit fixed point and 32 bit floating point arithmetic, including ADD, SUB, MUL, DIV, SIN, COS, TAN, ASIN, ACOS, ATAN, EXP, PWR, SQRT, LN, and supporting functions (such as fixed to float conversions). Such functions are often slower for 8 bit processors to calculate, so developers can offload such processing to the AM9511, where it can be done faster. Additionally, the main CPU may continue to do other activities while the APU works in parallel.

For example, a hardware floating point divide can take up to 184 clock cycles (92,000 nanoseconds at 2 Mhz) on the AM9511, but may take over 13,000 cycles (6.5 milliseconds or 6,500,000 nanoseconds at 2Mhz) using just the CPU using a floating point library, making the AM9511 about 70x faster even at the same clock rate. Additionally, a 4 Mhz clock can be used on the AM9511-4DC, making it even faster than many 8-bit CPUs.

This is often used for technical or scientific uses where very fast arithmetic is desirable. For example, see [NASA Technical Memorandum TM-86517](https://archive.org/details/NASA_NTRS_Archive_19850026198/page/n1/mode/2up) from July 1985 for a description on how NASA used these chips for controlling structural vibrations, and needed all the computations done within 20ms. They actually put four AM9511s in parallel! (Note there is a bug in Figure 6 on page 15; the 'BCS BA4' should be 'BCC BA4'.)

### More on the APU

Intel licensed the AM9511 design and produced it as the 8231. AMD also produced the 9512, which is pin compatible and provides 64 bit arithmetic, but only supports ADD, SUB, MUL, and DIV. The AM9512 was also licensed by Intel as the 8232. This pak should support all of them.

The APU may also be referred to as a floating-point unit (FPU) or a math coprocessor. The latter is a misnomer however; math coprocessors work in tandem with a CPU by extending the instruction set, such as the 387 for the Intel 386 CPU or the MC68882 for the 68k CPU. The AM9511 is better thought of as an IO peripheral, in that software instructs the CPU to output data and commands to it, then inputs the results later.

## Using the Board

Set the 6 dip switches (SW1) for the desired base IO address. These correspond to address lines A2 through A7. The default is $FF70 (switches set to 011100), which generally should not have a conflict unless you have a Glenside IDE Controller using its second jumper option. See [here](https://www.cocopedia.com/wiki/index.php/External_Hardware_IO_Address_Map) for choosing an IO address.

The four addresses used correspond to different registers on the Am9511 and board. For example, if given base address of $FF70:

  * $FF70 Data Register (Read and Write)
  * $FF71 Command Register (Write) and Status Register (Read)
  * $FF72 Latch Register (Read)
  * $FF73 Mirror of Latch Register

Read the [AM9511 Datasheet](docs/9511%20Datasheet.pdf), [Algorithm Details for the Am9511 Arithmetic Processing Unit](docs/The%20Am9511%20Arithmetic%20Processing%20Unit.pdf), and the [Am9511A/Am9512 Floating Point Processor Manual](docs/Am9511A-9512FP_Processor_Manual.pdf) for how to use the chip. The only adjustment for this board is that instead of reading directly from the chip, a two-step read is needed. The first will read the data into a latch, and a second read will load the real data into the CPU. See the Implementation Details below for information on why this is needed.

For example, to perform a float multiply:

	 	LDX	#fpbuf1			Floating Point Buffer 1
		LDY	#fpbuf2			Floating Point Buffer 2
		LDY	#result			Result Buffer
		LDB	#4
	loop1	LDA	,X+			Store Buffer 1 contents into chip
		STA	$FF70
		DECB
		BNE	loop1	
		LDB	#4
	loop2	LDA	,Y+			Store Buffer 2 contents into chip
		STA	$FF70
		DECB
		BNE	loop2
		LDA	#$12			Load in FMUL instruction
		STA	$FF71			and sent to chip's command register
	loop3	LDA	$FF71			Read from status register into latch
					;CPU will halt here until data is read
		LDA	$FF72			Now read from latch
		BMI	loop3			If bit 7 (Busy) is high, then loop
		LDB	#4
	loop4	LDA	$FF70			Read result into latch
		LDA	$FF72			Read from latch
		STA	,U+			Store into result buffer
		DECB
		BNE	loop4
	

## Implementation Details

Interfacing the AM9511 to the Color Computer is tricky. The AM9511 has a long read time; even on the fastest 4Mhz AM9511-4DC the time can range from 925ns to 1575ns. The standard AM9511, assuming its running at its fastest 2Mhz, can take from 1730ns to 2840ns. A standard Color Computer running at .89 Mhz has a clock cycle of 1117ns, with the needed lines only valid for about 800ns of that. On a Color Computer 3 with the double speed poke, this becomes only 400ns. As such, the AM9511 read time is longer than the CoCo listens for a response.

This problem of the AM9511 read time taking longer than a CPU clock cycle is not unique to the Color Computer (a CPU would have to be running at about 0.3Mhz to ensure an AM9511 read fits into a clock cycle, and CPUs were already faster than this when it came out). To account for this, many 8 bit CPUs either have a READY line available for peripherals to hold the CPU in the middle of an instruction (the 8080, Z80, and 6502 CPUs for example), or there is another way to pause the CPU's clock (using a 6871A clock chip with a 6800 for example). However, neither is available on the Color Computer, at least not without hardware modification.

As such, this pak uses a 74ls374 latch register at a third IO address to store read data coming from the AM9511. Software reading from the chip needs to perform two instructions: one to instruct the AM9511 to copy its data to that register, and another for the CPU to load from the register. The CPU HALT line is used to pause the CPU at the end of the first instruction until the transfer is complete, so the data is always ready in time for the second instruction.

For example, to load pi onto the AM9511's data stack followed by a check of the status register:

	 	LDA	#$1A	Command the am9511 to load pi
		STA	$FF71	Store into the command register
		LDA	$FF71	Load the status register into the latch register
		; CPU halts here until the data is loaded into the latch
		; The above 'LDA' pulls in junk data, just ignore it and use the below
		; 'LDA' to pull in the real data
		LDA	$FF72	Load the actual status result from the latch register into CPU 'A' register
		; Now go on to load the data out of the data registers
		LDX	#outputbuffer
		LDB	#4
	loop	LDA	$FF70	Read from data register into latch
		LDA	$FF72	Then read the real data	
		STA	,X+	And store it into the buffer
		DECB
		BNE	loop


This 'two instructions to read' method may not be the most elegant for those used to programming the AM9511 on an 8080, but was necessary due to the timing considerations discussed above. An alternative, if one wants to design their own board, is to use a PIA, discussed below.

Additionally, when doing a write, the AM9511-4 and AM9511-1 needs the write line to complete 30ns (60ns for the AM9511) before the chip select is finished. Since both signals are normally derived from the same clock on the Color Computer, they normally finish at the same time. As such, a one-shot multivibrator 74LS123 is used; the write signal triggers the one shot that provides the needed 100ns pulse (150ns on the AM9511), leaving enough time in the clock cycle to meet valid data bus and chip select timing requirements.

### But I don't want to HALT the CPU during a read!

A jumper is included on the board design so the HALT behavior can be disabled. If disabled, then the programmer will need to account for the time it takes for chip transfer to complete in software instead by calculating software instruction timing. 

On a 6809 CoCo running at .89 Mhz this is not an issue and the jumper can be removed to disable the HALT behavior; a LD instruction takes three cycles so the time for the two intervening clock cycles between the load cycles of the LD instructions is greater than the required 2840 ns.

However, if the CoCo3 double speed poke is done or the 6809 processor has been replaced with a 6309 processor running in native mode (so LD instructions only take 2 cycles), there might not be enough time for the transfer to complete, and the programmer will need to add in NOP instructions or perform other work to obtain the necessary timing.

## Alternative Implementation Methods

Many implementers avoid the complex bus timing requirements of the am9511 by interfacing it via a Peripherial Interface Adaptor (PIA) or Versatile Interface Adaptor (VIA), such as the Intel 8225, the Motorola 6821, or the MOS 6522. This makes for a much simpler hardware interface with a tradeoff for more complex software, as the software must now 'bit-bang' the individual control lines for the 9511 chip, also taking up additional CPU cycles.

Here are a few examples:

* [Compute! Magazine Nov 1980 Interfacing the Am9511 Arithmetic Processing Unit](https://archive.org/details/1980-11-compute-magazine/page/n123/mode/2up), Page 122

* [NASA Technical Memorandum 91 for calculating magnetic variation, March 1984](https://archive.org/details/NASA_NTRS_Archive_19840012438) No hardware schematic, but does have a block diagram and the software listings

* [S100Computers.com Math Board](http://s100computers.com/My%20System%20Pages/Math%20Board/Math%20Board.htm) This one controls only the C/D line with a PIA, but otherwise is a fairly standard implementation using the 8080/Z80's READY line.

* [Micro! Aug 1981 MICROCRUNCH: An Ultra-fast Arithmetic Computing System](https://archive.org/details/sim_micro_1981-08_39/page/n7), Page 7. This one uses the two flip-flops in a 74LS76 chip to control the R/W\* and C/D\* lines. Part 2 is in [Micro! Sep 1981](https://archive.org/details/sim_micro_1981-09_40/page/82/mode/2up), Page 83. This one uses a 74123 for writing timing much like this board.

## Chip Considerations

The markings on the board and the bill of materials is for the AM9511-4DC running at 4Mhz. If one uses a 2Mhz or 3Mhz AM9511 instead, make these adjustments:

Am9511:
* C16 150pf
* R2 2.2kohm
* X1 2Mhz Oscillator

Am9511-1:
* C16 100pf (no change from board)
* R2 2kohm (no change from board)
* X1 3Mhz Oscillator

For C16 and R2, if you don't have these exact values on hand, one can use a larger capacitor with a smaller resistor (and visa-versa) to get the write timing needed (150ns for Am9511, 100ns for the Am9511-1). See the 74LS123 datasheet and [Texas Instruments Designing With the SN54/74LS123](https://www.ti.com/lit/an/sdla006a/sdla006a.pdf) Page 3 for guidance.

## More Info

Links:

* [Older Datasheet including command details](docs/Am9511%20Arithmetic%20Processor.pdf)
* [New Datasheet with AM9511-4 timings](docs/9511%20Datasheet.pdf)
* [Algorithm Details](docs/The%20Am9511%20Arithmetic%20Processing%20Unit.pdf)
* [Am9511/Am9512 Processor Manual](Am9511A-9512FP_Processor_Manual.pdf) Includes schematics for interfacing to various processors including 8080, Z80, 6800, etc.
* [Color Computer Technical Reference](https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%20Technical%20Reference%20Manual%20%28Tandy%29.pdf) See Page 18 of the manual/25 of the PDF for bus timings.

## Errata

None at this time.


