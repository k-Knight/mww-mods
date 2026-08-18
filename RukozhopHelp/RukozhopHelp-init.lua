local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

_G.RukozhopHelpMod = {
    bg_tex = "hud_element_arcane",
    fg_tex = "hud_element_arcane",

    state = {

    },

    settings = {
        hotkey = { "mouse_forward" },
        movement_convenience_enabled = true,
        input_queue_enabled = true,
        aiming_recticles_enabled = true
    }
}

local render_mov_conv = function()
    if not RukozhopHelpMod.settings.movement_convenience_enabled then
        return
    end

    if not (RukozhopHelpMod.mov_conv_active and _G.ui) then
        return
    end

    local sz = RukozhopHelpMod.ui_size
    local x = RukozhopHelpMod.draw_x - (sz / 2)
    local y = RukozhopHelpMod.draw_y - (sz / 2)

    Gui.bitmap(
        _G.ui.ui_renderer.gui,
        RukozhopHelpMod.bg_tex,
        Vector3(x, y, 0),
        Vector2(sz, sz),
        Color(96, 0, 0, 0)
    )

    sz = sz * 0.2
    x = RukozhopHelpMod.draw_x - (sz / 2)
    y = RukozhopHelpMod.draw_y - (sz / 2)

    Gui.bitmap(
        _G.ui.ui_renderer.gui,
        RukozhopHelpMod.fg_tex,
        Vector3(x, y, 0),
        Vector2(sz, sz),
        Color(96, 0, 0, 0)
    )
end

local check_mov_conv_status = function()
    if not RukozhopHelpMod.settings.movement_convenience_enabled then
        RukozhopHelpMod.mov_conv_active = false
        return
    end

    local state = kUtil.is_hotkey_pressed(RukozhopHelpMod.settings.hotkey)

    if state ~= RukozhopHelpMod.mov_conv_active then
        if state then
            local cur_cursor = Mouse.axis(Mouse.axis_index("cursor"), Mouse.RAW, 3)
            RukozhopHelpMod.orig_x = cur_cursor[1]
            RukozhopHelpMod.orig_y = cur_cursor[2]

            local raw_w, raw_h = Application.resolution()
            RukozhopHelpMod.screen_scale = math.sqrt(raw_w * raw_w + raw_h * raw_h)
            RukozhopHelpMod.ui_size = RukozhopHelpMod.screen_scale / 16

            local min_x = (RukozhopHelpMod.ui_size / 2) + 1
            local min_y = min_x
            local max_x = raw_w - min_x
            local max_y = raw_h - min_y

            RukozhopHelpMod.draw_x = RukozhopHelpMod.orig_x < min_x and min_x or (RukozhopHelpMod.orig_x > max_x and max_x or RukozhopHelpMod.orig_x)
            RukozhopHelpMod.draw_y = RukozhopHelpMod.orig_y < min_y and min_y or (RukozhopHelpMod.orig_y > max_y and max_y or RukozhopHelpMod.orig_y)
            RukozhopHelpMod.first_pass = true
            Window.set_cursor_position(Vector2(RukozhopHelpMod.draw_x, RukozhopHelpMod.draw_y))
        elseif RukozhopHelpMod.orig_x and RukozhopHelpMod.orig_y then
            Window.set_cursor_position(Vector2(RukozhopHelpMod.orig_x, RukozhopHelpMod.orig_y))
        end

        RukozhopHelpMod.mov_conv_active = state
    end
end

local function reset_sate()
    RukozhopHelpMod.state = {
        casting_new_spell = false,
        casting_weapon_attack = false,
    }
end


local function init_mod()
    reset_sate()

    kUtil.task_scheduler.add(function ()
        SAVE_GLOBAL_MOD_SETTINGS("RukozhopHelp", RukozhopHelpMod.settings)
    end, 10)

    if mod_inited then
        return
    end

    mod_inited = true

    RukozhopHelpMod.settings = LOAD_GLOBAL_MOD_SETTINGS("RukozhopHelp", RukozhopHelpMod.settings)

    local success, err = xpcall(require, debug.traceback, "RukozhopHelp/overrides")
    if not success then
        k_log("[RukozhopHelp] failed to execute overrides ::\n" .. tostring(err))
        return
    end

    kUtil.add_on_tick_handler(check_mov_conv_status)
    kUtil.add_on_render_handler(render_mov_conv)
end

EventHandler.register_event("menu", "init", "RukozhopHelp_init", init_mod)
EventHandler.register_event("ingame", "game_over", "RukozhopHelp_init", reset_sate)