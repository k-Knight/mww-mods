local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

_G.IQ_UnitDict = {}

local function try_find_spell_wheel_system()
    repeat
        if not CharacterStateBase or CharacterStateBase._old_init then
            break
        end

        k_log("[InputQueue] overriding CharacterStateBase.init() !!!")
        CharacterStateBase._old_init = CharacterStateBase.init
        CharacterStateBase.init = function(self, context)
            k_log("[InputQueue] in CharacterStateBase.init() !!!")

            k_log("[InputQueue] overriding CharacterStateBase.handle_spellwheel_input() !!!")
            kUtil.task_scheduler.add(function()
                if not self._old_update then
                    self._old_update = self.update
                    self.update = function(self, context)
                        local input_data = context.input_data
                        local internal = context.internal
                        local input = nil
                        local os_time = os.clock()

                        if not input_data.wait_for_rmb_release and input_data.cast_spell and input_data.cast_spell > 0 and internal.previous_cursor ~= "magick" and internal.current_cursor ~= "magick" then
                            input = internal.current_cursor == "default" and "forward" or internal.current_cursor
                        elseif not input_data.wait_for_mbb_release and input_data.cast_self > 0 then
                            input = "self"
                        end

                        if not input_data.iq_data then
                            input_data.iq_data = {}
                        end

                        if input then
                            repeat
                                if input_data.iq_data.last_input == "forward" and input == "weapon" then
                                    break
                                end

                                k_log("[InputQueue] detected mistimed player input :: " .. tostring(input))
                                input_data.iq_data.last_input = input
                                input_data.iq_data.last_time = os_time
                            until true
                        end

                        return self._old_update(self, context)
                    end
                end
            end, 10)


            self.handle_spellwheel_input = function(self, unit, input_data, internal)
                local sw_ext = internal.spellwheel_ext

                if not input_data.wait_for_rmb_release and input_data.cast_spell and input_data.cast_spell > 0 and internal.previous_cursor ~= "magick" and internal.current_cursor ~= "magick" then
                    input_data.spell_cast = internal.current_cursor == "default" and "forward" or internal.current_cursor
                elseif not input_data.wait_for_mbb_release and input_data.cast_self > 0 then
                    input_data.spell_cast = "self"
                else
                    input_data.spell_cast = nil
                end

                if not input_data.spell_cast and input_data.iq_data then
                    local time = os.clock()
                    local last_input_time = input_data.iq_data.last_time or 0

                    if (time - last_input_time) < 0.15 then
                        input_data.spell_cast = input_data.iq_data.last_input
                        k_log("[InputQueue] carrying over input :: " .. tostring(input_data.spell_cast))
                    end
                end

                EntityAux.set_input_by_extension(sw_ext, "input_data", input_data)
            end

            return CharacterStateBase._old_init(self, context)
        end
    until true

    repeat
        if (not SpellWheelSystem) or SpellWheelSystem._old_update then
            break
        end

        SpellWheelSystem._old_update = SpellWheelSystem.update
        SpellWheelSystem.update = function(self, dt, context)
            local entities, entities_n = self:get_entities("spellwheel")
            local player_variable_manager = self.player_variable_manager
            local EntityAux_set_input = EntityAux.set_input
            local all_elements = AllElements
            local all_elements_n = #AllElements
            local network = self.network_transport

            for i = 1, entities_n do
                repeat
                    local extension_data = entities[i]
                    local u, extension = extension_data.unit, extension_data.extension
                    local internal = extension.internal
                    local input = extension.input
                    local input_data = input.input_data or input

                    input.input_data = nil

                    local element_queue = internal.element_queue
                    local last_elements = internal.last_elements
                    local cast_cooldown = internal.cast_cooldown

                    if cast_cooldown then
                        cast_cooldown = cast_cooldown - dt

                        if cast_cooldown < 0 then
                            cast_cooldown = nil
                        end

                        internal.cast_cooldown = cast_cooldown
                    end

                    if not input.dirty_flag then
                        element_queue:update(dt, extension.state)

                        for k, v in pairs(last_elements) do
                            last_elements[k] = nil
                        end

                        break
                    end

                    if input.enable then
                        internal.enabled = true
                        input.enable = nil
                    end

                    if input.disable then
                        internal.enabled = false
                        input.clear_spellwheel = true
                        input.disable = nil
                    end

                    if input.clear_spellwheel then
                        element_queue:clear()
                        network:transmit_to_server(u, "rpc_from_client_clear_element_queue")

                        input.clear_spellwheel = nil
                    end

                    input.dirty_flag = false

                    if not internal.enabled then
                        break
                    end

                    local state = extension.state
                    local new_elements = FrameTable.alloc_table()
                    local disabled_elements = state.disabled_elements
                    local go_id = NetworkUnit.game_object_id(u)

                    for j = 1, all_elements_n do
                        local elem = all_elements[j]

                        if input_data[elem] and (not disabled_elements or not disabled_elements[elem]) then
                            internal.element_queue:queue_element(elem)

                            new_elements[elem] = true

                            local element_id = NetworkLookup.elements[elem]

                            network:transmit_to_server(u, "rpc_from_client_queue_element", element_id)
                        end
                    end

                    for k, _ in pairs(last_elements) do
                        last_elements[k] = nil
                    end

                    for k, v in pairs(new_elements) do
                        last_elements[k] = v
                    end

                    local spell_cast = input_data.spell_cast
                    local spellcast_ext = EntityAux.extension(u, "spellcast")

                    if spell_cast and (not cast_cooldown or spell_cast == "weapon") and not spellcast_ext.internal._waiting_spell.name then
                        element_queue:process_element_combinations()

                        local selected_elements, num_elements = element_queue:get_elements()
                        local element_queue_raw = element_queue:get_element_queue()

                        element_queue:clear()
                        network:transmit_to_server(u, "rpc_from_client_clear_element_queue")

                        k_log("[InputQueue] player casting spell :: " .. tostring(spell_cast))

                        local spellcast_input = {
                            spell_type = spell_cast,
                            elements = selected_elements,
                            num_elements = num_elements,
                            element_queue = element_queue_raw
                        }

                        if input_data.iq_data then
                            k_log("[InputQueue] resetting player input :: " .. tostring(spell_cast))
                            input_data.iq_data[spell_cast] = 0
                        end

                        self.event_delegate:trigger2("player_spell_cast", spellcast_input)
                        EntityAux_set_input(u, "spellcast", spellcast_input)

                        input_data.spell_cast = nil
                        internal.cast_cooldown = SpellSettings.cast_cooldown * player_variable_manager:get_variable(u, "cast_cooldown")
                    end

                    element_queue:update(dt, extension.state)
                until true
            end

            entities, entities_n = self:get_entities("spellwheel_husk")

            for i = 1, entities_n do
                local extension_data = entities[i]
                local u, extension = extension_data.unit, extension_data.extension

                extension.internal.element_queue:update(dt, extension.state)
            end
        end
    until true

    kUtil.task_scheduler.add(try_find_spell_wheel_system, 1000)
end

local function init_mod(context)
    kUtil.task_scheduler.add(try_find_spell_wheel_system, 1000)
end


EventHandler.register_event("menu", "init", "InputQueue_init", init_mod)
