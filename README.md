# CoCo Am9511 Pak

## Description

This board is a cartridge for the Tandy Radio Shack TRS-80 Color Computer (CoCo), an 8 bit computer produced between 1980 and 1991. It provides an Arithmetic Processor Unit (APU), the AMD 9511, to the CoCo.

![Front View](images/coco9511pak.png?raw=true)

Note the specific component value for X1 on the board's markings and the bill of materials is for the Am9511-4DC; see below if one has a different chip.

Schematic is available [here](kicad/coco9511pak.pdf).

A software patch for the Color Computer 3's BASIC can be found in the [Basic Patch](Basic%20Patch/) directory.

## How to order for fabrication

Download [kicad/coco9511pak-fabrication.zip](kicad/coco9511pak-fabrication.zip), then upload it to one's PCB manufacturer when asked to provide Gerber files. Usually this is found under a 'Quote' option on the website. Search "pcb manufacturing" on any major search engine to get several manufacturers. NextPCB and PCBWay are two well-known ones.

Some may have ordered boards and have extra available. Reach out to don &#x40; dgb3.net to explore this.

Use the [Bill of Materials](kicad/coco9511pak.csv) to source the components from electronic supply houses such as Mouser, Jameco, or Digi-Key.

## Source and License

Design maintained at [https://github.com/barberd/coco9511pak](https://github.com/barberd/coco9511pak). [Kicad](https://www.kicad.org/) and [Freerouting](https://github.com/freerouting/freerouting/) were used to design the board.

The design is copyright 2023 by Don Barber. The design is open source, distributed via the GNU GPL version 3 license. Please see the COPYING file for details.

## Why

The Am9511 chip provides 16 bit and 32 bit fixed point and 32 bit floating point arithmetic, including ADD, SUB, MUL, DIV, SIN, COS, TAN, ASIN, ACOS, ATAN, EXP, PWR, SQRT, LN, and supporting functions (such as fixed to float conversions). Such functions are often slower for 8 bit processors to calculate, so developers can offload such processing to the Am9511, where it can be done faster. Additionally, the main CPU may continue to do other activities while the APU works in parallel.

For example, a hardware floating point divide can take up to 184 clock cycles (92,000 nanoseconds at 2 Mhz) on the Am9511, but may take over 13,000 cycles (6,500,000 nanoseconds at 2 Mhz) using just the CPU, making floating point math on the Am9511 about 70x faster. Additionally, a 4 Mhz clock can be used on the Am9511-4DC, making it even faster.

This is often used for technical or scientific uses where very fast arithmetic is desirable. For example, see [NASA Technical Memorandum TM-86517](https://archive.org/details/NASA_NTRS_Archive_19850026198/page/n1/mode/2up) from July 1985 for a description on how NASA used these chips for controlling structural vibrations, and needed all the computations done within 20ms. They actually put four Am9511s in parallel! (Note the 6502 processor used in that memo has the opposite BCC/BCS behavior compared to the 6809; keep this in mind when reviewing Figure 6 on page 15; the 'BCS BA4' should be 'BCC BA4' when transcoding to the CoCo.)

A quick benchmark executing in [Basic](Basic%20Patch/) that loops over Y=(TAN(ATN(SQR(Y\*Y)))+1)/Y 368 times gets these results:

 * Stock CoCo3: 66.08 seconds
 * CoCo3 with "Poke 65497,0" double speed poke: 32.86 seconds
 * CoCo3 with Am9511-4 and Basic Patches: 5.95 seconds
 * CoCo3 with Am9511-4, Basic Patches, and Double Speek Poke: 3.5 seconds

So, use of the Am9511 results in about 10x speed in floating-point operations when compared to the algorithms in the built-in Basic ROM. Please note this is linear, as the CPU waits for the result while the Am9511 is processing. A program that does other work in parallel could see even faster results.

### More on the APU

Intel licensed the Am9511 design and produced it as the 8231. AMD also produced the 9512, which is pin compatible and provides 64 bit arithmetic, but only supports ADD, SUB, MUL, and DIV. The AM9512 was also licensed by Intel as the 8232. This pak should support all of them.

The APU may also be referred to as a floating-point unit (FPU) or a math coprocessor. The latter is a misnomer however; math coprocessors work in tandem with a CPU by extending the instruction set, such as the 387 for the Intel 386 CPU or the MC68882 for the 68k CPU. The Am9511 is better thought of as an IO peripheral, in that software instructs the CPU to output data and commands to it, then inputs the results later.

## Using the Board

Set the 6 dip switches (SW1) for the desired base IO address. These correspond to address lines A2 through A7. The default is $FF70 (switches set to 011100), which generally should not have a conflict unless one has configured another hardware device with a conflicting IO address. See [here](https://www.cocopedia.com/wiki/index.php/External_Hardware_IO_Address_Map) for a list of known IO hardware addresses.

The four addresses used correspond to different registers on the Am9511 and board. For example, if given base address of $FF70:

  * $FF70 Data Register (Read and Write)
  * $FF71 Command Register (Write) and Status Register (Read)
  * $FF72 Latch Register (Read)
  * $FF73 Mirror of Latch Register

Read the [Am9511 Datasheet](docs/9511%20Datasheet.pdf?raw=true), [Algorithm Details for the Am9511 Arithmetic Processing Unit](docs/The%20Am9511%20Arithmetic%20Processing%20Unit.pdf?raw=true), and the [Am9511A/Am9512 Floating Point Processor Manual](docs/Am9511A-9512FP_Processor_Manual.pdf?raw=true) for how to use the chip. The only adjustment for this board is that instead of reading directly from the chip, a two-step read is needed. The first will read the data into a latch, and a second read will load the real data into the CPU. See the Implementation Details below for information on why this is needed.

For example, to perform a float multiply:

	 	LDX	#fpbuf1+4		End of Floating Point Buffer 1
		LDY	#fpbuf2+4		End of Floating Point Buffer 2
		LDY	#result			Result Buffer
		LDB	#4
	loop1	LDA	,-X			Push Buffer 1 contents into chip
		STA	$FF70
		DECB
		BNE	loop1	
		LDB	#4
	loop2	LDA	,-Y			Push Buffer 2 contents into chip
		STA	$FF70
		DECB
		BNE	loop2
		LDA	#$12			Load in FMUL instruction
		STA	$FF71			and send to chip's command register
		;
		;
		; The software/CPU can now go off to do other things while the
		; APU performs this command. FMUL can take up to 168 cycles.
		; Or one can continue straight to the status check loop and 
		; wait for the APU to finish.
		;
		;
	loop3	LDA	$FF71			Read from status register into latch
		;CPU will halt here until data is read
		LDA	$FF72			Now read from latch
		BMI	loop3			If bit 7 (Busy) is high, then loop
		LDB	#4
	loop4	LDA	$FF70			Pop result from chip into latch
		;CPU will halt here until data is read
		LDA	$FF72			Read from latch
		STA	,U+			Store into result buffer
		DECB
		BNE	loop4
	

## Implementation Details

Interfacing the Am9511 to the Color Computer is tricky. The Am9511 has a long read time; even on the fastest 4Mhz Am9511-4DC the time can range from 925ns to 1575ns. The standard Am9511, assuming its running at its fastest 2Mhz, can take from 1730 ns to 2840 ns. A standard Color Computer running at .89 Mhz has a clock cycle of 1117ns, with the needed lines only valid for 488ns of that. On a Color Computer 3 with the double speed poke, this becomes only 244ns. As such, the Am9511 read time takes longer than the CoCo listens for a response.

This problem of the Am9511 read time taking longer than a CPU clock cycle is not unique to the Color Computer (a CPU would have to be running at about 0.3Mhz to ensure an Am9511 read fits into a clock cycle, and CPUs were already faster than this when it came out). To account for this, many 8 bit CPUs either have a READY line available for peripherals to hold the CPU in the middle of an instruction (the 8080, Z80, and 6502 CPUs for example), or there is another way to pause the CPU's clock (using a 6871A clock chip with a 6800 for example). However, neither is available on the Color Computer, at least not without hardware modification.

As such, this pak uses a 74LS374 latch register accessible at a third IO address to store read data coming from the Am9511. Software reading from the chip needs to perform two instructions: one to instruct the Am9511 to copy its data to that register, and another for the CPU to load from the register. The CPU HALT line is used to pause the CPU at the end of the first load instruction until the transfer is complete, so the data is always ready in time for the second instruction.

For example, to check the status register:

		LDA	$FF71	Load the status register into the latch register
		; CPU halts here until the data is loaded into the latch
		; The above 'LDA' pulls in junk data, just ignore it and use the below
		; 'LDA' to pull in the real data
		LDA	$FF72	Load the actual status result from the latch register into CPU 'A' register

For another example, to pull 4 bytes off the Am9511's data register stack:

		LDX	#outputbuffer
		LDB	#4
	loop	LDA	$FF70	Read from data register into latch
		;CPU will halt here until data is read
		LDA	$FF72	Then read the real data	
		STA	,X+	And store it into the buffer
		DECB
		BNE	loop

This 'two instructions to read' method may not be the most elegant for those used to programming the Am9511 on an 8080, but was necessary due to the timing considerations discussed above. An alternative, if one wants to design their own board, is to use a PIA, discussed below.

Additionally, when doing a write, the Am9511-4 and Am9511-1 needs the write line to complete 30 ns (60 ns for the Am9511) before the chip select is finished. Since both signals are normally derived from the same clock on the Color Computer, they normally finish at the same time. As such, a one-shot multivibrator 74LS123 is used; the write signal triggers the one shot that provides the needed 100 ns pulse (150 ns on the Am9511), leaving enough time in the clock cycle to meet valid data bus and chip select timing requirements. See the below section 'Write Timing' for additional detail.

### But I don't want to HALT the CPU during a read!

Jumper JP1 is included on the board design so the HALT behavior can be disabled. If disabled, then the programmer will need to account for the time it takes for chip transfer to complete instead by calculating software instruction timing. 

On a 6809 CoCo running at .89 Mhz this is not an issue and the jumper can be removed to disable the HALT behavior; a LD instruction takes three cycles so the time for the two intervening clock cycles between the load cycles of the LD instructions is greater than the required 2840 ns.

However, when running without the jumper and the CoCo3 double speed poke or a 6309 processor running in native mode (so LD instructions only take 2 cycles), there might not be enough time for the transfer to complete, and the programmer will need to add in NOP instructions or perform other work to obtain the necessary timing between the two load instructions.

## Alternative Implementation Methods

Many implementers avoid the complex bus timing requirements of the am9511 by interfacing it via a Peripherial Interface Adaptor (PIA) or Versatile Interface Adaptor (VIA), such as the Intel 8225, the Motorola 6821, or the MOS 6522. This makes for a much simpler hardware interface with a tradeoff for more complex software, as the software must now 'bit-bang' the individual control lines for the 9511 chip, also taking up additional CPU cycles.

Here are a few examples:

* [Compute! Magazine Nov 1980 Interfacing the Am9511 Arithmetic Processing Unit](https://archive.org/details/1980-11-compute-magazine/page/n123/mode/2up), Page 122

* [NASA Technical Memorandum 91 for calculating magnetic variation, March 1984](https://archive.org/details/NASA_NTRS_Archive_19840012438) No hardware schematic, but does have a block diagram and the software listings

* [S100Computers.com Math Board](http://s100computers.com/My%20System%20Pages/Math%20Board/Math%20Board.htm) This one controls only the C/D line with a PIA, but otherwise is a fairly standard implementation using the 8080/Z80's READY line.

* [Micro! Aug 1981 MICROCRUNCH: An Ultra-fast Arithmetic Computing System](https://archive.org/details/sim_micro_1981-08_39/page/n7), Page 7. This one uses the two flip-flops in a 74LS76 chip like a PIA to control the R/W\* and C/D\* lines. Part 2 is in [Micro! Sep 1981](https://archive.org/details/sim_micro_1981-09_40/page/82/mode/2up), Page 83. This one uses a 74123 for writing timing much like this board.

## Providing 12 Volts

Use Jumper JP2 to select the source of 12 volts needed for the Am9511.

The original Color Computer and many Multi-Pak Interfaces (MPIs) provide +12v on the second cartridge pin. However, the CoCo 2, Coco 3, and many third-paty MPIs do not provide 12 volts on this pin, so a 5v to 12v boosting circuit is included on the board design. Set JP2 to 'Circuit' to use this circuit.

But if one has a setup that provides +12v to the cartridge and wants to use this source instead, set JP2 to 'Cart.' One can then also eliminate C3, C16, C17, L1, D1, R5, R6, R7, and U3.

## Chip Considerations

The markings on the board and the bill of materials is for the Am9511-4DC running at 4Mhz. If one uses a 2Mhz or 3Mhz Am9511 instead, make these adjustments:

Am9511:
* X1 2Mhz Oscillator

Am9511-1:
* X1 3Mhz Oscillator

## Tuning Write Timing

For C15 and R2, if one doesn't have the exact values on hand, one can use a larger capacitor with a smaller resistor (and visa-versa). One is trying to get the pulse to be long enough to meet the TDW (Data Bus Stable to WR\* High Set up Time) requirement but also short enough to allow the Am9511's TWCD (WR\* High to CS\* High Hold Time) requirement in the remaining CPU clock cycle. The range for the ideal pulse length is between 150 and 184 ns as this gives enough TDW time for the slower Am9511 but also leaves enough remaining TWCD time with the Color Computer's double speed poke. There is more flexibility if one has the Am9511-1 or Am9511-4; a pulse time between 100 and 214 ns will work, and even more flexibility if using the Am9511-1 or Am9511-4 without the double speed poke as the pulse can be anywhere between 100 and 458 ns.

See the 74LS123 datasheet and [Texas Instruments Designing With the SN54/74LS123](https://www.ti.com/lit/an/sdla006a/sdla006a.pdf) Page 3 for guidance on choosing the capacitor and resistor values. If one has a picky AM9511 one might have to check the signal timings with an oscilloscope or logic analyzer and adjust C15 and/or R2.

## More Info

Links:

* [Older Datasheet including command details](docs/Am9511%20Arithmetic%20Processor.pdf?raw=true)
* [New Datasheet with Am9511-4 timings](docs/9511%20Datasheet.pdf?raw=true)
* [Algorithm Details](docs/The%20Am9511%20Arithmetic%20Processing%20Unit.pdf?raw=true)
* [Am9511/Am9512 Processor Manual](docs/Am9511A-9512FP_Processor_Manual.pdf?raw=true) Includes schematics for interfacing to various processors including 8080, Z80, 6800, etc.
* [Color Computer Technical Reference](https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%20Technical%20Reference%20Manual%20%28Tandy%29.pdf) See Page 18 of the manual/25 of the PDF for bus timings.

## Errata

Version 1.0 of the board has several flaws and should not be used.

