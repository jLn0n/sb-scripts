local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local CommuniceptionCommon = {
    CONFIGURATION = {
        INCOMING_PACKET_THRESHOLD = 30,
        OUTCOMING_PACKET_THRESHOLD = 30,
    }
}

type RemoteRegistry = {
    reliable: RemoteEvent,
    unreliable: UnreliableRemoteEvent,
}
type InternalRemoteHandler = (remote_registry: RemoteRegistry) -> (boolean)

local function _DEFAULT_REMOTE_HANDLER(remote_registry: RemoteRegistry)
    local REMOTE_CONTAINER_NAME = `communiception_{game.PlaceId}`

    local _container: Folder
    local reliable_remote: RemoteEvent
    local unreliable_remote: UnreliableRemoteEvent

    if IS_SERVER then
        _container = (owner.PlayerGui:FindFirstChild(REMOTE_CONTAINER_NAME) :: Folder)
        if not _container then
            local new_container = Instance.new("Folder")
            new_container.Name = REMOTE_CONTAINER_NAME
            new_container.Parent = owner.PlayerGui
            _container = new_container
        end

        reliable_remote = Instance.new("RemoteEvent", _container)
        unreliable_remote = Instance.new("UnreliableRemoteEvent", _container)
    else
        _container = (owner.PlayerGui:WaitForChild(REMOTE_CONTAINER_NAME, 10) :: Folder)
        if not _container then
            error("[communiception]: could not fetch remote container", 0)
        end

        reliable_remote = (_container:FindFirstChildWhichIsA("RemoteEvent") :: any)
        unreliable_remote = (_container:FindFirstChildWhichIsA("UnreliableRemoteEvent") :: any)

        if not (reliable_remote and unreliable_remote) then
            error("[communiception]: internal remotes cannot be fully fetched", 0)
        end
    end

    remote_registry.reliable = reliable_remote
    remote_registry.unreliable = unreliable_remote

    return true
end

function CommuniceptionCommon.initializeInternalRemotes(remote_handler: InternalRemoteHandler?): (RemoteRegistry, BindableEvent)
    local registry_changed_event = Instance.new("BindableEvent")
    local remote_registry: RemoteRegistry = ({} :: any)

    if not remote_handler then
        _DEFAULT_REMOTE_HANDLER(remote_registry)
    else
        task.spawn(function()
            while true do RunService.PostSimulation:Wait()
                local new_registry = remote_handler(remote_registry)

                if new_registry then
                    registry_changed_event:Fire()
                end
            end
        end)
    end
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