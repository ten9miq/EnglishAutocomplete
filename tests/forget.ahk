#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

Checks := 0, App := false
Root := A_ScriptDir "\.."
Path := A_ScriptDir "\results\forget-user.db"
DirCreate A_ScriptDir "\results"
for suffix in ["", "-journal", "-wal", "-shm"]
    if FileExist(Path suffix)
        FileDelete Path suffix
OnError Fail
OnExit Cleanup
settings := EacConfig(Root, Root "\settings.default.ini")
user := EacUserDictionary(Path)
engine := EacSuggestionEngine(Root "\data\dictionary.db", settings, user)
App := ForgetApp(settings, user, engine)

user.Observe("ForgetFixtureWord"), user.Observe("ForgetFixtureWord")
App.Ready("forgetfixture")
Assert(App.SelectedLearned(), "promoted unknown is marked learned")
ticket := App.Items[1]
App.Selected := 0
Assert(!App.DeleteLearned(ticket), "unselected candidate cannot delete")
App.Selected := 1, App.Visible := false
Assert(!App.DeleteLearned(ticket), "hidden candidate cannot delete")
App.Visible := true, App.ShownGeneration -= 1
Assert(!App.DeleteLearned(ticket), "expired generation cannot delete")
App.ShownGeneration := App.Tracker.Generation
Assert(!App.DeleteLearned({Norm: ticket.Norm, Learned: true}), "old or substituted row object cannot delete")
App.Allowed := false
Assert(!App.DeleteLearned(ticket), "unsafe snapshot cannot delete")
App.Allowed := true, App.Target.Policy.Keys := false
Assert(!App.DeleteLearned(ticket), "keys-disabled app cannot delete")
App.Target.Policy.Keys := true, App.Ime.Allowed := false
Assert(!App.DeleteLearned(ticket), "native IME priority cannot delete")
App.Ime.Allowed := true, App.PositionOffset := 1
Assert(!App.DeleteLearned(ticket), "moved caret cannot delete")
App.PositionOffset := 0, App.ContextKey := "other"
Assert(!App.DeleteLearned(ticket), "changed focus cannot delete")
App.ContextKey := "fixture"
Assert(user.Db.Query("SELECT count(*) FROM personal WHERE norm=?", [ticket.Norm])[1][1] = "1", "guard failures preserve stored word")
App.Pending := [{Word: ticket.Word, ContextKey: "fixture", Tick: A_TickCount, Boundary: false}]
Assert(App.DeleteLearned(ticket), "selected learned unknown deleted")
Assert(!App.Items.Length && !App.Selected && !App.Navigating, "deleted unknown disappears and selection ends")
Assert(!App.Pending.Length, "pending observation cannot immediately relearn deleted word")
user.Db.Close()
user := EacUserDictionary(Path), engine.Personal := user, App.User := user
Assert(!engine.Search("forgetfixture").Length, "unknown deletion persists after database reopen")
user.Observe("ForgetFixtureWord")
Assert(!engine.Search("forgetfixture").Length, "deleted unknown starts again at first observation")
user.Observe("ForgetFixtureWord")
Assert(engine.Search("forgetfixture").Length = 1, "later deliberate retyping can learn again")

base := engine.Search("confidenc")[1]
Assert(!base.Learned, "base dictionary candidate is not marked learned")
user.Observe("confidence")
App.Ready("confidenc")
Assert(App.Items[1].Learned && App.Items[1].Score > base.Score, "known word learning marked and ranked")
Assert(App.DeleteLearned(App.Items[1]), "known word history deleted")
Assert(App.Items.Length && App.Items[1].Norm = "confidence" && !App.Items[1].Learned
    && App.Items[1].Score = base.Score, "base word remains with original score")
user.Observe("ManualFixtureWord", true), user.Observe("ManualFixtureWord")
App.Ready("manualfixture")
Assert(!App.SelectedLearned(), "manual entry is protected even after automatic learning")
Assert(!user.ForgetLearned("ManualFixtureWord"), "transaction refuses manual entry")
user.Block("BlockedFixtureWord")
Assert(!user.ForgetLearned("BlockedFixtureWord"), "transaction preserves blocked entry")
Assert(!user.ForgetLearned("MissingFixtureWord"), "transaction refuses absent entry")
Assert(user.Db.Query("SELECT manual FROM personal WHERE norm='manualfixtureword'")[1][1] = "1", "manual data preserved")
Assert(user.IsBlocked("blockedfixtureword"), "blocked data preserved")
App.Ready("forgetfixture")
ticket := App.Items[1]
locker := EacSQLite(Path)
locker.Query("BEGIN EXCLUSIVE")
Assert(!App.DeleteLearned(ticket) && App.Items[1] = ticket && App.Selected = 1, "locked DB does not falsely remove displayed row")
locker.Query("ROLLBACK"), locker.Close()
Assert(user.Db.Query("SELECT count(*) FROM personal WHERE norm='forgetfixtureword'")[1][1] = "1", "failed delete leaves database intact")
FileAppend "PASS forget_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
Cleanup()
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
    global App, Path
    if App {
        App.User.Db.Close(), App.Engine.Db.Close(), App.Gui.Dispose()
        App := false
    }
    for suffix in ["", "-journal", "-wal", "-shm"]
        if FileExist(Path suffix)
            try FileDelete Path suffix
}
class ForgetApp extends EacApplication {
    Allowed := true
    PositionOffset := 0
    ContextKey := "fixture"
    __New(config, user, engine) {
        this.Config := config, this.User := user, this.Engine := engine
        this.Tracker := EacInputTracker(), this.Ime := ForgetIme(), this.Gui := EacSuggestionGui(config)
    }
    Ready(prefix) {
        this.Tracker.Reset(), this.Tracker.Feed(prefix, "fixture")
        this.Items := this.Engine.Search(prefix)
        this.Selected := 1, this.Navigating := true, this.Visible := true
        this.ShownGeneration := this.Tracker.Generation
        this.Target := {Context: {Key: "fixture"}, Ime: {Key: "closed"},
            Field: {Before: prefix, After: "", Position: StrLen(prefix)}, Policy: {Enabled: true, Keys: true}}
    }
    Snapshot() => this.Allowed ? {Context: {Key: this.ContextKey}, Ime: {Key: "closed"}, Policy: this.Target.Policy,
        Field: {Before: this.Tracker.Word, After: "", Position: StrLen(this.Tracker.Word) + this.PositionOffset}} : false
    CurrentContext() => {Key: this.ContextKey}
    Refresh() => this.Items := this.Engine.Search(this.Tracker.Word)
}
class ForgetIme {
    Allowed := true
    GetState(context) => {Allowed: this.Allowed, Key: "closed"}
}
