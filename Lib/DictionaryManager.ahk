#Requires AutoHotkey v2.0+
#Include DictionaryTransfer.ahk

; Used only by ManageDictionary.ahk; no dependency from the resident app.
class EacDictionaryHelp {
    __New(root) {
        this.Root := root
        this.Window := Gui(, "辞書管理 - 使い方")
        this.Window.SetFont("s10", "Yu Gothic UI")
        this.Window.AddEdit("w660 r19 ReadOnly -Wrap", EacManageUsage())
        this.OpenButton := this.Window.AddButton("xm w230 h32 Default", "辞書管理画面を開く")
        this.OpenButton.OnEvent("Click", ObjBindMethod(this, "Open"))
        this.Window.AddButton("x+12 w100 h32", "閉じる").OnEvent("Click", (*) => this.Window.Destroy())
        this.Window.OnEvent("Close", (*) => this.Window.Destroy())
        this.Window.OnEvent("Escape", (*) => this.Window.Destroy())
    }

    Show() {
        this.Window.Show()
        this.OpenButton.Focus()
    }

    Open(*) {
        try {
            this.Manager := EacDictionaryManager(EacConfig(this.Root))
            this.Manager.Show()
            this.Window.Destroy()
        } catch as err {
            MsgBox err.Message, "辞書管理 - エラー", "Iconx"
        }
    }
}

class EacDictionaryStore {
    static PageSize := 100
    Personal := false
    Distribution := false

    __New(config) {
        this.Personal := EacUserDictionary(config.DataDirectory "\user.db", config.PromotionCount)
        if !this.Personal.Enabled
            throw Error(this.Personal.Fault)
        try {
            this.Distribution := EacSQLite(config.Root "\data\dictionary.db", true)
            if this.Distribution.Query("PRAGMA user_version")[1][1] != "2"
                throw Error("配布辞書の形式に対応していません。")
        } catch as err {
            this.Close()
            throw err
        }
    }

    List(source := 1, search := "", kind := 1, page := 1) {
        search := StrLower(Trim(search))
        if source = 1 {
            db := this.Personal.Db, table := "personal"
            condition := "instr(norm,?)>0"
            parameters := [search]
            switch kind {
                case 2: condition .= " AND manual=1 AND blocked=0"
                case 3: condition .= " AND manual=0 AND blocked=0"
                case 4: condition .= " AND blocked=1"
            }
            columns := "word,manual,uses,last_used,blocked"
        } else {
            db := this.Distribution, table := "words"
            condition := "(instr(norm,?)>0 OR instr(translation,?)>0)"
            parameters := [search, search]
            if source = 3
                condition .= " AND (source & 12)!=0"
            columns := "COALESCE((SELECT word FROM it_entries WHERE word_id=words.id AND source=8),"
                . "(SELECT word FROM it_entries WHERE word_id=words.id AND source=4),word),source,"
                . "COALESCE(NULLIF(translation,''),(SELECT translation FROM it_entries WHERE word_id=words.id AND source=8),"
                . "(SELECT translation FROM it_entries WHERE word_id=words.id AND source=4),'')"
        }
        total := Integer(db.Query("SELECT count(*) FROM " table " WHERE " condition, parameters)[1][1])
        pages := Max(1, Ceil(total / EacDictionaryStore.PageSize))
        page := Max(1, Min(page, pages))
        values := parameters.Clone()
        values.Push(EacDictionaryStore.PageSize, (page - 1) * EacDictionaryStore.PageSize)
        rows := db.Query("SELECT " columns " FROM " table " WHERE " condition " ORDER BY norm LIMIT ? OFFSET ?", values)
        return {Rows: rows, Total: total, Page: page, Pages: pages}
    }

    Apply(args) => EacApplyManagement(this.Personal, args)
    Export(path, overwrite := false) => EacDictionaryTransfer.Export(this.Personal, path, overwrite)
    ImportRows(rows, overwrite := false) => EacDictionaryTransfer.ImportRows(this.Personal, rows, overwrite)

    Close() {
        if this.Personal && this.Personal.Db
            this.Personal.Db.Close()
        if this.Distribution
            this.Distribution.Close()
    }

    __Delete() => this.Close()
}

class EacDictionaryManager {
    __New(config) {
        this.Store := EacDictionaryStore(config)
        this.DataDirectory := config.DataDirectory
        this.Page := 1
        this.Window := Gui(, "EnglishAutocomplete - 辞書管理")
        this.Window.SetFont("s10", "Yu Gothic UI")
        this.Window.AddText("xm w880", "個人辞書の編集と配布辞書の検索。行を選ぶと下の「操作する単語」に入ります。")
        this.Source := this.Window.AddDropDownList("xm y+12 w190 Choose1", ["個人辞書", "配布辞書（閲覧専用）", "IT追加辞書（閲覧専用）"])
        this.Kind := this.Window.AddDropDownList("x+10 w150 Choose1", ["すべて", "手動登録", "自動学習", "禁止"])
        this.Search := this.Window.AddEdit("x+10 w320")
        this.Window.AddButton("x+10 w80 Default", "検索").OnEvent("Click", ObjBindMethod(this, "SearchNow"))
        this.Window.AddButton("x+10 w90", "再読込").OnEvent("Click", ObjBindMethod(this, "SafeRefresh"))
        this.List := this.Window.AddListView("xm y+12 w880 r13 -Multi", ["単語", "状態 / 出典", "使用回数", "最終使用（ローカル）", "訳"])
        for index, width in [210, 120, 80, 165, 270]
            this.List.ModifyCol(index, width)
        this.List.ModifyCol(3, "Integer")
        this.List.OnEvent("ItemSelect", ObjBindMethod(this, "SelectWord"))
        this.Previous := this.Window.AddButton("xm y+10 w90", "前のページ")
        this.Previous.OnEvent("Click", (*) => this.ChangePage(-1))
        this.Next := this.Window.AddButton("x+10 w90", "次のページ")
        this.Next.OnEvent("Click", (*) => this.ChangePage(1))
        this.PageLabel := this.Window.AddText("x+15 yp+5 w650", "")
        this.Window.AddText("xm y+14 w110", "操作する単語")
        this.Word := this.Window.AddEdit("x+10 yp-3 w390")
        this.Window.AddText("x+12 yp+3 w350", "英字で開始、2～64文字")
        for item in [["登録 / 表記更新", "--add"], ["禁止", "--block"], ["禁止解除", "--unblock"], ["個人データ削除", "--delete"]] {
            options := A_Index = 1 ? "xm y+10 w155 h30" : "x+10 w155 h30"
            this.Window.AddButton(options, item[1]).OnEvent("Click", ObjBindMethod(this, "Execute", item[2]))
        }
        this.Window.AddText("xm y+10 w880", "削除は個人データだけが対象です。配布辞書の語を候補から隠すには「禁止」を使います。")
        this.Window.AddButton("xm y+10 w180 h30", "全単語の頻度を初期化").OnEvent("Click", ObjBindMethod(this, "Execute", "--reset-frequency"))
        this.Window.AddButton("x+10 w180 h30", "個人辞書を全消去").OnEvent("Click", ObjBindMethod(this, "Execute", "--reset-user"))
        this.Window.AddButton("x+25 w170 h30", "エクスポート（CSV）").OnEvent("Click", ObjBindMethod(this, "Export"))
        this.Window.AddButton("x+10 w170 h30", "インポート（CSV）").OnEvent("Click", ObjBindMethod(this, "Import"))
        this.Overwrite := this.Window.AddCheckbox("xm y+10 w880", "同じ単語があれば取込値で上書き（未選択時は既存データを保持）")
        this.Window.AddText("xm y+5 w880", "入出力の対象は個人辞書全件です。検索条件・ページ・配布辞書の表示には関係しません。")
        this.Status := this.Window.AddText("xm y+12 w880 r2", "")
        this.Window.AddText("xm y+2 w880", "データ: " config.DataDirectory "\user.db")
        this.Source.OnEvent("Change", ObjBindMethod(this, "SearchNow"))
        this.Kind.OnEvent("Change", ObjBindMethod(this, "SearchNow"))
        this.Window.OnEvent("Close", ObjBindMethod(this, "Close"))
        this.Window.OnEvent("Escape", ObjBindMethod(this, "Close"))
        try this.Refresh()
        catch as err {
            this.Close()
            throw err
        }
    }

    Show() => this.Window.Show()

    SearchNow(*) {
        this.Page := 1
        this.Word.Value := ""
        this.Kind.Enabled := this.Source.Value = 1
        this.SafeRefresh()
    }

    ChangePage(delta) {
        this.Page += delta
        this.Word.Value := ""
        this.SafeRefresh()
    }

    Refresh(*) {
        ; Clear stale targets even when a read fails (for example, a locked DB).
        this.List.Delete()
        result := this.Store.List(this.Source.Value, this.Search.Value, this.Kind.Value, this.Page)
        this.Page := result.Page
        for row in result.Rows {
            if this.Source.Value = 1 {
                state := Integer(row[5]) ? "禁止" : (Integer(row[2]) ? "手動登録" : "自動学習")
                lastUsed := Integer(row[4]) > 0 ? this.LocalTime(Integer(row[4])) : "—"
                this.List.Add(, row[1], state, row[3], lastUsed, "")
            } else {
                source := EacDictionaryManager.SourceNames(Integer(row[2]))
                this.List.Add(, row[1], Trim(source), "", "", StrReplace(StrReplace(row[3], "`r", " "), "`n", " "))
            }
        }
        this.PageLabel.Text := result.Total " 件 / " result.Page " / " result.Pages " ページ（100件ずつ表示）"
        this.Previous.Enabled := result.Page > 1
        this.Next.Enabled := result.Page < result.Pages
        this.Status.Text := "表示を更新しました。常駐本体の変更も「再読込」で反映できます。"
    }

    SafeRefresh(*) {
        try this.Refresh()
        catch as err {
            this.Word.Value := ""
            this.Status.Text := "読込に失敗しました: " err.Message
            MsgBox this.Status.Text, "辞書管理 - エラー", "Iconx Owner" this.Window.Hwnd
        }
    }

    SelectWord(control, row, selected) {
        if selected
            this.Word.Value := control.GetText(row, 1)
    }

    Execute(command, *) {
        word := Trim(this.Word.Value)
        args := [command]
        if command != "--reset-frequency" && command != "--reset-user"
            args.Push(word)
        try {
            EacValidateManagementArgs(args)
            switch command {
                case "--block":
                    prompt := "「" word "」を禁止しますか？`nこの語の使用回数と手動登録状態も消えます。"
                case "--delete":
                    prompt := "「" word "」の個人データ（登録・履歴・禁止）を削除しますか？`n配布辞書の語は残り、削除した語は再学習できます。"
                case "--reset-frequency":
                    prompt := "個人辞書の全単語の使用回数・最終使用日時を初期化しますか？`n手動登録と禁止は保持します。"
                case "--reset-user":
                    prompt := "個人辞書の全単語・手動登録・履歴・禁止を全消去しますか？`n取り消せません。配布辞書は変更しません。"
                default: prompt := ""
            }
            if prompt != "" && !this.Confirm(prompt)
                return
            this.Store.Apply(args)
            this.Refresh()
            labels := Map("--add", "登録 / 表記更新", "--block", "禁止", "--unblock", "禁止解除",
                "--delete", "個人データ削除", "--reset-frequency", "全単語の頻度初期化", "--reset-user", "個人辞書の全消去")
            this.Status.Text := labels[command] "が完了しました。" (args.Length = 2 ? " / " word : "")
        } catch as err {
            this.Status.Text := "操作に失敗しました: " err.Message
            MsgBox this.Status.Text, "辞書管理 - エラー", "Iconx Owner" this.Window.Hwnd
        }
    }

    Confirm(prompt) => MsgBox(prompt, "辞書管理 - 確認", "YesNo Default2 Icon! Owner" this.Window.Hwnd) = "Yes"

    static SourceNames(mask) => Trim((mask & 1 ? "SCOWL " : "") (mask & 2 ? "EJDict " : "")
        (mask & 4 ? "CSpell " : "") (mask & 8 ? "AI補助 " : ""))

    SelectTransferPath(save) {
        this.Window.Opt("+OwnDialogs")
        return FileSelect(save ? "S16" : 1, save ? this.DataDirectory "\personal-dictionary-" A_Now ".csv" : this.DataDirectory,
            save ? "個人辞書をエクスポート" : "個人辞書をインポート", "CSV (*.csv)")
    }

    Export(*) {
        try {
            path := this.SelectTransferPath(true)
            if path = ""
                return
            SplitPath path, , , &extension
            if extension = "" {
                path .= ".csv"
                if FileExist(path) && !this.Confirm("既存のCSVを上書きしますか？`n" path)
                    return
            }
            count := this.Store.Export(path, true)
            this.Status.Text := count "語をエクスポートしました: " path
        } catch as err {
            this.Status.Text := "エクスポートに失敗しました: " err.Message
            MsgBox this.Status.Text, "辞書管理 - エラー", "Iconx Owner" this.Window.Hwnd
        }
    }

    Import(*) {
        try {
            path := this.SelectTransferPath(false)
            if path = ""
                return
            rows := EacDictionaryTransfer.Read(path)
            overwrite := !!this.Overwrite.Value
            prompt := rows.Length "語を個人辞書に取り込みますか？`n"
                . (overwrite ? "同じ単語は表記・頻度・手動登録・禁止を含め取込値で上書きします。" : "同じ単語は現在のデータを保持し、新しい単語だけ追加します。")
                . "`nCSVにない既存の単語は削除しません。"
            if !this.Confirm(prompt)
                return
            result := this.Store.ImportRows(rows, overwrite)
            this.Page := 1
            this.Word.Value := ""
            this.Refresh()
            this.Status.Text := "インポート完了: 追加 " result.Added "語 / 上書き " result.Updated "語 / 既存保持 " result.Skipped "語"
        } catch as err {
            this.Status.Text := "インポートに失敗しました: " err.Message
            MsgBox this.Status.Text, "辞書管理 - エラー", "Iconx Owner" this.Window.Hwnd
        }
    }

    static LocalTime(seconds) {
        stamp := DateAdd("19700101000000", seconds, "Seconds")
        utc := Buffer(16, 0), localTime := Buffer(16, 0)
        for offset, value in Map(0, SubStr(stamp, 1, 4), 2, SubStr(stamp, 5, 2), 6, SubStr(stamp, 7, 2),
            8, SubStr(stamp, 9, 2), 10, SubStr(stamp, 11, 2), 12, SubStr(stamp, 13, 2))
            NumPut "UShort", Integer(value), utc, offset
        if !DllCall("SystemTimeToTzSpecificLocalTime", "Ptr", 0, "Ptr", utc, "Ptr", localTime)
            return FormatTime(stamp, "yyyy-MM-dd HH:mm") " UTC"
        return Format("{:04}-{:02}-{:02} {:02}:{:02}", NumGet(localTime, 0, "UShort"), NumGet(localTime, 2, "UShort"),
            NumGet(localTime, 6, "UShort"), NumGet(localTime, 8, "UShort"), NumGet(localTime, 10, "UShort"))
    }

    LocalTime(seconds) => EacDictionaryManager.LocalTime(seconds)

    Close(*) {
        this.Window.Destroy()
        this.Store.Close()
    }
}
