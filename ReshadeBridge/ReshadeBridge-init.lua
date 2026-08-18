local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

_G.ReShadeBridge = {}

local function process_asset_table(base_dir, asset_table)
    local changes_made = false

    if type(asset_table) ~= "table" then
        return changes_made
    end

    for key, value in pairs(asset_table) do
        if type(value) == "table" then
            local subfolder = type(key) == "string" and (key .. "/") or ""

            for filename, b64_str in pairs(value) do
                local target_path = base_dir .. subfolder .. filename
                local binary_data = kUtil.b64_decode(b64_str)

                if not kUtil.file_exists(target_path, binary_data) then
                    if kUtil.install_file(target_path, binary_data) then
                        changes_made = true
                    end
                end
            end
        elseif type(key) == "string" and type(value) == "string" then
            local target_path = base_dir .. key
            local binary_data = kUtil.b64_decode(value)

            if not kUtil.file_exists(target_path, binary_data) then
                if kUtil.install_file(target_path, binary_data) then
                    changes_made = true
                end
            end
        end
    end

    return changes_made
end

local function show_restart_required_popup(mod_name)
    if _G.BTLD_DATA.simple_text_popup and _G.BTLD_DATA.simple_text_popup.properties then
        UIFunc.kill_element_and_children(_G.BTLD_DATA.simple_text_popup)
        _G.BTLD_DATA.simple_text_popup = nil
    end

    local z_pos = 750
    local size_x = 450
    local size_y = 250

    local popup = UIFunc.new_texture_markup(
        "window_tile",
        {GET_CENTER_SCREEN_X_SCALED(), GET_CENTER_SCREEN_Y_SCALED(), z_pos},
        {size_x, size_y},
        true,
        {200, 15, 15, 15},
        {}
    )

    local title_text = string.format("[%s]\nDependencies installed.\nPlease restart your game\nfor mod to function properly.", mod_name or "ReShade Bridge")
    local current_y = 60
    local line_spacing = 24

    for line in string.gmatch(title_text, "[^\n]+") do
        local label = UIFunc.new_text_markup(
            line,
            {0, current_y, z_pos + 1},
            18,
            {255, 255, 255, 255},
            true
        )

        UIFunc.add_child(popup, label)
        current_y = current_y - line_spacing
    end

    local btn_y_offset = -(size_y * 0.3)
    local close_btn = UIFunc.new_button_unattached(
        {0, btn_y_offset, z_pos + 1},
        "OK  ",
        0,
        0,
        function()
            UIFunc.kill_element_and_children(popup)
            _G.BTLD_DATA.simple_text_popup = nil

            kUtil.task_scheduler.add(function ()
                Application.quit()
            end, 500)
        end
    )

    UIFunc.add_child(popup, close_btn)

    NEW_UI_ELEMENT(ACTIVE_GAME_STATE, popup)
    _G.BTLD_DATA.simple_text_popup = popup

    return popup
end

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    k_log("[Lua-ReShadeBridge] starting initalization ...")

    local ffi = require("ffi")

    ffi.cdef[[
        bool __cdecl IsBridgeReady();
        bool __cdecl SetShaderVariableFloat(const char* effect_name, const char* variable_name, float value);
        bool __cdecl SetShaderVariableFloat2(const char* effect_name, const char* variable_name, float x, float y);
        bool __cdecl SetShaderVariableFloat3(const char* effect_name, const char* variable_name, float x, float y, float z);
        bool __cdecl SetEffectStateAndOrder(const char* effect_name, bool enabled, bool move_to_beginning);
        bool __cdecl ResetShaderVariable(const char* effect_name, const char* variable_name, bool use_user_preset);
    ]]

    local needs_restart = false

    local success, b64_data = pcall(require, "ReshadeBridge/reshade_addon_bin")
    local target_bin1 = "./reshade_bridge.addon32"

    if success and type(b64_data) == "string" then
        local binary_data = kUtil.b64_decode(b64_data)

        if not kUtil.file_exists(target_bin1, binary_data) then
            k_log("[Lua-ReShadeBridge] missing file 'reshade_bridge.addon32', installing ...")
            if kUtil.install_file(target_bin1, binary_data) then
                needs_restart = true
            end
        end
    else
        k_log("[Lua-ReShadeBridge] Failed to require 'reshade_addon_bin.lua' or the return type is invalid, error ::\n" .. tostring(b64_data))
    end

    if needs_restart then
        k_log("[Lua-ReShadeBridge] Dependencies installed. Prompting user for manual restart...")

        kUtil.task_scheduler.add(function()
            show_restart_required_popup("ReShade Bridge")
        end, 200)

        mod_inited = true
        return
    end

    local dll_path = "./reshade_bridge.addon32"
    local bridge = nil
    local bridge_ready = false

    _G.ReShadeBridge.setFloat = function(effect_name, variable_name, value)
        if not bridge_ready then
            k_log("[Lua-ReShadeBridge] is not initialized !!!")
            return
        end

        if type(effect_name) ~= "string" or type(variable_name) ~= "string" or type(value) ~= "number" then
            k_log("[Lua-ReShadeBridge] Invalid types passed to setFloat. Expected: string, string, number")
            return
        end

        return bridge.SetShaderVariableFloat(effect_name, variable_name, value)
    end

    _G.ReShadeBridge.setFloat2 = function(effect_name, variable_name, x, y)
        if not bridge_ready then
            k_log("[Lua-ReShadeBridge] is not initialized !!!")
            return
        end

        if type(effect_name) ~= "string" or type(variable_name) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
            k_log("[Lua-ReShadeBridge] Invalid types passed to setFloat. Expected: string, string, number, number")
            return
        end

        return bridge.SetShaderVariableFloat2(effect_name, variable_name, x, y)
    end

    _G.ReShadeBridge.setFloat3 = function(effect_name, variable_name, x, y, z)
        if not bridge_ready then
            k_log("[Lua-ReShadeBridge] is not initialized !!!")
            return
        end

        if type(effect_name) ~= "string" or type(variable_name) ~= "string" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
            k_log("[Lua-ReShadeBridge] Invalid types passed to setFloat. Expected: string, string, number, number, number")
            return
        end

        return bridge.SetShaderVariableFloat3(effect_name, variable_name, x, y, z)
    end

    _G.ReShadeBridge.setStateAndOrder = function(effect_name, enabled, move_to_beginning)
        if not bridge_ready then
            k_log("[Lua-ReShadeBridge] is not initialized !!!")
            return false
        end

        if type(effect_name) ~= "string" or type(enabled) ~= "boolean" or type(move_to_beginning) ~= "boolean" then
            k_log("[Lua-ReShadeBridge] Invalid types passed to setStateAndOrder. Expected: string, boolean, boolean")
            return false
        end

        return bridge.SetEffectStateAndOrder(effect_name, enabled, move_to_beginning)
    end

    _G.ReShadeBridge.resetVariable = function(effect_name, variable_name, use_user_preset)
        if not bridge_ready then
            k_log("[Lua-ReShadeBridge] is not initialized !!!")
            return false
        end

        if type(effect_name) ~= "string" or type(variable_name) ~= "string" or type(use_user_preset) ~= "boolean" then
            k_log("[Lua-ReShadeBridge] Invalid types passed to resetVariable. Expected: string, string, boolean")
            return false
        end

        return bridge.ResetShaderVariable(effect_name, variable_name, use_user_preset)
    end

    _G.ReShadeBridge.installAssets = function(mod_name, shaders_table, textures_table)
        local shader_changes = process_asset_table("./reshade-shaders/Shaders/", shaders_table)
        local texture_changes = process_asset_table("./reshade-shaders/Textures/", textures_table)
        local total_changes = (shader_changes or texture_changes)

        if total_changes then
            kUtil.task_scheduler.add(function()
                show_restart_required_popup(mod_name)
            end, 200)
        end

        return total_changes
    end

    local status, err = pcall(function()
        bridge = ffi.load(dll_path)
    end)

    if not status then
        k_log("[Lua-ReShadeBridge] Failed to load Addon binary layout at path: " .. dll_path .. "\nError: " .. tostring(err))
        return
    end

    kUtil.task_scheduler.add(function ()
        if bridge.IsBridgeReady() then
            k_log("[Lua-ReShadeBridge] Linked successfully with pre-loaded active ReShade framework!")
            bridge_ready = true
        else
            k_log("[Lua-ReShadeBridge] Binary attached, waiting for rendering context capture loops...")
        end
    end, 100)

    CameraSettings.far_range = 1000

    k_log("[Lua-ReShadeBridge] initalization finished")
end

EventHandler.register_event("menu", "init", "ReshadeBridge_init", init_mod)
