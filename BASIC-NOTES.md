# Microsoft 6809 BASIC (Dragon & CoCo): architecture, quirks, bugs

The 6809 BASIC both families ship is, at root, the same Microsoft 6809
Color BASIC. Dragon Data licensed and adapted it; Tandy shipped it. That
shared heritage means most "how BASIC behaves" facts are true on both
machines, and the differences are smaller than the layouts suggest.
This note records the shared architecture, the quirks of the
implementation, and its bugs -- and marks, for each entry, whether it was
**verified on the machine** (V) here, is **in the ROM/source** (R), or is
**well-known but not re-verified** (W).

Scope: Dragon 32/64, CoCo 1/2/3. The disk-capable variants (DECB on the
CoCo, DragonDOS on the Dragon) add tokens and hooks but sit on the same
core.

## Architecture (the shared shape)

- **Tokenized storage, not text.** A program line is `[len][addr][line# hi]
  [line# lo][token stream][$00]`. Observed: `20 PRINT"HELLO..."` stores as
  `14 87 20 22 48 45...` -- `0x87` is the PRINT token and the rest of the
  line is ASCII (V, from a CSAVE'd file). A tool that searches a memory
  image or a CAS for `"PRINT"` as text will not find it.
- **Immediate vs program mode.** A line with no line number executes
  immediately and returns `OK`; a numbered line is stored. Both paths were
  exercised while driving DSKINIT/SAVE sessions (V).
- **Program area and variables.** The Dragon 32 starts its BASIC text area
  just above $0600; the DOS's own variables reserve 1.5K there and move it
  up when resident (R, DragonDOS "Additional Info"). Variable storage
  follows the program. Scratch/machine code goes safely below $0600 or near
  the top of RAM.
- **`?` is PRINT.** A remnant, true on both (W).
- **ROM arrangement per machine** (the layout differs; the BASIC inside is
  the same family):
  - Dragon 32/64: **monolithic 16K** -- the whole Extended Color BASIC set
    in one ROM (`d32.rom`, `d64.rom`). Boot log: "BASIC (1 x 16K)".
  - CoCo 1/2: **split 8K + 8K** -- Color BASIC, Extended Color BASIC as an
    add-on chip (`bas13.rom` + `extbas11.rom`). Boot log: "BASIC (2 x 8K)".
  - CoCo 3: monolithic 32K (`coco3.rom`).
- **Screen.** Text mode is a 32x16 block of RAM at $0400 (the Dragon; the
  CoCo family is the same VDG heritage). Write to it directly for headless
  verification -- but see the charset quirk below.

## Quirks of the implementation

- **No `MOD`, on either machine.** `A MOD B` is not a token of this
  family's BASIC; it parses and falls through in a way that prints the
  operands and zero rather than erroring, which reads as silent nonsense
  (V on the Dragon: `PRINT 28673 MOD 256` prints `28673 0`). Synthesize:
  `A-INT(A/B)*B`, which the ROM evaluates correctly (V: `28673` -> `1`).
  This is a family trait, not a Dragon-vs-CoCo difference.
- **The screen charset is not ASCII.** Text-screen RAM holds byte values
  whose glyphs (and some 0x40-bit display variants) are the machine's own,
  so dumping $0400 and decoding as ASCII misleads. Compare booleans
  ("does the file appear in DIR? is the byte range correct?") rather than
- **Logical operators AND / OR / NOT, and the boolean state they share.**
  Documented in the manual as condition combiners; the *implementation*
  facts, all measured on a Dragon 32 (V):
  - Comparisons yield **-1 for TRUE, 0 for FALSE**: `(1=1)` -> -1,
    `(1=2)` -> 0.
  - `NOT x` = `-x-1`: `NOT 0` -> -1 (true), `NOT 1` -> -2.
  - `AND`/`OR` are **bitwise over 16-bit integers**: `12 AND 10` = 8,
    `12 OR 8` = 12.
  - The truth *test* is looser than the representation: **any non-zero
    number is TRUE** in a condition, zero is FALSE (V: `IF 2 THEN`
    prints, `IF 0 THEN ... ELSE` takes the ELSE).
  - **Strings have no boolean link**: a string in a condition is
    `?TM ERROR`, never coerced (V).
  - Both sides of `AND`/`OR` are always evaluated; there is no
    short-circuit (W).
- **Error codes are two-letter mnemonics** with plain, per-manual meanings
  (`?SN` syntax, `?FC` function call, `?TM` type mismatch -- seen live
  above on the string-in-IF probe). `?UL` is simply "undefined line";
  nothing else needs saying about it (`R`, manual).

## Bugs

- **No `MOD`** -- arguably a missing feature rather than a bug, but the
  silent non-error fall-through is the bug-shaped part; it cost a real
  session here (V).
- **No `ON ERROR GOTO`.** Rescue idiom is the well-known one: POKE the
  error-dispatch vector (W). `ELSE` however **exists** -- optional, and
  documented in the manual (R) and taken live (V: the `IF 0` probe above
  ran its ELSE branch).
- The token table itself differs *between* the machines (CoCo vs Dragon
  variants moved tokens around and drop/add some), so **tokenized files
  are not portable** between them even though the BASIC is "the same"
  (W).

## Ledger

Verified here (V): MOD absence and its fall-through output; the
`A-INT(A/B)*B` idiom; tokenized storage shape; immediate-mode `OK`;
program area around $0600; screen charset caution; long-command screen
silence; boolean representation (-1/0, NOT = -x-1, bitwise AND/OR);
non-zero-is-true test; strings-in-conditions -> ?TM ERROR; ELSE exists.
From source (R): $0600 1.5K DOS reservation and program-link move;
DOS file-type semantics live in the DOS, not BASIC; the two-letter
error-code mnemonics (manual).
Well-known, not re-verified here (W): `?`, undefined-var-zero, GC
pauses, no ON ERROR GOTO, no short-circuit in AND/OR, token-table
non-portability.

Keep this ledger honest: a claim that moves from W to V gets its letter
changed and a note about how it was verified, same rule as
MACHINE-COVERAGE.md.