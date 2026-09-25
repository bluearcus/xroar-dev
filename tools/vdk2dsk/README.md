# vdk2dsk: VDK -> DSK/JVC converter

The CLI from [bluearcus/vdk2dsk](https://github.com/bluearcus/vdk2dsk),
pinned to commit `5924f8b` ("Initial repo upload", 2025-07-13), vendored
here as a single C file. It strips the 256-byte (or 12-byte) VDK header
and writes the raw sector payload as a JVC/DSK image, with control over
the output geometry header. No external dependencies; the fork builds it
with a bare `cc` line.

## Build

    tools/vdk2dsk/build.sh        # -> bin/vdk2dsk (gitignored)

## Usage

    bin/vdk2dsk [-f] [-[h|m]] filename.vdk

      -f    force output even if the image size is not as expected
      -h    write headerless .dsk output (no header at all)
      -m    write minimal JVC/DSK header (only as many bytes as needed)

Default: full 5-byte JVC geometry header. `-h` and `-m` are mutually
exclusive. Output name = input name with the extension replaced by
`.dsk` (rename to `.os9` yourself when that is the target).

## Which output to pick (see FORMATS-NOTES.md)

- **OS-9 RBF images: always `-h` (headerless)** and name them `.os9`.
  The `.os9` extension forces XRoar's LSN0 geometry read regardless of
  `-no-disk-auto-os9`, and host-side toolshed `os9` cannot cope with a
  VDK or JVC header at all.
- **DragonDOS images: the 5-byte JVC header is the safer default.**
  XRoar's JVC loader runs its headerless OS-9 auto-check on every raw
  `.dsk`; a DragonDOS boot sector can coincidentally satisfy it.  The
  F2X2-184K loader disk here does exactly that (LSN0 `dd_tot`=720,
  `dd_tks`==`dd_spt`==18), so a raw conversion would be mislabelled a
  "headerless OS-9 image" in every run log.  The 5-byte header sidesteps
  the check, and both XRoar's `-load-fdX` and the retrotools `dragondos`
  reader accept it.

## Fixes over upstream (all in the vendored `vdk2dsk.c`)

1. **`-m` wrote the cylinder count as "sectors per track"** — a 40-track
   image got an 18C/40S geometry header.  VDK has no spt field; the
   format family is always 18 x 256.  Now hardcodes 18 like the
   full-header path already did (`'\22'`).
2. **Output-name buffer overflow**: `malloc(strlen(argv))` then
   `sprintf("%s.dsk")` wrote past the allocation whenever the input name
   had a 4-char extension.  Now `+5`.
3. **Text-mode reads on binary header fields**: `fgets` on the 12-byte
   header stops at a `0x0A` byte and on the 256-byte name area could
   write past its allocation for short headers.  Both are now `fread`
   with checked lengths.

Upstream is unmaintained (single commit); the fixes are local until
someone upstreams them.