require("scripts/game/entity_system/systems/character/character_state_machine")

kUtil.loop_try_posthook_function(_G, "CharacterStateMachine", "init", function (self, context)
    for char_state_name, state in pairs(self._states) do
        k_log("[RukozhopHelp] overridng CharacterState[" .. tostring(char_state_name) .. "].update() !!!")
        if not state._old_update then
            state._old_update = state.update
            state.update = function(self, context)
                if RukozhopHelpMod.settings.input_queue_enabled then
                    local input_data = context.input_data
                    local internal = context.internal
                    local input = nil
                    local os_time = os.clock()
    
                    if input_data and internal then
                        if not input_data.wait_for_rmb_release and input_data.cast_spell and input_data.cast_spell > 0 and internal.previous_cursor ~= "magick" and internal.current_cursor ~= "magick" then
                            input = internal.current_cursor == "default" and "forward" or internal.current_cursor
                        elseif not input_data.wait_for_mbb_release and input_data.cast_self > 0 then
                            input = "self"
                        end
        
                        if not input_data.iq_data then
                            input_data.iq_data = {}
                        end
        
                        if input then
                            repeat
                                if input_data.iq_data.last_input == "forward" and input == "weapon" then
                                    break
                                end
        
                                input_data.iq_data.last_input = input
                                input_data.iq_data.last_time = os_time
                            until true
                        end
                    end
                end

                return self._old_update(self, context)
            end
        end

        k_log("[RukozhopHelp] overridng CharacterState[" .. tostring(char_state_name) .. "].handle_spellwheel_input() !!!")
        state.handle_spellwheel_input = function (self, unit, input_data, internal)
            local sw_ext = internal.spellwheel_ext
            local element_queue = table.deep_clone(sw_ext and sw_ext.state and sw_ext.state.element_queue and sw_ext.state.element_queue.element_queue or {})
            local max_elements = (#element_queue) > 2
            local same_elem_queue = true
            local prev_element_queue = input_data.iq_data and input_data.iq_data.prev_element_queue or {}

            if (#element_queue) ~= (#prev_element_queue) then
                same_elem_queue = false
            else
                for k, v in pairs(element_queue) do
                    if prev_element_queue[k] ~= v then
                        same_elem_queue = false
                        break
                    end
                end
            end

            if not input_data.wait_for_rmb_release and input_data.cast_spell and input_data.cast_spell > 0 and internal.previous_cursor ~= "magick" and internal.current_cursor ~= "magick" then
                input_data.spell_cast = internal.current_cursor == "default" and "forward" or internal.current_cursor
            elseif not input_data.wait_for_mbb_release and input_data.cast_self > 0 then
                input_data.spell_cast = "self"
            else
                input_data.spell_cast = nil
            end

            if max_elements and same_elem_queue then
                input_data.wait_for_rmb_release = false
                input_data.wait_for_mbb_release = false

                if not input_data.spell_cast and input_data.iq_data then
                    local time = os.clock()
                    local last_input_time = input_data.iq_data.last_time or 0
    
                    if (time - last_input_time) < 0.25 then
                        input_data.spell_cast = input_data.iq_data.last_input
                        k_log("[RukozhopHelp] carrying over input :: " .. tostring(input_data.spell_cast))
                    end
                end
            end

            if input_data.iq_data then
                if not same_elem_queue then
                    k_log("[RukozhopHelp] elements changed, resetting queue ...")
                    input_data.iq_data.last_time = 0
                end
                input_data.iq_data.prev_element_queue = element_queue
            end

            EntityAux.set_input_by_extension(sw_ext, "input_data", input_data)
        end
    end
end)

kUtil.loop_try_repalce_function(_G, "SpellWheelSystem", "update", function (self, dt, context)
    local entities, entities_n = self:get_entities("spellwheel")
    local player_variable_manager = self.player_variable_manager
    local EntityAux_set_input = EntityAux.set_input
    local all_elements = AllElements
    local all_elements_n = #AllElements
    local network = self.network_transport

    for i = 1, entities_n do
        repeat
            local extension_data = entities[i]
            local u, extension = extension_data.unit, extension_data.extension
            local internal = extension.internal
            local input = extension.input
            local input_data = input.input_data or input

            input.input_data = nil

            local element_queue = internal.element_queue
            local last_elements = internal.last_elements
            local cast_cooldown = internal.cast_cooldown

            if cast_cooldown then
                cast_cooldown = cast_cooldown - dt

                if cast_cooldown < 0 then
                    cast_cooldown = nil
                end

                internal.cast_cooldown = cast_cooldown
            end

            if not input.dirty_flag then
                element_queue:update(dt, extension.state)

                for k, v in pairs(last_elements) do
                    last_elements[k] = nil
                end

                break
            end

            if input.enable then
                internal.enabled = true
                input.enable = nil
            end

            if input.disable then
                internal.enabled = false
                input.clear_spellwheel = true
                input.disable = nil
            end

            if input.clear_spellwheel then
                element_queue:clear()
                network:transmit_to_server(u, "rpc_from_client_clear_element_queue")

                input.clear_spellwheel = nil
            end

            input.dirty_flag = false

            if not internal.enabled then
                break
            end

            local state = extension.state
            local new_elements = FrameTable.alloc_table()
            local disabled_elements = state.disabled_elements
            local go_id = NetworkUnit.game_object_id(u)

            for j = 1, all_elements_n do
                local elem = all_elements[j]

                if input_data[elem] and (not disabled_elements or not disabled_elements[elem]) then
                    internal.element_queue:queue_element(elem)

                    new_elements[elem] = true

                    local element_id = NetworkLookup.elements[elem]

                    network:transmit_to_server(u, "rpc_from_client_queue_element", element_id)
                end
            end

            for k, _ in pairs(last_elements) do
                last_elements[k] = nil
            end

            for k, v in pairs(new_elements) do
                last_elements[k] = v
            end

            local spell_cast = input_data.spell_cast
            local spellcast_ext = EntityAux.extension(u, "spellcast")

            if spell_cast and (not cast_cooldown or spell_cast == "weapon") and not spellcast_ext.internal._waiting_spell.name then
                element_queue:process_element_combinations()

                local selected_elements, num_elements = element_queue:get_elements()
                local element_queue_raw = element_queue:get_element_queue()

                element_queue:clear()
                network:transmit_to_server(u, "rpc_from_client_clear_element_queue")

                k_log("[RukozhopHelp] player casting spell :: " .. tostring(spell_cast))

                local spellcast_input = {
                    spell_type = spell_cast,
                    elements = selected_elements,
                    num_elements = num_elements,
                    element_queue = element_queue_raw
                }

                if input_data.iq_data then
                    k_log("[RukozhopHelp] resetting player input due to :: " .. tostring(spell_cast))
                    input_data.iq_data.last_time = 0
                end

                self.event_delegate:trigger2("player_spell_cast", spellcast_input)
                EntityAux_set_input(u, "spellcast", spellcast_input)

                input_data.spell_cast = nil
                internal.cast_cooldown = SpellSettings.cast_cooldown * player_variable_manager:get_variable(u, "cast_cooldown")
            end

            element_queue:update(dt, extension.state)
        until true
    end

    entities, entities_n = self:get_entities("spellwheel_husk")

    for i = 1, entities_n do
        local extension_data = entities[i]
        local u, extension = extension_data.unit, extension_data.extension

        extension.internal.element_queue:update(dt, extension.state)
    end
end)

kUtil.loop_try_prehook_function(_G, "ClientSpellCastingSystem", "_handle_spellcast", function (self, unit, input, internal, state, target)
    RukozhopHelpMod.state.casting_new_spell = true
end)

local tmp_context

kUtil.loop_try_prehook_function(_G, "ClientSpells_Weapon", "update", function(data, context)
    tmp_context = context
end)

kUtil.loop_try_posthook_function(_G, "ClientSpells_Weapon", "update", function(data, context)
    local my_context = tmp_context or context
    local caster = my_context.caster or my_context.caster

    if caster and Unit.alive(caster) then
        local owns_this = pdNetworkServerUnit.owning_peer_is_self(caster)
        local state = data.state

        if owns_this then
            RukozhopHelpMod.state.casting_weapon_attack = state == "charge_attacking_waiting_for_end" or state == "chain_attacking_waiting_for_end" or state == "chain_attacking_in_window"
        end
    end

    tmp_context = nil
end)

local hud_intersect_input_data_clear = {
    "interact",
    "click",
    "activate",
    "try_pickup",
    "cast_spell",
    "activate_magick",
    "twist_free"
}

local hud_intersect_inputdata_set_to_zero = {
    "do_move"
}

local additive_speed_modifier_categories = {
    gear = true
}

local CharacterSettings = require("scripts/game/settings/templates/character_system_settings")

local cursors = GameSettings.cursors

local function character_setting(unit)
    local ct = Unit.get_data(unit, "character_template") or "default"
    local cs = CharacterSettings
    local val = cs[ct]

    if not val then
        assert(false, "[charcter_settings] no settings for " .. ct)
    end

    return val
end

local function disable_input_data(input_data)
    input_data.move = nil
    input_data.cursor = nil

    for v, val in pairs(input_data) do
        if type(val) == "number" then
            input_data[v] = 0
        elseif type(val) == "boolean" then
            input_data[v] = false
        elseif type(val) == "table" then
            for b, _ in pairs(val) do
                val[b] = nil
            end
        elseif type(val) == "string" then
            input_data[v] = nil
        else
            assert(type(val) == "vector3", "Bad type!")

            input_data[v] = Vector3.zero()
        end
    end
end

local function handle_slowing_units(input, internal)
    local sunits = input.slowing_units
    local isunits = internal.slowing_units

    if sunits > 0 and isunits == 0 then
        local loco_ext = internal.loco_ext

        if loco_ext then
            internal.prev_velocity_smooth = loco_ext.state.velocity_smooth
            loco_ext.state.velocity_smooth = 0.002
        end
    elseif sunits == 0 and isunits > 0 then
        local loco_ext = internal.loco_ext

        if loco_ext then
            loco_ext.state.velocity_smooth = internal.prev_velocity_smooth
        end
    end

    internal.slowing_units = sunits
end

local function handle_speed_modifiers(input, internal)
    if internal.speed_modifier_override then
        input.scale_velocity = internal.speed_modifier_override
    else
        local speed_modifiers = internal.speed_modifiers

        speed_modifiers.dirty_flag = nil

        local final_modifier = 1

        for category, modifiers in pairs(speed_modifiers) do
            if additive_speed_modifier_categories[category] then
                local additive_modifier = 1

                for _, modifier in pairs(modifiers) do
                    additive_modifier = additive_modifier + (modifier - 1)
                end

                final_modifier = final_modifier * additive_modifier
            else
                for _, modifier in pairs(modifiers) do
                    final_modifier = final_modifier * modifier
                end
            end
        end

        input.scale_velocity = final_modifier
    end
end

local function spawn_aim_unit(unit_spawner, template_tex, override_texture)
    local scale = Vector3(0.75, 0.75, 0.75)
    local dot_color = Vector3(0.85, 0.85, 0.85)
    local aim_unit = unit_spawner:spawn_unit_local(template_tex, Vector3(100000, 100000, 100000), Quaternion.identity())

    local mesh = Unit.mesh(aim_unit, "g_body")
    local material = Mesh.material(mesh, "g_material") or Mesh.material(mesh, "decal_mat")

    if material then
        Material.set_vector3(material, "color_tint", dot_color)
        Material.set_vector3(material, "scale", scale)

        if override_texture then
            Material.set_texture(material, override_texture.name, override_texture.path)
        end
    end
    return aim_unit
end

local PROJECTION_PATH = "content/units/effects/projections/"
local DOT_AIM_TEX = PROJECTION_PATH .. "projection_magick_target_dot"

kUtil.loop_try_repalce_function(_G, "ClientCharacterSystem", "update_characters", function(self, dt)
    local debug_drawing_enabled = false
    local debug_drawing_disabled = not debug_drawing_enabled
    local movement_convenience = RukozhopHelpMod.mov_conv_active
    local camera = CameraProxy:setup(self.game_camera, self.game_camera_unit, self.world)
    local EntityAux_set_input = EntityAux.set_input
    local is_in_combat = false
    local unit_spawner = self.unit_spawner
    local state_context = self.character_update_context

    state_context.is_local = true
    state_context.dt = dt

    local network = self.network_transport
    local cane_navmeshquery = self.cane_character_navmeshquery_reference
    local entities, entities_n = self:get_entities("character")
    local was_hud_gui_intersect = self.hud_gui_intersects
    local hud_gui_intersects

    if entities_n > 0 then
        hud_gui_intersects = self.hud_manager.cursor_intersects
    end

    if hud_gui_intersects then
        Window.set_cursor(cursors.hud)
    end

    local failsafe_switch_back = was_hud_gui_intersect and not hud_gui_intersects

    self.hud_gui_intersects = hud_gui_intersects

    for i = 1, entities_n do
        local extension_data = entities[i]
        local unit, extension = extension_data.unit, extension_data.extension
        local unit_world_position = Unit.world_position(unit, 0)
        local internal = extension.internal
        local input = extension.input
        local state = extension.state
        local input_controller_state = internal.input_ext.state
        local input_data = input_controller_state.input_data

        local magick_cursor = internal.current_cursor == "magick"

        state_context.animation_scaled_dt = dt * internal.spellcast_ext.state.spellcast_scale

        if input.visible then
            input.visible = nil
            state.visible = true
        elseif input.invisible then
            input.invisible = nil
            state.visible = false
        end

        if input.respawn_prepare then
            input.respawn_prepare = nil
            state.respawn_prepare = true
            state.corpse_original_pos = Vector3Aux.box({}, Unit.local_position(unit, 0))
        end

        if input.respawn_abort then
            input.respawn_abort = nil
            state.respawn_prepare = false
            state.respawn_abort = true
        end

        if input.clear_magick_projection_units then
            input.clear_magick_projection_units = nil

            if internal.magick_projection_unit then
                CharacterSystemAux_delete_clear_projection_units_data(internal, unit_spawner)
            end
        end

        if self.input_disabled or input.disabled or input.disabled_ui then
            disable_input_data(input_data)
        elseif input_data.cursor then
            if not movement_convenience then
                RukozhopHelpMod.last_cur = {}
                RukozhopHelpMod.last_cur[1] = input_data.cursor[1]
                RukozhopHelpMod.last_cur[2] = input_data.cursor[2]
            else
                input_data.cursor[1] = RukozhopHelpMod.last_cur[1]
                input_data.cursor[2] = RukozhopHelpMod.last_cur[2]
            end

            if failsafe_switch_back then
                Window.set_cursor(cursors[internal.current_cursor])
            end

            local cursor_delta_x, cursor_delta_y

            if movement_convenience and not hud_gui_intersects then
                local cur_cursor

                if RukozhopHelpMod.first_pass then
                    RukozhopHelpMod.first_pass = false
                    cur_cursor = {RukozhopHelpMod.draw_x, RukozhopHelpMod.draw_y}
                    Window.set_cursor_position(Vector2(RukozhopHelpMod.draw_x, RukozhopHelpMod.draw_y))
                else
                    cur_cursor = Mouse.axis(Mouse.axis_index("cursor"), Mouse.RAW, 3)
                end


                cursor_delta_x = cur_cursor[1] - RukozhopHelpMod.draw_x
                cursor_delta_y = cur_cursor[2] - RukozhopHelpMod.draw_y

                local dist = math.sqrt(cursor_delta_x * cursor_delta_x + cursor_delta_y * cursor_delta_y)
                local max_dist = RukozhopHelpMod.screen_scale / 40

                if dist > max_dist then
                    local new_dist = dist / max_dist
                    local new_delta_x = cursor_delta_x / new_dist
                    local new_delta_y = cursor_delta_y / new_dist
                    Window.set_cursor_position(Vector2(RukozhopHelpMod.draw_x + new_delta_x, RukozhopHelpMod.draw_y + new_delta_y))
                end

                local not_dead_zone = (dist / max_dist) > 0.2
                cursor_delta_x = cur_cursor[1] - RukozhopHelpMod.draw_x
                cursor_delta_y = cur_cursor[2] - RukozhopHelpMod.draw_y
                cursor_delta_x = not_dead_zone and cursor_delta_x or 0
                cursor_delta_y = not_dead_zone and cursor_delta_y or 0
            end

            if not hud_gui_intersects then
                self:handle_input_data(unit, input_data, internal.input_ext, internal, state)
            else
                for i = 1, #hud_intersect_input_data_clear do
                    input_data[hud_intersect_input_data_clear[i]] = false
                end

                for i = 1, #hud_intersect_inputdata_set_to_zero do
                    input_data[hud_intersect_inputdata_set_to_zero[i]] = 0
                end
            end

            local cursor = input_data.cursor
            local cam, dir = camera:screen_ray(cursor[1], cursor[2])
            local plane = Plane.from_point_and_normal(unit_world_position, Vector3.up())
            local t = Intersect.ray_plane(cam, dir, plane)
            local intersect_pos

            if t then
                intersect_pos = cam + dir * t
            end

            local ignore_click = hud_gui_intersects or input.ignore_click
            local activate_position = not ignore_click and intersect_pos
            local my_force_move = false
            local my_force_stop = false

            if intersect_pos and movement_convenience and cursor_delta_x and cursor_delta_y then
                if cursor_delta_x == 0 or cursor_delta_y == 0 then
                    my_force_stop = true
                else
                    local base_mov, base_dir = camera:screen_ray(RukozhopHelpMod.draw_x, RukozhopHelpMod.draw_y)
                    local dest_mov, dest_dir = camera:screen_ray(RukozhopHelpMod.draw_x + cursor_delta_x, RukozhopHelpMod.draw_y + cursor_delta_y)

                    local base_intersect_pos = base_mov + base_dir * t
                    local dest_intersect_pos = dest_mov + dest_dir * t
                    local dir = dest_intersect_pos - base_intersect_pos

                    dir.z = 0
                    dir = Vector3.normalize(dir)

                    if Vector3.length(dir) > 0.3 and unit and Unit.alive(unit) then
                        intersect_pos = Unit.world_position(unit, 0) + (dir * 100)
                        my_force_move = true
                    end
                end
            end

            CharacterSystemAux_update_pending_magicks(unit, input, input_data, internal, activate_position, unit_spawner, self.entity_manager, cane_navmeshquery, dt)

            if my_force_stop or input_data.move_stop > 0 or input_data.do_move < 0.5 and internal.loco_ext.state.blocked then
                internal.move_destination = nil

                if internal.move_to_unit then
                    self.unit_spawner:mark_for_deletion(internal.move_to_unit)

                    internal.move_to_unit = nil
                end

                if internal.click_unit then
                    self.unit_spawner:mark_for_deletion(internal.click_unit)

                    internal.click_unit = nil
                end

                state.move_velocity = 0
            end

            if intersect_pos and (input_data.do_move > 0.5 and not ignore_click and internal.was_clicked or input_data.set_move_target and not ignore_click) and input_data.move_stop == 0 or my_force_move then
                if self.gamemode.gamemode_configuration.client.allow_minimap_ping and input_data.minimap_ping > 0 and (not my_force_move) then
                    self.event_delegate:trigger("on_world_click_ping", intersect_pos)
                else
                    if not self.time_since_last_move_rpc or Application.time_since_launch() - self.time_since_last_move_rpc > 2 then
                        self.time_since_last_move_rpc = Application.time_since_launch()

                        self.network_transport:transmit_message_to_server("rpc_from_client_player_moved")
                    end

                    internal.was_clicked = true
                    internal.disable_turning_to_cursor = nil

                    local path, path_n = PathAux_get_path(cane_navmeshquery, unit_world_position, intersect_pos)
                    local last_navmesh_position = path[path_n]
                    local last_navmesh_position_vec3 = Vector3Aux.unbox(last_navmesh_position)

                    internal.move_destination = last_navmesh_position
                    internal.move_path_info = {
                        current_index = 1,
                        path = path,
                        path_n = path_n
                    }
                    internal.was_clicked = true

                    if not internal.click_unit and input_data.set_move_target then
                        if Development_ui_enabled() then
                            internal.click_unit = self.unit_spawner:spawn_unit_local(GameSettings.move_to_unit_click, intersect_pos)
                        end
                    elseif internal.click_unit then
                        Unit.set_local_position(internal.click_unit, 0, intersect_pos)
                    end

                    if not internal.move_to_unit then
                        if Development_ui_enabled() then
                            internal.move_to_unit = self.unit_spawner:spawn_unit_local(GameSettings.move_to_unit, last_navmesh_position_vec3)
                        end
                    else
                        Unit.set_local_position(internal.move_to_unit, 0, last_navmesh_position_vec3)
                    end
                end
            end

            internal.was_clicked = internal.was_clicked and input_data.do_move > 0.5 or false

            local look_plane = Plane.from_point_and_normal(unit_world_position + Vector3.up(), Vector3.up())
            local look_t = Intersect.ray_plane(cam, dir, look_plane)

            if movement_convenience then
                look_t = nil
            end

            if look_t then
                local look_intersect_pos = cam + dir * look_t
                local look_aim_dir = unit_world_position - look_intersect_pos

                look_aim_dir.z = 0

                if Vector3.length(look_aim_dir) > 0 and not internal.disable_turning_to_cursor then
                    local look_direction = Vector3.normalize(look_aim_dir)

                    internal.loco_ext.input.wanted_rotation = QuaternionAux.box({}, Quaternion.look(-look_direction, Vector3.up()))
                    internal.loco_ext.dirty_flag = true
                end

                local activate_position = not ignore_click and look_intersect_pos
                local d = pdDebug.drawer("activate_position", not DevelopmentSetting_bool("activate_position_debugging"))

                d:reset()

                if activate_position and (input_data.spell_channel > 0 or input_data.self_channel > 0) and pdNetworkServerUnit.owning_peer_is_self(unit) then
                    local freen_world_direction = state.freen_world_direction
                    local diff = activate_position - unit_world_position

                    diff[3] = 0

                    local normalized_diff = Vector3.normalize(diff)
                    freen_world_direction[1], freen_world_direction[2] = normalized_diff[1], normalized_diff[2]
                end
            end

            if internal.move_destination then
                if not self.time_since_last_move_rpc or Application.time_since_launch() - self.time_since_last_move_rpc > 2 then
                    self.time_since_last_move_rpc = Application.time_since_launch()

                    self.network_transport:transmit_message_to_server("rpc_from_client_player_moved")
                end

                local move_path_info = internal.move_path_info
                local path, path_n = move_path_info.path, move_path_info.path_n
                local current_index = move_path_info.current_index
                local path_position, current_index, end_of_path = PathAux_get_path_index(path, path_n, move_path_info.current_index, unit_world_position, 0.2)

                move_path_info.current_index = current_index

                local aim_dir = unit_world_position - path_position
                local aim_dir_length = Vector3.length(aim_dir)

                if aim_dir_length < 0.1 then
                    if input_data.do_move < 0.5 then
                        input.stop_move_destination = true
                    end
                else
                    local direction = Vector3.normalize(aim_dir)

                    direction.z = 0
                    input_data.move = Vector3Aux.box({}, direction)
                    aim_dir.z = 0
                    aim_dir_length = Vector3.length(aim_dir)

                    local aim_len = aim_dir_length

                    if aim_len > 1 or not end_of_path then
                        state.move_velocity = internal.move_velocity
                    elseif aim_len < 0.2 then
                        if input_data.do_move < 0.5 then
                            input.stop_move_destination = true
                        end

                        state.move_velocity = 0
                    else
                        state.move_velocity = internal.move_velocity * (aim_len / 1)
                    end
                end
            end

            if input_data.move_stop > 0 then
                input.stop_move_destination = true
            end
        end

        local chg_is_charging = input_data.spell_channel > 0.5 and internal.prev_chenneling_input

        if not RukozhopHelpMod.state.casting_new_spell and RukozhopHelpMod.settings.aiming_recticles_enabled and chg_is_charging and (not magick_cursor) then
            repeat
                if RukozhopHelpMod.state.casting_weapon_attack then
                    break
                end

                if internal.spellcast_ext and internal.spellcast_ext.internal and internal.spellcast_ext.internal._waiting_spell then
                    local waiting_spell = internal.spellcast_ext.internal._waiting_spell
                    local waiting_data = waiting_spell.data

                    if waiting_data then
                        local elements = waiting_data.elements

                        if elements then
                            local has_ice = elements.ice > 0
                            local has_rock = elements.earth > 0

                            internal.chg_aim_spell_elems = {
                                has_ice = has_ice,
                                has_rock = has_rock,
                                rock_amnt = elements.earth,
                                ice_amnt = elements.ice
                            }

                            if not (has_ice or has_rock) then
                                break
                            end
                        end
                    end
                end

                local rel_spell_elems = internal.chg_aim_spell_elems
                if rel_spell_elems and not (rel_spell_elems.has_ice or rel_spell_elems.has_rock) then
                    break
                end

                local desired_units
                local dot_distance = 1.75

                local charge_time = internal.chg_charge_time or 0
                charge_time = charge_time + (charge_time > 2.0 and 0 or dt)
                internal.chg_charge_time = charge_time

                if charge_time == 0 then
                    internal.chg_count_aim_units = 0
                end

                local covered_distance = charge_time * 10

                if rel_spell_elems then
                    if rel_spell_elems.has_rock and not rel_spell_elems.has_ice then
                        covered_distance = covered_distance + 1
                        local rock_amnt = rel_spell_elems.rock_amnt
                        local mult = rock_amnt == 3 and 0.63 or (rock_amnt == 2 and 0.80 or 1.0)

                        covered_distance = ((rock_amnt - 2) * 0.5 + covered_distance) * mult
                    elseif not rel_spell_elems.has_rock then
                        covered_distance = (covered_distance - 1.5) / 1.35
                    end

                    covered_distance = covered_distance < 30 and covered_distance or 30
                    desired_units = math.floor(covered_distance / dot_distance)
                    internal.chg_fixed_length = false
                else
                    desired_units = 4
                    covered_distance = dot_distance * (desired_units + 1)
                    internal.chg_fixed_length = true
                end

                covered_distance = covered_distance >= 0 and covered_distance or 0

                if not internal.chg_aim_units then
                    internal.chg_aim_units = {}
                    internal.chg_colored_dots = 1
                    internal.chg_aim_units[1] = spawn_aim_unit(unit_spawner, DOT_AIM_TEX, {name = "\xb5\xce\x3d\xd0\x83\x1b\x92\xa8", path = "\x30\x30\x7d\xd0\x9e\x16\xbe\x3b"})
                end

                if internal.chg_aim_units then
                    while #internal.chg_aim_units < (desired_units + 1) do
                        internal.chg_aim_units[#internal.chg_aim_units + 1] = spawn_aim_unit(unit_spawner, DOT_AIM_TEX)
                    end

                    local rot, aim, pos
                    local freen_world_direction = state.freen_world_direction
                    pos = Unit.local_position(unit, 0)

                    if freen_world_direction and freen_world_direction[1] and freen_world_direction[2] then
                        aim = Vector3(freen_world_direction[1], freen_world_direction[2], 0)
                        rot = Quaternion.look(aim, Vector3.up())
                    else
                        rot = Unit.local_rotation(unit, 0)
                        aim = Quaternion.forward(rot)
                    end

                    pos[3] = pos[3] + 0.05
                    local end_pos = pos + aim * (covered_distance + 1)

                    for i, aim_unit in ipairs(internal.chg_aim_units) do
                        Unit.teleport_local_position(aim_unit, 0, end_pos - (i - 1) * dot_distance * aim)
                        Unit.teleport_local_rotation(aim_unit, 0, rot)
                    end
                end
            until true
        else
            if internal.chg_casting_new_spell then
                RukozhopHelpMod.state.casting_new_spell = false
                RukozhopHelpMod.state.casting_weapon_attack = false
            else
                internal.chg_casting_new_spell = RukozhopHelpMod.state.casting_new_spell
            end

            if internal.chg_aim_units then
                for i, aim_unit in ipairs(internal.chg_aim_units) do
                    unit_spawner:mark_for_deletion(aim_unit)
                end

                internal.chg_aim_units = nil
            end

            internal.chg_charge_time = 0
            internal.chg_fixed_length = false
            internal.chg_aim_spell_elems = nil
        end

        internal.prev_chenneling_input = input_data.spell_channel > 0.5

        if input.stop_move_destination then
            if internal.move_destination then
                local dest = Vector3Aux.unbox(internal.move_destination)
                local dist = Vector3.length(dest - unit_world_position)

                if dist > 1.0 then
                    input.stop_move_destination = false
                end
            end
        end

        if input.stop_move_destination then
            if input_data.do_move < 0.5 then
                input.stop_move_destination = nil
                internal.move_destination = nil

                if internal.move_to_unit then
                    self.unit_spawner:mark_for_deletion(internal.move_to_unit)

                    internal.move_to_unit = nil
                end

                if internal.click_unit then
                    self.unit_spawner:mark_for_deletion(internal.click_unit)

                    internal.click_unit = nil
                end

                state.move_velocity = 0
            else
                input.stop_move_destination = nil
            end
        elseif internal.move_to_unit then
            local current_rot = Unit.local_rotation(internal.move_to_unit, 0)
            local rot_amount = Quaternion(Vector3.up(), math.degrees_to_radians(90) * dt)

            Unit.set_local_rotation(internal.move_to_unit, 0, Quaternion.multiply(current_rot, rot_amount))

            if internal.click_unit then
                local time = (internal.click_time or 0.3) - dt

                internal.click_time = time

                if time < 0 then
                    self.unit_spawner:mark_for_deletion(internal.click_unit)

                    internal.click_unit = nil
                    internal.click_time = nil
                else
                    local click_unit = internal.click_unit
                    local mesh = Unit.mesh(click_unit, "g_body")
                    local material = Mesh.material(mesh, 0)

                    Material.set_vector3(material, "scale", Vector3(math.sin(time * 3.33) * 1.5, math.sin(time * 3.33) * 1.5, 2))
                end
            end
        end

        handle_slowing_units(input, internal)

        if internal.speed_modifiers.dirty_flag then
            handle_speed_modifiers(input, internal)

            if input.scale_velocity then
                assert(type(input.scale_velocity) == "number", "Error: Wrong type of scale velocity set on character extension.")

                local loco_ext = internal.loco_ext
                local loco_input = loco_ext.input

                loco_input.dirty_flag = true
                loco_input.scale_velocity = input.scale_velocity
                input.scale_velocity = nil
            end
        end

        if input_data.move then
            local m = input_data.move

            m[1] = -m[1]
            m[2] = -m[2]
            m[3] = -m[3]
        end

        if input_data.wait_for_rmb_release and input_data.hold_magick == 0 and input_data.cast_spell == 0 and input_data.spell_channel == 0 then
            input_data.wait_for_rmb_release = nil
        end

        if input_data.wait_for_mbb_release and input_data.cast_self == 0 then
            input_data.wait_for_mbb_release = nil
        end

        state_context.input = input
        state_context.input_data = input_data
        state_context.unit = unit
        state_context.state = state
        state_context.internal = internal
        state_context.gui_manager = self.gui_manager

        internal.state_machine:update(state_context)

        if input.stop_moving then
            internal.move_destination = nil
            state.move_velocity = 0
        end

        local state_name = internal.state_machine._state_name

        state.current_state = state_name

        local input_impulse = input.impulse

        input.impulse = nil

        local loco_ext = internal.loco_ext

        if loco_ext then
            loco_ext.input.impulse = input_impulse
            loco_ext.input.input_data = input_data
        end

        local current_character_setting = character_setting(unit)

        input.push_amount = input.push_amount - GameSettings.push_decay_rate * dt

        if input.push_amount > (current_character_setting.push_limit or CharacterSettings.default.push_limit) then
            input.pushed = true

            if input.push_amount > GameSettings.push_max then
                input.push_amount = GameSettings.push_max
            end
        elseif input.push_amount < 0 then
            input.pushed = nil
            input.push_amount = 0
        end

        if extension.state.current_state ~= "knocked_down" and extension.internal.knockdown_immunity then
            extension.internal.knockdown_immunity = extension.internal.knockdown_immunity - dt

            if extension.internal.knockdown_immunity < 0 then
                extension.internal.knockdown_immunity = nil
            end
        end
    end
end)

kUtil.loop_try_prehook_function(_G, "CameraSystem", "update_cursor", function (self)
    if RukozhopHelpMod.mov_conv_active and RukozhopHelpMod.last_cur and self.input_data and self.input_data.cursor then
        self.input_data.cursor[1] = RukozhopHelpMod.last_cur[1]
        self.input_data.cursor[2] = RukozhopHelpMod.last_cur[2]
    end
end)