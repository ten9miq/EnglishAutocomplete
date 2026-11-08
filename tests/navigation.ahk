#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Headless state/shortcut regression: never registers hotkeys or types anywhere.
Checks := 0
OnError((e, *) => (FileAppend("FAIL " e.Message " at " e.Line "`n" e.Stack, "**"), ExitApp(1)))
app := NavigationApp()
bindings := Map()
for binding in app.BuildBindings()
    bindings[StrLower(binding.Key)] := binding
Assert(!bindings.Has("^!tab"), "Ctrl Alt Tab is not registered")
Assert(!bindings.Has("space") && !bindings.Has("+space"), "Space and Shift Space are never candidate aliases")
for key in ["tab", "+tab", "up", "down", "enter", "^!9"]
    Assert(bindings.Has(key), "expected candidate key " key)
Assert(!app.CanIntercept(bindings["enter"]), "preview alone never intercepts Enter")
Assert(app.Selected = 0 && !app.Navigating, "prediction starts without any selected row")
app.Target.Policy.Enter := true
Assert(!app.CanIntercept(bindings["enter"]), "legacy Enter setting cannot auto-select a preview row")
app.Target.Policy.Enter := false
app.OnChar(0, " ")
Assert(!app.Visible && !app.Navigating && app.Tracker.Word == "", "literal Space finishes the word and ends preview")
Assert(app.Pending.Length = 1 && app.Pending[1].Word == "confi", "Space is observed as a real word boundary")
app.Ready()
app.Action(bindings["tab"])
Assert(app.Navigating && app.Selected = 1 && !app.Committed, "first Tab selects the first candidate")
app.OnChar(0, "`t")
app.OnChar(0, "`r")
Assert(app.Navigating && app.Tracker.Word == "confi", "Tab Enter notifications preserve conversion state")
app.Action(bindings["tab"])
Assert(app.Selected = 2, "second Tab selects the second candidate")
app.Action(bindings["+tab"])
Assert(app.Selected = 1, "Shift Tab selects previous")
app.Selected := 1
app.Action(bindings["up"])
Assert(app.Selected = 9, "Up wraps to ninth candidate")
app.Action(bindings["down"])
Assert(app.Selected = 1, "Down wraps to first")
Assert(app.CanIntercept(bindings["enter"]), "conversion mode permits Enter")
app.Action(bindings["enter"])
Assert(app.Committed = 1 && !app.Navigating && !app.Visible, "Enter commits selected candidate and ends mode")
Assert(app.Selected = 0, "commit returns to unselected state")
Assert(app.CanIntercept(bindings["enter"]), "held confirm Enter stays captured after popup closes")
app.Action(bindings["enter"])
Assert(app.Committed = 1, "repeat Enter never confirms twice")
app.ReleaseEnter()
for key, binding in bindings
    Assert(!app.CanIntercept(binding), "no visible candidate passes every key through")
app.Ready()
app.Action(bindings["^!9"])
Assert(app.Committed = 9, "ninth direct candidate can be accepted")
app.Ready()
app.Action(bindings["down"])
app.Action(bindings["esc"])
Assert(!app.Navigating && !app.Visible && !app.Committed, "Esc cancels conversion without commit")
app.Ready()
app.Allowed := false
for key in ["tab", "down", "enter"]
    Assert(!app.CanIntercept(bindings[key]), "unsafe or native IME snapshot passes keys through")
app.Allowed := true
app.Ready()
app.Target.Policy.ImeStyleKeys := false
for key in ["tab", "up", "enter"]
    Assert(!app.CanIntercept(bindings[key]), "per-app style opt out passes native keys through")
Assert(app.CanIntercept(bindings["^!space"]), "explicit accept shortcut remains available")
app.Ready()
app.Action(bindings["^!space"])
Assert(app.Committed = 1, "explicit accept can deliberately confirm first preview candidate")
app.Ready()
app.Action(bindings["down"])
app.OnChar(0, " ")
Assert(!app.Navigating && !app.Visible && app.Tracker.Word == "" && !app.Committed,
    "literal Space during navigation ends conversion without accepting a candidate")
app.Ready()
app.Target.Policy.Keys := false
Assert(!app.CanIntercept(bindings["down"]), "disabled app never captures navigation")
app.Ready(), app.Navigating := true, app.Selected := 1, app.Allowed := false
Assert(app.CanIntercept(bindings["enter"]), "conversion Enter is swallowed if validation temporarily fails")
app.Action(bindings["enter"])
Assert(!app.Committed && !app.Navigating, "failed conversion cancels instead of submitting")
app.Ready(), app.Navigating := true, app.Selected := 1, app.Ime.Allowed := false
Assert(!app.CanIntercept(bindings["enter"]), "open native IME still owns Enter")
app.Ready()
app.Action(bindings["tab"])
Assert(app.CanIntercept(bindings["enter"]), "confirm is armed before simulated early release")
app.ReleaseEnter()
app.Action(bindings["enter"])
Assert(app.Committed = 1 && !app.EnterLatched, "key-up before handler cannot leave a stuck latch")
Assert(!app.CanIntercept(bindings["enter"]), "a separate Enter after release passes through")
app.Ready(), app.Accepting := true, app.AcceptScopeKey := "test", app.Ime.Allowed := false
Assert(!app.CanIntercept(bindings["enter"]), "new native-IME Enter is not stolen during another commit")
FileAppend "PASS navigation_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}

class NavigationApp extends EacApplication {
    Allowed := true
    Committed := 0
    __New() {
        this.Config := {Enabled: true, AcceptKey: "^!Space", NextKey: "Tab", PreviousKey: "^!Up",
            CancelKey: "Esc", DirectModifier: "^!", DebounceMs: 30}
        this.RefreshCallback := ObjBindMethod(this, "Refresh")
        this.Ready()
        this.Ime := NavigationIme()
    }
    Ready() {
        this.Allowed := true
        this.Visible := true, this.Navigating := false, this.Selected := 0, this.Committed := 0
        this.ReleaseEnter()
        this.EnterActionArmed := false, this.Accepting := false
        if this.HasOwnProp("Ime")
            this.Ime.Allowed := true
        this.Tracker := EacInputTracker()
        this.Tracker.Feed("confi", "test")
        this.ShownGeneration := this.Tracker.Generation
        this.Pending := []
        this.Items := [1,2,3,4,5,6,7,8,9]
        this.Target := {Context: {Key: "test"}, Ime: {Key: "test"}, Field: {Before: "confi", After: ""},
            Policy: {Keys: true, Tab: false, Enter: false, ImeStyleKeys: true}}
    }
    Snapshot() => this.Allowed ? this.Target : false
    CurrentContext() => this.Target.Context
    Refresh() {
        if !this.Allowed
            this.Reset()
    }
    Reset(*) {
        this.Visible := false, this.Navigating := false, this.Selected := 0, this.Committed := 0
    }
    Commit() {
        if !this.Allowed {
            this.Reset()
            return false
        }
        this.Committed := this.Selected
        this.Visible := false, this.Navigating := false, this.Selected := 0
        return true
    }
    Modifiers() => 0
}

class NavigationIme {
    Allowed := true
    GetState(context) => {Allowed: this.Allowed, Key: "test", Reason: this.Allowed ? "IMEClosed" : "NativeIMEPriority"}
}
