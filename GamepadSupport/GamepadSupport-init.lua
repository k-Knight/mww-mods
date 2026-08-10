local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true
end