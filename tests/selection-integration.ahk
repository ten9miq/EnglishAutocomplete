#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Real InputHook/hotkey events, sent only to our fresh external native Edit.
InstallKeybdHook()
InstallMouseHook()
Root := A_ScriptDir "\.."
Checks := 0
App := false
Failing := false
FixtureHwnd := 0
FixturePid := 0
InputSenderPid := 0
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

if A_Args.Length && A_Args[1] = "--continuation-only" {
    RunContinuationTests()
    Record("PASS continuation_integration_checks=" Checks " AHK=" A_AhkVersion)
    Cleanup()
    ExitApp 0
}

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
Assert(App.Gui.Numbers[1].Text == "1", "selected row has a separate number gutter")
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

; Plain digits stay literal before Tab, then commit only visible numbered rows.
Prepare()
TypeFixture("confi")
SendFixture "3"
Sleep 80
Assert(Value() == "confi3", "ordinary digit before Tab remains literal")
Prepare()
TypeFixture("confi")
expected := EacSuggestionEngine.ApplyCase(App.Items[3].Word, "confi")
SendFixture "{Tab}"
Sleep 40
SendFixture "3"
Sleep 100
Assert(Value() == expected && App.CommitCount == 2, "Tab then plain three commits candidate three without a digit")
Prepare()
TypeFixture("confi")
loop 5 {
    SendFixture "{Tab}"
    Sleep 30
}
Assert(App.Selected = 5 && App.Gui.LastLayout.Rows = 9, "fifth real Tab expands GUI to nine rows")
expected := EacSuggestionEngine.ApplyCase(App.Items[9].Word, "confi")
SendFixture "9"
Sleep 100
Assert(Value() == expected && App.CommitCount == 3, "expanded plain nine commits candidate nine")
Guard()
Record("PASS selection_integration_checks=" Checks " elapsed_ms=" (A_TickCount - StartedAt)
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

RunContinuationTests() {
    global App, Settings
    ; Force the update gap in this isolated instance. All OS input remains
    ; guarded to the disposable Edit, with physical activity causing abort.
    SetTimer App.TickCallback, 0
    Settings.DebounceMs := 150
    Prepare()
    TypeFixture("co")
    SendFixture "{Tab}"
    Sleep 50
    Assert(App.Selected = 1 && App.Navigating, "initial real Tab selects preview")
    prefix := "co"
    loop parse "mpute" {
        SendFixture A_LoopField
        prefix .= A_LoopField
        Sleep 20
        Assert(App.NavigationPending && !App.Gui.Visible, "typing hides stale selected preview")
        SendFixture "{Tab}"
        refreshDeadline := A_TickCount + 700
        while (!App.Visible || !App.Navigating || App.Selected != 1) && A_TickCount < refreshDeadline {
            Guard()
            Sleep 10
        }
        Assert(App.Visible && App.Selected = 1 && App.Navigating, "real Tab selects refreshed prefix " prefix)
        Assert(Value() == prefix, "repeat selection does not insert Tab or complete text")
    }
    beforeCommits := App.CommitCount
    expected := prefix SubStr(EacSuggestionEngine.CompletionWord(App.Items[1], prefix), StrLen(prefix) + 1)
    SendFixture "{Enter}"
    Sleep 100
    Assert(App.CommitCount = beforeCommits + 1 && Value() == expected, "Enter completes after repeated type/select cycles")
    loop 3 {
        Prepare()
        TypeFixture("co"), SendFixture("{Tab}")
        Sleep 40
        SendFixture "m"
        Sleep 20
        Assert(App.NavigationPending, "fast confirmation begins inside refresh gap")
        beforeCommits := App.CommitCount
        SendExternal("tab-enter")
        refreshDeadline := A_TickCount + 700
        while App.CommitCount = beforeCommits && A_TickCount < refreshDeadline {
            Guard()
            Sleep 10
        }
        Assert(App.CommitCount = beforeCommits + 1 && !InStr(Value(), "`n"), "external fast Tab Enter completes once without newline")
    }
    Prepare()
    App.User.Observe("description", true)
    TypeFixture("it-des")
    Assert(App.Items.Length && App.Items[1].Norm == "description", "compound suffix appears in real candidate GUI")
    SendExternal("tab-enter")
    Sleep 150
    Assert(Value() == "it-description", "real completion preserves existing hyphen stem")
    Prepare()
    TypeFixture("co")
    beforeCommits := App.CommitCount
    SendExternal("enter")
    Sleep 80
    Assert(Value() == "co`n" && App.CommitCount = beforeCommits, "external unselected Enter remains native")
}

SendExternal(mode) {
    global FixtureHwnd, FixturePid, EditHwnd, TestDirectory, InputSenderPid
    Guard()
    resultPath := TestDirectory "\external-input.txt"
    if FileExist(resultPath)
        FileDelete resultPath
    ; The receiver remains in its message loop while a separate process sends
    ; input, as with real typing. Self-SendEvent can postpone our own Actions.
    senderCommand := '"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\continuation-input.ahk" '
        . FixtureHwnd ' ' FixturePid ' ' EditHwnd ' "' resultPath '" ' mode
    Run senderCommand, , "Hide", &InputSenderPid
    deadline := A_TickCount + 1800
    while ProcessExist(InputSenderPid) && A_TickCount < deadline {
        Guard()
        Sleep 10
    }
    if ProcessExist(InputSenderPid)
        throw Error("External input helper timed out")
    InputSenderPid := 0
    result := FileExist(resultPath) ? FileRead(resultPath, "UTF-8") : "no result file"
    if result != "PASS"
        throw Error("External input helper: " result)
    Guard()
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
    global App, Failing, FixtureHwnd, FixturePid, EditHwnd
    if Failing
        ExitApp 1
    Failing := true
    Record("FAIL " err.Message " at " err.File ":" err.Line "`n" err.Stack)
    if App
        Record("STATE selected=" App.Selected " navigating=" App.Navigating
            " visible=" App.Visible " commits=" App.CommitCount " fault=" App.Fault)
    if App && App.HasOwnProp("Trace")
        for entry in App.Trace
            Record(entry)
    if FixtureHwnd && EditHwnd && WinExist("ahk_id " FixtureHwnd) && WinGetPID("ahk_id " FixtureHwnd) = FixturePid {
        try {
            value := StrReplace(ControlGetText(EditHwnd), "`r`n", "`n")
            Record("STATE fixture_length=" StrLen(value) " has_newline=" (!!InStr(value, "`n")))
        }
    }
    Cleanup()
    ExitApp 1
}

Cleanup(*) {
    global App, FixtureHwnd, FixturePid, InputSenderPid, PreviousLayout, PreviousWindow, TestDirectory
    SetTimer Timeout, 0
    ReleaseEnter()
    if InputSenderPid && ProcessExist(InputSenderPid)
        ProcessClose InputSenderPid
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
        if FileExist(TestDirectory "\external-input.txt")
            FileDelete TestDirectory "\external-input.txt"
        try DirDelete TestDirectory
    }
}

class SelectionTestApplication extends EacApplication {
    Observed := ""
    Trace := []
    Note(event) {
        this.Trace.Push(A_TickCount " " event " pending=" this.NavigationPending " q=" this.QueuedNavigation.Length
            " qa=" this.QueuedAccept " vis=" this.Visible " sel=" this.Selected " len=" StrLen(this.Tracker.Word)
            " gen=" this.Tracker.Generation " shown=" this.ShownGeneration " armed=" this.EnterActionArmed " latch=" this.EnterLatched)
        if this.Trace.Length > 80
            this.Trace.RemoveAt(1)
    }
    OnChar(hook, text) {
        this.Note("char-before n=" StrLen(text) " boundary=" (!!RegExMatch(text, "^\s+$")))
        this.Observed .= text
        super.OnChar(hook, text)
        this.Note("char-after")
    }
    OnKeyDown(hook, vk, sc) {
        if vk = 9 || vk = 13
            this.Note("key-before vk=" vk)
        super.OnKeyDown(hook, vk, sc)
        if vk = 9 || vk = 13
            this.Note("key-after vk=" vk)
    }
    Action(binding, *) {
        this.Note("action-before " binding.Action)
        super.Action(binding)
        this.Note("action-after " binding.Action)
    }
    CanIntercept(binding, *) {
        allowed := super.CanIntercept(binding)
        if binding.Vk = 9 || binding.Vk = 13
            this.Note("condition vk=" binding.Vk " allow=" allowed)
        return allowed
    }
    Refresh() {
        this.Note("refresh-before")
        super.Refresh()
        this.Note("refresh-after")
    }
}
