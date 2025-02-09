local RunService = game:GetService("RunService")

local types = require("./types")
local common = require("./common")

local CONFIGURATION = common.CONFIGURATION

local current_remotes, _registry_changed = common.initializeInternalRemotes()

local registered_ids: {[string]: boolean?} = {}

local incoming_packets: {types.IncomingPacket} = {}
local outcoming_packets: {types.OutcomingPacket} = {}
local incoming_packet_listeners: {[string]: types.ClientListener<...any>} = {}

do
	local function onReliablePeerEvent(id: string, ...)
		table.insert(incoming_packets, {
			type = ("reliable" :: any), -- I HATE YOU
			id = id,
			args = {...},
		})
	end

	local function onUnreliablePeerEvent(id: string, ...)
		table.insert(incoming_packets, {
			type = ("unreliable" :: any), -- I HATE YOU
			id = id,
			args = {...},
		})
	end

	local function onRemoteRegistryChanged()
		current_remotes.reliable.OnClientEvent:Connect(onReliablePeerEvent)
		current_remotes.unreliable.OnClientEvent:Connect(onUnreliablePeerEvent)
	end

	RunService.PostSimulation:Connect(function()
		for _ = 1, CONFIGURATION.INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(incoming_packets)
			if not incoming_packet then
				-- no incoming packets to be processed, break the loop
				break
			end

			local listener = incoming_packet_listeners[incoming_packet.id]
			if not listener then
				-- the listener for id doesn't exist as of the invocation from the internal listener
				continue
			end

			task.spawn(listener, unpack(incoming_packet.args))
		end

		for _ = 1, CONFIGURATION.OUTCOMING_PACKET_THRESHOLD do
			local outcoming_packet = table.remove(outcoming_packets)
			if not outcoming_packet then
				-- no outcoming packets to be processed, break the loop
				break
			end

			current_remotes[outcoming_packet.type]:FireServer(outcoming_packet.id, unpack(outcoming_packet.args))
		end
	end)

	onRemoteRegistryChanged()
    _registry_changed.Event:Connect(onRemoteRegistryChanged)
end

-- @CommuniceptionEvent
local CommuniceptionEvent = {}

type CommuniceptionEventClient = typeof(CommuniceptionEvent) & {
	id: string,
	mode: types.EventCommunicationMode,

	_internal: {
		listeners: {types.ClientListener<...any>},
	},
}

function CommuniceptionEvent._init(self: CommuniceptionEventClient)
	incoming_packet_listeners[self.id] = function(...)
		for _, listener in self._internal.listeners do
			task.spawn(listener, ...)
		end
	end
end

function CommuniceptionEvent.send(self: CommuniceptionEventClient, ...)
	table.insert(outcoming_packets, {
		type = (self.mode :: any),
		id = self.id,
		args = {...},
	})
end

function CommuniceptionEvent.listen<T...>(self: CommuniceptionEventClient, listener: types.ClientListener<T...>): (() -> ())
	local listener_id = common.getEmptyIndex(self._internal.listeners)
	self._internal.listeners[listener_id] = listener

	return function()
		self._internal.listeners[listener_id] = nil
	end
end

function CommuniceptionEvent.listenOnce<T...>(self: CommuniceptionEventClient, listener: types.ClientListener<T...>): (() -> ())
	local disconnect_func
	local function listener_wrapper(...)
		listener(...)
		disconnect_func()
	end

	disconnect_func = CommuniceptionEvent.listen(self, listener_wrapper)
	return disconnect_func
end

function CommuniceptionEvent.wait(self: CommuniceptionEventClient): any
	local thread = coroutine.running()
	local disconnect_func

	local function listener_wrapper(...)
		disconnect_func()
		task.spawn(thread, ...)
	end

	disconnect_func = CommuniceptionEvent.listen(self, listener_wrapper)
	return coroutine.yield()
end

function CommuniceptionEvent.disconnectAll(self: CommuniceptionEventClient)
	table.clear(self._internal.listeners)
end

-- @CommuniceptionFunction
local CommuniceptionFunction = {}

type CommuniceptionFunctionClient = typeof(CommuniceptionFunction) & {
	id: string,

	_internal: {
		callback: types.ClientCallback<...any>,
		listeners: {types.ClientListener<...any>},
	},
}

function CommuniceptionFunction._init(self: CommuniceptionFunctionClient)
	-- listens to data recieved from server (callback response)
	incoming_packet_listeners[`incoming_{self.id}`] = function(callback_id: number, ...)
		local listener = self._internal.listeners[callback_id]
		if not listener then
			return
		end

		listener(...)
	end

	-- listens to data sent from server (callback request)
	incoming_packet_listeners[`outcoming_{self.id}`] = function(callback_id: number, ...)
		local current_callback = self._internal.callback
		if not current_callback then
			return
		end

		task.spawn(function(...)
			table.insert(outcoming_packets, {
				type = ("reliable" :: any),
				id = `incoming_{self.id}`,
				args = {callback_id, current_callback(...)},
			})
		end, ...)
	end
end

function CommuniceptionFunction.invoke(self: CommuniceptionFunctionClient, timeout: number, ...): (boolean, ...any)
	local thread = coroutine.running()
	local callback_recieved = false
	local callback_id = common.getEmptyIndex(self._internal.listeners)

	self._internal.listeners[callback_id] = function(...)
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

	table.insert(outcoming_packets, {
		type = ("reliable" :: any),
		id = `outcoming_{self.id}`,
		args = {callback_id, ...},
	})
	return coroutine.yield()
end

function CommuniceptionFunction.setListener(self: CommuniceptionFunctionClient, callback: types.ClientCallback<...any>)
	self._internal.callback = callback
end

-- main
local module = {}

function module.newEvent(
	id: string,
	mode: types.EventCommunicationMode
): CommuniceptionEventClient
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
	}

	self._init(self :: any)

	return (self :: any)
end

function module.newFunction(
	id: string
): CommuniceptionFunctionClient
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
	}

	self._init(self :: any)

	return (self :: any)
end

return module
