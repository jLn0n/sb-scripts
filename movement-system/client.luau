-- should always be lua 5.1 compatible
print("client waiting")
repeat task.wait() until script:GetAttribute("server_ready")

local input_service = game:GetService("UserInputService")
local run_service = game:GetService("RunService")

local remotes_container = script:FindFirstChild("remotes")
local character_pointer = script:FindFirstChild("movement_char_pointer")

local camera = workspace.CurrentCamera

local MOVEMENT_FIELDS = {
	forward = 1, 	-- 0b00001
	backward = 2, 	-- 0b00010
	leftward = 4, 	-- 0b00100
	rightward = 8,	-- 0b01000
	jump = 16,		-- 0b10000
}
local MOVEMENT_CONTROLS = {
	forward = Enum.KeyCode.W,
	backward = Enum.KeyCode.S,
	leftward = Enum.KeyCode.A,
	rightward = Enum.KeyCode.D,
	jump = Enum.KeyCode.Space
}

local remotes = {}

local character_data = {
	char_obj = character_pointer.Value,

	movement_states = {
		forward = false,
		backward = false,
		leftward = false,
		rightward = false,
		jump = false
	}
}

local function encode_movement(movement_states)
	local result
	result = bit32.band((movement_states.forward and 1 or 0), MOVEMENT_FIELDS.forward)
	result = result + bit32.band(bit32.lshift((movement_states.backward and 1 or 0), 1), MOVEMENT_FIELDS.backward)
	result = result + bit32.band(bit32.lshift((movement_states.leftward and 1 or 0), 2), MOVEMENT_FIELDS.leftward)
	result = result + bit32.band(bit32.lshift((movement_states.rightward and 1 or 0), 3), MOVEMENT_FIELDS.rightward)
	result = result + bit32.band(bit32.lshift((movement_states.jump and 1 or 0), 4), MOVEMENT_FIELDS.jump)

	return result
end

-- init
for _, remote_obj in ipairs(remotes_container:GetChildren()) do
	remotes[remote_obj.Name] = remote_obj
end

-- main
camera.CameraType = Enum.CameraType.Custom

run_service.PreSimulation:Connect(function()
	if input_service:GetFocusedTextBox() then return end

	for movement_name, movement_keycode in pairs(MOVEMENT_CONTROLS) do
		character_data.movement_states[movement_name] = input_service:IsKeyDown(movement_keycode)
	end
	camera.CameraSubject = character_data.char_obj
end)

run_service.PostSimulation:Connect(function()
	local _, yaw_rot = camera.CFrame:ToOrientation()
	remotes.send_movement_state:FireServer(encode_movement(character_data.movement_states), yaw_rot)
end)

print("client initialized")
