#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\ManageDictionary.ahk

Checks := 0, Personal := false, Engine := false, Store := false
Root := A_ScriptDir "\.."
DictionaryPath := A_Args.Length ? A_Args[1] : Root "\data\dictionary.db"
Fixture := A_ScriptDir "\results\it-" DllCall("GetCurrentProcessId")
DirCreate Fixture
settingsPath := Fixture "\settings.ini"
FileCopy Root "\settings.default.ini", settingsPath
IniWrite Fixture, settingsPath, "General", "DataDirectory"
OnError Fail
OnExit Cleanup
Config := EacConfig(Root, settingsPath)
Assert(Config.IT && Config.AISupplement && Config.ITScoreBoost = 1200 && Config.AIScoreBoost = 300, "default IT and AI options")
for key in ["IT", "ITScoreBoost", "AISupplement", "AIScoreBoost"]
    IniDelete settingsPath, "General", key
fallback := EacConfig(Root, settingsPath)
Assert(fallback.IT && fallback.AISupplement && fallback.ITScoreBoost = 1200, "existing INI gets defaults without rewrite")
IniWrite 99999, settingsPath, "General", "ITScoreBoost"
IniWrite -99999, settingsPath, "General", "AIScoreBoost"
bounded := EacConfig(Root, settingsPath)
Assert(bounded.ITScoreBoost = 5000 && bounded.AIScoreBoost = -5000, "priority offsets clamped")
Personal := EacUserDictionary(Fixture "\user.db")
Engine := EacSuggestionEngine(DictionaryPath, Config, Personal)
for pair in [["kuber", "kubernetes"], ["terrafor", "terraform"], ["kubec", "kubectl"], ["pn", "pnpm"], ["ripgr", "ripgrep"],
    ["oll", "ollama"], ["chatg", "chatgpt"], ["langch", "langchain"]]
    Assert(Find(Engine.Search(pair[1]), pair[2]), "default IT/AI completion " pair[2])
Assert(Find(Engine.Search("kuber"), "kubernetes").Translation == "コンテナ化したアプリの配置や運用をまとめて制御する基盤", "curated Japanese IT description reaches candidate")
baseDocker := Engine.Db.Query("SELECT translation FROM words WHERE norm='docker'")[1][1]
Assert(Find(Engine.Search("docke"), "docker").Translation == "アプリと実行に必要なものをコンテナにまとめて動かす基盤", "IT description overrides ordinary English homonym")
fallbackFound := false
for row in Engine.Db.Query("SELECT w.norm FROM words w JOIN it_entries it ON it.word_id=w.id "
    "WHERE it.source=4 AND w.source=4 AND it.translation='' AND length(w.norm) BETWEEN 5 AND 20 ORDER BY w.norm LIMIT 100") {
    candidate := Find(Engine.Search(SubStr(row[1], 1, -1)), row[1])
    if candidate {
        Assert(candidate.Translation == "[IT]", "unannotated IT word keeps fallback label")
        fallbackFound := true
        break
    }
}
Assert(fallbackFound, "fallback test covers a genuinely unannotated word")
Assert(Find(Engine.Search("oll"), "ollama").Translation == "AIモデルの実行環境", "existing AI supplement description remains visible")
item := Find(Engine.Search("curso"), "cursor")
Assert(item && item.Word == "Cursor", "AI spelling overrides shared ordinary word while enabled")
Config.IT := false
Assert(!Find(Engine.Search("kuber"), "kubernetes"), "IT off removes IT-only word")
Assert(!Find(Engine.Search("oll"), "ollama"), "IT off also disables supplement")
Assert(Find(Engine.Search("docke"), "docker").Translation == baseDocker, "IT off restores original English meaning")
item := Find(Engine.Search("curso"), "cursor")
Assert(item && item.Word == "cursor", "IT off restores base spelling")
Config.IT := true, Config.AISupplement := false
Assert(!Find(Engine.Search("oll"), "ollama"), "AI supplement can be independently disabled")
Assert(Find(Engine.Search("chatg"), "chatgpt"), "AI off retains word independently present in CSpell")
Config.AISupplement := true
normal := Find(Engine.Search("kuber"), "kubernetes").Score
Config.ITScoreBoost += 100
Assert(Find(Engine.Search("kuber"), "kubernetes").Score = normal + 100, "IT boost adjusts score")
normal := Find(Engine.Search("oll"), "ollama").Score
Config.AIScoreBoost += 100
Assert(Find(Engine.Search("oll"), "ollama").Score = normal + 100, "AI boost adjusts score independently")
Config.ITScoreBoost := -5000, Config.AIScoreBoost := 0
Assert(Position(Engine.Search("ope"), "openai") != 1, "negative boost moves supplemental word below common English or out of shortlist")
Config.ITScoreBoost := 5000
Assert(Position(Engine.Search("ope"), "openai") = 1, "positive boost puts supplemental word before common English")
Personal.Observe("OpenAIRouter", true)
Assert(Position(Engine.Search("ope"), "openairouter") = 1, "manual registration remains ahead of default static scores")
Personal.Block("Kubernetes")
Assert(!Find(Engine.Search("kuber"), "kubernetes"), "personal block wins over IT source")
Personal.Delete("Kubernetes")
Config.IT := false
Personal.Observe("Kubernetes", true)
Assert(Find(Engine.Search("kuber"), "kubernetes"), "explicit personal registration works even with IT off")
Config.SCOWL := false, Config.EJDict := false
Assert(!Engine.Search("chatg").Length, "all static dictionaries disabled yields no static word")
Config.IT := true, Config.AISupplement := false
Assert(Find(Engine.Search("terrafor"), "terraform"), "CSpell works without general English sources")
for item in Engine.Search("chat")
    Assert(SubStr(item.Norm, 1, 4) == "chat", "prefix boundary preserved")
Engine.Db.Close(), Engine := false
Personal.Db.Close(), Personal := false
; The shipped DB is exercised by normal verify.ps1; preview runs avoid old schema.
if !A_Args.Length {
    Store := EacDictionaryStore({Root: Root, DataDirectory: Fixture, PromotionCount: 2})
    Assert(Store.List(3, "kubernetes").Total = 1, "management screen can filter IT-only distribution entries")
    Assert(Store.List(3, "ollama").Rows[1][1] == "Ollama", "management screen preserves supplemental spelling")
    Assert(Store.List(3, "コンテナ化したアプリ").Total = 1, "management search includes Japanese IT description")
    Assert(Store.List(3, "docker").Rows[1][3] == "アプリと実行に必要なものをコンテナにまとめて動かす基盤", "management description agrees with candidate meaning")
    Assert(InStr(EacDictionaryManager.SourceNames(12), "CSpell") && InStr(EacDictionaryManager.SourceNames(12), "AI補助"), "management provenance labels include new sources")
    Store.Close(), Store := false
}
FileAppend "PASS it_dictionary_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
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
Position(items, norm) {
    for index, item in items
        if item.Norm == norm
            return index
    return 0
}
Fail(err, *) {
    FileAppend "FAIL " err.Message " at " err.Line "`n" err.Stack, "**"
    Cleanup()
    ExitApp 1
}
Cleanup(*) {
    global Personal, Engine, Store, Fixture
    if Store
        Store.Close(), Store := false
    if Engine
        Engine.Db.Close(), Engine := false
    if Personal
        Personal.Db.Close(), Personal := false
    loop files Fixture "\*", "F"
        FileDelete A_LoopFileFullPath
    if DirExist(Fixture)
        DirDelete Fixture
}
