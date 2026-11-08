#Requires AutoHotkey v2.0+

; Minimal parameterized SQLite C API binding. Load ONLY the OS-owned DLL.
class EacSQLite {
    static Module := DllCall("LoadLibraryW", "Str", A_WinDir "\System32\winsqlite3.dll", "Ptr")
    Handle := 0

    __New(path, readOnly := false) {
        if !EacSQLite.Module
            throw Error("Windows SQLite runtime unavailable")
        encodedPath := this.Utf8(path)
        code := DllCall(this.Fn("sqlite3_open_v2"), "Ptr", encodedPath, "Ptr*", &handle := 0,
            "Int", readOnly ? 1 : 6, "Ptr", 0, "CDecl Int")
        this.Handle := handle
        if code {
            this.Close()
            throw Error("Cannot open SQLite database", , code)
        }
        DllCall(this.Fn("sqlite3_busy_timeout"), "Ptr", handle, "Int", 30, "CDecl Int")
        this.Query("PRAGMA foreign_keys=ON")
        this.Query("PRAGMA cache_size=-2048")
    }

    Fn(name) {
        ptr := DllCall("GetProcAddress", "Ptr", EacSQLite.Module, "AStr", name, "Ptr")
        if !ptr
            throw Error("SQLite export unavailable: " name)
        return ptr
    }

    Query(sql, parameters := []) {
        if !this.Handle
            throw Error("Database is closed")
        ; UTF-8 is required for both paths and SQL. AStr would use ANSI for paths.
        text := this.Utf8(sql)
        statement := 0
        code := DllCall(this.Fn("sqlite3_prepare_v2"), "Ptr", this.Handle, "Ptr", text,
            "Int", -1, "Ptr*", &statement, "Ptr", 0, "CDecl Int")
        if code
            throw Error("SQLite prepare failed", , code)
        try {
            for index, value in parameters {
                encoded := this.Utf8(String(value))
                code := DllCall(this.Fn("sqlite3_bind_text"), "Ptr", statement,
                    "Int", index, "Ptr", encoded, "Int", encoded.Size - 1,
                    "Ptr", -1, "CDecl Int") ; SQLITE_TRANSIENT copies buffer
                if code
                    throw Error("SQLite parameter failed", , code)
            }
            rows := []
            columns := DllCall(this.Fn("sqlite3_column_count"), "Ptr", statement, "CDecl Int")
            loop {
                code := DllCall(this.Fn("sqlite3_step"), "Ptr", statement, "CDecl Int")
                if code = 101
                    break
                if code != 100
                    throw Error("SQLite step failed", , code)
                row := []
                loop columns {
                    ptr := DllCall(this.Fn("sqlite3_column_text"), "Ptr", statement,
                        "Int", A_Index - 1, "CDecl Ptr")
                    row.Push(ptr ? StrGet(ptr, "UTF-8") : "")
                }
                rows.Push(row)
            }
            return rows
        } finally {
            DllCall(this.Fn("sqlite3_finalize"), "Ptr", statement, "CDecl Int")
        }
    }

    static Utf8(text) {
        data := Buffer(StrPut(text, "UTF-8"), 0)
        StrPut text, data, "UTF-8"
        return data
    }

    Utf8(text) => EacSQLite.Utf8(text)

    Close() {
        if this.Handle {
            DllCall(this.Fn("sqlite3_close"), "Ptr", this.Handle, "CDecl Int")
            this.Handle := 0
        }
    }

    __Delete() => this.Close()
}
