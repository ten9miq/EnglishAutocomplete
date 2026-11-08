#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include FixtureKeyboardLayout.ahk
; Dedicated external-process native controls, contains no user documents.
if A_LineFile = A_ScriptFullPath {
TestLayout := EacFixtureKeyboardLayout()
window := Gui(, "EnglishAutocomplete disposable test fixture")
window.AddEdit("w700 r8")
window.AddEdit("w700 Password")
window.AddEdit("w700")
window.AddEdit("w700 ReadOnly", "Readonly")
window.OnEvent("Close", (*) => ExitApp())
window.Show()
TestLayout.UseEnglish()
Persistent
}
