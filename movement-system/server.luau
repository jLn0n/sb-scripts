local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local remotes_container = Instance.new("Folder")
remotes_container.Name = "remotes"

local character_container = Instance.new("WorldModel")
character_container.Name = "character store thing"
character_container.Parent = script

local types = require("@movement-system/types")
local Collision = require("@movement-system/simulation/collision")
local MathUtils = require("@movement-system/simulation/math_utils")

local MOVEMENT_ORDER = {
	"forward",
	"backward",
	"leftward",
	"rightward",
	"jump"
}

local remotes: {[string]: Instance & (RemoteEvent | UnreliableRemoteEvent)} = {}
local remote_registry: {[string]: types.ShittyRemoteConfig} = {}

local halonoid_data: types.HalonoidData = {
	modifiers = {
		gravity = 196.2,
		walk_speed = 16,
		jump_height = 7.6,
		hip_height = 2,
		max_slope_angle = 89,
	},

	pressed_controls = {
		forward = false,
		backward = false,
		leftward = false,
		rightward = false,
		jump = false
	},

	simulation = {
		angle_yaw = 0,
		position = Vector3.new(0, 20, 0),
		velocity = Vector3.new(0, 0, 0),
		push_direction = Vector2.new(0, 0),

		step_up = 0,
		air_time = 0,

		jump_debounce = 0.2,
		jump_thrust = 0,
	}
}

local function fetch_url(url: string, no_cache: boolean): string?
	local success, result = pcall(HttpService.GetAsync, HttpService, url, no_cache)

	if not success then
		warn(`Failed to load URL '{url}'\n{result}`)
		return nil
	end
	return result
end

local function decode_movement_state(packed_state: number): types.HalonoidControlState
	local result = {}

	for field_value, state_name in MOVEMENT_ORDER do
		result[state_name] = (bit32.extract(packed_state, (field_value - 1), 1) == 1)
	end
	return result
end

local function decode_character_state(state_buff: buffer)
	halonoid_data.simulation.angle_yaw = math.map(
		buffer.readu16(state_buff, 0),
		0, 65535,
		-math.pi, math.pi
	)
	halonoid_data.pressed_controls = decode_movement_state(buffer.readu16(state_buff, 2))
end

local function get_movement_dir(look_vect: Vector3, right_vect: Vector3): Vector3
	local control_state = halonoid_data.pressed_controls
	local result = Vector3.zero

	if control_state.forward then
		result += look_vect
	end
	if control_state.backward then
		result -= look_vect
	end
	if control_state.leftward then
		result -= right_vect
	end
	if control_state.rightward then
		result += right_vect
	end

	return result
end

local function simulate_halonoid(halonoid_data: types.HalonoidData, movement_dir: Vector3, delta_time: number)
	local char_control_state = halonoid_data.pressed_controls
	local char_simdata = halonoid_data.simulation
	local char_modifiers = halonoid_data.modifiers

	-- converts degrees angle to normal y point
	local max_slope_angle = math.cos(math.rad(math.clamp(char_modifiers.max_slope_angle, 0, 90)))
	local hipheight_vect = Vector3.new(0, -char_modifiers.hip_height, 0)

	local on_ground_result = Collision.DoGroundCheck(char_simdata.position + hipheight_vect)

	--If the player is on too steep a slope, its not ground
	if (on_ground_result ~= nil and on_ground_result.normal.Y < max_slope_angle) then
		--See if we can move downwards?
		if (char_simdata.velocity.Y < 0.1) then
			local stuck = Collision.CheckGroundSlopes(char_simdata.position + hipheight_vect)
			
			if (stuck == false) then
				--we moved, that means the player is on a slope and can free fall
				on_ground_result = nil
			else
				--we didn't move, it means the ground we're on is sloped, but we can't fall any further
				--treat it like flat ground
				on_ground_result.normal = Vector3.new(0,1,0)
			end
		else
			on_ground_result = nil
		end
	end

	--Create flat velocity to operate our input command on
	--In theory this should be relative to the ground plane instead...
	local flat_vel = MathUtils.FlatVector(char_simdata.velocity)

	--Mark if we were onground at the start of the frame
	char_simdata.started_on_ground = on_ground_result
		
	--Simplify - whatever we are at the start of the frame goes.
	char_simdata.last_ground = on_ground_result

	 --Did the player have a movement request?
	 local direction_wish: Vector3
	 if movement_dir.X ~= 0 or movement_dir.Z ~= 0 then
		direction_wish = MathUtils.FlatVector(movement_dir).Unit
		char_simdata.push_direction = Vector2.new(movement_dir.X, movement_dir.Z)
	 else
		char_simdata.push_direction = Vector2.zero
	 end

	if direction_wish then
		if on_ground_result ~= nil then
			--Moving along the ground under player input
			flat_vel = MathUtils.GroundAccelerate(
				direction_wish,
				char_modifiers.walk_speed,
				40,
				flat_vel,
				delta_time
			)
		else
			--Moving through the air under player control
			flat_vel = MathUtils.Accelerate(direction_wish, char_modifiers.walk_speed, 10, flat_vel, delta_time)
		end
	else
		if on_ground_result ~= nil then
			--Just standing around
			flat_vel = MathUtils.VelocityFriction(flat_vel, 0.02, delta_time)
		end
	end

	--Turn out flatvel back into our vel
	char_simdata.velocity = Vector3.new(flat_vel.X, char_simdata.velocity.Y, flat_vel.Z)

	--Do jumping?
	if char_simdata.jump_debounce > 0 then
		char_simdata.jump_debounce -= delta_time
		if char_simdata.jump_debounce < 0 then
			char_simdata.jump_debounce = 0
		end
	end

	if on_ground_result ~= nil then
		--jump!
		if char_control_state.jump and char_simdata.jump_debounce <= 0 then
			char_simdata.velocity = Vector3.new(
				char_simdata.velocity.X,
				math.sqrt(char_modifiers.jump_height * (2 * char_modifiers.gravity)),
				char_simdata.velocity.Z
			)
			char_simdata.jump_debounce = 0.2 --jumping has a cooldown (think jumping up a staircase)
		end
	end

	--In air?
	if on_ground_result == nil then
		char_simdata.air_time += delta_time
		if char_simdata.air_time > 10 then
			char_simdata.air_time = 10 --Capped just to keep the state var reasonable
		end

		--Jump thrust
		if char_control_state.jump then
			if char_simdata.jump_thrust > 0 then
				char_simdata.velocity += Vector3.new(0, char_simdata.jump_thrust * delta_time, 0)
				char_simdata.jump_thrust = MathUtils.Friction(
					char_simdata.jump_thrust,
					0, -- jump thrust decay
					delta_time
				)
			end
			if char_simdata.jump_thrust < 0.001 then
				char_simdata.jump_thrust = 0
			end
		else
			char_simdata.jump_thrust = 0
		end

		--gravity
		char_simdata.velocity += Vector3.new(0, -char_modifiers.gravity * delta_time, 0)
	else
		char_simdata.air_time = 0
	end

	--Sweep the player through the world, once flat along the ground, and once "step up'd"
    local step_up_result = nil
    local new_walk_pos, new_walk_vel, hit_something = Collision.ProjectVelocity(char_simdata.position + hipheight_vect, char_simdata.velocity, delta_time)

    --Did we crashland
    if on_ground_result == nil and hit_something == true then
        --Land after jump
        local groundCheck = Collision.DoGroundCheck(new_walk_pos)

        if groundCheck ~= nil then
            --Crashland
			new_walk_vel = Collision.CrashLand(char_simdata.angle_yaw, new_walk_vel, groundCheck)
        end
    end
	
    -- Do we attempt a stepup? (not jumping!)
    if on_ground_result ~= nil and hit_something == true and char_simdata.jump_debounce == 0 then
        step_up_result = Collision.DoStepUp(max_slope_angle, char_simdata.position + hipheight_vect, char_simdata.velocity, delta_time)
    end

    --Choose which one to use, either the original move or the stepup
    if step_up_result ~= nil then
		char_simdata.step_up = step_up_result.step_distance
		char_simdata.position = step_up_result.position
		char_simdata.velocity = step_up_result.velocity
    else
		char_simdata.position = new_walk_pos
		char_simdata.velocity = new_walk_vel
    end

    --Do stepDown
    if true then
        if char_simdata.started_on_ground ~= nil and char_simdata.jump_debounce == 0 and char_simdata.velocity.Y <= 0 then
            local step_down_result = Collision.DoStepDown(max_slope_angle, char_simdata.position + hipheight_vect)

            if step_down_result ~= nil then
				char_simdata.step_up = step_down_result.step_distance
				char_simdata.position = step_down_result.position
            end
        end
    end
end

-- init
print("initializing movement server")
local _character = owner.Character
if not _character then
	_character = owner.CharacterAdded:Wait()
end

if _character then
	local humanoid = _character.Humanoid
	local root_part = _character.HumanoidRootPart

	humanoid.EvaluateStateMachine = false
	humanoid:ChangeState(Enum.HumanoidStateType.None)
	root_part.Anchored = true

	halonoid_data.simulation.position = root_part.Position
	_character.Parent = character_container
end

remote_registry.send_movement_state = {
	mode = "reliable",
	callback = function(sender: Player, state_buff: buffer)
		if sender.UserId ~= owner.UserId then
			return
		end
	
		decode_character_state(state_buff)
	end
}

print("creating remotes")
for remote_name, remote_config in remote_registry do
	local remote_obj: Instance & (RemoteEvent | UnreliableRemoteEvent)
	if remote_config.mode == "reliable" then
		remote_obj = Instance.new("RemoteEvent")
	elseif remote_config.mode == "unreliable" then
		remote_obj = Instance.new("UnreliableRemoteEvent")
	end

	remote_obj.Name = remote_name;
	(remote_obj.OnServerEvent::RBXScriptSignal):Connect(remote_config.callback);
	remote_obj.Parent = remotes_container;
	remotes[remote_name] = remote_obj
end
print("remotes loaded")

-- main
-- TODO: add state system for potential character animations

RunService.PostSimulation:Connect(function(delta_time)
	local control_cframe = CFrame.fromOrientation(0, halonoid_data.simulation.angle_yaw, 0)
	local control_lvec, control_rvec = control_cframe.LookVector, control_cframe.RightVector

	local movement_dir = get_movement_dir(control_lvec, control_rvec)

	simulate_halonoid(halonoid_data, movement_dir, delta_time)

	-- applying processed position
	_character:PivotTo(control_cframe + halonoid_data.simulation.position)
end)

-- post-init
print("fetching client script")
local client_script_raw = fetch_url("https://github.com/jLn0n/sb-scripts/blob/main/movement-system/client.luau?raw=true", true)
local client_script = NLS(client_script_raw or "error('client script failed to load!')", owner:FindFirstChildWhichIsA("PlayerGui"))
print("client ran")

remotes_container.Parent = client_script

script.Name = "movement_system"
client_script.Name = "movement_system_client"
client_script:SetAttribute("server_ready", true)
print("every process now done")

return nil
