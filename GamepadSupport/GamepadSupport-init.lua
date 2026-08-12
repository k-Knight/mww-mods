local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

_G.GamepadSupportMod = {
    settings = {

    },
    state = {
        is_gamepad_looking = false,
        cursor_moved = false,
        last_cursor_pos = {0, 0}
    }
}

local function reset_cursor()
    k_log("[GamepadSupport] exiting game, resetting cursor ...")

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

    GamepadSupportMod.settings = LOAD_GLOBAL_MOD_SETTINGS("GamepadSupport", GamepadSupportMod.settings)

    local success, err = pcall(require, "GamepadSupport/gamepadinput")
    if not success then
        k_log("[GamepadSupport] failed to load  GamepadInputManager ::\n" .. tostring(err))
        return
    end

    GamepadSupportMod.gamepad_input_manager = GamepadInputManager()

    local success, err = pcall(require, "GamepadSupport/gamepadmapping")
    if not success then
        k_log("[GamepadSupport] failed to load  GamepadMapper ::\n" .. tostring(err))
        return
    end

    GamepadSupportMod.gamepad_mapper = GamepadMapper()
    GamepadSupportMod.gamepad_mapper:bind_key("fire_up", {"a"})
    GamepadSupportMod.gamepad_mapper:bind_key("fire", {"a"})
    GamepadSupportMod.gamepad_mapper:bind_key("lightning_up", {"b"})
    GamepadSupportMod.gamepad_mapper:bind_key("lightning", {"b"})
    GamepadSupportMod.gamepad_mapper:bind_key("earth_up", {"x"})
    GamepadSupportMod.gamepad_mapper:bind_key("earth", {"x"})
    GamepadSupportMod.gamepad_mapper:bind_key("arcane_up", {"y"})
    GamepadSupportMod.gamepad_mapper:bind_key("arcane", {"y"})
    GamepadSupportMod.gamepad_mapper:bind_key("cold_up", {"left_trigger", "a"})
    GamepadSupportMod.gamepad_mapper:bind_key("cold", {"left_trigger", "a"})
    GamepadSupportMod.gamepad_mapper:bind_key("water_up", {"left_trigger", "b"})
    GamepadSupportMod.gamepad_mapper:bind_key("water", {"left_trigger", "b"})
    GamepadSupportMod.gamepad_mapper:bind_key("shield_up", {"left_trigger", "x"})
    GamepadSupportMod.gamepad_mapper:bind_key("shield", {"left_trigger", "x"})
    GamepadSupportMod.gamepad_mapper:bind_key("life_up", {"left_trigger", "y"})
    GamepadSupportMod.gamepad_mapper:bind_key("life", {"left_trigger", "y"})

    GamepadSupportMod.gamepad_mapper:bind_key("magick1_up", {"d_left"})
    GamepadSupportMod.gamepad_mapper:bind_key("magick1", {"d_left"})
    GamepadSupportMod.gamepad_mapper:bind_key("magick2_up", {"d_up"})
    GamepadSupportMod.gamepad_mapper:bind_key("magick2", {"d_up"})
    GamepadSupportMod.gamepad_mapper:bind_key("magick3_up", {"d_right"})
    GamepadSupportMod.gamepad_mapper:bind_key("magick3", {"d_right"})
    GamepadSupportMod.gamepad_mapper:bind_key("magick4_up", {"d_down"})
    GamepadSupportMod.gamepad_mapper:bind_key("magick4", {"d_down"})

    GamepadSupportMod.gamepad_mapper:bind_key("self_channel", {"right_shoulder"})
    GamepadSupportMod.gamepad_mapper:bind_key("cast_self", {"right_shoulder"})

    GamepadSupportMod.gamepad_mapper:bind_key("cursor", "right_thumb_axis")
    GamepadSupportMod.gamepad_mapper:bind_key("movement", "left_thumb_axis")
    GamepadSupportMod.gamepad_mapper:bind_key("aim_range_multiplier", "left_trigger_axis")

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
