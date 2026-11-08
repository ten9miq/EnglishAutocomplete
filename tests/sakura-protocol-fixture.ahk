#Requires AutoHotkey v2.0+
#SingleInstance Off
; Hidden protocol receiver: never changes focus, documents, IMEs or settings.
if A_LineFile = A_ScriptFullPath {
    Mode := 0
    FixtureGui := Gui(, "EAC Sakura protocol fixture " DllCall("GetCurrentProcessId", "UInt"))
    OnMessage(0x117, UpdateMenu)
    OnMessage(0x8055, Echo)
    OnMessage(0x8056, SetMode)
    OnMessage(0x8057, (*) => ExitApp())
    FixtureGui.OnEvent("Close", (*) => ExitApp())
    Persistent
}

SetMode(modeValue, *) {
    global Mode
    Mode := modeValue
    return 1
}

UpdateMenu(menuHandle, *) {
    global Mode
    if Mode = 1 {
        DllCall "EnableMenuItem", "Ptr", menuHandle, "UInt", 30610, "UInt", 1
    } else if Mode = 2 {
        DllCall "EnableMenuItem", "Ptr", menuHandle, "UInt", 30245, "UInt", 1
    } else if Mode = 3 {
        DllCall "EnableMenuItem", "Ptr", menuHandle, "UInt", 30245, "UInt", 1
        DllCall "EnableMenuItem", "Ptr", menuHandle, "UInt", 30610, "UInt", 1
    }
    return 0
}

Echo(delay, value, *) {
    if delay
        Sleep delay
    return value
}
