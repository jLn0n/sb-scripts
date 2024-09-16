-- TODO: implement a character physics system thing
local http_service = game:GetService("HttpService")
local run_service = game:GetService("RunService")

local remotes_container = Instance.new("Folder")
remotes_container.Name = "remotes"

local character = Instance.new("Model")
character.Name = "char"
character.Parent = script

local root_part = Instance.new("Part")
root_part.Anchored = true
root_part.Name = "movement_part"
root_part.Size = Vector3.new(2, 2, 1)
root_part.Parent = character

local character_pointer = Instance.new("ObjectValue")
character_pointer.Name = "movement_char_pointer"
character_pointer.Value = character

local collider_rayparams = RaycastParams.new()
collider_rayparams.FilterType = Enum.RaycastFilterType.Exclude
collider_rayparams.FilterDescendantsInstances = {character}

local RAY_DIRECTIONS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 1).Unit,
	Vector3.new(-1, 0, -1).Unit,
	Vector3.new(1, 0, -1).Unit,
	Vector3.new(-1, 0, 1).Unit
}

local MOVEMENT_FIELDS = {
	forward = 	0,
	backward = 	1,
	leftward = 	2,
	rightward = 3,
	jump =		4,
}

local remotes = {
	send_movement_state = Instance.new("RemoteEvent"),
}

local imports = {
	gist_loader = "https://gist.githubusercontent.com/jLn0n/1ebbf7048a40d8d59737eca4e738fabd/raw/gist-loader.luau"
}

local character_data = {
	current_pos = CFrame.identity + (Vector3.yAxis * 20),
	control_yaw = 0,

	state = {
		forward = false,
		backward = false,
		leftward = false,
		rightward = false,
		jump = false
	},

	modifiers = {
		gravity = -9.8, -- pls convert to workspace.Gravity soon :pray:
		walk_speed = 16,
		jump_power = 50,
		hip_height = 0,
		max_slope_angle = 89,
	}
}

local function fetch_url(url: string, no_cache: boolean): string?
	local success, result = pcall(http_service.GetAsync, http_service, url, no_cache)

	if not success then
		warn(`Failed to load URL '{url}'\n{result}`)
		return nil
	end
	return result
end

local function decode_movement_state(packed_state: number)
	local result = {}

	for movement_name, field_value in MOVEMENT_FIELDS do
		result[movement_name] = (bit32.extract(packed_state, field_value, 1) == 1)
	end
	return result
end

local function get_movement_dir(look_vect: Vector3, right_vect: Vector3): Vector3
	local result = Vector3.zero

	if character_data.state.forward then
		result += look_vect
	end
	if character_data.state.backward then
		result += -look_vect
	end
	if character_data.state.leftward then
		result += -right_vect
	end
	if character_data.state.rightward then
		result += right_vect
	end
	
	if result.Magnitude > 0 then
		-- direction should be balanced
		-- should only be "unitized" when magnitude is not zero
		result = result.Unit
	end
	return result
end

local function is_character_grounded(position: Vector3)
	local result = workspace:Raycast(position, Vector3.new(0, -(character_data.modifiers.hip_height + 2), 0), collider_rayparams)

	return typeof(result) == "RaycastResult", result
end

local function check_collision(position: Vector3): (boolean, RaycastResult?)
	for _, direction in RAY_DIRECTIONS do
		local cast_result = workspace:Raycast(position, direction * 2, collider_rayparams)

		if cast_result and (cast_result.Instance and cast_result.Instance.CanCollide) then
			return true, cast_result
		end
	end
	return false, nil
end

-- init
if owner.Character then
	owner.Character.Parent = nil
end

print("loading imports")
for import_name, import_url in imports do
    local import_src = fetch_url(import_url, true)
    if not import_src then
        continue
    end

	local module, err = loadstring(import_src, import_name)
	if module then
		imports[import_name] = module()
	else
		warn(`Cannot import '{import_url}'. Error details:/n{err}`)
	end
end

local gist_loader: typeof(require("./../gist-loader")) = imports.gist_loader
local movement_gist = gist_loader("jLn0n", "33d96c89a319f3d1e06cd718eb47c8d5")

print("imports loaded")

for remote_name, remote_obj in remotes do
	remote_obj.Name = remote_name
	remote_obj.Parent = remotes_container
end

-- main
remotes.send_movement_state.OnServerEvent:Connect(function(_player, state_data, control_yaw)
	if _player.UserId ~= owner.UserId then return end

	character_data.state = decode_movement_state(state_data)
	character_data.control_yaw = control_yaw
end)

-- TODO: make the thing work
-- TODO: add state system for controller

run_service.Heartbeat:Connect(function(delta_time)
	local control_rot = CFrame.fromOrientation(0, character_data.control_yaw, 0)
	local control_lvec, control_rvec = control_rot.LookVector, control_rot.RightVector

	local movement_dir = get_movement_dir(control_lvec, control_rvec)
	local movement_vel = (movement_dir * (character_data.modifiers.walk_speed * delta_time))
	local processed_pos = character_data.current_pos

	-- fall physics
	local is_grounded = is_character_grounded(processed_pos.Position)
	local character_gravity = Vector3.zero

	if (character_data.state.jump and is_grounded) then
		character_gravity += Vector3.yAxis * (character_data.modifiers.jump_power * delta_time)
	end
	if not is_grounded then
		character_gravity += Vector3.yAxis * (character_data.modifiers.gravity * delta_time)
	end

	processed_pos += character_gravity

	-- collision
	local collided, cast_result = check_collision(processed_pos.Position)

	if not collided then
		processed_pos += movement_vel
	else
		local cast_normal = cast_result.Normal
		local slide_vect = movement_vel - cast_normal * movement_vel:Dot(cast_normal)
		local temp_pos = (processed_pos + movement_vel)
		collided, cast_result = check_collision(temp_pos.Position)

		if not collided then
			processed_pos += slide_vect
		else
			local pependicular_slide_vect = Vector3.new(movement_vel.Z, 0, -movement_vel.X)
			temp_pos = (processed_pos + pependicular_slide_vect)
			collided, cast_result = check_collision(temp_pos.Position)

			if not collided then
				processed_pos += pependicular_slide_vect
			end
		end
	end

	-- applying processed position
	character_data.current_pos = processed_pos
	root_part.CFrame = character_data.current_pos
end)

-- post-init
print("fetching client script")
local client_script_raw = movement_gist.fetch("movement_client.luau", true)
local client_script = NLS(client_script_raw or "error('client script failed to load!')")
print("client ran")

remotes_container.Parent = client_script
character_pointer.Parent = client_script

script.Name = "movement_system"
client_script.Name = "movement_system_client"
client_script:SetAttribute("server_ready", true)
print("every process now done")
