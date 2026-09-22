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
(prime6809/DragonDOS `doc/Additional Info.txt`) and the Kinns/Dragon
Data spec (dragon32.info `info/drgndos.txt`) (R); every byte-claim
below also checked on both a ROM-written image and a tool-written one (V):

- Directory track is **track 20, sectors 3-18** carry the directory;
  sectors 1-2 the free-block bitmap + geometry bytes `$FC/$FD` (tracks,
  sectors-per-track, `$FE/$FF` complements). Bit = 1 -> free.
  `LSN 0 = track 0, sector 1`, LSN = T*18+(S-1). The directory track is
  marked used in the bitmap, not skipped in the numbering.
- FIB: flags byte; **name 8 chars + extension 3 chars, NUL-padded**
  (not space-padded); four sector-allocation blocks of
  `[LSN 16-bit][count]`; byte `$18` = bytes used in the last sector
  (`0x00` means 256) or, with bit 5 set, the next entry number.
- **SAB LSNs are big-endian** (6809 `STD` order): the ROM wrote
  `01 44` = 0x0144 = 324 for its TEST.BIN; retrotools wrote `00 08` = 8.
  Little-endian reading of either image gives nonsense (2048 etc.).
- Flags byte: bit 0 = 0 filename-this-block, 1 = continuation block;
  bit 1 protected; bit 3 end-of-dir; bit 5 more extents; bit 7 deleted.
  DSKINIT's empty entries: `0x89` (deleted+end+continuation).

### The 9-byte file header, and directory byte accounting

Every file on disk starts with `55 | filetype | load(2) | len(2) | exec(2) |
AA`, then the payload (R, ddos12.asm `HdrLoad/HdrLen/HdrExec`; V on both
images). Header fields are `.BIN` semantics really: `type 02`, load = S,
`len = end - start` (end-exclusive), exec = X. For `.BAS` (type 01) they
are placeholders -- load "typically $2401", exec = the FC-error routine
($8B8D class) -- which is why the header lives in FORMATS notes but means
something only for .BIN files.

**The byte count includes the header.** The write path keeps the whole-file
length (9-byte header + payload) and copies its LSB into FIB `$18`
(ddos12.asm: `FCBFileLen` accumulation, `STB DirEntLastBytes,U`); the DOS's
DIR shows `(sectors-1)*256 + DirEntLastBytes`. Measured: HELLO.BAS files of
75 payload bytes get `$18 = 84` = 9+75, and DIR prints 84; a 47-byte .BIN
gets `$18 = 56`, DIR prints 56. retrotools' `list` disagrees per type
(.BAS payload-only, .BIN/.DAT with header) -- the tool's quirk, not the
DOS's.

### Host tooling

`tools/dragondos/` (fetch.sh -> `bin/dragondos`) creates, formats, lists
and populates DragonDOS images directly -- `new`/`insertbasic`/
`insertbinary`/`insertdata`/`list`/`info`/`extract`/`delete`. Verified
both ways: it reads the ROM-written `dragon.dsk` and the emulator ran
its images (DIR, LOAD+RUN, PEEK checks). `decb.py` remains RSDOS-only;
do not cross-feed images (see below).

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