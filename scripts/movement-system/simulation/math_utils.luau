local module = {}

function module.FlatVector(vect3: Vector3): Vector3
	return Vector3.new(vect3.X, 0, vect3.Z)
end

--dt variable decay function
function module.Friction(value: number, friction: number, delta_time: number): number
	return (1 / (1 + (delta_time / friction))) * value
end

function module.VelocityFriction(velocity: Vector3, friction: number, delta_time: number): Vector3
	local speed = velocity.Magnitude
	speed = module.Friction(speed, friction, delta_time)

	if speed < 0.001 then
		return Vector3.new(0, 0, 0)
	end
	velocity = velocity.Unit * speed

	return velocity
end

function module.ClipVelocity(input: Vector3, normal: Vector3, overbounce: number): Vector3
	local backoff = input:Dot(normal)

	if backoff < 0 then
		backoff = backoff * overbounce
	else
		backoff = backoff / overbounce
	end

	local changex = normal.X * backoff
	local changey = normal.Y * backoff
	local changez = normal.Z * backoff

	return Vector3.new(input.X - changex, input.Y - changey, input.Z - changez)
end

function module.GroundAccelerate(
	direction: Vector3,
	speed: number,
	acceleration: number,
	velocity: Vector3,
	delta_time: number
): Vector3
	--Cap velocity
	local vel_speed = velocity.Magnitude
	if vel_speed > speed then
		velocity = velocity.Unit * speed
	end

	local wish_vel = direction * speed
	local push_dir = wish_vel - velocity

	local push_dist = push_dir.Magnitude

	local can_push = acceleration * delta_time * speed

	if can_push > push_dist then
		can_push = push_dist
	end
	if can_push < 0.00001 then
		return velocity
	end
	return velocity + (can_push * push_dir.Unit)
end

function module.Accelerate(
	direction: Vector3,
	speed: number,
	acceleration: number,
	velocity: Vector3,
	delta_time: number
): Vector3
	local vel_speed = velocity.Magnitude

	local current_speed = velocity:Dot(direction)
	local added_speed = speed - current_speed

	if added_speed <= 0 then
		return velocity
	end

	local accel_speed = acceleration * delta_time * speed
	if accel_speed > added_speed then
		accel_speed = added_speed
	end

	velocity = velocity + (accel_speed * direction)

	--if we're already going over max speed, don't go any faster than that
	--Or you'll get strafe jumping!
	if vel_speed > speed and velocity.Magnitude > vel_speed then
		velocity = velocity.Unit * vel_speed
	end
	return velocity
end

return module
