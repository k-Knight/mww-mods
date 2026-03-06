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

local elementsMapping = {
    fire = "\xd8\x0f\x92\x5d\x73\x03\xa7\x96",
    arcane = "\x76\x22\xb0\x3b\xf0\xab\x46\xf6",
    cold = "\xb0\x8d\x04\x12\xc0\x69\x94\x14",
    earth = "\x8c\xd6\x51\xff\x43\xec\x17\x5c",
    life = "\x38\xe7\x7c\xf7\x53\x57\x13\xd3",
    lightning = "\x79\x20\x47\x63\x09\x96\x86\xcf",
    shield = "\xdd\x83\xb5\x4c\x83\xbe\x4b\x21",
    water = "\x44\xdc\x37\x00\x92\x4f\xb6\xc7",
}

_G.CEV_DATA = {
    elem_pos = {}
}

local draw_cev = function(self, dt, context)
    local scale = self.ui_renderer:get_scaling()
    local camera = CameraProxy:setup(self.game_camera, self.game_camera_unit, self.world)
    local ui_renderer = self.ui_renderer
    local elem_size = 26
    local elem_offset = elem_size / 2
    local texture_size = Vector2(elem_size, elem_size)

    for unit, elem_pos in pairs(CEV_DATA.elem_pos) do
        repeat
            local elem_opacity = elem_pos.opacity or 1

            if elem_opacity <= 0 then
                CEV_DATA.elem_pos[unit] = nil
                break
            end

            local pos = Vector3Aux.unbox(elem_pos.pos)
            local elem_type = elem_pos.elem
            local tint = Color(192 * math.sqrt(elem_pos.opacity), 255, 255, 255)

            pos = world_to_gui(camera, scale, pos, 50)
            pos.x = pos.x - elem_offset
            pos.y = pos.y - elem_offset

            local texture = elementsMapping[elem_type]
            if texture then
                ui_renderer:draw_texture(pos, texture_size, texture, tint)
            end
        until true
    end
end

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    local element_units = {
        shield = "content/units/effects/elements/shield",
        fire = "content/units/effects/elements/fire",
        arcane = "content/units/effects/elements/arcane",
        steam = "content/units/effects/elements/steam",
        water = "content/units/effects/elements/water",
        lightning = "content/units/effects/elements/lightning",
        cold = "content/units/effects/elements/cold",
        earth = "content/units/effects/elements/earth",
        life = "content/units/effects/elements/life",
        ice = "content/units/effects/elements/ice"
    }

    kUtil.loop_try_repalce_function(_G, "ElementUnitManager", "add_unit", function(self, element, index)
        if not self.cev_unit_types then
            self.cev_unit_types = {}
        end
        if not self.elem_shadow then
            self.elem_shadow = {}
        end

        local unit_type = element_units[element]
        local pos = Vector3.forward() + Vector3.up()
        local new_unit = self.unit_spawner:spawn_unit_local(unit_type)
        local eu = self.element_units
        local ind = index or #eu + 1

        table.insert(eu, ind, new_unit)
        Unit.set_local_position(new_unit, 0, pos)
        self.elem_shadow[new_unit] = { type = unit_type, unit = self.unit_spawner:spawn_unit_local(unit_type) }

        local em = self.element_movement
        local val = em[ind - 2] or ((#em / 3) * math.pi * 0.5)
        val = val + (math.pi * 0.5)

        table.insert(em, ind, val)

        for unit, _ in pairs(self.cev_unit_types) do
            if not (unit and Unit.alive(unit)) then
                self.cev_unit_types[unit] = nil
            end
        end

        self.cev_unit_types[new_unit] = unit_type:match("([^/]+)$")
    end)

    kUtil.loop_try_repalce_function(_G, "ElementUnitManager", "remove_unit", function(self, ind)
        local eu = self.element_units
        local es = self.elem_shadow
        local to_rem = table.remove(eu, ind)

        if es[to_rem] and es[to_rem].unit then
            self.unit_spawner:mark_for_deletion(es[to_rem].unit)
            es[to_rem] = nil
        end

        self.unit_spawner:mark_for_deletion(to_rem)
    end)

    kUtil.loop_try_repalce_function(_G, "ElementUnitManager", "clear", function(self, ind)
        local eu = self.element_units
        local us = self.unit_spawner
        local es = self.elem_shadow

        for i, u in ipairs(eu) do
            if u then
                if es[u] and es[u].unit then
                    self.unit_spawner:mark_for_deletion(es[u].unit)
                    es[u] = nil
                end

                us:mark_for_deletion(u)

                eu[i] = nil
            end
        end
    end)

    kUtil.loop_try_prehook_function(_G, "Gui2DSystem", "draw_elements", function(...)
        return true
    end)

    kUtil.loop_try_repalce_function(_G, "ElementUnitManager", "update", function(self, dt)
        local eu = self.element_units
        local em = self.element_movement
        local dir = 1
        local opos = Unit.world_position(self.owner, 0)
        local elem_pos = CEV_DATA.elem_pos

        if not self.elem_shadow then
            self.elem_shadow = {}
        end

        local es = self.elem_shadow

        for _, elem_pos in pairs(elem_pos) do
            elem_pos.opacity = elem_pos.opacity - (dt * 3.5)
        end

        for i, u in ipairs(eu) do
            if u then
                local mov = em[i] + dt * 2 * dir

                mov = mov < 0 and mov + (math.pi * 2) or mov
                mov = mov > (math.pi * 2) and mov - (math.pi * 2) or mov
                em[i] = mov

                local x = math.cos(mov)
                local y = math.sin(mov)
                local z = math.sin(mov * 0.5) + 1
                local pos = opos + Vector3(x, y, z + 0.2)

                Unit.set_local_position(u, 0, pos)

                if es[u] then
                    Unit.set_local_position(es[u].unit, 0, pos)
                end

                local unit_type = self.cev_unit_types[u]
                if unit_type then
                    elem_pos[u] = { elem = unit_type, pos = Vector3Aux.box({}, pos), opacity = 1 }
                end

                dir = dir * -1
            end
        end

        CEV_DATA.elem_pos = elem_pos
    end)

    kUtil.add_on_gui_update_handler(draw_cev)
end


EventHandler.register_event("menu", "init", "ClearerElementView_init", init_mod)
