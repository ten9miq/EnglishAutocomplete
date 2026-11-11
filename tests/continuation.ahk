#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Own DB and modelled UIA field; no window/input or external app interaction.
Checks := 0, Personal := false, Engine := false, App := false
Root := A_ScriptDir "\.."
Fixture := A_ScriptDir "\results\continuation-" DllCall("GetCurrentProcessId")
DirCreate Fixture
settingsPath := Fixture "\settings.ini"
FileCopy Root "\settings.default.ini", settingsPath
IniWrite Fixture, settingsPath, "General", "DataDirectory"
OnError Fail
OnExit Cleanup
config := EacConfig(Root, settingsPath)
Personal := EacUserDictionary(Fixture "\user.db")
Engine := EacSuggestionEngine(Root "\data\dictionary.db", config, Personal)
Assert(Engine.Search("it-des").Length > 0, "real dictionary supplies suffix candidates after hyphen")
Personal.Observe("description", true)
for pair in [["it-des", "it-description"], ["it-DES", "it-DESCRIPTION"], ["my.file-des", "my.file-description"],
    ["file_des", "file_description"], ["name.Des", "name.Description"]] {
    item := Find(Engine.Search(pair[1]), "description")
    Assert(item && item.CompletionPrefix != "", "compound suffix candidate " pair[1])
    Assert(EacSuggestionEngine.CompletionWord(item, pair[1]) == pair[2], "existing stem and typed case preserved " pair[1])
    Assert(EacSuggestionEngine.CompletionWord(item, "changed-des") == "", "stale prefix ticket cannot complete")
}
Personal.Observe("it-design", true)
items := Engine.Search("it-des")
Assert(Find(items, "it-design") && !Find(items, "description"), "whole compound dictionary match has priority")
Personal.Delete("it-design")
Personal.Observe("config.toml", true)
Assert(Find(Engine.Search("config.t"), "config.toml"), "dotted technical word still completes as a whole")
for prefix in ["name@it-des", "https://it-des", "C:\it-des", "token_des", "secret-des", "password.des", "foo--des"]
    Assert(!Engine.Search(prefix).Length, "unsafe/unsupported prefix never gets segment fallback " prefix)
Personal.Block("description")
Assert(!Find(Engine.Search("it-des"), "description"), "personal block applies to segment candidates")
Assert(EacFieldGuard.Matches({Before: "it-des", After: ""}, "it-des"), "entire compound is verified")
Assert(!EacFieldGuard.Matches({Before: "other-des", After: ""}, "it-des"), "changed stem is rejected")
Assert(!EacFieldGuard.Matches({Before: "name@it-des", After: ""}, "it-des"), "email tail is rejected by field guard")
Assert(!EacFieldGuard.Matches({Before: "it-des", After: "c"}, "it-des"), "middle of an existing token remains protected")

App := ContinuationApp()
bindings := Map()
for binding in App.KeyBindings
    bindings[StrLower(binding.Key)] := binding
tab := bindings["tab"], enter := bindings["enter"]
loop 6 {
    App.Action(tab)
    Assert(App.Selected = 1 && App.Navigating, "selection starts before adding text")
    App.OnChar(0, "a")
    Assert(!App.Visible && !App.Gui.Visible && App.NavigationPending && !App.Selected, "new text hides old popup and invalidates selection")
    prefix := App.Tracker.Word
    App.OnKeyDown(0, 9, 0), App.OnChar(0, "`t")
    Assert(App.Tracker.Word == prefix, "Tab notification does not terminate pending word")
    Assert(App.CanIntercept(tab), "Tab stays owned while a recent valid preview is updating")
    App.Action(tab)
    Assert(App.QueuedNavigation.Length = 1 && !App.Selected, "Tab queues intent without selecting stale candidate")
    App.Before := App.Tracker.Word
    App.Refresh()
    Assert(App.Visible && App.Selected = 1 && App.Navigating && !App.NavigationPending, "fresh preview applies queued selection")
    ; Start next cycle unselected, as after a new preview.
    App.ClearSelection()
}
App.OnChar(0, "b"), App.Action(tab)
Assert(App.CanIntercept(enter), "Enter after deferred Tab cannot fall through to app Submit")
App.OnKeyDown(0, 13, 0), App.OnChar(0, "`r")
Assert(App.CanIntercept(enter), "Enter notifications preserve deferred conversion")
App.Action(enter)
Assert(App.QueuedAccept && !App.Commits, "pending Enter does not commit stale text")
App.Before := App.Tracker.Word
App.Refresh()
Assert(App.Commits = 1 && App.LastCommit == App.Tracker.Word, "deferred Enter commits only fresh verified prefix")
App.ReleaseEnter()

App.Begin(), App.OnChar(0, "x"), App.Action(bindings["+tab"])
App.Before := App.Tracker.Word, App.Refresh()
Assert(App.Selected = 9 && App.Expanded, "deferred Shift Tab selects last fresh candidate")
for reason in ["context", "ime", "focus", "policy", "expired"] {
    App.Begin(), App.OnChar(0, "x")
    switch reason {
        case "context": App.ContextKey := "other"
        case "ime": App.Ime.Allowed := false
        case "focus": App.Focused := false
        case "policy": App.Policy.Keys := false
        case "expired": App.LastInputAt -= 351
    }
    Assert(!App.CanIntercept(tab), "deferred Tab refuses unsafe or expired state " reason)
}
App.Begin(), App.OnChar(0, "x"), App.Action(tab)
App.Readable := false
App.Refresh()
Assert(!App.Selected && !App.Visible && !App.QueuedNavigation.Length, "failed fresh read discards queued selection")
App.Begin(), App.OnChar(0, "x"), App.ChangeDuringFocus := true
Assert(!App.CanIntercept(tab), "input during remote focus validation cannot arm stale navigation")
App.Begin(), App.OnChar(0, "x"), App.Action(tab)
App.CanIntercept(enter), App.Action(enter)
App.OnChar(0, "y")
App.Before := App.Tracker.Word, App.Refresh()
Assert(!App.Commits && !App.QueuedAccept && !App.Selected, "further typing cancels pending confirmation")
App.Begin(), App.OnChar(0, "x"), App.Action(tab)
App.Before := App.Tracker.Word
App.Gui.RenderProbe := ObjBindMethod(App, "CanIntercept", enter)
App.Refresh()
Assert(App.Gui.ProbeAllowed, "fresh selection owns Enter during GUI rendering")
App.Gui.RenderProbe := false
App.Begin(), App.OnChar(0, "x"), App.Action(tab)
App.Before := App.Tracker.Word
App.Gui.RenderProbe := ObjBindMethod(App, "Hide")
App.Refresh()
Assert(!App.Visible && !App.Gui.Visible, "cancel during rendering cannot resurrect a popup")
App.Gui.RenderProbe := false
App.Begin(), App.OnChar(0, "x"), App.Action(tab)
App.Before := App.Tracker.Word
App.Gui.RenderProbe := ObjBindMethod(App, "PublishReplacement")
App.Refresh()
Assert(App.Visible && App.Gui.Visible && SubStr(App.Tracker.Word, -1) == "z", "older render cannot hide a newer preview")
App.Begin(), App.OnChar(0, "x")
Assert(!App.CanIntercept(enter), "unselected Enter remains native without a queued Tab")
App.OnChar(0, " ")
Assert(!App.NavigationPending && !App.CanIntercept(tab), "word boundary clears deferred ownership")

; A stale browser selection must not discard the first observed letters.
; No candidate or navigation is available until a fully valid read succeeds.
App.Begin(), App.Reset(), App.Readable := false, App.ReadFailure := "TextChanged"
App.OnChar(0, "c"), App.Refresh()
Assert(App.Tracker.Word == "c" && !App.Visible && !App.Target, "failed first read preserves only observed input")
Assert(!App.CanIntercept(tab) && !App.CanIntercept(enter), "selection retry owns no candidate keys")
App.OnChar(0, "onfi"), App.Before := "confi", App.Refresh()
Assert(App.Tracker.Word == "confi" && !App.Visible, "typing during retry retains complete observed word")
App.Readable := true, App.Refresh()
Assert(App.Visible && App.Tracker.Word == "confi" && App.Target.Field.Before == "confi", "fresh safe snapshot restores complete preview")
App.Begin(), App.Readable := false, App.ReadFailure := "TextChanged", App.Refresh()
App.TextRetryAt -= 351
App.Refresh()
Assert(App.Tracker.Word == "" && !App.Visible && !App.Target, "persistent invalid selection expires after bounded retry")
App.Begin(), App.Readable := false, App.ReadFailure := "UIAReadOnlyOrRange", App.Refresh()
Assert(App.Tracker.Word == "" && !App.Visible, "known readonly field still resets immediately")
App.Begin(), App.Readable := false, App.ReadFailure := "TextChanged", App.Refresh()
App.ContextKey := "other", App.Readable := true, App.Refresh()
Assert(App.Tracker.Word == "" && !App.Visible, "focus change cannot inherit retry text")
FileAppend "PASS continuation_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
Cleanup()
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}
Find(items, norm) {
    for item in items
        if item.Norm == norm
            return item
    return false
}
Fail(err, *) {
    FileAppend "FAIL " err.Message " at " err.Line "`n" err.Stack, "**"
    Cleanup()
    ExitApp 1
}
Cleanup(*) {
    global App, Engine, Personal, Fixture
    if App
        SetTimer App.RefreshCallback, 0
    if Engine
        Engine.Db.Close(), Engine := false
    if Personal
        Personal.Db.Close(), Personal := false
    loop files Fixture "\*", "F"
        FileDelete A_LoopFileFullPath
    if DirExist(Fixture)
        DirDelete Fixture
}
class ContinuationApp extends EacApplication {
    __New() {
        this.Config := {Enabled: true, InitialCandidates: 5, MinLength: 2, DebounceMs: 30,
            AcceptKey: "^!Space", NextKey: "Tab", PreviousKey: "^!Up", CancelKey: "Esc", DirectModifier: "^!"}
        this.Tracker := EacInputTracker(), this.Gui := ContinuationGui(), this.Engine := ContinuationEngine()
        this.Ime := ContinuationIme()
        this.RefreshCallback := (*) => 0
        this.KeyBindings := this.BuildBindings()
        this.Begin()
    }
    Begin() {
        this.ChangeDuringFocus := false
        this.ContextKey := "fixture", this.Focused := true, this.Readable := true
        this.ReadFailure := "Field"
        this.Ime.Allowed := true
        this.Policy := {Enabled: true, Keys: true, ImeStyleKeys: true, Tab: false, Enter: false, Learning: false}
        this.Reset(), this.ReleaseEnter()
        this.EnterActionArmed := false, this.Commits := 0, this.LastCommit := ""
        this.Tracker.Feed("confi", this.ContextKey), this.Before := "confi"
        this.LearningTracker.Reset(), this.LearningTracker.Feed("confi", this.ContextKey)
        this.Refresh()
    }
    CurrentContext() => {Key: this.ContextKey, Hwnd: 1, Focus: 2}
    Snapshot() {
        if !this.Readable || !this.Focused || !this.Ime.Allowed {
            this.SafetyReason := this.ReadFailure
            return false
        }
        context := this.CurrentContext()
        return {Context: context, Policy: this.Policy, Ime: this.Ime.GetState(context),
            Field: {Before: this.Before, After: "", Identity: "editor", Provider: "UIA", Anchor: {Found: true}}}
    }
    FocusedTarget(field, context) {
        if this.ChangeDuringFocus
            this.Tracker.Generation += 1
        return this.Focused
    }
    Modifiers() => 0
    PublishReplacement() {
        this.Gui.RenderProbe := false
        this.OnChar(0, "z")
        this.Before := this.Tracker.Word
        this.Refresh()
        return true
    }
    Commit() {
        snapshot := this.Snapshot()
        if !snapshot || !EacFieldGuard.Matches(snapshot.Field, this.Tracker.Word) {
            this.Reset()
            return false
        }
        this.Commits += 1, this.LastCommit := this.Tracker.Word
        this.Hide()
        return true
    }
}
class ContinuationIme {
    Allowed := true
    GetState(context) => {Allowed: this.Allowed, Key: "ime", Reason: this.Allowed ? "IMEClosed" : "NativeIMEPriority"}
}
class ContinuationEngine {
    Search(prefix) {
        items := []
        loop 9
            items.Push({Norm: prefix A_Index, Word: prefix A_Index, Learned: false})
        return items
    }
}
class ContinuationGui {
    Visible := false
    RenderProbe := false
    ProbeAllowed := false
    Hide() => this.Visible := false
    Show(*) {
        this.Visible := true
        if this.RenderProbe
            this.ProbeAllowed := this.RenderProbe.Call()
    }
}
