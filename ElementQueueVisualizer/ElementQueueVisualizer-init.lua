-- Add require stuff here
local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

local Resolution = require_bs("foundation/scripts/util/engine/resolution")

local function world_to_gui(camera, scale, position, z_offset)
	local pos = camera:world_to_screen(position)

	pos.y, pos.z = pos.z, pos.y
	pos.x, pos.y = Resolution.clip_to_viewport(pos.x, pos.y)
	pos = Vector3Aux.round(pos / scale)
	pos.z = z_offset or pos.z

	return pos
end

_G.EQD = {}

local on_gui_update = function(self, dt, context)
    EQD.is_spectator = self.is_spectator
    local time = os.clock()

    for unit, elem_data in pairs(EQD) do
        if unit and Unit.alive(unit) and (time - elem_data.time) < 0.5 then
            local pos = Unit.world_position(unit, 0)
            local scale = self.ui_renderer:get_scaling()
            local camera = CameraProxy:setup(self.game_camera, self.game_camera_unit, self.world)
    
            pos = world_to_gui(camera, scale, pos, 50)
    
            self:draw_elements(elem_data.elements, pos)
        else
            EQD[unit] = nil
        end
    end
end

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    kUtil.loop_try_repalce_function(_G, "ElementQueue", "update", function(self, dt, spellwheel_state)
        local u = self.owner
        local gui_2d_ext = EntityAux.extension(u, "gui_2d")
        local time = os.clock()

        local not_my_unit = false
        if gui_2d_ext then
            local internal = gui_2d_ext.internal
            local is_spectated_unit = EQD.is_spectator and rawget(_G, "CURRENTLY_SPECTATED_UNIT") == u

            not_my_unit = not (spellwheel_state and (internal.is_player or is_spectated_unit))
        else
            not_my_unit = true
        end

        if (#(self.element_queue) > 1) and not_my_unit then
            EQD[u] = {
                time = time,
                elements = table.deep_clone(self.element_queue)
            }
        end
        
        if gui_2d_ext then
            EntityAux.set_input_by_extension(gui_2d_ext, "elements", self.element_queue)
        end

        spellwheel_state.queued_elements = #self.element_queue
        
        self.element_unit_manager:update(dt)
    end)

    kUtil.add_on_gui_update_handler(on_gui_update)
end

EventHandler.register_event("menu", "init", "ElementQueueVisualizer_init", init_mod)
