local RunService = game:GetService("RunService")

local types = require("./types")

local INCOMING_PACKET_THRESHOLD = 30
local OUTCOMING_PACKET_THRESHOLD = 15

local REMOTE_CONTAINER_NAME = `communiception_{owner.UserId}`
local REMOTE_CONTAINER: Folder = (owner.PlayerGui:FindFirstChild(REMOTE_CONTAINER_NAME) :: any)

if REMOTE_CONTAINER then
	REMOTE_CONTAINER:ClearAllChildren()
else
	local new_container = Instance.new("Folder")
	new_container.Name = REMOTE_CONTAINER_NAME
	new_container.Parent = owner.PlayerGui
	REMOTE_CONTAINER = new_container
end

local CommuniceptionServer = {}

type CommuniceptionServerObject = typeof(CommuniceptionServer) & {
	id: string,
	mode: types.CommunicationMode,

	_internal: {
		listeners: { types.ServerListener<...any> },

		incoming_packets: { types.ServerIncomingPacket },
		outcoming_packets: { types.ServerOutcomingPacket },
	}
}

function CommuniceptionServer._init(self: CommuniceptionServerObject)
	local remote_obj: RemoteEvent
	if self.mode == "reliable" then
		remote_obj = Instance.new("RemoteEvent")
		remote_obj.Name = `{self.id}_reliable`
	elseif self.mode == "unreliable" then
		remote_obj = (Instance.new("UnreliableRemoteEvent") :: any) :: RemoteEvent
		remote_obj.Name = `{self.id}_unreliable`
	end

	remote_obj.Parent = REMOTE_CONTAINER
	remote_obj.OnServerEvent:Connect(function(sender: Player, args: {any})
		table.insert(self._internal.incoming_packets, {sender, unpack(args)})
	end)

	RunService.PostSimulation:Connect(function()
		for _ = 1, INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(self._internal.incoming_packets)
			if not incoming_packet then
				break
			end

			for _, listener in self._internal.listeners do
				listener(unpack(incoming_packet))
			end
		end

		for _ = 1, OUTCOMING_PACKET_THRESHOLD do
			local outcoming_packet = table.remove(self._internal.outcoming_packets)
			if not outcoming_packet then
				break
			end

			for _, target in outcoming_packet.targets do
				remote_obj:FireClient(target, outcoming_packet.args)
			end
		end
	end)
end

function CommuniceptionServer.sendTo(self: CommuniceptionServerObject, target: Player, ...)
	table.insert(self._internal.outcoming_packets, {
		targets = {target},
		args = {...}
	})
end

function CommuniceptionServer.sendToMultiple(self: CommuniceptionServerObject, targets: { Player }, ...)
	table.insert(self._internal.outcoming_packets, {
		targets = targets,
		args = {...}
	})
end

function CommuniceptionServer.listen<T...>(self: CommuniceptionServerObject, listener: types.ServerListener<T...>): (() -> ())
	local hash_id = #self._internal.listeners
	table.insert(self._internal.listeners, hash_id, listener)

	return function()
		table.remove(self._internal.listeners, hash_id)
	end
end

function CommuniceptionServer.listenOnce<T...>(self: CommuniceptionServerObject, listener: types.ServerListener<T...>): (() -> ())
	local disconnect_func
	local function listener_wrapper(...)
		listener(...)
		disconnect_func()
	end

	disconnect_func = CommuniceptionServer.listen(self, listener_wrapper)
	return disconnect_func
end

function CommuniceptionServer.wait(self: CommuniceptionServerObject): any
	local thread = coroutine.running()
	local disconnect_func

	local function listener_wrapper(...)
		disconnect_func()
		task.defer(thread, ...)
	end

	disconnect_func = CommuniceptionServer.listen(self, listener_wrapper)
	return coroutine.yield()
end

function CommuniceptionServer.disconnectAll(self: CommuniceptionServerObject)
	table.clear(self._internal.listeners)
end

local module = {}

function module.new(
	id: string,
	mode: types.CommunicationMode
): CommuniceptionServerObject
	local self = setmetatable({}, {
		__index = CommuniceptionServer
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
