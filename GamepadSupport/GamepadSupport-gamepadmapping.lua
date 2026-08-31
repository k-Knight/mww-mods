if not _G.GamepadMapper then
    _G.GamepadMapper = _G.class(GamepadMapper)

    local OUTPUT_FUNC_MAPPING = {
        magick5_up = "released",
        click_up = "released",
        twist_free = "pressed",
        right_click_hold = "button",
        magick3_up = "released",
        lightning = "pressed",
        fire_up = "released",
        double_click = "pressed",
        self_channel = "button",
        arcane = "pressed",
        magick1 = "pressed",
        right_click = "pressed",
        cast_self = "button",
        life_up = "released",
        earth = "pressed",
        water = "pressed",
        click = "pressed",
        cast_spell = "button",
        cold = "pressed",
        earth_up = "released",
        move_stop = "button",
        water_up = "released",
        spell_channel = "button",
        lightning_up = "released",
        magick2 = "pressed",
        set_move_target = "pressed",
        life = "pressed",
        use_consumable_up = "released",
        use_consumable = "pressed",
        do_move = "button",
        minimap_ping = "button",
        shield = "pressed",
        fire = "pressed",
        emote_hotkey = "pressed",
        magick5 = "pressed",
        shield_up = "released",
        activate_magick = "pressed",
        right_click_up = "released",
        show_select_magicks = "button",
        magick2_up = "released",
        magick4_up = "released",
        magick1_up = "released",
        hold_magick = "button",
        cold_up = "released",
        click_hold = "button",
        arcane_up = "released",
        magick4 = "pressed",
        magick3 = "pressed",
        cursor = "axis",

        movement = "axis",
        aim_range_multiplier = "axis",
        weapon_hold = "button",

        select_magick1 = "pressed",
        select_magick1_up = "released",
        select_magick2 = "pressed",
        select_magick2_up = "released",
        select_magick3 = "pressed",
        select_magick3_up = "released",
        select_magick4 = "pressed",
        select_magick4_up = "released",

        select_magick_forward = "pressed",
        select_magick_forward_up = "released",
        select_magick_backward = "pressed",
        select_magick_backward_up = "released"
    }

    function GamepadMapper:init()
        self.mappings = {}
        self.input_sates = {}
        self:initialize_mapping()
    end

    function GamepadMapper:initialize_mapping()
        self.binding_dirty = true
        self.input_dirty = true

        for action_name, behavior in pairs(OUTPUT_FUNC_MAPPING) do
            self.mappings[action_name] = {
                func = behavior,
                gamepad_keys = {},
                forbidden_keys = {},
                callbacks = {}
            }

            self.input_sates[action_name] = false
        end
    end

    function GamepadMapper:add_on_input_handler(action_name, callback)
        if self.mappings[action_name] then
            table.insert(self.mappings[action_name].callbacks, callback)
        else
            k_log("[GamepadMapper] cannot unbind, no such input :: " .. tostring(action_name))
        end
    end

    function GamepadMapper:bind_key(action_name, gamepad_keys)
        if action_name == "cursor" or action_name == "movement" then
            if type(gamepad_keys) == "string" and (gamepad_keys == "left_thumb_axis" or gamepad_keys == "right_thumb_axis") then
                self.mappings[action_name].gamepad_axis = {gamepad_keys}
            else
                k_log("[GamepadMapper] wrong axis name (" .. tostring(gamepad_keys) .. ") for binding " .. action_name)
                return
            end
        elseif action_name == "aim_range_multiplier" then
            if type(gamepad_keys) == "string" then
                if gamepad_keys == "left_trigger_axis" or gamepad_keys == "right_trigger_axis" then
                    self.mappings[action_name].gamepad_axis = self.mappings[action_name].gamepad_axis or {}
                    table.insert(self.mappings[action_name].gamepad_axis, gamepad_keys)
                else
                    k_log("[GamepadMapper] wrong axis name (" .. gamepad_keys .. ") for binding " .. action_name)
                    return
                end
            elseif type(gamepad_keys) == "table" then
                local valid = true

                for _, axis in ipairs(gamepad_keys) do
                    if axis ~= "left_trigger_axis" and axis ~= "right_trigger_axis" then
                        valid = false
                        k_log("[GamepadMapper] wrong axis name (" .. tostring(axis) .. ") for binding " .. action_name)
                        break
                    end
                end

                if valid then
                    self.mappings[action_name].gamepad_axis = gamepad_keys
                else
                    return
                end
            end
        elseif self.mappings[action_name] then
            if type(gamepad_keys) == "table" and type(gamepad_keys[1]) == "table" then
                self.mappings[action_name].gamepad_keys = gamepad_keys
            elseif type(gamepad_keys) == "table" and type(gamepad_keys[1]) == "string" then
                table.insert(self.mappings[action_name].gamepad_keys, gamepad_keys)
            else
                k_log("[GamepadMapper] invalid combination format for binding " .. action_name)
                return
            end
        else
            k_log("[GamepadMapper] cannot bind, no such input :: " .. tostring(action_name))
        end

        self.binding_dirty = true
    end

    function GamepadMapper:unbind_key(action_name)
        if self.mappings[action_name] then
            self.binding_dirty = true
            self.mappings[action_name].gamepad_keys = {}
        else
            k_log("[GamepadMapper] cannot unbind, no such input :: " .. tostring(action_name))
        end
    end

    function GamepadMapper:update_conflict_rules()
        for name_a, map_a in pairs(self.mappings) do
            map_a.forbidden_keys = {}

            for combo_index, combo_a in ipairs(map_a.gamepad_keys) do
                map_a.forbidden_keys[combo_index] = {}

                if #combo_a > 0 then
                    local keys_a_set = {}
                    for _, key_a in ipairs(combo_a) do
                        keys_a_set[key_a] = true
                    end

                    for name_b, map_b in pairs(self.mappings) do
                        if name_a ~= name_b then
                            for _, combo_b in ipairs(map_b.gamepad_keys) do
                                if #combo_b > #combo_a then
                                    local is_subset = true
                                    local keys_b_set = {}

                                    for _, key_b in ipairs(combo_b) do
                                        keys_b_set[key_b] = true
                                    end

                                    for key_a, _ in pairs(keys_a_set) do
                                        if not keys_b_set[key_a] then
                                            is_subset = false
                                            break
                                        end
                                    end

                                    if is_subset then
                                        for _, key_b in ipairs(combo_b) do
                                            if not keys_a_set[key_b] then
                                                map_a.forbidden_keys[combo_index][key_b] = true
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        self.binding_dirty = false
    end

    function GamepadMapper:update_input_sates()
        local mgr = GamepadSupportMod.gamepad_input_manager
        if not mgr or not mgr.input or not mgr.old_input then
            return
        end

        local cbs_to_call = {}

        for action_name, mapping in pairs(self.mappings) do
            repeat
                if not mapping or #mapping.gamepad_keys == 0 then
                    break
                end

                local behavior = mapping.func
                local action_triggered = false

                for combo_index, combo in ipairs(mapping.gamepad_keys) do
                    local n_buttons = #combo
                    if n_buttons > 0 then
                        local any_forbidden = false
                        local combo_forbidden = mapping.forbidden_keys[combo_index]
                        if combo_forbidden then
                            for forbidden_key, _ in pairs(combo_forbidden) do
                                if mgr.input[forbidden_key] then
                                    any_forbidden = true
                                    break
                                end
                            end
                        end

                        if not any_forbidden then
                            local n_old_pressed = 0
                            local n_new_pressed = 0

                            for _, gamepad_key in ipairs(combo) do
                                local current = mgr.input[gamepad_key] or false
                                local old = mgr.old_input[gamepad_key] or false

                                n_old_pressed = n_old_pressed + (old and 1 or 0)
                                n_new_pressed = n_new_pressed + (current and 1 or 0)
                            end

                            if behavior == "pressed" then
                                if (n_old_pressed < n_buttons) and (n_new_pressed == n_buttons) then
                                    action_triggered = true
                                    break
                                end
                            elseif behavior == "released" then
                                if (n_old_pressed == n_buttons) and (n_new_pressed < n_buttons) then
                                    action_triggered = true
                                    break
                                end
                            elseif behavior == "button" then
                                if n_new_pressed == n_buttons then
                                    action_triggered = true
                                    break
                                end
                            end
                        end
                    end
                end

                self.input_sates[action_name] = action_triggered

                if action_triggered then
                    for _, callback in ipairs(mapping.callbacks) do
                        cbs_to_call[#cbs_to_call + 1] = callback
                    end
                end
            until true
        end

        local axes = self.mappings.aim_range_multiplier.gamepad_axis
        local range_mult = 0.25
        for _, axis in ipairs(axes) do
            if axis == "left_trigger_axis" and mgr.input.left_trigger_axis > 0.05 then
                range_mult = range_mult + mgr.input.left_trigger_axis
            elseif axis == "right_trigger_axis" and mgr.input.right_trigger_axis > 0.05 then
                range_mult = range_mult + mgr.input.right_trigger_axis
            end
        end

        local deadzone_min = (GamepadSupportMod.settings["stick deadzone %"] or 5.0) / 100.0

        for _, input in ipairs({"cursor", "movement"}) do
            local axis_array = self.mappings[input].gamepad_axis
            local axis = axis_array and axis_array[1]

            local old_input = self.input_sates[input]
            --local was_zero = 0
            local old_x, old_y = 0, 0
            local a_x, a_y

            if old_input then
                --was_zero = old_input.is_zero and (old_input.was_zero + 1) or 0
                old_x, old_y = old_input.axis[1], old_input.axis[2]
            end

            if axis == "left_thumb_axis" then
                a_x, a_y = mgr.input.left_x, mgr.input.left_y
            elseif axis == "right_thumb_axis" then
                a_x, a_y = mgr.input.right_x, mgr.input.right_y
            end

            if a_x then
                a_x = math.abs(a_x) > deadzone_min and a_x or 0
                a_y = math.abs(a_y) > deadzone_min and a_y or 0
                --local is_zero = a_x == 0 and a_y == 0

                if input == "cursor" then
                    self.input_sates.cursor_amount = math.sqrt(a_x * a_x + a_y * a_y)

                    a_x = a_x * range_mult
                    a_y = a_y * range_mult
                end

                self.input_sates[input] = {
                    --was_zero = was_zero,
                    --is_zero = is_zero,
                    axis = {
                        -a_x,
                        a_y,
                        0
                    }
                }
            else
                self.input_sates[input] = {
                    --was_zero = was_zero,
                    --is_zero = true,
                    axis = {
                        old_x,
                        old_y,
                        0
                    }
                }
            end
        end

        for _, callback in ipairs(cbs_to_call) do
            local status, err = xpcall(callback, debug.traceback)

            if not status then
                k_log("[GamepadMapper] error in the \"" .. action_name .. "\" handler :: " .. tostring(err))
            end
        end

        self.input_dirty = false
    end

    function GamepadMapper:is_input_active(action_name, func)
        if self.binding_dirty then
            self:update_conflict_rules()
        end

        if self.input_dirty then
            self:update_input_sates()
        end

        local mapping = self.mappings[action_name]
        if not mapping then
            return false
        end

        local behavior = mapping.func

        if behavior == "axis" then
            local axis_input = self.input_sates[action_name]

            --if (axis_input.was_zero > 4) and axis_input.is_zero then
            --    return nil
            --else
            --    if axis_input.was_zero > 3 then
            --        k_log_table(self.input_sates[action_name].axis, 1, "    ")
            --    end
                return table.deep_clone(self.input_sates[action_name].axis)
            --end
        end

        if behavior ~= func then
            return false
        end

        return self.input_sates[action_name] or false
    end
end