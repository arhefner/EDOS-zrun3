# zrun3 architecture

zrun3 is a Z-machine version 3 interpreter for ELF-DOS. The VM core owns
Z-machine semantics; the ELF-DOS port supplies storage and terminal services.

## Address spaces

Guest addresses are 16-bit Z-machine addresses. The story image may be larger
than the host's directly mapped memory, so the storage implementation must not
use a host pointer as a guest address.

The V3 header divides the image into:

- dynamic memory: `[0, dynamic_end)`, writable and included in saves;
- static memory: `[dynamic_end, high_start)`, read-only;
- high memory: `[high_start, story_length)`, read-only and cacheable/streamable.

All guest reads go through `story_mem_read8/read16`; all writes go through
`story_mem_write8`. A write outside dynamic memory is an error. The first host
implementation is a flat image; the ELF-DOS implementation will replace its
backing store with a resident dynamic region plus a fixed high-memory cache.

## VM layers

1. **Core:** instruction fetch/decode, variables, evaluation stack, call
   frames, branches, object/property tables, dictionary/parser, and Z-text.
2. **Story memory:** guest-address validation, endian conversion, dynamic
   writes, and cache misses for static/high memory.
3. **Platform:** ELF-DOS file FCBs, console input/output, allocation, random
   numbers, and save/restore files.

The core must not call ELF-DOS entry points directly. Platform calls are narrow
interfaces so the host reference tests and the 1802 port can share semantics.

## Initial implementation order

1. Host story-memory and Z-text tests.
2. Host VM state: variables, stacks, frames, and calls.
3. V3 header validation and story loader.
4. 1802 memory/stack primitives and a diagnostic dispatch loop.
5. Object/property subsystem, dictionary, and parser.
6. ELF-DOS terminal adapter.
7. Save/restore and compatibility testing.

The first save format will be private and versioned. It will identify the story
with release, serial, checksum, and length, then store dynamic memory, ZPC,
evaluation stack, and call frames. Static and high memory are reloaded from the
story file.
