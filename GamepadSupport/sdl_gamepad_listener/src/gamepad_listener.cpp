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
static gamepad_state_t g_internal_gamepad_state = {};

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
    {"d_up", gamepad_d_up},
    {"d_down", gamepad_d_down},
    {"d_left", gamepad_d_left},
    {"d_right", gamepad_d_right},
    {"start", gamepad_start},
    {"back", gamepad_back},
    {"left_thumb", gamepad_left_thumb},
    {"right_thumb", gamepad_right_thumb},
    {"left_shoulder", gamepad_left_shoulder},
    {"right_shoulder", gamepad_right_shoulder},
    {"left_trigger", gamepad_left_trigger},
    {"right_trigger", gamepad_right_trigger},
    {"a", gamepad_a},
    {"b", gamepad_b},
    {"x", gamepad_x},
    {"y", gamepad_y}
};

static inline float normalize_axis(int16_t value) {
    float val = static_cast<float>(value) / 32767.0f;

    if (val < -1.0f)
        return -1.0f;
    if (val > 1.0f)
        return 1.0f;

    return val;
}

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

    for (int i = 0; i < num_joysticks; i++)
        if (SDL_IsGameController(i))
            return SDL_GameControllerOpen(i);

    return nullptr;
}

static void update_gamepad_status(gamepad_state_t &state) {
    SDL_GameControllerUpdate();

    if (controller && !SDL_GameControllerGetAttached(controller)) {
        SDL_GameControllerClose(controller);
        controller = nullptr;
        state = {};
    }

    if (!controller)
        controller = find_controller();
    if (!controller)
        return;

    for (int i = 0; i < GAMEPAD_BTN_NUM; i++) {
        gamepad_btn_t btn = static_cast<gamepad_btn_t>(i);

        if (btn_2_sdl_btn.count(btn))
            state.buttons[btn] = SDL_GameControllerGetButton(controller, btn_2_sdl_btn.at(btn));
        else if (btn_2_sdl_axis.count(btn))
            state.buttons[btn] = std::fabs((float)SDL_GameControllerGetAxis(controller, btn_2_sdl_axis.at(btn)) / 32767.0f) > 0.05f;
    }

    state.left_x = normalize_axis(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX));
    state.left_y = normalize_axis(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTY));
    state.right_x = normalize_axis(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_RIGHTX));
    state.right_y = normalize_axis(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_RIGHTY));
    
    state.left_trigger_axis = normalize_axis(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_TRIGGERLEFT));
    state.right_trigger_axis = normalize_axis(SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_TRIGGERRIGHT));
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

        if (g_update_thread.joinable())
            g_update_thread.join();

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

        if (it != name_2_btn.end())
            return g_internal_gamepad_state.buttons[it->second];

        return false;
    }

    DLL_EXPORT float get_left_axis_x() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.left_x;
    }

    DLL_EXPORT float get_left_axis_y() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.left_y;
    }

    DLL_EXPORT float get_right_axis_x() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.right_x;
    }

    DLL_EXPORT float get_right_axis_y() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.right_y;
    }

    DLL_EXPORT float get_left_trigger_axis() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.left_trigger_axis;
    }

    DLL_EXPORT float get_right_trigger_axis() {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        return g_internal_gamepad_state.right_trigger_axis;
    }
}
