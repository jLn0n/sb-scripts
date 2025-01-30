export type EventCommunicationMode = "reliable" | "unreliable"

export type ServerListener<T...> = (sender: Player, T...) -> ()
export type ClientListener<T...> = (T...) -> ()

export type ServerCallback<T...> = (sender: Player, T...) -> (...any)
export type ClientCallback<T...> = (T...) -> (...any)

export type EventPacket = {
    targets: {Player}?,
    args: {any},
}

type FunctionPacket = {
    callback_id: number,
    args: {any},
}

export type OutcomingFunctionPacket = FunctionPacket & {
    target: Player?,
}

export type IncomingFunctionPacket = FunctionPacket & {
    sender: Player?,
}

export type CommonFunctionInternal = {
    callback: ClientCallback<...any>,

    incoming_packets: {IncomingFunctionPacket},
    outcoming_packets: {OutcomingFunctionPacket},
}

export type CommonEventInternal = {
    incoming_packets: {EventPacket},
    outcoming_packets: {EventPacket},
}

return nil