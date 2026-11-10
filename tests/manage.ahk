#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\ManageDictionary.ahk

Checks := 0, Store := false, Manager := false, Help := false, Reader := false
Root := A_ScriptDir "\.."
Fixture := A_ScriptDir "\results\management-" DllCall("GetCurrentProcessId")
DirCreate Fixture
Config := {Root: Root, DataDirectory: Fixture, PromotionCount: 2}
OnError Fail
OnExit Cleanup

Assert(InStr(EacManage([], {}), "--gui"), "no arguments return usage without accessing config or DB")
Assert(InStr(EacManage(["--help"], {}), "--add"), "help does not access config or DB")
Assert(!FileExist(Fixture "\user.db"), "help does not create a database")
for args in [["--unknown"], ["--add"], ["--delete", "word", "extra"], ["--reset-user", "extra"],
    ["--reset-frequency", "extra"], ["--block", "a'b' OR 1=1"], ["--unblock", "x"]]
    Assert(Rejected(args), "invalid arguments rejected before config access")

EacManage(["--add", "MyInternalTool"], Config)
Store := EacDictionaryStore(Config)
Reader := EacUserDictionary(Fixture "\user.db")
Assert(Store.List().Total = 1, "CLI add persists and closes connection")
Store.Apply(["--add", "MYInternalTool"])
Assert(Store.List(1, "myinternal").Rows[1][1] == "MYInternalTool", "manual spelling update preserves normalization")
Store.Personal.Observe("LearnedFixture"), Store.Personal.Observe("LearnedFixture")
Assert(Store.List(1, "", 2).Total = 1 && Store.List(1, "", 3).Total = 1, "manual and learned filters")
Store.Apply(["--block", "MyInternalTool"])
Assert(Reader.IsBlocked("myinternaltool"), "independent resident-style connection sees block immediately")
Assert(Store.List(1, "", 4).Total = 1, "blocked filter")
Assert(!Store.List(1, "", 2).Total, "block clears manual status")
Assert(ThrowsApply(["--add", "MyInternalTool"]), "blocked registration reports failure")
Store.Apply(["--unblock", "MyInternalTool"])
Assert(!Reader.IsBlocked("myinternaltool"), "unblock visible to existing connection")
Store.Apply(["--add", "MyInternalTool"])
Assert(Store.List(1, "myinternal", 2).Total = 1, "unblocked word can be manually registered")
Store.Apply(["--reset-frequency"])
Assert(Store.List(1, "myinternal").Rows[1][3] = "0", "frequency reset clears uses")
Assert(Store.List(1, "", 2).Total = 1, "frequency reset keeps manual registration")
Store.Apply(["--delete", "MyInternalTool"])
Assert(!Store.List(1, "myinternal").Total, "delete removes personal entry")
Assert(!Store.List(1, "' OR 1=1 --").Total, "search binds SQL-like input literally")
Store.Apply(["--block", "confidence"])
Assert(Store.List(2, "confidence").Total > 0, "blocked base word remains in read-only distribution dictionary")
Assert(Store.List(2, "信頼").Total > 0, "base dictionary Japanese translation search")
Assert(ReadOnly(), "distribution dictionary refuses writes")
Store.Apply(["--reset-user"])
Assert(!Store.List().Total, "explicit reset clears all personal data")

loop 105
    Store.Apply(["--add", "FixtureWord" A_Index])
page := Store.List(1, "fixtureword")
Assert(page.Rows.Length = 100 && page.Total = 105 && page.Pages = 2, "pagination counts full result and limits rows")
page := Store.List(1, "fixtureword", 1, 99)
Assert(page.Page = 2 && page.Rows.Length = 5, "page is clamped to last page")
Assert(Store.List(1, "fixtureword", 1, -1).Page = 1, "page is clamped to first page")
locker := EacSQLite(Fixture "\user.db")
locker.Query("BEGIN EXCLUSIVE")
try {
    Assert(ThrowsList(), "locked database reports a read failure")
    Assert(ThrowsApply(["--delete", "FixtureWord1"]), "locked database reports a write failure")
} finally {
    locker.Query("ROLLBACK"), locker.Close()
}
Assert(Store.List(1, "fixtureword1").Total > 0, "failed operation preserves stored words")
Store.Close(), Store := false

Help := EacDictionaryHelp(Root)
Assert(Help.Window.Hwnd && InStr(Help.Window.Title, "使い方"), "no-argument help window constructs")
Help.Window.Destroy(), Help := false
Manager := CancelManagement(Config)
Assert(Manager.List.GetCount() = 100, "management GUI renders bounded personal rows")
Manager.List.Modify(1, "Select Focus")
Manager.SelectWord(Manager.List, 1, true)
Assert(Manager.Word.Value = Manager.List.GetText(1, 1), "selection targets displayed word")
Manager.Source.Choose(2), Manager.Search.Value := "confidence"
Manager.SearchNow()
Assert(!Manager.Kind.Enabled && Manager.List.GetCount() > 0, "base GUI search disables personal filter")
Manager.Source.Choose(1), Manager.Search.Value := "GuiFixtureWord", Manager.SearchNow()
Manager.Word.Value := "GuiFixtureWord"
Manager.Execute("--add")
Assert(Manager.List.GetCount() = 1 && InStr(Manager.Status.Text, "完了"), "GUI register action writes and refreshes results")
for command in ["--block", "--delete", "--reset-frequency", "--reset-user"] {
    Manager.Execute(command)
    row := Manager.Store.List(1, "guifixtureword").Rows[1]
    Assert(row[3] = "1" && row[2] = "1" && row[5] = "0", "cancelled " command " preserves data")
}
Manager.Close(), Manager := false
Assert(RegExMatch(EacDictionaryManager.LocalTime(1700000000), "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}"), "local timestamp formatting")
Reader.Db.Close(), Reader := false
FileAppend "PASS management_checks=" Checks " AHK=" A_AhkVersion " pointer_size=" A_PtrSize "`n", "*"
Cleanup()
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}
Rejected(args) {
    try EacManage(args, {})
    catch as err
        return !InStr(err.Message, "property named")
    return false
}
ThrowsApply(args) {
    global Store
    try Store.Apply(args)
    catch
        return true
    return false
}
ThrowsList() {
    global Store
    try Store.List()
    catch
        return true
    return false
}
ReadOnly() {
    global Store
    try Store.Distribution.Query("DELETE FROM words WHERE norm='management_fixture_does_not_exist'")
    catch
        return true
    return false
}
Fail(err, *) {
    FileAppend "FAIL " err.Message " at " err.Line "`n" err.Stack, "**"
    Cleanup()
    ExitApp 1
}
Cleanup(*) {
    global Store, Manager, Help, Reader, Fixture
    if Help
        Help.Window.Destroy(), Help := false
    if Manager
        Manager.Close(), Manager := false
    if Store
        Store.Close(), Store := false
    if Reader
        Reader.Db.Close(), Reader := false
    for suffix in ["", "-journal", "-wal", "-shm"]
        if FileExist(Fixture "\user.db" suffix)
            FileDelete Fixture "\user.db" suffix
    if DirExist(Fixture)
        DirDelete Fixture
}

class CancelManagement extends EacDictionaryManager {
    ; Exercise the real cancellation branch without input or a modal dialog.
    Confirm(prompt) => false
}
