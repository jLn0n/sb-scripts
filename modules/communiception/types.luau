export type EventCommunicationMode = "reliable" | "unreliable"

export type ServerListener<T...> = (sender: Player, T...) -> ()
export type ClientListener<T...> = (T...) -> ()

export type ServerCallback<T...> = (sender: Player, T...) -> (...any)
export type ClientCallback<T...> = (T...) -> (...any)

type CommonPacket = {
    type: "reliable" | "unreliable",
    id: string,
    args: {any},
}

export type IncomingPacket = CommonPacket & {
    sender: Player?
}

export type OutcomingPacket = CommonPacket & {
    targets: {Player}?
}

return nil