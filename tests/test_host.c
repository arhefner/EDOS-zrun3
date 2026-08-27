#include <assert.h>
#include <string.h>

#include "story_mem.h"
#include "story_header.h"
#include "vm_state.h"
#include "ztext.h"
#include "objects.h"
#include "properties.h"
#include "dictionary.h"
#include "parser.h"
#include "decode.h"

static int append_char(char character, void *context)
{
    char *output = context;
    size_t length = strlen(output);
    output[length] = character;
    output[length + 1] = '\0';
    return 0;
}

static uint16_t zword(unsigned first, unsigned second, unsigned third,
                      int end)
{
    return (uint16_t)((end ? 0x8000u : 0) | (first << 10) |
                      (second << 5) | third);
}

int main(void)
{
    uint8_t image[32] = {0};
    struct story_mem memory;
    uint16_t word;
    char text[32] = "";
    uint16_t hello_words[] = {zword(13, 10, 17, 0), zword(17, 20, 5, 1)};
    uint8_t hello[] = {
        (uint8_t)(hello_words[0] >> 8), (uint8_t)hello_words[0],
        (uint8_t)(hello_words[1] >> 8), (uint8_t)hello_words[1]
    };
    uint8_t header_image[128] = {0};
    struct story_header header;
    struct vm_state state;
    struct vm_frame frame;
    uint16_t locals[] = {0x1234, 0x5678};
    uint16_t value;
    uint8_t obj_image[256] = {0};
    struct story_mem obj_memory;
    const uint16_t OBJECT_TABLE = 0;
    uint8_t obj_num;
    int attr_flag;
    uint16_t prop_addr;
    uint8_t prop_len;
    uint16_t prop_value;
    uint16_t short_addr;
    uint16_t short_len;
    uint8_t dict_image[64] = {0};
    struct story_mem dict_memory;
    struct dict_header dict_hdr;
    uint16_t dict_entry_addr;
    uint8_t dict_encoded[ZTEXT_V3_ENCODED_LENGTH];
    const uint16_t DICT_ADDR = 0;
    uint8_t parser_image[80] = {0};
    struct story_mem parser_memory;
    const uint16_t PARSER_DICT_ADDR = 0;
    const uint16_t PARSER_TEXT_ADDR = 30;
    const uint16_t PARSER_PARSE_ADDR = 50;
    const char parser_text[] = "take cat, run";
    size_t parser_index;
    uint8_t parser_byte;
    uint16_t parse_word;
    uint8_t var_image[64] = {0};
    struct story_mem var_memory;
    struct vm_state var_state;
    uint16_t var_value;
    uint16_t var_locals[] = {0xaaaa, 0xbbbb};
    uint8_t decode_image[32] = {0};
    struct story_mem decode_memory;
    struct instruction instr;

    header_image[0] = 3;
    header_image[2] = 0;
    header_image[3] = 7;
    header_image[4] = 0x00;
    header_image[5] = 0x80;
    header_image[6] = 0x01;
    header_image[7] = 0x00;
    header_image[8] = 0x00;
    header_image[9] = 0x40;
    header_image[10] = 0x00;
    header_image[11] = 0x50;
    header_image[12] = 0x00;
    header_image[13] = 0x30;
    header_image[14] = 0x00;
    header_image[15] = 0x78;
    header_image[18] = '8';
    header_image[19] = '8';
    header_image[20] = '0';
    header_image[21] = '4';
    header_image[22] = '0';
    header_image[23] = '1';
    header_image[24] = 0x00;
    header_image[25] = 0x70;
    header_image[26] = 0x00;
    header_image[27] = 0x40;

    assert(story_mem_init(&memory, image, sizeof(image), 16) == 0);
    assert(story_mem_write8(&memory, 3, 0xa5) == 0);
    assert(image[3] == 0xa5);
    assert(story_mem_write8(&memory, 16, 0) != 0);
    image[20] = 0x12;
    image[21] = 0x34;
    assert(story_mem_read16(&memory, 20, &word) == 0 && word == 0x1234);
    assert(ztext_decode(hello, sizeof(hello), append_char, text) == 0);
    assert(strcmp(text, "hello") == 0);
        assert(story_header_parse(header_image, sizeof(header_image), &header) == 0);
        assert(header.release == 7 && header.file_length == 128 &&
            strcmp(header.serial, "880401") == 0);
        header_image[14] = 0x00;
        header_image[15] = 0x20;
        assert(story_header_parse(header_image, sizeof(header_image), &header) != 0);
        vm_state_init(&state, 0x30, 0x100);
        assert(vm_push(&state, 0x1111) == 0);
        assert(vm_push(&state, 0x2222) == 0);
        assert(vm_pop(&state, &value) == 0 && value == 0x2222);
        assert(vm_frame_push(&state, 0x3456, 2, 1, locals, 2) == 0);
        assert(vm_pop(&state, &value) == 0 && value == 0x1111);
        assert(vm_frame_pop(&state, &frame) == 0 && frame.return_pc == 0x3456 &&
            frame.locals[1] == 0x5678);
        assert(vm_pop(&state, &value) != 0);

    /* Object table: object 1 is the parent of object 2, which has
     * object 3 as a sibling. Property defaults[6] (property 7) is
     * 0x2222, used below since object 2 has no properties of its own. */
    obj_image[12] = 0x22;
    obj_image[13] = 0x22;

    obj_image[68] = 2;                 /* object 1: child = 2 */
    obj_image[69] = 0x00;
    obj_image[70] = 0x64;              /* object 1: property table @ 100 */

    obj_image[75] = 1;                 /* object 2: parent = 1 */
    obj_image[76] = 3;                 /* object 2: sibling = 3 */
    obj_image[78] = 0x00;
    obj_image[79] = 0x6e;              /* object 2: property table @ 110 */

    obj_image[84] = 1;                 /* object 3: parent = 1 */
    obj_image[87] = 0x00;
    obj_image[88] = 0x73;              /* object 3: property table @ 115 */

    obj_image[100] = 1;                /* object 1: 1-word short name */
    obj_image[101] = 0x80;
    obj_image[102] = 0x00;
    obj_image[103] = 0x05;             /* property 5, length 1 */
    obj_image[104] = 0x99;
    obj_image[105] = 0x23;             /* property 3, length 2 */
    obj_image[106] = 0x12;
    obj_image[107] = 0x34;
    obj_image[108] = 0x00;             /* end of object 1's properties */

    obj_image[110] = 0;                /* object 2: no short name */
    obj_image[111] = 0x00;             /* end of object 2's properties (none) */

    obj_image[115] = 0;                /* object 3: no short name */
    obj_image[116] = 0x05;             /* property 5, length 1 */
    obj_image[117] = 0x42;
    obj_image[118] = 0x00;             /* end of object 3's properties */

    assert(story_mem_init(&obj_memory, obj_image, sizeof(obj_image),
                          sizeof(obj_image)) == 0);

    assert(obj_get_parent(&obj_memory, OBJECT_TABLE, 1, &obj_num) == 0 &&
        obj_num == 0);
    assert(obj_get_child(&obj_memory, OBJECT_TABLE, 1, &obj_num) == 0 &&
        obj_num == 2);
    assert(obj_get_parent(&obj_memory, OBJECT_TABLE, 2, &obj_num) == 0 &&
        obj_num == 1);
    assert(obj_get_sibling(&obj_memory, OBJECT_TABLE, 2, &obj_num) == 0 &&
        obj_num == 3);
    assert(obj_get_parent(&obj_memory, OBJECT_TABLE, 0, &obj_num) != 0);

    assert(obj_test_attr(&obj_memory, OBJECT_TABLE, 1, 3, &attr_flag) == 0 &&
        attr_flag == 0);
    assert(obj_set_attr(&obj_memory, OBJECT_TABLE, 1, 3) == 0);
    assert(obj_test_attr(&obj_memory, OBJECT_TABLE, 1, 3, &attr_flag) == 0 &&
        attr_flag == 1);
    assert(obj_clear_attr(&obj_memory, OBJECT_TABLE, 1, 3) == 0);
    assert(obj_test_attr(&obj_memory, OBJECT_TABLE, 1, 3, &attr_flag) == 0 &&
        attr_flag == 0);

    assert(obj_remove(&obj_memory, OBJECT_TABLE, 2) == 0);
    assert(obj_get_parent(&obj_memory, OBJECT_TABLE, 2, &obj_num) == 0 &&
        obj_num == 0);
    assert(obj_get_child(&obj_memory, OBJECT_TABLE, 1, &obj_num) == 0 &&
        obj_num == 3);

    assert(obj_insert(&obj_memory, OBJECT_TABLE, 2, 3) == 0);
    assert(obj_get_parent(&obj_memory, OBJECT_TABLE, 2, &obj_num) == 0 &&
        obj_num == 3);
    assert(obj_get_child(&obj_memory, OBJECT_TABLE, 3, &obj_num) == 0 &&
        obj_num == 2);
    assert(obj_get_sibling(&obj_memory, OBJECT_TABLE, 2, &obj_num) == 0 &&
        obj_num == 0);

    assert(obj_short_name(&obj_memory, OBJECT_TABLE, 1, &short_addr,
                          &short_len) == 0 && short_addr == 101 &&
        short_len == 2);
    assert(obj_short_name(&obj_memory, OBJECT_TABLE, 2, &short_addr,
                          &short_len) == 0 && short_addr == 111 &&
        short_len == 0);

    assert(prop_get_addr(&obj_memory, OBJECT_TABLE, 1, 5, &prop_addr) == 0 &&
        prop_addr != 0);
    assert(prop_get_len(&obj_memory, prop_addr, &prop_len) == 0 &&
        prop_len == 1);
    assert(prop_get_addr(&obj_memory, OBJECT_TABLE, 1, 3, &prop_addr) == 0 &&
        prop_addr != 0);
    assert(prop_get_len(&obj_memory, prop_addr, &prop_len) == 0 &&
        prop_len == 2);
    assert(prop_get_addr(&obj_memory, OBJECT_TABLE, 1, 9, &prop_addr) == 0 &&
        prop_addr == 0);
    assert(prop_get_len(&obj_memory, 0, &prop_len) == 0 && prop_len == 0);

    assert(prop_get(&obj_memory, OBJECT_TABLE, 1, 5, &prop_value) == 0 &&
        prop_value == 0x99);
    assert(prop_get(&obj_memory, OBJECT_TABLE, 1, 3, &prop_value) == 0 &&
        prop_value == 0x1234);
    assert(prop_get(&obj_memory, OBJECT_TABLE, 2, 7, &prop_value) == 0 &&
        prop_value == 0x2222);

    assert(prop_get_next(&obj_memory, OBJECT_TABLE, 1, 0, &obj_num) == 0 &&
        obj_num == 5);
    assert(prop_get_next(&obj_memory, OBJECT_TABLE, 1, 5, &obj_num) == 0 &&
        obj_num == 3);
    assert(prop_get_next(&obj_memory, OBJECT_TABLE, 1, 3, &obj_num) == 0 &&
        obj_num == 0);
    assert(prop_get_next(&obj_memory, OBJECT_TABLE, 2, 0, &obj_num) == 0 &&
        obj_num == 0);
    assert(prop_get_next(&obj_memory, OBJECT_TABLE, 1, 9, &obj_num) != 0);

    /* ztext_encode: hand-verified against the V3 z-char tables --
     * 'c'=8, 'a'=6, 't'=25, then three padding (5) z-chars:
     * word0 = 8<<10 | 6<<5 | 25 = 0x20d9
     * word1 = 0x8000 | 5<<10 | 5<<5 | 5 = 0x94a5 */
    assert(ztext_encode("cat", 3, dict_encoded) == 0 &&
        dict_encoded[0] == 0x20 && dict_encoded[1] == 0xd9 &&
        dict_encoded[2] == 0x94 && dict_encoded[3] == 0xa5);
    {
        /* an overlong word truncates at 6 z-characters, not 6 bytes */
        uint8_t encoded_long[ZTEXT_V3_ENCODED_LENGTH];
        uint8_t encoded_truncated[ZTEXT_V3_ENCODED_LENGTH];
        assert(ztext_encode("alphabet", 8, encoded_long) == 0);
        assert(ztext_encode("alphab", 6, encoded_truncated) == 0);
        assert(memcmp(encoded_long, encoded_truncated,
                      ZTEXT_V3_ENCODED_LENGTH) == 0);
    }
    {
        /* uppercase round-trips through the A1 shift character */
        uint8_t encoded_upper[ZTEXT_V3_ENCODED_LENGTH];
        char decoded_upper[8] = "";
        assert(ztext_encode("Hi", 2, encoded_upper) == 0);
        assert(ztext_decode(encoded_upper, ZTEXT_V3_ENCODED_LENGTH,
                            append_char, decoded_upper) == 0);
        assert(strcmp(decoded_upper, "Hi") == 0);
    }
    assert(ztext_encode("h@i", 3, dict_encoded) != 0);   /* '@' unencodable */

    /* Dictionary: 1 separator (','), 7-byte entries (4 text + 3 data),
     * 3 entries -- "cat", "dog", "run" -- each followed by 3 arbitrary
     * data bytes a real game would use for part-of-speech flags. */
    dict_image[0] = 1;
    dict_image[1] = ',';
    dict_image[2] = 7;
    dict_image[3] = 0x00;
    dict_image[4] = 0x03;
    assert(ztext_encode("cat", 3, &dict_image[5]) == 0);
    dict_image[9] = 0xaa;
    dict_image[10] = 0xbb;
    dict_image[11] = 0xcc;
    assert(ztext_encode("dog", 3, &dict_image[12]) == 0);
    dict_image[16] = 0xdd;
    dict_image[17] = 0xee;
    dict_image[18] = 0xff;
    assert(ztext_encode("run", 3, &dict_image[19]) == 0);
    dict_image[23] = 0x11;
    dict_image[24] = 0x22;
    dict_image[25] = 0x33;

    assert(story_mem_init(&dict_memory, dict_image, sizeof(dict_image),
                          sizeof(dict_image)) == 0);
    assert(dict_parse_header(&dict_memory, DICT_ADDR, &dict_hdr) == 0 &&
        dict_hdr.entry_length == 7 && dict_hdr.entry_count == 3 &&
        dict_hdr.entries_addr == 5);

    assert(dict_find_word(&dict_memory, DICT_ADDR, "dog", 3,
                          &dict_entry_addr) == 0 && dict_entry_addr == 12);
    {
        uint8_t data_byte;
        assert(story_mem_read8(&dict_memory, (uint16_t)(dict_entry_addr + 4),
                               &data_byte) == 0 && data_byte == 0xdd);
    }
    assert(dict_find_word(&dict_memory, DICT_ADDR, "cat", 3,
                          &dict_entry_addr) == 0 && dict_entry_addr == 5);
    assert(dict_find_word(&dict_memory, DICT_ADDR, "run", 3,
                          &dict_entry_addr) == 0 && dict_entry_addr == 19);
    assert(dict_find_word(&dict_memory, DICT_ADDR, "xyz", 3,
                          &dict_entry_addr) == 0 && dict_entry_addr == 0);

    /* Parser: same dictionary layout as above, a fresh buffer so the
     * two tests stay independent. "take cat, run" exercises an
     * unlisted word ("take"), a listed one ("cat"), the separator
     * ',' as its own one-character token (also unlisted), and a
     * second listed word ("run"). */
    parser_image[0] = 1;
    parser_image[1] = ',';
    parser_image[2] = 7;
    parser_image[3] = 0x00;
    parser_image[4] = 0x03;
    parser_image[5] = 0x20;
    parser_image[6] = 0xd9;
    parser_image[7] = 0x94;
    parser_image[8] = 0xa5;            /* "cat" */
    parser_image[9] = 0xaa;
    parser_image[10] = 0xbb;
    parser_image[11] = 0xcc;
    parser_image[12] = 0x26;
    parser_image[13] = 0x8c;
    parser_image[14] = 0x94;
    parser_image[15] = 0xa5;           /* "dog" */
    parser_image[16] = 0xdd;
    parser_image[17] = 0xee;
    parser_image[18] = 0xff;
    parser_image[19] = 0x5f;
    parser_image[20] = 0x53;
    parser_image[21] = 0x94;
    parser_image[22] = 0xa5;           /* "run" */
    parser_image[23] = 0x11;
    parser_image[24] = 0x22;
    parser_image[25] = 0x33;

    for (parser_index = 0; parser_index < sizeof(parser_text) - 1;
        ++parser_index) {
        parser_image[PARSER_TEXT_ADDR + parser_index] =
            (uint8_t)parser_text[parser_index];
    }
    parser_image[PARSER_PARSE_ADDR] = 10;      /* max words */

    assert(story_mem_init(&parser_memory, parser_image,
                          sizeof(parser_image), sizeof(parser_image)) == 0);
    assert(parser_tokenize(&parser_memory, PARSER_DICT_ADDR,
                           PARSER_TEXT_ADDR,
                           (uint8_t)(sizeof(parser_text) - 1), 2,
                           PARSER_PARSE_ADDR) == 0);

    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 1,
                           &parser_byte) == 0 && parser_byte == 4);

    /* word 0: "take" -- not in the dictionary */
    assert(story_mem_read16(&parser_memory, PARSER_PARSE_ADDR + 2,
                            &parse_word) == 0 && parse_word == 0);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 4,
                           &parser_byte) == 0 && parser_byte == 4);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 5,
                           &parser_byte) == 0 && parser_byte == 2);

    /* word 1: "cat" -- found at dictionary offset 5 */
    assert(story_mem_read16(&parser_memory, PARSER_PARSE_ADDR + 6,
                            &parse_word) == 0 && parse_word == 5);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 8,
                           &parser_byte) == 0 && parser_byte == 3);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 9,
                           &parser_byte) == 0 && parser_byte == 7);

    /* word 2: "," -- a separator, so it's its own token; not listed */
    assert(story_mem_read16(&parser_memory, PARSER_PARSE_ADDR + 10,
                            &parse_word) == 0 && parse_word == 0);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 12,
                           &parser_byte) == 0 && parser_byte == 1);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 13,
                           &parser_byte) == 0 && parser_byte == 10);

    /* word 3: "run" -- found at dictionary offset 19 */
    assert(story_mem_read16(&parser_memory, PARSER_PARSE_ADDR + 14,
                            &parse_word) == 0 && parse_word == 19);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 16,
                           &parser_byte) == 0 && parser_byte == 3);
    assert(story_mem_read8(&parser_memory, PARSER_PARSE_ADDR + 17,
                           &parser_byte) == 0 && parser_byte == 12);

    /* Variable access: variable 0 is the stack (operand access pops/
     * pushes it; indirect access peeks/replaces in place), 1-15 are
     * the current frame's locals, 16-255 are globals in story memory. */
    assert(story_mem_init(&var_memory, var_image, sizeof(var_image),
                          sizeof(var_image)) == 0);
    vm_state_init(&var_state, 0, 0x100);

    assert(vm_write_variable(&var_state, &var_memory, 0, 0x1234) == 0 &&
        var_state.eval_depth == 1);
    assert(vm_read_variable(&var_state, &var_memory, 0, &var_value) == 0 &&
        var_value == 0x1234 && var_state.eval_depth == 0);

    assert(vm_frame_push(&var_state, 0x200, 0, 2, var_locals, 2) == 0);
    assert(vm_read_variable(&var_state, &var_memory, 1, &var_value) == 0 &&
        var_value == 0xaaaa);
    assert(vm_write_variable(&var_state, &var_memory, 2, 0xcccc) == 0);
    assert(vm_read_variable(&var_state, &var_memory, 2, &var_value) == 0 &&
        var_value == 0xcccc);
    assert(vm_read_variable(&var_state, &var_memory, 3, &var_value) != 0);

    assert(vm_write_variable(&var_state, &var_memory, 16, 0x5678) == 0);
    assert(vm_read_variable(&var_state, &var_memory, 16, &var_value) == 0 &&
        var_value == 0x5678);
    assert(story_mem_read16(&var_memory, 0, &var_value) == 0 &&
        var_value == 0x5678);

    assert(vm_push(&var_state, 0x9999) == 0);
    assert(vm_read_variable_indirect(&var_state, &var_memory, 0,
                                     &var_value) == 0 &&
        var_value == 0x9999 && var_state.eval_depth == 1);
    assert(vm_write_variable_indirect(&var_state, &var_memory, 0,
                                      0x8888) == 0 &&
        var_state.eval_depth == 1);
    assert(vm_pop(&var_state, &var_value) == 0 && var_value == 0x8888);
    assert(vm_read_variable_indirect(&var_state, &var_memory, 0,
                                     &var_value) != 0);

    assert(vm_frame_pop(&var_state, &frame) == 0);
    assert(vm_read_variable(&var_state, &var_memory, 1, &var_value) != 0);

    /* Decoder: each instruction below was hand-derived from the V3
     * encoding rules and cross-checked bit by bit, not just eyeballed. */
    assert(story_mem_init(&decode_memory, decode_image, sizeof(decode_image),
                          sizeof(decode_image)) == 0);

    /* long form, 2OP:20 "add", two small constants, stores: opcode
     * byte $14 (00 010100: long form, both operands small const,
     * opcode 20), operands 5 and 3, store variable $10 */
    decode_image[0] = 0x14;
    decode_image[1] = 5;
    decode_image[2] = 3;
    decode_image[3] = 0x10;
    assert(decode_instruction(&decode_memory, 0, &instr) == 0);
    assert(instr.form == FORM_LONG && instr.category == CATEGORY_2OP &&
        instr.opcode == 20);
    assert(instr.operand_count == 2 &&
        instr.operand_types[0] == OPERAND_SMALL &&
        instr.operand_types[1] == OPERAND_SMALL &&
        instr.operands[0] == 5 && instr.operands[1] == 3);
    assert(instr.stores && instr.store_variable == 0x10);
    assert(!instr.branches && !instr.has_text);
    assert(instr.length == 4);

    /* short form, 1OP:0 "jz", one variable operand, branches: opcode
     * byte $A0 (10 10 0000: short form, operand type variable,
     * opcode 0), operand = variable 5, then a single-byte branch (on
     * true, offset 10): $CA (11 001010) */
    decode_image[0] = 0xa0;
    decode_image[1] = 5;
    decode_image[2] = 0xca;
    assert(decode_instruction(&decode_memory, 0, &instr) == 0);
    assert(instr.form == FORM_SHORT && instr.category == CATEGORY_1OP &&
        instr.opcode == 0);
    assert(instr.operand_count == 1 &&
        instr.operand_types[0] == OPERAND_VARIABLE &&
        instr.operands[0] == 5);
    assert(!instr.stores);
    assert(instr.branches && instr.branch_on_true && instr.branch_offset == 10);
    assert(instr.length == 3);

    /* variable form, VAR:0 "call", stores: opcode byte $E0 (11 1 00000:
     * variable form, VAR category, opcode 0), operand types byte $1F
     * (00 01 11 11: large, small, omitted, omitted), operands $0800
     * and 7, store variable $11 */
    decode_image[0] = 0xe0;
    decode_image[1] = 0x1f;
    decode_image[2] = 0x08;
    decode_image[3] = 0x00;
    decode_image[4] = 7;
    decode_image[5] = 0x11;
    assert(decode_instruction(&decode_memory, 0, &instr) == 0);
    assert(instr.form == FORM_VARIABLE && instr.category == CATEGORY_VAR &&
        instr.opcode == 0);
    assert(instr.operand_count == 2 &&
        instr.operand_types[0] == OPERAND_LARGE &&
        instr.operand_types[1] == OPERAND_SMALL &&
        instr.operands[0] == 0x0800 && instr.operands[1] == 7);
    assert(instr.stores && instr.store_variable == 0x11);
    assert(instr.length == 6);

    /* short form, 0OP:2 "print", carries an inline packed string --
     * reuses the exact "hello" bytes from the ztext_decode test above */
    decode_image[0] = 0xb2;
    decode_image[1] = 0x35;
    decode_image[2] = 0x51;
    decode_image[3] = 0xc6;
    decode_image[4] = 0x85;
    assert(decode_instruction(&decode_memory, 0, &instr) == 0);
    assert(instr.form == FORM_SHORT && instr.category == CATEGORY_0OP &&
        instr.opcode == 2);
    assert(instr.operand_count == 0 && !instr.stores && !instr.branches);
    assert(instr.has_text);
    assert(instr.length == 5);

    /* long form, 2OP:4 "dec_chk", both operands variables, branches
     * with a two-byte offset of -50: opcode byte $64 (01 1 00100:
     * long form, both operands variable, opcode 4), operands =
     * variables 5 and 6, branch bytes $3F,$CE (on false, two-byte
     * form, 14-bit value $3FCE = 16334, sign-extends to -50) */
    decode_image[0] = 0x64;
    decode_image[1] = 5;
    decode_image[2] = 6;
    decode_image[3] = 0x3f;
    decode_image[4] = 0xce;
    assert(decode_instruction(&decode_memory, 0, &instr) == 0);
    assert(instr.form == FORM_LONG && instr.category == CATEGORY_2OP &&
        instr.opcode == 4);
    assert(instr.operand_count == 2 &&
        instr.operand_types[0] == OPERAND_VARIABLE &&
        instr.operand_types[1] == OPERAND_VARIABLE &&
        instr.operands[0] == 5 && instr.operands[1] == 6);
    assert(!instr.stores);
    assert(instr.branches && !instr.branch_on_true &&
        instr.branch_offset == -50);
    assert(instr.length == 5);

    /* a truncated instruction (operand runs past the story's own
     * length) is a decode error, not a crash */
    assert(story_mem_init(&decode_memory, decode_image, 2, 2) == 0);
    decode_image[0] = 0x14;                    /* "add", needs 4 bytes */
    decode_image[1] = 5;
    assert(decode_instruction(&decode_memory, 0, &instr) != 0);

    return 0;
}