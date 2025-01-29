export type CommunicationMode = "reliable" | "unreliable"

export type ServerListener<T...> = (sender: Player, T...) -> ()
export type ClientListener<T...> = (T...) -> ()

export type ServerOutcomingPacket = {
    targets: {Player},
    args: {any},
}
export type ServerIncomingPacket = {any}

export type ClientOutcomingPacket = {
    args: {any},
}
export type ClientIncomingPacket = {any}

return nil