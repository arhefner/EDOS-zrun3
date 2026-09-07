# Local ELF-DOS emulation for zrun3

`/opt/elfc/run02` emulates the machine ELF-DOS targets closely enough to
boot the real kernel off a real FAT16 image: BIOS vectors at `$FF00`
(matching `include/bios.inc`), SCRT at `$FA7B`/`$FA8D`, and an IDE disk
backed by a file named `disk1.ide` in the working directory. `-B` loads
sector 0 at `$0100` and enters at `$0106`, which is exactly what
`boot/mbr.asm` expects.

    make zrun3
    tools/emu/mkdisk.sh /tmp/zemu zrun3=/bin/zrun3 "$HOME/claude_io/infocom/ZORK I=/zork1"
    (cd /tmp/zemu && python3 <repo>/tools/emu/drive.py "zrun3 /zork1" "open mailbox" "north")

`drive.py` runs run02 under a pty, sends each argument as a line once the
output goes quiet, and prints everything the console produced. It clears
`ICRNL` deliberately: `lib/zinputl.asm` (the BIOS line-input routine)
accepts CR and ignores LF, and a pty's default line discipline would
rewrite the CR we send into an LF.

`fatput.py` is a minimal FAT16 writer (8.3 names only). It sets the
direntry NTRes byte for lowercase names, without which ELF-DOS's own
lowercase kernel paths (`/bin/shell`) don't match — see `kernel/dir.asm`'s
`_dir_fmt83`.

## RUN02_DIRTY_DF — make the emulator hostile about DF

Run/02's emulated console BIOS calls (`f_type` at `$FF03`, `f_btype` at
`$F803`, `f_utype` at `$F809`) return with DF clear. Real hardware does
not: `K_TYPE`/`K_MSG` have no documented DF contract at all — ELF-DOS's
`_redir_msg` just returns whatever its last `K_TYPE` left — and on the
user's machine that is DF=1. Any caller that treats a print's DF as a
result therefore passes locally and fails on hardware, which is exactly
how `zds_print_obj`'s missing `clc` survived a full local playthrough.

The patch is three lines in the emulator's own `cpu.c` (see the note at
`case 0xff03`): `if (getenv("RUN02_DIRTY_DF")) cpu->df = 1;` before
`sret`, in each of the three console-output cases. With
`RUN02_DIRTY_DF=1` set, the unfixed build reproduced the hardware failure
byte for byte. **Run both the diags and a real playthrough with it set** —
it costs nothing and it is the only local way to catch this class of bug.

## Debugging hooks

Run/02 builds from `~/projects/elf/Run02`. `run02-debug-hooks.patch` in
this directory applies all of them to a copy of that tree (`cp -r`, patch
`cpu.c`, `make`), each gated on an environment variable so an unset build
behaves exactly as stock. They paid for themselves repeatedly during the
2026-09-07 bug hunt:

- dump all 64K of RAM to a file when the PC reaches a chosen address
  (find `zrun3_error`'s address in `zrun3_main.lst`), then compare against
  the story file to read out globals, the object table, parse buffers;
- log every `f_ideread` (LBA + destination), which is how the kernel's
  `_fat_load_sector` RB-clobber was caught;
- log the Z-machine PC and resolved operands each time the interpreter
  loop is re-entered (`zdisp_pc`/`zdisp_operand`; their linked addresses
  come out of `zrun3_main.lst` plus `_zdispatch_data`'s field order) —
  this gives a Z-code-level trace to disassemble against the story file;
- `RUN02_DIRTY_DF`, above.

Variables: `RUN02_IDELOG`, `RUN02_DUMPPC` + `RUN02_RAMDUMP`,
`RUN02_ZHOOK` + `RUN02_ZPC` + `RUN02_ZOPS` + `RUN02_ZLOG`,
`RUN02_DIRTY_DF`. `drive.py` honours `$RUN02` to pick the patched binary.

The Z-code trace needs a disassembler to be useful; writing a small V3
one in Python (opcode forms, operand types, branch/store encoding, plus a
Z-string decoder and the object table) took well under an hour and was
what turned every remaining "it stopped here" into a specific diagnosis.
