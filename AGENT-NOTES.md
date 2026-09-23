# Notes for whoever automates this next

Short on purpose. Every rule here was paid for once already.

## The three that will actually bite you

### 1. Never hand-edit a unified diff

A blank context line in a diff is a line containing **one space**, not an empty
line. Editors strip it, many tools normalise it, and the result applies as if
nothing were wrong until the fifth patch downstream fails with a message
pointing at the wrong file. Hunk headers (`@@ -122,4 +122,14 @@`) also carry
line counts that must match what you wrote.

Both of those were got wrong within twenty minutes of each other while
preparing this fork.

**Generate diffs, never author them:**

    # apply the series to a scratch tree
    tar xzf xroar/xroar-1.12.1.tar.gz && cd xroar-1.12.1
    for p in ../xroar/[0-9]*.patch; do patch -p1 -s < "$p"; done
    cp src/thing.c /tmp/thing.c.orig
    # ...edit src/thing.c with whatever you like...
    diff -u --label a/src/thing.c --label b/src/thing.c /tmp/thing.c.orig src/thing.c

Paste that output under a commit message. Then **verify from a pristine
tarball** that the whole series still applies before you believe any of it.

### 1a. Fix a patch by regenerating it, not by appending a fixup

When patch N turns out to be wrong, **fix patch N**. Do not append "fix what
patch N got wrong" as a new patch at the end. (Numbers are deliberately not
used in this example: renumbering the series would rewrite them and turn the
sentence into nonsense, which is exactly what happened the first time it was
written.) A series that accumulates fixups forces every reader to
reconstruct the real content of a file by replaying edits in order, which is
exactly the property the one-patch-one-idea structure exists to avoid, and it
compounds, because the fixup is itself something a later rebase has to carry.

The regeneration is mechanical:

    build the tree with patches 1..N-1        # snapshot the files N touches
    apply patch N
    apply the fix
    diff snapshot vs result                   # this is the new patch N

Keep the original commit message and extend it to explain the thing that was
wrong; that history is worth more inside the patch than in a separate one.

The exception is a fix to **upstream's** code, where there is no earlier patch
of ours to fold into. Those are genuinely new patches.

### 1b. Edit a patch in bytes, not as text

The series is plain UTF-8 today, but a diff that touches a Windows resource
script or any other non-UTF-8 file will carry raw high bytes, and a tool that
reads it as UTF-8 and writes it back replaces those with `U+FFFD`. The patch
then fails on one hunk in a file that has nothing to do with what you were
changing, and the error points at that file rather than at you.

So edit in bytes:

    b = open(p, "rb").read()
    open(p, "wb").write(b.replace(b"old", b"new"))

and check the whole series afterwards:

    python3 -c "b=open(P,'rb').read(); assert b'\xef\xbf\xbd' not in b"

`.gitattributes` marks `*.patch` as `-text` so git will not normalise them
either.

### 2. Build with `-Werror` at least once

This series spent months being built without it. When it was finally turned on
for a cross-compile, it immediately found four missing declarations, three of
them functions returning pointers, which an implicit declaration truncates to
32 bits on a 64-bit host. Those compile silently and crash later, at the moment
the feature is first used, which may be months after the patch landed.

The Windows build (`build/build-windows.sh`) passes `-Werror`. Run it when you
add a patch even if you do not want a Windows binary.

### 2a. An option with no `-h` line does not exist

    bash build/audit-options.sh

Run it after adding an option. It compares every option this fork registers
against what `-h` prints, and fails if one is missing.

It exists because this happened twice: `-input-script`, the central feature,
and the whole `-profile-*` profiler were both registered, both worked, and
neither appeared in the help. That is the worst way for a feature to be broken.
An agent discovers this binary by reading `-h`, so an option that is not
there has effectively been removed, and the reasonable response to not finding
it is to go debug the build.

### 3. Suspect the harness before the emulator
A scripted run has far more ways to be wired wrong than the emulator has to be
broken. Before concluding you have found an emulator bug:

- Is the coordinate you clicked still on the thing you meant? UI geometry moves.
- Is a stale snapshot being resumed against a newly built binary?
- Did a defensive retry click land somewhere meaningful *after* the dialog it
  was aimed at closed? (A real bug hunt lost a day to exactly this: a retry
  press aimed at a button hit a palette strip once the dialog was gone, and the
  program was blamed for changing a colour it never touched.)
- Is the feature actually compiled in? Check the acceptance lines.

## Launching the emulator: the log is the diagnostic

Learned the hard way on the CoCo 3/DECB session: the screen is a poor
first witness, the log is the good one. Run every headless invocation
with stderr visible -- never `>/dev/null 2>&1` while finding your feet.

- **The startup log tells you what actually loaded.** `[part:coco3]` +
  `Slot 0: CRC32 ... FILE coco3.rom` proves the machine ROMs; a
  `[part:rsdos]` + `[cart:rom] ... FILE disk11.rom` pair proves the
  cartridge attached (a missing cart prints neither). Grep the log for
  `error|fail|warn|cart` before scripting any input.
- **A blocky pattern/checkerboard screen with no text = no machine ROM
  found** (the general rule). On the CoCo 3 it is also just *the boot
  screen* -- so if the log shows the ROMs, the checkerboard is benign
  and means "machine is up, in graphics mode", not "broken".
  Distinguish by the log, not the pixels.
- **The Dragon/CoCo rule "the text screen is RAM at $0400" does not
  transfer to the CoCo 3.** Its text lives in banked graphics RAM, so
  `-trap-ram` dumps of $0400 show noise. For the CoCo 3, prove state
  with `-trap-screenshot` (PNG -- readable, and the fork's own notes
  treat the screen as data), with disk-image bytes after writes, and
  with the log.
- **Boot pacing: nothing typed until the DOS is demonstrably up.**
  Characters typed in the boot gap vanish into a dead buffer -- the
  first DECB attempt typed `DSKINI` into nothing and the disk came back
  pristine. Give the machine its boot time (`-timeout` longer than the
  script, or a `wait`), watch for the banner, then type.
- Cartridges on the CoCo 3: `-cart TYPE`/`-cart-rom FILE` attach
  directly (no MPI needed on a bare machine); `-cart-type help` lists
  the types (`rsdos`, `dragondos`, ...). A `[cart:rom]` line with a
  sane CRC is your confirmation.

**Measure before optimising, and write the number down.** "It feels slow" and
"it copies 18,886 bytes per frame, 33ms, a 30fps ceiling" lead to different and
better decisions. The second one also tells you when to stop.

**Check whether the tree already solves your problem.** A portability fix here
was built twice the wrong way, a local helper and then a fallback in a shared
header, before the *link error from the second attempt* revealed that upstream
already had the mechanism, in `portalib`, with a documented idiom every caller
followed. The error message was more useful than either design. When something
looks like it needs a new mechanism, grep for the old one first.

**Prefer physical addresses.** Stated in the README, repeated here because it is
the single most common way to be intermittently wrong on a banked machine. Use
`xpc=` over `pc=`, flat physical peek/poke over logical reads, physical
watchpoints over logical ones.

**Disassemble with Capstone, not f9dasm.** Capstone knows the 6809 and the
6309 (`CS_ARCH_M680X`, `CS_MODE_M680X_6809` / `CS_MODE_M680X_6309`) and has
Python bindings (`pip install capstone`), so a script gets structured
instructions -- mnemonic, operands, size -- instead of parsing another tool's
text layout. f9dasm is fine as an interactive listing generator; it is the
wrong substrate to build tooling on.

**Say what you did not verify.** If you could not run the thing, say so plainly
  rather than implying a test happened. This matters more than usual with an
  emulator, because "it built" and "it works" are very far apart.

**Diagnosed a structural problem? Write it down that same session.** The
docs are the only record that survives; a finding that is not in
`AGENT-NOTES.md` (or the doc it belongs to) by the time the session ends
will cost the next session the entire investigation again. Updating the
docs is part of fixing the bug, not a cleanup chore, and it is what the
`\r` rule below is: a session ended with a 0-byte CAS file, the answer was
the script parser's line tokenisation, not the tape machinery -- and the
whole story now lives here instead of in a chat log nobody re-reads.

## Shell traps

- **`/bin/sh` may be dash.** No `$'...'` quoting, no `<(...)`, no brace
  expansion, no `shopt`. Wrap anything non-trivial in `bash -c '...'`.
- **An input-script `\r` is two characters, backslash then `r`.** The script
  parser tokenises each line with `strtok(NULL, "\r\n")`
  (`src/joystick_script.c`), so a *literal* CR byte (a `$'\r'` or
  `printf '...\r'` in a generator) terminates the `type` text and the ENTER
  keypress never happens: the line is typed, echoed on screen, and sits
  un-entered forever, and nothing you watch explains why -- it reads exactly
  like "the machine is not accepting input". Write `\r` as backslash-`r` in
  the recipe file and let `ak_parse_type_string()` do the converting. This
  cost a whole "CSAVE wrote a 0-byte CAS" investigation: the tape machinery
  (`-tape-write`, PLAYING, MOTOR ON/OFF) was fine all along and the guest
  simply never executed the command because ENTER never fired. Recognise it
  by the screen: typed line echoed, no `OK` re-prompt, and no following
  command ever runs.
- **`command -v` lies under WSL.** `/mnt/c/...` is on `PATH`, so Windows `.exe`
  files answer probes for Linux tools. Reject any answer under `/mnt/`.
- **Background processes may not survive between tool calls.** If you launch
  the emulator and something that talks to it, launch both in one command.

## When you add a capability

Add a patch. Do not accumulate local changes. The series *is* the fork, and a
change that is not in a patch does not exist as far as the next rebase is
concerned.

Read the four or five patches nearest to what you are adding and imitate them:
the commit-message style in this series is unusually explicit about failure
modes on purpose, because those messages are frequently the only surviving
record of why something is the way it is.

Then: series applies from a pristine tarball, `-Werror` build passes,
acceptance lines all present.

## Sources

What the fork's claims stand on, by machine family. The rule: a behaviour
we assert because a patch changes it should resolve to one of these, and an
agent asked "is this right?" should be able to get here and go read the
thing itself. This list exists because a DragonDOS session burned an hour
reverse-engineering DSKINIT before someone said "read the manual" -- the
manual was free and public the whole time.

### Tandy / CoCo side

- Tandy CoCo 3 Tech Reference -- the GIME, MMU, and the DAT registers
  `qxroar.block`/`task` and the physical-addressing patches (8, 27, 38)
  lean on.
- The Unravelled series (CoCo ROM disassemblies) -- ground truth for the
  RSDOS/DECB and BASIC ROM paths.
- RS-DOS / Disk Extended Color BASIC manuals -- the floppy and FDC work
  (patches 10, 11) and `decb.py`'s disk formats.
- MAME's CoCo and GIME-related sources where the fork's tables derive
  (`joy_rat_table[]` is one); MACHINE-COVERAGE says so when it does.

### Dragon side

- **Dragon Data, "An Introduction to Dragon DOS" (A. Mayer, 1983)** -- the
  DOS's own manual, and the authority on `SAVE`/`LOAD` file-type semantics
  (`.BAS` vs `.BIN` vs `.DAT`, the S,E,X post-parameters, end-exclusive end
  address, drive prefixes, backup-to-`.BAK`). Verifiable against the 6809
  here end to end.
- **Smeed & Somerville, "Inside the Dragon" (Sigma, 1984)** -- the machine's
  internals.
- prime6809/DragonDOS and prime6809/DragonRom -- assembleable, commented
  disassemblies of DragonDOS 1.0/1.2 and the Dragon 32/64 BASIC ROMs;
  `bin/lwasm` reproduces ddos10.rom byte-identically (CRC 0xb44536f6).
  The DOS listing (`ddos12.asm`) is the ground truth for what SAVE/DIR
  actually write and display (file header fields, FIB `$18` accounting).
- Graham's Dragon Page (dragon32.info) -- the classic collection of Dragon
  info files, referencing the Dragon 32 manual, Dragon 64 annex and
  DragonDOS handbook (`dragon.zip`); `info/drgndos.txt` (Kinns) is the
  canonical disk/directory-format spec.
- robcfg/retrotools `dragondos` -- host-side DragonDOS image tool;
  `tools/dragondos/` pins it, patches it, and documents what got
  verified against the machine.
- CASA "Starting Dragon" (solutionarchive.com) -- usage conventions; note it
  blocks non-browser clients (WAF), so fetch it via a cache if at all.

### Shared (both families)

- **Motorola MC6883 / SN74LS783 SAM datasheet** -- both the Dragon and the
  CoCo hang all address decoding off the SAM, so anything touching the
  memory maps of either (or `-gdb-pseudo-regs` SAM registers) starts
  here, once.
- **Dragon <-> Tandy CoCo compatibility notes** -- the two are cousins
  (same SAM/6809/VDG/PIA family, different ROMs and wiring), and the
  differences that matter for emulation work deserve their own note here
  rather than being re-derived per session. Known dimensions to cover:
  - **BASIC token differences** -- the Dragon 32/64 and CoCo token tables
    differ, so a tokenized file or a `POKE`-driven assumption from one family
    does not transfer to the other; gensym's lwasm side is house-independent,
    but BASIC is not. Concrete: **Dragon 32 Extended Color BASIC (one
    monolithic 16K ROM) has no `MOD`** operator (the manual documents none,
    and `A MOD B` parses but prints the operands and 0); synthesize it,
    `A-INT(A/B)*B`, which the ROM evaluates correctly. Also `HIMEM`,
    printer and disk tokens differ. Family-wide Microsoft BASIC behaviour
    (MOD included) lives in BASIC-NOTES.md, not here.

  - **Keyboard matrix** -- the Dragon and CoCo matrices are genuinely
    different layouts (Dragon's 53-key matrix vs CoCo's), so anything
    scanning the matrix raw (`-input-script key`, GetModifierKeys) sees
    different physical positions.
  - **Ports** -- PIA wiring differs: cassette out (PIA1-A via the DAC on
    both, but the Dragon adds the tape output through the same filter),
    serial (bit-banger on the CoCo family, different hardware on the
    Dragon -- patch 28 warns instead of silently arming), printer
    strobe/BUSY lines, and joystick/right-left port occupancy.
  - **Monolithic vs add-on ROMs** -- the CoCo 3's 32K BASIC is one
    monolithic ROM (`coco3.rom`). The CoCo 1/2 spread the same function over
    two 8K chips, Color BASIC plus Extended Color BASIC as an add-on chip
    (`bas13.rom` + `extbas11.rom`); **the Dragon 32/64's BASIC is itself
    monolithic -- the whole Extended Color BASIC set in a single 16K ROM**
    (`d32.rom`/`d64.rom`). Disk BASIC is a cartridge add-on on both
    (`disk11.rom`), and the Dragon's DOSes are cartridge ROMs too
    (`dragondos`, `delta`), which is why `-machine` wiring differs between
    the families.
  - **Disk system differences** -- RSDOS/DECB (CoCo, tracks 0-34 directory
    layout, `-load-fdX` + disk11.rom) vs DragonDOS/DeltaDOS (Dragon,
    different directory track format, `-cart dragondos|delta`, `SAVE`/`LOAD`
    file-type-by-extension semantics); `decb.py` makes RSDOS images and
    nothing here builds DragonDOS ones yet.


## What this fork is not

It is not a better XRoar and it is not trying to become upstream. It is stock
XRoar plus a machine-readable surface. If you find a bug that reproduces on
**stock** XRoar, it belongs upstream, not here. Reproduce it there first, then
report it there.
