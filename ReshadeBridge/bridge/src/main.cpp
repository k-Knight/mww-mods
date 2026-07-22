#include <windows.h>
#include <atomic>
#include <print>
#include <cstdlib>
#include <reshade.hpp>
#include <string>
#include <unordered_map>
#include <sstream>
#include <vector>

std::atomic<reshade::api::effect_runtime*> g_runtime = nullptr;
static uint32_t g_total_draw_calls = 0;
static uint32_t g_current_frame_draw_calls = 0;
static bool g_effects_rendered_this_frame = false;

static reshade::api::resource_view g_current_rtv = { 0 };
void RenderEffectsEarly(reshade::api::effect_runtime* runtime, reshade::api::command_list* cmd_list);

static void on_init_effect_runtime(reshade::api::effect_runtime* runtime) {
    std::println("[reshade-bridge] Effect runtime initialized/bound: 0x{:X}", reinterpret_cast<uintptr_t>(runtime));
    g_runtime.store(runtime, std::memory_order_relaxed);
}

static void on_destroy_effect_runtime(reshade::api::effect_runtime* runtime) {
    std::println("[reshade-bridge] Effect runtime destroyed: 0x{:X}", reinterpret_cast<uintptr_t>(runtime));

    if (g_runtime.load(std::memory_order_relaxed) == runtime)
        g_runtime.store(nullptr, std::memory_order_relaxed);
}

static void on_bind_render_targets_and_depth_stencil(reshade::api::command_list* cmd_list, uint32_t count, const reshade::api::resource_view* rtvs, reshade::api::resource_view dsv) {
    if (count > 0 && rtvs != nullptr)
        g_current_rtv = *rtvs;
}

static void on_present(reshade::api::command_queue* queue, reshade::api::swapchain* swapchain, const reshade::api::rect* source_rect, const reshade::api::rect* dest_rect, uint32_t dirty_rect_count, const reshade::api::rect* dirty_rects) {
    g_total_draw_calls = g_current_frame_draw_calls;
    g_current_frame_draw_calls = 0;
    g_effects_rendered_this_frame = false;
}

static bool on_draw(reshade::api::command_list* cmd_list, uint32_t vertex_count, uint32_t instance_count, uint32_t first_vertex, uint32_t first_instance) {
    if (g_total_draw_calls > 2 && g_current_frame_draw_calls == (g_total_draw_calls - 1)) {
        reshade::api::effect_runtime* runtime = g_runtime.load(std::memory_order_relaxed);

        if (runtime && !g_effects_rendered_this_frame) {
            RenderEffectsEarly(runtime, cmd_list);
            g_effects_rendered_this_frame = true;
        }
    }

    return false;
}

static bool on_draw_indexed(reshade::api::command_list* cmd_list, uint32_t index_count, uint32_t instance_count, uint32_t first_index, int32_t vertex_offset, uint32_t first_instance) {
    if (g_total_draw_calls > 2 && g_current_frame_draw_calls == (g_total_draw_calls - 1)) {
        reshade::api::effect_runtime* runtime = g_runtime.load(std::memory_order_relaxed);

        if (runtime && !g_effects_rendered_this_frame) {
            RenderEffectsEarly(runtime, cmd_list);
            g_effects_rendered_this_frame = true;
        }
    }

    return false;
}

void RenderEffectsEarly(reshade::api::effect_runtime* runtime, reshade::api::command_list* cmd_list) {
    if (g_current_rtv.handle != 0)
        runtime->render_effects(cmd_list, g_current_rtv, g_current_rtv);
}

static bool set_uniform_internal(const char* effect_name, const char* variable_name, const float* values, size_t count) {
    reshade::api::effect_runtime* runtime = g_runtime.load(std::memory_order_relaxed);

    if (!runtime) {
        std::println(stderr, "[reshade-bridge] Error: ReShade runtime context is not yet captured.");
        return false;
    }

    reshade::api::effect_uniform_variable var = runtime->find_uniform_variable(effect_name, variable_name);

    if (var.handle != 0) {
        runtime->set_uniform_value_float(var, values, count);
        return true;
    }

    return false;
}

void InitializePreprocessorDefinitions() {
    char existing_defs[4096] = { 0 };
    size_t size = sizeof(existing_defs);
    reshade::get_config_value(nullptr, "GENERAL", "PreprocessorDefinitions", existing_defs, &size);

    std::unordered_map<std::string, std::string> defs_map;
    std::string input_str(existing_defs);

    if (!input_str.empty()) {
        std::stringstream ss(input_str);
        std::string item;
        while (std::getline(ss, item, ',')) {
            if (item.empty()) continue;

            size_t eq_pos = item.find('=');
            if (eq_pos != std::string::npos) {
                defs_map[item.substr(0, eq_pos)] = item.substr(eq_pos + 1);
            } else {
                defs_map[item] = "";
            }
        }
    }

    defs_map["RESHADE_DEPTH_LINEARIZATION_FAR_PLANE"] = "200.0";
    defs_map["RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN"] = "0";
    defs_map["RESHADE_DEPTH_INPUT_IS_REVERSED"] = "0";
    defs_map["RESHADE_DEPTH_INPUT_IS_LOGARITHMIC"] = "0";
    defs_map["RESHADE_DEPTH_MULTIPLIER"] = "1.005";

    std::vector<char> output_buffer;

    for (auto const& [key, val] : defs_map) {
        if (key.empty()) continue;

        if (!output_buffer.empty()) {
            output_buffer.push_back('\0');
        }

        std::string element = val.empty() ? key : key + "=" + val;
        output_buffer.insert(output_buffer.end(), element.begin(), element.end());
    }

    output_buffer.push_back('\0');

    reshade::set_config_value(
        nullptr, 
        "GENERAL", 
        "PreprocessorDefinitions", 
        static_cast<const char*>(output_buffer.data()), 
        output_buffer.size() - 1
    );

    std::println("[reshade-bridge] Preprocessor definitions successfully initialized/updated.");
}

extern "C" {
    __declspec(dllexport) bool __cdecl AddonInit(HMODULE addon_module, HMODULE reshade_module) {
        std::println("[reshade-bridge] AddonInit called by ReShade core framework. Resolving handshake hooks...");

        if (!reshade::register_addon(addon_module, reshade_module)) {
            std::println(stderr, "[reshade-bridge] Critical Error: register_addon handshake aborted inside AddonInit!");
            return false;
        }

        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init_effect_runtime);
        reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_effect_runtime);
        reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(on_bind_render_targets_and_depth_stencil);
        reshade::register_event<reshade::addon_event::present>(on_present);
        reshade::register_event<reshade::addon_event::draw>(on_draw);
        reshade::register_event<reshade::addon_event::draw_indexed>(on_draw_indexed);

        std::println("[reshade-bridge] Addon Registered Successfully. Ready for Lua connections.");

        InitializePreprocessorDefinitions();

        return true;
    }

    __declspec(dllexport) void __cdecl AddonUninit(HMODULE addon_module, HMODULE reshade_module) {
        std::println("[reshade-bridge] AddonUninit called. Cleaning hooks...");

        reshade::unregister_event<reshade::addon_event::init_effect_runtime>(on_init_effect_runtime);
        reshade::unregister_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_effect_runtime);
        reshade::unregister_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(on_bind_render_targets_and_depth_stencil);
        reshade::unregister_event<reshade::addon_event::present>(on_present);
        reshade::unregister_event<reshade::addon_event::draw>(on_draw);
        reshade::unregister_event<reshade::addon_event::draw_indexed>(on_draw_indexed);
        reshade::unregister_addon(addon_module, reshade_module);

        std::println("[reshade-bridge] Cleanup complete via AddonUninit.");
    }

    __declspec(dllexport) bool __cdecl IsBridgeReady() {
        bool ready = (g_runtime.load(std::memory_order_relaxed) != nullptr);
        std::println("[reshade-bridge] IsBridgeReady query received. Status: {}", ready);

        return ready;
    }

    __declspec(dllexport) bool __cdecl SetShaderVariableFloat(const char* effect_name, const char* variable_name, float value) {
        return set_uniform_internal(effect_name, variable_name, &value, 1);
    }

    __declspec(dllexport) bool __cdecl SetShaderVariableFloat2(const char* effect_name, const char* variable_name, float x, float y) {
        float values[2] = { x, y };

        return set_uniform_internal(effect_name, variable_name, values, 2);
    }

    __declspec(dllexport) bool __cdecl SetShaderVariableFloat3(const char* effect_name, const char* variable_name, float x, float y, float z) {
        float values[3] = { x, y, z };

        return set_uniform_internal(effect_name, variable_name, values, 3);
    }

    __declspec(dllexport) bool __cdecl ResetShaderVariable(const char* effect_name, const char* variable_name, bool use_user_preset) {
        reshade::api::effect_runtime* runtime = g_runtime.load(std::memory_order_relaxed);

        if (!runtime) {
            std::println(stderr, "[reshade-bridge] Error: ReShade runtime context is not yet captured.");
            return false;
        }

        reshade::api::effect_uniform_variable var = runtime->find_uniform_variable(effect_name, variable_name);
        if (var.handle == 0)
            return false;

        if (!use_user_preset) {
            runtime->reset_uniform_value(var);
            return true;
        }

        char preset_path[MAX_PATH] = { 0 };
        size_t path_size = sizeof(preset_path);
        runtime->get_current_preset_path(preset_path, &path_size);

        if (path_size == 0)
            return false;

        char value_buffer[256] = { 0 };
        GetPrivateProfileStringA(
            effect_name,
            variable_name,
            "",
            value_buffer,
            sizeof(value_buffer),
            preset_path
        );

        if (strlen(value_buffer) == 0) {
            runtime->reset_uniform_value(var);
            return true;
        }

        float preset_values[4] = { 0.0f };
        size_t count = 0;

        char* start_ptr = value_buffer;
        char* end_ptr = nullptr;

        while (*start_ptr != '\0' && count < 4) {
            float val = std::strtof(start_ptr, &end_ptr);

            if (start_ptr == end_ptr)
                break;

            preset_values[count] = val;
            count++;

            if (*end_ptr == ',')
                start_ptr = end_ptr + 1;
            else
                break;
        }

        if (count > 0) {
            runtime->set_uniform_value_float(var, preset_values, count);
            return true;
        }

        return false;
    }

    __declspec(dllexport) bool __cdecl SetEffectStateAndOrder(const char* effect_name, bool enabled, bool move_to_beginning) {
        reshade::api::effect_runtime* runtime = g_runtime.load(std::memory_order_relaxed);
        if (!runtime) {
            std::println(stderr, "[reshade-bridge] Error: ReShade runtime context is not yet captured.");
            return false;
        }

        reshade::api::effect_technique tech = runtime->find_technique(nullptr, effect_name);
        if (tech.handle == 0) {
            std::println(stderr, "[reshade-bridge] Error: Technique '{}' not found.", effect_name);
            return false;
        }

        runtime->set_technique_state(tech, enabled);
        std::println("[reshade-bridge] Set technique '{}' state to: {}", effect_name, enabled ? "Enabled" : "Disabled");

        char sorting_list[2048] = { 0 };
        size_t size = sizeof(sorting_list);
        reshade::get_config_value(nullptr, "BOOSTER", "TechniqueSorting", sorting_list, &size);

        std::string order_str(sorting_list);
        std::string tech_str(effect_name);

        size_t pos = order_str.find(tech_str);
        if (pos != std::string::npos) {
            if (pos + tech_str.length() < order_str.length() && order_str[pos + tech_str.length()] == ',') {
                order_str.erase(pos, tech_str.length() + 1);
            } else if (pos > 0 && order_str[pos - 1] == ',') {
                order_str.erase(pos - 1, tech_str.length() + 1);
            } else {
                order_str.erase(pos, tech_str.length());
            }
        }

        if (move_to_beginning) {
            order_str = order_str.empty() ? tech_str : tech_str + "," + order_str;
        } else {
            order_str = order_str.empty() ? tech_str : order_str + "," + tech_str;
        }

        reshade::set_config_value(nullptr, "BOOSTER", "TechniqueSorting", order_str.c_str());
        std::println("[reshade-bridge] Reordered technique '{}' to the {}.", effect_name, move_to_beginning ? "beginning" : "end");

        return true;
    }
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    return TRUE;
}
