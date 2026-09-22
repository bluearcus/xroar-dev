# File formats: the media this emulator moves around

A start, not a reference. Each format is described as far as the fork has
needed it, with the source of every claim tagged: **V** = verified by
running the machine here (write it, read it back, compare), **R** = from
the authoritative source cited, **W** = well-known but not re-derived
here. The extend rule is the same as BASIC-NOTES.md: a claim moves from R
to V by making real files on the machine and reading them back -- an
emulator is the one place a format can be checked without hardware.

## CAS (cassette images)

Structure verified from a 588-byte file written by the Dragon 32's own
`CSAVE` and then `CLOAD`ed back by it (V):

- `0x55` leader, 218 bytes observed
- blocks, each `[0x3C][type][len][payload...][checksum]`:
  - type `0x00` -- filename block (e.g. `"HELLO"` space-padded + NULs)
  - type `0x01` -- data block (the tokenized BASIC program bytes)
  - type `0xFF` -- end of tape, `3C FF 00 FF`
- XRoar appends `[CUE...CUE]` metadata after the tape data (R, XRoar
  `tape_cas.c`)

The machine is the judge: a CAS that `CLOAD`s and `RUN`s is correct, a
layout argument is not.

## DragonDOS disks (Dragon 32/64)

Raw `.dsk` image: 40 cylinders, 1 head, 18 sectors of 256 bytes,
single-sided = 184,320 bytes (V: `[vdisk/jvc] ... 40C 1H 18S`). DSKINIT
fills the surface with `0xE5` sector data (V).

Directory track format, from Dragon Data's DOS 2.C "Additional Info"
(prime6809/DragonDOS `doc/Additional Info.txt`) (R):

- Sector 1 of the directory track: bytes 0-179 = free-block bitmap
  (bit = 1 -> sector free); byte `$FC` = number of tracks; `$FD` =
  sectors per side; `$FE`/`$FF` = their complements.
- FIB (normal) entry: flags byte; 8-char name + 3-char extension, space
  padded; four extent records (16-bit LSN + sector count, 3 bytes each);
  byte `$18` = bytes used in last sector, or link to the next extent
  block when `more extents` is set.
- Extent-block variant: extents at offset 11, `7*3` bytes; bytes `$16$17`
  unused.
- LSN decodes as `track = LSN DIV sectors-per-track`,
  `sector = LSN MOD sectors-per-track`; directory and alternate
  directory tracks are not counted into the LSN.
- Flags byte: bit 0 sector-unit (0 = filename, 1 = extension), bit 1
  protected, bit 3 end-of-dir, bit 5 more extents, bit 7 deleted ("not
  valid"); only bits 1 and 7 are meaningful in a FIB.

Host tooling status: nothing here creates DragonDOS images yet;
`decb.py` is RSDOS-only (see below). The practical route is
`-cart dragondos` + typed `DSKINIT`/`SAVE`/`LOAD`, which is the
`mytests/dragon-disk/` workflow.

## RSDOS / DECB (CoCo disks)

Directory and filing conventions differ from DragonDOS (R, `decb.py` +
XRoar's RSDOS support; not re-derived here). `decb.py` maintains these
images (`dir` / `copy` / `kill`; see tools/README.md). A DragonDOS image
must not be fed to RSDOS tooling and vice versa.

## Raw vs JVC disk images

`.dsk` raw image = bare sectors, size implies geometry. JVC adds a
3-byte per-sector header carrying the marker and addresses, and is what
older amusements encode; `-load-fdX` auto-detects (R, XRoar `vdisk/jvc`).
Nothing about the fork requires knowing the difference by hand.

## Not covered yet

`.sym`/`.lines` (gensym format 1 and 2 -- tools/README.md), snapshots
(`.sna`), tape WAV, `.ccc` cartridge images. Each gets a section here
when something needs it; write the claim with its R source, then test it
against the machine so it can be re-tagged V.