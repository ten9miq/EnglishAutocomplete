#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Real InputHook/hotkey events, sent only to our fresh external native Edit.
InstallKeybdHook()
InstallMouseHook()
CoordMode "Mouse", "Screen"
MouseGetPos &OriginalMouseX, &OriginalMouseY
Root := A_ScriptDir "\.."
Checks := 0
App := false
FixtureHwnd := 0
FixturePid := 0
EditHwnd := 0
EnterHeld := false
DeleteHeld := false
PreviousWindow := WinExist("A")
PreviousLayout := DllCall("GetKeyboardLayout", "UInt", 0, "Ptr")
PhysicalInputAt := A_TickCount - A_TimeIdlePhysical
StartedAt := A_TickCount
DirCreate A_ScriptDir "\results"
ResultFile := A_ScriptDir "\results\forget-integration.txt"
if FileExist(ResultFile)
    FileDelete ResultFile
OnError Fail
OnExit Cleanup

SettingsPath := A_ScriptDir "\results\forget-integration.ini"
FileCopy Root "\settings.default.ini", SettingsPath, true
TestDirectory := A_ScriptDir "\results\forget-user-" DllCall("GetCurrentProcessId", "UInt")
IniWrite TestDirectory, SettingsPath, "General", "DataDirectory"
IniWrite 0, SettingsPath, "General", "Learning"
IniWrite 0, SettingsPath, "General", "Debug"
IniWrite 1, SettingsPath, "app:AutoHotkey64.exe", "Enabled"
IniWrite 0, SettingsPath, "app:AutoHotkey64.exe", "Learning"
Settings := EacConfig(Root, SettingsPath)
App := SelectionTestApplication(Settings, false)
App.Start(true)
Run '"' A_AhkPath '" "' A_ScriptDir '\fixture.ahk"', , , &FixturePid
FixtureHwnd := WinWait("EnglishAutocomplete disposable test fixture ahk_pid " FixturePid, , 3)
Assert(FixtureHwnd, "fresh external fixture started")
EditHwnd := ControlGetHwnd("Edit1", "ahk_id " FixtureHwnd)
if A_Args.Length && A_Args[1] = "--wait-foreground" {
    if !WinWaitActive("ahk_id " FixtureHwnd, , 120)
        throw Error("Waiting for user to focus disposable fixture timed out; no input sent")
    Sleep 200
    PhysicalInputAt := A_TickCount - A_TimeIdlePhysical
}
if WinExist("A") != FixtureHwnd
    throw Error("Fixture did not obtain foreground; abort input")
ControlFocus EditHwnd
Sleep 80
SetTimer Timeout, -10000
Guard()
Assert(App.Ime.GetState(EacFieldGuard.Context()).Allowed, "real ENG layout allowed")
SetKeyDelay 5, 5

; Seed only the isolated fixture DB. Never change the live personal dictionary.
App.User.Observe("ForgetFixtureWord"), App.User.Observe("ForgetFixtureWord")
App.User.Observe("ClickFixtureWord"), App.User.Observe("ClickFixtureWord")
Prepare()
TypeFixture("forgetfixture")
Assert(App.Visible && App.Selected = 0, "learned preview starts unselected")
Assert(!App.Gui.DeleteControl.Visible, "unselected preview has no delete cross")
SendFixture "{Tab}"
Sleep 40
Assert(App.Selected = 1 && App.Gui.DeleteControl.Visible, "selected learned row displays cross")
expected := Value()
DeleteHeld := true
SendFixture "{Ctrl down}{Delete down}"
Sleep 70
Assert(Value() == expected && !App.Visible, "Ctrl Delete removes learned candidate without changing input")
Assert(!App.User.Db.Query("SELECT norm FROM personal WHERE norm='forgetfixtureword'").Length, "real Ctrl Delete removes stored history")
loop 2 {
    SendFixture "{Delete down}"
    Sleep 30
    Assert(Value() == expected, "held Ctrl Delete does not erase input " A_Index)
}
SendFixture "{Delete up}{Ctrl up}"
DeleteHeld := false
Sleep 30
Assert(!App.DeleteLatched, "Delete key-up releases repeat guard")

Prepare()
TypeFixture("clickfixture")
SendFixture "{Tab}"
Sleep 40
Assert(App.Gui.DeleteControl.Visible, "second selected learned candidate displays cross")
rect := Buffer(16, 0)
DllCall "GetWindowRect", "Ptr", App.Gui.DeleteControl.Hwnd, "Ptr", rect
x := (NumGet(rect, 0, "Int") + NumGet(rect, 8, "Int")) // 2
y := (NumGet(rect, 4, "Int") + NumGet(rect, 12, "Int")) // 2
Guard()
MouseMove x, y, 0
Assert(App.Gui.DeleteAtPointer() = App.Items[1], "pointer hit-test identifies displayed learned row")
SendLevel 1
Click
Sleep 100
Guard()
Assert(Value() == "clickfixture", "cross click preserves original input and focus")
Assert(!App.User.Db.Query("SELECT norm FROM personal WHERE norm='clickfixtureword'").Length, "real cross click removes stored history")
Assert(!App.Visible && !App.Selected, "deleted unknown hides list and clears selection")

App.User.Observe("confidence")
Prepare()
TypeFixture("confidenc")
SendFixture "{Tab}"
Sleep 30
Assert(App.Items[1].Norm = "confidence" && App.Gui.DeleteControl.Visible, "known learned word has delete cross")
SendFixture "^{Delete}"
Sleep 100
Assert(Value() == "confidenc" && App.Visible && App.Selected = 0, "known history removal leaves preview with no text change")
Assert(App.Items[1].Norm = "confidence" && !App.Items[1].Learned && !App.Gui.DeleteControl.Visible,
    "base dictionary word survives and loses cross")
SendFixture "{Tab}"
Sleep 30
Assert(!App.Gui.DeleteControl.Visible, "selecting base-only word has no cross")

App.User.Observe("ManualFixtureWord", true)
Prepare()
TypeFixture("manualfixture")
SendFixture "{Tab}"
Sleep 30
Assert(!App.Gui.DeleteControl.Visible && !App.SelectedLearned(), "manual entry has no delete affordance")
Guard()
Record("PASS forget_integration_checks=" Checks " elapsed_ms=" (A_TickCount - StartedAt)
    " AHK=" A_AhkVersion " real_OnChar=true real_hotkeys=true native_multiline_Edit=true")
Cleanup()
ExitApp 0

AssertUnselected() {
    global App
    Assert(App.Tracker.Word == "confi" && App.Observed == "confi", "actual OnChar captures confi")
    Assert(App.Visible && App.Items.Length == 9 && App.Gui.LastLayout.Rows = 5, "nine available candidates start as five displayed rows")
    Assert(App.Selected == 0 && !App.Navigating, "candidates initially unselected")
    Assert(App.Gui.Numbers[1].Text == "1", "unselected row has a separate number gutter")
}

Prepare() {
    global App, EditHwnd
    Guard()
    App.Reset()
    App.Observed := ""
    ControlSetText "", EditHwnd
    Sleep 20
}

Guard() {
    global FixtureHwnd, FixturePid, EditHwnd, PhysicalInputAt
    if !FixtureHwnd || !EditHwnd || WinExist("A") != FixtureHwnd
        || WinGetPID("ahk_id " FixtureHwnd) != FixturePid
        throw Error("Fixture lost foreground; abort input")
    context := EacFieldGuard.Context()
    if !context || context.Hwnd != FixtureHwnd || context.Focus != EditHwnd
        throw Error("Fixture lost Edit1 focus; abort input")
    ; Physical keyboard/mouse activity aborts the remaining synthetic sequence.
    ; Allow the tick granularity of A_TimeIdlePhysical when comparing timestamps.
    if A_TickCount - A_TimeIdlePhysical > PhysicalInputAt + 32
        throw Error("Physical user input detected; abort input")
}

TypeFixture(text) {
    global App
    loop parse text {
        Guard()
        SendLevel 1
        SendEvent "{Raw}" A_LoopField
    }
    deadline := A_TickCount + 700
    while (!App.Visible || App.Tracker.Word != text) && A_TickCount < deadline {
        Guard()
        Sleep 10
    }
    Guard()
}

SendFixture(keys) {
    Guard()
    SendLevel 1
    SendEvent keys
}

ReleaseEnter() {
    global EnterHeld, FixtureHwnd, FixturePid, EditHwnd
    if !EnterHeld
        return
    EnterHeld := false
    ; Cleanup must not inject a key-up into an unrelated foreground window.
    context := EacFieldGuard.Context()
    if FixtureHwnd && WinExist("A") == FixtureHwnd
        && WinGetPID("ahk_id " FixtureHwnd) == FixturePid
        && context && context.Hwnd == FixtureHwnd && context.Focus == EditHwnd {
        SendLevel 1
        SendEvent "{Enter up}"
    }
}

Value() {
    global EditHwnd
    Guard()
    return StrReplace(ControlGetText(EditHwnd), "`r`n", "`n")
}

ReleaseDelete() {
    global DeleteHeld, FixtureHwnd, FixturePid, EditHwnd
    if !DeleteHeld
        return
    DeleteHeld := false
    context := EacFieldGuard.Context()
    if FixtureHwnd && WinExist("A") == FixtureHwnd
        && WinGetPID("ahk_id " FixtureHwnd) == FixturePid
        && context && context.Hwnd == FixtureHwnd && context.Focus == EditHwnd {
        SendLevel 1
        SendEvent "{Delete up}{Ctrl up}"
    }
}

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
    Record("PASS " description)
}

Record(message) {
    global ResultFile
    FileAppend message "`n", ResultFile, "UTF-8"
    FileAppend message "`n", "*", "UTF-8"
}

Timeout() => Fail(Error("Selection integration exceeded ten seconds; abort input"))

Fail(err, *) {
    global App
    if App
        Record("STATE selected=" App.Selected " navigating=" App.Navigating
            " visible=" App.Visible " commits=" App.CommitCount " fault=" App.Fault)
    Record("FAIL " err.Message " at " err.File ":" err.Line "`n" err.Stack)
    Cleanup()
    ExitApp 1
}

Cleanup(*) {
    global App, FixtureHwnd, FixturePid, PreviousLayout, PreviousWindow, TestDirectory, OriginalMouseX, OriginalMouseY, PhysicalInputAt
    SetTimer Timeout, 0
    if A_TickCount - A_TimeIdlePhysical <= PhysicalInputAt + 32
        MouseMove OriginalMouseX, OriginalMouseY, 0
    ReleaseEnter()
    ReleaseDelete()
    if App {
        App.Stop()
        App.User.Db.Close()
        App.Engine.Db.Close()
        App := false
    }
    if FixtureHwnd && WinExist("ahk_id " FixtureHwnd)
        && WinGetPID("ahk_id " FixtureHwnd) == FixturePid {
        try WinClose "ahk_id " FixtureHwnd
        FixtureHwnd := 0
    }
    DllCall "ActivateKeyboardLayout", "Ptr", PreviousLayout, "UInt", 0
    if PreviousWindow && WinExist("ahk_id " PreviousWindow)
        try WinActivate "ahk_id " PreviousWindow
    if IsSet(TestDirectory) && DirExist(TestDirectory) {
        for suffix in ["", "-journal", "-wal", "-shm"]
            if FileExist(TestDirectory "\user.db" suffix)
                try FileDelete TestDirectory "\user.db" suffix
        try DirDelete TestDirectory
    }
}

class SelectionTestApplication extends EacApplication {
    Observed := ""
    OnChar(hook, text) {
        this.Observed .= text
        super.OnChar(hook, text)
    }
}
