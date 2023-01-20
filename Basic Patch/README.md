# CoCo Am9511 Pak BASIC Patch for Tandy Color Computer 3

## Description

This code will patch CoCo3's Super Extended Basic to use the CoCo Am9511 Pak (open source hardware design available at https://github.com/barberd/coco9511pak) and its Arithmetic Processing Unit for several of its float functions, including: \*, /, ^, SIN, ATN, COS, TAN, EXP, FIX, LOG, and SQR.
Additionally, four new functions have been added: ACOS, ARCSIN, LG10, and APUPI.

## How to use

Load the bas9511.dsk via Coco SDC, DriveWire, or [write it to floppy](https://nitros9.sourceforge.io/wiki/index.php/Transferring_DSK_Images_to_Floppies). Once the disk is loaded into your CoCo, load the executable with

	LOADM"BAS9511" <enter>

and then execute it with

	EXEC <enter>

This will load the patch.

## Source and License

Source maintained at [https://github.com/barberd/coco9511pak/](https://github.com/barberd/coco9511pak/).

The code is copyright 2023 by Don Barber. The software is open source, distributed via the GNU GPL version 3 license. Please see the COPYING file for details.

## Why

The 6809 processor used on the Color Computer does not have hardware support for floating point operations, and only has arithmetic functions for 8 and 16 bit addition, 8 and 16 bit subtraction, and 8 bit multiply. Division, exponentiation, trigonometric functions, square root, and logarithms are done in software.

Performing these tasks in software can be time intensive. As such, arithmetic processing units such as the Am9511 can be interfaced to the computer to offload these tasks, speeding up processing.

By patching BASIC to use the CoCo Am9511 pak, developers and operators can access the additional speed of the Am9511 with no change to their existing BASIC programs.

Additionally, the patch includes 4 new functions not present. These are arccos (ACOS), arcsin (ARCSIN), base 10 log (LG10), and pi (APUPI).

## Tradeoffs

Color Computer BASIC uses the [Microsoft Binary Format](https://en.wikipedia.org/wiki/Microsoft_Binary_Format), using 5 bytes to store floating point numbers. This gives 32 bits (or approximately 9 decimal digits) of precision. An 8 bit exponent is used, meaning the approximate range is from 2\*\*-128 to 2\*\*127.

Conversely, the Am9511 uses 4 bytes to store floating point numbers. It uses 24 bits (or approximately 7 decimal digits) of precision, and a 7 bit exponent, giving an approximate range from 2\*\*-64 to 2\*\*63.

So, the native software format provides more precision and greater range, but is also slower. The Am9511 has less precision and range, but is still good enough for almost all use cases, and is much faster.

Use of a number in BASIC that does not fit within the Am9511's range results in an OV (overflow) error when sending an operation to the Am9511. Time is also spent in converting values between systems when writing to or reading from the Am9511, but this overhead is dwarfed by the time saved by the APU processing.

## Implementation Choices

The base IO address for accessing the Am9511 is $FF70. If a different IO address is desired, the patch will need to be modified and reassembled.

ARCSIN was used for arcsin instead of ASIN as this conflicts with the 'AS' token used in Disk BASIC.

LG10 was used for base 10 log instead of LOG10 as this conflicts with the 'LOG' token used for natural logarithms.

APUPI was used for returning pi instead of PI as many programmers choose to use a variable called PI to store the value of pi, and this would slow down the program with constant hardware calls to the Am9511 APU.

In the event the chip returns an underflow, the number returned is simply rounded down to 0 instead of returning an error; this is the same behavior as BASIC.

## Color Computer 3 Only?

Simply put, I wrote this for the CoCo 3 as thats what I have. But it should be possible to modify for the CoCo 1 or 2.

The CoCo3 runs in RAM mode by default, meaning that the BASIC ROM is copied into RAM where it can be patched. The CoCo 1 and 2 keep it in ROM, so it can not be modified. However, on the CoCo 2, one can write a program to copy the ROM to RAM and put it in RAM mode. Evidently its also possible on the CoCo 1, but might require some creative re-addressing as it would require moving the contents of the ROM down into RAM. If this is done, conceptually the CoCo 1 and 2 could also be patched.

Also, the rentry points in the AMLINK2, AMLINK3, and AMLINK5 routines currently point into the Super Extended BASIC area; these would need to be updated to point back into the Color BASIC / Extended BASIC ROMs instead. Alternatively, these patches can be ignored, but one will not have the new ACOS, ARCSIN, LG10, or APUPI functions.

## Ideas for the Future

Make CoCo 1 and CoCo 2 patches.

Modify the entire BASIC ROM so the APU floating point format is used internal to BASIC, so conversion to and from the APU is not needed.

Do some tests to see if it also makes sense to perform addition and subtraction on the Am9511. Assumption is that multi-byte addition and subtraction in software is still faster when including the overhead required in communicating with the Am9511, as this is generally the case on other machines, but this has not been tested empirically.

