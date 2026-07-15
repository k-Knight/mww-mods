local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

_G.BTLD_DATA = {}

local VERSION = "2.0"
local VERSION_WHOLE = "BetterLoadouts Mod Version " .. VERSION
local ACTIVE_GAME_STATE = "menu"

_G.BTLD_DATA.info = {
    name = "BetterLoadouts",
    author = "SuperMickyJay and k-Knight",
    description = "Adds the ability to save and load gear loadouts.",
    version = VERSION,
    repo_link = "",
    last_dt = 0,
}

_G.BTLD_DATA.hidden_settings = {
    loadouts = {},
}

_G.BTLD_DATA.game_state = {}

local function popup_function_self_destroy(popup_item, button_function)
    if button_function then
        button_function()
    end

    UIFunc.kill_element_and_children(popup_item)
    _G.BTLD_DATA.current_top_level_popup = nil
end

local function save_loadout(slot_index)
    k_log("saving loadout to index :: " .. tostring(slot_index))
    local loadout_info = DEEP_CLONE(GET_GAME_DATA("loadout_info"))
    local settings = _G.BTLD_DATA.hidden_settings

    if (#settings.loadouts) < slot_index then
        for i=1, slot_index do
            if not settings.loadouts[i] then
                settings.loadouts[i] = {}
            end
        end
    end

    if not settings.loadouts[slot_index] then
        settings.loadouts[slot_index] = {}
    end

    settings.loadouts[slot_index][1] = loadout_info

    SAVE_GLOBAL_MOD_SETTINGS(_G.BTLD_DATA.info.name, settings, true)
end

local function load_loadout(slot_index)
    k_log("applying loadout at index :: " .. tostring(slot_index))
    _G.BTLD_DATA.hidden_settings = LOAD_GLOBAL_MOD_SETTINGS(_G.BTLD_DATA.info.name, _G.BTLD_DATA.hidden_settings, true)

    local slot_data = _G.BTLD_DATA.hidden_settings.loadouts[slot_index]
    if not slot_data or #slot_data == 0 then
        return
    end

    local loadout = slot_data[1]
    local setup = LoadoutSetup_init_from_defaults()
    local visual_setup, persistent_setup

    if _G.BTLD_DATA.game_state.menu_player_loadout then
        visual_setup = _G.BTLD_DATA.game_state.menu_player_loadout.loadout
        persistent_setup = _G.BTLD_DATA.game_state.menu_player_loadout.persistent_loadout
    end

    for k in pairs(loadout) do
        k_log("applying loadout [" .. tostring(k) .. "] :: " .. tostring(loadout[k]["equipment_name"]))
        LoadoutSetup.set_equipment(setup, k, loadout[k]["equipment_name"])

        if visual_setup then
            LoadoutSetup.set_equipment(visual_setup, k, loadout[k]["equipment_name"])
        end
        if persistent_setup then
            LoadoutSetup.set_equipment(persistent_setup, k, loadout[k]["equipment_name"])
        end
    end

    if _G.BTLD_DATA.game_state.menu_player_loadout then
        MenuPlayerLoadout.update_loadout(_G.BTLD_DATA.game_state.menu_player_loadout)
        if persistent_setup then
            pcall(function()
                LoadoutSetup.transmit_to_server(
                    persistent_setup,
                    MenuPlayerLoadout.get_server_peer_id(_G.BTLD_DATA.game_state.menu_player_loadout)
                )
            end)
        end
    end

    if _G.BTLD_DATA.game_state.menu_loadout_stats2 and _G.BTLD_DATA.game_state.ui_renderer then
        MenuLoadoutStats2.do_update_loadout_stats(
            _G.BTLD_DATA.game_state.menu_loadout_stats2,
            _G.BTLD_DATA.game_state.ui_renderer,
            _G.BTLD_DATA.game_state.menu_player_loadout
        )
    else
        k_log("missing MenuLoadoutStats2 instance !!!")
    end
end

local function random_loadout()
    local setup = LoadoutSetup_init_from_defaults()
    local visual_setup, persistent_setup

    if _G.BTLD_DATA.game_state.menu_player_loadout then
        visual_setup = _G.BTLD_DATA.game_state.menu_player_loadout.loadout
        persistent_setup = _G.BTLD_DATA.game_state.menu_player_loadout.persistent_loadout
    end

    local equipment_types = {
        "robe",
        "staff",
        "weapon",
        "trinket",
        "ring",
        "robe_skin"
    }

    for _, type in pairs(equipment_types) do
        LoadoutSetup.set_random_equipment(setup, type, "")
        local equipment_name = setup[type].equipment_name
        k_log("randomly picked loadout [" .. tostring(type) .. "] :: " .. tostring(equipment_name))

        if visual_setup then
            LoadoutSetup.set_equipment(visual_setup, type, equipment_name)
        end
        if persistent_setup then
            LoadoutSetup.set_equipment(persistent_setup, type, equipment_name)
        end
    end

    if _G.BTLD_DATA.game_state.menu_player_loadout then
        MenuPlayerLoadout.update_loadout(_G.BTLD_DATA.game_state.menu_player_loadout)
        if persistent_setup then
            pcall(function()
                LoadoutSetup.transmit_to_server(
                    persistent_setup,
                    MenuPlayerLoadout.get_server_peer_id(_G.BTLD_DATA.game_state.menu_player_loadout)
                )
            end)
        end
    end

    if _G.BTLD_DATA.game_state.menu_loadout_stats2 and _G.BTLD_DATA.game_state.ui_renderer then
        MenuLoadoutStats2.do_update_loadout_stats(
            _G.BTLD_DATA.game_state.menu_loadout_stats2,
            _G.BTLD_DATA.game_state.ui_renderer,
            _G.BTLD_DATA.game_state.menu_player_loadout
        )
    else
        k_log("missing MenuLoadoutStats2 instance !!!")
    end
end

local function my_new_skin_indicator_btn(pos, image_normal, image_hover, size, center, color, condition_args, mouse_clicked)
    local mouse_enters = function(state)
        if state.mouse_entered then
            return
        end

        state.self_reference.properties.texture.image = state.self_reference.properties.texture.image_hover;
    end
    local mouse_leaves = function(state)
        if state.mouse_leaves then
            return
        end

        state.self_reference.properties.texture.image = state.self_reference.properties.texture.image_normal;
    end

    return {
        properties = {
            name = "indicator button",
            texture = {
                fade_out = false,
                fade_in = false,
                image = image_normal,
                image_normal = image_normal,
                image_hover = image_hover,
                clicked = mouse_clicked,
                mouse_enters = mouse_enters,
                mouse_leaves = mouse_leaves,
                pos = pos,
                size = { x = size[1], y = size[2] },
                center = center,
                color = color or GET_DEFAULT_TEXTURE_COLOR(),
                condition_args = condition_args or {}
            }
        }
    }
end

local function my_new_button_unattached(pos, text, text_offset_x, text_offset_y, disabled, mouse_clicked, mouse_enters, mouse_leaves)
    local function pos_func(postion_conditions)
        local tex_pos = postion_conditions.self_reference.properties.texture.pos
        local text_offset_x = postion_conditions.text_offset_x
        local text_offset_y = postion_conditions.text_offset_y

        return {
            tex_pos[1] + text_offset_x,
            tex_pos[2] + text_offset_y,
            tex_pos[3] + 3
        }
    end

    return {
        properties = {
            name = "button background",
            texture = {
                ui_button = not disabled,
                fade_in = true,
                center = true,
                image = disabled and "button_topmenu_disabled" or "button_topmenu_default",
                fade_out = true,
                pos = pos,
                size = { x = 64, y = 64 },
                color = GET_DEFAULT_TEXTURE_COLOR(),
                clicked = disabled and function() end or mouse_clicked,
                mouse_enters = mouse_enters,
                mouse_leaves = mouse_leaves,
                condition_args = {}
            },
            text = {
                fade_in = true,
                font = "philosopher_bold",
                move_type = "slerp",
                center = true,
                size = 18,
                fade_out = true,
                string = text,
                pos = pos_func,
                color = { 255, 255, 255, 255 },
                condition_args = {
                    text_offset_x = text_offset_x or 0,
                    text_offset_y = (text_offset_y or 0) - 5
                }
            }
        }
    }
end

local function get_loadout_icon_or_text(index)
    if index == 1 then
        return true, "hud_element_water", {255, 0, 64, 64}
    elseif index == 2 then
        return true, "hud_element_life", {255, 0, 64, 64}
    elseif index == 3 then
        return true, "hud_element_shield", {255, 0, 64, 64}
    elseif index == 4 then
        return true, "hud_element_cold", {255, 0, 64, 64}
    elseif index == 5 then
        return true, "hud_element_lightning", {255, 0, 64, 64}
    elseif index == 6 then
        return true, "hud_element_arcane", {255, 0, 64, 64}
    elseif index == 7 then
        return true, "hud_element_earth", {255, 0, 64, 64}
    elseif index == 8 then
        return true, "hud_element_fire", {255, 0, 64, 64}
    elseif index == 9 then
        return true, "icon_health", {255, 255, 255, 255}
    elseif index == 10 then
        return true, "icon_speed", {255, 255, 255, 255}
    elseif index == 11 then
        return true, "icon_attack", {255, 255, 255, 255}
    elseif index == 12 then
        return true, "icon_weapon_ability", {255, 255, 255, 255}
    else
        local num = index - 12
        if (num ~= 1) and (num < 10) then
            return false, tostring(num) .. " "
        else
            return false, tostring(num)
        end
    end
end

local function create_simple_text_popup(title_text, width, height)
    if _G.BTLD_DATA.simple_text_popup and _G.BTLD_DATA.simple_text_popup.properties then
        UIFunc.kill_element_and_children(_G.BTLD_DATA.simple_text_popup)
        _G.BTLD_DATA.simple_text_popup = nil
    end

    local z_pos = 750
    local size_x = width or 400
    local size_y = height or 300

    local popup = UIFunc.new_texture_markup(
        "window_tile",
        {GET_CENTER_SCREEN_X_SCALED(), GET_CENTER_SCREEN_Y_SCALED(), z_pos},
        {size_x, size_y},
        true,
        {200, 15, 15, 15},
        {}
    )

    local current_y = 100
    local line_spacing = 24

    for line in string.gmatch(title_text, "[^\n]+") do
        k_log("adding line :: \"" .. line .. "\"")
        local label = UIFunc.new_text_markup(
            line,
            {0, current_y, z_pos + 1},
            18,
            {255, 255, 255, 255},
            true
        )
        UIFunc.add_child(popup, label)
        current_y = current_y - line_spacing
    end

    local btn_y_offset = -(size_y * 0.3)
    local close_btn = UIFunc.new_button_unattached(
        {0, btn_y_offset, z_pos + 1},
        "CLOSE ",
        0,
        0,
        function()
            UIFunc.kill_element_and_children(popup)
            _G.BTLD_DATA.simple_text_popup = nil
        end
    )
    UIFunc.add_child(popup, close_btn)

    NEW_UI_ELEMENT(ACTIVE_GAME_STATE, popup)
    _G.BTLD_DATA.simple_text_popup = popup

    return popup
end

local function create_override_skin_indicator(child_texture)
    if _G.BTLD_DATA.skin_override_indicator and _G.BTLD_DATA.skin_override_indicator.properties then
        UIFunc.kill_element_and_children(_G.BTLD_DATA.skin_override_indicator)
        _G.BTLD_DATA.skin_override_indicator = nil
    end

    local z_pos = 650

    local indicator = my_new_skin_indicator_btn(
        {GET_CENTER_SCREEN_X_SCALED() - 800, GET_CENTER_SCREEN_Y_SCALED() + 300, z_pos},
        "offer_backdrop",
        "offer_backdrop_hover",
        {100, 100},
        true,
        {255, 255, 255, 255},
        {},
        function ()
            if kUtil.is_hotkey_pressed({"shift"}) then
                k_log("(transmog fallback) resetting skin override and setting regular skin")
                _G.BTLD_DATA.game_state.override_skin = nil

                local player_loadout = _G.BTLD_DATA.game_state.menu_player_loadout
                if player_loadout then
                    MenuPlayerLoadout.set_skin(player_loadout, "robe", 1, true)
                end
            else
                create_simple_text_popup("[shift + click] on a skin\nto select override\n \n \n[shift + click] on this indicator\nto remove skin override")
            end
        end
    )

    if child_texture then
        local overlay_child = UIFunc.new_texture_markup(
            child_texture,
            {2, 2, z_pos + 1},
            {90, 90},
            true,
            {255, 0, 64, 64}
        )
    
        UIFunc.add_child(indicator, overlay_child)
    end

    NEW_UI_ELEMENT(ACTIVE_GAME_STATE, indicator)
    _G.BTLD_DATA.skin_override_indicator = indicator

    return indicator
end

local function create_loadout_select_popup(action_fn, title_prefix, check_existing)
    if _G.BTLD_DATA.current_top_level_popup and _G.BTLD_DATA.current_top_level_popup.properties then
        popup_function_self_destroy(_G.BTLD_DATA.current_top_level_popup, nil)
    end

    if check_existing then
        _G.BTLD_DATA.hidden_settings = LOAD_GLOBAL_MOD_SETTINGS(_G.BTLD_DATA.info.name, _G.BTLD_DATA.hidden_settings, true)
    end

    local z_pos = 700
    local x_size = 520
    local y_size = 400

    local popup = UIFunc.new_texture_markup(
        "window_tile",
        {GET_CENTER_SCREEN_X_SCALED() - 400, GET_CENTER_SCREEN_Y_SCALED(), z_pos},
        {x_size, y_size},
        true,
        {200, 0, 0, 0},
        {}
    )

    UIFunc.add_child(popup, UIFunc.new_text_markup(title_prefix, {0, 150, z_pos + 1}, 28, {255, 255, 255, 255}, true))

    local start_x = -165
    local start_y = 105
    local x_gap = 110
    local y_gap = 65

    for i = 1, 16 do
        local no_data = false

        if check_existing then
            local slot_data = _G.BTLD_DATA.hidden_settings.loadouts[i]
            no_data = not slot_data or #slot_data == 0
        end

        local row = math.floor((i - 1) / 4)
        local col = (i - 1) % 4
        local x = start_x + (col * x_gap)
        local y = start_y - (row * y_gap)

        local is_icon, icon, icon_color = get_loadout_icon_or_text(i)
        local btn = my_new_button_unattached({x, y, z_pos + 1}, is_icon and "" or icon, 0, 0, no_data, function()
            popup_function_self_destroy(popup, function()
                action_fn(i)
            end)
        end)

        if is_icon then
            if i < 9 then
                if no_data then
                    icon_color[3] = 0
                end

                local frame = UIFunc.new_texture_markup(
                    "hud_element_random",
                    {-16, -14, z_pos + 3},
                    {32, 32},
                    false,
                    {255, 255, 255, 255}
                )

                UIFunc.add_child(
                    frame,
                    UIFunc.new_texture_markup(
                        icon,
                        {1, 1, z_pos + 4},
                        {30, 30},
                        false,
                        icon_color
                    )
                )

                UIFunc.add_child(btn, frame)
            else
                if no_data then
                    icon_color[2] = 64
                    icon_color[3] = 64
                    icon_color[4] = 64
                end

                UIFunc.add_child(
                    btn,
                    UIFunc.new_texture_markup(
                        icon,
                        {-16, -14, z_pos + 3},
                        {32, 32},
                        false,
                        icon_color
                    )
                )
            end
        end

        UIFunc.add_child(popup, btn)
    end

    UIFunc.add_child(popup, UIFunc.new_button_unattached({0, -165, z_pos + 1}, "CLOSE ", 0, 0, function()
        popup_function_self_destroy(popup, function() end)
    end))

    local border_color = function() return {255, 60, 60, 60} end
    UIFunc.add_child(popup, UIFunc.new_texture_markup("window_tile", {(x_size * 0.49), 0, z_pos + 1}, UIFunc.new_texture_size(y_size, 10), true, border_color))
    UIFunc.add_child(popup, UIFunc.new_texture_markup("window_tile", {-(x_size * 0.49), 0, z_pos + 1}, UIFunc.new_texture_size(y_size, 10), true, border_color))
    UIFunc.add_child(popup, UIFunc.new_texture_markup("window_tile", {0, (y_size * 0.49), z_pos + 1}, UIFunc.new_texture_size(10, x_size), true, border_color))
    UIFunc.add_child(popup, UIFunc.new_texture_markup("window_tile", {0, -(y_size * 0.49), z_pos + 1}, UIFunc.new_texture_size(10, x_size), true, border_color))

    NEW_UI_ELEMENT(ACTIVE_GAME_STATE, popup)

    _G.BTLD_DATA.current_top_level_popup = popup
    return popup
end

local function open_save_popup()
    create_loadout_select_popup(save_loadout, "Save Loadout", false)
end

local function open_load_popup()
    create_loadout_select_popup(load_loadout, "Load Loadout", true)
end

local function open_random_popup()
    random_loadout()
end

local game_functions_hooked = false

local function init_mod(context)
    if not game_functions_hooked then
        kUtil.loop_try_prehook_function(_G, "MenuPlayerLoadout", "update", function(self, ui_renderer, dt, input_data)
            _G.BTLD_DATA.game_state.menu_player_loadout = self

            if ui_renderer then
                _G.BTLD_DATA.game_state.ui_renderer = ui_renderer
            end
        end)

        kUtil.loop_try_prehook_function(_G, "_MenuStateGear", "on_enter", function(self, param_block)
            k_log("(transmog fallback) resetting override skin ...")
            _G.BTLD_DATA.game_state.override_skin = nil
        end)

        kUtil.loop_try_prehook_function(_G, "_MenuStateGear", "on_exit", function(self)
            k_log("(transmog fallback) resetting override skin ...")
            _G.BTLD_DATA.game_state.override_skin = nil
        end)

        local animation_by_unit_type = {
            robe = {
                "to_lobby",
                "lobby_robe"
            },
            weapon = {
                "lobby_weapon"
            },
            staff = {
                "lobby_staff"
            }
        }

        local function check_unit(loadout_data, new_unit, world, unit_type, animation_unit, maintain_rotation, override_robe, robe_override_id)
            if override_robe then
                local override_file_name = InventoryAux.get_robe_filename(GameSettings.available_robes[robe_override_id])
                k_log("(transmog fallback) overriding visual robe file :: " .. tostring(new_unit) .. " -> " .. tostring(override_file_name))
                new_unit = override_file_name
            end

            if new_unit ~= loadout_data.file or not Unit.alive(loadout_data.unit) then
                local rotation = Quaternion(Vector3.up(), math.pi / 8)

                if loadout_data.unit and Unit.alive(loadout_data.unit) then
                    Unit.flow_event(loadout_data.unit, "on_despawn")
                    World.unlink_unit(world, loadout_data.unit)
                    World.destroy_unit(world, loadout_data.unit)
                end

                loadout_data.unit = World.spawn_unit(world, new_unit, Vector3.zero(), rotation)
                loadout_data.file = new_unit

                Unit.flow_event(loadout_data.unit, "on_preview")

                local animation_to_play = animation_by_unit_type[unit_type]

                if animation_to_play then
                    for i, anim in ipairs(animation_to_play) do
                        Unit.animation_event(animation_unit or loadout_data.unit, anim)
                    end
                end

                Unit.disable_physics(loadout_data.unit)

                return true
            end
        end

        kUtil.loop_try_repalce_function(_G, "MenuPlayerLoadout", "update_loadout", function(self, no_sound)
            local loadout = self.loadout
            local new_robe = loadout.robe.equipment_id
            local new_weapon = loadout.weapon.equipment_id
            local new_staff = loadout.staff.equipment_id
            local new_trinket = loadout.trinket.equipment_id
            local new_ring = loadout.ring.equipment_id
            local new_familiar = loadout.familiar.equipment_id
            local world = ui._world
            local equipment_type, equipped_unit

            if loadout.weapon.unit then
                InventoryAux.show_weapon(world, loadout.weapon.unit)
            end

            if loadout.staff.unit then
                InventoryAux.show_staff(world, loadout.staff.unit)
            end

            if not Unit.alive(self.player_unit) then
                self.player_unit = World.spawn_unit(ui._world, "content/units/player/player", Vector3.zero(), Quaternion.identity())
            end

            local override_robe = false
            local robe_override_id
            local new_robe_name = loadout.robe.equipment_name
            local override_skin_name = _G.BTLD_DATA.game_state.override_skin or loadout.robe_skin.equipment_name
            local skin_robe_name = override_skin_name:gsub("_(%d+)$", "")

            if new_robe_name ~= skin_robe_name then
                for i, robe in ipairs(GameSettings.available_robes) do
                    if robe == skin_robe_name then
                        robe_override_id = i
                        break
                    end
                end

                if robe_override_id then
                    override_robe = (robe_override_id ~= loadout.robe) or (robe_override_id ~= new_robe)
                end

                if override_robe then
                    k_log("(transmog fallback) overriding visual robe :: " .. tostring(new_robe) .. " -> " .. tostring(robe_override_id))
                end
            end

            if override_robe then
                local icon_name = EquipmentTemplates[override_skin_name] and EquipmentTemplates[override_skin_name].icon or nil
                k_log("(transmog fallback) displaying skin override icon for (" .. tostring(override_skin_name) .. ") :: " .. tostring(icon_name))

                create_override_skin_indicator(icon_name)
            else
                create_override_skin_indicator()
            end

            if check_unit(loadout.robe, InventoryAux.get_robe_filename(GameSettings.available_robes[new_robe]), world, "robe", nil, true, override_robe, robe_override_id) then
                InventoryAux.set_flow_variable_on_wielder(self.player_unit, loadout.robe.unit, "robe")

                loadout.robe.equipment = GameSettings.available_robes[new_robe]

                if loadout.staff.unit then
                    print("attaching staff")
                    World.unlink_unit(world, loadout.staff.unit)
                    World.link_unit(world, loadout.staff.unit, loadout.robe.unit, Unit.node(loadout.robe.unit, InventoryAux.SlotAttachNode.staff))
                end

                if loadout.weapon.unit then
                    print("attaching weapon")
                    World.unlink_unit(world, loadout.weapon.unit)
                    World.link_unit(world, loadout.weapon.unit, loadout.robe.unit, Unit.node(loadout.robe.unit, InventoryAux.SlotAttachNode.weapon))
                end

                equipment_type = "robe"
                equipped_unit = loadout.robe.unit
            end

            if loadout.robe_skin.equipment_id and SkinningAux.try_skin_unit(loadout.robe.unit, GameSettings.available_robes[new_robe], loadout.robe_skin.equipment_name) then
                equipment_type = equipment_type or "robe_skin"
            end

            if check_unit(loadout.staff, InventoryAux.get_staff_filename(GameSettings.available_staffs[new_staff]), world, "staff", loadout.robe.unit) then
                loadout.staff.equipment = GameSettings.available_staffs[new_staff]

                World.link_unit(world, loadout.staff.unit, loadout.robe.unit, Unit.node(loadout.robe.unit, InventoryAux.SlotAttachNode.staff))

                equipment_type = equipment_type or "staff"
                equipped_unit = equipped_unit or loadout.staff.unit or equipped_unit
            end

            if check_unit(loadout.weapon, InventoryAux.get_weapon_filename(GameSettings.available_weapons[new_weapon]), world, "weapon", loadout.robe.unit) then
                loadout.weapon.equipment = GameSettings.available_weapons[new_weapon]

                World.link_unit(world, loadout.weapon.unit, loadout.robe.unit, Unit.node(loadout.robe.unit, InventoryAux.SlotAttachNode.weapon))

                equipment_type = equipment_type or "weapon"
                equipped_unit = equipped_unit or loadout.weapon.unit or equipped_unit
            end

            if loadout.trinket.equipment ~= GameSettings.available_trinkets[new_trinket] then
                equipment_type = equipment_type or "trinket"
            end

            loadout.trinket.equipment = GameSettings.available_trinkets[new_trinket]

            if loadout.ring.equipment ~= GameSettings.available_rings[new_ring] then
                equipment_type = equipment_type or "ring"
            end

            loadout.ring.equipment = GameSettings.available_rings[new_ring]
            loadout.familiar.equipment = GameSettings.available_familiars[new_familiar]

            if check_unit(loadout.familiar, InventoryAux.get_familiar_filename(loadout.familiar.equipment), world, "familiar", nil) then
                local unit = loadout.familiar.unit

                if unit then
                    Unit.set_local_position(unit, 0, Vector3(3, 0, 0.2))
                    Unit.set_local_rotation(loadout.familiar.unit, 0, Quaternion(Vector3.up(), 20 * math.pi / 180))
                    Unit.animation_event(unit, "to_lobby")
                    Unit.animation_event(unit, "lobby_change_familiar")

                    if loadout.familiar.accessories then
                        for i = 1, #loadout.familiar.accessories do
                            if Unit.alive(loadout.familiar.accessories[i]) then
                                World.destroy_unit(world, loadout.familiar.accessories[i])
                            end
                        end
                    end

                    loadout.familiar.accessories = {}

                    local accessory_template = Unit.get_data(unit, "accessory_template")

                    if accessory_template then
                        local accessory_template = AccessoryTemplates[accessory_template]

                        for i = 1, #accessory_template do
                            local accessory_template = accessory_template[i]
                            local unit_type = accessory_template.inventory_type
                            local accessory_unit = World.spawn_unit(world, unit_type, Vector3.zero(), Quaternion.identity())

                            World.link_unit(world, accessory_unit, unit, Unit.node(unit, accessory_template.joint))

                            loadout.familiar.accessories[#loadout.familiar.accessories + 1] = accessory_unit
                        end
                    end
                end
            end

            for i = 1, LoadoutAux.num_magicks do
                local magick_keyword = LoadoutAux.magick_keywords[i]
                local available_magicks = GameSettings.available_magicks_by_tier[i]
                local equipment_id = loadout[magick_keyword].equipment_id
                local new_magick = available_magicks[equipment_id]

                if loadout[magick_keyword].equipment ~= new_magick then
                    equipment_type = equipment_type or "magick"
                    loadout[magick_keyword].equipment = available_magicks[equipment_id]
                end
            end

            if equipped_unit then
                Unit.flow_event(equipped_unit, "play_preview_sound")
            end

            if equipment_type and not no_sound then
                self:play_sound(equipment_type)
            end

            PresenceAux.set(PresenceAux.Skin.KEY, loadout.robe_skin.equipment_name)

            if self.chat_system then
                self.chat_system:set_presence_robe_skin(loadout.robe_skin.equipment_name)
            end
        end)

        kUtil.loop_try_repalce_function(_G, "MenuPlayerLoadout", "set_skin", function(self, equipment_type, skinning_index, persist_changes)
            assert(equipment_type == "robe", "Skins only implemented for robes so far.")

            local current_equipment_name = self.loadout[equipment_type].equipment_name
            local current_skin_name = string.format("%s_%d", current_equipment_name, skinning_index)
            local equipment_skin_type = string.format("%s_skin", equipment_type)

            equipment_type = equipment_skin_type

            if _G.BTLD_DATA.game_state.override_skin then
                k_log("(transmog fallback) preventing skin change ...")
                current_skin_name = _G.BTLD_DATA.game_state.override_skin
                persist_changes = true
            end

            print("MenuPlayerLoadout.set_skin")
            printf("current_equipment_name: %s", current_equipment_name)
            printf("current_skin_name: %s", current_skin_name)
            printf("equipment_skin_type: %s", equipment_skin_type)

            if LoadoutSetup.set_equipment(self.loadout, equipment_skin_type, current_skin_name) then
                self:play_sound(equipment_type)
                self:update_loadout()
            end

            if persist_changes and LoadoutSetup.set_equipment(self.persistent_loadout, equipment_skin_type, current_skin_name) then
                local server_peer_id = self:get_server_peer_id()

                if server_peer_id then
                    pcall(function ()
                        LoadoutSetup.transmit_to_server(self.persistent_loadout, server_peer_id)
                    end)
                end
            end
        end)

        kUtil.loop_try_repalce_function(_G, "MenuCategoryList", "update_skin_tooltip", function(self, ui_renderer, dt, input_data)
            if not self.skin_tooltip_visible then
                return
            end

            local current_skin_name = self.player_loadout:get_skin("robe")
            local current_robe_name = self.player_loadout:get_equipment_name("robe")
            local current_skin_index = current_skin_name:match(current_robe_name .. "_(%d+)")
            local skin_icons = self.skin_icons

            for i = 1, #skin_icons do
                local ui_element = skin_icons[i]
                local icon_name = ui_element:get("icon_texture", "texture")

                icon_name = ui_renderer:has_material(icon_name) and icon_name or "item_icon_wip"

                ui_element:set("icon_texture", "texture", icon_name)
                ui_element:set_pass_enabled("selected", i == current_skin_index)
                ui_element:update(ui_renderer, dt, input_data)

                if ui_element.state.released then
                    k_log("setting skin for robe (" .. tostring(current_robe_name) .. ") :: #" .. tostring(i))
                    if kUtil.is_hotkey_pressed({"shift"}) then
                        local skin_name = current_robe_name .. "_" .. tostring(i)
                        k_log("(transmog fallback) setting override skin :: " .. skin_name)
                        _G.BTLD_DATA.game_state.override_skin = skin_name
                    end
                    self:set_robe_skin(i)
                    self:destroy_skin_tooltip()

                    return true
                end
            end

            self.skin_tooltip_frame:update(ui_renderer, dt, input_data)
        end)

        local skip_equipment_type = {
            consumable = true,
            robe_tint = true,
            robe_skin = true,
            consumable_amount = true,
            magick_start = true
        }
        local NULLIFY_TEXT_COLOR = {
            255,
            235,
            160,
            20
        }
        local ELEMENT_BAR_COLOR = {
            160,
            255,
            255,
            255
        }
        local NULLIFY_BAR_COLOR = {
            160,
            142,
            142,
            142
        }
        local NULLIFY_BAR_COLOR_SPEED_HEALTH = {
            225,
            225,
            225,
            225
        }
        local white_color_table = UISettings.detail_color
        local UI = require_bs("foundation/scripts/ui/ui")

        local function reset_player_data(player_data)
            for k, v in pairs(player_data) do
                player_data[k] = 0
            end

            player_data.speed = 1
            player_data.health = HealthTemplates.player.health
        end

        kUtil.loop_try_repalce_function(_G, "MenuLoadoutStats2", "do_update_loadout_stats", function(self, ui_renderer, menu_player_loadout)
            _G.BTLD_DATA.game_state.menu_loadout_stats2 = self

            if ui_renderer then
                _G.BTLD_DATA.game_state.ui_renderer = ui_renderer
            end

            local stats = self.stats

            reset_player_data(stats)

            local nullify = menu_player_loadout:get_equipment_name("trinket") == "trinket_stats_to_zero"

            if nullify then
                stats.speed = 1
            else
                local speed = 1
                local hitpoints_addition = 0
                local num_loadouts = #LoadoutMapping

                for i = 1, num_loadouts do
                    repeat
                        local equipment_type = LoadoutMapping[i]

                        if skip_equipment_type[equipment_type] then
                            break
                        end

                        local equipment_name = menu_player_loadout:get_equipment_name(equipment_type)

                        if not equipment_name then
                            break
                        end

                        if not EquipmentTemplates[equipment_name] then
                            k_log("missing item in EquipmentTemplates (" .. tostring(equipment_type) .. ") :: " .. tostring(equipment_name))
                            EquipmentTemplates[equipment_name] = {
                                icon = "item_icon_wip",
                                category = equipment_type,
                                description = equipment_name .. "_desc"
                            }
                        end

                        local equipment_template = EquipmentTemplates[equipment_name].ability_name
                        local ability_template = AbilityTemplates[equipment_template]

                        if not ability_template then
                            break
                        end

                        if ability_template then
                            for ability_type, ability_data in pairs(ability_template) do
                                if ability_type == "speed_multiplier" then
                                    stats.speed = stats.speed + (ability_data.multiplier - 1)
                                elseif ability_type == "modify_template_variables" then
                                    for element_type, amount in pairs(ability_data) do
                                        stats[element_type] = (stats[element_type] or 0) + amount
                                    end
                                elseif ability_type == "max_hps_add" then
                                    stats.health = stats.health + ability_data.value
                                end
                            end
                        end
                    until true
                end
            end

            local element_icons = self.element_icons
            local stat_icons = self.stat_icons

            for element_type, amount in pairs(stats) do
                local ui_element
                local element_index = LoadoutAux.element_order[element_type]

                if nullify then
                    amount = 0
                end

                if element_index then
                    ui_element = element_icons[element_index]

                    if amount > 50 then
                        amount = 50
                    elseif amount < -50 then
                        amount = -50
                    end

                    local bar_size_x = self.bar_size * 0.05 + self:get_element_bar_size(amount, self.bar_size)

                    UIElement.get_pass_variable_by_id(ui_element, "element_bar", "size")[1] = bar_size_x

                    UIElement.set_pass_variable_by_id(ui_element, "element_bar", "u1", bar_size_x / (self.bar_size + self.bar_size * 0.05))
                    UIElement.set_pass_variable_by_id(ui_element, "value", "text", 50 + amount)

                    if nullify then
                        UIElement.set_pass_variable_by_id(ui_element, "value", "color", NULLIFY_TEXT_COLOR)
                        UIElement.set_pass_variable_by_id(ui_element, "element_bar", "color", NULLIFY_BAR_COLOR)
                    else
                        UIElement.set_pass_variable_by_id(ui_element, "value", "color", UISettings.detail_color)
                        UIElement.set_pass_variable_by_id(ui_element, "element_bar", "color", ELEMENT_BAR_COLOR)
                    end
                elseif stat_icons[element_type] ~= nil then
                    ui_element = stat_icons[element_type]
                end

                local tooltip_title = string.format("menu_player_info_%s_hover_title", element_type)
                local tooltip_text = string.format("menu_player_info_%s_hover_text", element_type)

                tooltip_title = LocalizationManager:lookup(tooltip_title)
                tooltip_text = LocalizationManager:lookup(tooltip_text)

                local textarea = TextArea(ui_renderer, UI.tooltip.textarea_settings)

                textarea:append(tooltip_title, UI.tooltip.title_font, UI.tooltip.title_font_size)
                textarea:append("\n\n")
                textarea:append(tooltip_text)
                ui_element:set("element_tooltip", "textarea", textarea)
            end

            if next(self.delta_loadout) then
                self:reset_modified_loadout_stats()
            end

            local weapon_unit = menu_player_loadout.loadout.weapon.unit

            stats.melee = math.floor(Unit.get_data(weapon_unit, "damage", "default", 1) or 1)
            stats.attack_speed = Unit.get_data(weapon_unit, "attack_info", "chain_info", 0, "attack_animation_length") or 1
            stats.speed = math.round(stats.speed * 100)

            local stat_icons = self.stat_icons

            UIElement.set_pass_variable_by_id(stat_icons.health, "value", "text", tostring(stats.health))
            UIElement.set_pass_variable_by_id(stat_icons.melee, "value", "text", tostring(stats.melee))
            UIElement.set_pass_variable_by_id(stat_icons.attack_speed, "value", "text", string.format("%.2f", stats.attack_speed))
            UIElement.set_pass_variable_by_id(stat_icons.speed, "value", "text", string.format("%s%%", tostring(stats.speed)))

            if nullify then
                UIElement.set_pass_variable_by_id(stat_icons.health, "value", "color", NULLIFY_TEXT_COLOR)
                UIElement.set_pass_variable_by_id(stat_icons.speed, "value", "color", NULLIFY_TEXT_COLOR)
                UIElement.set_pass_variable_by_id(stat_icons.health, "background", "color", NULLIFY_BAR_COLOR_SPEED_HEALTH)
                UIElement.set_pass_variable_by_id(stat_icons.speed, "background", "color", NULLIFY_BAR_COLOR_SPEED_HEALTH)
            else
                UIElement.set_pass_variable_by_id(stat_icons.health, "value", "color", UISettings.detail_color)
                UIElement.set_pass_variable_by_id(stat_icons.speed, "value", "color", UISettings.detail_color)
                UIElement.set_pass_variable_by_id(stat_icons.health, "background", "color", white_color_table)
                UIElement.set_pass_variable_by_id(stat_icons.speed, "background", "color", white_color_table)
            end
        end)

        local transmit_equipment_name_table = {}
        local transmit_equipment_type_table = {}

        kUtil.loop_try_repalce_function(_G, "LoadoutSetup", "copy_valid_changes", function(destination, source, inventory)
            local has_changed = false

            for name, entry in pairs(destination) do
                local source_entry = source[name]

                if source_entry and (entry.equipment_name ~= source_entry.equipment_name or false) then
                    if inventory and not inventory.owns_item(inventory, source_entry.equipment_name) and not inventory.owns_bulk_item(inventory, source_entry.equipment_name) then
                        cat_printf_green("This item is not owned, invalid change: ", source_entry.equipment_name)
                    else
                        entry.equipment_name = source_entry.equipment_name
                        entry.equipment_id = source_entry.equipment_id
                        has_changed = true
                    end
                end
            end

            local skin_check = string.find(destination.robe_skin.equipment_name, destination.robe.equipment_name .. "_%d")
            k_log("skin check for [" .. tostring(destination.robe_skin.equipment_name) .. "] and [" .. tostring(destination.robe.equipment_name) .. "] :: " .. tostring(skin_check))

            if not skin_check then
                k_log("OVERRIDING SKIN CHECK !!!")
                --LoadoutSetup.set_equipment(destination, "robe", string.gsub(destination.robe_skin.equipment_name, "_%d", ""))
                --has_changed = true
            end

            return has_changed
        end)

        kUtil.loop_try_repalce_function(_G, "SkinningAux", "try_skin_unit", function(unit, robe_name, skin_name, make_permanent, override)
            if not unit then
                return false
            end

            if not skin_name then
                return false
            end

            local current_skin = Unit.get_data(unit, "skin")
            local material, skin_id

            if tonumber(skin_name) then
                skin_id = tonumber(skin_name)
            else
                skin_id = skin_name:match(robe_name .. "_(%d+)")
            end

            if skin_id == nil then
                robe_name = skin_name:gsub("_(%d+)$", "")
                k_log("(transmog fallback) robe_name :: " .. tostring(robe_name))
                skin_id = skin_name:match(robe_name .. "_(%d+)")
                k_log("(transmog fallback) skin_id :: " .. tostring(skin_id))
            end


            if current_skin == skin_id and not override then
                return false
            end

            if not skin_id or skin_id == 1 then
                material = Unit.get_data(unit, "material")
            elseif not Unit.has_data(unit, "material_variations", skin_id - 1) then
                return false
            else
                material = Unit.get_data(unit, "material_variations", skin_id - 1)
            end

            local dot = StringAux.find_last_of(material, ".", true)

            if dot then
                material = material:sub(1, dot - 1)
            end

            if make_permanent then
                Unit.set_data(unit, "material", material)
            end

            Unit.set_material_variation(unit, material)
            Unit.set_data(unit, "skin", skin_id)
            Unit.flow_event(unit, "set_skin_" .. tostring(skin_id))

            return true
        end)

        local InventorySlots = {
            "robe",
            "staff",
            "weapon",
            "hat",
            "boots",
            "gloves",
            "other",
            "other2"
        }
        InventorySlots = table.make_bimap(InventorySlots)

        local function add_inventory_unit(unit_spawner, world, unit, extension_data, unit_name, index, extension_init_data)
            local inventory = extension_data.inventory
            local slot_name = InventorySlots[index]

            assert(slot_name)

            local inventory_unit = unit_spawner:spawn_unit_local_register_extensions(unit_name, nil, nil, extension_init_data)

            inventory[slot_name] = inventory_unit

            InventoryAux.set_flow_variable_on_inventory_item(inventory_unit, unit)
            InventoryAux.set_flow_variable_on_wielder(unit, inventory_unit, slot_name)

            local child = inventory_unit
            local parent, parent_link_node_index

            if index == InventorySlots.robe then
                parent = unit
                parent_link_node_index = 0
            else
                local attach_node_name = InventoryAux.SlotAttachNode[slot_name]

                parent = assert(inventory.robe)
                parent_link_node_index = Unit.node(parent, attach_node_name)

                InventoryAux.destroy_non_damage_physic_actors(inventory_unit)
            end

            World.link_unit(world, child, parent, parent_link_node_index)
            Unit.set_data(child, "owner_player", unit)
            print("added " .. unit_name)
            SETUP_STATE({
                unit_name = unit_name,
                parent = parent,
                child = child,
                world = world,
                parent_link_node_index = parent_link_node_index
            }, "inventory_system", "add_inventory_unit")
        end

        local function InventorySystemAux_init_extension_by_loadout(u, extension, loadout, world, unit_spawner, event_delegate)
            local is_husk = extension.is_husk
            local inventory_extension_init_data = {
                damage_info = {
                    is_husk = is_husk
                }
            }
            local loadout = table.deep_clone(loadout)

            local skin_robe_name = LoadoutAux.robe_skin(loadout):gsub("_(%d+)$", "")
            local loadout_robe_id, loadout_robe = LoadoutAux.robe_id(loadout), LoadoutAux.robe(loadout)

            if skin_robe_name ~= loadout_robe then
                k_log("(transmog fallback) robe visuals dont match :: " .. tostring(skin_robe_name) .. " / " .. tostring(loadout_robe))
                k_log("(transmog fallback) overrding ...")
                loadout_robe_id = nil
                loadout_robe = skin_robe_name
            end

            local loadout_staff_id, loadout_staff = LoadoutAux.staff_id(loadout), LoadoutAux.staff(loadout)
            local loadout_weapon_id, loadout_weapon = LoadoutAux.weapon_id(loadout), LoadoutAux.weapon(loadout)
            local robe_unit_name = InventoryAux.get_robe_filename(loadout_robe)
            local staff_unit_name = InventoryAux.get_staff_filename(loadout_staff)
            local weapon_unit_name = InventoryAux.get_weapon_filename(loadout_weapon)

            add_inventory_unit(unit_spawner, world, u, extension, robe_unit_name, 1, inventory_extension_init_data)
            add_inventory_unit(unit_spawner, world, u, extension, staff_unit_name, 2, inventory_extension_init_data)
            add_inventory_unit(unit_spawner, world, u, extension, weapon_unit_name, 3, inventory_extension_init_data)
        end

        kUtil.loop_try_repalce_function(_G, "InventorySystem", "on_add_extension", function(self, unit, extension_name, extension_init_data)
            local owner_peer_id = extension_init_data and extension_init_data.owner or pdNetworkServerUnit.owning_peer(unit)
            local extension = {
                is_husk = false,
                owner_peer_id = owner_peer_id,
                inventory = {},
                input = {}
            }

            if extension_name == "inventory" then
                -- block empty
            elseif extension_name == "inventory_husk" then
                extension_name = "inventory"
                extension.is_husk = true
            else
                assert(false)
            end

            local loadout = assert(self.game_detail_synchronizer:get_peer_loadout(extension.owner_peer_id))

            InventorySystemAux_init_extension_by_loadout(unit, extension, loadout, self.world, self.unit_spawner, self.event_delegate)

            if self.CLIENT and owner_peer_id == self.own_peer_id and DevelopmentSetting("animation_debug") and extension.inventory.robe then
                Unit.set_animation_logging(extension.inventory.robe, true)
            end

            EntityAux.set_extension(unit, extension_name, extension)

            return extension
        end)

        game_functions_hooked = true
    end

    _G.BTLD_DATA.hidden_settings = LOAD_GLOBAL_MOD_SETTINGS(_G.BTLD_DATA.info.name, _G.BTLD_DATA.hidden_settings, true)
    SAVE_GLOBAL_MOD_SETTINGS(_G.BTLD_DATA.info.name, _G.BTLD_DATA.hidden_settings, true)

    local better_loadout_mod_tab = {tab = nil}

    better_loadout_mod_tab.tab = UIFunc.new_mod_tab("BetterLoadouts Mod", "BetterLoadouts", function()
        local tab_description = _G.BTLD_DATA.info .. "\nCreated by " .. _G.BTLD_DATA.author
        UIFunc.add_element_to_tab(better_loadout_mod_tab.tab, UIFunc.new_text_markup(VERSION_WHOLE, {100, GET_SCREEN_SIZE_Y() - 200, 502}, 40, {255, 255, 255, 255}, false, {}))
        UIFunc.add_element_to_tab(better_loadout_mod_tab.tab, UIFunc.new_text_body(tab_description, {100, GET_SCREEN_SIZE_Y() - 250, 502}, 20, 100, 25))
    end)

    kUtil.task_scheduler.add(function ()
        local bar_btn_data = {
            {name = "RANDOM LOADOUT", pos = {700, 32, 500}, func = open_random_popup, text_offset = -22},
            {name = "APPLY LOADOUT", pos = {900, 32, 500}, func = open_load_popup, text_offset = -13},
            {name = "SAVE LOADOUT", pos = {1100, 32, 500}, func = open_save_popup, text_offset = -11}
        }


        for _, data in pairs(bar_btn_data) do
            local bar_btn = UIFunc.new_button_unattached(data.pos, data.name, data.text_offset, 0, data.func)
            bar_btn.properties.text.size = 16
            bar_btn.properties.texture.size.x = 200
            NEW_UI_ELEMENT(ACTIVE_GAME_STATE, bar_btn)
        end

        local update_initial_loadout
        update_initial_loadout = function ()
            if _G.BTLD_DATA.game_state.menu_player_loadout then
                MenuPlayerLoadout.update_loadout(_G.BTLD_DATA.game_state.menu_player_loadout)
            else
                kUtil.task_scheduler.add(function ()
                    update_initial_loadout()
                end, 100)
            end
        end

        update_initial_loadout()
    end, 200)
end

EventHandler.register_event("menu", "init", "BetterLoadouts_init", init_mod)
