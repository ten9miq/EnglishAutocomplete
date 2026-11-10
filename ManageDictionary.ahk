#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include Lib\All.ahk
#Include Lib\DictionaryManager.ahk
if A_LineFile = A_ScriptFullPath {
try {
    if EacManageIsHelp(A_Args)
        EacManagerHelp := EacDictionaryHelp(A_ScriptDir), EacManagerHelp.Show()
    else if A_Args.Length = 1 && A_Args[1] = "--gui"
        EacManager := EacDictionaryManager(EacConfig(A_ScriptDir)), EacManager.Show()
    else {
        EacValidateManagementArgs(A_Args)
        EacManage(A_Args, EacConfig(A_ScriptDir))
        ExitApp 0
    }
} catch as err {
    try FileAppend err.Message "`n", "**"
    catch
        MsgBox err.Message, "辞書管理 - エラー", "Iconx"
    ExitApp 1
}
}

EacManageIsHelp(args) => !args.Length || (args.Length = 1 && (args[1] = "--help" || args[1] = "-h"))

EacManageUsage() => "ManageDictionary.ahk の使い方`r`n`r`n"
    . "引数なし / --help : この使い方を表示`r`n"
    . "--gui : 辞書管理画面を開く`r`n"
    . "--add 単語 : 手動登録（大文字・小文字の表記も更新）`r`n"
    . "--block 単語 : 候補への表示を禁止`r`n"
    . "--unblock 単語 : 禁止を解除`r`n"
    . "--delete 単語 : 個人辞書の登録・履歴・禁止を削除`r`n"
    . "--reset-frequency : 全単語の使用回数・最終使用日時を初期化`r`n"
    . "--reset-user : 個人辞書を全消去（取り消せません）`r`n`r`n"
    . "例: AutoHotkey64.exe ManageDictionary.ahk --add MyInternalTool`r`n`r`n"
    . "管理画面では個人辞書を編集し、配布辞書を検索できます。`r`n"
    . "配布辞書そのものは変更しません。通常の手動登録は本体のトレイからも行えます。"

EacValidateManagementArgs(args) {
    if EacManageIsHelp(args)
        return
    switch args[1] {
        case "--add", "--block", "--unblock", "--delete":
            if args.Length != 2 || !EacUserDictionary.Valid(args[2], true)
                throw Error("有効な単語を1つ指定してください（英字で開始、2～64文字）。")
        case "--reset-frequency", "--reset-user":
            if args.Length != 1
                throw Error("このコマンドに追加の引数は指定できません。")
        default: throw Error("不明な管理コマンドです。--help で使い方を確認してください。")
    }
}

EacManage(args, config) {
    ; Validate before opening a database, including calls from regression tests.
    if EacManageIsHelp(args)
        return EacManageUsage()
    EacValidateManagementArgs(args)
    personal := EacUserDictionary(config.DataDirectory "\user.db", config.PromotionCount)
    if !personal.Enabled
        throw Error(personal.Fault)
    try EacApplyManagement(personal, args)
    finally personal.Db.Close()
}

EacApplyManagement(personal, args) {
    if EacManageIsHelp(args)
        return EacManageUsage()
    EacValidateManagementArgs(args)
    if !personal.Enabled
        throw Error(personal.Fault)
    switch args[1] {
        case "--add":
            if !personal.Observe(args[2], true)
                throw Error("登録できませんでした。禁止状態・登録上限・データベースを確認してください。")
        case "--block": personal.Block(args[2])
        case "--unblock": personal.Db.Query("UPDATE personal SET blocked=0 WHERE norm=?", [StrLower(args[2])])
        case "--delete": personal.Delete(args[2])
        case "--reset-frequency": personal.ResetFrequency()
        case "--reset-user": personal.Clear()
    }
}
