#include <windows.h>
#include <psapi.h>
#include <vector>
#include <atomic>
#include <print>
#include <MinHook.h>
#include <reshade.hpp>

typedef void(__thiscall* t_render_effects)(
    reshade::api::effect_runtime* thisptr,
    reshade::api::command_list* cmd_list,
    reshade::api::resource_view rtv,
    reshade::api::resource_view rtv_srgb
);

t_render_effects original_render_effects = nullptr;

std::atomic<reshade::api::effect_runtime*> g_cached_runtime = nullptr;

uintptr_t FindPattern(HMODULE hModule, const char* signature) {
    MODULEINFO modInfo = { 0 };
    if (!GetModuleInformation(GetCurrentProcess(), hModule, &modInfo, sizeof(modInfo))) {
        std::println(stderr, "[reshade-bridge] Error: Failed to fetch module information. Win32 Error Code: {}", GetLastError());
        return 0;
    }

    uintptr_t startAddress = reinterpret_cast<uintptr_t>(modInfo.lpBaseOfDll);
    size_t size = modInfo.SizeOfImage;

    std::vector<unsigned char> pattern_bytes;
    std::vector<bool> pattern_mask;

    const char* current = signature;
    while (*current) {
        if (*current == ' ') {
            current++;
            continue;
        }
        if (*current == '?') {
            pattern_bytes.push_back(0);
            pattern_mask.push_back(false);
            current += (*(current + 1) == '?') ? 2 : 1;
        } else {
            pattern_bytes.push_back(static_cast<unsigned char>(strtoul(current, const_cast<char**>(&current), 16)));
            pattern_mask.push_back(true);
        }
    }

    if (pattern_bytes.empty()) return 0;

    size_t patternLength = pattern_bytes.size();
    unsigned char* scanStart = reinterpret_cast<unsigned char*>(scanStart);

    for (size_t i = 0; i < size - patternLength; ++i) {
        bool found = true;
        for (size_t j = 0; j < patternLength; ++j) {
            if (pattern_mask[j] && pattern_bytes[j] != reinterpret_cast<unsigned char*>(startAddress)[i + j]) {
                found = false;
                break;
            }
        }
        if (found) {
            return startAddress + i;
        }
    }

    std::println(stderr, "[reshade-bridge] Error: Target signature sequence not matched in module memory.");
    return 0;
}

class HookContainer {
public:
    void __thiscall detoured_render_effects(
        reshade::api::command_list* cmd_list,
        reshade::api::resource_view rtv,
        reshade::api::resource_view rtv_srgb)
    {
        reshade::api::effect_runtime* thisptr = reinterpret_cast<reshade::api::effect_runtime*>(this);
        g_cached_runtime.store(thisptr, std::memory_order_relaxed);

        original_render_effects(thisptr, cmd_list, rtv, rtv_srgb);
    }
};

extern "C" {
    __declspec(dllexport) bool __cdecl SetupReShadeBridge() {
        if (g_cached_runtime.load(std::memory_order_relaxed)) {
            std::println(stderr, "[reshade-bridge] Setup Skip: reshade bridge is already successfully initialized.");
            return true;
        }

        HMODULE hReshade = GetModuleHandleA("dxgi.dll");

        if (!hReshade) {
            std::println(stderr, "[reshade-bridge] Setup Error: ReShade module (dxgi.dll) are not loaded in this process.");
            return false;
        }

        const char* pattern = "55 8B EC 83 E4 ? 81 EC ? ? ? ? 56 57 8B F9 89 7C 24 ? 80 7F ? ? 0F 85";

        uintptr_t target_function_address = FindPattern(hReshade, pattern);
        if (!target_function_address) {
            std::println(stderr, "[reshade-bridge] Setup Error: Could not resolve target render effects function address.");
            return false;
        }

        MH_STATUS init_status = MH_Initialize();
        if (init_status != MH_OK && init_status != MH_ERROR_ALREADY_INITIALIZED) {
            std::println(stderr, "[reshade-bridge] MinHook Error: MH_Initialize failed with status code: {}", static_cast<int>(init_status));
            return false;
        }

        auto detour_ptr = &HookContainer::detoured_render_effects;
        LPVOID target_detour = *reinterpret_cast<LPVOID*>(&detour_ptr);

        MH_STATUS hook_status = MH_CreateHook((LPVOID)target_function_address, target_detour, (LPVOID*)&original_render_effects);
        if (hook_status != MH_OK) {
            std::println(stderr, "[reshade-bridge] MinHook Error: MH_CreateHook failed with status code: {}", static_cast<int>(hook_status));
            return false;
        }

        MH_STATUS enable_status = MH_EnableHook((LPVOID)target_function_address);
        if (enable_status != MH_OK) {
            std::println(stderr, "[reshade-bridge] MinHook Error: MH_EnableHook failed with status code: {}", static_cast<int>(enable_status));
            return false;
        }

        std::println("[reshade-bridge] Setup Success: initialized reshade bridge.");
        return true;
    }

    __declspec(dllexport) bool __cdecl SetShaderVariableFloat(const char* effect_name, const char* variable_name, float value) {
        reshade::api::effect_runtime* runtime = g_cached_runtime.load(std::memory_order_relaxed);
        if (!runtime) {
            std::println(stderr, "[reshade-bridge] Error: ReShade runtime context is not yet captured.");
            return false;
        }

        reshade::api::effect_uniform_variable var = runtime->find_uniform_variable(effect_name, variable_name);

        if (var.handle != 0) {
            runtime->set_uniform_value_float(var, &value, 1);
            return true;
        }

        std::println(stderr, "[reshade-bridge] Error: Could not resolve uniform variable '{}' in shader file '{}'.", variable_name, effect_name);
        return false;
    }
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH:
        case DLL_THREAD_ATTACH:
        case DLL_THREAD_DETACH:
        case DLL_PROCESS_DETACH:
            break;
    }
    return TRUE;
}
