local RunService = game:GetService("RunService")

local remotes_container = Instance.new("Folder")
remotes_container.Name = "remotes"

local character_container = Instance.new("WorldModel")
character_container.Name = "character store thing"
character_container.Parent = script

local gist_loader = require("@shared/gist-loader")
local communiception = require("@shared/communiception/server")

local types = require("./types")
local Collision = require("./simulation/collision")
local MathUtils = require("./simulation/math_utils")

local MOVEMENT_ORDER = {
	"forward",
	"backward",
	"leftward",
	"rightward",
	"jump"
}

local send_movement_state = communiception.newEvent("send_movement_state", "unreliable")
local thingamajig = communiception.newFunction("thingamajig")

local halonoid_data: types.HalonoidData = {
	modifiers = {
		gravity = 196.2,
		walk_speed = 16,
		jump_height = 7.6,
		step_size = 2,
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
	local control_state = halonoid_data.pressed_controls
	local simulation_data = halonoid_data.simulation
	local modifiers = halonoid_data.modifiers

	-- converts degrees angle to normal y point
	local max_slope_angle = math.cos(math.rad(math.clamp(modifiers.max_slope_angle, 0, 90)))

	local on_ground_result = Collision.DoGroundCheck(simulation_data.position)

	--If the player is on too steep a slope, its not ground
	if (on_ground_result and on_ground_result.normal.Y < max_slope_angle) then
		--See if we can move downwards?
		if (simulation_data.velocity.Y < 0.1) then
			local stuck = Collision.CheckGroundSlopes(simulation_data.position)
			
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
	local flat_vel = MathUtils.FlatVector(simulation_data.velocity)

	--Mark if we were onground at the start of the frame
	simulation_data.started_on_ground = on_ground_result
		
	--Simplify - whatever we are at the start of the frame goes.
	simulation_data.last_ground = on_ground_result

	 --Did the player have a movement request?
	 local direction_wish: Vector3
	 if movement_dir.Magnitude > 0 then
		direction_wish = MathUtils.FlatVector(movement_dir).Unit
		simulation_data.push_direction = Vector2.new(movement_dir.X, movement_dir.Z)
	 else
		simulation_data.push_direction = Vector2.zero
	 end

	if direction_wish then
		if on_ground_result then
			--Moving along the ground under player input
			flat_vel = MathUtils.GroundAccelerate(
				direction_wish,
				modifiers.walk_speed,
				40,
				flat_vel,
				delta_time
			)
		else
			--Moving through the air under player control
			flat_vel = MathUtils.Accelerate(direction_wish, modifiers.walk_speed, 10, flat_vel, delta_time)
		end
	else
		if on_ground_result then
			--Just standing around
			flat_vel = MathUtils.VelocityFriction(flat_vel, 0.02, delta_time)
		end
	end

	--Turn out flatvel back into our vel
	simulation_data.velocity = Vector3.new(flat_vel.X, simulation_data.velocity.Y, flat_vel.Z)

	--Do jumping?
	if simulation_data.jump_debounce > 0 then
		simulation_data.jump_debounce -= delta_time
		if simulation_data.jump_debounce < 0 then
			simulation_data.jump_debounce = 0
		end
	end

	if on_ground_result then
		--jump!
		if control_state.jump and simulation_data.jump_debounce <= 0 then
			simulation_data.velocity = Vector3.new(
				simulation_data.velocity.X,
				math.sqrt(modifiers.jump_height * (2 * modifiers.gravity)),
				simulation_data.velocity.Z
			)
			simulation_data.jump_debounce = 0.2 --jumping has a cooldown (think jumping up a staircase)
		end
	end

	--In air?
	if not on_ground_result then
		simulation_data.air_time += delta_time
		if simulation_data.air_time > 10 then
			simulation_data.air_time = 10 --Capped just to keep the state var reasonable
		end

		--Jump thrust
		if control_state.jump then
			if simulation_data.jump_thrust > 0 then
				simulation_data.velocity += Vector3.new(0, simulation_data.jump_thrust * delta_time, 0)
				simulation_data.jump_thrust = MathUtils.Friction(
					simulation_data.jump_thrust,
					0, -- jump thrust decay
					delta_time
				)
			end
			if simulation_data.jump_thrust < 0.001 then
				simulation_data.jump_thrust = 0
			end
		else
			simulation_data.jump_thrust = 0
		end

		--gravity
		simulation_data.velocity += Vector3.new(0, -modifiers.gravity * delta_time, 0)
	else
		simulation_data.air_time = 0
	end

	--Sweep the player through the world, once flat along the ground, and once "step up'd"
    local step_up_result = nil
    local new_walk_pos, new_walk_vel, hit_something = Collision.ProjectVelocity(simulation_data.position, simulation_data.velocity, delta_time)

    --Did we crashland
    if (not on_ground_result) and hit_something then
        --Land after jump
        local groundCheck = Collision.DoGroundCheck(new_walk_pos)

        if groundCheck then
            --Crashland
			new_walk_vel = Collision.CrashLand(simulation_data.angle_yaw, new_walk_vel, groundCheck)
        end
    end
	
    -- Do we attempt a stepup? (not jumping!)
    if on_ground_result and hit_something and simulation_data.jump_debounce <= 0.01 then
        step_up_result = Collision.DoStepUp(modifiers.step_size,max_slope_angle, simulation_data.position, simulation_data.velocity, delta_time)
    end

    --Choose which one to use, either the original move or the stepup
    if step_up_result then
		simulation_data.step_up = step_up_result.step_distance
		simulation_data.position = step_up_result.position
		simulation_data.velocity = step_up_result.velocity
    else
		simulation_data.position = new_walk_pos
		simulation_data.velocity = new_walk_vel
    end

    --Do stepDown
	if simulation_data.started_on_ground and simulation_data.jump_debounce <= 0.01 and simulation_data.velocity.Y <= 0 then
		local step_down_result = Collision.DoStepDown(
			modifiers.step_size,
			max_slope_angle,
			simulation_data.position
		)

		if step_down_result then
			simulation_data.step_up = step_down_result.step_distance
			simulation_data.position = step_down_result.position
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

print("initializing communiception & registering remotes")
communiception.initialize()

send_movement_state:listen(function(sender: Player, state_buff: buffer)
	if owner.UserId ~= sender.UserId then
		return
	end

	decode_character_state(state_buff)
end)

thingamajig:setListener(function(sender: Player, ...: any): ...any
	if owner.UserId ~= sender.UserId then
		return
	end

	print("thingamajig fired,", ...)
	return "im a test"
end)

print("remotes shenanigans done")

-- main
-- TODO: add state system for potential character animations

RunService.PostSimulation:Connect(function(delta_time)
	local control_cframe = CFrame.fromOrientation(0, halonoid_data.simulation.angle_yaw, 0)
	local control_lvec, control_rvec = control_cframe.LookVector, control_cframe.RightVector

	local movement_dir = get_movement_dir(control_lvec, control_rvec)

	simulate_halonoid(halonoid_data, movement_dir, delta_time)

	-- applying processed position
	_character:PivotTo(control_cframe + halonoid_data.simulation.position + Vector3.new(0, 2, 0))
end)

-- post-init
print("fetching client script")
-- TODO: specify gist commit for the version where it got build
local gist_obj = gist_loader("fe59b29cb2d0d6a26273a892dcfd104a")
local client_script_raw = gist_obj.fetch("client.luau", true)
local client_script = NLS(client_script_raw or "error('client script failed to load!')", owner:FindFirstChildWhichIsA("PlayerGui"))
print("client ran")

remotes_container.Parent = client_script

script.Name = "movement_system"
client_script.Name = "movement_system_client"
client_script:SetAttribute("server_ready", true)
print("every process now done")

return nil
