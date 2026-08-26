# 1802 target contract

The host C sources are a reference model only. The ELF-DOS interpreter is
hand-written 1802 assembly and is assembled with the installed `asm02` and
`link02` tools against this repository's SDK snapshot.

## Register allocation

This is the initial convention for routines that do not call the kernel:

- `R7`: ZPC, the next guest instruction address;
- `R8`: current instruction/temporary pointer;
- `R9`: story cache/file-offset scratch;
- `RA`: evaluation-stack pointer;
- `RB`: current call-frame pointer;
- `RC`: operand or size temporary;
- `RD`: first argument / guest address;
- `RE`: second argument / temporary;
- `RF`: return value and first argument where documented.

These assignments are an ABI, not a claim that every register remains live
across an ELF-DOS kernel or BIOS call. Callers must spill live state before
platform calls until survival has been hardware-confirmed for that service.

## Resident story memory primitive

`zminit` takes `RD = host RAM base` and `RF = exclusive guest dynamic end`.
`zmread` takes `RD = guest address` and returns the byte in `D`; it returns
`DF=1` when the address is outside resident dynamic memory. `zmwrite` takes
`RD = guest address` and `RF.0 = byte`; it returns `DF=1` for a non-dynamic
address. These routines do not access the filesystem. A later high-memory
routine will use the same failure result to invoke the cache/file backend.

The high-memory cache uses one 512-byte window. `zcinit` takes `RD = open FCB`
and `RF = cache buffer`; `zcread` takes a 32-bit physical story offset as
`RD = high word`, `RF = low word`. It returns the byte in `D`, or `DF=1` for
EOF or an I/O failure. Cache state is invalidated after failed seek/read calls.

The bounds comparison is written as `address - dynamic_end`: on the 1802,
`SM`/`SMB` set `DF=1` when the subtraction did *not* borrow (minuend >=
subtrahend) and `DF=0` when it did. So for `address - dynamic_end`, `DF=1`
means `address >= dynamic_end` -- out of range -- and `DF=0` (borrowed)
means the address is below the limit, i.e. valid. The failure branch must
therefore use the no-borrow case (`lbdf`), not `lbnf` -- get this backwards
and every bounds check silently inverts (rejects valid addresses, accepts
invalid ones); see zmem.asm/zstack.asm/zcache.asm's own comments at each
comparison for the specific direction in that routine.

## Memory plan

The program is loaded at `PROG_BASE` from the SDK. The loader-provided RAM range
is divided at startup into fixed regions:

1. resident interpreter code and static tables;
2. resident dynamic story memory;
3. VM evaluation stack and call frames;
4. one or more fixed-size high-memory cache buffers;
5. temporary parser and I/O workspace.

The exact split is selected from `mem_base/mem_top` at startup, not hard-coded
to a particular ELF-DOS machine. Story bytes are always accessed through VM
routines. A 16-bit guest address and a packed routine/string file offset are
different types; the latter may need 17 bits for a V3 image.

## Assembly stack primitive

`zstack_init` takes `RD = first byte` and `RF = exclusive end`, both in RAM.
`zstack_push` takes `RF = value`; `zstack_pop` returns `RF = value`.
Both return `DF=0` on success and `DF=1` on overflow/underflow. Values are
stored big-endian, matching Z-machine words. The stack grows upward and is
separate from the call-frame stack.
