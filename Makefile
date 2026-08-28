CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -Ihost

HOST_TEST = build/test_host
ASM ?= /opt/elfc/asm02
ASMFLAGS ?= -r -I ..
LINK ?= /opt/elfc/link02
LFLAGS ?= -b -be -r

HOST_SOURCES = host/story_mem.c host/story_header.c host/vm_state.c \
	host/ztext.c host/objects.c host/properties.c host/dictionary.c \
	host/parser.c host/decode.c host/dispatch.c tests/test_host.c
ASM_MODULES = lib/zstack.prg lib/zmem.prg lib/zcache.prg lib/zobj.prg \
	lib/zprop.prg lib/zdict.prg lib/zparse.prg lib/zterm.prg lib/zdec.prg \
        lib/zinputl.prg lib/zdecode.prg lib/zvar.prg lib/zdispatch.prg \
	lib/zdispemit.prg
DIAG_MODULES = diag/zdiag.prg diag/zdiag_main.prg diag/zobjdiag.prg \
	diag/zobjdiag_main.prg diag/zpropdiag.prg diag/zpropdiag_main.prg \
	diag/zdictdiag.prg diag/zdictdiag_main.prg diag/zparsediag.prg \
	diag/zparsediag_main.prg diag/ztermdiag.prg diag/ztermdiag_main.prg \
	diag/zdecdiag.prg diag/zdecdiag_main.prg diag/zdecodediag.prg \
	diag/zdecodediag_main.prg diag/zvardiag.prg diag/zvardiag_main.prg \
	diag/zdispatchdiag.prg diag/zdispatchdiag_main.prg

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
	@test -f lib/zdecode.prg
	@test -f lib/zvar.prg
	@test -f lib/zdispatch.prg
	@test -f lib/zdispemit.prg

# diag/zdiag_main, diag/zobjdiag_main, diag/zpropdiag_main,
# diag/zdictdiag_main, diag/zparsediag_main, diag/zdecdiag_main,
# diag/zdecodediag_main, diag/zvardiag_main, and diag/zdispatchdiag_main
# are ELF-DOS front ends for zdiag.asm/zobjdiag.asm/zpropdiag.asm/
# zdictdiag.asm/zparsediag.asm/zdecdiag.asm/zdecodediag.asm/
# zvardiag.asm/zdispatchdiag.asm's checks against the resident memory/
# stack, object/attribute, property, dictionary, tokenizer, Z-text
# decoder, instruction decoder, call-frame/variable-access, and opcode
# execution primitives (see docs/ARCHITECTURE.md's "diagnostic
# dispatch loop" step) -- run them on hardware or under an emulator
# with the real ELF-DOS kernel loaded; K_MSG/K_INMSG have nothing to
# call otherwise.
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
	$(LINK) $(LFLAGS) -o diag/zdecodediag diag/zdecodediag_main.prg diag/zdecodediag.prg lib/zdecode.prg lib/zmem.prg
	rm -f diag/zdecodediag.lkb
	$(LINK) $(LFLAGS) -o diag/zvardiag diag/zvardiag_main.prg diag/zvardiag.prg lib/zvar.prg lib/zstack.prg lib/zmem.prg
	rm -f diag/zvardiag.lkb
	# diag/zdispatchdiag.prg supplies its own zdisp_emit_string (a
	# capture-buffer test double, so print/new_line stay bare-metal
	# testable and assertable) -- lib/zdispemit.prg's real, K_MSG-
	# backed implementation of the same name is deliberately left out
	# of this link; an eventual ELF-DOS interpreter program links that
	# one in instead, never both together (duplicate symbol).
	$(LINK) $(LFLAGS) -o diag/zdispatchdiag diag/zdispatchdiag_main.prg diag/zdispatchdiag.prg lib/zdispatch.prg lib/zdecode.prg lib/zvar.prg lib/zstack.prg lib/zmem.prg lib/zdec.prg
	rm -f diag/zdispatchdiag.lkb

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
	rm -f diag/zdiag diag/zdiag.lkb diag/zobjdiag diag/zobjdiag.lkb diag/zpropdiag diag/zpropdiag.lkb diag/zdictdiag diag/zdictdiag.lkb diag/zparsediag diag/zparsediag.lkb diag/ztermdiag diag/ztermdiag.lkb diag/zdecdiag diag/zdecdiag.lkb diag/zdecodediag diag/zdecodediag.lkb diag/zvardiag diag/zvardiag.lkb diag/zdispatchdiag diag/zdispatchdiag.lkb
