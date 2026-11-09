#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

SetWorkingDir A_ScriptDir
Root := A_ScriptDir "\.."
DirCreate A_ScriptDir "\results"
ResultFile := A_ScriptDir "\results\core.txt"
if FileExist(ResultFile)
    FileDelete ResultFile
OnError TestError
Checks := 0
Fixture := A_ScriptDir "\results\個人辞書-test.db"
for suffix in ["", "-journal", "-wal", "-shm"]
    if FileExist(Fixture suffix)
        FileDelete Fixture suffix
settingsPath := A_ScriptDir "\results\settings.ini"
FileCopy Root "\settings.default.ini", settingsPath, true
Settings := EacConfig(Root, settingsPath)
Assert(Settings.MinLength == 2, "default minimum prefix length")
Assert(Settings.MaxCandidates == 9, "default candidate count")
Assert(Settings.InitialCandidates == 5, "initial visible count")
Assert(Settings.OffsetX = 0 && Settings.OffsetY = 24, "default caret spacing")
Assert(Settings.PromotionCount = 2, "unknown words require two verified uses by default")
StartTime := NowMs()
Personal := EacUserDictionary(Fixture, Settings.PromotionCount)
Assert(Personal.Enabled, "SQLite native Unicode path")
LoadStart := NowMs()
Engine := EacSuggestionEngine(Root "\data\dictionary.db", Settings, Personal)
LoadMs := NowMs() - LoadStart
Assert(Engine.Db.Query("PRAGMA integrity_check")[1][1] == "ok", "dictionary integrity")
Assert(Integer(Engine.Db.Query("SELECT count(*) FROM words")[1][1]) > 100000, "full dictionary shipped")
Assert(Engine.Search("confi").Length == Settings.MaxCandidates, "prefix query returns configured candidate count")
Assert(!HasWord(Engine.Search("teacher"), "teacher's"), "unrequested possessive is omitted")
Assert(HasWord(Engine.Search("teacher'"), "teacher's"), "explicit apostrophe retains possessive completion")
Assert(HasWord(Engine.Search("it'"), "it's"), "contractions remain available")
Assert(!EacUserDictionary.Valid("teacher'", true), "partial apostrophe prefix is never a registerable word")
Assert(!EacSuggestionEngine.ValidPrefix("teacher''"), "repeated apostrophe prefix remains invalid")
Assert(Engine.Search("CONFI")[1].Norm == Engine.Search("confi")[1].Norm, "case insensitive search")
Assert(Engine.Search("zzzzzzzzzzzz").Length == 0, "unknown prefix")
Assert(Engine.Search("c").Length == 0, "one character is below minimum length")
Assert(Engine.Search("co").Length == Settings.MaxCandidates, "two characters return configured candidate count")
for item in Engine.Search("co")
    Assert(SubStr(item.Norm, 1, 2) == "co", "two-character prefix boundary")
Assert(Engine.Search("xyz@abc").Length == 0, "invalid input")
for item in Engine.Search("compu")
    Assert(SubStr(item.Norm, 1, 5) == "compu", "prefix boundary")
Assert(EacSuggestionEngine.ApplyCase("computer", "COM") == "COMPUTER", "uppercase suffix")
Assert(EacSuggestionEngine.ApplyCase("computer", "com") == "computer", "lowercase stays lowercase")
Assert(EacSuggestionEngine.ApplyCase("computer", "Com") == "Computer", "titlecase suffix")
Assert(EacSuggestionEngine.ApplyCase("OpenAI", "Ope") == "OpenAI", "proper case suffix")
Personal.Observe("MyInternalTool")
Assert(!HasWord(Engine.Search("myi"), "myinternaltool"), "unknown once not promoted")
Personal.Observe("MyInternalTool")
Assert(HasWord(Engine.Search("myi"), "myinternaltool"), "unknown promoted after exactly two uses")
Personal.Db.Close()
Personal := EacUserDictionary(Fixture, 3)
Engine.Personal := Personal
Assert(!HasWord(Engine.Search("myi"), "myinternaltool"), "existing two-use row hidden at old threshold")
Personal.Db.Close()
Personal := EacUserDictionary(Fixture)
Engine.Personal := Personal
Assert(HasWord(Engine.Search("myi"), "myinternaltool"), "lower threshold promotes existing two-use row without DB migration")
Assert(Personal.Db.Query("SELECT word FROM personal WHERE norm='myinternaltool'")[1][1] == "MyInternalTool", "CamelCase preserved")
Personal.Observe("myinternaltool")
Assert(Personal.Db.Query("SELECT count(*) FROM personal WHERE norm='myinternaltool'")[1][1] == "1", "normalized duplicates")
Assert(Personal.Db.Query("SELECT word FROM personal WHERE norm='myinternaltool'")[1][1] == "MyInternalTool", "automatic usage preserves learned canonical case")
Assert(Personal.Db.Query("SELECT uses FROM personal WHERE norm='myinternaltool'")[1][1] == "3", "usage increments")
for word in ["OpenAI", "Codex", "getUserInfo", "AutoHotkey", "kubectl", "kustomize", "php-fpm", "config.toml", "snake_case", "Tool2"]
    Assert(Personal.Observe(word, true), "manual technical word " word)
Assert(HasWord(Engine.Search("config.t"), "config.toml"), "dotted manual completion")
Assert(Engine.Search("ope")[1].Word == "OpenAI", "manual ranking boost")
Personal.Observe("OPENAI")
Assert(Personal.Db.Query("SELECT word FROM personal WHERE norm='openai'")[1][1] == "OpenAI", "automatic uppercase preserves manual CamelCase")
Personal.Observe("CONFIDENCE")
Assert(Engine.Search("confidenc")[1].Word == "confidence", "automatic uppercase does not override static spelling")
previousScore := Engine.Search("confidenc")[1].Score
Personal.Observe("confidence")
Assert(Engine.Search("confidenc")[1].Score = previousScore + 100, "known word usage still increases ranking score")
for word in ["name@example.com", "https://example.com", "abc123Secret", "password", "Bearer_abc", "token_abc", "config.toml", "php-fpm"]
    Assert(!Personal.Observe(word), "learning excluded " word)
Personal.Block("OpenAI")
Assert(!Personal.Observe("OpenAI", true), "blocked learning")
Assert(!HasWord(Engine.Search("ope"), "openai"), "blocked suggestion")
Personal.Block("computer")
Assert(!HasWord(Engine.Search("compu"), "computer"), "blocked standard suggestion")
Personal.Delete("OpenAI")
Assert(Personal.Observe("OpenAI", true), "delete unblocks explicit registration")
Personal.ResetFrequency()
Assert(Personal.Db.Query("SELECT uses FROM personal WHERE norm='openai'")[1][1] == "0", "frequency reset")
Personal.Db.Close()
Personal := EacUserDictionary(Fixture, 3)
Engine.Personal := Personal
Assert(Personal.Db.Query("SELECT word FROM personal WHERE norm='openai'")[1][1] == "OpenAI", "SQLite restart persistence")
Assert(HasWord(Engine.Search("ope"), "openai"), "manual survives reset and restart")
Tracker := EacInputTracker()
Tracker.Feed("confi", "1:2")
Assert(Tracker.Word == "confi", "input characters")
Tracker.Backspace()
Assert(Tracker.Word == "conf", "backspace shortens observed prefix for verification")
Tracker.Feed("abc", "1:2")
Tracker.Feed("def", "1:3")
Assert(Tracker.Word == "def", "focus invalidates")
Tracker.Reset()
Assert(Tracker.Feed("name@example.com ", "1:2")[1] == "name@example.com", "email stays one segment")
Tracker.Reset()
Tracker.Feed("compu", "1:2")
Tracker.Word := "computer", Tracker.Learned := true
Assert(Tracker.Feed(" ", "1:2").Length == 0, "completion not learned recursively")
Tracker.Reset()
Loop 20
    Tracker.Feed("abc", "1:2")
Assert(StrLen(Tracker.Word) == 60, "rapid consecutive input")
Tracker.Feed("abcdef", "1:2")
Assert(Tracker.Blocked && Tracker.Word == "", "input size bound")
Tracker.Feed(" ", "1:2")
Assert(!Tracker.Blocked, "boundary releases overlength block")
Assert(EacFieldGuard.Matches({Before: "hello compu", After: " "}, "compu"), "actual prefix match")
Assert(!EacFieldGuard.Matches({Before: "hello compu", After: "ter"}, "compu"), "middle of word refuses")
Assert(!EacFieldGuard.Matches({Before: "user@compu", After: ""}, "compu"), "email prefix refuses")
Assert(!EacFieldGuard.Matches({Before: "other", After: ""}, "compu"), "auto correction mismatch refuses")
Assert(!EacFieldGuard.Matches({Before: "Compu", After: ""}, "compu"), "case-only auto correction mismatch refuses")
Assert(EacFieldGuard.Matches({Before: "computer `r`n", After: ""}, "computer", true), "boundary learning verification")
Assert(!EacFieldGuard.Matches({Before: "computer", After: ""}, "computer", true), "no boundary no learning")
Assert(Settings.Policy("excel.exe").Enabled && Settings.Policy("excel.exe").Keys, "Excel safe fields can complete without app opt-in")
Assert(Settings.Policy("code.exe").Enabled && Settings.Policy("code.exe").Keys, "VS Code safe fields can complete without app opt-in")
Assert(Settings.Policy("unknown.exe").Enabled && Settings.Policy("unknown.exe").Learning, "unknown app can complete and learn in verified safe fields")
for process in ["notepad.exe", "notepad++.exe", "sakura.exe", "chrome.exe", "brave.exe", "msedge.exe", "chatgpt.exe", "codex.exe"]
    Assert(Settings.Policy(process).Enabled && Settings.Policy(process).Learning, "default supported app learns " process)
Assert(!Settings.Policy("keepass.exe").Enabled && !Settings.Policy("keepass.exe").Learning, "excluded app cannot learn")
IniWrite 0, settingsPath, "app:optout.exe", "Learning"
Assert(!EacConfig(Root, settingsPath).Policy("optout.exe").Learning, "explicit per-app learning opt-out")
IniWrite 0, settingsPath, "app:optout.exe", "Enabled"
Assert(!EacConfig(Root, settingsPath).Policy("optout.exe").Enabled, "explicit per-app completion opt-out")
IniWrite 0, settingsPath, "General", "Learning"
Assert(!EacConfig(Root, settingsPath).Policy("chrome.exe").Learning, "general learning opt-out overrides enabled profile")
IniDelete settingsPath, "General", "Learning"
IniDelete settingsPath, "General", "PromotionCount"
IniDelete settingsPath, "Applications", "DefaultLearning"
IniDelete settingsPath, "Applications", "DefaultEnabled"
fallback := EacConfig(Root, settingsPath)
Assert(fallback.PromotionCount = 2 && fallback.Policy("unknown.exe").Learning && fallback.Policy("unknown.exe").Enabled, "missing INI keys enable verified-field completion and learning")
Assert(Settings.Policy("notepad.exe").Tab == false, "Tab unchanged default")
BrokenPath := A_ScriptDir "\results\broken.db"
if FileExist(BrokenPath)
    FileDelete BrokenPath
FileAppend "not a sqlite database", BrokenPath
Broken := EacUserDictionary(BrokenPath)
Assert(!Broken.Enabled && !Broken.Observe("TestingWord"), "corrupt DB safe stop")
FileDelete BrokenPath
FuturePath := A_ScriptDir "\results\future.db"
futureDb := EacSQLite(FuturePath)
futureDb.Query("PRAGMA user_version=999")
futureDb.Close()
Future := EacUserDictionary(FuturePath)
Assert(!Future.Enabled, "future schema refused")
FileDelete FuturePath
Locker := EacSQLite(Fixture)
Locker.Query("BEGIN EXCLUSIVE")
Assert(!Personal.Observe("LockedDatabaseTest", true) && !Personal.Enabled, "locked DB safe stop")
Locker.Query("ROLLBACK")
Locker.Close()
Personal.Db.Close()
Personal := EacUserDictionary(Fixture, 3)
Engine.Personal := Personal
Samples := []
Prefixes := ["co", "th", "pr", "con", "confi", "compu", "pro", "the", "un", "sta", "ope", "zzz", "config.t", "absolutelylongunknown"]
Loop 1000 {
    prefix := Prefixes[Mod(A_Index - 1, Prefixes.Length) + 1]
    t := NowMs()
    Engine.Search(prefix)
    Samples.Push(NowMs() - t)
}
Sorted := []
for sample in Samples {
    index := 1
    while index <= Sorted.Length && Sorted[index] < sample
        index += 1
    Sorted.InsertAt(index, sample)
}
P95 := Sorted[Ceil(Sorted.Length * 0.95)]
Assert(P95 < 10, "prefix search P95 under 10ms")
memory := Buffer(A_PtrSize == 8 ? 80 : 44, 0)
NumPut "UInt", memory.Size, memory
DllCall "psapi\GetProcessMemoryInfo", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "Ptr", memory, "UInt", memory.Size
WorkingSet := NumGet(memory, A_PtrSize == 8 ? 16 : 12, "UPtr") / 1048576
Record("METRIC dictionary_open_ms=" Round(LoadMs, 3))
Record("METRIC prefix_p95_ms=" Round(P95, 3) " n=1000 includes SQLite+personal+ranking")
Record("METRIC working_set_mb=" Round(WorkingSet, 2) " test_process_after_benchmark")
Record("PASS checks=" Checks " AHK=" A_AhkVersion " OS=" A_OSVersion " x64=" (A_PtrSize == 8))
Personal.Db.Close()
Engine.Db.Close()
FileDelete Fixture
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error("FAIL " description)
}

HasWord(items, norm) {
    for item in items
        if item.Norm == norm
            return true
    return false
}

NowMs() {
    static frequency := 0
    if !frequency
        DllCall "QueryPerformanceFrequency", "Int64*", &frequency
    DllCall "QueryPerformanceCounter", "Int64*", &counter := 0
    return counter * 1000 / frequency
}

Record(message) {
    global ResultFile
    FileAppend message "`n", ResultFile, "UTF-8"
    FileAppend message "`n", "*", "UTF-8"
}

TestError(err, *) {
    Record("FAIL " err.Message " at " err.File ":" err.Line " " err.Stack)
    ExitApp 1
}
