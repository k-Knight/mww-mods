pcall(require, "AlternativeServerJoiner/login_server_joiner_direct")

local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    local status, err = pcall(require, "AlternativeServerJoiner/overrides")
    if not status then
        k_log("[AlternativeServerJoiner] ERROR initializing overrides ::\n" .. tostring(err))
    end

    mod_inited = true
end


EventHandler.register_event("login_screen", "init", "Test_init", init_mod)