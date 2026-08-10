#include <SDL.h>
#include <vector>
#include <map>
#include <chrono>
#include <algorithm>
#include <cmath>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include "gamepad_state.hpp"

static SDL_GameController *controller = NULL;
static std::chrono::high_resolution_clock::time_point reinit_time;
static GamepadState g_internal_gamepad_state = {};

static std::thread g_update_thread;
static std::atomic<bool> g_running(false);
static std::mutex g_state_mutex;

static const std::map<gamepad_btn_t, SDL_GameControllerButton> btn_2_sdl_btn = {
    {gamepad_d_up, SDL_CONTROLLER_BUTTON_DPAD_UP},
    {gamepad_a, SDL_CONTROLLER_BUTTON_A},
    {gamepad_d_down, SDL_CONTROLLER_BUTTON_DPAD_DOWN},
    {gamepad_b, SDL_CONTROLLER_BUTTON_B},
    {gamepad_d_left, SDL_CONTROLLER_BUTTON_DPAD_LEFT},
    {gamepad_x, SDL_CONTROLLER_BUTTON_X},
    {gamepad_d_right, SDL_CONTROLLER_BUTTON_DPAD_RIGHT},
    {gamepad_y, SDL_CONTROLLER_BUTTON_Y},
    {gamepad_start, SDL_CONTROLLER_BUTTON_START},
    {gamepad_back, SDL_CONTROLLER_BUTTON_BACK},
    {gamepad_left_thumb, SDL_CONTROLLER_BUTTON_LEFTSTICK},
    {gamepad_right_thumb, SDL_CONTROLLER_BUTTON_RIGHTSTICK},
    {gamepad_left_shoulder, SDL_CONTROLLER_BUTTON_LEFTSHOULDER},
    {gamepad_right_shoulder, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER}
};

static const std::map<gamepad_btn_t, SDL_GameControllerAxis> btn_2_sdl_axis = {
    {gamepad_left_trigger, SDL_CONTROLLER_AXIS_TRIGGERLEFT},
    {gamepad_right_trigger, SDL_CONTROLLER_AXIS_TRIGGERRIGHT}
};

static const std::map<std::string, gamepad_btn_t> name_2_btn = {
    {"d up", gamepad_d_up},
    {"d down", gamepad_d_down},
    {"d left", gamepad_d_left},
    {"d right", gamepad_d_right},
    {"start", gamepad_start},
    {"back", gamepad_back},
    {"l3", gamepad_left_thumb},
    {"r3", gamepad_right_thumb},
    {"l1", gamepad_left_shoulder},
    {"r1", gamepad_right_shoulder},
    {"l2", gamepad_left_trigger},
    {"r2", gamepad_right_trigger},
    {"a", gamepad_a},
    {"b", gamepad_b},
    {"x", gamepad_x},
    {"y", gamepad_y}
};

static SDL_GameController *find_controller() {
    int num_joysticks = SDL_NumJoysticks();
    if (!num_joysticks) {
        auto cur_time = std::chrono::high_resolution_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(cur_time - reinit_time).count() > 10000) {
            SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
            SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER);
            reinit_time = cur_time;
        }
    }
    for (int i = 0; i < num_joysticks; i++) {
        if (SDL_IsGameController(i)) return SDL_GameControllerOpen(i);
    }
    return nullptr;
}

static void update_gamepad_status(GamepadState &state) {
    if (!controller)
        controller = find_controller();
    if (!controller)
        return;

    SDL_GameControllerUpdate();

    for (int i = 0; i < GAMEPAD_BTN_NUM; i++) {
        gamepad_btn_t btn = static_cast<gamepad_btn_t>(i);

        if (btn_2_sdl_btn.count(btn))
            state.buttons[btn] = SDL_GameControllerGetButton(controller, btn_2_sdl_btn.at(btn));
        else if (btn_2_sdl_axis.count(btn))
            state.buttons[btn] = std::fabs((float)SDL_GameControllerGetAxis(controller, btn_2_sdl_axis.at(btn)) / 32767.0f) > 0.05f;
    }

    state.left_x = SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX);
    state.left_y = SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTY);
    state.right_x = SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_RIGHTX);
    state.right_y = SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_RIGHTY);
}

static void gamepad_update_loop() {
    while (g_running) {
        {
            std::lock_guard<std::mutex> lock(g_state_mutex);
            update_gamepad_status(g_internal_gamepad_state);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
}

extern "C" {
    DLL_EXPORT void initialize_gamepad() {
        if (g_running)
            return;

        SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER);
        g_running = true;
        g_update_thread = std::thread(gamepad_update_loop);
    }

    DLL_EXPORT void shutdown_gamepad() {
        if (!g_running)
            return;

        g_running = false;

        if (g_update_thread.joinable()) {
            g_update_thread.join();
        }

        if (controller) {
            SDL_GameControllerClose(controller);
            controller = NULL;
        }

        SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
    }

    DLL_EXPORT bool get_button_state(const char* btn_name) {
        if (!btn_name)
            return false;
    
        std::lock_guard<std::mutex> lock(g_state_mutex);
        auto it = name_2_btn.find(btn_name);

        if (it != name_2_btn.end()) {
            return g_internal_gamepad_state.buttons[it->second];
        }

        return false;
    }

    DLL_EXPORT int16_t get_left_axis_x() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.left_x;
    }

    DLL_EXPORT int16_t get_left_axis_y() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.left_y;
    }

    DLL_EXPORT int16_t get_right_axis_x() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.right_x;
    }

    DLL_EXPORT int16_t get_right_axis_y() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.right_y;
    }
}
