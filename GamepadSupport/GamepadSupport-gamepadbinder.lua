local setting_2_ctrls = function (setting_name)
    local lookup = {
        ["fire"]                        = {"fire", "fire_up"},
        ["lightning"]                   = {"lightning", "lightning_up"},
        ["earth"]                       = {"earth", "earth_up"},
        ["arcane"]                      = {"arcane", "arcane_up"},
        ["cold"]                        = {"cold", "cold_up"},
        ["water"]                       = {"water", "water_up"},
        ["shield"]                      = {"shield", "shield_up"},
        ["life"]                        = {"life", "life_up"},
        
        ["magick 1"]                    = {"magick1", "magick1_up"},
        ["magick 2"]                    = {"magick2", "magick2_up"},
        ["magick 3"]                    = {"magick3", "magick3_up"},
        ["magick 4"]                    = {"magick4", "magick4_up"},
        
        ["self cast"]                   = {"self_channel", "cast_self"},
        ["use weapon"]                  = {"weapon_hold"},
        ["twist free"]                  = {"twist_free"},
        ["emote hotkey"]                = {"emote_hotkey"},
        
        ["use magick or cast immediately"] = {"right_click", "right_click_up"},
        
        ["select magick 1"]             = {"select_magick1", "select_magick1_up"},
        ["select magick 2"]             = {"select_magick2", "select_magick2_up"},
        ["select magick 3"]             = {"select_magick3", "select_magick3_up"},
        ["select magick 4"]             = {"select_magick4", "select_magick4_up"},
        
        ["select magick forward"]       = {"select_magick_forward_up"},
        ["select magick backward"]      = {"select_magick_backward_up"},
        
        ["cursor"]                      = {"cursor"},
        ["movement"]                    = {"movement"},
        ["aim range multiplier"]        = {"aim_range_multiplier"},
    }

    return lookup[setting_name] or nil
end

local btn_name_2_ctrl = function (human_name)
    local lookup = {
        ["A"]                       = "a",
        ["B"]                       = "b",
        ["X"]                       = "x",
        ["Y"]                       = "y",

        ["D-Pad Up"]                = "d_up",
        ["D-Pad Down"]              = "d_down",
        ["D-Pad Left"]              = "d_left",
        ["D-Pad Right"]             = "d_right",

        ["LB"]                      = "left_shoulder",
        ["RB"]                      = "right_shoulder",
        ["Left Shoulder"]           = "left_shoulder",
        ["Right Shoulder"]          = "right_shoulder",

        ["LT"]                      = "left_trigger",
        ["RT"]                      = "right_trigger",
        ["Left Trigger"]            = "left_trigger",
        ["Right Trigger"]           = "right_trigger",

        ["LS"]                      = "left_thumb",
        ["RS"]                      = "right_thumb",
        ["Left Thumb"]              = "left_thumb",
        ["Right Thumb"]             = "right_thumb",

        ["Start"]                   = "start",
        ["Back"]                    = "back",

        ["Cross"]                   = "a",
        ["Circle"]                  = "b",
        ["Square"]                  = "x",
        ["Triangle"]                = "y",

        ["L1"]                      = "left_shoulder",
        ["R1"]                      = "right_shoulder",
        
        ["L2"]                      = "left_trigger",
        ["R2"]                      = "right_trigger",

        ["L3"]                      = "left_thumb",
        ["R3"]                      = "right_thumb",

        ["Options"]                 = "start",
        ["Share"]                   = "back",

        ["Left Thumb Axis"]         = "left_thumb_axis",
        ["Right Thumb Axis"]        = "right_thumb_axis",
        ["Left Trigger Axis"]       = "left_trigger_axis",
        ["Right Trigger Axis"]      = "right_trigger_axis",
    }

    return lookup[human_name] or nil
end

local function translate_binding(val)
    if type(val) == "string" then
        local ctrl = btn_name_2_ctrl(val)
        assert(ctrl, "[GamepadSupport] invalid button name  in configuration :: '" .. tostring(val) .. "'")

        return ctrl
    elseif type(val) == "table" then
        local processed = {}

        for i, sub_val in ipairs(val) do
            processed[i] = translate_binding(sub_val)
        end

        return processed
    end

    return val
end

local bind_buttons = function (btn_bindings)
    for btn, bindings in pairs(btn_bindings) do
        local ctrls = setting_2_ctrls(btn)
        local clean_bindings = translate_binding(bindings)

        assert(ctrls, "[GamepadSupport] invalid control name in configuration :: '" .. tostring(btn) .. "'")

        for _, ctrl in ipairs(ctrls) do
            GamepadSupportMod.gamepad_mapper:bind_key(ctrl, clean_bindings)
        end
    end
end

bind_buttons(GamepadSupportMod.settings.bindings.buttons)
bind_buttons(GamepadSupportMod.settings.bindings.axis)
bind_buttons(GamepadSupportMod.settings.bindings.trigger_axis)
