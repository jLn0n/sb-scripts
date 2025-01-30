local HttpService = game:GetService("HttpService")
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

local registered_ids: {[string]: boolean?} = {}

-- @CommuniceptionEvent
local CommuniceptionEvent = {}

type CommuniceptionEventServer = typeof(CommuniceptionEvent) & {
	id: string,
	mode: types.EventCommunicationMode,

	_internal: {
		listeners: {types.ServerListener<...any>},

		incoming_packets: {types.EventPacket},
		outcoming_packets: {types.EventPacket},
	}
}

function CommuniceptionEvent._init(self: CommuniceptionEventServer)
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
		table.insert(self._internal.incoming_packets, {
			targets = {sender},
			args = args
		})
	end)

	RunService.PostSimulation:Connect(function()
		for _ = 1, INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(self._internal.incoming_packets)
			if not incoming_packet then
				break
			end
			if not incoming_packet.targets then
				continue
			end

			for _, listener in self._internal.listeners do
				for _, target in incoming_packet.targets do
					task.defer(listener, target, unpack(incoming_packet.args))
				end
			end
		end

		for _ = 1, OUTCOMING_PACKET_THRESHOLD do
			local outcoming_packet = table.remove(self._internal.outcoming_packets)
			if not outcoming_packet then
				break
			end
			if not outcoming_packet.targets then
				continue
			end

			for _, target in outcoming_packet.targets do
				remote_obj:FireClient(target, outcoming_packet.args)
			end
		end
	end)
end

function CommuniceptionEvent.sendTo(self: CommuniceptionEventServer, target: Player, ...)
	table.insert(self._internal.outcoming_packets, {
		targets = {target},
		args = {...}
	})
end

function CommuniceptionEvent.sendToMultiple(self: CommuniceptionEventServer, targets: { Player }, ...)
	table.insert(self._internal.outcoming_packets, {
		targets = targets,
		args = {...}
	})
end

function CommuniceptionEvent.listen<T...>(self: CommuniceptionEventServer, listener: types.ServerListener<T...>): (() -> ())
	local hash_id = (#self._internal.listeners + 1)
	self._internal.listeners[hash_id] = listener

	return function()
		table.remove(self._internal.listeners, hash_id)
	end
end

function CommuniceptionEvent.listenOnce<T...>(self: CommuniceptionEventServer, listener: types.ServerListener<T...>): (() -> ())
	local disconnect_func
	local function listener_wrapper(...)
		listener(...)
		disconnect_func()
	end

	disconnect_func = CommuniceptionEvent.listen(self, listener_wrapper)
	return disconnect_func
end

function CommuniceptionEvent.wait(self: CommuniceptionEventServer): any
	local thread = coroutine.running()
	local disconnect_func

	local function listener_wrapper(...)
		disconnect_func()
		task.defer(thread, ...)
	end

	disconnect_func = CommuniceptionEvent.listen(self, listener_wrapper)
	return coroutine.yield()
end

function CommuniceptionEvent.disconnectAll(self: CommuniceptionEventServer)
	table.clear(self._internal.listeners)
end

local CommuniceptionFunction = {}

type CommuniceptionFunctionServer = typeof(CommuniceptionFunction) & {
	id: string,

	_internal: {
		callback: types.ServerCallback<...any>,

		listeners: {[string]: types.ServerListener<...any>},

		incoming_packets: {types.IncomingFunctionPacket},
		outcoming_packets: {types.OutcomingFunctionPacket},
	}
}

function CommuniceptionFunction._init(self: CommuniceptionFunctionServer)
	local on_incoming_remote = Instance.new("RemoteEvent")
	local on_outcoming_remote = Instance.new("RemoteEvent")

	on_incoming_remote.Name, on_outcoming_remote.Name = `{self.id}_incoming`, `{self.id}_outcoming`
	on_incoming_remote.Parent, on_outcoming_remote.Parent = REMOTE_CONTAINER, REMOTE_CONTAINER

	-- listens to data recieved from player
	on_incoming_remote.OnServerEvent:Connect(function(sender: Player, callback_id: string, args: {any})
		table.insert(self._internal.outcoming_packets, {
			callback_id = callback_id,
			target = sender,
			args = args
		})
	end)

	-- listens to data sent from player
	on_outcoming_remote.OnServerEvent:Connect(function(sender: Player, callback_id: string, args: {any})
		table.insert(self._internal.incoming_packets, {
			callback_id = callback_id,
			sender = sender,
			args = args
		})
	end)

	RunService.PostSimulation:Connect(function()
		for _ = 1, INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(self._internal.incoming_packets)
			if not incoming_packet then
				break
			end
			if not (incoming_packet.sender) then
				continue
			end

			local listener = self._internal.listeners[incoming_packet.callback_id]
			if not listener then
				continue
			end

			task.defer(function()
				local result = {listener(incoming_packet.sender, unpack(incoming_packet.args))}

				on_incoming_remote:FireClient(incoming_packet.sender, incoming_packet.callback_id, result)
			end)
		end

		for _ = 1, OUTCOMING_PACKET_THRESHOLD do
			local outcoming_packet = table.remove(self._internal.outcoming_packets)
			if not outcoming_packet then
				break
			end
			if not (outcoming_packet.target) then
				continue
			end

			on_outcoming_remote:FireClient(outcoming_packet.target, outcoming_packet.callback_id, outcoming_packet.args)
		end
	end)
end

function CommuniceptionFunction.invokeTo(self: CommuniceptionFunctionServer, target: Player, timeout: number, ...): (boolean, ...any)
	local thread = coroutine.running()
	local callback_recieved = false
	local callback_id = HttpService:GenerateGUID(false)

	self._internal.listeners[callback_id] = function(sender: Player, ...)
		if target.UserId ~= sender.UserId then
			-- the sender lied
			return
		end

		callback_recieved = true
		self._internal.listeners[callback_id] = nil
		task.spawn(thread, true, ...)
	end

	task.delay(timeout, function()
		if callback_recieved then
			-- callback is already recieved, cancel this automatic cancellation
			return
		end

		self._internal.listeners[callback_id] = nil
		task.spawn(thread, false)
	end)

	table.insert(self._internal.outcoming_packets, {
		callback_id = callback_id,
		target = target,
		args = {...}
	})
	return coroutine.yield()
end

function CommuniceptionFunction.setListener(self: CommuniceptionFunctionServer, callback: types.ServerCallback<...any>)
	self._internal.callback = callback
end

-- main
local module = {}

function module.newEvent(
	id: string,
	mode: types.EventCommunicationMode
): CommuniceptionEventServer
	if registered_ids[id] then
		return error(`[communiception]: remote[id={id}] is already registered`)
	end
	registered_ids[id] = true

	local self = setmetatable({}, {
		__index = CommuniceptionEvent
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

function module.newFunction(
	id: string
): CommuniceptionFunctionServer
	if registered_ids[id] then
		return error(`[communiception]: remote[id={id}] is already registered`)
	end
	registered_ids[id] = true

	local self = setmetatable({}, {
		__index = CommuniceptionFunction
	})
	
	self.id = id
	self._internal = {
		listeners = {},
		
		incoming_packets = {},
		outcoming_packets = {},
	}

	self._init(self :: any)

	return (self :: any)
end

return module
