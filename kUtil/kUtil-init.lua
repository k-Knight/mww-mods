local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

local status, err = pcall(function()
    _G.kUtil = {}

    local internal_hook_counter = 0

    _G.k_to_str = function(obj)
        local text = tostring(obj)

        local cur_time
        for _, world in pairs(Application.worlds()) do
            if world then
                local time = World.time(world)
                if time and time > 0 then
                    cur_time = time
                    break
                end
            end
        end

        if cur_time then
            return ("[" .. string.format("%.2f", cur_time * 1000.0) .. "]" .. text)
        else
            return text
        end
    end

    _G.k_log = function(sth)
        local text =  k_to_str(sth)
        print(text)
    end

    _G.kUtil.dbg_con_allocated = false

    _G.kUtil.alloc_dbg_console = function()
        if _G.kUtil.dbg_con_allocated then
            return
        end

        local ffi = require("ffi")

        ffi.cdef [[
            typedef void* HANDLE;
            typedef int BOOL;
            typedef unsigned long DWORD;
            typedef const char* LPCSTR;
            typedef void* LPVOID;
            typedef void* HWND;

            static const DWORD GENERIC_READ          = 0x80000000;
            static const DWORD GENERIC_WRITE         = 0x40000000;
            static const DWORD FILE_SHARE_READ       = 0x00000001;
            static const DWORD FILE_SHARE_WRITE      = 0x00000002;
            static const DWORD OPEN_EXISTING         = 3;
            static const DWORD FILE_ATTRIBUTE_NORMAL = 0x80;
            static const DWORD STD_OUTPUT_HANDLE     = -11;
            static const DWORD STD_ERROR_HANDLE      = -12;

            BOOL AllocConsole(void);
            HANDLE CreateFileA(const char* lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, void* lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
            BOOL SetStdHandle(DWORD nStdHandle, HANDLE hHandle);
            BOOL WriteConsoleA(HANDLE hConsoleOutput, const void* lpBuffer, DWORD nNumberOfCharsToWrite, DWORD* lpNumberOfCharsWritten, void* lpReserved);
            HWND GetConsoleWindow(void);
        ]]

        local has_console = ffi.C.GetConsoleWindow()
        if has_console ~= ffi.NULL then
            k_log("[kUtil] console is already allocated :: " .. tostring(has_console ~= ffi.NULL))
            return
        end

        ffi.C.AllocConsole()

        local hConOut = ffi.C.CreateFileA(
            "CONOUT$",
            ffi.C.GENERIC_READ + ffi.C.GENERIC_WRITE,
            ffi.C.FILE_SHARE_READ + ffi.C.FILE_SHARE_WRITE,
            nil,
            ffi.C.OPEN_EXISTING,
            ffi.C.FILE_ATTRIBUTE_NORMAL,
            nil
        )

        ffi.C.SetStdHandle(ffi.C.STD_OUTPUT_HANDLE, hConOut)
        ffi.C.SetStdHandle(ffi.C.STD_ERROR_HANDLE, hConOut)

        _G.k_log = function(sth)
            local text =  k_to_str(sth) .. "\n"
            local written = ffi.new("DWORD[1]")
            ffi.C.WriteConsoleA(hConOut, text, #text, written, nil)
        end

        _G.kUtil.dbg_con_allocated = true
        k_log("[kUtil] allocated debugging console")
    end

    _G.k_log_table_helper = function(table, depth, indent)
        local accum = ""

        if type(table) ~= "table" then
            accum = accum .. type(table) .. " is not a table type !!!\n"
            return accum
        end

        if not depth or type(depth) ~= "number" or depth < 0 then
            return accum
        end

        if not indent or type(indent) ~= "string" then
            indent = "    "
        end

        local depth_left = depth - 1
        local new_indent = indent .. "    "

        for k, v in pairs(table) do
            accum = accum .. indent .. tostring(k) .. " :: " .. type(v) .. " :: " .. tostring(v) .. "\n"
            if type(v) == "table" then
                accum = accum .. k_log_table_helper(v, depth_left, new_indent)
            end
        end

        return accum
    end

    _G.k_log_table = function(table, depth, indent)
        local res = k_log_table_helper(table, depth, indent)
        k_log(res)
    end

    kUtil.task_scheduler = {}
    kUtil.task_scheduler.schedule = {}

    kUtil.task_scheduler.get_time_after = function(delay)
        return os.clock() + (delay / 1000.0)
    end

    kUtil.task_scheduler.add = function(callback, delay)
        if type(callback) ~= "function" then
            return
        end

        local time = 0

        if delay then
            time = os.clock() + (delay / 1000.0)
        end

        local schedule = kUtil.task_scheduler.schedule
        local entry = {}
        entry.callback = callback
        entry.time = time
        schedule[#schedule + 1] = entry
    end

    kUtil.task_scheduler.add_at = function(callback, timestamp)
        if type(callback) ~= "function" then
            return
        end

        local schedule = kUtil.task_scheduler.schedule
        local entry = {}
        entry.callback = callback
        entry.time = timestamp
        schedule[#schedule + 1] = entry
    end

    kUtil.task_scheduler.try_run_next_task = function(callback)
        local schedule = kUtil.task_scheduler.schedule

        if #schedule < 1 then
            return
        end

        local schedule_count = #schedule
        local time = os.clock()
        local max_exec = 3 -- (schedule_count > 5 and 3) or (schedule_count > 3 and 2) or 1
        local exec_count = 0

        repeat
            local index = nil
            local callback = nil

            for i, v in pairs(schedule) do
                if v.time < time then
                    index = i
                    callback = v.callback
                    break
                end
            end

            if index then
                table.remove(schedule, index)
                local status, err = pcall(callback)

                if not status then
                    k_log("[kUtil] error running scheduled task :: " .. tostring(err))
                end
            else
                exec_count = max_exec
            end

            exec_count = exec_count + 1
        until exec_count >= max_exec
    end

    kUtil.on_update_listeners = {}
    kUtil.on_render_listeners = {}
    kUtil.on_gui_update_handlers = {}

    kUtil.add_on_tick_handler = function (callback)
        local listeners = kUtil.on_update_listeners
        listeners[#listeners + 1] = callback
    end

    kUtil.add_on_render_handler = function (callback)
        local listeners = kUtil.on_render_listeners
        listeners[#listeners + 1] = callback
    end

    kUtil.add_on_gui_update_handler = function (callback)
        local listeners = kUtil.on_gui_update_handlers
        listeners[#listeners + 1] = callback
    end

    kUtil.on_update = function(dt)
        kUtil.task_scheduler.try_run_next_task()

        for k, v in pairs(kUtil.on_update_listeners) do
            local status, err = pcall(v, dt)
            if not status then
                k_log("[kUtil] error running kUtil.on_update() :: " .. tostring(err))
            end
        end
    end

    kUtil.on_render = function()
        for k, v in pairs(kUtil.on_render_listeners) do
            local status, err = pcall(v)

            if not status then
                k_log("[kUtil] error running kUtil.on_render() :: " .. tostring(err))
            end
        end
    end

    kUtil.on_gui_update = function(self, dt)
        for k, v in pairs(kUtil.on_gui_update_handlers) do
            local status, err = pcall(v, self, dt)

            if not status then
                k_log("[kUtil] error running kUtil.on_gui_update() :: " .. tostring(err))
            end
        end
    end

    local function Keyboard_down(k)
        local btn_index = Keyboard and Keyboard.button_index(k) or nil
        return btn_index and Keyboard.button(btn_index) > 0 or false
    end

    kUtil.is_hotkey_pressed = function (kbd_hotkey)
        if kbd_hotkey then
            local status = true

            for _, key in ipairs(kbd_hotkey) do
                if key == "mouse_forward" then
                    status = status and Mouse_down("extra_2")
                elseif key == "mouse_backward" then
                    status = status and Mouse_down("extra_1")
                elseif key == "ctrl" or key == "shift" or key == "alt" then
                    local r_key = "right " .. key
                    local l_key = "left " .. key

                    status = status and (Keyboard_down(key) or Keyboard_down(r_key) or Keyboard_down(l_key))
                else
                    status = status and Keyboard_down(key)
                end
            end

            return status
        end

        return false
    end

    kUtil.loop_try_prehook_function = function(parent_table, table_name, func_name, callback)
        if not parent_table then
            k_log("[kUtil] error in loop_try_prehook_function() :: parent_table not a table or a table name")
        end

        local try_hook_func
        try_hook_func = function ()
            local hooked = false
            local actual_parent = parent_table

            if type(parent_table) == "string" then
                actual_parent = _G[parent_table]
            end

            if actual_parent and actual_parent[table_name] and actual_parent[table_name][func_name] then
                k_log("[kUtil] trying to prehook to " .. table_name .. "." .. func_name .. "() ...")
                internal_hook_counter = internal_hook_counter + 1
                local old_name = "_old_" .. func_name .. "_" .. tostring(internal_hook_counter)

                actual_parent[table_name][old_name] = actual_parent[table_name][func_name]
                actual_parent[table_name][func_name] = function (...)
                    local dont_run, ret = callback(...)

                    if dont_run then
                        return ret
                    else
                        return actual_parent[table_name][old_name](...)
                    end
                end

                hooked = true
            end

            if not hooked then
                kUtil.task_scheduler.add(try_hook_func, 1000)
            end
        end

        try_hook_func()
    end

    kUtil.loop_try_posthook_function = function(parent_table, table_name, func_name, callback)
        if not parent_table then
            k_log("[kUtil] error in loop_try_posthook_function() :: parent_table not a table or a table name")
        end

        local try_hook_func
        try_hook_func = function ()
            local hooked = false
            local actual_parent = parent_table

            if type(parent_table) == "string" then
                actual_parent = _G[parent_table]
            end

            if actual_parent and actual_parent[table_name] and actual_parent[table_name][func_name] then
                k_log("[kUtil] trying to posthook to " .. table_name .. "." .. func_name .. "() ...")
                internal_hook_counter = internal_hook_counter + 1
                local old_name = "_old_" .. func_name .. "_" .. tostring(internal_hook_counter)

                actual_parent[table_name][old_name] = actual_parent[table_name][func_name]
                actual_parent[table_name][func_name] = function (...)
                    local ret = {actual_parent[table_name][old_name](...)}
                    callback(..., ret)

                    return unpack(ret)
                end

                hooked = true
            end

            if not hooked then
                kUtil.task_scheduler.add(try_hook_func, 1000)
            end
        end

        try_hook_func()
    end

    kUtil.loop_try_repalce_function = function(parent_table, table_name, func_name, new_function)
        if not parent_table then
            k_log("[kUtil] error in loop_try_repalce_function() :: parent_table not a table or a table name")
        end

        local try_hook_func
        try_hook_func = function ()
            local hooked = false
            local actual_parent = parent_table

            if type(parent_table) == "string" then
                actual_parent = _G[parent_table]
            end

            if actual_parent and actual_parent[table_name] and actual_parent[table_name][func_name] then
                k_log("[kUtil] trying to overwrite to " .. table_name .. "." .. func_name .. "() ...")
                internal_hook_counter = internal_hook_counter + 1
                local old_name = "_old_" .. func_name .. "_" .. tostring(internal_hook_counter)

                actual_parent[table_name][old_name] = actual_parent[table_name][func_name]
                actual_parent[table_name][func_name] = new_function
                hooked = true
            end

            if not hooked then
                kUtil.task_scheduler.add(try_hook_func, 1000)
            end
        end

        try_hook_func()
    end

    kUtil.loop_try_replace_local_value = function(parent_table, table_name, func_name, local_name, replacement_val)
        if not parent_table then
            k_log("[kUtil] error in loop_try_replace_local_value() :: parent_table not a table or a table name")
        end

        if not debug or not debug.getupvalue or not debug.setupvalue then
            print("[kUtil] debug library or required upvalue functions are missing !!!")
            return false
        end

        local try_override_func
        try_override_func = function ()
            local actual_parent = parent_table

            if type(parent_table) == "string" then
                actual_parent = _G[parent_table]
            end

            if actual_parent and actual_parent[table_name] and actual_parent[table_name][func_name] then
                k_log("[kUtil] trying to change local value '" .. local_name .. "' in " .. table_name .. "." .. func_name .. "() ...")
                local host_function = actual_parent[table_name][func_name]

                if jit and type(jit.off) == "function" then
                    jit.off(host_function)
                end

                local index = 1
                while true do
                    local name, value = debug.getupvalue(host_function, index)

                    if not name then
                        break
                    end

                    if name == local_name then
                        print("[kUtil] indentified upvalue target local value '" .. local_name .. "', replacing ...")
                        debug.setupvalue(host_function, index, replacement_val)
                        return
                    end

                    index = index + 1
                end

                print("[kUtil] could not find local value '" .. local_name .. "' in " .. func_name .. "() !!!")
                return
            end

            kUtil.task_scheduler.add(try_override_func, 1000)
        end

        try_override_func()
    end

    local ffi = require("ffi")

    local decode_lut = ffi.new("int8_t[256]")
    for i = 0, 255 do decode_lut[i] = -1 end

    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for i = 1, #b do
        decode_lut[string.byte(b, i)] = i - 1
    end

    kUtil.b64_decode = function(data)
        local len = #data
        if len == 0 then return "" end

        local src = ffi.cast("const uint8_t*", data)

        local max_out_len = math.floor(len * 3 / 4)
        local dst = ffi.new("uint8_t[?]", max_out_len)

        local bit_buffer = 0
        local bit_count = 0
        local dst_idx = 0

        for i = 0, len - 1 do
            local char = src[i]

            if char == 61 then break end

            local val = decode_lut[char]
            if val ~= -1 then
                bit_buffer = bit.lshift(bit_buffer, 6) + val
                bit_count = bit_count + 6

                if bit_count >= 8 then
                    bit_count = bit_count - 8
                    dst[dst_idx] = bit.band(bit.rshift(bit_buffer, bit_count), 0xFF)
                    dst_idx = dst_idx + 1
                end
            end
        end

        return ffi.string(dst, dst_idx)
    end

    kUtil.file_exists = function(path, expected_data)
        local f = io.open(path, "rb")

        if f then 
            local current_data = f:read("*all")
            f:close()
        
            return current_data == expected_data
        end

        return false
    end

    kUtil.install_file = function(filename, binary_data)
        local f, err = io.open(filename, "wb")

        if not f then
            k_log("[Lua-ReShadeBridge] Failed to write file: " .. filename .. ". Error: " .. tostring(err))
            return false
        end

        f:write(binary_data)
        f:close()
        k_log("[Lua-ReShadeBridge] Successfully installed: " .. filename)

        return true
    end
end)

if not status then
    print("[kUtil] error initializing library :: " .. tostring(err))
else
    --k_log("[kUtil] calling util.alloc_dbg_console() ...")
    --kUtil.alloc_dbg_console()

    local mod_inited = false

    local function init_mod(context)
        if mod_inited then
            return
        end

        mod_inited = true

        if kUtil.runtime_init then
            return
        end

        k_log("[kUtil] trying to append to _UIContext.update() ...")

        _UIContext._old_update = _UIContext.update
        _UIContext.update = function(self, dt)
            kUtil.on_update(dt)
            return _UIContext._old_update(self, dt)
        end

        k_log("[kUtil] trying to replace to _UIContext.render() ...")
        _UIContext.render = function(self)
            self.ui_renderer:pre_render()
            self.ui_scene:render(self, self.ui_renderer)
            kUtil.on_render()
            Application.render_world(self._world, self._camera, self._viewport, self._shading_environment)
        end

        kUtil.loop_try_prehook_function(_G, "GuiManager", "update", function(self, dt)
            kUtil.on_gui_update(self, dt)
        end)

        kUtil.loop_try_posthook_function(_G, "EntityManager", "init", function(self, ...)
            kUtil.entity_manager = self
        end)

        kUtil.loop_try_posthook_function(_G, "NetworkUnitStorage", "init", function(self, ...)
            kUtil.unit_storage = self
        end)

        kUtil.loop_try_posthook_function(_G, "pdNetworkUnitSpawner", "init", function(self, ...)
            kUtil.unit_spawner = self
        end)

        kUtil.loop_try_posthook_function(_G, "pdWorldAux", "new_world", function(identifier_name, ...)
            if identifier_name == "CLIENT_GAME_WORLD" then
                local count = select('#', ...)
                local world = select(count, ...)
                kUtil.game_world = world[1]
            end
        end)

        kUtil.loop_try_prehook_function(_G, "GameStateInGame", "on_exit", function(self, ...)
            kUtil.entity_manager = nil
            kUtil.unit_storage = nil
            kUtil.unit_spawner = nil
            kUtil.game_world = nil
        end)


        local new_local_extension = function (u, extension_name, assert_on_non_existing)
            local unit_extensions = _G.G_Entities[u]
            local extension = unit_extensions and unit_extensions[extension_name]

            if not assert_on_non_existing then
                return extension
            end

            if not extension then
                local fail_text = sprintf("EntityAux.extension(%s, %s) failed!. No extension named(%s)!", tostring(u), extension_name, extension_name)
                k_log(fail_text)
            end

            return extension
        end

        kUtil.loop_try_repalce_function(_G, "EntityAux", "extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "state", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "internal", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "input", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "set_input", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "add_number_input", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "add_number_input_by_extension", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "append_input", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "append_input_by_extension", "local_extension", new_local_extension)
        kUtil.loop_try_replace_local_value(_G, "EntityAux", "set_table_input", "local_extension", new_local_extension)

        local orig_GET_STATE = GET_STATE
        local orig_HOOK_GAME_DATA = HOOK_GAME_DATA
        local orig_GET_GAME_DATA = GET_GAME_DATA
        local orig_SUBSCRIBE_TO_STATE = SUBSCRIBE_TO_STATE

        local function wrap_function_in_pcall(old_function, parent_table, function_name)
            parent_table[function_name] = function (...)
                local status, err = xpcall(old_function, debug.traceback, ...)
                if not status then
                    k_log("[kUtil] ERROR in " .. function_name .. "() :: " .. tostring(err))
                else
                    return err
                end
            end
        end

        wrap_function_in_pcall(orig_GET_STATE, _G, "GET_STATE")
        wrap_function_in_pcall(orig_HOOK_GAME_DATA, _G, "HOOK_GAME_DATA")
        wrap_function_in_pcall(orig_GET_GAME_DATA, _G, "GET_GAME_DATA")
        wrap_function_in_pcall(orig_SUBSCRIBE_TO_STATE, _G, "SUBSCRIBE_TO_STATE")

        local function propagate_state(state_type, state_func, delta_time)
            local dt = delta_time or 0

            _G.SUBSCRIBED_EVENTS[state_type] = _G.SUBSCRIBED_EVENTS[state_type] or {}
            _G.SUBSCRIBED_EVENTS[state_type][state_func] = _G.SUBSCRIBED_EVENTS[state_type][state_func] or {}

            local subsriber_count = 0

            for sub_index, sub_callback in pairs(_G.SUBSCRIBED_EVENTS[state_type][state_func]) do
                subsriber_count = subsriber_count + 1

                local status, err = xpcall(function ()
                    if _G.SUBSCRIBED_EVENTS[state_type][sub_index] then
                        sub_callback(_G.SUBSCRIBED_EVENTS[state_type][sub_index], {
                            dt = dt,
                            state_type = state_type,
                            state = _G.STATES[state_type],
                            data = _G.STATES[state_type],
                            self = _G.SUBSCRIBED_EVENTS[state_type][sub_index] or nil
                        })
                    else
                        sub_callback({
                            dt = dt,
                            state_type = state_type,
                            state = _G.STATES[state_type],
                            data = _G.STATES[state_type]
                        })
                    end
                end, debug.traceback)

                if not status then
                    k_log("[kUtil] error progagating state to the subscriber :: " .. tostring(err))
                end
            end
        end

        _G.SETUP_STATE = function (state, state_type, event_)
            local state_func = event_ or "init"

            if state then
                _G.STATES[state_type or "missing_state"] = state
            end

            propagate_state(state_type, state_func)
        end

        _G.REMOVE_STATE = function(state_type, dt)
            propagate_state(state_type, "exit", dt or 0)

            if state_type == "menu" then
                _G.STATES.menu = nil
            end
        end

        _G.UPDATE_STATE = function (state_type, dt, state)
            if state then
                _G.STATES[state_type or "missing_state"] = state
            end

            propagate_state(state_type, "update", dt)
        end

        SE.event_handler = {
            get_gamestate = GET_STATE,
            register_new_event = SETUP_STATE,
            remove_event = REMOVE_STATE,
            update_event = UPDATE_STATE,
            hook_variable = HOOK_GAME_DATA,
            get_variable = GET_GAME_DATA,
            register_event = SUBSCRIBE_TO_STATE
        }

        kUtil.runtime_init = true
    end

    local UIContext = require_bs("scripts/game/ui2/ui_context")
    init_mod()
end

