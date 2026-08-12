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
        aim_range_multiplier = "axis"
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
                forbidden_keys = {}
            }

            self.input_sates[action_name] = false
        end
    end

    function GamepadMapper:bind_key(action_name, gamepad_keys)
        if action_name == "cursor" or action_name == "movement" then
            if gamepad_keys == "left_thumb_axis" or gamepad_keys == "right_thumb_axis" then
                self.mappings[action_name].gamepad_axis = gamepad_keys
            else
                k_log("[GamepadMapper] wrong axis name (" .. gamepad_keys .. ") for binding " .. action_name)
            end
        elseif action_name == "aim_range_multiplier" then
            if gamepad_keys == "left_trigger_axis" or gamepad_keys == "right_trigger_axis" then
                self.mappings[action_name].gamepad_axis = gamepad_keys
            else
                k_log("[GamepadMapper] wrong axis name (" .. gamepad_keys .. ") for binding " .. action_name)
            end
        elseif self.mappings[action_name] then
            self.binding_dirty = true
            self.mappings[action_name].gamepad_keys = gamepad_keys
        else
            k_log("[GamepadMapper] cannot bind, no such input :: " .. tostring(action_name))
        end
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
        for _, mapping in pairs(self.mappings) do
            mapping.forbidden_keys = {}
        end

        for name_a, map_a in pairs(self.mappings) do
            if #map_a.gamepad_keys > 0 then
                local keys_a_set = {}

                for _, key_a in ipairs(map_a.gamepad_keys) do
                    keys_a_set[key_a] = true
                end

                for name_b, map_b in pairs(self.mappings) do
                    if name_a ~= name_b and #map_b.gamepad_keys > #map_a.gamepad_keys then
                        local is_subset = true
                        local keys_b_set = {}

                        for _, key_b in ipairs(map_b.gamepad_keys) do
                            keys_b_set[key_b] = true
                        end

                        for key_a, _ in pairs(keys_a_set) do
                            if not keys_b_set[key_a] then
                                is_subset = false
                                break
                            end
                        end

                        if is_subset then
                            for _, key_b in ipairs(map_b.gamepad_keys) do
                                if not keys_a_set[key_b] then
                                    map_a.forbidden_keys[key_b] = true
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

        for action_name, mapping in pairs(self.mappings) do
            repeat
                if not mapping or #mapping.gamepad_keys == 0 then
                    break
                end

                local behavior = mapping.func
                local any_forbidden = false

                local n_buttons = #(mapping.gamepad_keys)
                local n_old_pressed = 0
                local n_new_pressed = 0

                if n_buttons == 0 then
                    self.input_sates[action_name] = false
                    break
                end

                for forbidden_key, _ in pairs(mapping.forbidden_keys) do
                    if mgr.input[forbidden_key] then
                        any_forbidden = true
                        break
                    end
                end

                if any_forbidden then
                    self.input_sates[action_name] = false
                    break
                end

                for _, gamepad_key in ipairs(mapping.gamepad_keys) do
                    local current = mgr.input[gamepad_key] or false
                    local old = mgr.old_input[gamepad_key] or false

                    n_old_pressed = n_old_pressed + (old and 1 or 0)
                    n_new_pressed = n_new_pressed + (current and 1 or 0)
                end

                if behavior == "pressed" then
                    if (n_old_pressed < n_buttons) and (n_new_pressed == n_buttons) then
                        self.input_sates[action_name] = true
                        break
                    end
                elseif behavior == "released" then
                    if (n_old_pressed == n_buttons) and (n_new_pressed < n_buttons) then
                        self.input_sates[action_name] = true
                        break
                    end
                elseif behavior == "button" then
                    if n_new_pressed == n_buttons then
                        self.input_sates[action_name] = true
                        break
                    end
                end

                self.input_sates[action_name] = false
            until true
        end

        local axis = self.mappings.aim_range_multiplier.gamepad_axis
        local range_mult = 0.25
        if axis then
            if axis == "left_trigger_axis" then
                range_mult = range_mult + mgr.input.left_trigger_axis
            elseif axis == "right_trigger_axis" then
                range_mult = range_mult + mgr.input.right_trigger_axis
            end
        end
    
        local s_w, s_h = Application.resolution()
        local x, y = s_w / 2, s_h / 2

        for _, input in ipairs({"cursor", "movement"}) do
            local axis = self.mappings[input].gamepad_axis
            local old_input = self.input_sates[input]
            local was_zero
            local old_x, old_y
            local a_x, a_y

            if old_input then
                was_zero = old_input.is_zero or false
                old_x, old_y = old_input.axis[1], old_input.axis[2]
            end

            if axis == "left_thumb_axis" then
                a_x, a_y = mgr.input.left_x, mgr.input.left_y
            elseif axis == "right_thumb_axis" then
                a_x, a_y = mgr.input.right_x, mgr.input.right_y
            end

            if a_x then
                a_x = math.abs(a_x) > 0.1 and a_x or 0
                a_y = math.abs(a_y) > 0.1 and a_y or 0

                if input == "cursor" then
                    self.input_sates[input] = {
                        was_zero = was_zero,
                        is_zero = a_x == 0 and a_y == 0,
                        axis = {
                            a_x * x * range_mult + x,
                            s_h - (a_y * y * range_mult + y),
                            0
                        }
                    }
                else
                    self.input_sates[input] = {
                        was_zero = was_zero,
                        is_zero = a_x == 0 and a_y == 0,
                        axis = {
                            -a_x,
                            a_y,
                            0
                        }
                    }
                end
            else
                self.input_sates[input] = {
                    was_zero = was_zero,
                    is_zero = true,
                    axis = {
                        old_x,
                        old_y,
                        0
                    }
                }
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

            if axis_input.was_zero and axis_input.is_zero then
                return nil
            else
                return table.deep_clone(self.input_sates[action_name].axis)
            end
        end

        if behavior ~= func then
            return false
        end

        return self.input_sates[action_name] or false
    end
end