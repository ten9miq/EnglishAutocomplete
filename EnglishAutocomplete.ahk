#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include Lib\All.ahk

; Local Unicode input; no clipboard, server, elevation or startup registration.
if A_LineFile = A_ScriptFullPath {
SendMode "Input"
try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
EacStarted := A_TickCount
try {
    EacSettings := EacConfig(A_ScriptDir)
    EacApp := EacApplication(EacSettings)
    OnMessage(DllCall("RegisterWindowMessageW", "Str", "EnglishAutocomplete.Diagnostics.v1", "UInt"),
        ObjBindMethod(EacApp, "DiagnosticPacket"))
    EacInitMs := A_TickCount - EacStarted
    A_TrayMenu.Delete()
    A_TrayMenu.Add("有効 / 無効", (*) => EacToggle())
    A_TrayMenu.Add("単語を手動登録", (*) => EacRegister())
    A_TrayMenu.Add("設定を開く", (*) => Run('notepad.exe "' EacSettings.Path '"'))
    A_TrayMenu.Add("設定を再読込", (*) => Reload())
    A_TrayMenu.Add("診断状態", (*) => MsgBox("状態: " (EacSettings.Enabled ? "有効" : "無効")
        "`n学習DB: " (EacApp.User.Enabled ? "利用可能" : EacApp.User.Fault)
        "`n入力欄の判定: " (EacApp.HasOwnProp("SafetyReason") ? EacApp.SafetyReason : "待機")
        "`n" EacApp.Fault "`n起動初期化: " EacInitMs " ms"))
    A_TrayMenu.Add("終了", (*) => ExitApp())
    A_IconTip := "EnglishAutocomplete: Ctrl+Alt+Space で確定"
    Persistent
} catch as err {
    FileAppend "EnglishAutocomplete startup failed: " err.Message "`n", "**"
    ExitApp 1
}
}

EacToggle() {
    global EacSettings, EacApp
    EacSettings.Enabled := !EacSettings.Enabled
    EacApp.Reset()
    A_IconTip := "EnglishAutocomplete: " (EacSettings.Enabled ? "有効" : "無効")
}

EacRegister() {
    global EacApp
    result := InputBox("登録する単語 (文章・認証情報は登録しないでください)", "EnglishAutocomplete")
    if result.Result = "OK"
        MsgBox EacApp.User.Observe(Trim(result.Value), true) ? "登録しました" : "登録できませんでした"
}
