# mytests: Dragon 32 cassette workflow

A minimal end-to-end edit -> assemble... no, edit -> type -> CSAVE -> CLOAD -> RUN
loop for the Dragon 32, using only the fork's own machinery.

| File | What it is |
|---|---|
| `hello.bas` | The program, as plain ASCII BASIC source |
| `type_program.txt` | `-input-script`: types the program into BASIC and runs `CSAVE"HELLO"` |
| `hello.cas` | The cassette image, written by the *real ROM's* CSAVE via `-tape-write` (588 bytes: leader, filename block, tokenized data, end block, CUE) |
| `run_cas.txt` | `-input-script`: types `CLOAD"HELLO"` then `RUN` |

## Commands

```bash
# 1. create the CAS (types the source, CSAVEs it to the tape file)
bin/xroar-dev -machine dragon32 -headless \
    -input-script mytests/type_program.txt \
    -tape-write mytests/hello.cas -timeout 16

# 2. load and run it, headless (verify by RAM-dumping the screen at $0400)
bin/xroar-dev -machine dragon32 -headless \
    -load-tape mytests/hello.cas \
    -input-script mytests/run_cas.txt -timeout 16

# 2b. ...or in a window (GUI build; close the window to quit)
bin/xroar-dev-gui -machine dragon32 \
    -load-tape mytests/hello.cas \
    -input-script mytests/run_cas.txt
```

## Gotchas paid for, in order

1. **ROMs.** The starter `roms.tar.gz` is CoCo-only. A Dragon 32 needs `d32.rom`
   (16,384 bytes, CRC32 `0xe3879310`, "Dragon 32 BASIC (1982)"), placed in
   `~/.xroar/roms/`. XRoar prints the CRC on load and validates against its table.

2. **`-input-script` `\r` is two characters.** The parser tokenizes the script
   line with `strtok(NULL, "\r\n")` (`src/joystick_script.c`), so a *literal* CR
   byte terminates the `type` text and the ENTER is silently dropped: the line
   gets typed but never entered. Write `\r` as backslash + `r` in the script
   file; `ak_parse_type_string()` converts it to an ENTER keypress. (The
   AGENT-NOTES `$'\r'` warning is about generating recipe files from shell —
   the recipes themselves want the backslash-r.)

3. **Diagnosing "nothing happened": read the screen as data.** The Dragon text
   screen is RAM at `$0400` (32x16, ASCII-ish). `-trap-range 1-1 -trap-ram
   FILE` dumps it at a trap; decode from Python. Screenshots are good, but this
   works from any headless run and shows every echoed keystroke.

4. **Unbounded `-trap-screenshot` auto-numbers files** (`smoke1.png`, capped at
   10). Use `-trap-range N-N` for a single plain-named image.

## Conveniences discovered along the way

- Traps are silent unless they print (`-trap-cycle-print` does):
  `-trap 'seconds=8'` firing is visible only through its actions.
- `-tape-write` + `[tape] writing: ... [PLAYING]` and `MOTOR ON`/`MOTOR OFF`
  (at `-v 2`) are the tape-side state; a 0-byte CAS means the guest never
  wrote, not that the tape path is broken.
- Machine names: `dragon32`, `dragon64`, `coco`, `coco3`, `mc10`.