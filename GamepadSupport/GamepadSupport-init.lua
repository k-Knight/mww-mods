local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

_G.GamepadSupportMod = {
    settings = {

    }
}

local function init_mod()
    kUtil.task_scheduler.add(function ()
        SAVE_GLOBAL_MOD_SETTINGS("GamepadSupport", GamepadSupportMod.settings)
    end, 10)

    if mod_inited then
        return
    end

    GamepadSupportMod.settings = LOAD_GLOBAL_MOD_SETTINGS("GamepadSupport", GamepadSupportMod.settings)

    local success, err = pcall(require, "GamepadSupport/gamepadinput")
    if not success then
        k_log("[GamepadSupport] failed to load  GamepadSupport ::\n" .. tostring(err))
        return
    end

    GamepadSupportMod.gamepad_input_manager = GamepadInputManager()
    kUtil.add_on_tick_handler(function (dt)
        if GamepadSupportMod.gamepad_input_manager then
            GamepadSupportMod.gamepad_input_manager:update(dt)
        end
    end)

    local success, err = pcall(require, "GamepadSupport/overrides")
    if not success then
        k_log("[GamepadSupport] failed to execute overrides ::\n" .. tostring(err))
        return
    end

    mod_inited = true
end

EventHandler.register_event("menu", "init", "GamepadSupport_init", init_mod)
