local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

_G.MovConv = {
    bg_tex = "hud_element_arcane",
    fg_tex = "hud_element_arcane",
    mod_settings = {
        hotkey = {"mouse_forward"}
    }
}

local render_mov_conv = function()
    if not (MovConv.enabled and _G.ui) then
        return
    end

    local sz = MovConv.screen_scale / 8
    local x = MovConv.orig_x - (sz / 2)
    local y = MovConv.orig_y - (sz / 2)

    Gui.bitmap(
        _G.ui.ui_renderer.gui,
        MovConv.bg_tex,
        Vector3(x, y, 0),
        Vector2(sz, sz),
        Color(96, 0, 0, 0)
    )

    sz = MovConv.screen_scale / 65
    x = MovConv.orig_x - (sz / 2)
    y = MovConv.orig_y - (sz / 2)

    Gui.bitmap(
        _G.ui.ui_renderer.gui,
        MovConv.fg_tex,
        Vector3(x, y, 0),
        Vector2(sz, sz),
        Color(96, 0, 0, 0)
    )
end

local check_mov_conv_status = function()
    local state = kUtil.is_hotkey_pressed(MovConv.mod_settings.hotkey)

    if state ~= MovConv.enabled then
        if state then
            local cur_cursor = Mouse.axis(Mouse.axis_index("cursor"), Mouse.RAW, 3)
            MovConv.orig_x = cur_cursor[1]
            MovConv.orig_y = cur_cursor[2]

            local raw_w, raw_h = Application.resolution()
            MovConv.screen_scale = math.sqrt(raw_w * raw_w + raw_h * raw_h)
        elseif MovConv.orig_x and MovConv.orig_y then
            Window.set_cursor_position(Vector2(MovConv.orig_x, MovConv.orig_y))
        end

        MovConv.enabled = state
    end
end


local function try_hook_needed_funcs()
    repeat
        if (not ClientCharacterSystem) or ClientCharacterSystem._old_update_characterse then
            break
        end

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

        k_log("[MovementConvenience] overriding ClientCharacterSystem.update_characters() !!")
        ClientCharacterSystem._old_update_characterse = ClientCharacterSystem.update_characters
        ClientCharacterSystem.update_characters = function(self, dt)
            local movement_convenience = MovConv.enabled
            local camera = CameraProxy:setup(self.game_camera, self.game_camera_unit, self.world)
            local unit_spawner = self.unit_spawner
            local state_context = self.character_update_context

            state_context.is_local = true
            state_context.dt = dt

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

                    local cursor_delta_x, cursor_delta_y

                    if movement_convenience and not hud_gui_intersects then
                        local cur_cursor = Mouse.axis(Mouse.axis_index("cursor"), Mouse.RAW, 3)
        
                        cursor_delta_x = cur_cursor[1] - MovConv.orig_x
                        cursor_delta_y = cur_cursor[2] - MovConv.orig_y
        
                        local dist = math.sqrt(cursor_delta_x * cursor_delta_x + cursor_delta_y * cursor_delta_y)
                        local max_dist = MovConv.screen_scale / 20
        
                        if dist > max_dist then
                            local new_dist = dist / max_dist
                            local new_delta_x = cursor_delta_x / new_dist
                            local new_delta_y = cursor_delta_y / new_dist
                            Window.set_cursor_position(Vector2(MovConv.orig_x + new_delta_x, MovConv.orig_y + new_delta_y))
                        end
        
                        local not_dead_zone = (dist / max_dist) > 0.1
                        cursor_delta_x = cur_cursor[1] - MovConv.orig_x
                        cursor_delta_y = cur_cursor[2] - MovConv.orig_y
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

                    if intersect_pos and movement_convenience and cursor_delta_x and cursor_delta_y then
                        local delta_mov, delta_dir = camera:screen_ray(cursor[1] + cursor_delta_x, cursor[2] + cursor_delta_y)
            
                        local t2 = Intersect.ray_plane(cam, dir, plane)
                        if t2 == nil then
                            t2 = 0
                        end
            
                        local intersect_pos_movement2 = delta_mov + delta_dir * t2
                        local dir = Vector3.normalize(intersect_pos_movement2 - intersect_pos)
            
                        dir.z = 0
            
                        if Vector3.length(dir) > 0.3 and unit and Unit.alive(unit) then
                            intersect_pos = Unit.world_position(unit, 0) + (dir * 100)
                            my_force_move = true
                        end
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
                            local old_freen_x, old_freen_y = freen_world_direction[1], freen_world_direction[2]

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
        end
    until true

    kUtil.task_scheduler.add(try_hook_needed_funcs, 1000)
end

local function init_mod(context)
    MovConv.mod_settingss = LOAD_GLOBAL_MOD_SETTINGS("MovementConvenience", MovConv.mod_settings)
    kUtil.add_on_tick_handler(check_mov_conv_status)
    kUtil.add_on_render_handler(render_mov_conv)
    kUtil.task_scheduler.add(try_hook_needed_funcs, 1000)
    SAVE_GLOBAL_MOD_SETTINGS("MovementConvenience", MovConv.mod_settings)
end

EventHandler.register_event("menu", "init", "MovementConvenience_init", init_mod)
