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
- Bootable disks: `'OS'` at LSN 2 (track 0, sector 3); `BOOT` then loads
  sectors 3-18 of track 0 to `$2600` and jumps `$2602` (R, Kinns
  spec). Not the same thing as an autostart cartridge.

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

## RSDOS / DECB (Tandy CoCo disks)

Layout per the canonical Kinns spec (dragon32.info `info/tandydsk.txt`,
which credits Eric Hall's Dragon User May-1988 article and the NDUG
notebook) (R), cross-implementer checked against `decb.py` here and
ToolShed/MAME imgtool (R), and spot-verified on a fresh image (V):

- Geometry: 35 tracks (0-34), 1 side, 18 sectors of 256 bytes;
  `decb.py dskini -3/-4/-8` covers 35/40/80 tracks.
- Granule = 9 sectors (2304 bytes), the allocation unit. Granule
  numbering is zero-based and **skips the directory track**: granule 0 =
  track 0 sectors 1-9; granule 33 = track 16 s10-18; granule 34 = track
  18 s1-9. 35T disks have 68 granules (70 minus the track 17 pair).
- Directory on track 17; **sector 2 = granule map (GAT)**, sectors 3-11
  = 72 directory entries of 32 bytes (8 per sector, 9 sectors).
  Sectors 1 and 12-18 of the track are unused (the spec presumes;
  `dskini`/imgtool leave their 0xFF fill, ToolShed zeroes some).
- GAT byte per granule: `0x00-0x43` = next granule in the chain;
  `0xC0+` = last granule, low bits = sectors used in the last granule
  (spec says bits 3-0; `decb.py` masks `0x3F`); `0xFF` = free. Other
  values = corrupt or a stray fill.
- Directory entry (32 bytes): `[0:8]` name, `[8:11]` extension, both
  space padded; `[11]` type: 0 = Basic, 1 = Basic data, 2 = machine
  code, 3 = text; `[12]` ASCII flag (`0xFF` ASCII / `0x00` binary);
  `[13]` first granule; `[14:15]` bytes used in last sector, big-
  endian, `0x0100` = full sector; `[16:31]` unused. Byte 0 `0xFF`/
  `0x00` mark a free/deleted slot (fresh disks are all 0xFF).
- File payloads: tokenised BASIC = `0xFF`, BE length, token stream;
  ML = header `0x00`, BE length, BE load address; tail `0xFF`, `0x0000`,
  BE exec address; segmented files repeat the header per segment.
- Bootable: `'OS'` on **track 34** (granule 66) and boot code near
  granule 32 (track 16 s1) -- the *last* track, unlike DragonDOS's
  LSN 2. RSDOS tokens differ from Dragon's (DIR is `0xCE` on both; SAVE
  `0xD8`, LOAD `0xD3`, DSKINI `0xDC` here; see AGENT-NOTES token
  bullet).

Spot-verified (V) with `decb.py dskini` + `copy` on a 256-byte binary:
GAT byte 0 = `0xC1` (chain terminator, 1 sector in granule 0), and the
entry decodes `DECFILE` type 2 (ML), binary, first granule 0, last-
sector bytes `0x0100` -- everything above lines up. `decb.py dir`/`stat`
read the same numbers back.

The fork's take: `decb.py` is the maintained reader/writer for these
images (it also absorbs JVC headers transparently); XRoar only moves
raw sectors -- the DECB ROM itself implements this file system at
runtime. Do not cross-feed DECB and DragonDOS images.

## Raw vs JVC disk images

`.dsk` raw image = bare sectors, size implies geometry. JVC (Jeff
Vavasour CoCo disk image) is raw sectors plus a short *geometry header*
-- not per-sector markers (that was wrong in earlier drafts). The spec
(R, Tim Lindner's page, tlindner.macmess.org/?page_id=86):

- header length = `fileLength % 256`, so 0..255 bytes; contents:
  sectors-per-track (default 18), side count (1), sector-size code
  (`0x00`=128 `0x01`=256 `0x02`=512 `0x03`=1024), first sector ID (1),
  sector-attribute flag (0). Missing/too-short => defaults.
- tracks = (fileLength-header)/spt/(128<<code)/sides; two sides are
  interleaved per track (T0S1, T0S2, T1S1, ...).
- If the attribute flag is set, each sector gains one prepended byte
  (the WD179x Read-Sector status: deleted-data bit, not-found, CRC).
- Vavasour's CoCo3 emulator reads headers up to 255 bytes; his CoCo2
  emulator only length 0.

- `-load-fdX` routes by filename (R, xroar.c): `.vdk` -> VDK loader,
  `.jvc` **and `.dsk`** -> the JVC loader, `.os9`/`.dmk` their own. So a
  `.dsk` is JVC-loader territory: with a size that is a multiple of 256
  it is raw; otherwise it carries the optional variable-length geometry
  header above. XRoar's own `.dsk` writer emits the header only when
  needed, keeping images payload-compatible (R, `vdisk.c`).
- Endianness note: the spec page says `fileLength % 256`, XRoar's
  reader computes `file_size % 128` (vdisk.c). They agree for headers
  under 128 bytes -- headers 128..255 (legal per Vavasour's emulator)
  are misread by XRoar. The retrotools writer's 5-byte header
  validates both. Worth knowing before importing exotic JVCs.

## VDK (Dragon virtual disk)

Magic `dk` at 0; the *declared total* header length at bytes`[2..3]`
little-endian, so lengths vary by file: a short VDK is exactly the
12-byte core, and 256-byte headers (core + name/extra block) are common
in the wild (R, PC-Dragon II spec as carried in XRoar's `vdisk.c`):

- `[0..1]` `dk`; `[2..3]` header length (LE, >= 12); `[4]` VDK version;
  `[5]` backwards-compat version; `[6]` source identity (`P` PC-Dragon,
  `X` XRoar); `[7]` source version; `[8]` cylinders; `[9]` heads;
  `[10]` flags (bit 0 = write-protect); `[11]` compression (bits 0-2),
  disk-name length (bits 3-7). Sectors follow the header.
- XRoar rejects compressed VDKs and a VDK version above 0x10; it stores
  and rewrites all extra header bytes verbatim.

Verified here (V): retrotools `dragondos new t.vdk 180` writes
`64 6b 0c 00 10 10 50 26 28 01 00 00` = `dk`, length 12, version 0x10,
source `P`, 40 cyls, 1 head, no protection, no name -- 184,332 bytes =
184,320 + the 12-byte short header. A raw .dsk of the same contents
differs from it only by that header; the payload after the header is
the same sector run.
## OS-9 disk images

An OS-9 image is a **headerless, image-only .dsk** -- the same raw
sector payload as a JVC-with-zero-header file, with no geometry header
of any kind. The geometry is read out of LSN0's OS-9 DD map when the
image is loaded (R, `vdisk.c do_load_jvc`): `dd_tot` (3 bytes),
`dd_tks`, `dd_fmt` (sides = (fmt&1)+1), `dd_spt`; if
`dd_tot*256 >= filesize && dd_tks == dd_spt > 0` the geometry is taken
from there. A `.os9` filename forces this check even when
auto-detection is disabled (`-no-disk-auto-os9`).

## DMK (David Keil's disk format)

Preserves more of the raw floppy than VDK/JVC -- this is where "real
sector headers and deleted marks" live, not in JVC. 16-byte header (R,
`vdisk.c`, itself from the DMK spec): `[0]` write protect (`$00`/`$FF`;
XRoar treats `$FF` as write-back-off), `[1]` cylinders, `[2..3]` track
length incl. IDAM table (LE, valid 0x0cc0..0x2940), `[4]` flags (bit 4
single-sided, bit 6 single-density-only, bit 7 mixed; 6/7 ignored),
`[5..11]` reserved, `[12..15]` must be 0 (`0x12345678` flags a real
drive, unsupported). Each track then = a 64-entry table of 16-bit LE
IDAM offsets (relative to track start, table included) + raw track
data. SD/DD is per track, so both densities fit in one image.

## Cartridge / ROM images

`.ccc`, `.cco`, `.dgn`, `.bin`, `.rom` all map to ROM loads (R,
xroar.c filetypes) and `cart.c` reads them as raw ROM bytes -- no
container header is parsed. The DragonDOS cart is an 8K ROM in this
slot; `bin/lwasm` rebuilds it byte-identically. If a community `.ccc`
with a 257-byte container header shows up somewhere, XRoar is not the
reader for it.

## Snapshots

`.sn` is XRoar's serialised state: tag `0x23` + the literal text
header `/usr/bin/env xroar\n# 6809.org.uk\n`, then a tagged stream of
machine/parts/vdrive regions (R, `snapshot.c`). The fork's
`-trap-ram` dumps are a deliberately simpler, script-verifiable
excuse for state capture; nothing here writes `.sn` yet.

## Tape: CAS / C10 / K7 / WAV

All four extensions reach the tape layer (R, tape.c): `.cas` is the
form this fork uses (see the CAS section), `.c10` the CoCo's raw
cassette, `.k7`/`.wav` other containers. The ROM is the decoder; a
tape that CLOADs is correct.

## S19 / HEX, and what XRoar *doesn't* read

`lwasm` can emit `.s19`; XRoar loads S19/HEX/ihex as ROM images
(non-tokenised, address-tagged ASCII -- not a media format worth more
than this line). EDSK and IMD are *not* read by XRoar; the cobbled
`dragondos` factory understands them, so use it as a converter when a
preservation site ships those.

## Fork-native formats (pointers)

`gensym`'s `.sym`/`.lines` pair and the `-audit` access map are this
fork's own files; both are specified in tools/README.md (gensym/
symread/auditreport), not here, because they are not emulated-media
formats. Formats that genuinely lack a section (WAV audio details, a
community `.ccc` container) get one here when something needs it;
write the claim with its R source, then test it against the machine so
it can be re-tagged V.