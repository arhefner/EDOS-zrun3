#include <assert.h>
#include <string.h>

#include "story_mem.h"
#include "story_header.h"
#include "vm_state.h"
#include "ztext.h"

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
    return 0;
}