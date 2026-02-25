local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

_G.WLF_Units = {}

local ensure_unit_info = function(unit)
    local unit_info = WLF_Units[unit]

    if not unit_info then
        k_log("WaterLockFix] initializing unit_info ...")
        unit_info = {
            time_in = 0,
            time_out = 0,
            time = 0,
            mult = 1,
            pushed = false
        }
    end

    WLF_Units[unit] = unit_info

    return unit_info
end

local get_unit_info = function(unit)
    return WLF_Units[unit] or nil
end

local update_unit_info = function(unit_info, dt)
    unit_info.time = unit_info.time_in - unit_info.time_out

    if unit_info.pushed then
        unit_info.time = unit_info.time + dt

        unit_info.time_in = unit_info.time
        unit_info.time_out = 0
    else
        unit_info.time_out = unit_info.time_out + dt

        if unit_info.time_out > 1.0 then
            unit_info.time_out = 0
            unit_info.time_in = 0
            unit_info.time = 0
        end
    end

    local bad_time = unit_info.time - 2
    bad_time = bad_time > 0 and bad_time or 0
    unit_info.mult = math.max(1.0 - (bad_time / 1), 0)
end

local on_tick_state_update = function (dt)
    for _, unit_info in pairs(WLF_Units) do
        update_unit_info(unit_info, dt)
    end
end

local function try_patch_waterlocking()
    local status, err = pcall(function()
        repeat
            if (not CharacterStateInAir) or CharacterStateInAir._old_on_enter then
                break
            end

            CharacterStateInAir._old_on_enter = CharacterStateInAir.on_enter
            CharacterStateInAir.on_enter = function(self)
                k_log("entering inair")
                local unit_info = ensure_unit_info(self._unit)
                unit_info.pushed = true

                return CharacterStateInAir._old_on_enter(self)
            end

            CharacterStateInAir._old_on_exit = CharacterStateInAir.on_exit
            CharacterStateInAir.on_exit = function(self)
                k_log("exiting inair")
                local unit_info = ensure_unit_info(self._unit)
                unit_info.pushed = false

                return CharacterStateInAir._old_on_exit(self)
            end

            CharacterStatePushed._old_on_enter = CharacterStatePushed.on_enter
            CharacterStatePushed.on_enter = function(self)
                k_log("entering pushed")
                local unit_info = ensure_unit_info(self._unit)
                unit_info.pushed = true

                return CharacterStatePushed._old_on_enter(self)
            end

            CharacterStatePushed._old_on_exit = CharacterStatePushed.on_exit
            CharacterStatePushed.on_exit = function(self)
                k_log("exiting pushed")
                local unit_info = ensure_unit_info(self._unit)
                unit_info.pushed = false

                return CharacterStatePushed._old_on_exit(self)
            end
        until true

        repeat
            if (not DamageSystem) or DamageSystem._old_update_damage_receiver_husks then
                break
            end

            k_log("[WaterLockFix] overridng DamageSystem.update_damage_receiver_husks() !!!")

            local ATTACKERS_TABLE = {}

            DamageSystem._old_update_damage_receiver_husks = DamageSystem.update_damage_receiver_husks
            function DamageSystem:update_damage_receiver_husks()
                local alloc_table = FrameTable.alloc_table
                local entities, entities_n = self:get_entities("damage_receiver_husk")

                for i = 1, entities_n do
                    repeat
                        local extension_data = entities[i]
                        local unit, extension = extension_data.unit, extension_data.extension
                        local input = extension.input
                        local state = extension.state
                        local dmg = state.damage

                        for j = 1, #dmg do
                            dmg[j] = nil
                        end

                        state.damage_taken = false
                        state.damage_n = 0

                        if not input.dirty_flag then
                            break
                        end

                        input.dirty_flag = false

                        local inputdmg = input.damage
                        local damage_n = #inputdmg

                        state.dirty = damage_n > 0

                        local damage_taken = false
                        local state_damage_n = 0

                        for damage_i = 1, damage_n do
                            local damage_data = inputdmg[damage_i]

                            inputdmg[damage_i] = nil

                            local damages = damage_data
                            local num_attackers = damage_data.num_attackers
                            local attacker = damage_data[1]
                            local category = damage_data.category

                            for damage_type, damage_amount in pairs(damages) do
                                repeat
                                    if damage_type == "category" or damage_type == "num_attackers" or damage_type == "metadata" or lua_type(damage_type) == "number" then
                                        break
                                    end

                                    damage_taken = true

                                    local other_hit_by_self = false
                                    local self_hit = pdNetworkServerUnit.owning_peer_is_self(unit)

                                    if Unit.alive(attacker) and pdNetworkServerUnit.owning_peer_is_self(attacker) and (category == "beam" or category == "melee") and not self_hit and not damage_type == "life" then
                                        other_hit_by_self = true
                                    end

                                    self:trigger_beam_damage_sound(unit, damage_type, self_hit, other_hit_by_self)

                                    if damage_type ~= "push" and damage_type ~= "elevate" and damage_type ~= "knockdown" then
                                        state_damage_n = state_damage_n + 1

                                        do
                                            local new_dmg = alloc_table()

                                            if not AllElementsMap[damage_type] then
                                                assert(false, "Could not find damage element %s in element types.", damage_type)
                                            end

                                            local attackers_table = alloc_table()

                                            for apa = 1, num_attackers do
                                                attackers_table[apa] = damage_data[apa]

                                                GLOBAL_ASSERT_IS_UNIT(attackers_table[apa])
                                            end

                                            new_dmg[DamageDataIndex.DAMAGE_TYPE] = damage_type
                                            new_dmg[DamageDataIndex.DAMAGE_AMOUNT] = damage_amount
                                            new_dmg[DamageDataIndex.ATTACKERS] = attackers_table
                                            new_dmg[DamageDataIndex.DAMAGE_CATEGORY] = category
                                            new_dmg[DamageDataIndex.NUM_ATTACKERS] = num_attackers
                                            new_dmg[DamageDataIndex.PIERCE_RES] = damage_data.metadata and damage_data.metadata.pierce_resistance or false
                                            dmg[state_damage_n] = new_dmg
                                        end

                                        break
                                    end

                                    if extension.is_owned_unit then
                                        do
                                            local invulnerable = EntityAux.extension(unit, "health") and EntityAux.state(unit, "health").invulnerable

                                            if not invulnerable then
                                                if damage_type == "knockdown" then
                                                    do
                                                        local character_extension = extension.character_extension
                                                        local immune = character_extension and character_extension.internal.knockdown_immunity

                                                        if character_extension and not immune then
                                                            local defense_ext = EntityAux.extension(unit, "defense")
                                                            local earth_res = defense_ext.internal.resistances.earth

                                                            earth_res = earth_res and earth_res.mul[1][2] or 1
                                                            immune = earth_res ~= 1

                                                            local knockdown_limit = character_extension.knockdown_limit

                                                            if knockdown_limit <= damage_amount and not immune then
                                                                character_extension.internal.knockdown_immunity = character_extension.knockdown_immunity_duration

                                                                EntityAux.set_input_by_extension(character_extension, "knockdown", true)
                                                            end
                                                        end
                                                    end

                                                    break
                                                end

                                                local water_res = 1
                                                local defense_ext = EntityAux.extension(unit, "defense")
                                                local earth_res = defense_ext.internal.resistances.earth

                                                earth_res = earth_res and earth_res.mul[1][2] or 1

                                                local steam_res = 1

                                                if damage_data.steam then
                                                    local defense_ext = EntityAux.extension(unit, "defense")

                                                    steam_res = defense_ext.internal.resistances.steam
                                                    steam_res = steam_res and steam_res.mul[1][2] or 1

                                                    if damage_data.fire and damage_data.fire > 0 then
                                                        damage_data.steam = damage_data.steam + damage_data.fire
                                                        damage_data.fire = 0
                                                    end
                                                end

                                                if damage_data.water then
                                                    water_res = defense_ext.internal.resistances.water
                                                    water_res = water_res and water_res.mul[1][2] or 1
                                                    water_res = SpellSettings.selfshield_water_push_resistance(water_res)
                                                    earth_res = math.lerp(earth_res, 1, 0.5)
                                                end

                                                local inair_push_mult, inair_time = 1, 0
                                                local unit_info = get_unit_info(unit)

                                                if unit_info then
                                                    inair_push_mult = unit_info.mult
                                                    inair_time = unit_info.time
                                                end

                                                local push_resistance = water_res * earth_res * steam_res * inair_push_mult
                                                k_log("[WaterLockFix] push_resistance :: " .. tostring(push_resistance))
                                                k_log("[WaterLockFix] inair push mult :: " .. tostring(inair_push_mult))
                                                k_log("[WaterLockFix] inair time :: " .. tostring(inair_time))

                                                if push_resistance > 0 then
                                                    local impulse = damage_amount
                                                    local impulse_duration = 0.25

                                                    --k_log("[WaterLockFix] dmg --- " .. damage_type .. " :: ")
                                                    --if type(impulse) == "number" then
                                                    --    k_log("    number :: " .. tostring(impulse))
                                                    --else
                                                    --    k_log_table(impulse, 1, "    ")
                                                    --end


                                                    if type(impulse) == "number" then
                                                        damage_amount = damage_amount * push_resistance

                                                        local direction

                                                        if damage_type == "elevate" then
                                                            direction = Vector3.up()
                                                        else
                                                            local target = unit
                                                            local du_wp = Unit.world_position(attacker, 0)
                                                            local t_wp = Unit.world_position(target, 0)

                                                            direction = Vector3.normalize(t_wp - du_wp)

                                                            if attacker == target then
                                                                direction = -Unit.world_forward(target, 0)
                                                            end

                                                            direction.z = 0
                                                        end

                                                        assert(type(damage_amount) == "number", "Bad push-type in damage system.")

                                                        impulse = direction * damage_amount
                                                    elseif damage_type == "push" then
                                                        impulse = Vector3Aux.unbox(impulse) * push_resistance
                                                        impulse_duration = damage_amount[4]
                                                    else
                                                        damage_amount[1] = damage_amount[1] * push_resistance
                                                        impulse = Vector3.up() * damage_amount[1]
                                                        impulse_duration = damage_amount[2]
                                                    end

                                                    local character_extension = extension.character_extension

                                                    if character_extension then
                                                        do
                                                            local weight, start_weight = character_extension.character_weight, character_extension.character_weight_start

                                                            if weight > GameSettings.infinite_weight_threshold then
                                                                impulse = Vector3.zero()
                                                            else
                                                                impulse = impulse * (start_weight / weight)
                                                            end

                                                            local boxed_impulse = Vector3Aux.box({}, impulse)
                                                            local behavior = EntityAux.extension(unit, "behaviour")

                                                            if not behavior then
                                                                boxed_impulse[4] = impulse_duration
                                                            else
                                                                boxed_impulse[3] = boxed_impulse[3] * 0.1
                                                            end

                                                            if damage_type == "push" then
                                                                local new_push = Vector3Aux.length_squared(impulse) * boxed_impulse[4] * GameSettings.push_state_sensitivity * push_resistance

                                                                if not character_extension.input.push_amount then
                                                                    character_extension.input.push_amount = new_push
                                                                else
                                                                    character_extension.input.push_amount = character_extension.input.push_amount + new_push
                                                                end
                                                            end

                                                            character_extension.last_push_dmg_unit = attacker

                                                            EntityAux.set_input_by_extension(character_extension, "impulse", boxed_impulse)
                                                        end

                                                        break
                                                    end

                                                    local num_actors = Unit.num_actors(unit) - 1
                                                    local is_dynamic = false
                                                    local dynamic_actor

                                                    for j = 0, num_actors do
                                                        local actor = Unit.actor(unit, j)

                                                        if actor and Actor.is_physical(actor) then
                                                            is_dynamic = true
                                                            dynamic_actor = actor
                                                        end
                                                    end

                                                    if is_dynamic then
                                                        local impulse_scale = Unit.get_data(unit, "impulse_scale") or 1

                                                        Actor.add_impulse(dynamic_actor, impulse * impulse_scale)
                                                    end
                                                end
                                            end
                                        end

                                        break
                                    end

                                    if unit ~= attacker then
                                        local is_reflectable = damage_data.metadata and damage_data.metadata.is_reflectable
                                        local is_invulnerable = EntityAux.extension(unit, "health") and EntityAux.state(unit, "health").invulnerable
                                        local char_ext = EntityAux.extension(unit, "character")

                                        if not is_invulnerable and is_reflectable and char_ext then
                                            local water_res = 1
                                            local defense_ext = EntityAux.extension(unit, "defense")

                                            if damage_data.water and defense_ext then
                                                water_res = defense_ext.internal.resistances.water

                                                if water_res then
                                                    local res = 1
                                                    local mul = water_res.mul[1]

                                                    for i = 1, #mul do
                                                        res = res * mul[i]
                                                    end

                                                    water_res = res
                                                else
                                                    water_res = 1
                                                end

                                                water_res = SpellSettings.selfshield_water_push_resistance(water_res)
                                            end

                                            if water_res == 0 then
                                                local damage_copy = table.clone(damage_data)

                                                for i = 1, damage_copy.num_attackers do
                                                    damage_copy[i] = nil
                                                end

                                                damage_copy.num_attackers = nil
                                                damage_copy.volume = nil
                                                damage_copy.knockdown = nil

                                                if damage_copy.push then
                                                    damage_copy.push[1] = -damage_copy.push[1] * (1 - water_res)
                                                    damage_copy.push[2] = -damage_copy.push[2] * (1 - water_res)
                                                end

                                                ATTACKERS_TABLE[1] = attacker

                                                EntityAux.add_damage(attacker, ATTACKERS_TABLE, damage_copy, "spell_forward", damage_copy.metadata)
                                            end
                                        end
                                    end
                                until true
                            end
                        end

                        state.damage_n = state_damage_n
                        state.damage_taken = damage_taken
                    until true
                end
            end
        until true
    end)

    if not status then
        k_log("[WaterLockFix] error in try_patch_waterlocking() :: " .. tostring(err))
    end

    kUtil.task_scheduler.add(try_patch_waterlocking, 1000)
end

local function init_mod(context)
    kUtil.add_on_tick_handler(on_tick_state_update)
    kUtil.task_scheduler.add(try_patch_waterlocking, 1000)
end

EventHandler.register_event("menu", "init", "WaterLockFix_init", init_mod)
