#include <windows.h>
#include <atomic>
#include <print>
#include <reshade.hpp>

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
        reshade::api::effect_runtime* runtime = g_runtime.load(std::memory_order_relaxed);

        if (!runtime) {
            std::println(stderr, "[reshade-bridge] Error: ReShade runtime context is not yet captured.");
            return false;
        }

        reshade::api::effect_uniform_variable var = runtime->find_uniform_variable(effect_name, variable_name);

        if (var.handle != 0) {
            runtime->set_uniform_value_float(var, &value, 1);
            return true;
        }

        return false;
    }
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    return TRUE;
}
