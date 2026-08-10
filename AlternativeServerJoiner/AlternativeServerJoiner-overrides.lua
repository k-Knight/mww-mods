local REFRESH_DELAY_NO_MATCHING_SERVERS = 20
local REFRESH_DELAY_FULL_SERVERS = 30
local PlayerAssembly = require_bs("scripts/game/network/network_player_assembly")

local function reverse_region_lookup(regions, value)
    for k, v in pairs(regions) do
        if v == value then
            return k
        end
    end
end

kUtil.loop_try_repalce_function(_G, "GameStateLogin", "update_loginserver_connection", function (self, dt)
    local login_server_joiner = self.login_server_joiner
    local login_server_finder = self.login_server_finder

    if self.refresh_timer then
        if self.refresh_timer == 0 then
            self.refresh_timer = nil

            self:setup_join_login_server()
        else
            self.refresh_timer = math.max(0, self.refresh_timer - dt)
        end
    end

    if login_server_joiner then
        login_server_joiner:update()

        if login_server_joiner:is_failed() then
            if self.login_server_joiner.last_error == "server_full" then
                self.current_server_full = true
            end

            login_server_joiner:destroy()

            self.login_server_joiner = nil
            self.account_state_context.login_server_joiner = nil
            self.account_state_context.login_server_joiner_valid = nil
            self.account_state_context.login_server_joiner_fail_reason = nil
            self.account_state_context.server_id = nil

            if PlayerAssembly.server_peer_id then
                PlayerAssembly.destroy()
            end
        elseif login_server_joiner:is_connected() then
            self.current_server_full = false

            if not PlayerAssembly.server_peer_id then
                PlayerAssembly.init(self.network_message_router, self.event_delegate, login_server_joiner.server_id)
            end
        end
    else
        local available_servers = self.available_servers
        local n_available_servers = available_servers and #available_servers or nil

        if available_servers and n_available_servers > 0 then
            local server_to_join = available_servers[n_available_servers]

            if not self.param_block.region and not self.param_block.region_disabled then
                local server_region = self:determine_closest_region(available_servers)

                self.param_block.region = reverse_region_lookup(self.param_block.regions, server_region)

                SetUserSetting("region", self.param_block.region)
                SaveUserSettings()
                self:setup_join_login_server()
            elseif server_to_join.content_version ~= NetworkGameVersion() and not PD_APPLICATION_PARAMETER["ignore-version-check"] then
                self.current_server_version_missmatch = true
            else
                self.current_server_version_missmatch = nil
                k_log("[AlternativeServerJoiner] overriding login server joiner with a direct one, context ::\n" .. k_log_table_helper(server_to_join, 1, "    "))
                self.login_server_joiner = LoginServerJoinerDirect(server_to_join.address, self.network_message_router)
                --self.login_server_joiner = LoginServerJoiner(server_to_join.id, self.network_message_router)
                self.param_block.login_server_joiner = self.login_server_joiner

                printf("[GameStateLogin] Connecting to login server [%s]", self.login_server_joiner.server_id)
            end

            available_servers[n_available_servers] = nil
        elseif n_available_servers == 0 then
            local delay_until_retry = 0

            if self.current_server_full then
                delay_until_retry = REFRESH_DELAY_FULL_SERVERS

                if not self.current_server_full_shown then
                    self.account_state_context.result = "timeout"
                    self.current_server_full_shown = true
                    self.error = "loginserver_error_server_full"
                end
            elseif self.current_server_version_missmatch then
                delay_until_retry = REFRESH_DELAY_NO_MATCHING_SERVERS

                if not self.current_server_version_missmatch_shown then
                    self.current_server_version_missmatch_shown = true
                    self.error = "loginserver_error_version_missmatch"
                end
            end

            self:setup_join_login_server(delay_until_retry)
        end
    end

    login_server_finder:update()
end)

local LOGIN_SERVER_TIMEOUT = 100
local HEARTBEAT_INTERVAL = 2

kUtil.loop_try_repalce_function(_G, "LoginServerHandler", "update", function (self)
    if self.fail_reason then
        return false
    end

    local current_time = Application.time_since_launch()

    if current_time - self.server_heartbeat_time > LOGIN_SERVER_TIMEOUT or Network.is_broken(self.server_id) then
        self.fail_reason = "timeout"

        printf("LoginServerHandler: Login server timeout (%s)", tostring(self.server_id))

        if Network.has_connection(self.server_id) then
            self.event_delegate:trigger("on_ls_disconnect", self.fail_reason)
            NetworkHandler:destroy_connection(self.server_id)
        end

        return false
    elseif current_time - self.my_heartbeat_time >= HEARTBEAT_INTERVAL then
        self:rpc("rpc_client_heartbeat")
        kUtil.task_scheduler.add(function ()
            self:rpc("rpc_client_heartbeat")
        end, 10)

        self.my_heartbeat_time = Application.time_since_launch()
    end

    return true
end)

kUtil.loop_try_prehook_function(_G, "XMPP", "connect", function (...)
    k_log("[AlternativeServerJoiner] requested XMPP connection, skipping to avoid lag :/")

    return true, nil
end)
