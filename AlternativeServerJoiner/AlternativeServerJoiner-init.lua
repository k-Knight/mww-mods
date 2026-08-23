local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

_G.AlternativeServerJoiner = {
    settings = {
        disable_xmpp = true
    }
}

local function init_mod(context)
    if mod_inited then
        return
    end

    kUtil.task_scheduler.add(function ()
        SAVE_GLOBAL_MOD_SETTINGS("AlternativeServerJoiner", AlternativeServerJoiner.settings)
    end, 10)

    mod_inited = true

    AlternativeServerJoiner.settings = LOAD_GLOBAL_MOD_SETTINGS("AlternativeServerJoiner", AlternativeServerJoiner.settings)
    
    local status, err = pcall(require, "AlternativeServerJoiner/lobby_proxy_juggler")
    if not status then
        k_log("[AlternativeServerJoiner] ERROR initializing LobbyProxyJuggler ::\n" .. tostring(err))
        return
    end

    status, err = pcall(require, "AlternativeServerJoiner/login_server_joiner_direct")
    if not status then
        k_log("[AlternativeServerJoiner] ERROR initializing LoginServerJoinerDirect ::\n" .. tostring(err))
        return
    end


    status, err = pcall(require, "AlternativeServerJoiner/overrides")
    if not status then
        k_log("[AlternativeServerJoiner] ERROR initializing overrides ::\n" .. tostring(err))
        return
    end
end

EventHandler.register_event("login_screen", "init", "AlternativeServerJoiner_init", init_mod)
