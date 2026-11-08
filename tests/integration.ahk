#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Uses only a fresh, disposable native Edit fixture. Never types into other apps.
Root := A_ScriptDir "\.."
DirCreate A_ScriptDir "\results"
ResultFile := A_ScriptDir "\results\integration.txt"
if FileExist(ResultFile)
    FileDelete ResultFile
Checks := 0
CaseOnly := A_Args.Length && A_Args[1] == "--case-only"
PreviousWindow := WinExist("A")
PreviousLayout := DllCall("GetKeyboardLayout", "UInt", 0, "Ptr")
FixtureGui := false
App := false
OnError Fail
OnExit Cleanup
Path := A_ScriptDir "\results\integration-settings.ini"
FileCopy Root "\settings.default.ini", Path, true
IniWrite 1, Path, "app:AutoHotkey64.exe", "Enabled"
IniWrite 1, Path, "app:AutoHotkey64.exe", "Learning"
TestDirectory := A_ScriptDir "\results\integration-user-" DllCall("GetCurrentProcessId", "UInt")
IniWrite TestDirectory, Path, "General", "DataDirectory"
Settings := EacConfig(Root, Path)
IniWrite 0, Path, "General", "Debug"
Started := ClockMs()
App := TestApplication(Settings, false)
; Isolate keyboard/GUI tests from unrelated physical wheel activity. Production
; Start() always installs mouse invalidation; mouse behavior is tested manually.
App.Start(false)
InitMs := ClockMs() - Started
Run '"' A_AhkPath '" "' A_ScriptDir '\fixture.ahk"', , , &FixturePid
fixtureHwnd := WinWait("EnglishAutocomplete disposable test fixture ahk_pid " FixturePid, , 5)
if !fixtureHwnd
    throw Error("External fixture did not start")
FixtureGui := TestWindow(fixtureHwnd)
TestEdit := TestField(ControlGetHwnd("Edit1", "ahk_id " fixtureHwnd))
Password := TestField(ControlGetHwnd("Edit2", "ahk_id " fixtureHwnd))
Other := TestField(ControlGetHwnd("Edit3", "ahk_id " fixtureHwnd))
ReadOnlyEdit := TestField(ControlGetHwnd("Edit4", "ahk_id " fixtureHwnd))
TestEdit.Focus()
Sleep 120
context := EacFieldGuard.Context()
Assert(context && context.Focus == TestEdit.Hwnd, "native focus context")
Assert(App.Ime.GetState(context).Allowed, "ENG layout allowed (real OS query)")
Assert(EacFieldGuard.Read(context), "native editable safety")
if CaseOnly {
    RunCaseTests()
    Record("PASS exact_case_checks=" Checks " AHK=" A_AhkVersion)
    Cleanup()
    ExitApp 0
}

; Real InputHook capture of nonzero SendLevel events, typed only into our fixture.
SendLevel 1
SetKeyDelay 18, 10
TypeFixture("confi")
Assert(App.Tracker.Word == "confi", "InputHook OnChar actual events")
Assert(App.Visible && App.Items.Length == Settings.MaxCandidates, "real candidate GUI")
Assert(WinExist("A") == FixtureGui.Hwnd && EacFieldGuard.Context().Focus == TestEdit.Hwnd,
    "NoActivate preserves target focus")
expected := App.Items[1].Word
before := TestEdit.Value
Started := ClockMs()
Assert(App.Selected = 0 && !App.Navigating, "prediction is initially unselected")
App.Selected := 1
Assert(App.Commit(), "suffix-only commit")
CommitMs := ClockMs() - Started
Sleep 100
Assert(TestEdit.Value == before SubStr(expected, StrLen(before) + 1), "commit field content intact")
Assert(App.Tracker.Word == TestEdit.Value, "injected suffix not recaptured recursively")
SendLevel 1
SendFixture "x"
Sleep 100
Assert(TestEdit.Value == expected "x", "input immediately after commit")
SendFixture " "
Sleep 80

; Real global hotkeys with configured modifiers. No Enter/Tab is sent on accept.
Prepare()
TypeFixture("compu")
Assert(App.Visible, "candidate for configured hotkey")
expected := App.Items[1].Word
SendLevel 1
SendFixture "^!{Space}"
Sleep 160
Assert(TestEdit.Value == expected, "configured accept hotkey actual event")
Prepare()
TypeFixture("confi")
count := App.Items.Length
SendLevel 1
SendFixture "{Tab}"
Sleep 80
Assert(App.Selected == 1 && App.Navigating, "first Tab selects first candidate and enters conversion mode")
SendFixture "^!{Up}"
Sleep 80
Assert(App.Selected == count, "configured previous hotkey wraps to last candidate")
expected := App.Items[2].Word
SendFixture "^!2"
Sleep 120
Assert(TestEdit.Value == expected, "number hotkey accepts corresponding candidate")
Prepare()
TypeFixture("confi")
SendLevel 1
SendFixture "{Esc}"
Sleep 100
Assert(!App.Visible && TestEdit.Value == "confi", "Esc cancels without changing text")

Prepare()
TypeFixture("confi")
SendLevel 1
SendFixture "{BS}"
Sleep 100
Assert(App.Visible && App.Tracker.Word == "conf" && TestEdit.Value == "conf", "Backspace native operation + verified update")
Prepare()
TypeFixture("confi")
SendLevel 1
SendFixture "{Left}"
Sleep 100
Assert(!App.Visible && App.Tracker.Word == "", "cursor movement invalidates")
Prepare()
TypeFixture("confi")
SendLevel 1
SendFixture "{Delete}"
Sleep 100
Assert(!App.Visible && App.Tracker.Word == "", "Delete invalidates")
Prepare()
TypeFixture("confi")
Other.Focus()
Sleep 450
Assert(!App.Visible, "focus change invalidates at monitor tick")
Assert(!App.Commit(), "old target cannot receive completion")

Prepare()
TypeFixture("confi")
TestEdit.Value := "application autocorrected text"
App.Refresh()
Assert(!App.Visible && !App.Commit(), "app-side text change refuses stale completion")

Prepare()
TypeFixture("confi")
SendLevel 1
SendFixture "^a"
Sleep 100
Assert(!App.Visible && App.Tracker.Word == "", "shortcut invalidates")
Prepare()
TypeFixture("confi")
App.Target.Policy.ImeStyleKeys := false
SendLevel 1
SendFixture "{Tab}"
Sleep 100
Assert(TestEdit.Value == "confi" && EacFieldGuard.Context().Focus == Password.Hwnd,
    "style opt-out Tab passes through to next control")
Assert(!App.Visible, "password receives no candidate")
Settings.Policies["autohotkey64.exe"].ImeStyleKeys := true
Password.Focus()
Assert(!EacFieldGuard.Read(EacFieldGuard.Context()), "ES_PASSWORD refused")
SendLevel 1
SendFixture "sensitiveFixtureWord "
Sleep 150
Assert(App.User.Db.Query("SELECT count(*) FROM personal WHERE norm='sensitivefixtureword'")[1][1] == "0",
    "password field never learned")
ReadOnlyEdit.Focus()
Assert(!EacFieldGuard.Read(EacFieldGuard.Context()), "read-only refused")

Prepare()
TypeFixture("LearnFixtureWord ")
Assert(App.User.Db.Query("SELECT uses FROM personal WHERE norm='learnfixtureword'")[1][1] == "1",
    "manual typed word learned only at verified boundary")
Prepare()
TypeFixture("name@example.com ")
Assert(App.User.Db.Query("SELECT count(*) FROM personal WHERE norm LIKE '%example%'")[1][1] == "0",
    "email not learned")

Settings.Enabled := false
Prepare()
TypeFixture("DisabledFixtureWord ")
Assert(!App.Visible && App.User.Db.Query("SELECT count(*) FROM personal WHERE norm='disabledfixtureword'")[1][1] == "0",
    "global disable stops both suggestions and learning with cached app policy")
Settings.Enabled := true
Prepare()
TypeFixture("confi")
Assert(App.Visible, "global re-enable restores cached application policy")

Prepare()
SetKeyDelay 1, 1
TypeFixture("configuration")
Assert(TestEdit.Value == "configuration" && App.Tracker.Word == "configuration", "rapid input has no lost characters")
SetKeyDelay 18, 10
Record("STAGE base keyboard/safety complete; exact case tests")
RunCaseTests()
Record("STAGE CamelCase passed; performance samples")
Prepare()
TypeFixture("compu")
context := EacFieldGuard.Context()
samples := [], guiSamples := []
Loop 100 {
    t := ClockMs()
    anchor := App.Caret.GetPosition(EacFieldGuard.Context(), true)
    samples.Push(ClockMs() - t)
    t := ClockMs()
    App.Gui.Show(App.Items, Mod(A_Index, App.Items.Length) + 1, anchor)
    guiSamples.Push(ClockMs() - t)
}
Record("METRIC initialization_ms=" Round(InitMs, 3))
Record("METRIC suffix_commit_ms=" Round(CommitMs, 3))
Record("METRIC caret_p95_ms=" Round(P95(samples), 3) " n=100 Win32")
Record("METRIC gui_update_p95_ms=" Round(P95(guiSamples), 3) " n=100 native fixture")
displaySamples := []
Loop 30 {
    Prepare()
    TypeFixture("comp")
    t := ClockMs()
    SendLevel 1
    SendFixture "u"
    deadline := A_TickCount + 1000
    while (!App.Visible || App.Tracker.Word != "compu" || App.ShownGeneration != App.Tracker.Generation) && A_TickCount < deadline
        Sleep 1
    Assert(App.Visible && App.Tracker.Word == "compu", "candidate display end to end")
    displaySamples.Push(ClockMs() - t)
}
Record("METRIC candidate_display_p95_ms=" Round(P95(displaySamples), 3) " n=30 final_synthetic_key_to_GUI_including_key_duration")
Record("PASS checks=" Checks " OS=" A_OSVersion " AHK=" A_AhkVersion)
Cleanup()
ExitApp 0

RunCaseTests() {
    global App, TestEdit
    SetKeyDelay 5, 5
    App.User.Observe("computer", true)
    App.User.Observe("getUserInfo", true)
    for casePair in [["compu", "computer", "computer"], ["COMPU", "COMPUTER", "computer"],
        ["Compu", "Computer", "computer"], ["coMPu", "coMPuter", "computer"],
        ["getU", "getUserInfo", "getuserinfo"]] {
        Prepare()
        TypeFixture(casePair[1])
        candidate := 0
        for index, item in App.Items
            if item.Norm == casePair[3]
                candidate := index
        Assert(candidate, "case candidate available")
        App.Selected := candidate
        Assert(App.Commit(), "case-sensitive suffix commit")
        Sleep 90
        Assert(TestEdit.Value == casePair[2], "actual field exact case " casePair[2])
        Record("STAGE exact case passed: " casePair[2])
    }
    SetKeyDelay 18, 10
}

Prepare() {
    global App, TestEdit, FixtureGui
    if WinExist("A") != FixtureGui.Hwnd
        throw Error("Test fixture lost foreground; abort typing")
    App.Reset()
    TestEdit.Value := ""
    TestEdit.Focus()
    Sleep 40
}

TypeFixture(text) {
    global FixtureGui, TestEdit
    if WinExist("A") != FixtureGui.Hwnd || EacFieldGuard.Context().Focus != TestEdit.Hwnd
        throw Error("Test fixture lost focus; abort typing")
    loop parse text {
        if WinExist("A") != FixtureGui.Hwnd || EacFieldGuard.Context().Focus != TestEdit.Hwnd
            throw Error("Test fixture lost focus before next key; abort typing")
        SendLevel 1
        SendEvent "{Raw}" A_LoopField
    }
    Sleep 150
}

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error("FAIL " description)
}

ClockMs() {
    static frequency := 0
    if !frequency
        DllCall "QueryPerformanceFrequency", "Int64*", &frequency
    DllCall "QueryPerformanceCounter", "Int64*", &counter := 0
    return counter * 1000 / frequency
}

P95(values) {
    sorted := []
    for value in values {
        index := 1
        while index <= sorted.Length && sorted[index] < value
            index += 1
        sorted.InsertAt(index, value)
    }
    return sorted[Ceil(sorted.Length * 0.95)]
}

Record(message) {
    global ResultFile
    FileAppend message "`n", ResultFile, "UTF-8"
    FileAppend message "`n", "*", "UTF-8"
}

Fail(err, *) {
    global App, TestEdit
    if App
        Record("State fault=" App.Fault " tracker_length=" StrLen(App.Tracker.Word) " visible=" App.Visible " generation=" App.Tracker.Generation " safety=" App.SafetyReason)
    if App && App.HasOwnProp("LastReset")
        Record(App.LastReset)
    if App && App.HasOwnProp("Trace")
        for entry in App.Trace
            Record(entry)
    if IsSet(TestEdit)
        Record("Fixture value=" TestEdit.Value " foreground=" WinExist("A"))
    Record("FAIL " err.Message " at " err.File ":" err.Line " " err.Stack)
    Cleanup()
    ExitApp 1
}

class TestApplication extends EacApplication {
    Trace := []
    Note(message) {
        this.Trace.Push(message)
        if this.Trace.Length > 30
            this.Trace.RemoveAt(1)
    }
    OnChar(hook, text) {
        this.Note("char=" text " prior=" this.Tracker.Word " mask=" this.InputModifierMask)
        super.OnChar(hook, text)
    }
    Snapshot() {
        result := super.Snapshot()
        if result && this.Tracker.Word != "" && !EacFieldGuard.Matches(result.Field, this.Tracker.Word)
            this.Note("mismatch word=" this.Tracker.Word " before=" result.Field.Before " pos=" result.Field.Position)
        return result
    }
    Reset(*) {
        this.Note("reset word=" this.Tracker.Word " reason=" (this.HasOwnProp("SafetyReason") ? this.SafetyReason : "none") " caller=" StrSplit(Error().Stack, "`n")[2])
        this.LastReset := Error().Stack
        super.Reset()
    }
}

class TestField {
    __New(hwnd) => this.Hwnd := hwnd
    Value {
        get => ControlGetText(this.Hwnd)
        set => ControlSetText(value, this.Hwnd)
    }
    Focus() => ControlFocus(this.Hwnd)
}

class TestWindow {
    __New(hwnd) => this.Hwnd := hwnd
    Destroy() {
        if WinExist("ahk_id " this.Hwnd)
            WinClose "ahk_id " this.Hwnd
    }
}

Cleanup(*) {
    global App, FixtureGui, PreviousLayout, PreviousWindow, TestDirectory
    if App {
        App.Stop()
        App.User.Db.Close()
        App.Engine.Db.Close()
        App := false
    }
    if FixtureGui {
        FixtureGui.Destroy()
        FixtureGui := false
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

SendFixture(keys) {
    global FixtureGui
    context := EacFieldGuard.Context()
    if !context || context.Hwnd != FixtureGui.Hwnd
        throw Error("Test fixture lost foreground; abort synthetic key")
    SendLevel 1
    SendEvent keys
}
