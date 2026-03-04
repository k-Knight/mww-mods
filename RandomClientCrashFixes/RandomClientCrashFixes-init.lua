-- Add require stuff here
local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    local DuelState = table.make_bimap_inplace({
        "WAITING_TO_PRESENT_DUELERS",
        "PRESENTING_DUELERS",
        "IN_DUEL_COUNTDOWN",
        "DUEL_UNDER_WAY",
        "PRESENTING_DUEL_RESULT"
    })

    kUtil.loop_try_prehook_function(_G, "NetworkGameModeDuelClientGame", "on_unit_resurrected", function(self, peer_id, unit)
        if not self.timpani_world or (not self.last_end_round_event_id and self.duel_state ~= DuelState.DUEL_UNDER_WAY) then
            k_log("[RandomClientCrashFixes] trying to prevent player duel ressurect crash ...")
            return true, nil
        end
    end)

    kUtil.loop_try_repalce_function(_G, "EntityAux", "add_ability", function(u, ability, arg)
        local status, err = pcall(function()
            assert(ability)
            arg = arg or "dummy_param"

            local input = EntityAux.extension(u, "ability_user", true).input

            input.dirty_flag = true

            local abilities = input.start_ability

            abilities[#abilities + 1] = ability
            abilities[#abilities + 1] = arg
        end)

        if not status then
            k_log("[RandomClientCrashFixes] error in EntityAux.add_ability() :: " .. tostring(err))
        end
    end)

    kUtil.loop_try_repalce_function(_G, "EntityAux", "add_effect", function(u, effect_table)
        local status, err = pcall(function()
            assert(effect_table.effect_type, "Nil effect provided to add-effect.")

            local input = EntityAux.extension(u, "effect_producer", true).input

            input.dirty_flag = true

            local new_effects = input.new_effects

            new_effects[#new_effects + 1] = effect_table
        end)

        if not status then
            k_log("[RandomClientCrashFixes] error in EntityAux.add_effect() :: " .. tostring(err))
        end
    end)

    local function call_destroy_listener(unit_destroy_listeners, unit)
        local listeners = unit_destroy_listeners[unit]

        if not listeners then
            return
        end

        for _, listener in pairs(listeners) do
            listener(unit)
        end

        unit_destroy_listeners[unit] = nil
    end

    kUtil.loop_try_repalce_function(_G, "pdNetworkUnitSpawner", "delete_units", function(self, world, units)
        local game_session, unit_storage = self.game_session, self.unit_storage

        if not game_session then
            print_warning("[unit_spawner] no network game")
        end

        local unit_destroy_listeners = self.unit_destroy_listeners
        local own_peer_id = self.own_peer_id
        local Unit_alive = Unit.alive
        local World_destroy_unit = World.destroy_unit
        local NetworkUnit_game_object_id = NetworkUnit.game_object_id
        local GameSession_destroy_game_object = GameSession.destroy_game_object
        local gameobject_notifier = self.gameobject_notifier

        if game_session then
            for unit, _ in pairs(units) do
                local unit_is_alive, unit_alive_name = Unit_alive(unit)

                if unit_is_alive then
                    local go_id_to_remove = unit_storage:go_id(unit)
                    local status, err = pcall(function()
                        cat_printf_info_blue("unit_spawner", "[%s] delete_units : unit [%s] destroyed with go_id [%s], unique_id [%s]", self.identifier_tag, tostring(unit), tostring(go_id_to_remove), tostring(UnitAux.unique_id(unit)))

                        if go_id_to_remove then
                            GameSession_destroy_game_object(game_session, go_id_to_remove)
                            gameobject_notifier:add_destroyed_gameobject_id(go_id_to_remove, own_peer_id)
                            call_destroy_listener(unit_destroy_listeners, unit)
                            self:notify_go_type_listeners("destroy", unit_storage:go_type(go_id_to_remove), unit, go_id_to_remove, own_peer_id)
                            unit_storage:remove(go_id_to_remove)
                        elseif NetworkUnit_game_object_id(unit) then
                            assert(false, "unit_spawner major fail! -> " .. tostring(unit))
                        end

                        if not go_id_to_remove then
                            call_destroy_listener(unit_destroy_listeners, unit)
                        end

                        World_destroy_unit(world, unit)
                    end)

                    if not status then
                        k_log("[RandomClientCrashFixes] error deleting unit (go_id : " .. tostring(go_id_to_remove) .. ") :: " .. tostring(err))
                    end
                else
                    cat_printf_info_blue("unit_spawner", "[%s] delete_units : unit was already destroyed!", self.identifier_tag)
                end
            end
        else
            for unit, _ in pairs(units) do
                local unit_is_alive, unit_alive_name = Unit_alive(unit)

                if not unit_is_alive then
                    assert(false)
                end

                cat_printf_info_blue("unit_spawner", "[%s] delete_units : unit [%s] destroyed without gamesession. unique_id [%s]", self.identifier_tag, tostring(unit), tostring(UnitAux.unique_id(unit)))
                call_destroy_listener(unit_destroy_listeners, unit)
                World_destroy_unit(world, unit)
            end
        end
    end)
end

EventHandler.register_event("menu", "init", "RandomClientCrashFixes_init", init_mod)
