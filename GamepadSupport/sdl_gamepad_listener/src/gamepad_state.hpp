#ifndef SDL_GAMEPAD_STATE
#define SDL_GAMEPAD_STATE

#include <stdint.h>

#ifdef _WIN32
#   define DLL_EXPORT __declspec(dllexport)
#else
#   define DLL_EXPORT
#endif

enum gamepad_btn_t {
    gamepad_d_up = 0,
    gamepad_d_down,
    gamepad_d_left,
    gamepad_d_right,
    gamepad_start,
    gamepad_back,
    gamepad_left_thumb,
    gamepad_right_thumb,
    gamepad_left_shoulder,
    gamepad_right_shoulder,
    gamepad_left_trigger,
    gamepad_right_trigger,
    gamepad_a,
    gamepad_b,
    gamepad_x,
    gamepad_y,
    GAMEPAD_BTN_NUM
};

struct gamepad_state_t {
    bool buttons[GAMEPAD_BTN_NUM];
    float left_x;
    float left_y;
    float right_x;
    float right_y;
};

#endif //SDL_GAMEPAD_STATE