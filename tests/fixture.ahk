#Requires AutoHotkey v2.0+
#SingleInstance Off
; Dedicated external-process native controls, contains no user documents.
if A_LineFile = A_ScriptFullPath {
window := Gui(, "EnglishAutocomplete disposable test fixture")
window.AddEdit("w700 r8")
window.AddEdit("w700 Password")
window.AddEdit("w700")
window.AddEdit("w700 ReadOnly", "Readonly")
window.OnEvent("Close", (*) => ExitApp())
window.Show()
english := DllCall("LoadKeyboardLayoutW", "Str", "00000409", "UInt", 0, "Ptr")
DllCall "ActivateKeyboardLayout", "Ptr", english, "UInt", 0
Persistent
}
