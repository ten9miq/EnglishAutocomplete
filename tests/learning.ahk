#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Real application callbacks and private SQLite, modelled field only: no UI,
; focus changes, keys, clipboard or reads/writes of the real personal DB.
Checks := 0, App := false
Root := A_ScriptDir "\.."
Fixture := A_ScriptDir "\results\learning-" DllCall("GetCurrentProcessId")
DirCreate Fixture
settingsPath := Fixture "\settings.ini"
FileCopy Root "\settings.default.ini", settingsPath
IniWrite Fixture, settingsPath, "General", "DataDirectory"
OnError Fail
OnExit Cleanup
App := LearningApp(EacConfig(Root, settingsPath))

Begin()
App.Type("MSAN MSAN MSAN "), App.Refresh()
Assert(Uses("msan") = 3, "rapid repeated words count their own positions exactly once")
App.Refresh()
Assert(Uses("msan") = 3, "refresh does not count observations twice")
found := false
for item in App.Engine.Search("MSA")
    if item.Norm = "msan"
        found := true
Assert(found, "repeated real DB observations promote personal candidate")

Begin()
App.Type(Repeat("abCd ", 24)), App.Refresh()
Assert(Uses("abcd") = 24 && Uses("ab") = 24 && Uses("cd") = 24,
    "dense case boundaries within 128 characters do not overflow pending queue")

Begin()
App.Type("MSAN next")
App.Refresh()
Assert(Uses("msan") = 1 && !Uses("next"), "word before space learns after next word already started")
App.Type(" "), App.Refresh()
Assert(Uses("msan") = 1 && Uses("next") = 1, "next boundary learns next word without duplication")

Begin()
App.Type("alpha.beta,gamma-delta "), App.Refresh()
for word in ["alpha","beta","gamma","delta"]
    Assert(Uses(word) = 1, "punctuation learning boundary " word)
Assert(!Uses("alpha.beta") && !Uses("gamma-delta"), "dotted and hyphenated whole identifiers are not auto registered")

Begin()
App.Type("getUserInfo HTTPServer MSAN OpenAI fooFoo."), App.Refresh()
for word in ["getuserinfo","get","user","info","httpserver","http","server","msan","openai","open","ai","foofoo","foo"]
    Assert(Uses(word) = 1, "camel/acronym pieces and original word " word)
Assert(!Uses("ms") && !Uses("an"), "consecutive capitals never split arbitrarily")

Begin()
App.Type(".alpha,-beta `r`ngamma`t"), App.Refresh()
for word in ["alpha","beta","gamma"]
    Assert(Uses(word) = 1, "leading punctuation and actual control-character boundary " word)

Begin()
App.Type("Newlineword`n"), App.Before := "Newlineword`r`n", App.Refresh()
Assert(Uses("newlineword") = 1, "InputHook LF matches native Edit CRLF")
Begin()
App.Type("Newlineword`r"), App.Type("`n"), App.Refresh()
Assert(Uses("newlineword") = 1, "split CRLF callbacks count exactly once")

Begin()
App.Type("name@example.com https://example.com C:\private\alpha-beta tokenSecret-innocent Beta123-Gamma AbcDefGhiJklMnoPqrStuVwx ")
App.Refresh()
Assert(App.User.Db.Query("SELECT count(*) FROM personal")[1][1] = "0", "URL email path digit credential and long mixed-case pieces remain excluded")
for unsafe in ["www.example.com ","api-key-SAMPLE "] {
    Begin()
    App.Type(unsafe), App.Refresh()
    Assert(App.User.Db.Query("SELECT count(*) FROM personal")[1][1] = "0", "obvious dotted URL or separated credential prefix excludes all pieces")
}

Begin()
App.Before := "unobservedprefix"
App.Type("MSAN "), App.Refresh()
Assert(!Uses("msan"), "observed suffix inside existing word is not invented as a whole word")
Begin()
App.Before := "MSAN ", App.Refresh()
Assert(!Uses("msan"), "unobserved text is never learned")
Begin()
App.Type("MSAN "), App.Before := "msan ", App.Refresh()
Assert(!Uses("msan"), "case-only correction is not silently accepted")

Begin()
App.Type("mispell next "), App.Before := "misspell next ", App.Refresh()
Assert(!Uses("mispell") && Uses("next") = 1, "earlier autocorrection cannot poison later independently anchored words")
App.Type(Repeat("x", 130) " "), App.Refresh()
Assert(App.Pending.Length = 0 && StrLen(App.LearningTracker.Tail) <= 128, "unverifiable observations expire with bounded input window")

Begin()
App.Type("alpha."), App.After := "suffix", App.Refresh()
Assert(!Uses("alpha"), "period in middle of existing token is not a proven complete learning span")
Begin()
App.Type("MSAN "), App.ContextKey := "other", App.Refresh()
Assert(!Uses("msan"), "focus change invalidates queued learning")
Begin()
App.Policy.Learning := false
App.Type("MSAN "), App.Refresh()
Assert(!Uses("msan") && !App.Pending.Length, "Learning off discards observations")

Begin()
App.Type("MSAN next "), saved := App.Before, App.Before := "MSAN "
App.Refresh()
Assert(!Uses("msan") && App.Pending.Length = 2, "provider lag retains pending spans without guessing")
App.Before := saved, App.Refresh()
Assert(Uses("msan") = 1 && Uses("next") = 1, "fresh provider text validates both retained spans")

Begin()
App.Type("conf")
App.Pending.Push(App.LearningTracker.Complete("idence", "confidence", App.ContextKey))
App.Before .= "idence", App.Tracker.Word := "confidence", App.Tracker.Learned := true
App.Type(" next "), App.Refresh()
Assert(Uses("confidence") = 1 && Uses("next") = 1, "completion counts once even when next word arrives before refresh")
App.Refresh()
Assert(Uses("confidence") = 1, "completion separator cannot recursively learn whole word or pieces")

Begin()
App.Type("firstword secondword ")
App.User.Callback := (*) => App.Type("thirdword ")
App.Refresh(), App.Refresh()
for word in ["firstword","secondword","thirdword"]
    Assert(Uses(word) = 1, "input reentry during DB write preserves pending observation " word)

Begin()
App.Type("firstword secondword ")
App.User.Callback := (*) => ResetDuringWrite()
App.Refresh(), App.Refresh()
Assert(Uses("firstword") = 1 && Uses("secondword") = 1, "reset during DB write cannot revive stale observations")
Begin()
old := App.LearningTracker.Feed("MSAN ", App.ContextKey)[1]
App.LearningTracker.Reset(), App.LearningTracker.Feed("MSAN ", App.ContextKey)
Assert(App.LearningTracker.Verify({Before:"MSAN ",After:""}, old) = "Discard", "epoch prevents stale offsets matching new identical input")

FileAppend "PASS learning_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
Cleanup()
ExitApp 0

Begin() {
    global App
    App.Reset(), App.Before := "", App.After := "", App.ContextKey := "fixture"
    App.Policy.Learning := true, App.User.Callback := false
    App.User.Db.Query("DELETE FROM personal")
}
Uses(word) {
    global App
    rows := App.User.Db.Query("SELECT uses FROM personal WHERE norm=?", [word])
    return rows.Length ? Integer(rows[1][1]) : 0
}
ResetDuringWrite() {
    global App
    App.Reset(), App.Before := ""
    App.Type("secondword ")
}
Repeat(value, count) {
    result := ""
    Loop count
        result .= value
    return result
}
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
    global App, Fixture
    if App {
        SetTimer App.RefreshCallback, 0
        App.Engine.Db.Close(), App.User.Db.Close(), App := false
    }
    loop files Fixture "\*", "F"
        FileDelete A_LoopFileFullPath
    if DirExist(Fixture)
        DirDelete Fixture
}
class LearningApp extends EacApplication {
    __New(config) {
        this.Config := config, this.Tracker := EacInputTracker()
        this.User := LearningUser(config.DataDirectory "\user.db")
        this.Engine := EacSuggestionEngine(config.Root "\data\dictionary.db", config, this.User)
        this.Gui := LearningGui(), this.RefreshCallback := (*) => 0
        this.ContextKey := "fixture", this.Before := "", this.After := ""
        this.Policy := {Enabled:false,Learning:true,Keys:false}
    }
    Type(text) {
        loop parse text {
            this.Before .= A_LoopField
            this.OnChar(0, A_LoopField)
        }
    }
    CurrentContext() => {Hwnd:0,Focus:0,Key:this.ContextKey}
    Modifiers() => 0
    Snapshot() => {Context:this.CurrentContext(),Policy:this.Policy,
        Field:{Before:SubStr(this.Before,-128),After:this.After}}
}
class LearningGui {
    Hide() {
    }
}
class LearningUser extends EacUserDictionary {
    Callback := false
    Observe(word, manual := false) {
        result := super.Observe(word, manual)
        callback := this.Callback, this.Callback := false
        if callback
            callback.Call()
        return result
    }
}
