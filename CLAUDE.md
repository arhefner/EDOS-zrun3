# zrun3

A Z-machine version 3 interpreter for ELF-DOS (CDP1802). No real
*hardware* is available here — the user reflashes and reports console
output back — but the whole system CAN be run locally under Run/02
against a real ELF-DOS disk image; see "Local emulation" below, and
prefer it to a hardware round for anything short of final confirmation.
See `docs/ARCHITECTURE.md` for the VM layering and `docs/TARGET.md` for
the memory plan and the 1802 DF/borrow convention.

ELF-DOS itself (kernel, toolchain, `CLAUDE.md` with its own extensive
toolchain-gotchas list) lives in the sibling `ELF-DOS` repo. zrun3 runs as
an ordinary ELF-DOS program loaded at `PROG_BASE`, via `include/kernel_api.inc`'s
`K_*` jump table.

## Build

```
make zrun3   # links zrun3_main.prg + lib/*.prg -> zrun3
make diag    # diag/*.asm -> diag/<name> (bare-metal, no kernel touched)
make all     # host-side C reference tests (host/*.c) — model-checks VM
             # semantics against the same behavior the 1802 port must match
make clean
```

Toolchain: `asm02 -r -I .. <file>.asm` produces a `.prg`; `link02 -b -be -r
-o <out> <files.prg...>` links them (`-r` = short-branch relaxation).
Installed at `/opt/elfc/{asm02,link02}`.

## Toolchain gotchas (Asm/02 / Link/02) — confirmed this project, check by hand

1. **A same-file cross-`proc` reference needs its own `extrn`, even though
   it's defined later in the very same file.** `proc`/`endp` are real scope
   boundaries to this assembler — a label declared inside one `proc` is
   invisible to code in a different `proc`, in the same file or not, unless
   it's declared `public` in its own proc's data block AND `extrn`'d at the
   top of every OTHER proc that references it. Forgetting the `extrn` (even
   though the symbol is "right there" in the same file) fails with `*ERROR:
   Label not found`, not a warning. Every static-data field in a `lib/*.asm`
   module referenced from more than one `proc` needs this treatment — see
   any of `zload.asm`/`zcache.asm`/`zdecode.asm`'s own `extrn` blocks for the
   established pattern (declare the `extrn` up top, `public` it in the data
   proc down below).
2. **`mov Rd, Rs` and `mov Rd, #immediate` both clobber D as a side effect**
   — same lesson ELF-DOS's own `CLAUDE.md` gotcha #4 documents for that
   codebase. D must be set LAST, with nothing but the instruction that needs
   it (a `call`, a `str`, a comparison) between the load and its use. Hit
   repeatedly enough in this project's own history (save/restore's zsptr
   calc, div/mod's sign fixup, twice in abbreviation decode — see memory)
   that it's a standing review question for any new 1802 code here.
3. **A register is not confirmed to survive any call unless its callee's
   actual body has been read.** Don't trust a subroutine's own header
   comment or "looks like scratch" — grep the callee's body for what it
   clobbers. Hit repeatedly (zdispsave, zvar, zdec) — see memory
   `project_zrun3_save_restore_lessons`.
4. **Multi-byte `SHL`/`SHLC` or `SHR`/`SHRC` chains must go strictly
   low-to-high (or high-to-low) byte order** — mixing the order feeds the
   carry into the wrong end. Hit in `zdisp_umod16`'s remainder shift — see
   memory `project_zrun3_1802_shift_chain_order`.
5. **Program size directly costs heap margin, not just "code space."**
   ELF-DOS's loader sets `mem_base = PROG_BASE + program size` — every byte
   added to `zrun3_main.asm`/any linked `lib/*.asm` shrinks the arena
   `bump_alloc` has to work with (dynamic memory, eval stack, call frames,
   dictionary buffer, `zcache`'s window). A real incident this project hit:
   diagnostic instrumentation added across several rounds silently pushed
   the dictionary-buffer allocation into OOM (stage 10) even though nothing
   about the story file had changed — the loader was correct, `zrun3` had
   just grown. When adding instrumentation, prefer trimming
   already-answered diagnostics over letting the binary grow unbounded, and
   don't assume "small edit" means "no memory-margin effect."
6. **`zmread_bytes`/`zmread_wide`'s "short read is a normal partial result,
   not a failure" contract is real and must be honored by the caller.**
   `zmread_bytes` returns DF=0 with `RC` less than requested when the
   underlying cache genuinely ran short — correct for callers with no known
   length (`print_addr`/abbreviation expansion), a real bug for a caller
   that measured an exact length (`zload_story`'s dictionary-prefix/table
   fetch) and only checked DF, not RC. Any new caller with a caller-known
   exact length must compare the returned RC against what it asked for, not
   just check DF.

## Status

**ZORK I plays end to end** under Run/02 with a real ELF-DOS disk image
(banner, room descriptions, parser, object/container handling, score and
move counters, status line), and ZORK III boots and plays too. The
long-parked ">64K story file" blocker below is root-caused and fixed.

Hardware round 1 (`~/claude_io/zr21.txt`) got as far as the banner plus
"West of House" and then stopped with a bogus decode error — bug 14
below, the one failure mode the emulator was too forgiving to show. Fixed,
and the emulator taught to reproduce it (`RUN02_DIRTY_DF`, see
`tools/emu/README.md`). **Hardware round 2 confirmed working.**

Since that confirmation the build has changed in one way that has NOT
been on hardware yet: `-r` is back on (see the memory budget below), which
rewrites 430 branches. It passes the full diag suite and playthroughs of
ZORK I, ZORK III and MOONMIST under Run/02 with `RUN02_DIRTY_DF=1`, but
branch relaxation is exactly the sort of change that deserves its own
hardware check.

## Memory budget (real hardware: `mem_top - PROG_BASE` = 44927)

zrun3 is ~23.1KB, leaving ~21.3KB of heap. A story needs
`dynamic_end + 512 (eval stack) + 592 (frames) + dictionary` resident.
**Every V3 title in the sample library now fits**, but the margin is
genuinely thin at the top: MOONMIST +196 bytes, SEASTALKER +1640,
WISHBRINGER +1988, SORCERER +2152. Gotcha #5 (program size costs heap
directly, byte for byte) is therefore live — roughly every 200 bytes
added to the binary drops another title off the end of that list. Check
the budget before adding anything permanent.

MOONMIST only fits because of `-r`. Branch relaxation was switched off
during the ">64K seek" hunt and left off; re-enabling it shortened 430 of
628 long branches and saved 418 bytes, which was the difference between
MOONMIST missing by 188 and clearing by 196. Keep `-r` on in both
`ASMFLAGS` and `LFLAGS`.

## Local emulation (Run/02) — this project CAN be run locally now

The "no local emulator" note above is out of date for integration
testing. `/opt/elfc/run02` emulates the exact machine ELF-DOS targets
(BIOS vectors at `$FF00`, matching `include/bios.inc`; SCRT at
`$FA7B`/`$FA8D`; an IDE disk backed by a file called `disk1.ide` in the
working directory, booted with `-B`, which loads sector 0 at `$0100` and
enters at `$0106` — exactly ELF-DOS's own boot contract).

To build a bootable image:

1. 32MB file, one FAT16 partition at LBA 2048 (`sfdisk`), `mkfs.fat -F 16`
   into a separate file and `dd` it into place.
2. `../ELF-DOS/sys/elfdos-sys -m mbr.bin -k kernel-full.bin disk1.ide`
   (it works on a plain file, not just a raw device).
3. Copy files into the FAT16 partition. Set the NTRes byte (offset 12) to
   `$08`/`$18` for lowercase names, or ELF-DOS's own lowercase kernel paths
   (`/bin/shell`) will not match — see `kernel/dir.asm`'s `_dir_fmt83`.
   On-disk names must fit 8.3.
4. Drive it through a pty with `ICRNL` cleared: the BIOS line-input
   routine (`lib/zinputl.asm`) accepts CR and ignores LF, and a pty's
   default line discipline turns a sent CR into LF.

Worth rebuilding this harness rather than going back to hardware rounds:
every bug listed under "Bugs found via local emulation" below was found in
minutes with it, after nine-plus hardware rounds had failed to find the
first one.

## The parked ">64K seek" bug — SOLVED

It was never a `K_FILE_SEEK` bug at all. `zdisp_step`'s preamble did:

```
mov     r8, zdisp_pc_bank
ldn     r8
mov     r9, zm_bank      ; <-- clobbers D (toolchain gotcha #2)
str     r9
```

so `zm_bank` was set to **the low byte of its own address**, and `zmread`
handed that to `zcread` as the 32-bit offset's high word. Hence "the low
word is always correct, only the high word is garbage", and hence
"editing anything changes the symptom" — the bogus value *is* a link-time
address. `diag/zseekdiag_main.asm` never reproduced it because its own two
`zm_bank` writes already load the pointer before the byte.

Everything else in the old bisection trail (the kernel `file_read`
lookahead fix, the RAM measurement, the `-r` experiments) was real work but
unrelated. `diag/zseekdiag_main.asm` has been deleted — it referenced the
`zcdiag_*` globals the fix removed, so it no longer assembled, and it had
served its purpose. It was never committed, so it appears in no history;
recover it from a session transcript if it is ever wanted again.

One leftover from that trail was worth reversing: `-r` had been switched
off while chasing the bug and never switched back. See the memory budget
above for what it was costing.

## Bugs found via local emulation (all fixed)

In rough order of discovery. Every one is commented at its own site.

1. **ELF-DOS kernel** (`kernel/fat.asm`): `_fat_load_sector` clobbered `RB`
   on its cache-miss path while documenting only `R7/R8/RF`, and
   `fat_flush` clobbers `RB` too. `_fcb_sector_lba_and_iobuf` keeps the
   live FCB pointer in `RB` across its `fat_get` call, so a FAT-cache miss
   during a cluster advance silently duplicated one sector of the file
   *and* fired a wild 512-byte `f_ideread` into a garbage address. Affects
   every ELF-DOS program, not just zrun3.
2. `zload_story`'s dictionary header parse: `mov` between `ldn` and `str`
   (gotcha #2), so the separator count became an address byte and the
   dictionary size came out as garbage (stage 10 "OOM").
3. `zdisp_step`'s `zm_bank` write: the parked bug above (gotcha #2 again).
4. **A2 alphabet**: no entry for z-char 7 (newline), so every digit and
   punctuation mark was one z-char early. `host/ztext.c` had the identical
   error, which is exactly why the host tests never caught it.
5. `zobj_prop_table_addr` returned the object entry's property-table field
   verbatim — the one GUEST address in the object table — while
   `zobj_short_name`/`zprop_*` treat it as a real host pointer.
   `zobj_init` now takes the story's host base as a second argument.
6. `call 0`: legal per the standard (store false, no call). Both the port
   and `host/dispatch.c` treated it as an error.
7. A2 z-char 6's 10-bit ZSCII escape was unimplemented, so ZORK I's `>`
   prompt printed as `" cannot "` (placeholder space plus the escape's own
   two halves read as an abbreviation reference).
8. Dictionary entry addresses written into the game's parse buffer were
   translated with `zmbase`, but the dictionary gets its own dedicated
   buffer. `zdict_init` now takes the dictionary's guest address too.
9. `zdict_encode` stopped one z-char early (`>=` vs `>` on the fill
   pointer), so any word needing all 6 z-chars encoded wrongly and was
   never found — "I don't know the word 'mailbox'".
10. `zmread16` kept the low byte's address in `R7` across `zmread`, which
    stopped being safe when `zmread` grew its cache fallback (gotcha #3).
11. `zdisp_do_call` read `zdisp_routine_addr_hi` (a word) with a single
    `ldn` into the register's HIGH half, so a routine past 64K lost its
    bank entirely.
12. `zdisp_branch`/`jump` loaded `zdisp_pc_bank` (a byte) with `phi`
    instead of `plo`, so every taken branch inside a >64K routine dropped
    back to bank 0.
13. `zmread` chose resident-vs-cache from the 16-bit address alone,
    ignoring `zm_bank` — a bank-1 address below `zmend` read dynamic
    memory.
14. `zds_print_obj` returned `K_MSG`'s DF as its own result — the only
    `zdisp_emit_string` call site in `zdispatch.asm` without a `clc`. It
    printed the room name correctly and then reported a bogus opcode
    error. **Hardware-only:** Run/02's emulated console returns DF clear,
    and `diag/zdispatchdiag.asm`'s own `zdisp_emit_string` double already
    ended in `clc`, so both the emulator and the diags disagreed with the
    real platform hook about DF. `zdisp_emit_string`/`zterm_print_string`/
    `zterm_print_char` now all guarantee DF=0; see
    `tools/emu/README.md`'s `RUN02_DIRTY_DF`, which reproduces it locally.
15. The decoder's "z-char 5 in the final word's last slot is padding" rule
    is this project's own invention, not in the standard, and it swallowed
    a trailing abbreviation whose index happens to be 5. Again mirrored in
    `host/ztext.c`.

Note the pattern: **five of these were mirrored in the host reference
model**, so `make all` agreed with the port and proved nothing. When the
model and the port share an assumption, only a real story file can
falsify it. Bug 14 is the same shape one level down: the *test double* for
a platform hook was stricter than the real hook, so nothing that ran
against the double could see the difference. When a diag substitutes its
own implementation of an interface, the two implementations' contracts
have to be checked against each other, not just against the caller.

**A kernel call's DF is not a result unless its own documentation says
so.** `K_MSG`/`K_TYPE` document none; `_redir_msg` returns whatever its
last `K_TYPE` left. Treat DF from `K_*` as undefined and set it yourself
before returning — this is the same class as gotcha #3 (don't assume a
register survives a call), applied to the flags.
