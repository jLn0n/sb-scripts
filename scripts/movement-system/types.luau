local SimulationTypes = require("./simulation/types")

export type HalonoidControlState = {
    forward: boolean,
    backward: boolean,
    leftward: boolean,
    rightward: boolean,
    jump: boolean
}

export type HalonoidModifiers = {
    gravity: number,
    walk_speed: number,
    jump_height: number,
    step_size: number,
    max_slope_angle: number,
}

export type HalonoidSimulationData = {
    angle_yaw: number,
    position: Vector3,
    velocity: Vector3,
    push_direction: Vector2,

    step_up: number,
    air_time: number,

    jump_debounce: number,
    jump_thrust: number,

    started_on_ground: SimulationTypes.CollisionResult?,
    ground_state: SimulationTypes.CollisionResult?,
    last_ground: SimulationTypes.CollisionResult?
}

export type HalonoidData = {
    modifiers: HalonoidModifiers,
    pressed_controls: HalonoidControlState,
    simulation: HalonoidSimulationData
}

return nil