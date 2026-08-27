CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -Ihost

HOST_TEST = build/test_host
ASM ?= /opt/elfc/asm02
ASMFLAGS ?= -r -I ..
LINK ?= /opt/elfc/link02
LFLAGS ?= -b -be -r

HOST_SOURCES = host/story_mem.c host/story_header.c host/vm_state.c \
	host/ztext.c host/objects.c host/properties.c host/dictionary.c \
	host/parser.c tests/test_host.c
ASM_MODULES = lib/zstack.prg lib/zmem.prg lib/zcache.prg lib/zobj.prg \
	lib/zprop.prg lib/zdict.prg lib/zparse.prg lib/zterm.prg lib/zdec.prg \
        lib/zinputl.prg
DIAG_MODULES = diag/zdiag.prg diag/zdiag_main.prg diag/zobjdiag.prg \
	diag/zobjdiag_main.prg diag/zpropdiag.prg diag/zpropdiag_main.prg \
	diag/zdictdiag.prg diag/zdictdiag_main.prg diag/zparsediag.prg \
	diag/zparsediag_main.prg diag/ztermdiag.prg diag/ztermdiag_main.prg \
	diag/zdecdiag.prg diag/zdecdiag_main.prg

.PHONY: all test asm diag clean

all: test

test: $(HOST_TEST)
	$(HOST_TEST)

asm: $(ASM_MODULES)
	@test -f lib/zmem.prg
	@test -f lib/zstack.prg
	@test -f lib/zobj.prg
	@test -f lib/zprop.prg
	@test -f lib/zdict.prg
	@test -f lib/zparse.prg
	@test -f lib/zterm.prg
	@test -f lib/zdec.prg
	@test -f lib/zinputl.prg

# diag/zdiag_main, diag/zobjdiag_main, diag/zpropdiag_main,
# diag/zdictdiag_main, diag/zparsediag_main, and diag/zdecdiag_main are
# ELF-DOS front ends for zdiag.asm/zobjdiag.asm/zpropdiag.asm/
# zdictdiag.asm/zparsediag.asm/zdecdiag.asm's checks against the
# resident memory/stack, object/attribute, property, dictionary,
# tokenizer, and Z-text decoder primitives (see
# docs/ARCHITECTURE.md's "diagnostic dispatch loop" step) -- run them
# on hardware or under an emulator with the real ELF-DOS kernel
# loaded; K_MSG/K_INMSG have nothing to call otherwise.
# diag/ztermdiag_main is different: it's an interactive demo, not an
# automated check list (see zterm.asm's own header comment for why).
diag: $(ASM_MODULES) $(DIAG_MODULES)
	$(LINK) $(LFLAGS) -o diag/zdiag diag/zdiag_main.prg diag/zdiag.prg lib/zmem.prg lib/zstack.prg
	rm -f diag/zdiag.lkb
	$(LINK) $(LFLAGS) -o diag/zobjdiag diag/zobjdiag_main.prg diag/zobjdiag.prg lib/zobj.prg
	rm -f diag/zobjdiag.lkb
	$(LINK) $(LFLAGS) -o diag/zpropdiag diag/zpropdiag_main.prg diag/zpropdiag.prg lib/zprop.prg lib/zobj.prg
	rm -f diag/zpropdiag.lkb
	$(LINK) $(LFLAGS) -o diag/zdictdiag diag/zdictdiag_main.prg diag/zdictdiag.prg lib/zdict.prg
	rm -f diag/zdictdiag.lkb
	$(LINK) $(LFLAGS) -o diag/zparsediag diag/zparsediag_main.prg diag/zparsediag.prg lib/zparse.prg lib/zdict.prg
	rm -f diag/zparsediag.lkb
	$(LINK) $(LFLAGS) -o diag/ztermdiag diag/ztermdiag_main.prg lib/zterm.prg lib/zinputl.prg
	rm -f diag/ztermdiag.lkb
	$(LINK) $(LFLAGS) -o diag/zdecdiag diag/zdecdiag_main.prg diag/zdecdiag.prg lib/zdec.prg
	rm -f diag/zdecdiag.lkb

lib/%.prg: lib/%.asm include/opcodes.def
	cd lib && $(ASM) $(ASMFLAGS) $*.asm

diag/%.prg: diag/%.asm include/opcodes.def include/bios.inc include/kernel_api.inc
	cd diag && $(ASM) $(ASMFLAGS) $*.asm

$(HOST_TEST): $(HOST_SOURCES) | build
	$(CC) $(CFLAGS) $(HOST_SOURCES) -o $@

build:
	mkdir -p $@

clean:
	rm -rf build
	rm -f $(ASM_MODULES) $(ASM_MODULES:.prg=.build) $(ASM_MODULES:.prg=.lst)
	rm -f $(DIAG_MODULES) $(DIAG_MODULES:.prg=.build) $(DIAG_MODULES:.prg=.lst)
	rm -f diag/zdiag diag/zdiag.lkb diag/zobjdiag diag/zobjdiag.lkb diag/zpropdiag diag/zpropdiag.lkb diag/zdictdiag diag/zdictdiag.lkb diag/zparsediag diag/zparsediag.lkb diag/ztermdiag diag/ztermdiag.lkb diag/zdecdiag diag/zdecdiag.lkb
