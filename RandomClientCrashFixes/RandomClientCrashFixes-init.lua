-- Add require stuff here
local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler


local function try_override_methods()
    repeat
        if not NetworkGameModeDuelClientGame or NetworkGameModeDuelClientGame._old_on_unit_resurrected then
            break
        end

        k_log("[RandomClientCrashFixes] fixing revive after round end crash (hopefully)")
        NetworkGameModeDuelClientGame._old_on_unit_resurrected = NetworkGameModeDuelClientGame.on_unit_resurrected

        NetworkGameModeDuelClientGame.on_unit_resurrected = function(self, peer_id, unit)
            if not (self.timpani_world and self.last_end_round_event_id) then
                return
            end

            return NetworkGameModeDuelClientGame._old_on_unit_resurrected(self, peer_id, unit)
        end
    until true

    kUtil.task_scheduler.add(try_override_methods, 1000)
end

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    kUtil.task_scheduler.add(try_override_methods, 1000)
end

EventHandler.register_event("menu", "init", "RandomClientCrashFixes_init", init_mod)
