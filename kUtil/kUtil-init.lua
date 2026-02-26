local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

local status, err = pcall(function()
    _G.kUtil = {}

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
        local max_exec = 1 -- (schedule_count > 5 and 3) or (schedule_count > 3 and 2) or 1
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

    kUtil.add_on_tick_handler = function (callback)
        local listeners = kUtil.on_update_listeners
        listeners[#listeners + 1] = callback
    end

    kUtil.add_on_render_handler = function (callback)
        local listeners = kUtil.on_render_listeners
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

        k_log("[kUtil] trying to append to _UIContext.render() ...")
    
        _UIContext._old_render = _UIContext.render
        _UIContext.render = function(self)
            kUtil.on_render()
            return _UIContext._old_render(self)
        end

        kUtil.runtime_init = true
    end
    
    EventHandler.register_event("menu", "init", "kUtil_init", init_mod)
end

