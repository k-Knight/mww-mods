local InputController = require("scripts/input_controller")

_G.BTLD_DATA = {}

local VERSION = "2.0"
local VERSION_WHOLE = "BetterLoadouts Mod Version " .. VERSION
local ACTIVE_GAME_STATE = "menu"

local string_dash_break = "-----------------------------------------------------------\n"

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

local function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

local function string_insert(whole_string, insert, pos)
    if pos < 1 then pos = 1 end
    return whole_string:sub(1, pos - 1) .. insert .. whole_string:sub(pos)
end

local function popup_function_self_destroy(popup_item, button_function)
    if button_function then
        button_function()
    end
    UIFunc.kill_element_and_children(popup_item)
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
    local gear_string = string_dash_break
    local persistent_setup = _G.BTLD_DATA.game_state.menu_player_loadout and _G.BTLD_DATA.game_state.menu_player_loadout.loadout or nil

    for k in pairs(loadout) do
        k_log("applying loadout [" .. tostring(k) .. "] :: " .. tostring(loadout[k]["equipment_name"]))
        LoadoutSetup.set_equipment(setup, k, loadout[k]["equipment_name"])

        if persistent_setup then
            LoadoutSetup.set_equipment(persistent_setup, k, loadout[k]["equipment_name"])
        end

        if k == "staff" or k == "ring" or k == "trinket" or k == "robe" or k == "weapon" then
            if k == "robe" then
                gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. " () \n"
            else
                gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. "\n"
            end
        end
    end

    if _G.BTLD_DATA.game_state.menu_player_loadout then
        MenuPlayerLoadout.update_loadout(_G.BTLD_DATA.game_state.menu_player_loadout)
        if persistent_setup then
            LoadoutSetup.transmit_to_server(
                persistent_setup,
                MenuPlayerLoadout.get_server_peer_id(_G.BTLD_DATA.game_state.menu_player_loadout)
            )
        end
    end

    for k in pairs(loadout) do
        if k == "robe_skin" then
            local position = string.find(gear_string, "%(")
            if position then
                gear_string = string_insert(gear_string, LocalizationManager:lookup(loadout[k]["equipment_name"]), position)
            end
        end
    end
end

local function random_loadout()
    local setup = LoadoutSetup_init_from_defaults()
    local persistent_setup = _G.BTLD_DATA.game_state.menu_player_loadout and _G.BTLD_DATA.game_state.menu_player_loadout.loadout or nil
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

        if persistent_setup then
            LoadoutSetup.set_equipment(persistent_setup, type, equipment_name)
        end
    end

    if _G.BTLD_DATA.game_state.menu_player_loadout then
        MenuPlayerLoadout.update_loadout(_G.BTLD_DATA.game_state.menu_player_loadout)
        if persistent_setup then
            LoadoutSetup.transmit_to_server(
                persistent_setup,
                MenuPlayerLoadout.get_server_peer_id(_G.BTLD_DATA.game_state.menu_player_loadout)
            )
        end
    end
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

local function create_loadout_select_popup(action_fn, title_prefix, check_existing)
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
        end)

        kUtil.loop_try_repalce_function(_G, "LoadoutSetup", "sanity_check_loadout", function(setup_map)
            k_log("DISCARDING LOADOUT SANITY CHECK !!!")
            return true
        end)

        kUtil.loop_try_prehook_function(_G, "LobbyLoadoutWorld", "set_loadout", function(self, loadout, player_index)
            if loadout and LoadoutMapping and loadout[LoadoutMapping.robe_skin] and NetworkLookup.equipments then
                local new_robe_skin = NetworkLookup.equipments[loadout[LoadoutMapping.robe_skin]]
                k_log("==================== new robe skin for player #" .. tostring(player_index) .. " :: " .. tostring(new_robe_skin))
            end
        end)

        kUtil.loop_try_repalce_function(_G, "InventorySystem", "set_visible" function(self, u)
            set_unit_and_inventory_visibility(u, true)

            local extension = EntityAux_extension(u, "inventory")

            if not extension then
                return
            end

            local loadout = assert(self.game_detail_synchronizer:get_peer_loadout(extension.owner_peer_id))
            local robe_skin = loadout[LoadoutMapping.robe_skin]
            local robe = loadout[LoadoutMapping.robe]

            if robe and robe_skin and self.CLIENT then
                local success = SkinningAux.try_skin_unit(extension.inventory.robe, NetworkLookup.equipments[robe], NetworkLookup.equipments[robe_skin], true, true)
                k_log("-------------------- unit skinning result [" .. tostring(robe_skin) .. "] :: " .. tostring(success))

                pdUnitAux.update_unit_material_settings(extension.inventory.robe)
            end
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

    SIMPLE_TIMER(0.2, function()
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
    end)
end

EventHandler.register_event("menu", "init", "BetterLoadouts_init", init_mod)
