-- provided by mr RaT

require("scripts/game/network/network_lookup")

LoginServerJoinerDirect = class(LoginServerJoinerDirect)

local LOGIN_SERVER_REQUEST_TIMEOUT = 60
local LOGIN_SERVER_TIMEOUT = 100
local HEARTBEAT_INTERVAL = 1

local lobby_fail_reason_to_last_error = {
	timeout = "timeout",
	server_is_full = "server_full"
}

function LoginServerJoinerDirect:init(server_address, network_message_router)
	self.ALIAS = "LoginServerJoinerDirect"
	self.server_type = "Login server"
	self.network_message_router = network_message_router
	self.server_address = server_address
	self.my_guid = Application.guid()
	self.current_state = "joining_lobby"

	network_message_router:register(self.ALIAS, self, "rpc_login_server_join_request_response", "rpc_login_server_heartbeat")

	k_log(string.format("[LoginServerJoinerDirect] joining %s at %q", self.server_type, tostring(server_address)))

	self.lobby_proxy = SteamLobbyProxy(NetworkHandler:join_server(server_address))
end

function LoginServerJoinerDirect:destroy()
	self.network_message_router:unregister(self.ALIAS)
end

function LoginServerJoinerDirect:abort()
	local lobby_proxy = self.lobby_proxy

	if lobby_proxy and not lobby_proxy.left then
		lobby_proxy:leave_lobby()
	end
end

function LoginServerJoinerDirect:fail(last_error)
	self.last_error = last_error

	self:abort()

	self.current_state = "error"
end

function LoginServerJoinerDirect:update_joining_lobby()
	local lobby_proxy = self.lobby_proxy

	lobby_proxy:update()

	local is_failed, fail_reason = lobby_proxy:is_failed()

	if lobby_proxy:joined_successfully() then
		self.server_id = lobby_proxy.lobby_host

		k_log(string.format("[LoginServerJoinerDirect] joined %s lobby with host [%s]. sending join request", self.server_type, tostring(self.server_id)))

		self.time_at_hello = Application.time_since_launch()
		self.time_at_last_hello = Application.time_since_launch()
		self.current_state = "waiting_for_response"

		RPC.rpc_from_client_login_server_join_request(self.server_id, self.my_guid)
	elseif is_failed then
		k_log(string.format("[LoginServerJoinerDirect] failed to join %s lobby. fail_reason [%s]", self.server_type, tostring(fail_reason)))

		self:fail(lobby_fail_reason_to_last_error[fail_reason] or "internal_error")
	end
end

function LoginServerJoinerDirect:update_waiting_for_response()
	local lobby_proxy = self.lobby_proxy

	lobby_proxy:update()

	local is_failed = lobby_proxy:is_failed()
	local time_since_hello = Application.time_since_launch() - self.time_at_hello

	if is_failed or time_since_hello > LOGIN_SERVER_REQUEST_TIMEOUT then
		k_log(string.format("[LoginServerJoinerDirect] request timeout to login-server: %s", tostring(self.server_id)))
		self:fail(is_failed and "disconnected" or "timeout")

		return
	end

	local time_since_last_hello = Application.time_since_launch() - self.time_at_last_hello

	if time_since_last_hello > 2 then
		k_log(string.format("[LoginServerJoinerDirect] sending join request to login-server: %s", tostring(self.server_id)))

		self.time_at_last_hello = Application.time_since_launch()

		RPC.rpc_from_client_login_server_join_request(self.server_id, self.my_guid)
	end
end

function LoginServerJoinerDirect:update_connected()
	local lobby_proxy = self.lobby_proxy

	lobby_proxy:update()

	local is_failed = lobby_proxy:is_failed()
	local current_time = Application.time_since_launch()

	if current_time - self.time_since_last_heartbeat > HEARTBEAT_INTERVAL then
		self.time_since_last_heartbeat = current_time

		RPC.rpc_client_heartbeat(self.server_id, self.my_guid)
	end

	if is_failed or current_time - self.time_at_server_heartbeat > LOGIN_SERVER_TIMEOUT then
		k_log("[LoginServerJoinerDirect] login server heartbeat timeout!")
		self:fail(is_failed and "disconnected" or "timeout")
	end
end

function LoginServerJoinerDirect:update()
	local current_state = self.current_state

	if current_state == "joining_lobby" then
		self:update_joining_lobby()
	elseif current_state == "waiting_for_response" then
		self:update_waiting_for_response()
	elseif current_state == "connected" then
		self:update_connected()
	end
end

function LoginServerJoinerDirect:rpc_login_server_heartbeat(sender)
	if sender == self.server_id then
		self.time_at_server_heartbeat = Application.time_since_launch()
	end
end

function LoginServerJoinerDirect:rpc_login_server_join_request_response(sender, guid, response_code)
	k_log("[LoginServerJoinerDirect] in rpc_login_server_join_request_response()")

	if self.current_state ~= "waiting_for_response" then
		return
	end

	if sender ~= self.server_id then
		k_log(string.format("[LoginServerJoinerDirect] Login server response with bad sender! Wanting to join %s, got response from %s", tostring(self.server_id), tostring(sender)))
	elseif guid ~= self.my_guid then
		k_log(string.format("[LoginServerJoinerDirect] Login server response with bad guid! My guid: %s theirs: %s", tostring(self.my_guid), tostring(guid)))
	elseif response_code == ConnectionResponseType.accepted then
		self.current_state = "connected"
		self.time_since_last_heartbeat = Application.time_since_launch()
		self.time_at_server_heartbeat = Application.time_since_launch()
	elseif response_code == ConnectionResponseType.rejected_server_full then
		k_log("[LoginServerJoinerDirect] Connection rejected: Server full")
		self:fail("server_full")
	else
		k_log("[LoginServerJoinerDirect] connection failed: internal error")
		self:fail("internal_error")
	end
end

function LoginServerJoinerDirect:get_current_state()
	return self.current_state
end

function LoginServerJoinerDirect:is_failed()
	return self.current_state == "error"
end

function LoginServerJoinerDirect:is_connected()
	return self.current_state == "connected"
end

function LoginServerJoinerDirect:disconnect()
	if self.current_state ~= "error" then
		RPC.rpc_leaving_server(self.server_id, self.my_guid)

		self.current_state = "disconnected"
	end

	self:abort()
end
