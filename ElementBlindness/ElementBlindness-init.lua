local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    kUtil.loop_try_repalce_function(_G, "ElementUnitManager", "add_unit", function(self, element, index)
        return
    end)
end


EventHandler.register_event("menu", "init", "ElementBlindness_init", init_mod)
