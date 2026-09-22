# DragonDOS disk workflow (verified on a Dragon 32)

Everything here was executed against `bin/xroar-dev` (headless) on a
`dragon32` with the DragonDOS 1.0 cartridge (`ddos10.rom`, CRC32
`0xb44536f6` — byte-identical rebuild via `bin/lwasm` from
prime6809/DragonDOS) and a 40-track raw `.dsk` image.

| File | Purpose |
|---|---|
| `dragon.dsk` | 40C 1H 18S (256-byte) raw image, formatted and holding `HELLO.BAS` + `TEST.BIN` (a 47-byte blob `00..2E` at `$7000`) — write-back was on, so this file *is* the floppy |
| `01_format.txt` | `DSKINIT` (the format command — NOT `FORMAT`, which DragonBASIC rejects) |
| `02_save_basic.txt` | type a program, `SAVE"HELLO.BAS"` |
| `03_load_run_basic.txt` | fresh boot: `LOAD"HELLO.BAS"`, `RUN` |
| `04_save_bin.txt` | `SAVE"TEST.BIN",28672,28719,28672` — `.BIN` + S,E,X post-parameters = machine code |
| `05_load_bin.txt` | fresh boot: `LOAD"TEST.BIN"` — verified `$7000` comes back as the saved blob |

## The rules this workflow is built on (from "An Introduction to Dragon DOS", Mayer 1983)

- **No DLOAD/DSAVE; no SAVEM/LOADM.** DragonDOS is BASIC-flavoured: plain
  `SAVE`/`LOAD` go to the floppy while the DOS is resident; the file type is
  chosen by the **extension** — `.BAS` tokenized BASIC, `.BIN` machine code,
  `.DAT` data. `SAVEM"..."` throws `?TM ERROR`.
- **Binary save**: `SAVE"FILE.BIN",start,end,entry` — `end` is *exclusive*
  (address of the byte after the last). We saved 28672..28718 by passing end
  = 28719; 48 bytes would need 28720.
- **Binary load**: `LOAD"FILE.BIN"` loads at the original address and sets
  EXEC to `entry`; `LOAD"FILE.BIN",begin` relocates and recomputes EXEC
  (`begin+entry-start`) — a more flexible convention than CLOADM.
- **Drive prefix**: `KILL"2:PROG.BAS"` style `n:` works. Default drive 0.
- **Backup**: re-saving a name produces a `.BAK` of the previous version.
- **DSKINIT is not fast**: it formats every track and then *verifies by
  reading each track back*, paced by the emulated rotor. Give it ~60 s of
  headless time; a screen frozen on `DSKINIT` with no screen I/O is the DOS
  working, not a hang.

## Input-script notes

- `type CMD` followed by `key enter down` / `key enter up` (raw matrix
  ENTER) is the reliable form; a literal CR in the script still chops lines
  (see the main `mytests/README.md`).
- The Dragon text screen charset is not ASCII: screen RAM shows many chars
  with bit 0x40 set. When verifying by RAM dump, compare *booleans*
  (program loaded? file appears in DIR? address range matches?) rather than
  eyeballing the screen text.

## DragonBASIC gotchas hit while proving this

- **No `MOD`.** Dragon 32 Extended Color BASIC (the monolithic 16K ROM)
  lacks the operator entirely (absent from the manual; `A MOD B` parses to
  nonsense). Use `A-INT(A/B)*B`.
- `FOR A=s TO e: POKE A,...: NEXT` runs fine; `POKE`/`PEEK` are ordinary.
- Machine code under test: put it at `$7000` (top of the 32K as seen by the
  DOS, safely above its variables at `$0600+`).

## Sources

Dragon Data, "An Introduction to Dragon DOS" (A. Mayer, 1983) — the manual
for the semantics above. prime6809/DragonDOS — the assembleable, commented
disassembly; `bin/lwasm` reproduces `ddos10.rom` byte-identically. See the
`Sources` section of `AGENT-NOTES.md` for the full list (Dragon, Tandy/CoCo
and shared references).