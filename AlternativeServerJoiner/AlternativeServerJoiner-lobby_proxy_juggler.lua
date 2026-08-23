local mt = {}

mt.__index = function(t, k)
    local juggler_method = LobbyProxyJuggler[k]
    if juggler_method then
        return juggler_method
    end

    local proxy = rawget(t, "_selected_proxy")
    if not proxy then
        return t[k]
    end

    local val = proxy[k]
    if type(val) == "function" then
        return function(_, ...)
            return val(proxy, ...)
        end
    end

    return val
end

mt.__newindex = function(t, k, v)
    if k == "_proxies" or k == "_selected_proxy" then
        rawset(t, k, v)
        return
    end

    local proxy = rawget(t, "_selected_proxy")

    if proxy then
        proxy[k] = v
    else
        k_log("[LobbyProxyJuggler] WARNING: trying to set '" .. tostring(k) .. "' with no active proxy.")
    end
end

LobbyProxyJuggler = class(LobbyProxyJuggler)

function LobbyProxyJuggler:init(server_address, count)
    k_log("[LobbyProxyJuggler] in new() with        server_address ::" .. tostring(server_address) .. "        count :: " .. tostring(count))
    local _proxies = {}

    for i = 1, count do
        k_log("[LobbyProxyJuggler] creating lobby #" .. tostring(i) .. " ...")
        local proxy = SteamLobbyProxy(NetworkHandler:join_server(server_address))

        if proxy then
            _proxies[#_proxies + 1] = proxy
        end
    end

    self._proxies = _proxies
    self._selected_proxy = self._proxies[1]

    self = setmetatable(self, mt)
end

function LobbyProxyJuggler:update()
    for i = 1, #self._proxies do
        self._proxies[i]:update()
    end
end

function LobbyProxyJuggler:joined_successfully()
    for i = 1, #self._proxies do
        local proxy = self._proxies[i]
        if proxy:joined_successfully() then
            self._selected_proxy = proxy

            return true
        end
    end

    return false
end

function LobbyProxyJuggler:is_failed()
    local all_failed = true
    local last_fail_reason = nil
    local healthy_proxy = nil

    for i = 1, #self._proxies do
        local proxy = self._proxies[i]
        local is_failed, fail_reason = proxy:is_failed()

        if is_failed then
            last_fail_reason = fail_reason
        else
            all_failed = false
            healthy_proxy = proxy
        end
    end

    if healthy_proxy then
        self._selected_proxy = healthy_proxy
    end

    if all_failed then
        return true, last_fail_reason
    end

    return false, nil
end

function LobbyProxyJuggler:leave_lobby()
    for i = 1, #self._proxies do
        local proxy = self._proxies[i]

        if not proxy.left then
            proxy:leave_lobby()
        end
    end
end
