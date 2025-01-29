--[[
	epictrymote.luau
	@jLn0n | 2025

	Wrapper that handles remotes to ease my pain.
	Based of https://github.com/nightcycle/network-util/blob/29934bc19679fe3841defbf61230a1535bb80026/src/init.luau with some changes
--]]

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local REMOTE_CONTAINER: Folder
local REMOTE_CONTAINER_NAME = `epictrymotes - {owner.Name}`
local REMOTE_CONTAINER_PARENT = owner.PlayerGui

if IS_SERVER then
	local _thing = REMOTE_CONTAINER_PARENT:FindFirstChild(REMOTE_CONTAINER_NAME)
	if _thing then
		_thing:Destroy()
	end

	REMOTE_CONTAINER = Instance.new("Folder")
	REMOTE_CONTAINER.Name = REMOTE_CONTAINER_NAME
	REMOTE_CONTAINER.Parent = REMOTE_CONTAINER_PARENT
else
	REMOTE_CONTAINER = (REMOTE_CONTAINER_PARENT:WaitForChild(REMOTE_CONTAINER_NAME, 5)::Folder)

	if not REMOTE_CONTAINER then
		error("could not fetch remote container")
	end
end

type RemoteClasses = "RemoteEvent" | "UnreliableRemoteEvent" | "RemoteFunction" 

local function fetch_remote_obj(key: string, remote_class: RemoteClasses): Instance
	local remote_obj = (if IS_SERVER then REMOTE_CONTAINER:FindFirstChild(key) else REMOTE_CONTAINER:WaitForChild(key, 5))
	if not remote_obj then
		if not IS_SERVER then
			return error(`could not get remote['{key}'], make sure it is defined on the server!`, 2)
		end

		local new_remote = Instance.new(remote_class)
		new_remote.Name = key
		new_remote.Parent = REMOTE_CONTAINER
		
		return new_remote
	end

	if not remote_obj:IsA(remote_class) then
		return error(`remote['{key}'] cannot be used as remote type '{remote_class}'.`, 2)
	end

	return remote_obj
end

-- main
local module = {}

function module.getReliable(key: string): RemoteEvent
	return (fetch_remote_obj(key, "RemoteEvent") :: any)
end

function module.getUnreliable(key: string): UnreliableRemoteEvent
	return (fetch_remote_obj(key, "UnreliableRemoteEvent") :: any)
end

function module.getFunction(key: string): RemoteFunction
	return (fetch_remote_obj(key, "RemoteEvent") :: any)
end

function module.onClientEvent(key: string, func: (...any) -> ()): RBXScriptConnection
	assert(IS_CLIENT, "this can only be called in client-side!")
	local remote_obj = module.getReliable(key)

	return remote_obj.OnClientEvent:Connect(func)
end

function module.onUnreliableClientEvent(
	key: string,
	func: (...any) -> ()
): RBXScriptConnection
	assert(IS_CLIENT, "this can only be called in client-side!")
	local remote_obj = module.getUnreliable(key)
	
	return remote_obj.OnClientEvent:Connect(func)
end

function module.onServerEvent(
	key: string,
	func: (player: Player, ...any) -> ()
): RBXScriptConnection
	assert(IS_SERVER, "this can only be called in server-side!")
	local remote_obj = module.getReliable(key)

	return remote_obj.OnServerEvent:Connect(func)
end

function module.onUnreliableServerEvent(
	key: string,
	func: (player: Player, ...any) -> ()
): RBXScriptConnection
	assert(IS_SERVER, "this can only be called in server-side!")
	local remote_obj = module.getUnreliable(key)

	return remote_obj.OnServerEvent:Connect(func)
end

function module.fireServer(key: string, ...: any): ()
	assert(IS_CLIENT, "this can only be called in client-side!")
	
	local remote_obj = module.getReliable(key)
	remote_obj:FireServer(...)
end

function module.fireServerUnreliable(key: string, ...: any): ()
	assert(IS_CLIENT, "this can only be called in client-side!")
	
	local remote_obj = module.getUnreliable(key)
	remote_obj:FireServer(...)
end

function module.fireClientAt(key: string, target: Player, ...: any): ()
	assert(IS_SERVER, "this can only be called in server-side!")
	
	local remote_obj = module.getReliable(key)
	remote_obj:FireClient(target, ...)
end

function module.fireClientUnreliableAt(key: string, target: Player, ...: any): ()
	assert(IS_SERVER, "this can only be called in server-side!")
	
	local remote_obj = module.getUnreliable(key)
	remote_obj:FireClient(target, ...)
end

function module.fireAllClients(key: string, ...: any): ()
	assert(IS_SERVER, "this can only be called in server-side!")

	local remote_obj = module.getReliable(key)
	remote_obj:FireAllClients(...)
end

function module.fireAllClientsUnreliable(key: string, ...: any): ()
	assert(IS_SERVER, "this can only be called in server-side!")

	local remote_obj = module.getUnreliable(key)
	remote_obj:FireAllClients(...)
end

function module.invokeServer<V>(key: string, ...: any): V
	assert(IS_CLIENT, "this can only be called in client-side!")

	local remote_obj = module.getFunction(key)
	return remote_obj:InvokeServer(...)
end

function module.invokeClient<V>(key: string, target: Player, ...: any): V
	assert(IS_SERVER, "this can only be called in server-side!")

	local remote_obj = module.getFunction(key)
	return remote_obj:InvokeClient(target, ...)
end

function module.onServerInvoke<V>(
	key: string,
	func: (player: Player, ...any) -> V
): ()
	assert(IS_CLIENT, "this can only be called in client-side!")

	local remote_obj = module.getFunction(key)
	remote_obj.OnServerInvoke = func
end

function module.onClientInvoke<V>(
	key: string,
	func: (...any) -> V
): ()
	assert(IS_SERVER, "this can only be called in server-side!")

	local remote_obj = module.getFunction(key)
	remote_obj.OnClientInvoke = func
end

return module
