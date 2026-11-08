#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Real InputHook/hotkey events, sent only to our fresh external native Edit.
InstallKeybdHook()
InstallMouseHook()
Root := A_ScriptDir "\.."
Checks := 0
App := false
FixtureHwnd := 0
FixturePid := 0
EditHwnd := 0
EnterHeld := false
PreviousWindow := WinExist("A")
PreviousLayout := DllCall("GetKeyboardLayout", "UInt", 0, "Ptr")
PhysicalInputAt := A_TickCount - A_TimeIdlePhysical
StartedAt := A_TickCount
DirCreate A_ScriptDir "\results"
ResultFile := A_ScriptDir "\results\selection-integration.txt"
if FileExist(ResultFile)
    FileDelete ResultFile
OnError Fail
OnExit Cleanup
SetTimer Timeout, -7000

SettingsPath := A_ScriptDir "\results\selection-integration.ini"
FileCopy Root "\settings.default.ini", SettingsPath, true
TestDirectory := A_ScriptDir "\results\selection-user-" DllCall("GetCurrentProcessId", "UInt")
IniWrite TestDirectory, SettingsPath, "General", "DataDirectory"
IniWrite 0, SettingsPath, "General", "Learning"
IniWrite 0, SettingsPath, "General", "Debug"
IniWrite 1, SettingsPath, "app:AutoHotkey64.exe", "Enabled"
IniWrite 0, SettingsPath, "app:AutoHotkey64.exe", "Learning"
Settings := EacConfig(Root, SettingsPath)
App := SelectionTestApplication(Settings, false)
App.Start(false)
Run '"' A_AhkPath '" "' A_ScriptDir '\fixture.ahk"', , , &FixturePid
FixtureHwnd := WinWait("EnglishAutocomplete disposable test fixture ahk_pid " FixturePid, , 3)
Assert(FixtureHwnd, "fresh external fixture started")
EditHwnd := ControlGetHwnd("Edit1", "ahk_id " FixtureHwnd)
if WinExist("A") != FixtureHwnd
    throw Error("Fixture did not obtain foreground; abort input")
ControlFocus EditHwnd
Sleep 80
Guard()
Assert(App.Ime.GetState(EacFieldGuard.Context()).Allowed, "real ENG layout allowed")
SetKeyDelay 5, 5

; No initial selection: Enter reaches the native multiline Edit exactly once.
Prepare()
TypeFixture("confi")
AssertUnselected()
SendFixture "{Enter}"
Sleep 100
Assert(Value() == "confi`n", "unselected Enter inserts native newline only")
Assert(App.CommitCount == 0, "unselected Enter does not commit")
Assert(!App.Navigating, "unselected Enter leaves selection mode off")

; Hold the same Enter press across explicit repeat key-down events.
Prepare()
TypeFixture("confi")
AssertUnselected()
expected := EacSuggestionEngine.ApplyCase(App.Items[1].Word, "confi")
SendFixture "{Tab}"
Sleep 60
Assert(App.Selected == 1 && App.Navigating, "first Tab selects candidate one")
Assert(InStr(App.Gui.Labels[1].Text, "▶") == 1, "selected first GUI row has marker")
Guard()
EnterHeld := true
try {
    SendFixture "{Enter down}"
    Sleep 90
    Assert(Value() == expected, "Enter down commits first candidate without newline")
    Assert(App.CommitCount == 1, "Enter down commits exactly once")
    loop 3 {
        SendFixture "{Enter down}"
        Sleep 40
        Assert(Value() == expected && App.CommitCount == 1,
            "held Enter repeat " A_Index " neither commits nor inserts newline")
    }
} finally {
    ReleaseEnter()
}
Sleep 40
SendFixture "{Enter}"
Sleep 100
Assert(Value() == expected "`n" && App.CommitCount == 1,
    "separate Enter after key-up inserts native newline only")

; Space remains a normal word boundary even when a candidate is selected.
Prepare()
TypeFixture("confi")
SendFixture "{Tab}"
Sleep 60
Assert(App.Selected == 1 && App.Navigating, "Space case begins in selection mode")
SendFixture "{Space}"
Sleep 100
Assert(Value() == "confi " && App.CommitCount == 1, "selected Space inserts ordinary space only")
Assert(!App.Navigating && !App.Visible, "Space ends selection mode and hides candidates")
Guard()
Record("PASS selection_integration_checks=" Checks " elapsed_ms=" (A_TickCount - StartedAt)
    " AHK=" A_AhkVersion " real_OnChar=true real_hotkeys=true native_multiline_Edit=true")
Cleanup()
ExitApp 0

AssertUnselected() {
    global App
    Assert(App.Tracker.Word == "confi" && App.Observed == "confi", "actual OnChar captures confi")
    Assert(App.Visible && App.Items.Length == 9, "nine candidates displayed")
    Assert(App.Selected == 0 && !App.Navigating, "candidates initially unselected")
    Assert(!InStr(App.Gui.Labels[1].Text, "▶"), "unselected first GUI row has no marker")
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

Timeout() => Fail(Error("Selection integration exceeded seven seconds; abort input"))

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
    global App, FixtureHwnd, FixturePid, PreviousLayout, PreviousWindow, TestDirectory
    SetTimer Timeout, 0
    ReleaseEnter()
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
