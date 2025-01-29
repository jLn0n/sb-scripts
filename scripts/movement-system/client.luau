print("client waiting")
repeat task.wait() until script:GetAttribute("server_ready")

local input_service = game:GetService("UserInputService")
local run_service = game:GetService("RunService")

local communiception = require("@shared/communiception/client")

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

local send_movement_states = communiception.new("send_movement_states", "unreliable")

local character_data = {
	movement_states = {
		forward = 0,
		backward = 0,
		leftward = 0,
		rightward = 0,
		jump = 0
	}
}

local function encode_movement(movement_states)
	local result
	result = bit32.band((movement_states.forward), MOVEMENT_FIELDS.forward)
	result += bit32.band(bit32.lshift((movement_states.backward), 1), MOVEMENT_FIELDS.backward)
	result += bit32.band(bit32.lshift((movement_states.leftward), 2), MOVEMENT_FIELDS.leftward)
	result += bit32.band(bit32.lshift((movement_states.rightward), 3), MOVEMENT_FIELDS.rightward)
	result += bit32.band(bit32.lshift((movement_states.jump), 4), MOVEMENT_FIELDS.jump)

	return result
end

local function send_current_state()
	local movement_state = encode_movement(character_data.movement_states)
	local _, yaw_rot = camera.CFrame:ToOrientation()

	--[[
	data format:
	* 2 byte uint16 yaw (mapped to range 0 - 65535)
	* 2 byte uint16 for movement states 0b00000000_000mmmmm
	]]
	local state_buff = buffer.create(2 + 2)

	local mapped_yaw = math.floor(math.map(yaw_rot, -math.pi, math.pi, 0, 65535))
	buffer.writeu16(state_buff, 0, mapped_yaw)
	buffer.writeu16(state_buff, 2, movement_state)

	send_movement_states:send(state_buff)
end

-- main
run_service.PreSimulation:Connect(function()
	if input_service:GetFocusedTextBox() then return end

	for movement_name, movement_keycode in pairs(MOVEMENT_CONTROLS) do
		character_data.movement_states[movement_name] = (input_service:IsKeyDown(movement_keycode) and 1 or 0)
	end
end)

run_service.PostSimulation:Connect(function()
	send_current_state()
end)

print("client initialized")
