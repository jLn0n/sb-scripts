local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local REMOTE_CONTAINER_NAME = `communiception_{owner.UserId}`

local CommuniceptionCommon = {
    CONFIGURATION = {
        INCOMING_PACKET_THRESHOLD = 30,
        OUTCOMING_PACKET_THRESHOLD = 30,
    }
}

function CommuniceptionCommon.initializeContainer(): Folder
    local container: Folder

    if IS_SERVER then
        container = (owner.PlayerGui:FindFirstChild(REMOTE_CONTAINER_NAME) :: Folder)

        if container then
            container:ClearAllChildren()
        else
            local new_container = Instance.new("Folder")
            new_container.Name = REMOTE_CONTAINER_NAME
            new_container.Parent = owner.PlayerGui
            container = new_container
        end
    else
        container = (owner.PlayerGui:WaitForChild(REMOTE_CONTAINER_NAME, 10) :: Folder)

        if not container then
            error("[communiception]: could not fetch remote container", 0)
        end
    end
    return container
end

function CommuniceptionCommon.fetchEmptyIndex(tbl_array: {[number]: any}, start: number?): number
    local tbl_size = rawlen(tbl_array)

    for idx = start or 1, tbl_size do
        if tbl_array[idx] then
            continue
        end

        return idx
    end
    return tbl_size + 1
end

return CommuniceptionCommon