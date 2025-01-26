export type CollisionResult = {
	start_pos: Vector3,
	end_pos: Vector3,
	normal: Vector3,
	fraction: number,

	start_solid: boolean,
	all_solid: boolean,
}

export type StepUpResult = {
    step_distance: number,
    position: Vector3,
    velocity: Vector3
}

export type StepDownResult = {
    step_distance: number,
    position: Vector3,
}

return nil