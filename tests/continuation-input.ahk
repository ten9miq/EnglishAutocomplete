#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Fixed two-key (or Enter-only) input, never a general input command server.
if A_Args.Length != 5
    ExitApp 1
target := Integer(A_Args[1]), ownerPid := Integer(A_Args[2]), editHwnd := Integer(A_Args[3])
resultPath := A_Args[4], mode := A_Args[5]
InstallKeybdHook()
InstallMouseHook()
physicalAt := A_TickCount - A_TimeIdlePhysical
try {
    if mode != "tab-enter" && mode != "enter"
        throw Error("Unsupported test input")
    SetKeyDelay 5, 5
    if mode = "tab-enter" {
        Guard()
        SendLevel 1
        SendEvent "{Tab}"
    }
    Guard()
    SendLevel 1
    SendEvent "{Enter}"
    FileAppend "PASS", resultPath, "UTF-8"
    ExitApp 0
} catch as err {
    FileAppend "FAIL " err.Message, resultPath, "UTF-8"
    ExitApp 1
}
Guard() {
    global target, ownerPid, editHwnd, physicalAt
    context := EacFieldGuard.Context()
    if !context || context.Hwnd != target || context.Focus != editHwnd
        throw Error("Disposable input focus mismatch")
    if WinGetPID("ahk_id " target) != ownerPid
        throw Error("Disposable input PID mismatch")
    if A_TickCount - A_TimeIdlePhysical > physicalAt + 32
        throw Error("Physical input detected")
}
