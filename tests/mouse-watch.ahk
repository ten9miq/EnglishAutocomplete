#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; No keyboard/mouse input is generated and no user window is opened.
Checks := 0
App := MouseWatchApp()
OnError Fail
OnExit Cleanup

Assert(!App.CanWatchMouse(), "idle application does not activate mouse hotkeys")
App.Tracker.Feed("c", "fixture")
Assert(App.CanWatchMouse(), "single tracked letter is invalidated even before popup")
activations := 0
loop 1000 {
    if App.CanWatchMouse() {
        activations += 1
        App.Reset()
    }
}
Assert(activations = 1, "modelled wheel burst invalidates once, then stays inactive")
Assert(!App.CanWatchMouse(), "first invalidation disarms subsequent wheel events")
App.Tracker.Blocked := true
Assert(App.CanWatchMouse(), "blocked partial input is invalidated on mouse action")
App.Reset(), App.Visible := true
Assert(App.CanWatchMouse(), "visible popup enables delete click and other invalidation")
App.Reset(), App.Pending.Push({Word: "FixtureWord"})
Assert(App.CanWatchMouse(), "pending learning is cancelled by mouse action")
App.Reset(), App.ExcelStart := {Tick: 1}
Assert(App.CanWatchMouse(), "pending Excel editor transition is cancelled by mouse action")
App.Reset()
Assert(!App.CanWatchMouse(), "reset clears all mouse-watch reasons")

; Inspect the actual registered variants without sending OS input.
App.InstallMouse()
Assert(App.MouseBindings.Length = 5, "five pass-through mouse handlers are registered")
for binding in App.MouseBindings {
    Assert(IsObject(binding.Condition) && !binding.Condition.Call(), "all mouse registrations have an inactive idle HotIf")
    Assert(SubStr(binding.Key, 1, 1) == "~", "mouse registration preserves native event")
}
App.Visible := true
Assert(App.MouseBindings[1].Condition.Call(), "registered HotIf reflects live popup state")
App.Stop()
Assert(!App.CanWatchMouse(), "Stop leaves mouse-watch state idle")
FileAppend "PASS mouse_watch_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}
Fail(err, *) {
    FileAppend "FAIL " err.Message " at " err.Line "`n" err.Stack, "**"
    Cleanup()
    ExitApp 1
}
Cleanup(*) {
    global App
    if App
        try App.Stop()
}
class MouseWatchApp extends EacApplication {
    __New() {
        this.Tracker := EacInputTracker()
        this.KeyBindings := []
        this.TickCallback := (*) => 0
        this.RefreshCallback := (*) => 0
    }
    Reset(*) {
        this.Visible := false
        this.Tracker.Reset()
        this.Pending := []
        this.ExcelStart := false
    }
}
