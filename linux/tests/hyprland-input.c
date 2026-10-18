#define _GNU_SOURCE
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "virtual-keyboard-client.h"
#include "virtual-pointer-client.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *keyboards;
static struct zwlr_virtual_pointer_manager_v1 *pointers;

static void capabilities(void *data, struct wl_seat *object, uint32_t value) {}
static void seat_name(void *data, struct wl_seat *object, const char *name) {}
static const struct wl_seat_listener seat_listener = {capabilities, seat_name};

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_seat")) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    } else if (!strcmp(interface, "zwp_virtual_keyboard_manager_v1"))
        keyboards = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (!strcmp(interface, "zwlr_virtual_pointer_manager_v1"))
        pointers = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void removed(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {global, removed};

static uint32_t timestamp(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !keyboards || !pointers) {
        fprintf(stderr, "Virtual keyboard/pointer protocols unavailable\n");
        return 2;
    }
    struct zwp_virtual_keyboard_v1 *keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keyboards, seat);
    struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointers, seat);
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = {.layout = "us"};
    struct xkb_keymap *map = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!map) return 3;
    struct xkb_state *state = xkb_state_new(map);
    char *keymap = xkb_keymap_get_as_string(map, XKB_KEYMAP_FORMAT_TEXT_V1);
    if (!state || !keymap) return 3;
    size_t size = strlen(keymap) + 1;
    int fd = memfd_create("shiftdrop-test-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, keymap, size) != (ssize_t)size) return 4;
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    if (wl_display_roundtrip(display) < 0) return 5;
    close(fd);
    free(keymap);
    puts("ready"); fflush(stdout);

    char line[128], command[16];
    unsigned first, second;
    while (fgets(line, sizeof(line), stdin)) {
        int count = sscanf(line, "%15s %u %u", command, &first, &second);
        if (count != 3) return 6;
        if (!strcmp(command, "move")) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer, timestamp(), first, second, 1280, 720);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else if (!strcmp(command, "button")) {
            zwlr_virtual_pointer_v1_button(pointer, timestamp(), first, second);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else if (!strcmp(command, "key")) {
            xkb_state_update_key(state, first + 8, second ? XKB_KEY_DOWN : XKB_KEY_UP);
            zwp_virtual_keyboard_v1_key(keyboard, timestamp(), first, second);
            zwp_virtual_keyboard_v1_modifiers(keyboard,
                xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED),
                xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
                xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED),
                xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
        } else return 7;
        if (wl_display_roundtrip(display) < 0) return 8;
        puts("ok"); fflush(stdout);
    }
    zwp_virtual_keyboard_v1_destroy(keyboard);
    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_flush(display);
    wl_display_disconnect(display);
    xkb_state_unref(state);
    xkb_keymap_unref(map);
    xkb_context_unref(context);
    return 0;
}
