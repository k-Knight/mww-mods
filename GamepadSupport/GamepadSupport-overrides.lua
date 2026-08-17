require("scripts/game/entity_system/systems/character/character_state_machine")

kUtil.loop_try_repalce_function(_G, "InputManager", "_send_input", function (self, target, mapping)
    local set_nil
    local output = target.input_data or {}

    for _, value in pairs(mapping) do
        local controller = value.controller

        if value.index then
            local function_type = value.func
            local val = controller[function_type](value.index)

            if function_type == "button" and val < math.EPSILON then
                val = 0
            elseif function_type == "axis" then
                val = Vector3Aux.box({}, val)
            end

            local is_cursor = value.output == "cursor"
            local mousr_cursor_moved = false

            if is_cursor and val then
                local old_x, old_y = GamepadSupportMod.state.last_cursor_pos[1], GamepadSupportMod.state.last_cursor_pos[2]
                local new_x, new_y = val[1], val[2]

                if new_x and new_y then
                    local diff = math.abs(old_x - new_x) + math.abs(old_y - new_y)

                    if diff > 50 then
                        GamepadSupportMod.state.is_gamepad_looking = false
                        GamepadSupportMod.state.cursor_moved = true
                        GamepadSupportMod.state.last_cursor_pos = {new_x, new_y}
                        mousr_cursor_moved = true
                    else
                        GamepadSupportMod.state.cursor_moved = false
                    end
                end
            end

            local gamepad_value = GamepadSupportMod.gamepad_mapper and GamepadSupportMod.gamepad_mapper:is_input_active(value.output, value.func)
            if gamepad_value then
                if type(val) == "number" then
                    val = 1
                else
                    if is_cursor then
                        gamepad_value = GamepadSupportMod.state.cur_cursor_pos
                        local new_x, new_y = gamepad_value[1], gamepad_value[2]

                        GamepadSupportMod.state.last_cursor_pos = {new_x, new_y}
                    end

                    val = gamepad_value
                end
            elseif not mousr_cursor_moved and is_cursor then
                GamepadSupportMod.state.cursor_moved = false
            end

            output[value.output] = val
        elseif value.filter then
            output[value.output] = value.filter:evaluate(output)
        else
            local function_type = value.func

            if function_type == "button" then
                output[value.output] = 0
            else
                if function_type ~= "pressed" then
                    -- block empty
                end

                output[value.output] = false
            end

            if false then
                if function_type == "axis" then
                    output[value.output] = {
                        0,
                        0,
                        0
                    }
                else
                    cat_printf_warning("ui", "unhandled input %s", value.output)
                end
            end
        end
    end

    target.input_data = output
end)

kUtil.loop_try_posthook_function(_G, "CharacterStateMachine", "init", function (self, context)
    for char_state_name, state in pairs(self._states) do
        if not state._old_set_channeling_state and state.set_channeling_state then
            k_log("[GamepadSupport] overridng CharacterState[" .. tostring(char_state_name) .. "].set_channeling_state() !!!")
            state._old_set_channeling_state = state.set_channeling_state
            state.set_channeling_state = function(self, value)
                if GamepadSupportMod.state.holding_weapon then
                    value = true
                end

                return self._old_set_channeling_state(self, value)
            end
        end

        k_log("[GamepadSupport] overridng CharacterState[" .. tostring(char_state_name) .. "].handle_spellwheel_input() !!!")
        state.handle_spellwheel_input = function (self, unit, input_data, internal)
            local sw_ext = internal.spellwheel_ext
            local holding_weapon = GamepadSupportMod.state.holding_weapon
            local aiming_spell = GamepadSupportMod.state.trying_to_channel

            local state = sw_ext and sw_ext.state
            local queued_elements = state and state.queued_elements or 0
            aiming_spell = aiming_spell and (queued_elements > 0)

            local overide_behaviour = holding_weapon or aiming_spell
            local current_cursor = internal.current_cursor

            if overide_behaviour then
                if holding_weapon then
                    input_data.spell_cast = "weapon"
                elseif aiming_spell and current_cursor == "default" or current_cursor == "forward" then
                    input_data.spell_cast = "forward"
                end
            else
                if not input_data.wait_for_rmb_release and input_data.cast_spell and input_data.cast_spell > 0 and internal.previous_cursor ~= "magick" and current_cursor ~= "magick" then
                    input_data.spell_cast = current_cursor == "default" and "forward" or current_cursor
                elseif not input_data.wait_for_mbb_release and input_data.cast_self > 0 then
                    input_data.spell_cast = "self"
                else
                    input_data.spell_cast = nil
                end
            end
            EntityAux.set_input_by_extension(sw_ext, "input_data", input_data)
        end
    end
end)

kUtil.loop_try_prehook_function(_G, "ClientSpellCastingSystem", "_handle_spellcast", function (self, unit, input, internal, state, target)
    GamepadSupportMod.state.casting_new_spell = true
    GamepadSupportMod.state.right_click_pressed = false
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
            GamepadSupportMod.state.casting_weapon_attack = state == "charge_attacking_waiting_for_end" or state == "chain_attacking_waiting_for_end" or state == "chain_attacking_in_window"
        end
    end

    tmp_context = nil
end)

kUtil.task_scheduler.add(function ()
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
        elseif GamepadSupportMod.state.is_gamepad_looking then
            Window.set_cursor(cursors.empty)
        elseif GamepadSupportMod.state.cursor_moved then
            Window.set_cursor(cursors.default)
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

            local player_ext = EntityAux.extension(unit, "player")
            local sw_ext = EntityAux.extension(unit, "spellwheel")
            local stopped_casting = false
            local gamepad_is_aiming = false
            local magick_cursor = internal.current_cursor == "magick"
            local holding_weapon
            local char_state = EntityAux.state(unit, "character")

            if char_state then
                holding_weapon = GamepadSupportMod.gamepad_mapper and GamepadSupportMod.gamepad_mapper:is_input_active("weapon_hold", "button") or false
                GamepadSupportMod.state.holding_weapon = holding_weapon
            end

            if player_ext and sw_ext then
                local queued_elements = sw_ext.state and sw_ext.state.queued_elements or 0
                local aim_len = GamepadSupportMod.gamepad_mapper.input_sates.cursor_amount or 0
                local aim_tershold = GamepadSupportMod.settings["aiming/spell casting threshold"] or 0.90
                local need_release = false

                if aim_len > aim_tershold then
                    if queued_elements > 0 then
                        local time = os.clock()
                        local in_aiming_treshold = GamepadSupportMod.state.in_aiming_treshold

                        if in_aiming_treshold < 0 then
                            GamepadSupportMod.state.in_aiming_treshold = time
                        end

                        if GamepadSupportMod.state.right_click_pressed or ((time - in_aiming_treshold) > (GamepadSupportMod.settings["aiming/spell casting delay (s)"] or 0.05)) then
                            GamepadSupportMod.state.trying_to_channel = true
                        end
                    elseif GamepadSupportMod.state.holding_weapon then
                        need_release = true
                    end
                elseif aim_len < ((GamepadSupportMod.settings["aiming/spell reset ratio"] or 0.9) * aim_tershold) then
                    need_release = true
                end

                if need_release then
                    if GamepadSupportMod.state.trying_to_channel then
                        stopped_casting = true
                    end

                    GamepadSupportMod.state.in_aiming_treshold = -1
                    GamepadSupportMod.state.trying_to_channel = false
                end
            end

            if not holding_weapon and GamepadSupportMod.state.trying_to_channel then
                GamepadSupportMod.gamepad_mapper.input_sates.spell_channel = true
                input_data.spell_channel = 1
            elseif stopped_casting then
                GamepadSupportMod.gamepad_mapper.input_sates.spell_channel = false
                input_data.spell_channel = 0
            end

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
                if failsafe_switch_back then
                    Window.set_cursor(cursors[internal.current_cursor])
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

                repeat
                    local gamepad_cursor = GamepadSupportMod.gamepad_mapper and GamepadSupportMod.gamepad_mapper:is_input_active("cursor", "axis")
                    if not gamepad_cursor then
                        break
                    end

                    local x, y = gamepad_cursor[1], gamepad_cursor[2]
                    local unit_world_position = Unit.world_position(unit, 0)
                    unit_world_position[3] = unit_world_position[3] + 1
                    local cur_world_pos = unit_world_position + Vector3(x, y, 0) * (GamepadSupportMod.settings["aiming range multiplie"] or 17.5)
                    if not cur_world_pos then
                        break
                    end

                    local screen_width, screen_height = Application.resolution()
                    local screen_pos = Camera.world_to_screen(camera.camera, cur_world_pos, Vector3(screen_width, screen_height, 0))
                    if not screen_pos then
                        break
                    end

                    gamepad_is_aiming = true

                    x, y = screen_pos[1], screen_pos[3]
                    x = math.min(screen_width, math.max(0, x))
                    y = math.min(screen_height, math.max(0, y))
                    input_data.cursor[1], input_data.cursor[2] = x, y
                    GamepadSupportMod.state.cur_cursor_pos = {x, y, 0}
                    GamepadSupportMod.state.is_gamepad_looking = true

                    Window.set_cursor_position(Vector2(x, y))

                    local dir = cur_world_pos - unit_world_position
                    dir[3] = 0
                    local x, y, z = Vector3.to_elements(Vector3.normalize(dir))

                    local freen_world_direction = state.freen_world_direction
                    if freen_world_direction then
                        freen_world_direction[1], freen_world_direction[2] = x, y
                    end
                until true

                local cursor = input_data.cursor
                local cam, dir = camera:screen_ray(cursor[1], cursor[2])
                local plane = Plane.from_point_and_normal(unit_world_position, Vector3.up())
                local t = Intersect.ray_plane(cam, dir, plane)
                local intersect_pos

                if t then
                    intersect_pos = cam + dir * t
                end

                local ignore_click = hud_gui_intersects or input.ignore_click
                local override_intersect_pos
                local allow_moveto_unit = true

                if not gamepad_is_aiming and pdNetworkServerUnit.owning_peer_is_self(unit) then
                    local plane = Plane.from_point_and_normal(unit_world_position + Vector3.up(), Vector3.up())
                    local t = Intersect.ray_plane(cam, dir, plane)

                    if t then
                        local intersect_pos = cam + dir * t
                        local freen_world_direction = state.freen_world_direction

                        if freen_world_direction then
                            local diff = intersect_pos - unit_world_position
                            diff[3] = 0

                            local normalized_diff = Vector3.normalize(diff)
                            freen_world_direction[1], freen_world_direction[2], freen_world_direction[3] = normalized_diff[1], normalized_diff[2], 0
                            state.freen_world_direction = freen_world_direction
                        end
                    end
                end

                if GamepadSupportMod.gamepad_mapper then
                    local move_axis = GamepadSupportMod.gamepad_mapper:is_input_active("movement", "axis")

                    if move_axis then
                        local move_dir = Vector3(move_axis[1], move_axis[2], move_axis[3])
                        local move_lenth = Vector3.length(move_dir)

                        if move_lenth > 0.1 then
                            input_data.do_move = 1
                            input_data.set_move_target = 1
                            input_data.move_stop = 0
                            ignore_click = false
                            allow_moveto_unit = false
                        else
                            input_data.do_move = 0
                            input_data.set_move_target = 0
                            input_data.move_stop = 1
                        end

                        override_intersect_pos = unit_world_position + move_dir * 2
                    end
                end

                local activate_position = not ignore_click and intersect_pos

                if GamepadSupportMod.state.right_click_pressed then
                    if magick_cursor then
                        input_data.activate_magick = not internal.gamepad_magick_hold
                        internal.gamepad_magick_hold = true
                        input_data.spell_channel = 1
                        input_data.hold_magick = 1
                        input_data.right_click_hold = 1
                        input_data.cast_spell = 1

                        if intersect_pos then
                            activate_position = intersect_pos
                        end
                    end
                elseif internal.gamepad_magick_hold then
                    internal.gamepad_magick_hold = false
                    input_data.activate_magick = true
                    input_data.hold_magick = 0
                    input_data.right_click_hold = 0
                    input_data.cast_spell = 0
                end

                CharacterSystemAux_update_pending_magicks(unit, input, input_data, internal, activate_position, unit_spawner, self.entity_manager, cane_navmeshquery, dt)

                if input_data.move_stop > 0 or input_data.do_move < 0.5 and internal.loco_ext.state.blocked then
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

                if (intersect_pos or override_intersect_pos) and (input_data.do_move > 0.5 and not ignore_click and internal.was_clicked or input_data.set_move_target and not ignore_click) and input_data.move_stop == 0 then
                    local move_to_pos =  override_intersect_pos and override_intersect_pos or intersect_pos
                    if self.gamemode.gamemode_configuration.client.allow_minimap_ping and input_data.minimap_ping > 0 then
                        self.event_delegate:trigger("on_world_click_ping",move_to_pos)
                    else
                        if not self.time_since_last_move_rpc or Application.time_since_launch() - self.time_since_last_move_rpc > 2 then
                            self.time_since_last_move_rpc = Application.time_since_launch()

                            self.network_transport:transmit_message_to_server("rpc_from_client_player_moved")
                        end

                        internal.was_clicked = true
                        internal.disable_turning_to_cursor = nil

                        local path, path_n = PathAux_get_path(cane_navmeshquery, unit_world_position, move_to_pos)
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
                            if Development_ui_enabled() and allow_moveto_unit then
                                internal.click_unit = self.unit_spawner:spawn_unit_local(GameSettings.move_to_unit_click, move_to_pos)
                            end
                        elseif internal.click_unit then
                            Unit.set_local_position(internal.click_unit, 0, move_to_pos)
                        end

                        if not internal.move_to_unit then
                            if Development_ui_enabled() and allow_moveto_unit then
                                internal.move_to_unit = self.unit_spawner:spawn_unit_local(GameSettings.move_to_unit, last_navmesh_position_vec3)
                            end
                        else
                            Unit.set_local_position(internal.move_to_unit, 0, last_navmesh_position_vec3)
                        end

                        if input_data.set_move_target then
                            -- block empty
                        end
                    end
                end

                internal.was_clicked = internal.was_clicked and input_data.do_move > 0.5 or false

                local look_plane = Plane.from_point_and_normal(unit_world_position + Vector3.up(), Vector3.up())
                local look_t = Intersect.ray_plane(cam, dir, look_plane)

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

            local chg_is_charging = input_data.spell_channel > 0.5 and internal.prev_chenneling_input or holding_weapon

            if not GamepadSupportMod.state.casting_new_spell and chg_is_charging and (not magick_cursor) then
                repeat
                    if GamepadSupportMod.state.casting_weapon_attack then
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
                    GamepadSupportMod.state.casting_new_spell = false
                    GamepadSupportMod.state.casting_weapon_attack = false
                else
                    internal.chg_casting_new_spell = GamepadSupportMod.state.casting_new_spell
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
end, 1)

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

                if spell_cast ~= "weapon" then
                    element_queue:clear()
                end
                network:transmit_to_server(u, "rpc_from_client_clear_element_queue")

                local spellcast_input = {
                    spell_type = spell_cast,
                    elements = selected_elements,
                    num_elements = num_elements,
                    element_queue = element_queue_raw
                }

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

kUtil.loop_try_prehook_function(_G, "HudMagicks", "update", function (self, dt, input_data)
    GamepadSupportMod.state.hud_magicks = self

    if GamepadSupportMod.state.selecting_magick_ui > 0.5 then
        local magick_index = GamepadSupportMod.state.selecting_magick_ui
        self.gssmu_tier_index = magick_index
        self:hide_all_magick_lists()

        local magick_list_toggler_arrow = self.magick_list_toggler_arrows[magick_index]

        UIElement.set_pass_variable_by_id(magick_list_toggler_arrow, "root_alpha", "alpha", 0)

        for j = 1, #self.magick_list[magick_index] do
            local list_button = self.magick_list[magick_index][j]

            list_button:set_enabled(true)

            if list_button.magick_name ~= self.magick_buttons[magick_index].magick_name then
                UIElement.set_pass_disabled(list_button, "magick_click", false)
                UIElement.set_pass_disabled(list_button, "magick_state", false)
                UIElement.set_pass_disabled(list_button, "magick_color", false)
            end
        end

        self.visible_magick_list_index = magick_index

        if not self.gssmu_cur_selected then
            GamepadSupportMod.state.select_magick_forward = false
            GamepadSupportMod.state.select_magick_backward = false

            for j = 1, #self.magick_list[magick_index] do
                local list_button = self.magick_list[magick_index][j]
                local is_currently_selected = list_button.pass_id_mapping.magick_click.disabled

                if is_currently_selected then
                    self.gssmu_cur_selected = j
                    break
                end
            end
        end

        local selected_index = self.gssmu_cur_selected

        if selected_index then
            if GamepadSupportMod.state.select_magick_backward then
                GamepadSupportMod.state.select_magick_backward = false

                selected_index = selected_index - 1
                if selected_index < 1 then
                    selected_index = #(self.magick_list[magick_index])
                end
            end

            if GamepadSupportMod.state.select_magick_forward then
                GamepadSupportMod.state.select_magick_forward = false

                selected_index = selected_index + 1
                if selected_index > #(self.magick_list[magick_index]) then
                    selected_index = 1
                end
            end

            for j = 1, #self.magick_list[magick_index] do
                local list_button = self.magick_list[magick_index][j]
                local is_currently_selected = j == selected_index

                if is_currently_selected then
                    if list_button.passes[#(list_button.passes)].id ~= "gssmu_overlay" then
                        list_button.passes[#(list_button.passes) + 1] = {
                            texture = "hud_magick_button_pressed",
                            name = "texture",
                            id = "gssmu_overlay"
                        }
                    end
                elseif list_button.passes[#(list_button.passes)].id == "gssmu_overlay" then
                    list_button.passes[#(list_button.passes)] = nil
                end
            end

            self.gssmu_cur_selected = selected_index
        end
    elseif self.gssmu_tier_index then
        local magick_tier = self.gssmu_tier_index
        local magick_idex = self.gssmu_cur_selected

        self.gssmu_tier_index = nil
        self.gssmu_cur_selected = nil

        for j = 1, #self.magick_list[magick_tier] do
            local list_button = self.magick_list[magick_tier][j]

            if list_button.passes[#(list_button.passes)].id == "gssmu_overlay" then
                list_button.passes[#(list_button.passes)] = nil
            end
        end

        if magick_tier and self.magick_list[magick_tier] and magick_idex then
            local list_button = self.magick_list[magick_tier][magick_idex]

            if list_button and list_button.magick_name then
                self:select_magick(magick_tier, list_button.magick_name)
            end
        end

        self:hide_all_magick_lists()
    end
end)
