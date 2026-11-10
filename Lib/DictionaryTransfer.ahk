#Requires AutoHotkey v2.0+

; A versioned-by-header, UTF-8 CSV for the entire personal dictionary.
; No extra runtime, shell, extension DLL, or live database copy is required.
class EacDictionaryTransfer {
    static Header := "word,uses,last_used,manual,blocked"
    static MaxRows := 10000
    static MaxBytes := 8 * 1024 * 1024

    static CsvPath(path) {
        SplitPath path, , , &extension
        if StrLower(extension) != "csv"
            throw Error("CSVファイル（.csv）を指定してください。")
    }

    static Export(personal, path, overwrite := false) {
        this.CsvPath(path)
        if !personal.Enabled
            throw Error(personal.Fault)
        ; One SELECT supplies a consistent snapshot, including blocked entries.
        rows := personal.Db.Query("SELECT word,uses,last_used,manual,blocked FROM personal ORDER BY norm")
        this.Validate(rows)
        temporary := path "." DllCall("GetCurrentProcessId") "-" A_TickCount ".tmp"
        if FileExist(temporary)
            throw Error("一時ファイルが既に存在します。保存をやり直してください。")
        try {
            file := FileOpen(temporary, "w", "UTF-8")
            if !file
                throw Error("エクスポート先に書き込めません。")
            try {
                file.Write(this.Header "`r`n")
                for row in rows
                    file.Write(row[1] "," row[2] "," row[3] "," row[4] "," row[5] "`r`n")
            } finally file.Close()
            ; Move only a fully written file, on the destination's volume.
            FileMove temporary, path, overwrite
        } finally {
            if FileExist(temporary)
                FileDelete temporary
        }
        return rows.Length
    }

    static Read(path) {
        this.CsvPath(path)
        if FileGetSize(path) > this.MaxBytes
            throw Error("CSVは8MiB以下にしてください。")
        bytes := FileRead(path, "RAW")
        if bytes.Size > this.MaxBytes
            throw Error("CSVは8MiB以下にしてください。")
        if bytes.Size && !DllCall("MultiByteToWideChar", "UInt", 65001, "UInt", 8,
            "Ptr", bytes, "Int", bytes.Size, "Ptr", 0, "Int", 0)
            throw Error("CSVをUTF-8で保存してください。")
        loop bytes.Size
            if NumGet(bytes, A_Index - 1, "UChar") = 0
                throw Error("CSVにNUL文字が含まれています。UTF-8で保存してください。")
        content := bytes.Size ? StrGet(bytes, bytes.Size, "UTF-8") : ""
        if SubStr(content, 1, 1) = Chr(0xFEFF)
            content := SubStr(content, 2)
        lines := StrSplit(StrReplace(content, "`r`n", "`n"), "`n")
        if lines[1] != this.Header
            throw Error("CSVの先頭行は " this.Header " にしてください。")
        rows := []
        for number, line in lines {
            if number = 1 || line = ""
                continue
            try rows.Push(this.ParseLine(line))
            catch as err
                throw Error("CSV " number "行目: " err.Message)
        }
        this.Validate(rows)
        return rows
    }

    static ParseLine(line) {
        fields := [], position := 1, length := StrLen(line)
        loop {
            value := ""
            if SubStr(line, position, 1) = '"' {
                position += 1, closed := false
                while position <= length {
                    char := SubStr(line, position, 1)
                    position += 1
                    if char = '"' {
                        if SubStr(line, position, 1) = '"'
                            value .= '"', position += 1
                        else {
                            closed := true
                            break
                        }
                    } else
                        value .= char
                }
                if !closed || (position <= length && SubStr(line, position, 1) != ",")
                    throw Error("引用符の形式が不正です。")
            } else {
                while position <= length && SubStr(line, position, 1) != "," {
                    char := SubStr(line, position, 1)
                    if char = '"'
                        throw Error("引用符の形式が不正です。")
                    value .= char, position += 1
                }
            }
            fields.Push(value)
            if position > length
                break
            position += 1
        }
        return fields
    }

    static Validate(rows) {
        if rows.Length > this.MaxRows
            throw Error("個人辞書のCSVは10000語以下にしてください。")
        seen := Map()
        for index, row in rows {
            if row.Length != 5 || !EacUserDictionary.Valid(row[1], true)
                throw Error("CSVのデータ " index "件目: 単語または列数が不正です。")
            for column, maximum in Map(2, 2147483647, 3, 253402214400, 4, 1, 5, 1) {
                if !RegExMatch(row[column], "^(?:0|[1-9][0-9]*)$") || StrLen(row[column]) > 12 || row[column] > maximum
                    throw Error("CSVのデータ " index "件目: 回数・日時・状態は規定範囲の整数にしてください。")
            }
            norm := StrLower(row[1])
            if seen.Has(norm)
                throw Error("CSV内で同じ単語が重複しています: " row[1])
            seen[norm] := true
        }
    }

    static ImportRows(personal, rows, overwrite := false) {
        this.Validate(rows)
        if !personal.Enabled
            throw Error(personal.Fault)
        db := personal.Db
        db.Query("BEGIN IMMEDIATE")
        try {
            existing := Map()
            for entry in db.Query("SELECT norm FROM personal")
                existing[entry[1]] := true
            added := 0, updated := 0, skipped := 0
            for row in rows
                if !existing.Has(StrLower(row[1]))
                    added += 1
            if existing.Count + added > this.MaxRows
                throw Error("取込後の個人辞書が10000語を超えるため、取り込みませんでした。")
            for row in rows {
                norm := StrLower(row[1])
                if existing.Has(norm) {
                    if !overwrite {
                        skipped += 1
                        continue
                    }
                    updated += 1
                }
                db.Query("INSERT INTO personal(norm,word,uses,last_used,manual,blocked) VALUES(?,?,?,?,?,?) "
                    "ON CONFLICT(norm) DO UPDATE SET word=excluded.word,uses=excluded.uses,last_used=excluded.last_used,manual=excluded.manual,blocked=excluded.blocked",
                    [norm, row[1], row[2], row[3], row[4], row[5]])
            }
            db.Query("COMMIT")
            return {Added: added, Updated: updated, Skipped: skipped}
        } catch as err {
            try db.Query("ROLLBACK")
            throw err
        }
    }
}
