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
#include "dispatch.h"

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

/* A fixed "sread" input source for tests -- ignores max_length (the
 * fixed string is always short enough) and returns it verbatim, mixed
 * case included, so the test can confirm sread lowercases it. */
static int fixed_read_line(char *buffer, uint8_t max_length, void *context)
{
    const char *text = context;
    size_t length = strlen(text);

    (void)max_length;
    memcpy(buffer, text, length);
    return (int)length;
}

/* A single save slot standing in for whatever the platform layer
 * would actually do with "save"/"restore"/"restart" -- this reference
 * model only needs the opcodes' control flow to be correct, not a
 * real serialization format (see dispatch.h's own comment on
 * vm_save_fn/vm_restore_fn). The same pair of callbacks serves both
 * restore (reads a slot a prior save wrote) and restart (reads a slot
 * pre-populated with the story's pristine state before play began). */
struct dispatch_save_slot {
    struct vm_state state;
    uint8_t dynamic_memory[64];
    uint16_t dynamic_length;
    int used;
};

static int dispatch_do_save(const struct vm_state *state,
                            const uint8_t *dynamic_memory,
                            uint16_t dynamic_length, void *context)
{
    struct dispatch_save_slot *slot = context;

    slot->state = *state;
    memcpy(slot->dynamic_memory, dynamic_memory, dynamic_length);
    slot->dynamic_length = dynamic_length;
    slot->used = 1;
    return 0;
}

static int dispatch_do_restore(struct vm_state *state, uint8_t *dynamic_memory,
                               uint16_t dynamic_length, void *context)
{
    struct dispatch_save_slot *slot = context;

    if (!slot->used) {
        return -1;
    }
    *state = slot->state;
    memcpy(dynamic_memory, slot->dynamic_memory, dynamic_length);
    return 0;
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
    uint8_t dispatch_a_image[64] = {0};
    struct story_mem dispatch_a_memory;
    struct vm_state dispatch_a_state;
    struct vm_context dispatch_a_ctx;
    uint16_t dispatch_a_result;
    uint8_t dispatch_b_image[16] = {0};
    struct story_mem dispatch_b_memory;
    struct vm_state dispatch_b_state;
    struct vm_context dispatch_b_ctx;
    char dispatch_b_text[8] = "";
    uint8_t dispatch_c_image[200] = {0};
    struct story_mem dispatch_c_memory;
    struct vm_state dispatch_c_state;
    struct vm_context dispatch_c_ctx;
    uint16_t dispatch_c_g0;
    uint16_t dispatch_c_g1;
    uint16_t dispatch_c_g2;
    uint8_t dispatch_d_image[256] = {0};
    struct story_mem dispatch_d_memory;
    struct vm_state dispatch_d_state;
    struct vm_context dispatch_d_ctx;
    uint16_t dispatch_d_g16, dispatch_d_g17, dispatch_d_g18, dispatch_d_g19;
    uint8_t dispatch_e_image[256] = {0};
    struct story_mem dispatch_e_memory;
    struct vm_state dispatch_e_state;
    struct vm_context dispatch_e_ctx;
    uint16_t dispatch_e_g16, dispatch_e_g17, dispatch_e_g18, dispatch_e_g19;
    uint8_t dispatch_f_image[64] = {0};
    struct story_mem dispatch_f_memory;
    struct vm_state dispatch_f_state;
    struct vm_context dispatch_f_ctx;
    uint16_t dispatch_f_g16, dispatch_f_g17;
    uint8_t dispatch_g_image[128] = {0};
    struct story_mem dispatch_g_memory;
    struct vm_state dispatch_g_state;
    struct vm_context dispatch_g_ctx;
    uint16_t dispatch_g_g16, dispatch_g_g17, dispatch_g_g18, dispatch_g_g19;
    uint16_t dispatch_g_g20, dispatch_g_g21, dispatch_g_g22;
    uint8_t dispatch_h_image[64] = {0};
    struct story_mem dispatch_h_memory;
    struct vm_state dispatch_h_state;
    struct vm_context dispatch_h_ctx;
    char dispatch_h_text[8] = "";
    uint8_t dispatch_i_image[64] = {0};
    struct story_mem dispatch_i_memory;
    struct vm_state dispatch_i_state;
    struct vm_context dispatch_i_ctx;
    uint16_t dispatch_i_g16, dispatch_i_g17, dispatch_i_g18;
    uint16_t dispatch_i_g19, dispatch_i_g20;
    uint8_t dispatch_j_image[128] = {0};
    struct story_mem dispatch_j_memory;
    struct vm_state dispatch_j_state;
    struct vm_context dispatch_j_ctx;
    uint8_t dispatch_j_byte;
    uint8_t dispatch_k_image[64] = {0};
    struct story_mem dispatch_k_memory;
    struct vm_state dispatch_k_state;
    struct vm_context dispatch_k_ctx;
    struct dispatch_save_slot dispatch_k_slot;
    uint16_t dispatch_k_g16, dispatch_k_g17;
    uint8_t dispatch_l_image[64] = {0};
    uint8_t dispatch_l_pristine[64];
    struct story_mem dispatch_l_memory;
    struct vm_state dispatch_l_state;
    struct vm_context dispatch_l_ctx;
    struct dispatch_save_slot dispatch_l_slot;
    uint16_t dispatch_l_g16;
    uint8_t dispatch_m_image[128] = {0};
    struct story_mem dispatch_m_memory;
    struct vm_state dispatch_m_state;
    struct vm_context dispatch_m_ctx;
    char dispatch_m_text[8] = "";
    uint16_t dispatch_m_table_len;

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

    assert(prop_put(&obj_memory, OBJECT_TABLE, 1, 5, 0x77) == 0);
    assert(prop_get(&obj_memory, OBJECT_TABLE, 1, 5, &prop_value) == 0 &&
        prop_value == 0x77);
    assert(prop_put(&obj_memory, OBJECT_TABLE, 1, 3, 0x9abc) == 0);
    assert(prop_get(&obj_memory, OBJECT_TABLE, 1, 3, &prop_value) == 0 &&
        prop_value == 0x9abc);
    assert(prop_put(&obj_memory, OBJECT_TABLE, 1, 9, 1) != 0);   /* absent */

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

    /* Dispatch A: call a routine with one argument, which doubles it
     * via "add" and returns the result; the caller stores it in a
     * global. Exercises call (including the routine-header/argument-
     * default mechanics), variable-operand resolution, add, and
     * ret/return. All bytes hand-derived from the encoding rules the
     * same way as the decoder tests above. */
    dispatch_a_image[0x10] = 1;                /* routine: 1 local */
    dispatch_a_image[0x11] = 0x00;              /* local's default: 0 */
    dispatch_a_image[0x12] = 0x00;
    dispatch_a_image[0x13] = 0x74;              /* add L01,L01 -> (stack) */
    dispatch_a_image[0x14] = 0x01;
    dispatch_a_image[0x15] = 0x01;
    dispatch_a_image[0x16] = 0x00;
    dispatch_a_image[0x17] = 0xab;              /* ret (stack) */
    dispatch_a_image[0x18] = 0x00;
    dispatch_a_image[0x20] = 0xe0;              /* call routine($08), 5
                                                 * -> global 16 ($10) */
    dispatch_a_image[0x21] = 0x5f;
    dispatch_a_image[0x22] = 0x08;
    dispatch_a_image[0x23] = 5;
    dispatch_a_image[0x24] = 0x10;
    dispatch_a_image[0x25] = 0xba;              /* quit */

    assert(story_mem_init(&dispatch_a_memory, dispatch_a_image,
                          sizeof(dispatch_a_image),
                          sizeof(dispatch_a_image)) == 0);
    vm_state_init(&dispatch_a_state, 0, 0x20);
    dispatch_a_ctx.memory = &dispatch_a_memory;
    dispatch_a_ctx.state = &dispatch_a_state;
    dispatch_a_ctx.object_table = 0;
    dispatch_a_ctx.emit = 0;
    dispatch_a_ctx.emit_context = 0;
    dispatch_a_ctx.quit = 0;

    assert(vm_step(&dispatch_a_ctx) == 0 && dispatch_a_state.pc == 0x13 &&
        dispatch_a_state.frame_depth == 1);
    assert(vm_step(&dispatch_a_ctx) == 0 && dispatch_a_state.pc == 0x17);
    assert(vm_step(&dispatch_a_ctx) == 0 && dispatch_a_state.pc == 0x25 &&
        dispatch_a_state.frame_depth == 0);
    assert(story_mem_read16(&dispatch_a_memory, 0, &dispatch_a_result) == 0 &&
        dispatch_a_result == 10);
    assert(vm_step(&dispatch_a_ctx) == 0 && dispatch_a_ctx.quit);

    /* Dispatch B: print an inline string, then a newline. Exercises
     * 0OP print's reuse of ztext_decode and the emit callback. */
    dispatch_b_image[0] = 0xb2;                 /* print "hi" */
    dispatch_b_image[1] = 0x35;
    dispatch_b_image[2] = 0xc5;
    dispatch_b_image[3] = 0x94;
    dispatch_b_image[4] = 0xa5;
    dispatch_b_image[5] = 0xbb;                 /* new_line */
    dispatch_b_image[6] = 0xba;                 /* quit */

    assert(story_mem_init(&dispatch_b_memory, dispatch_b_image,
                          sizeof(dispatch_b_image),
                          sizeof(dispatch_b_image)) == 0);
    vm_state_init(&dispatch_b_state, 0, 0);
    dispatch_b_ctx.memory = &dispatch_b_memory;
    dispatch_b_ctx.state = &dispatch_b_state;
    dispatch_b_ctx.object_table = 0;
    dispatch_b_ctx.emit = append_char;
    dispatch_b_ctx.emit_context = dispatch_b_text;
    dispatch_b_ctx.quit = 0;

    assert(vm_step(&dispatch_b_ctx) == 0);
    assert(vm_step(&dispatch_b_ctx) == 0);
    assert(vm_step(&dispatch_b_ctx) == 0 && dispatch_b_ctx.quit);
    assert(strcmp(dispatch_b_text, "hi\n") == 0);

    /* Dispatch C: je taken (skips the next instruction) and je not
     * taken (falls through normally). Exercises branching and the
     * "store"opcode's own indirect variable-number operand. */
    dispatch_c_image[0x90] = 0x01;              /* je 5,5 ?+5 */
    dispatch_c_image[0x91] = 5;
    dispatch_c_image[0x92] = 5;
    dispatch_c_image[0x93] = 0xc5;
    dispatch_c_image[0x94] = 0x0d;              /* store global16,99 --
                                                 * skipped by the branch */
    dispatch_c_image[0x95] = 0x10;
    dispatch_c_image[0x96] = 99;
    dispatch_c_image[0x97] = 0x0d;              /* store global17,1 --
                                                 * the branch lands here */
    dispatch_c_image[0x98] = 0x11;
    dispatch_c_image[0x99] = 1;
    dispatch_c_image[0x9a] = 0x01;              /* je 5,6 ?+5 (false:
                                                 * falls through) */
    dispatch_c_image[0x9b] = 5;
    dispatch_c_image[0x9c] = 6;
    dispatch_c_image[0x9d] = 0xc5;
    dispatch_c_image[0x9e] = 0x0d;              /* store global18,1 */
    dispatch_c_image[0x9f] = 0x12;
    dispatch_c_image[0xa0] = 1;
    dispatch_c_image[0xa1] = 0xba;              /* quit */

    assert(story_mem_init(&dispatch_c_memory, dispatch_c_image,
                          sizeof(dispatch_c_image),
                          sizeof(dispatch_c_image)) == 0);
    vm_state_init(&dispatch_c_state, 0, 0x90);
    dispatch_c_ctx.memory = &dispatch_c_memory;
    dispatch_c_ctx.state = &dispatch_c_state;
    dispatch_c_ctx.object_table = 0;
    dispatch_c_ctx.emit = 0;
    dispatch_c_ctx.emit_context = 0;
    dispatch_c_ctx.quit = 0;

    assert(vm_step(&dispatch_c_ctx) == 0 && dispatch_c_state.pc == 0x97);
    assert(vm_step(&dispatch_c_ctx) == 0 && dispatch_c_state.pc == 0x9a);
    assert(vm_step(&dispatch_c_ctx) == 0 && dispatch_c_state.pc == 0x9e);
    assert(vm_step(&dispatch_c_ctx) == 0 && dispatch_c_state.pc == 0xa1);
    assert(vm_step(&dispatch_c_ctx) == 0 && dispatch_c_ctx.quit);
    assert(story_mem_read16(&dispatch_c_memory, 0, &dispatch_c_g0) == 0 &&
        dispatch_c_g0 == 0);
    assert(story_mem_read16(&dispatch_c_memory, 2, &dispatch_c_g1) == 0 &&
        dispatch_c_g1 == 1);
    assert(story_mem_read16(&dispatch_c_memory, 4, &dispatch_c_g2) == 0 &&
        dispatch_c_g2 == 1);

    /* Dispatch D: object tree + attributes. Same object-1/2/3 layout as
     * the top-of-file object/property tests, in a fresh image. Exercises
     * set_attr/test_attr (with its branch), insert_obj, get_parent, and
     * get_child (with its own store+branch). All bytes hand-derived
     * (variable form throughout: 0xC0|opcode for 2OP, type byte 0x5f =
     * small,small,omitted,omitted) and cross-checked against a scratch
     * harness driving the real vm_step before being copied here. */
    dispatch_d_image[68] = 2;                  /* object 1: child = 2 */
    dispatch_d_image[70] = 0x64;               /* object 1: proptable @ 100 */
    dispatch_d_image[75] = 1;                  /* object 2: parent = 1 */
    dispatch_d_image[76] = 3;                  /* object 2: sibling = 3 */
    dispatch_d_image[79] = 0x6e;               /* object 2: proptable @ 110 */
    dispatch_d_image[84] = 1;                  /* object 3: parent = 1 */
    dispatch_d_image[88] = 0x73;               /* object 3: proptable @ 115 */
    dispatch_d_image[100] = 0;                 /* object 1: empty proplist */
    dispatch_d_image[110] = 0;                 /* object 2: empty proplist */
    dispatch_d_image[115] = 0;                 /* object 3: empty proplist */

    dispatch_d_image[0x90] = 0xcb;             /* set_attr 1,3 */
    dispatch_d_image[0x91] = 0x5f;
    dispatch_d_image[0x92] = 1;
    dispatch_d_image[0x93] = 3;
    dispatch_d_image[0x94] = 0xca;             /* test_attr 1,3 ?+6 */
    dispatch_d_image[0x95] = 0x5f;
    dispatch_d_image[0x96] = 1;
    dispatch_d_image[0x97] = 3;
    dispatch_d_image[0x98] = 0xc6;
    dispatch_d_image[0x99] = 0xcd;             /* store g16,99 -- skipped */
    dispatch_d_image[0x9a] = 0x5f;
    dispatch_d_image[0x9b] = 0x10;
    dispatch_d_image[0x9c] = 99;
    dispatch_d_image[0x9d] = 0xcd;             /* store g17,1 -- branch lands here */
    dispatch_d_image[0x9e] = 0x5f;
    dispatch_d_image[0x9f] = 0x11;
    dispatch_d_image[0xa0] = 1;
    dispatch_d_image[0xa1] = 0xce;             /* insert_obj 3,2 */
    dispatch_d_image[0xa2] = 0x5f;
    dispatch_d_image[0xa3] = 3;
    dispatch_d_image[0xa4] = 2;
    dispatch_d_image[0xa5] = 0x93;             /* get_parent 3 -> g18 */
    dispatch_d_image[0xa6] = 3;
    dispatch_d_image[0xa7] = 0x12;
    dispatch_d_image[0xa8] = 0x92;             /* get_child 2 ?+2 -> g19 */
    dispatch_d_image[0xa9] = 2;
    dispatch_d_image[0xaa] = 0x13;
    dispatch_d_image[0xab] = 0xc2;
    dispatch_d_image[0xac] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_d_memory, dispatch_d_image,
                          sizeof(dispatch_d_image),
                          sizeof(dispatch_d_image)) == 0);
    vm_state_init(&dispatch_d_state, 0, 0x90);
    dispatch_d_ctx.memory = &dispatch_d_memory;
    dispatch_d_ctx.state = &dispatch_d_state;
    dispatch_d_ctx.object_table = 0;
    dispatch_d_ctx.emit = 0;
    dispatch_d_ctx.emit_context = 0;
    dispatch_d_ctx.quit = 0;

    assert(vm_step(&dispatch_d_ctx) == 0 && dispatch_d_state.pc == 0x94);
    assert(vm_step(&dispatch_d_ctx) == 0 && dispatch_d_state.pc == 0x9d);
    assert(vm_step(&dispatch_d_ctx) == 0 && dispatch_d_state.pc == 0xa1);
    assert(vm_step(&dispatch_d_ctx) == 0 && dispatch_d_state.pc == 0xa5);
    assert(vm_step(&dispatch_d_ctx) == 0 && dispatch_d_state.pc == 0xa8);
    assert(vm_step(&dispatch_d_ctx) == 0 && dispatch_d_state.pc == 0xac);
    assert(vm_step(&dispatch_d_ctx) == 0 && dispatch_d_ctx.quit);
    assert(story_mem_read16(&dispatch_d_memory, 0, &dispatch_d_g16) == 0 &&
        dispatch_d_g16 == 0);
    assert(story_mem_read16(&dispatch_d_memory, 2, &dispatch_d_g17) == 0 &&
        dispatch_d_g17 == 1);
    assert(story_mem_read16(&dispatch_d_memory, 4, &dispatch_d_g18) == 0 &&
        dispatch_d_g18 == 2);           /* object 3's parent is now 2 */
    assert(story_mem_read16(&dispatch_d_memory, 6, &dispatch_d_g19) == 0 &&
        dispatch_d_g19 == 3);           /* object 2's child is now 3 */

    /* Dispatch E: properties. Object 1 has property 5 (len 1, =0x99)
     * and property 3 (len 2, =0x1234), same layout as the top-of-file
     * property tests. Exercises get_prop, put_prop, get_prop_addr, and
     * get_next_prop. */
    dispatch_e_image[70] = 0x64;               /* object 1: proptable @ 100 */
    dispatch_e_image[100] = 0;                 /* no short name */
    dispatch_e_image[101] = 0x05;              /* property 5, len 1 */
    dispatch_e_image[102] = 0x99;
    dispatch_e_image[103] = 0x23;              /* property 3, len 2 */
    dispatch_e_image[104] = 0x12;
    dispatch_e_image[105] = 0x34;
    dispatch_e_image[106] = 0x00;              /* end of properties */

    dispatch_e_image[0x90] = 0xd1;             /* get_prop 1,5 -> g16 */
    dispatch_e_image[0x91] = 0x5f;
    dispatch_e_image[0x92] = 1;
    dispatch_e_image[0x93] = 5;
    dispatch_e_image[0x94] = 0x10;
    dispatch_e_image[0x95] = 0xe3;             /* put_prop 1,5,0x55 */
    dispatch_e_image[0x96] = 0x53;
    dispatch_e_image[0x97] = 1;
    dispatch_e_image[0x98] = 5;
    dispatch_e_image[0x99] = 0x00;
    dispatch_e_image[0x9a] = 0x55;
    dispatch_e_image[0x9b] = 0xd1;             /* get_prop 1,5 -> g17 */
    dispatch_e_image[0x9c] = 0x5f;
    dispatch_e_image[0x9d] = 1;
    dispatch_e_image[0x9e] = 5;
    dispatch_e_image[0x9f] = 0x11;
    dispatch_e_image[0xa0] = 0xd2;             /* get_prop_addr 1,3 -> g18 */
    dispatch_e_image[0xa1] = 0x5f;
    dispatch_e_image[0xa2] = 1;
    dispatch_e_image[0xa3] = 3;
    dispatch_e_image[0xa4] = 0x12;
    dispatch_e_image[0xa5] = 0xd3;             /* get_next_prop 1,0 -> g19 */
    dispatch_e_image[0xa6] = 0x5f;
    dispatch_e_image[0xa7] = 1;
    dispatch_e_image[0xa8] = 0;
    dispatch_e_image[0xa9] = 0x13;
    dispatch_e_image[0xaa] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_e_memory, dispatch_e_image,
                          sizeof(dispatch_e_image),
                          sizeof(dispatch_e_image)) == 0);
    vm_state_init(&dispatch_e_state, 0, 0x90);
    dispatch_e_ctx.memory = &dispatch_e_memory;
    dispatch_e_ctx.state = &dispatch_e_state;
    dispatch_e_ctx.object_table = 0;
    dispatch_e_ctx.emit = 0;
    dispatch_e_ctx.emit_context = 0;
    dispatch_e_ctx.quit = 0;

    assert(vm_step(&dispatch_e_ctx) == 0 && dispatch_e_state.pc == 0x95);
    assert(vm_step(&dispatch_e_ctx) == 0 && dispatch_e_state.pc == 0x9b);
    assert(vm_step(&dispatch_e_ctx) == 0 && dispatch_e_state.pc == 0xa0);
    assert(vm_step(&dispatch_e_ctx) == 0 && dispatch_e_state.pc == 0xa5);
    assert(vm_step(&dispatch_e_ctx) == 0 && dispatch_e_state.pc == 0xaa);
    assert(vm_step(&dispatch_e_ctx) == 0 && dispatch_e_ctx.quit);
    assert(story_mem_read16(&dispatch_e_memory, 0, &dispatch_e_g16) == 0 &&
        dispatch_e_g16 == 0x99);
    assert(story_mem_read16(&dispatch_e_memory, 2, &dispatch_e_g17) == 0 &&
        dispatch_e_g17 == 0x55);
    assert(story_mem_read16(&dispatch_e_memory, 4, &dispatch_e_g18) == 0 &&
        dispatch_e_g18 == 104);
    assert(story_mem_read16(&dispatch_e_memory, 6, &dispatch_e_g19) == 0 &&
        dispatch_e_g19 == 5);

    /* Dispatch F: memory access. Exercises storew/loadw and
     * storeb/loadb against the same base address. */
    dispatch_f_image[0x20] = 0xe1;             /* storew 0,2,0x1234 */
    dispatch_f_image[0x21] = 0x53;
    dispatch_f_image[0x22] = 0;
    dispatch_f_image[0x23] = 2;
    dispatch_f_image[0x24] = 0x12;
    dispatch_f_image[0x25] = 0x34;
    dispatch_f_image[0x26] = 0xcf;             /* loadw 0,2 -> g16 */
    dispatch_f_image[0x27] = 0x5f;
    dispatch_f_image[0x28] = 0;
    dispatch_f_image[0x29] = 2;
    dispatch_f_image[0x2a] = 0x10;
    dispatch_f_image[0x2b] = 0xe2;             /* storeb 0,9,0x42 */
    dispatch_f_image[0x2c] = 0x57;
    dispatch_f_image[0x2d] = 0;
    dispatch_f_image[0x2e] = 9;
    dispatch_f_image[0x2f] = 0x42;
    dispatch_f_image[0x30] = 0xd0;             /* loadb 0,9 -> g17 */
    dispatch_f_image[0x31] = 0x5f;
    dispatch_f_image[0x32] = 0;
    dispatch_f_image[0x33] = 9;
    dispatch_f_image[0x34] = 0x11;
    dispatch_f_image[0x35] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_f_memory, dispatch_f_image,
                          sizeof(dispatch_f_image),
                          sizeof(dispatch_f_image)) == 0);
    vm_state_init(&dispatch_f_state, 0, 0x20);
    dispatch_f_ctx.memory = &dispatch_f_memory;
    dispatch_f_ctx.state = &dispatch_f_state;
    dispatch_f_ctx.object_table = 0;
    dispatch_f_ctx.emit = 0;
    dispatch_f_ctx.emit_context = 0;
    dispatch_f_ctx.quit = 0;

    assert(vm_step(&dispatch_f_ctx) == 0 && dispatch_f_state.pc == 0x26);
    assert(vm_step(&dispatch_f_ctx) == 0 && dispatch_f_state.pc == 0x2b);
    assert(vm_step(&dispatch_f_ctx) == 0 && dispatch_f_state.pc == 0x30);
    assert(vm_step(&dispatch_f_ctx) == 0 && dispatch_f_state.pc == 0x35);
    assert(vm_step(&dispatch_f_ctx) == 0 && dispatch_f_ctx.quit);
    assert(story_mem_read16(&dispatch_f_memory, 0, &dispatch_f_g16) == 0 &&
        dispatch_f_g16 == 0x1234);
    assert(story_mem_read16(&dispatch_f_memory, 2, &dispatch_f_g17) == 0 &&
        dispatch_f_g17 == 0x42);

    /* Dispatch G: stack/variable-indirect ops and arithmetic. Exercises
     * push/pull, inc/dec_chk (both using their variable-NUMBER operand
     * indirectly), and mul/div/mod. */
    dispatch_g_image[0x20] = 0xe8;             /* push 0x77 */
    dispatch_g_image[0x21] = 0x7f;
    dispatch_g_image[0x22] = 0x77;
    dispatch_g_image[0x23] = 0xe9;             /* pull 16 */
    dispatch_g_image[0x24] = 0x7f;
    dispatch_g_image[0x25] = 0x10;
    dispatch_g_image[0x26] = 0xcd;             /* store g17,5 */
    dispatch_g_image[0x27] = 0x5f;
    dispatch_g_image[0x28] = 0x11;
    dispatch_g_image[0x29] = 5;
    dispatch_g_image[0x2a] = 0x95;             /* inc 17 (-> 6) */
    dispatch_g_image[0x2b] = 0x11;
    dispatch_g_image[0x2c] = 0xc4;             /* dec_chk 17,10 ?+6 (-> 5, 5<10 true) */
    dispatch_g_image[0x2d] = 0x5f;
    dispatch_g_image[0x2e] = 0x11;
    dispatch_g_image[0x2f] = 10;
    dispatch_g_image[0x30] = 0xc6;
    dispatch_g_image[0x31] = 0xcd;             /* store g18,99 -- skipped */
    dispatch_g_image[0x32] = 0x5f;
    dispatch_g_image[0x33] = 0x12;
    dispatch_g_image[0x34] = 99;
    dispatch_g_image[0x35] = 0xcd;             /* store g19,1 -- branch lands here */
    dispatch_g_image[0x36] = 0x5f;
    dispatch_g_image[0x37] = 0x13;
    dispatch_g_image[0x38] = 1;
    dispatch_g_image[0x39] = 0xd6;             /* mul 6,7 -> g20 */
    dispatch_g_image[0x3a] = 0x5f;
    dispatch_g_image[0x3b] = 6;
    dispatch_g_image[0x3c] = 7;
    dispatch_g_image[0x3d] = 0x14;
    dispatch_g_image[0x3e] = 0xd7;             /* div 20,6 -> g21 */
    dispatch_g_image[0x3f] = 0x5f;
    dispatch_g_image[0x40] = 20;
    dispatch_g_image[0x41] = 6;
    dispatch_g_image[0x42] = 0x15;
    dispatch_g_image[0x43] = 0xd8;             /* mod 20,6 -> g22 */
    dispatch_g_image[0x44] = 0x5f;
    dispatch_g_image[0x45] = 20;
    dispatch_g_image[0x46] = 6;
    dispatch_g_image[0x47] = 0x16;
    dispatch_g_image[0x48] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_g_memory, dispatch_g_image,
                          sizeof(dispatch_g_image),
                          sizeof(dispatch_g_image)) == 0);
    vm_state_init(&dispatch_g_state, 0, 0x20);
    dispatch_g_ctx.memory = &dispatch_g_memory;
    dispatch_g_ctx.state = &dispatch_g_state;
    dispatch_g_ctx.object_table = 0;
    dispatch_g_ctx.emit = 0;
    dispatch_g_ctx.emit_context = 0;
    dispatch_g_ctx.quit = 0;

    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x23);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x26);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x2a);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x2c);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x35);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x39);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x3e);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x43);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_state.pc == 0x48);
    assert(vm_step(&dispatch_g_ctx) == 0 && dispatch_g_ctx.quit);
    assert(story_mem_read16(&dispatch_g_memory, 0, &dispatch_g_g16) == 0 &&
        dispatch_g_g16 == 0x77);
    assert(story_mem_read16(&dispatch_g_memory, 2, &dispatch_g_g17) == 0 &&
        dispatch_g_g17 == 5);
    assert(story_mem_read16(&dispatch_g_memory, 4, &dispatch_g_g18) == 0 &&
        dispatch_g_g18 == 0);
    assert(story_mem_read16(&dispatch_g_memory, 6, &dispatch_g_g19) == 0 &&
        dispatch_g_g19 == 1);
    assert(story_mem_read16(&dispatch_g_memory, 8, &dispatch_g_g20) == 0 &&
        dispatch_g_g20 == 42);
    assert(story_mem_read16(&dispatch_g_memory, 10, &dispatch_g_g21) == 0 &&
        dispatch_g_g21 == 3);
    assert(story_mem_read16(&dispatch_g_memory, 12, &dispatch_g_g22) == 0 &&
        dispatch_g_g22 == 2);

    /* Dispatch H: text. print_char, print_num, print_addr, and
     * print_paddr -- the last two both targeting the same "hi" bytes
     * reused from the ztext_decode test (byte address 8, packed
     * address 4). */
    dispatch_h_image[8] = 0x35;
    dispatch_h_image[9] = 0xc5;
    dispatch_h_image[10] = 0x94;
    dispatch_h_image[11] = 0xa5;

    dispatch_h_image[0x20] = 0xe5;             /* print_char 'A' */
    dispatch_h_image[0x21] = 0x7f;
    dispatch_h_image[0x22] = 'A';
    dispatch_h_image[0x23] = 0xe6;             /* print_num 42 */
    dispatch_h_image[0x24] = 0x7f;
    dispatch_h_image[0x25] = 42;
    dispatch_h_image[0x26] = 0x97;             /* print_addr 8 */
    dispatch_h_image[0x27] = 8;
    dispatch_h_image[0x28] = 0x9d;             /* print_paddr 4 */
    dispatch_h_image[0x29] = 4;
    dispatch_h_image[0x2a] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_h_memory, dispatch_h_image,
                          sizeof(dispatch_h_image),
                          sizeof(dispatch_h_image)) == 0);
    vm_state_init(&dispatch_h_state, 0, 0x20);
    dispatch_h_ctx.memory = &dispatch_h_memory;
    dispatch_h_ctx.state = &dispatch_h_state;
    dispatch_h_ctx.object_table = 0;
    dispatch_h_ctx.emit = append_char;
    dispatch_h_ctx.emit_context = dispatch_h_text;
    dispatch_h_ctx.quit = 0;

    assert(vm_step(&dispatch_h_ctx) == 0);
    assert(vm_step(&dispatch_h_ctx) == 0);
    assert(vm_step(&dispatch_h_ctx) == 0);
    assert(vm_step(&dispatch_h_ctx) == 0);
    assert(vm_step(&dispatch_h_ctx) == 0 && dispatch_h_ctx.quit);
    assert(strcmp(dispatch_h_text, "A42hihi") == 0);

    /* Dispatch I: random. A negative range reseeds the PRNG to a
     * value derived from the range itself, giving a repeatable
     * sequence -- the exact draws below were captured from this same
     * vm_random implementation via a scratch harness, not guessed.
     * random(0) also reseeds (unpredictably, from the wall clock) and
     * returns 0, which is the one thing about it this test can still
     * check deterministically. */
    dispatch_i_image[0x20] = 0xe7;             /* random(-999) -> g16 */
    dispatch_i_image[0x21] = 0x3f;             /* type: large,omit,omit,omit */
    dispatch_i_image[0x22] = 0xfc;
    dispatch_i_image[0x23] = 0x19;
    dispatch_i_image[0x24] = 0x10;
    dispatch_i_image[0x25] = 0xe7;             /* random(6) -> g17 */
    dispatch_i_image[0x26] = 0x7f;
    dispatch_i_image[0x27] = 6;
    dispatch_i_image[0x28] = 0x11;
    dispatch_i_image[0x29] = 0xe7;             /* random(6) -> g18 */
    dispatch_i_image[0x2a] = 0x7f;
    dispatch_i_image[0x2b] = 6;
    dispatch_i_image[0x2c] = 0x12;
    dispatch_i_image[0x2d] = 0xe7;             /* random(6) -> g19 */
    dispatch_i_image[0x2e] = 0x7f;
    dispatch_i_image[0x2f] = 6;
    dispatch_i_image[0x30] = 0x13;
    dispatch_i_image[0x31] = 0xe7;             /* random(0) -> g20 */
    dispatch_i_image[0x32] = 0x7f;
    dispatch_i_image[0x33] = 0;
    dispatch_i_image[0x34] = 0x14;
    dispatch_i_image[0x35] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_i_memory, dispatch_i_image,
                          sizeof(dispatch_i_image),
                          sizeof(dispatch_i_image)) == 0);
    vm_state_init(&dispatch_i_state, 0, 0x20);
    dispatch_i_ctx.memory = &dispatch_i_memory;
    dispatch_i_ctx.state = &dispatch_i_state;
    dispatch_i_ctx.object_table = 0;
    dispatch_i_ctx.dictionary_table = 0;
    dispatch_i_ctx.emit = 0;
    dispatch_i_ctx.emit_context = 0;
    dispatch_i_ctx.read_line = 0;
    dispatch_i_ctx.read_line_context = 0;
    dispatch_i_ctx.quit = 0;

    assert(vm_step(&dispatch_i_ctx) == 0 && dispatch_i_state.pc == 0x25);
    assert(vm_step(&dispatch_i_ctx) == 0 && dispatch_i_state.pc == 0x29);
    assert(vm_step(&dispatch_i_ctx) == 0 && dispatch_i_state.pc == 0x2d);
    assert(vm_step(&dispatch_i_ctx) == 0 && dispatch_i_state.pc == 0x31);
    assert(vm_step(&dispatch_i_ctx) == 0 && dispatch_i_state.pc == 0x35);
    assert(vm_step(&dispatch_i_ctx) == 0 && dispatch_i_ctx.quit);
    assert(story_mem_read16(&dispatch_i_memory, 0, &dispatch_i_g16) == 0 &&
        dispatch_i_g16 == 0);
    assert(story_mem_read16(&dispatch_i_memory, 2, &dispatch_i_g17) == 0 &&
        dispatch_i_g17 == 2);
    assert(story_mem_read16(&dispatch_i_memory, 4, &dispatch_i_g18) == 0 &&
        dispatch_i_g18 == 1);
    assert(story_mem_read16(&dispatch_i_memory, 6, &dispatch_i_g19) == 0 &&
        dispatch_i_g19 == 3);
    assert(story_mem_read16(&dispatch_i_memory, 8, &dispatch_i_g20) == 0 &&
        dispatch_i_g20 == 0);

    /* Dispatch J: sread. Same dictionary layout as the top-of-file
     * dictionary test (1 separator, 7-byte entries: cat/dog/run).
     * fixed_read_line hands back "Take cat" -- sread must lowercase
     * it before tokenizing, and "take" isn't in the dictionary while
     * "cat" is. */
    dispatch_j_image[0] = 1;
    dispatch_j_image[1] = ',';
    dispatch_j_image[2] = 7;
    dispatch_j_image[3] = 0x00;
    dispatch_j_image[4] = 0x03;
    assert(ztext_encode("cat", 3, &dispatch_j_image[5]) == 0);
    dispatch_j_image[9] = 0xaa;
    dispatch_j_image[10] = 0xbb;
    dispatch_j_image[11] = 0xcc;
    assert(ztext_encode("dog", 3, &dispatch_j_image[12]) == 0);
    dispatch_j_image[16] = 0xdd;
    dispatch_j_image[17] = 0xee;
    dispatch_j_image[18] = 0xff;
    assert(ztext_encode("run", 3, &dispatch_j_image[19]) == 0);
    dispatch_j_image[23] = 0x11;
    dispatch_j_image[24] = 0x22;
    dispatch_j_image[25] = 0x33;

    dispatch_j_image[0x50] = 20;               /* text buffer: max length 20 */
    dispatch_j_image[0x70] = 10;               /* parse buffer: max words 10 */

    dispatch_j_image[0x20] = 0xe4;             /* sread 0x50,0x70 */
    dispatch_j_image[0x21] = 0x5f;
    dispatch_j_image[0x22] = 0x50;
    dispatch_j_image[0x23] = 0x70;
    dispatch_j_image[0x24] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_j_memory, dispatch_j_image,
                          sizeof(dispatch_j_image),
                          sizeof(dispatch_j_image)) == 0);
    vm_state_init(&dispatch_j_state, 0, 0x20);
    dispatch_j_ctx.memory = &dispatch_j_memory;
    dispatch_j_ctx.state = &dispatch_j_state;
    dispatch_j_ctx.object_table = 0;
    dispatch_j_ctx.dictionary_table = 0;
    dispatch_j_ctx.emit = 0;
    dispatch_j_ctx.emit_context = 0;
    dispatch_j_ctx.read_line = fixed_read_line;
    dispatch_j_ctx.read_line_context = (void *)"Take cat";
    dispatch_j_ctx.quit = 0;

    assert(vm_step(&dispatch_j_ctx) == 0 && dispatch_j_state.pc == 0x24);
    assert(vm_step(&dispatch_j_ctx) == 0 && dispatch_j_ctx.quit);

    assert(memcmp(&dispatch_j_image[0x51], "take cat", 8) == 0);
    assert(dispatch_j_image[0x59] == 0);       /* zero terminator */
    assert(dispatch_j_image[0x71] == 2);       /* word count */
    /* word 0: "take" -- not in the dictionary */
    assert(story_mem_read16(&dispatch_j_memory, 0x72, &word) == 0 &&
        word == 0);
    assert(story_mem_read8(&dispatch_j_memory, 0x74, &dispatch_j_byte) == 0 &&
        dispatch_j_byte == 4);
    assert(story_mem_read8(&dispatch_j_memory, 0x75, &dispatch_j_byte) == 0 &&
        dispatch_j_byte == 1);
    /* word 1: "cat" -- found at dictionary offset 5 */
    assert(story_mem_read16(&dispatch_j_memory, 0x76, &word) == 0 &&
        word == 5);
    assert(story_mem_read8(&dispatch_j_memory, 0x78, &dispatch_j_byte) == 0 &&
        dispatch_j_byte == 3);
    assert(story_mem_read8(&dispatch_j_memory, 0x79, &dispatch_j_byte) == 0 &&
        dispatch_j_byte == 6);

    /* Dispatch K: save/restore round trip. save's branch (taken on
     * success, per the V1-3 encoding) skips a "store g16,99" and
     * lands on "store g17,1" -- that landing point is "the point
     * where it was saved". A later "store g16,2" then mutates memory;
     * restore hands back the saved snapshot, which un-mutates g16 and
     * re-enters execution at the landing point (running "store
     * g17,1" a second time), never taking its own branch, per "the
     * branch is never actually made". */
    dispatch_k_image[0x20] = 0xcd;             /* store g16,1 */
    dispatch_k_image[0x21] = 0x5f;
    dispatch_k_image[0x22] = 0x10;
    dispatch_k_image[0x23] = 1;
    dispatch_k_image[0x24] = 0xb5;             /* save ?+6 */
    dispatch_k_image[0x25] = 0xc6;
    dispatch_k_image[0x26] = 0xcd;             /* store g16,99 -- skipped */
    dispatch_k_image[0x27] = 0x5f;
    dispatch_k_image[0x28] = 0x10;
    dispatch_k_image[0x29] = 99;
    dispatch_k_image[0x2a] = 0xcd;             /* store g17,1 -- save's
                                                * resumption point */
    dispatch_k_image[0x2b] = 0x5f;
    dispatch_k_image[0x2c] = 0x11;
    dispatch_k_image[0x2d] = 1;
    dispatch_k_image[0x2e] = 0xcd;             /* store g16,2 -- mutate
                                                * after save */
    dispatch_k_image[0x2f] = 0x5f;
    dispatch_k_image[0x30] = 0x10;
    dispatch_k_image[0x31] = 2;
    dispatch_k_image[0x32] = 0xb6;             /* restore */
    dispatch_k_image[0x33] = 0xba;             /* quit -- only reached
                                                * if restore fails */

    assert(story_mem_init(&dispatch_k_memory, dispatch_k_image,
                          sizeof(dispatch_k_image),
                          sizeof(dispatch_k_image)) == 0);
    vm_state_init(&dispatch_k_state, 0, 0x20);
    dispatch_k_ctx.memory = &dispatch_k_memory;
    dispatch_k_ctx.state = &dispatch_k_state;
    dispatch_k_ctx.object_table = 0;
    dispatch_k_ctx.dictionary_table = 0;
    dispatch_k_ctx.emit = 0;
    dispatch_k_ctx.emit_context = 0;
    dispatch_k_ctx.output_table_active = 0;
    dispatch_k_ctx.read_line = 0;
    dispatch_k_ctx.read_line_context = 0;
    dispatch_k_slot.used = 0;
    dispatch_k_ctx.save = dispatch_do_save;
    dispatch_k_ctx.save_context = &dispatch_k_slot;
    dispatch_k_ctx.restore = dispatch_do_restore;
    dispatch_k_ctx.restore_context = &dispatch_k_slot;
    dispatch_k_ctx.restart = 0;
    dispatch_k_ctx.restart_context = 0;
    dispatch_k_ctx.quit = 0;

    assert(vm_step(&dispatch_k_ctx) == 0 && dispatch_k_state.pc == 0x24);
    assert(vm_step(&dispatch_k_ctx) == 0 && dispatch_k_state.pc == 0x2a);
    assert(vm_step(&dispatch_k_ctx) == 0 && dispatch_k_state.pc == 0x2e);
    assert(vm_step(&dispatch_k_ctx) == 0 && dispatch_k_state.pc == 0x32);
    assert(vm_step(&dispatch_k_ctx) == 0 && dispatch_k_state.pc == 0x2a);
    assert(vm_step(&dispatch_k_ctx) == 0 && dispatch_k_state.pc == 0x2e);
    assert(!dispatch_k_ctx.quit);
    assert(story_mem_read16(&dispatch_k_memory, 0, &dispatch_k_g16) == 0 &&
        dispatch_k_g16 == 1);              /* the mutation to 2 was undone */
    assert(story_mem_read16(&dispatch_k_memory, 2, &dispatch_k_g17) == 0 &&
        dispatch_k_g17 == 1);

    /* Dispatch L: restart resets both dynamic memory and pc to their
     * initial values. */
    dispatch_l_image[0x20] = 0xcd;             /* store g16,42 */
    dispatch_l_image[0x21] = 0x5f;
    dispatch_l_image[0x22] = 0x10;
    dispatch_l_image[0x23] = 42;
    dispatch_l_image[0x24] = 0xb7;             /* restart */

    memcpy(dispatch_l_pristine, dispatch_l_image, sizeof(dispatch_l_image));
    assert(story_mem_init(&dispatch_l_memory, dispatch_l_image,
                          sizeof(dispatch_l_image),
                          sizeof(dispatch_l_image)) == 0);
    vm_state_init(&dispatch_l_state, 0, 0x20);
    dispatch_l_ctx.memory = &dispatch_l_memory;
    dispatch_l_ctx.state = &dispatch_l_state;
    dispatch_l_ctx.object_table = 0;
    dispatch_l_ctx.dictionary_table = 0;
    dispatch_l_ctx.emit = 0;
    dispatch_l_ctx.emit_context = 0;
    dispatch_l_ctx.output_table_active = 0;
    dispatch_l_ctx.read_line = 0;
    dispatch_l_ctx.read_line_context = 0;
    dispatch_l_ctx.save = 0;
    dispatch_l_ctx.save_context = 0;
    dispatch_l_ctx.restore = 0;
    dispatch_l_ctx.restore_context = 0;
    dispatch_l_slot.used = 1;
    vm_state_init(&dispatch_l_slot.state, 0, 0x20);
    memcpy(dispatch_l_slot.dynamic_memory, dispatch_l_pristine,
          sizeof(dispatch_l_pristine));
    dispatch_l_slot.dynamic_length = sizeof(dispatch_l_pristine);
    dispatch_l_ctx.restart = dispatch_do_restore;
    dispatch_l_ctx.restart_context = &dispatch_l_slot;
    dispatch_l_ctx.quit = 0;

    assert(vm_step(&dispatch_l_ctx) == 0 && dispatch_l_state.pc == 0x24);
    assert(story_mem_read16(&dispatch_l_memory, 0, &dispatch_l_g16) == 0 &&
        dispatch_l_g16 == 42);
    assert(vm_step(&dispatch_l_ctx) == 0 && dispatch_l_state.pc == 0x20);
    assert(story_mem_read16(&dispatch_l_memory, 0, &dispatch_l_g16) == 0 &&
        dispatch_l_g16 == 0);              /* dynamic memory reset too */

    /* Dispatch M: output_stream redirects print output into a memory
     * table (stream 3) and back to the screen (stream -3); show_status
     * is a no-op in this portable core. The table lives at 0x50, well
     * clear of the program bytes below. */
    dispatch_m_image[0x20] = 0xf3;             /* output_stream 3,0x50 */
    dispatch_m_image[0x21] = 0x5f;
    dispatch_m_image[0x22] = 3;
    dispatch_m_image[0x23] = 0x50;
    dispatch_m_image[0x24] = 0xe5;             /* print_char 'h' */
    dispatch_m_image[0x25] = 0x7f;
    dispatch_m_image[0x26] = 'h';
    dispatch_m_image[0x27] = 0xe5;             /* print_char 'i' */
    dispatch_m_image[0x28] = 0x7f;
    dispatch_m_image[0x29] = 'i';
    dispatch_m_image[0x2a] = 0xf3;             /* output_stream -3 */
    dispatch_m_image[0x2b] = 0x3f;
    dispatch_m_image[0x2c] = 0xff;
    dispatch_m_image[0x2d] = 0xfd;
    dispatch_m_image[0x2e] = 0xe5;             /* print_char 'X' */
    dispatch_m_image[0x2f] = 0x7f;
    dispatch_m_image[0x30] = 'X';
    dispatch_m_image[0x31] = 0xbc;             /* show_status */
    dispatch_m_image[0x32] = 0xba;             /* quit */

    assert(story_mem_init(&dispatch_m_memory, dispatch_m_image,
                          sizeof(dispatch_m_image),
                          sizeof(dispatch_m_image)) == 0);
    vm_state_init(&dispatch_m_state, 0, 0x20);
    dispatch_m_ctx.memory = &dispatch_m_memory;
    dispatch_m_ctx.state = &dispatch_m_state;
    dispatch_m_ctx.object_table = 0;
    dispatch_m_ctx.dictionary_table = 0;
    dispatch_m_ctx.emit = append_char;
    dispatch_m_ctx.emit_context = dispatch_m_text;
    dispatch_m_ctx.output_table_active = 0;
    dispatch_m_ctx.read_line = 0;
    dispatch_m_ctx.read_line_context = 0;
    dispatch_m_ctx.save = 0;
    dispatch_m_ctx.save_context = 0;
    dispatch_m_ctx.restore = 0;
    dispatch_m_ctx.restore_context = 0;
    dispatch_m_ctx.restart = 0;
    dispatch_m_ctx.restart_context = 0;
    dispatch_m_ctx.quit = 0;

    assert(vm_step(&dispatch_m_ctx) == 0 && dispatch_m_state.pc == 0x24);
    assert(vm_step(&dispatch_m_ctx) == 0 && dispatch_m_state.pc == 0x27);
    assert(vm_step(&dispatch_m_ctx) == 0 && dispatch_m_state.pc == 0x2a);
    assert(vm_step(&dispatch_m_ctx) == 0 && dispatch_m_state.pc == 0x2e);
    assert(vm_step(&dispatch_m_ctx) == 0 && dispatch_m_state.pc == 0x31);
    assert(vm_step(&dispatch_m_ctx) == 0 && dispatch_m_state.pc == 0x32);
    assert(vm_step(&dispatch_m_ctx) == 0 && dispatch_m_ctx.quit);
    assert(strcmp(dispatch_m_text, "X") == 0);     /* only the un-redirected
                                                    * print_char reached
                                                    * the screen */
    assert(story_mem_read16(&dispatch_m_memory, 0x50, &dispatch_m_table_len) == 0 &&
        dispatch_m_table_len == 2);
    assert(memcmp(&dispatch_m_image[0x52], "hi", 2) == 0);

    return 0;
}