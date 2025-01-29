local RunService = game:GetService("RunService")

local types = require("./types")

local INCOMING_PACKET_THRESHOLD = 30
local OUTCOMING_PACKET_THRESHOLD = 15

local REMOTE_CONTAINER_NAME = `communiception_{owner.UserId}`
local REMOTE_CONTAINER: Folder = (owner.PlayerGui:WaitForChild(REMOTE_CONTAINER_NAME, 10) :: any)

if not REMOTE_CONTAINER then
    error("[communiception]: could not fetch remote container")
end

local CommuniceptionClient = {}

type CommuniceptionClientObject = typeof(CommuniceptionClient) & {
	id: string,
	mode: types.CommunicationMode,

	_internal: {
		listeners: { types.ClientListener<...any> },

		incoming_packets: { types.ClientIncomingPacket },
		outcoming_packets: { types.ClientOutcomingPacket },
	}
}

function CommuniceptionClient._init(self: CommuniceptionClientObject)
	local remote_obj: RemoteEvent
	if self.mode == "reliable" then
		remote_obj = (REMOTE_CONTAINER:WaitForChild(`{self.id}_reliable`, 5) :: any)
	elseif self.mode == "unreliable" then
		remote_obj = (REMOTE_CONTAINER:WaitForChild(`{self.id}_unreliable`, 5) :: any)
	end

    if not remote_obj then
        error(`[communiception]: could not find remote[id={self.id}, mode={self.mode}], perhaps it is not registered`, 3)
    end

	remote_obj.OnClientEvent:Connect(function(args: {any})
		table.insert(self._internal.incoming_packets, args)
	end)

	RunService.PostSimulation:Connect(function()
		for _ = 1, INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(self._internal.incoming_packets)
			if not incoming_packet then
				break
			end

			for _, listener in ipairs(self._internal.listeners) do
				listener(unpack(incoming_packet))
			end
		end

		for _ = 1, OUTCOMING_PACKET_THRESHOLD do
			local outcoming_packet = table.remove(self._internal.outcoming_packets)
			if not outcoming_packet then
				break
			end

			remote_obj:FireServer(outcoming_packet.args)
		end
	end)
end

function CommuniceptionClient.send(self: CommuniceptionClientObject, ...)
	table.insert(self._internal.outcoming_packets, {
		args = {...}
	})
end

function CommuniceptionClient.listen<T...>(self: CommuniceptionClientObject, listener: types.ClientListener<T...>): (() -> ())
	local hash_id = #self._internal.listeners
	table.insert(self._internal.listeners, hash_id, listener)

	return function()
		table.remove(self._internal.listeners, hash_id)
	end
end

function CommuniceptionClient.listenOnce<T...>(self: CommuniceptionClientObject, listener: types.ClientListener<T...>): (() -> ())
	local disconnect_func
	local function listener_wrapper(...)
		listener(...)
		disconnect_func()
	end

	disconnect_func = CommuniceptionClient.listen(self, listener_wrapper)
	return disconnect_func
end

function CommuniceptionClient.wait(self: CommuniceptionClientObject): any
	local thread = coroutine.running()
	local disconnect_func

	local function listener_wrapper(...)
		disconnect_func()
		task.defer(thread, ...)
	end

	disconnect_func = CommuniceptionClient.listen(self, listener_wrapper)
	return coroutine.yield()
end

function CommuniceptionClient.disconnectAll(self: CommuniceptionClientObject)
	table.clear(self._internal.listeners)
end

local module = {}

function module.new(
	id: string,
	mode: types.CommunicationMode
): CommuniceptionClientObject
	local self = setmetatable({}, {
		__index = CommuniceptionClient
	})
	
	self.id = id
	self.mode = mode
	self._internal = {
		listeners = {},
		
		incoming_packets = {},
		outcoming_packets = {},
	}

	self._init(self :: any)

	return (self :: any)
end

return module
