# dragondos: host-side DragonDOS disk tool (robcfg/retrotools)

The CLI from [robcfg/retrotools](https://github.com/robcfg/retrotools)
(`dragondos/` subproject, MIT, (c) 2019 robcfg), pinned to commit
`2d5723a` (2025-09-30). It creates, formats, lists, extracts and
populates DragonDOS disk images directly on the host — the "do it
directly" counterpart to typing `DSKINIT`/`SAVE`/`LOAD` in the emulator
(the `mytests/dragon-disk/` workflow).

## Build

    tools/dragondos/fetch.sh     # -> bin/dragondos

Fetches the pinned upstream, applies `patches/01-cli-only-cmake.patch`
(the upstream CMake demands FLTK for its GUI; the CLI itself needs only
the C++17 stdlib) and `patches/02-raw-geometry-from-size.patch` (see
"Upstream quirks"), builds, installs to `bin/` (gitignored).

## Usage

    dragondos new disk.dsk 180 3        # 180K raw .dsk (format index 3 = raw;
                                        # 0 VDK, 1 JVC, 2 IMD — 'listimages')
    dragondos insertbasic disk.dsk prog.bas      # tokenizes on the host
    dragondos insertbinary disk.dsk blob.bin 28672 0x7000
    dragondos insertdata disk.dsk notes.dat
    dragondos list disk.dsk                      # names, sizes, load/exec
    dragondos info disk.dsk                      # geometry + free space
    dragondos extract disk.dsk [index]           # pull files off an image
    dragondos delete disk.dsk <index>

DragonDOS BASIC types are chosen by extension, as in the DOS: `.BAS`
(tokenized), `.BIN` (load/exec), `.DAT` (data). Inserted names are
truncated to 8.3 and uppercased.

## Verified against the machine (2026-09-22)

- **Reader ↔ ROM-written media**: `dragondos list` on the image the
  Dragon's own `SAVE` filled (`mytests/dragon-disk/dragon.dsk`) shows
  exactly what `DIR` showed: `HELLO.BAS` + `TEST.BIN` + the `.BAK`
  DragonDOS made on re-save.
- **Writer → machine**: an image built entirely with `new` +
  `insertbasic` + `insertbinary` + `insertdata`, then mounted in
  `xroar-dev`:
  - `DIR` lists all three files;
  - `LOAD"HELLO.BAS"` + `RUN` prints the program;
  - `LOAD"PAYLOAD.BIN"` + `PRINT PEEK(28672);PEEK(28718)` prints `0 46`
    (the `00..2E` blob came back byte-exact).
- **Tokenizer fidelity**: the same 3-line source tokenized by
  `insertbasic` and typed into the Dragon's own BASIC produce identical
  tokenized streams (74 of 74 significant bytes; only the trailing
  end-of-program byte convention differs by one `00`). The host
  tokenizer is the ROM's.

## Upstream quirks found (worth knowing before you rely on it)

- **Raw images can't be read unpatched**: `CRAWDiskImage::Load()` never
  sets sector geometry, so `list`/`info`/`extract` on any pre-existing
  `.dsk` fail with "Unable to initialize DragonDOS file system".
  Patch 02 infers geometry from file size (256-byte sectors, 18/track).
- **`extract` double-frees** on (at least) `.BAS` files — it crashes
  after writing output. Extraction can be done by hand from the image
  (see the FIB layout in FORMATS-NOTES.md) or by `LOAD`ing in the
  emulator; this has not been chased upstream.
- **Size display**: `list` shows `.BAS` payload-only (excluding the
  9-byte header) but `.BIN`/`.DAT` with it. The DOS's own `DIR` always
  shows whole-file size including the 9-byte header (see
  FORMATS-NOTES.md, "Directory byte accounting" — grounded in Phil
  Harvey-Smith's DragonDOS disassembly).

## Related

- `tools/decb.py` — the RS-DOS (CoCo) counterpart; do not cross-feed
  images (the two file systems differ).
- `FORMATS-NOTES.md` — CAS / DragonDOS / RSDOS layouts, with the
  verified-against-the-machine ledger.
- `mytests/dragon-disk/` — the in-emulator workflow this tool replaces
  for creating images.