if not _G.GamepadInputManager then
    _G.GamepadInputManager = _G.class(GamepadInputManager)

    local ffi = require("ffi")
    ffi.cdef[[
        void initialize_gamepad();
        void shutdown_gamepad();
        bool get_button_state(const char* btn_name);
        float get_left_axis_x();
        float get_left_axis_y();
        float get_right_axis_x();
        float get_right_axis_y();
        float get_left_trigger_axis();
        float get_right_trigger_axis();
    ]]

    local gamepad_lib = ffi.load("sdl_gamepad_listener.dll")

    local BUTTON_NAMES = {
        "d_up", "d_down", "d_left", "d_right",
        "start", "back", "left_thumb", "right_thumb",
        "left_shoulder", "right_shoulder", "left_trigger", "right_trigger",
        "a", "b", "x", "y"
    }

    function GamepadInputManager:init()
        gamepad_lib.initialize_gamepad()

        self.input = {}
        self:clearState()
    end

    function GamepadInputManager:clearState()
        for _, btn in ipairs(BUTTON_NAMES) do
            self.input[btn] = false
        end

        self.input.left_x  = 0.0
        self.input.left_y  = 0.0
        self.input.right_x = 0.0
        self.input.right_y = 0.0

        self.input.left_trigger_axis  = 0.0
        self.input.right_trigger_axis = 0.0

        self.old_input = table.deep_clone(self.input)
    end

    function GamepadInputManager:update()
        self.old_input = table.deep_clone(self.input)

        for _, btn in ipairs(BUTTON_NAMES) do
            self.input[btn] = gamepad_lib.get_button_state(btn)
        end

        self.input.left_x  = gamepad_lib.get_left_axis_x()
        self.input.left_y  = gamepad_lib.get_left_axis_y()
        self.input.right_x = gamepad_lib.get_right_axis_x()
        self.input.right_y = gamepad_lib.get_right_axis_y()

        self.input.left_trigger_axis  = gamepad_lib.get_left_trigger_axis()
        self.input.right_trigger_axis = gamepad_lib.get_right_trigger_axis()
    end

    function GamepadInputManager:destroy()
        gamepad_lib.shutdown_gamepad()
    end
end
