export type CommunicationType = "reliable" | "unreliable"

export type ServerListener<T...> = (sender: Player, T...) -> ()
export type ClientListener<T...> = (T...) -> ()

export type ServerCallback<T...> = (sender: Player, T...) -> (...any)
export type ClientCallback<T...> = (T...) -> (...any)

type CommonPacket = {
	type: CommunicationType,
	id: string,
	args: {any},
}

export type IncomingPacket = CommonPacket & {
	sender: Player?
}

export type OutcomingPacket = CommonPacket & {
	targets: {Player}?
}

-- PROBABLY INTERNAL --

export type RemoteRegistry = {
	reliable: RemoteEvent,
	unreliable: UnreliableRemoteEvent,
}

export type InternalRemoteHandler = (remote_registry: RemoteRegistry) -> (boolean)

export type CommuniceptionConfiguration = {
	INCOMING_PACKET_THRESHOLD: number,
	OUTCOMING_PACKET_THRESHOLD: number,

	INTERNAL_REMOTE_HANDLER: InternalRemoteHandler
}

return nil