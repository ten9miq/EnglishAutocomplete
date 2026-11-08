#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

Checks := 0
FixtureHwnd := 0
App := false
PreviousWindow := WinExist("A")
OnError Fail
OnExit Cleanup
Root := A_ScriptDir "\.."
DirCreate A_ScriptDir "\results"
ResultFile := A_ScriptDir "\results\ime-integration.txt"
if FileExist(ResultFile)
    FileDelete ResultFile
SettingsPath := A_ScriptDir "\results\ime-integration.ini"
FileCopy Root "\settings.default.ini", SettingsPath, true
TestDirectory := A_ScriptDir "\results\ime-user-" DllCall("GetCurrentProcessId", "UInt")
IniWrite TestDirectory, SettingsPath, "General", "DataDirectory"
IniWrite 1, SettingsPath, "app:AutoHotkey64.exe", "Enabled"
IniWrite 1, SettingsPath, "app:AutoHotkey64.exe", "Learning"
App := EacApplication(EacConfig(Root, SettingsPath), false)
; Native UIA/controls/SendText are real; IMM modes and observed character
; notifications are test inputs. This is NOT a real MS IME composition test.
App.Ime := FixtureIme()
App.Start(false)
Run '"' A_AhkPath '" "' A_ScriptDir '\ime-fixture.ahk"', , , &fixturePid
FixtureHwnd := WinWait("EnglishAutocomplete disposable IME fixture ahk_pid " fixturePid, , 5)
Assert(FixtureHwnd, "external fixture started")
RichHwnd := ControlGetHwnd("RICHEDIT50W1", "ahk_id " FixtureHwnd)
EditHwnd := ControlGetHwnd("Edit1", "ahk_id " FixtureHwnd)
ControlFocus RichHwnd
Sleep 100
context := EacFieldGuard.Context()
proof := App.Ime.Composition.GetState(context)
Record("UIA known=" proof.Known " active=" proof.Active " stage=" (proof.HasOwnProp("Reason") ? proof.Reason : "queried")
    " hr=" (proof.HasOwnProp("HResult") ? Format("{:X}", proof.HResult) : "none"))
Assert(proof.Known && !proof.Active, "external RichEdit exposes empty active composition")
ControlFocus EditHwnd
Sleep 30
Assert(!App.Ime.Composition.GetState(context).Known, "old RichEdit focus cannot prove composition state")
proof := App.Ime.Composition.GetState(EacFieldGuard.Context())
Assert(!proof.Known, "standard Edit without TextEditPattern is unknown")
ControlFocus RichHwnd
Sleep 30
for mode in [0, 16] {
    Prepare()
    App.Ime.Mode := mode
    TypeFixture("compu")
    Assert(App.Visible && App.SafetyReason = "OK", "candidate with modeled open mode + real UIA " mode)
    expected := EacSuggestionEngine.ApplyCase(App.Items[1].Word, "compu")
    App.Selected := 1
    Assert(App.Commit(), "commit with modeled open mode + real UIA " mode)
    Sleep 60
    Assert(ControlGetText(RichHwnd) == expected, "exact suffix-only result " mode)
}
Prepare()
App.Ime.Mode := 16
TypeFixture("confi")
Assert(App.Visible, "candidate ready before mode change")
binding := App.KeyBindings[1]
App.Ime.Mode := 25
Assert(!App.CanIntercept(binding), "mode change passes candidate keys through immediately")
Assert(!App.Commit() && ControlGetText(RichHwnd) == "confi", "mode change prevents stale commit")
Prepare()
App.Ime.Mode := 0
TypeFixture("confi")
Assert(App.Visible, "candidate ready before allowed mode transition")
App.Ime.Mode := 16
Assert(!App.CanIntercept(binding) && !App.Commit(), "even allowed mode change invalidates old candidate")
App.Ime.Mode := 16
Prepare()
TypeFixture("confi")
Assert(App.Visible, "candidate ready before composition begins")
nativeComposition := App.Ime.Composition
App.Ime.Composition := FixtureComposition(true, true)
Assert(!App.CanIntercept(binding), "active composition passes keys through")
Assert(!App.Commit() && ControlGetText(RichHwnd) == "confi", "active composition prevents stale commit")
Prepare()
TypeFixture("UncommittedFixtureWord ")
Assert(!App.Visible && App.User.Db.Query("SELECT count(*) FROM personal WHERE norm='uncommittedfixtureword'")[1][1] = "0",
    "active composition blocks learning and candidates")
App.Ime.Composition := FixtureComposition(false, false)
Prepare()
TypeFixture("UnknownCompositionWord ")
Assert(!App.Visible && !App.Commit()
    && App.User.Db.Query("SELECT count(*) FROM personal WHERE norm='unknowncompositionword'")[1][1] = "0",
    "unknown composition blocks learning candidates and commit")
App.Ime.Composition := nativeComposition
Prepare()
App.Ime.Mode := 8
TypeFixture("confi")
Assert(!App.Visible && !App.Commit(), "fullwidth alphanumeric blocked")
ControlFocus EditHwnd
Sleep 30
App.Ime.Mode := 16
Assert(!App.Ime.GetState(EacFieldGuard.Context()).Allowed, "open IME unsupported Edit stays blocked")
Record("PASS ime_integration_checks=" Checks " AHK=" A_AhkVersion " OS=" A_OSVersion " modeled_IMM=true real_UIA=true")
Cleanup()
ExitApp 0

Prepare() {
    global App, RichHwnd, FixtureHwnd
    Guard()
    App.Reset()
    ControlFocus RichHwnd
    ControlSetText "", RichHwnd
    Sleep 30
}

Guard() {
    global FixtureHwnd
    if WinExist("A") != FixtureHwnd
        throw Error("Fixture lost foreground; abort input")
}

TypeFixture(text) {
    global RichHwnd, App
    Guard()
    if EacFieldGuard.Context().Focus != RichHwnd
        throw Error("Fixture lost rich edit focus")
    ControlSetText text, RichHwnd
    SendMessage 0xB1, StrLen(text), StrLen(text), RichHwnd ; EM_SETSEL
    App.OnChar(0, text)
    App.Refresh()
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

Fail(e, *) {
    Record("FAIL " e.Message " at " e.Line "`n" e.Stack)
    Cleanup()
    ExitApp 1
}

Cleanup(*) {
    global App, FixtureHwnd, PreviousWindow, TestDirectory
    if App {
        App.Stop()
        App.User.Db.Close()
        App.Engine.Db.Close()
        App := false
    }
    if FixtureHwnd && WinExist("ahk_id " FixtureHwnd) {
        WinClose "ahk_id " FixtureHwnd
        FixtureHwnd := 0
    }
    if PreviousWindow && WinExist("ahk_id " PreviousWindow)
        try WinActivate "ahk_id " PreviousWindow
    if IsSet(TestDirectory) && DirExist(TestDirectory) {
        for suffix in ["", "-journal", "-wal", "-shm"]
            if FileExist(TestDirectory "\user.db" suffix)
                try FileDelete TestDirectory "\user.db" suffix
        try DirDelete TestDirectory
    }
}

class FixtureIme extends EacImeStateProvider {
    Mode := 0
    ReadState(context) => {Known: true, Reason: "TestIMEOpen", Layout: 0x411, Open: 1, Mode: this.Mode}
}

class FixtureComposition {
    __New(known, active) {
        this.Known := known
        this.Active := active
    }
    GetState(context) => {Known: this.Known, Active: this.Active}
}
