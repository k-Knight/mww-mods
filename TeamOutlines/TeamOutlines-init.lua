local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local mod_inited = false

local MY_CUSTOM_HIGHLIGHT_KEY = "mod_team_outline"

function apply_game_outline(target_unit, enable, color_vector)
    if not target_unit or not Unit.alive(target_unit) then
        k_log("[TeamOutlines] unit is not valid :: " .. tostring(target_unit))
        return
    end
    
    local outline_ext = EntityAux.extension(target_unit, "outline")
    if not outline_ext then
        k_log("[TeamOutlines] unit missing outline extension !!!")
        return
    end

    if enable then
        if not outline_ext.state[MY_CUSTOM_HIGHLIGHT_KEY] then
            local outline_data = {
                add = true,
                name = MY_CUSTOM_HIGHLIGHT_KEY,
                outline = {
                    alpha = 0.25,
                    size = 0.05,
                    color = color_vector or {1, 0, 1}
                }
            }
    
            EntityAux.append_input(target_unit, "outline", "add_remove_outline", outline_data)
        end
    else
        local remove_data = {
            name = MY_CUSTOM_HIGHLIGHT_KEY
        }

        EntityAux.append_input(target_unit, "outline", "add_remove_outline", remove_data)
    end
end

local try_apply_outline_to_players = function ()
    repeat
        if not kUtil.entity_manager then
            k_log("[TeamOutlines] missing entity_manager !!!!")
            break
        end
            
        local players, players_n = kUtil.entity_manager:get_entities("player")
        local my_player
    
        for _, player in pairs(players) do
            if pdNetworkServerUnit.owning_peer_is_self(player.unit) then
                my_player = player
                break
            end
        end

        local my_team = 1

        if my_player then
            local team_ext = EntityAux.extension(my_player.unit, "team")
        
            my_team = team_ext.internal and team_ext.internal.team or my_team
        end

        for _, player in pairs(players) do
            local team_ext = EntityAux.extension(player.unit, "team")
            local is_friend = (team_ext and team_ext.internal and team_ext.internal.team or (my_team - 1)) == my_team

            apply_game_outline(player.unit, true, is_friend and {0, 1, 0.35} or {1, 0, 0.35})
        end
    until true
end

local outline_async_loop
outline_async_loop = function ()
    pcall(try_apply_outline_to_players)
    kUtil.task_scheduler.add(outline_async_loop, 1000)
end

local function init_mod(context)
    if mod_inited then
        return
    end

    outline_async_loop()

    mod_inited = true
end


EventHandler.register_event("menu", "init", "TeamOutlines_init", init_mod)
