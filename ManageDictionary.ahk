#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include Lib\All.ahk
if A_LineFile = A_ScriptFullPath {
try {
    EacManage(A_Args, EacConfig(A_ScriptDir))
    ExitApp 0
} catch as err {
    FileAppend err.Message "`n", "**"
    ExitApp 1
}
}

EacManage(args, config) {
    personal := EacUserDictionary(config.DataDirectory "\user.db", config.PromotionCount)
    if !personal.Enabled
        throw Error(personal.Fault)
    switch args[1] {
        case "--add", "--block", "--delete":
            if args.Length != 2 || !EacUserDictionary.Valid(args[2], true)
                throw Error("Specify one valid word")
            switch args[1] {
                case "--add":
                    if !personal.Observe(args[2], true)
                        throw Error("Registration refused; check block list or database")
                case "--block": personal.Block(args[2])
                case "--delete": personal.Delete(args[2])
            }
        case "--reset-frequency": personal.ResetFrequency()
        case "--reset-user": personal.Clear()
        default: throw Error("Unknown management command")
    }
}
