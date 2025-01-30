local RunService = game:GetService("RunService")

local types = require("./types")

local INCOMING_PACKET_THRESHOLD = 30
local OUTCOMING_PACKET_THRESHOLD = 15

local REMOTE_CONTAINER_NAME = `communiception_{owner.UserId}`
local REMOTE_CONTAINER: Folder = (owner.PlayerGui:WaitForChild(REMOTE_CONTAINER_NAME, 10) :: any)

if not REMOTE_CONTAINER then
    error("[communiception]: could not fetch remote container")
end

local registered_ids: {[string]: boolean?} = {}

-- @CommuniceptionEvent
local CommuniceptionEvent = {}

type CommuniceptionEventClient = typeof(CommuniceptionEvent) & {
	id: string,
	mode: types.EventCommunicationMode,

	_internal: {
		listeners: {types.ClientListener<...any>},

		incoming_packets: {types.EventPacket},
		outcoming_packets: {types.EventPacket},
	}
}

function CommuniceptionEvent._init(self: CommuniceptionEventClient)
	local remote_obj: RemoteEvent
	if self.mode == "reliable" then
		remote_obj = (REMOTE_CONTAINER:WaitForChild(`{self.id}_reliable`, 5) :: any)
	elseif self.mode == "unreliable" then
		remote_obj = (REMOTE_CONTAINER:WaitForChild(`{self.id}_unreliable`, 5) :: any)
	end

    if not remote_obj then
        error(`[communiception]: could not find remote[id={self.id},type=event,mode={self.mode}], perhaps it is not registered`, 3)
    end

	remote_obj.OnClientEvent:Connect(function(args: {any})
		table.insert(self._internal.incoming_packets, {
			args = args
		})
	end)

	RunService.PostSimulation:Connect(function()
		for _ = 1, INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(self._internal.incoming_packets)
			if not incoming_packet then
				break
			end

			for _, listener in self._internal.listeners do
				task.defer(listener, unpack(incoming_packet.args))
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

function CommuniceptionEvent.send(self: CommuniceptionEventClient, ...)
	table.insert(self._internal.outcoming_packets, {
		args = {...}
	})
end

function CommuniceptionEvent.listen<T...>(self: CommuniceptionEventClient, listener: types.ClientListener<T...>): (() -> ())
	local hash_id = (#self._internal.listeners + 1)
	self._internal.listeners[hash_id] = listener

	return function()
		table.remove(self._internal.listeners, hash_id)
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
		task.defer(thread, ...)
	end

	disconnect_func = CommuniceptionEvent.listen(self, listener_wrapper)
	return coroutine.yield()
end

function CommuniceptionEvent.disconnectAll(self: CommuniceptionEventClient)
	table.clear(self._internal.listeners)
end

local CommuniceptionFunction = {}

type CommuniceptionFunctionClient = typeof(CommuniceptionFunction) & {
	id: string,

	_internal: {
		callback: types.ClientCallback<...any>,

		listeners: {types.ClientListener<...any>},

		incoming_packets: {types.IncomingFunctionPacket},
		outcoming_packets: {types.OutcomingFunctionPacket},
	}
}

function CommuniceptionFunction._init(self: CommuniceptionFunctionClient)
	local on_incoming_remote = (REMOTE_CONTAINER:WaitForChild(`{self.id}_incoming`, 5) :: RemoteEvent)
	local on_outcoming_remote = (REMOTE_CONTAINER:WaitForChild(`{self.id}_outcoming`, 5) :: RemoteEvent)

	if not (on_incoming_remote and on_outcoming_remote) then
        error(`[communiception]: could not find remote[id={self.id},type=function]`, 3)
	end

	-- listens to data recieved from player
	on_incoming_remote.OnClientEvent:Connect(function(callback_id: number, args: {any})
		table.insert(self._internal.outcoming_packets, {
			callback_id = callback_id,
			args = args
		})
	end)

	-- listens to data sent from player
	on_outcoming_remote.OnClientEvent:Connect(function(callback_id: number, args: {any})
		table.insert(self._internal.incoming_packets, {
			callback_id = callback_id,
			args = args
		})
	end)

	RunService.PostSimulation:Connect(function()
		for _ = 1, INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(self._internal.incoming_packets)
			if not incoming_packet then
				break
			end

			local listener = self._internal.listeners[incoming_packet.callback_id]
			if not listener then
				continue
			end

			task.defer(listener, unpack(incoming_packet))
		end

		for _ = 1, OUTCOMING_PACKET_THRESHOLD do
			local outcoming_packet = table.remove(self._internal.outcoming_packets)
			if not outcoming_packet then
				break
			end

			on_outcoming_remote:FireServer(outcoming_packet.callback_id, outcoming_packet.args)
		end
	end)
end

function CommuniceptionFunction.invoke(self: CommuniceptionFunctionClient, timeout: number, ...): (boolean, ...any)
	local thread = coroutine.running()
	local callback_recieved = false
	local callback_id = (#self._internal.listeners + 1)

	self._internal.listeners[callback_id] = function(...)
		callback_recieved = true
		table.remove(self._internal.listeners, callback_id)
		task.spawn(thread, true, ...)
	end

	task.delay(timeout, function()
		if callback_recieved then
			-- callback is already recieved, cancel this automatic cancellation
			return
		end

		table.remove(self._internal.listeners, callback_id)
		task.spawn(thread, false)
	end)

	table.insert(self._internal.outcoming_packets, {
		callback_id = callback_id,
		args = {...}
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
		
		incoming_packets = {},
		outcoming_packets = {},
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
		
		incoming_packets = {},
		outcoming_packets = {},
	}

	self._init(self :: any)

	return (self :: any)
end

return module
