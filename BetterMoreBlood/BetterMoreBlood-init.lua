local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler
local BloodColors = {
    "red",
    "black"
}
local BloodVariants = {}
local BetterMoreBlood_settings = {
    enable_blood_spurts = true,
    enable_blood_splashes = true,
    max_emitters_per_player = 3,
    enable_large_splat = true,
    blood_damage_threshold = 325,
    valid_damage_types = {
        shield = false,
        fire = false,
        water = false,
        earth = true,
        life = false,
        lightning = false,
        magick = true,
        cold = false,
        arcane = true,
        steam = false,
        ice = true
    }
}
local UnitEmitters = {}
local UnitDamageTracker = {}

for _, color in ipairs(BloodColors) do
    BloodVariants[color] = {}

    for variant = 1, 4 do
        BloodVariants[color][variant] = "blood_" .. color .. variant - 1
    end
end

local ingame_players_initialized = false

local function on_ingame_players_initialized(...)
    ingame_players_initialized = true
end

local function get_particle_position(context)
    local player_id = context.player_id
    local player_unit = GET_UNIT_DATA(player_id).unit

    if not player_unit or not VALID_UNIT(player_unit) then
        return Vector3.zero()
    end

    local inventory_ext = EntityAux.extension(player_unit, "inventory")
    local particle_pos = VEC_TO_TABLE(UnitAux.world_position(player_unit, 0))

    if inventory_ext and inventory_ext.inventory then
        local robe_unit = inventory_ext.inventory.robe
        local hips_node = Unit.node(robe_unit, "Hips")

        particle_pos = VEC_TO_TABLE(Unit.world_position(robe_unit, hips_node))
    end

    return particle_pos
end

local function create_blood_splash(wanted_size, player_id)
    if not BetterMoreBlood_settings.enable_blood_splashes then
        return
    end

    local particle_pos = get_particle_position({
        player_id = player_id
    })

    particle_pos[3] = particle_pos[3] + math.random(0, 2) * 0.1

    UIFunc.create_particles_3d("hud_duelscore_red", 1, particle_pos, {
        0,
        0
    }, {
        wanted_size,
        wanted_size * 2
    }, {
        75,
        150,
        10,
        10
    }, {
        math.random(-200, 200) * 0.01,
        math.random(-200, 200) * 0.01,
        math.random(-5, 15)
    }, {
        0,
        0,
        -40
    }, 1, 2, {
        collide_with_ground = true,
        hide_blood_particle = true,
        spread_on_ground = true,
        blood_particle = true,
        player_id = player_id
    })
end

local function create_blood_spurt(wanted_size, player_id, velocity)
    if not BetterMoreBlood_settings.enable_blood_spurts then
        return
    end

    local particle_pos = get_particle_position({
        player_id = player_id
    })

    particle_pos[3] = particle_pos[3] + math.random(0, 2) * 0.1

    velocity[1] = velocity[1] + math.random(-100, 100) * 0.002
    velocity[2] = velocity[2] + math.random(-100, 100) * 0.002
    velocity[3] = velocity[3] + math.random(-100, 100) * 0.002

    UIFunc.create_particles_3d("hud_duelscore_red", 1, particle_pos, {
        0,
        0
    }, {
        wanted_size,
        wanted_size * 2
    }, {
        75,
        150,
        10,
        10
    }, velocity, {
        0,
        0,
        -40
    }, 1, 2, {
        collide_with_ground = true,
        hide_blood_particle = false,
        spread_on_ground = true,
        blood_particle = true,
        player_id = player_id
    })
end

local function create_blood_large_splat(wanted_size, player_id)
    if not BetterMoreBlood_settings.enable_large_splat then
        return
    end

    local particle_pos = get_particle_position({
        player_id = player_id
    })

    particle_pos[3] = particle_pos[3] + math.random(0, 2) * 0.1

    UIFunc.create_particles_3d("hud_duelscore_red", 1, particle_pos, {
        0,
        0
    }, {
        wanted_size,
        wanted_size * 3
    }, {
        50,
        150,
        10,
        10
    }, {
        math.random(-100, 100) * 0.01,
        math.random(-100, 100) * 0.01,
        math.random(-50, 50) * 0.01
    }, {
        0,
        0,
        -40
    }, 3, 1.5, {
        collide_with_ground = true,
        hide_blood_particle = true,
        player_id = player_id
    })
end

local function on_damage_received_anywhere(context)
    if not ingame_players_initialized then
        return
    end

    local data = context.data
    local self_id = data.self_id
    local damaged_unit = GET_UNIT_DATA(self_id).unit

    if damaged_unit then
        local internal_health = EntityAux.internal(damaged_unit, "health")
        local unit = internal_health.effect_unit or damaged_unit
        local blood_effect = internal_health.blood_effect

        if unit then
            local pos = UnitAux.world_position(unit, internal_health.bleed_joint)

            if not blood_effect then
                k_log("No blood effect for unit " .. tostring(unit))
                return
            end

            if not ingame_players_initialized then
                return
            end

            if BetterMoreBlood_settings.valid_damage_types[data.element] then
                CREATE_WORLD_PARTICLES(TO_VECTOR(pos), blood_effect)

                for i = 1, CLAMP_BETWEEN(1, 10, math.round(data.amount * 0.05)) do
                    kUtil.task_scheduler.add(function()
                        create_blood_splash(math.random(5, 12), self_id)
                    end, math.random(10, 500))
                end

                if (UnitEmitters[damaged_unit] or 0) <= BetterMoreBlood_settings.max_emitters_per_player then
                    UnitEmitters[damaged_unit] = (UnitEmitters[damaged_unit] or 0) + 1

                    kUtil.task_scheduler.add(function()
                        UnitEmitters[damaged_unit] = UnitEmitters[damaged_unit] - 1
                    end, 2000)

                    if data.amount > (BetterMoreBlood_settings.blood_damage_threshold / 2) then
                        if UnitEmitters[damaged_unit] <= 1 then
                            for i = 1, CLAMP_BETWEEN(1, 5, math.round(data.amount * 0.025)) do
                                kUtil.task_scheduler.add(function()
                                    create_blood_large_splat(math.random(100, 300), self_id)
                                end, math.random(10, 500))
                            end
                        end
                    end

                    if data.amount > BetterMoreBlood_settings.blood_damage_threshold then
                        for i = 1, CLAMP_BETWEEN(50, 100, math.round(data.amount * 0.1)) do
                            kUtil.task_scheduler.add(function()
                                if not ingame_players_initialized then
                                    return
                                end

                                local spurt_vel = {
                                    math.random(-300, 300) * 0.01,
                                    math.random(-300, 300) * 0.01,
                                    math.random(5, 9)
                                }

                                create_blood_spurt(math.random(5, 10), self_id, table.deep_clone(spurt_vel))
                            end, math.random(10, 2000))
                        end
                    end
                end
            end
        end
    end
end

local function on_any_unit_death(context)
    if not ingame_players_initialized then
        return
    end

    local data = context.data
    local killed_unit = data.killed_unit
    local owner_peer_id = data.killed_player_extension and data.killed_player_extension.owner_peer_id or nil

    if killed_unit then
        local health_internal = EntityAux.internal(killed_unit, "health")
        local effect_unit = health_internal.effect_unit
        local blood_effect = health_internal.blood_effect

        if effect_unit then
            local pos = UnitAux.world_position(effect_unit, health_internal.bleed_joint)

            if not blood_effect then
                k_log("No blood effect for unit " .. tostring(effect_unit))
                return
            end

            CREATE_WORLD_PARTICLES(TO_VECTOR(pos), blood_effect)
            create_blood_large_splat(math.random(150, 250), owner_peer_id)

            for i = 1, 5 do
                kUtil.task_scheduler.add(function()
                    if not ingame_players_initialized then
                        return
                    end

                    CREATE_WORLD_PARTICLES(TO_VECTOR(get_particle_position({
                        player_id = owner_peer_id
                    })), blood_effect)

                    create_blood_large_splat(math.random(150, 250), owner_peer_id)
                end, i * 900)
            end

            for i = 1, 10 do
                kUtil.task_scheduler.add(function()
                    if not ingame_players_initialized then
                        return
                    end

                    create_blood_splash(math.random(5, 10), owner_peer_id)
                    create_blood_splash(math.random(7, 12), owner_peer_id)
                end, math.random(100, 5000))
            end

            for i = 1, 5 do
                for j = 1, CLAMP_BETWEEN(100, 200, math.random(100, 200)) do
                    kUtil.task_scheduler.add(function()
                        if not ingame_players_initialized then
                            return
                        end

                        local spurt_vel = {
                            math.random(-300, 300) * 0.01,
                            math.random(-300, 300) * 0.01,
                            math.random(5, 9)
                        }

                        create_blood_spurt(math.random(5, 10), owner_peer_id, table.deep_clone(spurt_vel))
                    end, math.random(10, 4500))
                end
            end
        end
    end
end

local hooks_added = false

local function hook_damage_table(state, unit)
    if not state or type(state.damage) ~= "table" then
        return
    end

    local dmg_table = state.damage

    if dmg_table.__is_hooked then
        return
    end

    if not (unit and Unit.alive(unit)) then
        return
    end

    if not EntityAux.extension(unit, "player") then
        return
    end

    local peer_id = pdNetworkServerUnit.owning_peer(unit) or NetworkUnit.owner(unit)
    if not peer_id then
        return
    end

    local local_storage = {}

    for k, v in pairs(dmg_table) do
        local_storage[k] = v
        dmg_table[k] = nil
    end

    local mt = {
        __index = function(_, key)
            if key == "__is_hooked" then
                return true
            end

            return local_storage[key]
        end,
        __newindex = function(_, key, value)
            if value then
                local dmg_type = value[DamageDataIndex.DAMAGE_TYPE]
                local dmg_amount = value[DamageDataIndex.DAMAGE_AMOUNT]

                if dmg_type and dmg_amount and AllElementsMap[dmg_type] then
                    local dmg_accum = UnitDamageTracker[peer_id] or {}

                    dmg_accum[dmg_type] = (dmg_accum[dmg_type] or 0) + dmg_amount

                    UnitDamageTracker[peer_id] = dmg_accum
                end
            end

            local_storage[key] = value
        end
    }

    setmetatable(dmg_table, mt)
end

local function init(context)
    if not hooks_added then
        kUtil.loop_try_prehook_function(_G, "DamageSystem", "update_damage_receivers", function (self)
            local entities, entities_n = self:get_entities("damage_receiver")

            for i = 1, entities_n do
                repeat
                    local extension_data = entities[i]
                    local unit, extension = extension_data.unit, extension_data.extension
                    local state = extension.state
                    hook_damage_table(state, unit)
                until true
            end
        end)

        kUtil.loop_try_prehook_function(_G, "DamageSystem", "update_damage_receiver_husks", function (self)
            local entities, entities_n = self:get_entities("damage_receiver_husk")

            for i = 1, entities_n do
                repeat
                    local extension_data = entities[i]
                    local unit, extension = extension_data.unit, extension_data.extension
                    local state = extension.state
                    hook_damage_table(state, unit)
                until true
            end
        end)

        kUtil.loop_try_posthook_function(_G, "DamageSystem", "update", function (self)
            for peer_id, damages in pairs(UnitDamageTracker) do
                local text = "damage accumulated for [" .. tostring(peer_id) .. "] :: "
                local need_output = false
                local valid_damage_type = nil

                for dmg_type, dmg_amount in pairs(damages) do
                    if BetterMoreBlood_settings.valid_damage_types[dmg_type] and dmg_amount > 0 then
                        valid_damage_type = dmg_type
                        break
                    end
                end

                if valid_damage_type then
                    local dmg_cumulative = 0

                    for dmg_type, dmg_amount in pairs(damages) do
                        if dmg_amount > 0 then
                            text = text .. "\n    [" .. tostring(dmg_type) .. "] :: " .. tostring(dmg_amount)
                            need_output = true

                            if dmg_type ~= "life" then
                                dmg_cumulative = dmg_cumulative + dmg_amount
                            end

                        end

                        damages[dmg_type] = 0
                    end

                    local context = {
                        data = {
                            self_id = peer_id,
                            element = valid_damage_type,
                            amount = dmg_cumulative
                        }
                    }

                    on_damage_received_anywhere(context)
                end


                if need_output then
                    k_log(text)
                end
            end
        end)

        hooks_added = true
    end

    ingame_players_initialized = false
    BetterMoreBlood_settings = LOAD_GLOBAL_MOD_SETTINGS("BetterMoreBlood", BetterMoreBlood_settings)

    print("BetterMoreBlood_settings:")
    PRINT_TABLE(BetterMoreBlood_settings)
    SAVE_GLOBAL_MOD_SETTINGS("BetterMoreBlood", BetterMoreBlood_settings, false)
end

EventHandler.register_event("menu", "init", "BetterMoreBlood_init", init)
EventHandler.register_event("ingame", "players_initialized", "BetterMoreBlood_init", on_ingame_players_initialized)
EventHandler.register_event("unit_death", "any", "BetterMoreBlood_init", on_any_unit_death)
