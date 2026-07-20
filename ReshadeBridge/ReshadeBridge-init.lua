local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

_G.ReShadeBridge = {}

local mod_inited = false

local function b64_decode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')

    return (data:gsub('.', function(x)
        if x == '=' then
            return ''
        end

        local r, f = '', (b:find(x) - 1)

        for i = 6, 1, -1 do
            r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0')
        end

        return r
    end):gsub('%d%d%d%d%d%d%d%d', function(x)
        local n = 0
        for i = 1, 8 do
            n = n + (x:sub(i, i) == '1' and 2^(8-i) or 0)
        end

        return string.char(n)
    end))
end

local function file_exists(path)
    local f = io.open(path, "rb")

    if f then f:close()
        return true
    end

    return false
end

local function install_file(filename, b64_string)
    local binary_data = b64_decode(b64_string)
    local f, err = io.open(filename, "wb")

    if not f then
        k_log("[Lua-ReShadeBridge] Failed to write file: " .. filename .. ". Error: " .. tostring(err))
        return false
    end

    f:write(binary_data)
    f:close()
    k_log("[Lua-ReShadeBridge] Successfully installed: " .. filename)

    return true
end

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

                if not file_exists(target_path) then
                    if install_file(target_path, b64_str) then
                        changes_made = true
                    end
                end
            end
        elseif type(key) == "string" and type(value) == "string" then
            local target_path = base_dir .. key

            if not file_exists(target_path) then
                if install_file(target_path, value) then
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

local function init_mod(context)
    if mod_inited then
        return
    end

    local ffi = require("ffi")

    ffi.cdef[[
        bool __cdecl IsBridgeReady();
        bool __cdecl SetShaderVariableFloat(const char* effect_name, const char* variable_name, float value);
    ]]

    local needs_restart = false

    local success, b64_data = pcall(require, "ReshadeBridge/reshade_addon_bin")
    local target_bin1 = "./reshade_bridge.addon32"

    if success and type(b64_data) == "string" then
        if not file_exists(target_bin1) then
            k_log("[Lua-ReShadeBridge] missing file 'reshade_bridge.addon32', installing ...")
            if install_file(target_bin1, b64_data) then
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

    mod_inited = true
end

EventHandler.register_event("menu", "init", "ReshadeBridge_init", init_mod)
