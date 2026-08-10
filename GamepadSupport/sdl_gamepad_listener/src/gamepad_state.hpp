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
    int16_t left_x;
    int16_t left_y;
    int16_t right_x;
    int16_t right_y;
};

extern "C" {
    DLL_EXPORT void InitializeGamepad();
    DLL_EXPORT void ShutdownGamepad();
    DLL_EXPORT bool GetButtonStateByName(const char* btn_name);
    DLL_EXPORT int16_t GetLeftAxisX();
    DLL_EXPORT int16_t GetLeftAxisY();
    DLL_EXPORT int16_t GetRightAxisX();
    DLL_EXPORT int16_t GetRightAxisY();
}

#endif //SDL_GAMEPAD_STATE