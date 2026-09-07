/*
 * tools/zrun_ref.c - host reference runner
 *
 * Drives the same portable core (the host/ sources) the 1802 port is modelled on
 * against a real V3 story file, so its output can be diffed against
 * what zrun3 produces on ELF-DOS. Not part of `make all`'s own unit
 * tests -- this is an oracle for debugging the port, built by
 * `make zrun_ref`.
 *
 * Usage: zrun_ref <story-file> [max-steps] < input-lines
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "story_mem.h"
#include "story_header.h"
#include "vm_state.h"
#include "dispatch.h"

static int emit_char(char c, void *ctx) {
    (void)ctx;
    putchar(c == 10 || c == 13 ? '\n' : c);
    return 0;
}

static int read_line_cb(char *buffer, uint8_t max_length, void *ctx) {
    (void)ctx;
    if (!fgets(buffer, max_length + 1, stdin)) return -1;
    size_t n = strlen(buffer);
    while (n && (buffer[n-1] == '\n' || buffer[n-1] == '\r')) buffer[--n] = 0;
    printf("%s\n", buffer);
    return (int)n;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: zrun_ref <story> [max-steps]\n"); return 2; }
    long max_steps = argc > 2 ? atol(argv[2]) : 200000;

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *image = malloc((size_t)len);
    if (!image || fread(image, 1, (size_t)len, f) != (size_t)len) { fprintf(stderr, "read failed\n"); return 1; }
    fclose(f);

    struct story_header h;
    if (story_header_parse(image, (size_t)len, &h) != 0) { fprintf(stderr, "bad header\n"); return 1; }

    struct story_mem mem;
    if (story_mem_init(&mem, image, (size_t)len, h.static_memory) != 0) { fprintf(stderr, "mem init failed\n"); return 1; }

    struct vm_state st;
    vm_state_init(&st, h.globals, h.initial_pc);

    struct vm_context ctx;
    memset(&ctx, 0, sizeof ctx);
    ctx.memory = &mem;
    ctx.state = &st;
    ctx.object_table = h.object_table;
    ctx.dictionary_table = h.dictionary;
    ctx.abbrev_table = h.abbreviations;
    ctx.emit = emit_char;
    ctx.read_line = read_line_cb;

    long steps = 0;
    while (!ctx.quit && steps < max_steps) {
        uint16_t pc = st.pc;
        if (vm_step(&ctx) != 0) {
            fflush(stdout);
            fprintf(stderr, "\n[zrun_ref: stopped at pc=%04X after %ld steps]\n", pc, steps);
            return 1;
        }
        steps++;
    }
    fflush(stdout);
    fprintf(stderr, "\n[zrun_ref: %s after %ld steps]\n", ctx.quit ? "quit" : "step limit", steps);
    return 0;
}
