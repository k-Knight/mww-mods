local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

_G.GamepadSupportMod = {
    settings = {
        ["aiming/spell casting threshold"] = 0.90,
        ["aiming/spell casting delay (s)"] = 0.05,
        ["aiming/spell reset ratio"] = 0.90,
        ["aiming range multiplier"] = 17.5,
        ["stick deadzone %"] = 5.0,

        bindings = {
            buttons = {
                ["fire"] = {{"A"}},
                ["lightning"] = {{"B"}},
                ["earth"] = {{"X"}},
                ["arcane"] = {{"Y"}},

                ["cold"] = {{"LB", "A"}},
                ["water"] = {{"LB", "B"}},
                ["shield"] = {{"LB", "X"}},
                ["life"] = {{"LB", "Y"}},

                ["magick 1"] = {{"D-Pad Left"}},
                ["magick 2"] = {{"D-Pad Up"}},
                ["magick 3"] = {{"D-Pad Right"}},
                ["magick 4"] = {{"D-Pad Down"}},

                ["self cast"] = {{"RB"}},
                ["use weapon"] = {{"RT"}},
                ["twist free"] = {{"LB"}, {"RB"}},

                ["select magick 1"] = {{"LB", "D-Pad Left"}},
                ["select magick 2"] = {{"LB", "D-Pad Up"}},
                ["select magick 3"] = {{"LB", "D-Pad Right"}},
                ["select magick 4"] = {{"LB", "D-Pad Down"}},

                ["select magick forward"] = {{"D-Pad Up"}},
                ["select magick backward"] = {{"D-Pad Down"}},

                ["emote hotkey"] = {{"RS"}},
                ["use magick or cast immediately"] = {{"LS"}},
            },

            axis = {
                ["cursor"] = "Right Thumb Axis",
                ["movement"] = "Left Thumb Axis",
            },

            trigger_axis = {
                ["aim range multiplier"] = {"Left Trigger Axis"},
            }
        },
    }
}

local function reset_cursor()
    k_log("[GamepadSupport] exiting game, resetting cursor ...")
    local s_w, s_h = Application.resolution()

    _G.GamepadSupportMod.state = {
        is_gamepad_looking = false,
        cursor_moved = false,
        last_cursor_pos = {0, 0},
        cur_cursor_pos = {s_w / 2, s_h / 2, 0},
        holding_weapon = false,
        in_aiming_treshold = -1,
        trying_to_channel = false,
        right_click_pressed = false,
        casting_new_spell = false,
        selecting_magick_ui = 0,
        casting_weapon_attack = false,
        select_magick_forward = false,
        select_magick_backward = false,
        hud_magicks = nil
    }

    if GameSettings and GameSettings.cursors then
        Window.set_cursor(GameSettings.cursors.hud)
    else
        k_log("[GamepadSupport] cannot find cursors or the GameSettings !!!")
    end
end

local function init_mod()
    reset_cursor()

    kUtil.task_scheduler.add(function ()
        SAVE_GLOBAL_MOD_SETTINGS("GamepadSupport", GamepadSupportMod.settings)
    end, 10)

    if mod_inited then
        return
    end

    local context = {
        target_bin = "",
        b64_data = ""
    }

    context.b64_data = require("GamepadSupport/sdl2_bin")
    context.target_bin = "./SDL2.dll"

    if type(context.b64_data) == "string" then
        local binary_data = kUtil.b64_decode(context.b64_data)

        if not kUtil.file_exists(context.target_bin, binary_data) then
            k_log("[GamepadSupport] missing file 'SDL2.dll', installing ...")
            if not kUtil.install_file(context.target_bin, binary_data) then
                k_log("[GamepadSupport] failed to install 'SDL2.dll' file !!!")
                return
            end
        end
    end

    context.b64_data = require("GamepadSupport/sdl_gamepad_listener_bin")
    context.target_bin = "./sdl_gamepad_listener.bin"

    if type(context.b64_data) == "string" then
        local binary_data = kUtil.b64_decode(context.b64_data)

        if not kUtil.file_exists(context.target_bin, binary_data) then
            k_log("[GamepadSupport] missing file 'sdl_gamepad_listener.bin', installing ...")
            if not kUtil.install_file(context.target_bin, binary_data) then
                k_log("[GamepadSupport] failed to install 'sdl_gamepad_listener.bin' file !!!")
                return
            end
        end
    end

    context.b64_data = require("GamepadSupport/gamepad_configurator_bin")
    context.target_bin = "./gamepad_configurator.pyw"

    if type(context.b64_data) == "string" then
        local binary_data = kUtil.b64_decode(context.b64_data)

        if not kUtil.file_exists(context.target_bin, binary_data) then
            k_log("[GamepadSupport] missing file 'gamepad_configurator.pyw', installing ...")
            if not kUtil.install_file(context.target_bin, binary_data) then
                k_log("[GamepadSupport] failed to install 'gamepad_configurator.pyw' file !!!")
                return
            end
        end
    end

    context.b64_data = nil
    context.target_bin = nil

    GamepadSupportMod.settings = LOAD_GLOBAL_MOD_SETTINGS("GamepadSupport", GamepadSupportMod.settings)

    local success, err = xpcall(require, debug.traceback, "GamepadSupport/gamepadinput")
    if not success then
        k_log("[GamepadSupport] failed to load  GamepadInputManager ::\n" .. tostring(err))
        return
    end

    GamepadSupportMod.gamepad_input_manager = GamepadInputManager()

    local success, err = xpcall(require, debug.traceback, "GamepadSupport/gamepadmapping")
    if not success then
        k_log("[GamepadSupport] failed to load  GamepadMapper ::\n" .. tostring(err))
        return
    end

    GamepadSupportMod.gamepad_mapper = GamepadMapper()

    local success, err = xpcall(require, debug.traceback, "GamepadSupport/gamepadbinder")
    if not success then
        k_log("[GamepadSupport] failed to bind keys ::\n" .. tostring(err))
        return
    end

    GamepadSupportMod.gamepad_mapper:add_on_input_handler("right_click", function ()
        GamepadSupportMod.state.right_click_pressed = true
        GamepadSupportMod.gamepad_mapper.input_sates["right_click"] = false
        GamepadSupportMod.gamepad_mapper.input_sates["right_click_up"] = false
    end)
    GamepadSupportMod.gamepad_mapper:add_on_input_handler("right_click_up", function ()
        GamepadSupportMod.state.right_click_pressed = false
        GamepadSupportMod.gamepad_mapper.input_sates["right_click"] = false
        GamepadSupportMod.gamepad_mapper.input_sates["right_click_up"] = false
    end)

    GamepadSupportMod.gamepad_mapper:add_on_input_handler("select_magick_forward_up", function ()
        k_log("select_magick_forward_up !!!!!!!!!!")
        GamepadSupportMod.state.select_magick_forward = true
    end)
    GamepadSupportMod.gamepad_mapper:add_on_input_handler("select_magick_backward_up", function ()
        k_log("select_magick_backward_up !!!!!!!!!!")
        GamepadSupportMod.state.select_magick_backward = true
    end)

    local magick_trigger_inputs = {
        "magick1", "magick2", "magick3", "magick4",
        "magick1_up", "magick2_up", "magick3_up", "magick4_up"
    }

    local stop_magick_button_triggers = function()
        if GamepadSupportMod.state.selecting_magick_ui > 0.5 then
            for _, input in ipairs(magick_trigger_inputs) do
                GamepadSupportMod.gamepad_mapper.input_sates[input] = false
            end
        end
    end

    for _, input in ipairs(magick_trigger_inputs) do
        GamepadSupportMod.gamepad_mapper:add_on_input_handler(input, stop_magick_button_triggers)
    end

    GamepadSupportMod.gamepad_mapper:add_on_input_handler("select_magick1_up", function ()
        GamepadSupportMod.state.selecting_magick_ui = GamepadSupportMod.state.selecting_magick_ui == 1 and 0 or 1
    end)
    GamepadSupportMod.gamepad_mapper:add_on_input_handler("select_magick2_up", function ()
        GamepadSupportMod.state.selecting_magick_ui = GamepadSupportMod.state.selecting_magick_ui == 2 and 0 or 2
    end)
    GamepadSupportMod.gamepad_mapper:add_on_input_handler("select_magick3_up", function ()
        GamepadSupportMod.state.selecting_magick_ui = GamepadSupportMod.state.selecting_magick_ui == 3 and 0 or 3
    end)
    GamepadSupportMod.gamepad_mapper:add_on_input_handler("select_magick4_up", function ()
        GamepadSupportMod.state.selecting_magick_ui = GamepadSupportMod.state.selecting_magick_ui == 4 and 0 or 4
    end)

    local success, err = pcall(require, "GamepadSupport/overrides")
    if not success then
        k_log("[GamepadSupport] failed to execute overrides ::\n" .. tostring(err))
        return
    end

    kUtil.add_on_tick_handler(function (dt)
        GamepadSupportMod.gamepad_input_manager:update(dt)
        GamepadSupportMod.gamepad_mapper.input_dirty = true
    end)

    mod_inited = true
end

EventHandler.register_event("menu", "init", "GamepadSupport_init", init_mod)
EventHandler.register_event("ingame", "game_over", "GamepadSupport_init", reset_cursor)
