local function get_input_changes(old_inputs, new_inputs)
    if not old_inputs or not new_inputs then
        return nil
    end

    local changes = {}
    local has_changes = false

    for key, new_val in pairs(new_inputs) do
        local old_val = old_inputs[key]

        if type(new_val) == "table" then
            local sub_changes = get_input_changes(old_val or {}, new_val)

            if sub_changes ~= nil then
                changes[key] = sub_changes
                has_changes = true
            end
        else
            if old_val ~= new_val then
                changes[key] = {
                    old = old_val or 0,
                    new = new_val
                }
                has_changes = true
            end
        end
    end

    if has_changes then
        return changes
    else
        return nil
    end
end

if not _G.GamepadInputManager then
    _G.GamepadInputManager = _G.class(GamepadInputManager)

    function GamepadInputManager:init()
        self.active_pad = nil

        self.inputs = {
            axis_left = { x = 0, y = 0 },
            axis_right = { x = 0, y = 0 },

            d_up = 0, d_down = 0, d_left = 0, d_right = 0,

            start = 0, back = 0,

            left_thumb = 0, right_thumb = 0,

            left_shoulder = 0, right_shoulder = 0,
            left_trigger = 0, right_trigger = 0,

            a = 0, b = 0, x = 0, y = 0
        }
    end

    function GamepadInputManager:find_active_gamepad()
        local status, err = pcall(function()
            local pads = {
                pad1 = Pad1,
                pad2 = Pad2,
                pad3 = Pad3,
                pad4 = Pad4,
                pad5 = Pad5,
                pad6 = Pad6,
                pad7 = Pad7,
                pad8 = Pad8,
                pad9 = Pad9
            }

            for name, pad in pairs(pads) do
                if pad.connected() then
                    local pad_active = pad.active()
                    k_log("[GamepadInputManager] pad '" .. name "' is connected :: active [" .. tostring(pad_active) .. "]")

                    if pad_active then
                        return pad
                    end
                end
            end

            k_log("[GamepadInputManager] no active pads !!!")
        end)

        if status then
            self.active_pad = err

            if self.active_pad then
                k_log("[GamepadInputManager] found active gamepad :: " .. tostring(self.active_pad))
            end
        else
            k_log("[GamepadInputManager] error getting active gamepad :: " .. tostring(err))
            return nil
        end
    end

    function GamepadInputManager:update(dt)
        local old_inputs = table.deep_clone(self.inputs)

        if self.active_pad and self.active_pad.active() then
            local pad = self.active_pad

            local left_axis_id = pad.axis_id("left")
            local right_axis_id = pad.axis_id("right")

            local left_stick = pad.axis(left_axis_id)
            local right_stick = pad.axis(right_axis_id)

            self.inputs.axis_left.x = left_stick.x
            self.inputs.axis_left.y = left_stick.y
            self.inputs.axis_right.x = right_stick.x
            self.inputs.axis_right.y = right_stick.y

            self.inputs.a = pad.button(pad.button_id("a"))
            self.inputs.b = pad.button(pad.button_id("b"))
            self.inputs.x = pad.button(pad.button_id("x"))
            self.inputs.y = pad.button(pad.button_id("y"))

            self.inputs.d_up    = pad.button(pad.button_id("d_up"))
            self.inputs.d_down  = pad.button(pad.button_id("d_down"))
            self.inputs.d_left  = pad.button(pad.button_id("d_left"))
            self.inputs.d_right = pad.button(pad.button_id("d_right"))

            self.inputs.start = pad.button(pad.button_id("start"))
            self.inputs.back  = pad.button(pad.button_id("back"))

            self.inputs.left_shoulder  = pad.button(pad.button_id("left_shoulder"))
            self.inputs.right_shoulder = pad.button(pad.button_id("right_shoulder"))
            self.inputs.left_trigger   = pad.button(pad.button_id("left_trigger"))
            self.inputs.right_trigger  = pad.button(pad.button_id("right_trigger"))

            self.inputs.left_thumb  = pad.button(pad.button_id("left_thumb"))
            self.inputs.right_thumb = pad.button(pad.button_id("right_thumb"))
        else
            self.inputs.axis_left.x = 0; self.inputs.axis_left.y = 0
            self.inputs.axis_right.x = 0; self.inputs.axis_right.y = 0

            self.inputs.d_up = 0; self.inputs.d_down = 0; self.inputs.d_left = 0; self.inputs.d_right = 0
            self.inputs.start = 0; self.inputs.back = 0
            self.inputs.left_thumb = 0; self.inputs.right_thumb = 0
            self.inputs.left_shoulder = 0; self.inputs.right_shoulder = 0
            self.inputs.left_trigger = 0; self.inputs.right_trigger = 0
            self.inputs.a = 0; self.inputs.b = 0; self.inputs.x = 0; self.inputs.y = 0

            self:find_active_gamepad()
        end

        local diff = get_input_changes(old_inputs, self.inputs)
        if diff then
            k_log("[GamepadInputManager] inputs changed :: " .. k_log_table_helper(diff, 2, "    "))
        end
    end
end
