export type EventCommunicationMode = "reliable" | "unreliable"

export type ServerListener<T...> = (sender: Player, T...) -> ()
export type ClientListener<T...> = (T...) -> ()

export type ServerCallback<T...> = (sender: Player, T...) -> (...any)
export type ClientCallback<T...> = (T...) -> (...any)

export type OutcomingFunctionPacket = {
    callback_id: number,
    target: Player?,
    args: {any},
}

export type IncomingFunctionPacket = {
    callback_id: number,
    sender: Player?,
    args: {any},
}

export type EventPacket = {
    targets: {Player}?,
    args: {any},
}

return nil