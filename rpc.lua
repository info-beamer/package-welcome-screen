local function create(endpoints)
    endpoints = endpoints or {}
    local json = require "json"
    local clients = {}
    node.event("connect", function(client, prefix)
        if prefix == "rpc/python" then
            clients[client] = true
        end
    end)
    node.event("disconnect", function(client)
        clients[client] = nil
    end)
    node.event("input", function(line, client)
        if clients[client] then
            local call = json.decode(line)
            local fn = table.remove(call, 1)
            if endpoints[fn] then
                endpoints[fn](unpack(call))
            end
        end
    end)
    local function send_call(call, ...)
        local args = {...}
        table.insert(args, 1, call)
        local pkt = json.encode(args)
        local sent = false
        for client, _ in pairs(clients) do
            sent = true
            node.client_write(client, pkt) 
        end
        return sent
    end
    return setmetatable({
        register = function(name, fn)
            endpoints[name] = fn
        end,
    }, {
        __index = function(t, call)
            return function(...)
                return send_call(call, ...)
            end
        end
    })
end

return {
    create = create,
}
