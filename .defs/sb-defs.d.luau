type AssetLoader = {
    Get: (asset: string) -> Instance,
    Exists: (asset: string) -> boolean,
    GetNames: () -> {string},
    GetArray: () -> {Instance},
    GetDictionary: () -> {[string]: Instance}
}


declare owner: Player

declare function print<T...>(...: T...): ()
declare function warn<T...>(...: T...): ()
declare function error<T>(message: T, level: number?): never

declare function printf<T...>(...: T...): ()
declare function warnf<T...>(...: T...): ()

declare function LoadLibrary(library: string): (any)

declare function LoadAssets(id: number): (AssetLoader)

declare function NewScript(source: string, parent: Instance?, ...: any): (Script)
declare function NewLocalScript(source: string, parent: Instance?, ...: any): (LocalScript)

declare NS: typeof(NewScript)
declare NLS: typeof(NewLocalScript)
