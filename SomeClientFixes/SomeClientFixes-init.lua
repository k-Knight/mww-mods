-- Add require stuff here
local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

local processed_tables = {Boot, SE.event_handler}

local function wrap_object(obj, name_path)
    if type(obj) == "table" and type(obj.update) == "function" and not obj._unprotected_update then
        obj._unprotected_update = obj.update

        obj.update = function(self, ...)
            local results = { pcall(obj._unprotected_update, self, ...) }

            if not results[1] then
                k_log("[SomeClientFixes] update failed in '" .. name_path .. "' error :: " .. tostring(results[2]))
                return
            end

            return unpack(results, 2, #results)
        end

        k_log("[SomeClientFixes] successfully wrapped update() in a pcall for :: " .. name_path)
    end
end

function scan_and_wrap_updates()
    for k1, v1 in pairs(_G) do
        if type(v1) == "table" and k1 ~= "_G" and not processed_tables[v1] then
            processed_tables[v1] = true
            pcall(wrap_object, v1, tostring(k1))

            for k2, v2 in pairs(v1) do
                if type(v2) == "table" and not processed_tables[v2] then
                    pcall(wrap_object, v2, tostring(k1) .. "." .. tostring(k2))
                end
            end
        end
    end
end

local schedule_scan
schedule_scan = function()
    scan_and_wrap_updates()

    local next_delay = 1.0 + math.random()
    kUtil.task_scheduler.add(schedule_scan, next_delay)
end

local mod_inited = false

local function init_mod(context)
    if mod_inited then
        return
    end

    mod_inited = true

    k_log("[SomeClientFixes] starting initialization ...")

    local DuelState = table.make_bimap_inplace({
        "WAITING_TO_PRESENT_DUELERS",
        "PRESENTING_DUELERS",
        "IN_DUEL_COUNTDOWN",
        "DUEL_UNDER_WAY",
        "PRESENTING_DUEL_RESULT"
    })

    kUtil.loop_try_prehook_function(_G, "NetworkGameModeDuelClientGame", "on_unit_resurrected", function(self, peer_id, unit)
        if not self.timpani_world or (not self.last_end_round_event_id and self.duel_state ~= DuelState.DUEL_UNDER_WAY) then
            k_log("[SomeClientFixes] trying to prevent player duel ressurect crash ...")
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
            k_log("[SomeClientFixes] error in EntityAux.add_ability() :: " .. tostring(err))
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
            k_log("[SomeClientFixes] error in EntityAux.add_effect() :: " .. tostring(err))
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
                        k_log("[SomeClientFixes] error deleting unit (go_id : " .. tostring(go_id_to_remove) .. ") :: " .. tostring(err))
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

    kUtil.loop_try_prehook_function("ClientStatusSystemStatuses", "frozen", "on_start", function(unit, internal, status, network)
        local ext = EntityAux.extension(unit, "spellcast", true) or EntityAux.extension(unit, "spellcast_husk", true)

        if not ext then
            k_log("MISSING SPELLCAST EXTENSION for unit :: " .. tostring(unit))
        end

        local input = (ext and ext.input and ext.input.input) or (ext and ext.input) or nil

        if input then
            --input.cancel_spell[#(input.cancel_spell) + 1] = "LightningAoe"
            --input.cancel_spell[#(input.cancel_spell) + 1] = "Aoe"
            input.cancel_spell[#(input.cancel_spell) + 1] = "Shield"
        end
    end)

    local Profiler_start, Profiler_stop = Profiler.start, Profiler.stop
    local Resolution = _Resolution

    Boot.pre_update_fail_counter = 0
    k_log("[SomeClientFixes] overriding Boot.pre_update() ...")
    Boot.pre_update = function(self, dt)
        local success, error = xpcall(function ()
            Profiler_start("lua_pre_update")
            self.machine:pre_update(dt)
            Profiler_stop()
        end, debug.traceback)

        if not success then
            Boot.pre_update_fail_counter = Boot.pre_update_fail_counter + 1
            k_log(error)

            if Boot.pre_update_fail_counter > 9 then
                Application.quit()
            end
        else
            Boot.pre_update_fail_counter = 0
        end
    end

    Boot.update_fail_counter = 0
    k_log("[SomeClientFixes] overriding Boot.update() ...")
    Boot.update = function(self, dt)
        local success, error = xpcall(function ()
            self:pre_update(dt)
            Profiler_start("lua_update")
            Profiler_start("package_manager_update")
            self.package_manager:update(dt)
            Profiler_stop()
            self.machine:update(dt)

            if rawget(_G, "ui") then
                ui:update(dt)
            end

            if Resolution.is_inited then
                Resolution.update()
            end

            Profiler_stop()
        end, debug.traceback)

        if not success then
            Boot.update_fail_counter = Boot.update_fail_counter + 1
            k_log(error)

            if Boot.update_fail_counter > 9 then
                Application.quit()
            end
        else
            Boot.update_fail_counter = 0
        end
    end

    Boot.post_update_fail_counter = 0
    k_log("[SomeClientFixes] overriding Boot.post_update() ...")
    Boot.post_update = function(self, dt)
        local success, error = xpcall(function ()
            Profiler_start("lua_post_update")
            self.machine:post_update(dt)

            if rawget(_G, "ui") then
                ui:post_update(dt)
            end

            FrameTable.swap_tables()
            FrameTable.clear_tables()
            Profiler_stop()

            if self.quit_game and not rawget(_G, "EDITOR_LAUNCH") then
                Application.quit()
            end
        end, debug.traceback)

        if not success then
            Boot.post_update_fail_counter = Boot.post_update_fail_counter + 1
            k_log(error)

            if Boot.post_update_fail_counter > 9 then
                Application.quit()
            end
        else
            Boot.post_update_fail_counter = 0
        end
    end

    Boot.render_fail_counter = 0
    k_log("[SomeClientFixes] overriding Boot.render() ...")
    Boot.render = function(self)
        local success, error = xpcall(function ()
            self.machine:render()

            if rawget(_G, "ui") then
                ui:pre_render()
                ui:render()
            end
        end, debug.traceback)

        if not success then
            Boot.render_fail_counter = Boot.render_fail_counter + 1
            k_log(error)

            if Boot.render_fail_counter > 9 then
                Application.quit()
            end
        else
            Boot.render_fail_counter = 0
        end
    end

    local ffi = require("ffi")

    ffi.cdef[[
        void* GetCurrentProcess();
        int TerminateProcess(void* hProcess, unsigned int uExitCode);
    ]]

    Application.quit = function(...)
        ffi.C.TerminateProcess(ffi.C.GetCurrentProcess(), 0)
    end

    local ffi = require("ffi")

    ffi.cdef[[
        typedef struct _EXCEPTION_POINTERS EXCEPTION_POINTERS;

        typedef long (__stdcall *PVECTORED_EXCEPTION_HANDLER)(EXCEPTION_POINTERS* ExceptionInfo);

        void* AddVectoredExceptionHandler(unsigned long FirstHandler, PVECTORED_EXCEPTION_HANDLER VectoredHandler);
        void* GetCurrentProcess();
        int TerminateProcess(void* hProcess, unsigned int uExitCode);
    ]]

    local function exception_handler(exception_info)
        ffi.C.TerminateProcess(ffi.C.GetCurrentProcess(), 0)
        return 0
    end

    local keep_alive_handler = ffi.cast("PVECTORED_EXCEPTION_HANDLER", exception_handler)

    ffi.C.AddVectoredExceptionHandler(1, keep_alive_handler)

    schedule_scan()

    k_log("[SomeClientFixes] finished initialization ...")
end

EventHandler.register_event("menu", "init", "SomeClientFixes_init", init_mod)
