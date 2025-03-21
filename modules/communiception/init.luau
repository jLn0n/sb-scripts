local RunService = game:GetService("RunService")

local types = require("./types")
local common = require("./common")

local IS_SERVER = RunService:IsServer()

local _initialized = false

local registered_ids: {[string]: boolean?} = {}

local incoming_packets: {types.IncomingPacket} = {}
local outcoming_packets: {types.OutcomingPacket} = {}
local incoming_packet_listeners: {[string]: types.InternalListener} = {}

-- @CommuniceptionEvent
local CommuniceptionEventObj = {}

type CommuniceptionEvent = typeof(CommuniceptionEventObj) & {
	id: string,
	mode: types.CommunicationType,

	_internal: {
		listeners: {types.CommunicationListener<any>},
	},
}

function CommuniceptionEventObj._init(self: CommuniceptionEvent)
	incoming_packet_listeners[self.id] = function(sender: Player?, ...)
		for _, listener in self._internal.listeners do
			task.spawn(listener, {...}, sender)
		end
	end
end

function CommuniceptionEventObj.send(self: CommuniceptionEvent, ...)
    assert(not IS_SERVER, "[communiception]: CommuniceptionEvent::send can only be called on client-side")

	table.insert(outcoming_packets, {
		type = (self.mode :: any),
		id = self.id,
		args = {...},
	})
end


function CommuniceptionEventObj.sendTo(self: CommuniceptionEvent, target: Player, ...)
    assert(IS_SERVER, "[communiception]: CommuniceptionEvent::sendTo can only be called on server-side")

	table.insert(outcoming_packets, {
		type = (self.mode :: any),
		id = self.id,
		args = {...},
		targets = {target},
	})
end

function CommuniceptionEventObj.sendToMultiple(self: CommuniceptionEvent, targets: {Player}, ...)
    assert(IS_SERVER, "[communiception]: CommuniceptionEvent::sendToMultiple can only be called on server-side")

	table.insert(outcoming_packets, {
		type = (self.mode :: any),
		id = self.id,
		args = {...},
		targets = targets,
	})
end

function CommuniceptionEventObj.listen<T>(self: CommuniceptionEvent, listener: types.CommunicationListener<T>): (() -> ())
	local listener_id = common.getEmptyIndex(self._internal.listeners)
	self._internal.listeners[listener_id] = listener

	return function()
		self._internal.listeners[listener_id] = nil
	end
end

function CommuniceptionEventObj.listenOnce<T>(self: CommuniceptionEvent, listener: types.CommunicationListener<T>): (() -> ())
	local disconnect_func
	local function listener_wrapper(...)
		listener(...)
		disconnect_func()
	end

	disconnect_func = CommuniceptionEventObj.listen(self, listener_wrapper)
	return disconnect_func
end

function CommuniceptionEventObj.wait(self: CommuniceptionEvent): any
	local thread = coroutine.running()
	local disconnect_func

	local function listener_wrapper(...)
		disconnect_func()
		task.spawn(thread, ...)
	end

	disconnect_func = CommuniceptionEventObj.listen(self, listener_wrapper)
	return coroutine.yield()
end

function CommuniceptionEventObj.disconnectAll(self: CommuniceptionEvent)
	table.clear(self._internal.listeners)
end

-- @CommuniceptionFunction
local CommuniceptionFunctionObj = {}

type CommuniceptionFunction = typeof(CommuniceptionFunctionObj) & {
	id: string,

	_internal: {
		callback: types.CommunicationCallback<any>,
		listeners: {types.InternalListener},
	},
}

function CommuniceptionFunctionObj._init(self: CommuniceptionFunction)
	-- listens to data recieved from peer (callback response)
	incoming_packet_listeners[`i_{self.id}`] = function(sender: Player?, callback_id: number, ...)
		local listener = self._internal.listeners[callback_id]
		if not listener then
			return
		end

		listener(sender, ...)
	end

	-- listens to data sent from peer (callback request)
	incoming_packet_listeners[`o_{self.id}`] = function(sender: Player?, callback_id: number, ...)
		local current_callback = self._internal.callback
		if not current_callback then
			return
		end

		task.spawn(function(...)
			table.insert(outcoming_packets, {
				type = ("reliable" :: any),
				id = `i_{self.id}`,
				args = {callback_id, current_callback({...}, sender)},
				targets = ({sender} :: any),
			})
		end, ...)
	end
end

function CommuniceptionFunctionObj.invoke(self: CommuniceptionFunction, timeout: number, ...): (boolean, ...any)
    assert(not IS_SERVER, "[communiception]: CommuniceptionFunction::invoke can only be called on client-side")

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
		id = `o_{self.id}`,
		args = {callback_id, ...},
	})
	return coroutine.yield()
end

function CommuniceptionFunctionObj.invokeTo(self: CommuniceptionFunction, target: Player, timeout: number, ...): (boolean, ...any)
    assert(IS_SERVER, "[communiception]: CommuniceptionFunction::invokeTo can only be called on server-side")

	local thread = coroutine.running()
	local callback_recieved = false
	local callback_id = common.getEmptyIndex(self._internal.listeners)

	self._internal.listeners[callback_id] = function(sender: Player?, ...)
		if sender and (target.UserId ~= sender.UserId) then
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

	table.insert(outcoming_packets, {
		type = ("reliable" :: any),
		id = `o_{self.id}`,
		args = {callback_id, ...},
		targets = {target},
	})
	return coroutine.yield()
end

function CommuniceptionFunctionObj.setListener<T>(self: CommuniceptionFunction, callback: types.CommunicationCallback<T>)
	self._internal.callback = callback
end

-- main
local module = {}

function module.initialize(config: types.CommuniceptionConfiguration?): ()
	if _initialized then
		return error("[communiception]: already initialized.")
	end
	_initialized = true

	local current_config = config or common.DEFAULT_CONFIGURATION
	local current_remotes, _registry_changed = common.initializeInternalRemotes(current_config.INTERNAL_REMOTE_HANDLER)

	local __RBXSignalConnect = _registry_changed.Event.Connect
	local _registration_event: "OnServerEvent" | "OnClientEvent" = nil
	local _remote_refs: types.RemoteRegistry = ({} :: any)
	local _registering_funcs: {
		["reliable"]: (...any) -> (),
		["unreliable"]: (...any) -> (),
	} = ({} :: any)

    if IS_SERVER then
		_registration_event = "OnServerEvent"

        _registering_funcs.reliable = function(sender: Player, id: string, ...)
            table.insert(incoming_packets, {
                type = ("reliable" :: any),
                id = id,
                args = {...},
                sender = sender
            })
        end
        _registering_funcs.unreliable = function(sender: Player, id: string, ...)
            table.insert(incoming_packets, {
                type = ("unreliable" :: any),
                id = id,
                args = {...},
                sender = sender
            })
        end
    else
		_registration_event = "OnClientEvent"

        _registering_funcs.reliable = function(id: string, ...)
            table.insert(incoming_packets, {
                type = ("reliable" :: any),
                id = id,
                args = {...},
            })
        end
        _registering_funcs.unreliable = function(id: string, ...)
            table.insert(incoming_packets, {
                type = ("unreliable" :: any),
                id = id,
                args = {...},
            })
        end
    end

	local function _onRemoteRegistryChanged()
		for remote_type: any, remote_obj: any in current_remotes do
			if _remote_refs[remote_type] == remote_obj then
				continue
			end

			_remote_refs[remote_type] = remote_obj
			print("REMOTE REGISTRATION!!!", remote_type, remote_obj, _registration_event)
			__RBXSignalConnect(remote_obj[_registration_event], _registering_funcs[remote_type])
		end
	end

	RunService.PostSimulation:Connect(function()
		for _ = 1, current_config.INCOMING_PACKET_THRESHOLD do
			local incoming_packet = table.remove(incoming_packets)
			if not incoming_packet then
				-- no incoming packets to be processed, break the loop
				break
			end
			if IS_SERVER and (not incoming_packet.sender) then
				-- this is not possible bruv (on server-side)
				continue
			end

			local listener = incoming_packet_listeners[incoming_packet.id]
			if not listener then
				-- the listener for id doesn't exist as of the invocation from the internal listener
				continue
			end

			task.spawn(listener, incoming_packet.sender, unpack(incoming_packet.args))
		end

		for _ = 1, current_config.OUTCOMING_PACKET_THRESHOLD do
			local outcoming_packet = table.remove(outcoming_packets)
			if not outcoming_packet then
				-- no outcoming packets to be processed, break the loop
				break
			end

            if IS_SERVER then
                if (not outcoming_packet.targets) then
                    -- this is not allowed (on server-side)
                    continue
                end

                for _, target in outcoming_packet.targets do
                    current_remotes[outcoming_packet.type]:FireClient(target, outcoming_packet.id, unpack(outcoming_packet.args))
                end
            else
                current_remotes[outcoming_packet.type]:FireServer(outcoming_packet.id, unpack(outcoming_packet.args))
            end
		end
	end)

	_onRemoteRegistryChanged()
	_registry_changed.Event:Connect(_onRemoteRegistryChanged)
end

function module.newEvent(
	id: string,
	mode: types.CommunicationType
): CommuniceptionEvent
	if registered_ids[id] then
		return error(`[communiception]: remote[id={id}] is already registered`)
	end
	registered_ids[id] = true

	local self = setmetatable({}, {
		__index = CommuniceptionEventObj
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
): CommuniceptionFunction
	if registered_ids[id] then
		return error(`[communiception]: remote[id={id}] is already registered`)
	end
	registered_ids[id] = true

	local self = setmetatable({}, {
		__index = CommuniceptionFunctionObj
	})

	self.id = id
	self._internal = {
		listeners = {},
	}

	self._init(self :: any)

	return (self :: any)
end

return module
