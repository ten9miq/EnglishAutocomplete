#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\ManageDictionary.ahk

Checks := 0, Source := false, Target := false, Manager := false, Locker := false
Root := A_ScriptDir "\.."
Fixture := A_ScriptDir "\results\transfer-" DllCall("GetCurrentProcessId")
DirCreate Fixture "\source"
DirCreate Fixture "\target"
OnError Fail
OnExit Cleanup
Source := EacUserDictionary(Fixture "\source\user.db")
Target := EacUserDictionary(Fixture "\target\user.db")
rows := [["MyInternalTool", "12", "1700000000", "1", "0"], ["LearnedFixture", "2", "1700000020", "0", "0"],
    ["BlockedFixture", "0", "0", "0", "1"], ["teacher's", "1", "1700000030", "1", "0"]]
result := EacDictionaryTransfer.ImportRows(Source, rows)
Assert(result.Added = 4 && result.Updated = 0, "initial import reports additions")
backup := Fixture "\日本語-backup.csv"
Assert(EacDictionaryTransfer.Export(Source, backup) = 4, "export includes entire personal dictionary")
Assert(SubStr(FileRead(backup, "UTF-8"), 1, StrLen(EacDictionaryTransfer.Header)) = EacDictionaryTransfer.Header, "CSV has expected header")
restored := EacDictionaryTransfer.Read(backup)
Assert(restored.Length = 4, "UTF-8 BOM and Japanese file path roundtrip")
EacDictionaryTransfer.ImportRows(Target, restored)
copy := Fixture "\copy.csv"
EacDictionaryTransfer.Export(Target, copy)
Assert(FileRead(backup, "UTF-8") == FileRead(copy, "UTF-8"), "roundtrip preserves spelling, counts, timestamps, manual and blocked flags")
incoming := [["MYINTERNALTOOL", "99", "1700000090", "0", "1"], ["NewFixture", "3", "1700000040", "0", "0"]]
result := EacDictionaryTransfer.ImportRows(Target, incoming)
Assert(result.Added = 1 && result.Skipped = 1 && result.Updated = 0, "default merge adds new and skips existing words")
Assert(Target.Db.Query("SELECT word,uses,manual,blocked FROM personal WHERE norm='myinternaltool'")[1][1] == "MyInternalTool", "default merge preserves existing spelling and values")
result := EacDictionaryTransfer.ImportRows(Target, incoming, true)
Assert(result.Updated = 2 && result.Added = 0 && result.Skipped = 0, "overwrite replaces all matching metadata without adding frequency")
Assert(Target.IsBlocked("myinternaltool"), "overwrite restores imported block status")
Assert(Target.Db.Query("SELECT uses FROM personal WHERE norm='myinternaltool'")[1][1] = "99", "frequency is restored exactly")
Assert(Target.Db.Query("SELECT count(*) FROM personal WHERE norm='learnedfixture'")[1][1] = "1", "merge retains words absent from import")
before := Snapshot(Target)
for badRows in [
    [["ValidFixture", "1", "0", "1", "0"], ["invalid word", "1", "0", "0", "0"]],
    [["GoodWord", "-1", "0", "0", "0"]], [["GoodWord", "1.5", "0", "0", "0"]],
    [["GoodWord", "2147483648", "0", "0", "0"]], [["GoodWord", "1", "253402214401", "0", "0"]],
    [["GoodWord", "1", "0", "2", "0"]], [["GoodWord", "1", "0", "0", "2"]],
    [["GoodWord", "1", "0", "0"]], [["GoodWord", "1", "0", "0", "0"], ["GOODWORD", "2", "0", "0", "0"]]] {
    Assert(ImportRejected(badRows), "invalid rows rejected")
    Assert(Snapshot(Target) == before, "invalid import makes no changes")
}
Assert(EacDictionaryTransfer.ParseLine('"GoodWord","1","0","1","0"')[1] == "GoodWord", "quoted CSV fields supported")
Assert(EacDictionaryTransfer.ParseLine('"a""b",1,0,1,0')[1] == 'a"b', "CSV escaped quotes parsed before word validation")
for text in ['"GoodWord,1,0,1,0', 'Good"Word,1,0,1,0', '"GoodWord"x,1,0,1,0']
    Assert(ParseRejected(text), "malformed CSV quotes rejected")
invalid := Fixture "\invalid.csv"
FileAppend "word,wrong_header`n", invalid, "UTF-8"
Assert(ReadRejected(invalid), "incompatible header rejected")
FileDelete invalid
FileAppend EacDictionaryTransfer.Header "`nGoodWord,1,0,1,0,extra`n", invalid, "UTF-8"
Assert(ReadRejected(invalid), "extra CSV columns rejected")
FileDelete invalid
csvFile := FileOpen(invalid, "w", "UTF-16")
csvFile.Write(EacDictionaryTransfer.Header "`nGoodWord,1,0,1,0`n"), csvFile.Close()
Assert(ReadRejected(invalid), "UTF-16 with embedded NUL bytes rejected")
FileDelete invalid
csvFile := FileOpen(invalid, "w", "UTF-8-RAW")
bytes := Buffer(2), NumPut("UChar", 0xC0, bytes, 0), NumPut("UChar", 0xAF, bytes, 1)
csvFile.RawWrite(bytes), csvFile.Close()
Assert(ReadRejected(invalid), "invalid UTF-8 rejected without replacement decoding")
Assert(ExportRejected(Fixture "\target\user.db"), "export cannot overwrite SQLite DB")
Assert(ExportRejected(backup), "existing export is protected unless overwrite is explicit")
Assert(FileRead(backup, "UTF-8") == FileRead(copy, "UTF-8"), "failed overwrite preserves original CSV")
Assert(EacDictionaryTransfer.Export(Source, backup, true) = 4, "explicit CSV overwrite succeeds")

Target.Db.Query("CREATE TEMP TRIGGER transfer_abort BEFORE INSERT ON personal WHEN NEW.norm='rollbackfixture' BEGIN SELECT RAISE(ABORT,'fixture'); END")
Assert(ImportRejected([["BeforeRollback", "1", "0", "1", "0"], ["RollbackFixture", "1", "0", "1", "0"]]), "database failure during import is reported")
Assert(Snapshot(Target) == before, "database failure rolls back earlier inserted rows")
Target.Db.Query("DROP TRIGGER transfer_abort")
Locker := EacSQLite(Fixture "\target\user.db")
Locker.Query("BEGIN EXCLUSIVE")
try Assert(ImportRejected([["LockedFixture", "1", "0", "1", "0"]]), "locked DB rejects entire import")
finally Locker.Query("ROLLBACK"), Locker.Close(), Locker := false
Assert(Snapshot(Target) == before, "lock failure preserves all data")
Target.Clear()
Target.Db.Query("WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<10000) INSERT INTO personal(norm,word) SELECT 'capacity' || i,'Capacity' || i FROM n")
Assert(ImportRejected([["TooManyFixture", "1", "0", "1", "0"]]), "merged capacity above 10000 is rejected")
Assert(Target.Db.Query("SELECT count(*) FROM personal")[1][1] = "10000", "capacity rejection does not change rows")
result := EacDictionaryTransfer.ImportRows(Target, [["Capacity1", "7", "0", "1", "0"]], true)
Assert(result.Updated = 1, "updating existing word is allowed at capacity")
Target.Clear(), Target.Db.Close(), Target := false

Manager := TransferManagement({Root: Root, DataDirectory: Fixture "\target", PromotionCount: 2})
Assert(!Manager.Overwrite.Value, "GUI defaults to keeping existing data")
Manager.TransferPath := backup
Manager.Allow := false
Manager.Import()
Assert(!Manager.Store.List().Total, "cancelled GUI import does not write")
Manager.Allow := true
Manager.Import()
Assert(Manager.Store.List().Total = 4 && InStr(Manager.Status.Text, "インポート完了"), "GUI import writes and reports result")
Manager.Search.Value := "missing", Manager.SearchNow()
Manager.TransferPath := Fixture "\gui-export.csv"
Manager.Export()
Assert(EacDictionaryTransfer.Read(Manager.TransferPath).Length = 4, "GUI exports all personal data despite active search")
Manager.Allow := false
Manager.TransferPath := SubStr(backup, 1, -4)
Manager.Export()
Assert(FileRead(backup, "UTF-8") == FileRead(copy, "UTF-8"), "extension auto-append respects overwrite cancellation")
Manager.TransferPath := ""
Manager.Export(), Manager.Import()
Assert(Manager.Store.List().Total = 4, "file selection cancellation leaves dictionary unchanged")
empty := Fixture "\empty.csv"
FileAppend EacDictionaryTransfer.Header "`r`n", empty, "UTF-8"
Assert(!EacDictionaryTransfer.ImportRows(Manager.Store.Personal, EacDictionaryTransfer.Read(empty)).Added, "empty dictionary CSV imports without deleting existing data")
Manager.Close(), Manager := false
FileAppend "PASS transfer_checks=" Checks " AHK=" A_AhkVersion " pointer_size=" A_PtrSize "`n", "*"
Cleanup()
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}
Snapshot(personal) {
    result := ""
    for row in personal.Db.Query("SELECT norm,word,uses,last_used,manual,blocked FROM personal ORDER BY norm")
        for value in row
            result .= value "|"
    return result
}
ImportRejected(rows) {
    global Target
    try EacDictionaryTransfer.ImportRows(Target, rows, true)
    catch
        return true
    return false
}
ParseRejected(text) {
    try EacDictionaryTransfer.ParseLine(text)
    catch
        return true
    return false
}
ReadRejected(path) {
    try EacDictionaryTransfer.Read(path)
    catch
        return true
    return false
}
ExportRejected(path) {
    global Source
    try EacDictionaryTransfer.Export(Source, path)
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
    global Source, Target, Manager, Locker, Fixture
    if Locker
        Locker.Close(), Locker := false
    if Manager
        Manager.Close(), Manager := false
    if Target
        Target.Db.Close(), Target := false
    if Source
        Source.Db.Close(), Source := false
    for directory in [Fixture "\source", Fixture "\target", Fixture] {
        if DirExist(directory) {
            loop files directory "\*", "F"
                FileDelete A_LoopFileFullPath
            DirDelete directory
        }
    }
}

class TransferManagement extends EacDictionaryManager {
    TransferPath := ""
    Allow := false
    SelectTransferPath(save) => this.TransferPath
    Confirm(prompt) => this.Allow
}
