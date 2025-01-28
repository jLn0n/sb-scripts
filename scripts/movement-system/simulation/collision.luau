local types = require("@movement-system/simulation/types")
local MathUtils = require("@movement-system/simulation/math_utils")

local COLLISION_SHIFTBACK = 1
local COLLISION_SIZE = Vector3.new(3, 5, 3)

local COLLISION_CASTPARAMS = RaycastParams.new()
COLLISION_CASTPARAMS.RespectCanCollide = true
COLLISION_CASTPARAMS.IgnoreWater = true

local module = {}

function module.Sweep(start_pos: Vector3, end_pos: Vector3): types.CollisionResult
	local data: types.CollisionResult = {
		start_pos = start_pos,
		end_pos = end_pos,
		normal = Vector3.new(0, 1, 0),
		fraction = 1,

		start_solid = false,
		all_solid = false,
	}

	local offset = (end_pos - start_pos)
	local distance = offset.Magnitude
	if not (distance >= 0 and distance <= 1024) then
		return data
	end
	
	local direction = offset.Unit
	local cast_origin = start_pos - (direction * COLLISION_SHIFTBACK)
	local ray_result = workspace:Blockcast(
		CFrame.identity + (cast_origin),
		COLLISION_SIZE,
		direction * (distance + COLLISION_SHIFTBACK),
        COLLISION_CASTPARAMS
	)

	if ray_result then
		data.fraction = (ray_result.Distance - COLLISION_SHIFTBACK) / direction.Magnitude
		data.normal = ray_result.Normal
		data.end_pos = cast_origin + (direction.Unit * ray_result.Distance)
		data.all_solid = data.start_solid and data.fraction < 0.001
	end
	return data
end

function module.ProjectVelocity(start_pos: Vector3, start_vel: Vector3, delta_time: number): (Vector3, Vector3, boolean)
	local move_position = start_pos
    local move_velocity = start_vel
    local hit_something = false

    --Project our movement through the world
    local planes = {}
    local time_left = delta_time

    for _ = 0, 3 do
        if move_velocity.Magnitude < 0.001 then
            --done
            break
        end

        if move_velocity:Dot(start_vel) < 0 then
            --we projected back in the opposite direction from where we started. No.
			move_velocity = Vector3.new(0, 0, 0)
            break
        end

        --We only operate on a scaled down version of velocity
        local result = module.Sweep(move_position, move_position + (move_velocity * time_left))

        --Update our position
        if result.fraction > 0 then
            move_position = result.end_pos
        end

        --See if we swept the whole way?
        if result.fraction == 1 then
            break
        end

        if result.fraction < 1 then
            hit_something = true
        end

        if result.all_solid then
            --all solid, don't do anything
            --(this doesn't mean we wont project along a normal!)
            move_velocity = Vector3.new(0, 0, 0)
            break
        end

        --Hit!
        time_left -= (time_left * result.fraction)

        if not planes[result.normal] then
            planes[result.normal] = true

            --Deflect the velocity and keep going
            move_velocity = MathUtils.ClipVelocity(move_velocity, result.normal, 1.0)
        else
            --We hit the same plane twice, push off it a bit
            move_position += result.normal * 0.01
            move_velocity += result.normal
            break
        end
    end

	table.clear(planes)
    return move_position, move_velocity, hit_something
end

function module.DoGroundCheck(position: Vector3): types.CollisionResult?
    local results = module.Sweep(position + Vector3.new(0, 0.1, 0), position + Vector3.new(0, -0.1, 0))

    if results.all_solid or results.start_solid then
        --We're stuck, pretend we're in the air

        results.fraction = 1
        return results
    end

    if results.fraction < 1 then
        return results
    end
    return nil
end

function module.CheckGroundSlopes(start_pos: Vector3): boolean
    local move_pos = start_pos
	local move_dir = Vector3.new(0, -1, 0)
	
	--We only operate on a scaled down version of velocity
	local result = module.Sweep(move_pos, move_pos + move_dir)

	--Update our position
	if result.fraction > 0 then
		move_pos = result.end_pos
	end
	--See if we swept the whole way?
	if result.fraction == 1 then
		return false
	end
	
	if result.all_solid then
		return true --stuck
	end
	
	move_dir = MathUtils.ClipVelocity(move_dir, result.normal, 1.0)
	if (move_dir.Magnitude < 0.001) then
		return true --stuck
	end
	
	--Try and move it
	result = module.Sweep(move_pos, move_pos + move_dir)
	if (result.fraction == 0) then
		return true --stuck
	end
	
	--Not stuck
	return false	
end

function module.CrashLand(angle: number, velocity: Vector3, ground: types.CollisionResult): Vector3
    local flat = Vector3.new(ground.normal.X, 0, ground.normal.Z).Unit
    local forward = Vector3.new(math.sin(angle), 0, math.cos(angle)) --MathUtils:PlayerAngleToVec(self.state.angle)

    if (forward:Dot(flat) < 0) then --bhop forward if the slope is the way we're facing
        return velocity
    end

    --else stop
    return Vector3.new(0, 0, 0)
end

function module.DoStepUp(step_size: number, max_slope: number, position: Vector3, velocity: Vector3, delta_time: number): types.StepUpResult?
    local flat_velocity = MathUtils.FlatVector(velocity)

    local step_vect = Vector3.new(0, step_size, 0)
    --first move upwards as high as we can go

    local collision_head_hit = module.Sweep(position, position + step_vect)

    --Project forwards
    local step_up_new_pos, step_up_new_vel = module.ProjectVelocity(collision_head_hit.end_pos, flat_velocity, delta_time)

    --Trace back down
    local trace_down_pos = step_up_new_pos
    local hit_result = module.Sweep(trace_down_pos, trace_down_pos - step_vect)

    step_up_new_pos = hit_result.end_pos

    --See if we're mostly on the ground after this? otherwise rewind it
    local ground = module.DoGroundCheck(step_up_new_pos)

    --Slope check
    if ground then
        if ground.normal.Y < max_slope or ground.start_solid == true then
            return nil
        end
    end

    if ground then
        return {
            step_distance = position.Y - step_up_new_pos.Y,
            position = step_up_new_pos,
            velocity = step_up_new_vel,
        }
    end
    return nil
end

function module.DoStepDown(step_size: number, max_slope: number, position: Vector3): types.StepDownResult?
    local step_vect = Vector3.new(0, step_size, 0)
    local hit_result = module.Sweep(position, position - step_vect)

    if
        not hit_result.start_solid and
        hit_result.fraction < 1 and
        hit_result.normal.Y >= max_slope
    then
        local delta = position.Y - hit_result.end_pos.Y

        if delta > 0.001 then
            return {
                step_distance = delta,
                position = hit_result.end_pos
            }
        end
    end
    return nil
end

return module
