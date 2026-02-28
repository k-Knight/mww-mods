local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

_G.SBF_LOCAL = {}
_G.SBF_WET_CAST_UNITS = {}

local function try_find_client_spellcastingsystem()
    local status, err = pcall(function()
        repeat
            if NetworkGameModeTrainingGroundsClientGame and NetworkGameModeTrainingGroundsClientGame.init then
                if NetworkGameModeTrainingGroundsClientGame._old_init then
                    break
                end

                k_log("[SpellBufferFix] overridng NetworkGameModeTrainingGroundsClientGame.init() !!!")
                NetworkGameModeTrainingGroundsClientGame._old_init = NetworkGameModeTrainingGroundsClientGame.init

                NetworkGameModeTrainingGroundsClientGame.init = function(self, context)
                    NetworkGameModeClientGame.init(self, context)

                    self.training_gui = GameModeTrainingGroundsGui(context, self.gamemode_settings, self.pending_level_events_array)
                    context.hud_manager.game_mode_gui = self.training_gui

                    self:reset_gamemode_state()

                    self.hud_manager = context.hud_manager
                    self.hud_manager.enable_hud_portraits = true
                    self.hud_manager.enable_chat = true
                    self.hud_manager.enable_team_scores = false
                    self.hud_manager.enable_consumables = false
                    self.hud_manager.custom_minimap_frame = "hud_frame_minimap_training_ground"

                    self.hud_manager:rebuild_frames()

                    self.transaction_handler = context.transaction_handler
                end
            end
        until true

        repeat
            if ClientSpellCastingSystem and ClientSpellCastingSystem.update_spellcast_units then
                if ClientSpellCastingSystem._old_update_spellcast_units then
                    break
                end

                SBF_LOCAL.ClientSpells = {
                    Aoe = ClientSpells_Aoe,
                    Beam = ClientSpells_Beam,
                    Lightning = Spells_Lightning,
                    LightningAoe = Spells_LightningAoe,
                    Heal = Spells_Heal,
                    Magick = ClientSpells_Magick,
                    Projectile = ClientSpells_Projectile,
                    Spray = ClientSpells_Spray,
                    Shield = ClientSpells_Shield,
                    Weapon = ClientSpells_Weapon,
                    SelfShield = ClientSpells_SelfShield,
                    Mine = ClientSpells_Mine,
                    Barrier = ClientSpells_Barrier
                }

                SBF_LOCAL.ESF = SpellSettings.element_slowdown_factor

                SBF_LOCAL.TEMP_CANCEL_DAMAGE_INFO_TABLE = {}

                function SBF_LOCAL.get_spell_multiplier(unit, spell, spell_data, player_variable_manager)
                    local spell_element_mul = SpellSettings.spell_element_influence_multiplier[spell] or 1
                    local is_table = type(spell_element_mul) == "table"

                    if is_table or spell_element_mul ~= 0 then
                        local multiplier = 1
                        local affinity_multiplier = 1

                        if is_table then
                            for element, magnitude in pairs(spell_data.elements) do
                                if magnitude > 0 then
                                    affinity_multiplier = player_variable_manager:get_template_value(unit, element, spell:lower(), "movement_speed")

                                    local element_multiplier = spell_element_mul[element] or spell_element_mul.default

                                    if spell_data.elements.steam > 0 then
                                        element_multiplier = spell_element_mul.default
                                    end

                                    if type(element_multiplier) == "table" then
                                        multiplier = multiplier - element_multiplier[magnitude] * SBF_LOCAL.ESF * affinity_multiplier
                                    else
                                        multiplier = multiplier - element_multiplier * magnitude * SBF_LOCAL.ESF * affinity_multiplier
                                    end
                                end
                            end
                        else
                            multiplier = multiplier - spell_element_mul * spell_data.num_elements * SBF_LOCAL.ESF
                        end

                        return multiplier
                    end

                    return nil
                end

                function SBF_LOCAL.revert_element_speed_multiplier(u, spell, spell_data, player_variable_manager)
                    local multiplier = SBF_LOCAL.get_spell_multiplier(u, spell, spell_data, player_variable_manager)

                    if multiplier and spell_data.speed_multiplier_id then
                        EntityAux.revert_speed_multiplier(u, spell_data.speed_multiplier_id, "spellcast")
                    end
                end

                function SBF_LOCAL.add_element_speed_multiplier(u, spell, spell_data, player_variable_manager)
                    local multiplier = SBF_LOCAL.get_spell_multiplier(u, spell, spell_data, player_variable_manager)

                    if multiplier then
                        spell_data.speed_multiplier_id = EntityAux.add_speed_multiplier(u, multiplier, "spellcast")
                    end
                end

                function SBF_LOCAL._get_element_precedence(element_set, num_elements)
                    if element_set.shield > 0 then
                        return "shield"
                    elseif element_set.earth > 0 or element_set.ice > 0 then
                        return "solid"
                    elseif element_set.life > 0 or element_set.arcane > 0 then
                        return "channel"
                    end

                    return "other"
                end

                function SBF_LOCAL.on_cast_spell(unit, extension, spell_context)
                    local internal = extension.internal
                    local ws = internal._waiting_spell
                    local ws_name = ws.name

                    if ws_name then
                        local spells = internal.spells
                        local spells_data = internal.spells_data

                        spells[#spells + 1] = ws.name
                        spells_data[#spells_data + 1] = ws.data

                        local spell_table = SBF_LOCAL.ClientSpells[ws_name]

                        if spell_table.on_cast then
                            local spell_context = spell_context

                            spell_context.caster = unit
                            spell_context.internal = internal
                            spell_context.magick = nil
                            spell_context.element_queue = nil
                            spell_context.state = extension.state
                            spell_context.target = nil

                            spell_table.on_cast(ws.data, spell_context)
                        end

                        ws.name = nil
                        ws.data = nil
                    end
                end

                k_log("[SpellBufferFix] overriding ClientSpellCastingSystem.update_spellcast_units() !!!")
                ClientSpellCastingSystem._old_update_spellcast_units = ClientSpellCastingSystem.update_spellcast_units

                ClientSpellCastingSystem.update_spellcast_units = function(self, entities, entities_n, spell_update_context, dt)
                    local SpellTypes = SBF_LOCAL.ClientSpells

                    for n = 1, entities_n do
                        repeat
                            local extension_data = entities[n]
                            local unit, extension = extension_data.unit, extension_data.extension
                            local internal = extension.internal
                            local input = extension.input
                            local channeling = internal.channeling
                            local channel_dur = internal.channel_duration
                            local input_channel = input.channel
                            local state = extension.state
                            local inventory_extension = EntityAux.extension(unit, "inventory")

                            local spells = {}
                            local spells_data = {}

                            for _, spell_name in pairs(internal.spells) do
                                spells[#spells + 1] = spell_name
                            end
                            for _, spell_data in pairs(internal.spells_data) do
                                spells_data[#spells_data + 1] = spell_data
                            end

                            internal.spells = spells
                            internal.spells_data = spells_data

                            handle_spellcast_scale(internal, state)

                            if input.spellcast_scale_enabled then
                                state.spellcast_scale_enabled = state.spellcast_scale_enabled + input.spellcast_scale_enabled
                                input.spellcast_scale_enabled = nil
                            end

                            local scaled_dt = dt * state.spellcast_scale

                            if state.spellcast_scale_enabled < 0 then
                                scaled_dt = 0
                            elseif state.spellcast_scale_enabled > 0 then
                                local robe = inventory_extension.inventory.robe

                                Unit.set_timescale(robe, state.spellcast_scale)
                            end

                            if input_channel then
                                if channeling == false then
                                    channel_dur = 0
                                end

                                channeling = true

                                if math.floor(channel_dur) ~= math.floor(channel_dur + dt) then
                                    k_log("[SpellBufferFix] triggering spell_channel_tick !!")
                                    self.event_delegate:trigger3("spell_channel_tick", unit, internal.spells, channel_dur + dt)
                                end

                                channel_dur = channel_dur + dt
                            else
                                channeling = false
                            end

                            spell_update_context.scaled_dt = scaled_dt
                            spell_update_context.spell_channel = channeling
                            spell_update_context.caster = unit
                            spell_update_context.channel_duration = channel_dur
                            spell_update_context.explode_beam = input.explode_beam
                            spell_update_context.melee_chain = input.melee_chain or 0
                            spell_update_context.state = state
                            spell_update_context.target = EntityAux.state(unit, "character").cursor_intersect_unit
                            internal.channeling = channeling
                            internal.channel_duration = channel_dur

                            local ws = internal._waiting_spell
                            if ws then
                                local ws_name = ws.name
                                local ws_data = ws.data

                                if ws_name then
                                    local waiting_time = ws.waiting_time - scaled_dt

                                    ws.waiting_time = waiting_time

                                    if waiting_time < 0 then
                                        k_log("[SpellBufferFix] calling SBF_LOCAL.on_cast_spell !!")
                                        SBF_LOCAL.on_cast_spell(unit, extension, self.spell_context)
                                    else
                                        local spell_table = SBF_LOCAL.ClientSpells[ws_name]

                                        if spell_table.waiting_spell_update then
                                            local keep = spell_table.waiting_spell_update(ws_data, spell_update_context)

                                            if not keep then
                                                k_log("[SpellBufferFix] triggering player_spell_cast_cancel #1 for :: " .. tostring(ws_name))
                                                self.event_delegate:trigger2("player_spell_cast_cancel", unit, ws_name, self.spell_context.player_variable_manager)
                                                SBF_LOCAL.revert_element_speed_multiplier(unit, ws_name, ws_data)

                                                ws.name = nil
                                                ws.data = nil
                                            end
                                        end
                                    end
                                end
                            end

                            local j = 1

                            for i = 1, #spells do
                                local spell = spells[i]
                                local data = spells_data[i]
                                local current_spelltype = SpellTypes[spell]

                                if not current_spelltype then
                                    cat_printf_error("default", "[spellcasting] no spell_type named(%s)", spell)
                                else
                                    local val = current_spelltype.update(data, spell_update_context)

                                    if val then
                                        spells[j] = spell
                                        spells_data[j] = data
                                        j = j + 1
                                    else
                                        k_log("[SpellBufferFix] triggering player_spell_cast_cancel #2 for :: " .. tostring(spell))
                                        self.event_delegate:trigger2("player_spell_cast_cancel", unit, spell, self.spell_context.player_variable_manager)
                                        SBF_LOCAL.revert_element_speed_multiplier(unit, spell, data, self.spell_context.player_variable_manager)
                                    end
                                end
                            end

                            while spells[j] ~= nil do
                                spells[j] = nil
                                spells_data[j] = nil
                                j = j + 1
                            end

                            state.charge_time_normalized = input.charge_time_normalized
                            input.charge_time_normalized = nil
                            state.overcharge_time_normalized = input.overcharge_time_normalized
                            input.overcharge_time_normalized = nil

                            local dont_cast = false
                            if input.spell_type ~= "" then
                                if internal.sbf_timer and internal.sbf_timer > 0 then
                                    internal.sbf_timer = internal.sbf_timer - dt

                                    if internal.sbf_force_on_timer then
                                        dont_cast = true
                                    else
                                        local is_not_fwd = input.spell_type ~= "forward"
                                        local spells = internal.spells

                                        for k = 1, #spells do
                                            local spell = spells[k]
                                            local is_beam = spell == "Beam"
                                            local is_proj = spell == "Projectile"

                                            if is_not_fwd and (is_proj or is_beam) then
                                                dont_cast = true
                                                break
                                            elseif (not is_not_fwd) and is_beam then
                                                dont_cast = true
                                                break
                                            end
                                        end
                                    end
                                end
                            end

                            if dont_cast then
                                k_log("[SpellBufferFix] preventing spellcast :: " .. tostring(input.spell_type))
                                break
                            else
                                internal.sbf_timer = 0.1
                                internal.sbf_force_on_timer = nil
                            end

                            if not input.dirty_flag then
                                break
                            end

                            local cancelled_all_spell_heuristic = true
                            local cancel_all_spells_targets = {
                                ["Shield"] = true,
                                ["Beam"] = true,
                                ["Spray"] = true,
                                ["Projectile"] = true,
                                ["Lightning"] = true,
                                ["LightningAoe"] = true,
                                ["Weapon"] = true,
                                ["Aoe"] = true
                            }

                            for i = 1, #input.cancel_spell do
                                local spell_type = input.cancel_spell[i]
                                cancel_all_spells_targets[spell_type] = nil

                                self:cancel_spell(unit, spell_type, extension, spell_update_context)

                                input.cancel_spell[i] = nil
                            end

                            for k, v in pairs(cancel_all_spells_targets) do
                                if v then
                                    cancelled_all_spell_heuristic = false
                                    break
                                end
                            end

                            if cancelled_all_spell_heuristic then
                                k_log("[SpellBufferFix] cancel all heuristic triggered, clearing input ...")
                                local ws = internal._waiting_spell

                                if ws then
                                    ws.name = nil
                                    ws.data = nil
                                end

                                input.spell_type = ""
                                input.elements = nil

                                internal.sbf_timer = 0.15
                                internal.sbf_force_on_timer = true
                                break
                            end

                            if input.spell_type ~= "" then
                                internal.last_spell = input.spell_type

                                k_log("[SpellBufferFix] calling _handle_spellcast with :: " .. tostring(input.spell_type))
                                self:_handle_spellcast(unit, input, internal, state)

                                input.spell_type = ""
                                input.elements = nil
                            end

                            input.explode_beam = false

                            if input.abort_spellcasting then
                                k_log("[SpellBufferFix] abort_spellcasting !!")
                                self:cancel_all_spells(unit, extension)

                                input.abort_spellcasting = nil
                                input.despawn_beam = true
                                input.dirty_flag = true

                                if inventory_extension then
                                    local weapon = inventory_extension.inventory.weapon

                                    if weapon then
                                        local damage_info_extension = EntityAux.extension(weapon, "damage_info")

                                        if damage_info_extension then
                                            SBF_LOCAL.TEMP_CANCEL_DAMAGE_INFO_TABLE[1] = weapon

                                            EntityAux.set_input_by_extension(damage_info_extension, "cancel_damage", SBF_LOCAL.TEMP_CANCEL_DAMAGE_INFO_TABLE)
                                        end
                                    end
                                end
                            end

                            input.dirty_flag = false
                        until true
                    end
                end
            end
        until true

        repeat
            if not ClientSpellCastingSystem or ClientSpellCastingSystem._old__handle_spellcast then
                break
            end

            k_log("[SpellBufferFix] overriding ClientSpellCastingSystem._handle_spellcast() !!")
            ClientSpellCastingSystem._old__handle_spellcast = ClientSpellCastingSystem._handle_spellcast
            ClientSpellCastingSystem._handle_spellcast = function(self, unit, input, internal, state, target)
                local spell_context = self.spell_context

                if input.spell_type == "self" then
                    local new_spell_type
                    local status_state = EntityAux.extension(unit, "status").state
                    local statuses = status_state.status
                    local elements = input.elements
                    local num_elements = input.num_elements

                    if elements.fire > 0 and (statuses.chilled or statuses.wet) then
                        if elements.fire + elements.life == num_elements then
                            new_spell_type = "self"
                        end
                    elseif statuses.burning and (elements.water > 0 or elements.cold > 0) and (elements.water + elements.life == num_elements or elements.cold + elements.life == num_elements) then
                        new_spell_type = "self"
                    end

                    if not new_spell_type then
                        if elements.life > 0 and elements.lightning == 0 then
                            new_spell_type = "self"
                        elseif elements.shield > 0 then
                            if num_elements == 1 then
                                new_spell_type = "area"
                            else
                                new_spell_type = "self"
                            end
                        elseif num_elements > 0 then
                            new_spell_type = "area"
                        end
                    end

                    input.spell_type = new_spell_type
                end

                local spell_result = input.spell_type == "magick" and "magick" or SBF_LOCAL._get_element_precedence(input.elements, input.num_elements)

                if input.num_elements == 0 and input.spell_type ~= "weapon" and input.spell_type ~= "magick" then
                    cat_printf_blue("spellcast", "Tried to cast a spell with no elements.")

                    return
                end

                internal.channel_duration = 0
                spell_context.input = input
                spell_context.melee_chain = input.melee_chain or 0
                spell_context.result = spell_result
                spell_context.elements = input.elements
                spell_context.caster = unit
                spell_context.num_elements = input.num_elements
                spell_context.internal = internal
                spell_context.magick = input.magick
                spell_context.element_queue = input.element_queue
                spell_context.state = state
                spell_context.target = target or EntityAux.state(unit, "character").cursor_intersect_unit
                spell_context.magick_activate_position = input.magick_activate_position
                spell_context.random_seed = input.random_seed or math.floor(math.random() * 255)

                local spell_type = input.spell_type
                local magick = input.magick
                local element_queue = input.element_queue
                local num_elements = input.num_elements

                input.spell_type = nil
                input.magick = nil
                input.element_queue = nil
                input.num_elements = nil
                input.elements = nil

                local spell_name = SpellTypes[spell_type](spell_context)

                if not spell_name then
                    cat_printf_blue("spellcast", "Tried to cast a spell that had no result. This is likely due to frame-delay in reaction on element queue from input Num Elements: %d, Spell Type %s, Elements: %s", num_elements, spell_type, table.concat(element_queue, " "))

                    return
                end

                local SPELLS = SBF_LOCAL.ClientSpells

                assert(SPELLS[spell_name], "No such spell named %s", spell_name)

                local health_ext = EntityAux.extension(unit, "health")

                if self.is_gamemode_running and health_ext and health_ext.internal and health_ext.internal.invulnerable_time then
                    health_ext.internal.invulnerable_time = 0
                end

                for y = 1, #internal.spells_data do
                    local spells = internal.spells
                    local spell = spells[y]

                    if spell == "Spray" then
                        local spell_data = internal.spells_data[y]

                        spell_data.duration = 0
                    end
                end

                cat_printf_blue("freen", "[handle_spellcast] Client -> %s", spell_name)

                local spell_is_magick = spell_name == "Magick"

                if spell_is_magick then
                    local spells_data = internal.spells_data

                    for i = 1, #spells_data do
                        local spell_data = spells_data[i]

                        if spell_data.magick_type == magick then
                            local spells = internal.spells
                            local spell = spells[i]
                            local spell_update_context = self.spell_update_context

                            spell_update_context.dt = 0
                            spell_update_context.caster = unit
                            spell_update_context.target = nil

                            SPELLS[spell].on_cancel(spell_data, spell_update_context)
                            self.event_delegate:trigger2("player_spell_cast_cancel", unit, spell)
                            SBF_LOCAL.revert_element_speed_multiplier(unit, spell, spell_data, self.spell_context.player_variable_manager)

                            spells[i] = spells[#spells]
                            spells[#spells] = nil
                            spells_data[i] = spells_data[#spells_data]
                            spells_data[#spells_data] = nil

                            break
                        end
                    end
                elseif spell_context.elements.lightning > 0 and spell_name ~= "SelfShield" then
                    local status_state = EntityAux.state(unit, "status").status

                    if status_state.wet then
                        if pdNetworkServerUnit.owning_peer_is_self(unit) then
                            k_log("[SpellBufferFix] _handle_spellcast about to send_cast_spell WHEN WET !!!")
                            SBF_WET_CAST_UNITS[unit] = os.clock()
                            self.network_transport:send_cast_spell(unit, spell_type, magick, element_queue, nil, input.magick_activate_position, Vector3(0, 0, 0), spell_context.random_seed)
                        end

                        return
                    end
                end

                local spell_data, waiting_time = SPELLS[spell_name].init(spell_context, spell_type)
                local skip_waiting
                local waiting_time_type = type(waiting_time)

                if waiting_time_type == "boolean" then
                    skip_waiting = waiting_time
                    waiting_time = nil
                end

                if spell_data then
                    spell_data.element_queue = element_queue
                    spell_data.elements = spell_context.elements
                    spell_data.num_elements = num_elements

                    SBF_LOCAL.add_element_speed_multiplier(unit, spell_name, spell_data, self.spell_context.player_variable_manager)
                end

                local character_state = EntityAux.state(unit, "character")

                if pdNetworkServerUnit.owning_peer_is_self(unit) then
                    local target = character_state.cursor_intersect_unit
                    local unit_pos = Unit.local_position(unit, 0)
                    local activate_pos = Vector3(0, 0, 0)

                    if input.magick_activate_position then
                        activate_pos = Vector3Aux.unbox(input.magick_activate_position)
                    end

                    local dir = Vector3.normalize(activate_pos - unit_pos)
                    local length = 12

                    if spell_data.length_max then
                        length = spell_data.length_max + spell_data.length_min
                    end

                    local target_position = unit_pos + dir * length

                    k_log("[SpellBufferFix] _handle_spellcast about to send_cast_spell normally !!!")
                    self.network_transport:send_cast_spell(unit, spell_type, magick, element_queue, target, input.magick_activate_position, target_position, spell_context.random_seed)
                end

                if not skip_waiting then
                    if internal._waiting_spell.name then
                        k_log("[SpellBufferFix] _handle_spellcast about to spells on_cancel for :: " .. tostring(internal._waiting_spell.name))
                        SPELLS[internal._waiting_spell.name].on_cancel(internal._waiting_spell.data, spell_context)
                        SBF_LOCAL.revert_element_speed_multiplier(unit, internal._waiting_spell.name, internal._waiting_spell.data, self.spell_context.player_variable_manager)
                    end

                    internal._waiting_spell.name = spell_name
                    internal._waiting_spell.data = spell_data
                    internal._waiting_spell.waiting_time = waiting_time
                else
                    local spells = internal.spells
                    local spells_data = internal.spells_data
                    local spell_table = SPELLS[spell_name]

                    if spell_table.on_cast then
                        k_log("[SpellBufferFix] _handle_spellcast about to spells on_cast for :: " .. tostring(spell_name))
                        spell_table.on_cast(spell_data, spell_context)
                    end

                    spells[#spells + 1] = spell_name

                    assert(spell_data, "Error: Received no spell_data")

                    spells_data[#spells_data + 1] = spell_data

                    assert(#spells == #spells_data, "Error: wrong amounts of spell/spelldata.")
                end
            end
        until true

        repeat
            if not CharacterStateBase or CharacterStateBase._my_old_init then
                break
            end

            k_log("[SpellBufferFix] overriding CharacterStateBase.init() !!!")
            CharacterStateBase._my_old_init = CharacterStateBase.init
            CharacterStateBase.init = function(self, context)
                k_log("[SpellBufferFix] in CharacterStateBase.init() !!!")

                k_log("[SpellBufferFix] overriding CharacterStateBase.update() !!!")
                kUtil.task_scheduler.add(function()
                    if not self._my_old_update then
                        self._my_old_update = self.update
                        self.update = function(self, context)
                            local input_data = context.input_data
                            local unit = context.unit
                            local time = os.clock()
                            local zap_time = SBF_WET_CAST_UNITS[unit] or 0

                            if input_data and (time - zap_time) < 0.1 then
                                k_log("[SpellBufferFix] i should get zapped !!!")

                                input_data.wait_for_rmb_release = true
                                input_data.cast_spell = false
                                SBF_WET_CAST_UNITS[unit] = nil

                                if input_data.iq_data then
                                    input_data.iq_data.last_input = nil
                                    input_data.iq_data.last_time = nil
                                end
                            end

                            return self._my_old_update(self, context)
                        end
                    end
                end, 100)

                return CharacterStateBase._my_old_init(self, context)
            end
        until true

        repeat
            if not pdNetworkTransportArena or pdNetworkTransportArena._old_send_cast_spell then
                break
            end

            k_log("[SpellBufferFix] overriding dNetworkTransportArena:send_cast_spell() !!!")
            pdNetworkTransportArena._old_send_cast_spell = pdNetworkTransportArena.send_cast_spell
            pdNetworkTransportArena.send_cast_spell = function(self, unit, cast_type, magick, element_queue, target, magick_target_position, target_position, random_seed)
                k_log("delaying old pdNetworkTransportArena._old_send_cast_spell()")
                local _target_position = nil
                if target_position then
                    _target_position = Vector3Aux.box({}, target_position)
                end

                local _magick_target_position = nil
                if _magick_target_position then
                    _magick_target_position = {}
                    for k, v in pairs(magick_target_position) do
                        _magick_target_position[k] = v
                    end
                end

                local _element_queue = nil
                if element_queue then
                    _element_queue = {}
                    for k, v in pairs(element_queue) do
                        _element_queue[k] = v
                    end
                end

                kUtil.task_scheduler.add(function()
                    k_log("  executing old pdNetworkTransportArena._old_send_cast_spell() !!")
                    pdNetworkTransportArena._old_send_cast_spell(self, unit, cast_type, magick, _element_queue, target, _magick_target_position, _target_position and Vector3Aux.unbox(_target_position) or nil, random_seed)
                end, 10)
            end
        until true
    end)

    if not status then
        k_log("[SpellBufferFix] error in try_find_client_spellcastingsystem() :: " .. tostring(err))
    end

    kUtil.task_scheduler.add(try_find_client_spellcastingsystem, 1000)
end

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    kUtil.task_scheduler.add(try_find_client_spellcastingsystem, 1000)
end

EventHandler.register_event("menu", "init", "SpellBufferFix_init", init_mod)
