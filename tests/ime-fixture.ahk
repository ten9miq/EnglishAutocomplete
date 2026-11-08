#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include FixtureKeyboardLayout.ahk
; Dedicated external-process controls. Temporary ENG is unloaded on exit.
if A_LineFile = A_ScriptFullPath {
    OnError((e, *) => (FileAppend(e.Message "`n" e.Stack, "**"), ExitApp(1)))
    TestLayout := EacFixtureKeyboardLayout()
    DllCall "LoadLibraryW", "Str", "msftedit.dll", "Ptr"
    Fixture := Gui(, "EnglishAutocomplete disposable IME fixture")
    Fixture.AddCustom("ClassRICHEDIT50W w650 h100")
    Fixture.AddEdit("w650")
    Fixture.OnEvent("Close", (*) => ExitApp())
    Fixture.Show()
    TestLayout.UseEnglish()
    Persistent
}
