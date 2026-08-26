#include <assert.h>
#include <string.h>

#include "story_mem.h"
#include "story_header.h"
#include "vm_state.h"
#include "ztext.h"
#include "objects.h"
#include "properties.h"

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

    return 0;
}