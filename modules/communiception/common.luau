local RunService = game:GetService("RunService")

local types = require("@self/types")

local IS_SERVER = RunService:IsServer()

local __internal_default_remote_from_handler_initialized = false
local function _DEFAULT_REMOTE_HANDLER(remote_registry: types.RemoteRegistry): (boolean)
	if __internal_default_remote_from_handler_initialized then
		return false
	end
	__internal_default_remote_from_handler_initialized = true

	local REMOTE_CONTAINER_NAME = `communiception_{game.PlaceId}`

	local _container_parent: Instance
	if owner then
		_container_parent = (owner:FindFirstChildWhichIsA("PlayerGui") :: any)
	else
		_container_parent = game:GetService("ReplicatedStorage")
	end

	local _container: Folder
	if IS_SERVER then
		_container = (_container_parent:FindFirstChild(REMOTE_CONTAINER_NAME) :: Folder)
		if not _container then
			local new_container = Instance.new("Folder")
			new_container.Name = REMOTE_CONTAINER_NAME
			new_container.Parent = _container_parent
			_container = new_container
		end
	else
		_container = (_container_parent:WaitForChild(REMOTE_CONTAINER_NAME, 10) :: Folder)
		if not _container then
			error("[communiception]: could not fetch remote container", 0)
		end
	end

	local reliable_remote: RemoteEvent = (_container:FindFirstChildWhichIsA("RemoteEvent") :: any)
	local unreliable_remote: UnreliableRemoteEvent = (_container:FindFirstChildWhichIsA("UnreliableRemoteEvent") :: any)

	if not (reliable_remote and unreliable_remote) then
		if not IS_SERVER then
			error("[communiception]: internal remotes cannot be fully fetched", 0)
		end

		reliable_remote = Instance.new("RemoteEvent", _container)
		unreliable_remote = Instance.new("UnreliableRemoteEvent", _container)
	end

	remote_registry.reliable = reliable_remote
	remote_registry.unreliable = unreliable_remote

	return true
end

local _DEFAULT_CONFIGURATION: types.CommuniceptionConfiguration = {
	INCOMING_PACKET_THRESHOLD = 30,
	OUTCOMING_PACKET_THRESHOLD = 30,

	INTERNAL_REMOTE_HANDLER = _DEFAULT_REMOTE_HANDLER
}

-- main
local CommuniceptionCommon = {
	DEFAULT_CONFIGURATION = _DEFAULT_CONFIGURATION
}

function CommuniceptionCommon.initializeInternalRemotes(
	remote_handler: types.InternalRemoteHandler
): (types.RemoteRegistry, BindableEvent)
	local registry_changed_event = Instance.new("BindableEvent")
	local remote_registry: types.RemoteRegistry = ({} :: any)

	task.spawn(function()
		while true do RunService.PostSimulation:Wait()
			local new_registry = remote_handler(remote_registry)

			if new_registry then
				registry_changed_event:Fire()
			end
		end
	end)
	registry_changed_event.Event:Wait()
	return remote_registry, registry_changed_event
end

function CommuniceptionCommon.getEmptyIndex(tbl_array: {[number]: any}, start: number?): number
	local tbl_size = #tbl_array

	for idx = start or 1, tbl_size do
		if tbl_array[idx] then
			continue
		end

		return idx
	end
	return tbl_size + 1
end

return CommuniceptionCommon
