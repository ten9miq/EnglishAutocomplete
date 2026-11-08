#Requires AutoHotkey v2.0+

; Sakura's ABI 182 is pinned in docs/ARCHITECTURE.md. Never interpret an
; arbitrary custom editor as Edit, and never write to the shared mapping.
class EacSakuraFieldProvider {
    static Busy := false

    static Read(context) {
        if this.Busy
            return EacFieldGuard.Reject("TextChanged")
        if EacSakuraQuery.Pending.Count
            return EacFieldGuard.Reject("SakuraPending")
        this.Busy := true
        try return this.ReadCurrent(context)
        finally this.Busy := false
    }

    static ReadCurrent(context) {
        try {
            if StrLower(WinGetProcessName("ahk_id " context.Hwnd)) != "sakura.exe"
                return EacFieldGuard.Reject("SakuraIdentity")
            cls := WinGetClass("ahk_id " context.Hwnd)
            if !RegExMatch(cls, "^TextEditorWindow(M64)?WP182$", &match)
                return EacFieldGuard.Reject("SakuraVersion")
            suffix := (match[1] = "M64" ? "M64" : "") "WP182"
            if !this.Editable(context)
                return EacFieldGuard.Reject("SakuraSelectionOrReadOnly")
            lease := EacSakuraLease()
            try {
                lease.Mapping := DllCall("OpenFileMappingW", "UInt", 4, "Int", false,
                    "Str", "SakuraShareData" suffix, "Ptr")
                if !lease.Mapping
                    return EacFieldGuard.Reject("SakuraMapping")
                lease.View := DllCall("MapViewOfFile", "Ptr", lease.Mapping, "UInt", 4,
                    "UInt", 0, "UInt", 0, "UPtr", 64580, "Ptr")
                if !lease.View || NumGet(lease.View, 0, "UInt") != 182
                    || NumGet(lease.View, 4, "UInt") < 64580
                    return EacFieldGuard.Reject("SakuraVersion")
                ; The mapping must describe the exact running executable version.
                version := StrSplit(FileGetVersion(WinGetProcessPath("ahk_id " context.Hwnd)), ".")
                if version.Length != 4 || NumGet(lease.View, 8, "UInt") != ((Integer(version[1]) << 16) | Integer(version[2]))
                    || NumGet(lease.View, 12, "UInt") != ((Integer(version[3]) << 16) | Integer(version[4]))
                    return EacFieldGuard.Reject("SakuraVersion")
                lease.Mutex := DllCall("OpenMutexW", "UInt", 0x100001, "Int", false,
                    "Str", "MutexSakuraEditorShareWork" suffix, "Ptr")
                if !lease.Mutex
                    return EacFieldGuard.Reject("SakuraMutex")
                wait := DllCall("WaitForSingleObject", "Ptr", lease.Mutex, "UInt", 20, "UInt")
                lease.Locked := wait = 0 || wait = 0x80
                if wait != 0 ; an abandoned buffer is unknown, not usable
                    return EacFieldGuard.Reject("SakuraMutex")
                if !this.Cursor(context, lease, &row, &column)
                    return EacFieldGuard.Reject("SakuraCursor")
                if !EacSakuraQuery.Call(context.Hwnd, 0x80E2, 0, 0, lease, &lines) ; MYWM_GETLINECOUNT
                    return EacFieldGuard.Reject("SakuraTimeout")
                empty := lines <= 0x7FFFFFFF && row = lines && column = 0
                if !empty && (row < 0 || column < 0 || lines > 0x7FFFFFFF || row >= lines) {
                    return EacFieldGuard.Reject("SakuraCursor")
                }
                offset := Max(0, column - 128)
                before := "", after := ""
                if !empty && !this.Neighborhood(context, lease, row, column, offset, &before, &after)
                    return EacFieldGuard.Reject("SakuraText")
                if !this.Cursor(context, lease, &nextRow, &nextColumn) || nextRow != row || nextColumn != column
                    return EacFieldGuard.Reject("TextChanged")
                if empty {
                    if !EacSakuraQuery.Call(context.Hwnd, 0x80E2, 0, 0, lease, &verifiedLines) || verifiedLines != lines
                        return EacFieldGuard.Reject("TextChanged")
                } else {
                    if !this.Neighborhood(context, lease, row, column, offset, &verifiedBefore, &verifiedAfter)
                        || !(before == verifiedBefore) || !(after == verifiedAfter)
                        return EacFieldGuard.Reject("TextChanged")
                }
            } finally {
                ; A timed-out recipient may still be accessing these resources.
                ; Its original SendMessageCallback completion releases the lease.
                if !lease.Deferred
                    lease.Close()
            }
            if !this.Editable(context)
                return EacFieldGuard.Reject("SakuraSelectionOrReadOnly")
            current := EacFieldGuard.Context()
            if !current || current.Key != context.Key || current.Thread != context.Thread
                return EacFieldGuard.Reject("FocusChanged")
            EacFieldGuard.LastReason := "OK"
            return {Before: before, After: after, Position: row ":" column, Context: context, Provider: "Sakura182"}
        }
        return EacFieldGuard.Reject("SakuraUnavailable")
    }

    static Cursor(context, lease, &row, &column) {
        row := -1, column := -1
        if !EacSakuraQuery.Call(context.Hwnd, 0x80CB, 0, 0, lease, &unused) ; MYWM_GETFILEINFO
            return false
        ; DLLSHAREDATA header(16) + WCHAR work[32000](64000) +
        ; EditInfo::m_ptCursor(556). All fields in this prefix have fixed width.
        column := NumGet(lease.View, 64572, "Int")
        row := NumGet(lease.View, 64576, "Int")
        return row >= 0 && column >= 0
    }

    static Neighborhood(context, lease, row, column, offset, &before, &after) {
        before := "", after := ""
        if !EacSakuraQuery.Call(context.Hwnd, 0x80D0, row, offset, lease, &remaining) ; MYWM_GETLINEDATA
            || remaining > 0x7FFFFFFF || remaining < column - offset
            return false
        count := Min(remaining, column - offset + 1)
        value := count ? StrGet(lease.View + 16, count, "UTF-16") : ""
        if StrLen(value) != count ; embedded NUL/short response is unknown
            return false
        before := SubStr(value, 1, column - offset)
        after := SubStr(value, column - offset + 1, 1)
        return true
    }

    static Editable(context) {
        lease := EacSakuraLease()
        try {
            lease.Menu := DllCall("CreatePopupMenu", "Ptr")
            if !lease.Menu
                return false
            ; InitMenu only disables/checks items. Both start enabled, so a
            ; recipient that ignores the request fails this two-item handshake.
            if !DllCall("AppendMenuW", "Ptr", lease.Menu, "UInt", 0, "UPtr", 30245, "Str", "line")
                || !DllCall("AppendMenuW", "Ptr", lease.Menu, "UInt", 0, "UPtr", 30610, "Str", "selection")
                return false
            ; fSystemMenu=true: update our private menu, skip Sakura's dynamic
            ; menu generation. No menu is displayed and no command is executed.
            if !EacSakuraQuery.Call(context.Hwnd, 0x117, lease.Menu, 0x10000, lease, &unused)
                return false
            editable := DllCall("GetMenuState", "Ptr", lease.Menu, "UInt", 30245, "UInt", 0, "UInt")
            selected := DllCall("GetMenuState", "Ptr", lease.Menu, "UInt", 30610, "UInt", 0, "UInt")
            return editable != 0xFFFFFFFF && selected != 0xFFFFFFFF
                && !(editable & 3) && !!(selected & 3)
        } finally {
            if !lease.Deferred
                lease.Close()
        }
    }
}

class EacSakuraLease {
    Mapping := 0
    View := 0
    Mutex := 0
    Menu := 0
    Thread := 0
    Locked := false
    Deferred := false
    Closing := 0

    Close() {
        if (this.Closing++) ; one owner even if a late callback interrupts cleanup
            return
        if this.Locked {
            DllCall "ReleaseMutex", "Ptr", this.Mutex
            this.Locked := false
        }
        if this.View {
            DllCall "UnmapViewOfFile", "Ptr", this.View
            this.View := 0
        }
        for name in ["Mutex", "Mapping", "Thread"] {
            if this.%name% {
                DllCall "CloseHandle", "Ptr", this.%name%
                this.%name% := 0
            }
        }
        if this.Menu {
            DllCall "DestroyMenu", "Ptr", this.Menu
            this.Menu := 0
        }
    }
}

class EacSakuraQuery {
    static Pending := Map()
    static Sequence := 0
    static Callback := CallbackCreate(ObjBindMethod(EacSakuraQuery, "Complete"), , 4)
    static Reaper := ObjBindMethod(EacSakuraQuery, "Reap")

    static Call(hwnd, message, wparam, lparam, lease, &result) {
        result := 0
        if !lease.Thread {
            threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
            if !threadId
                return false
            lease.Thread := DllCall("OpenThread", "UInt", 0x100000, "Int", false, "UInt", threadId, "Ptr")
            if !lease.Thread
                return false
        }
        token := ++this.Sequence
        request := {Done: false, Result: 0, Lease: lease}
        this.Pending[token] := request
        if !DllCall("SendMessageCallbackW", "Ptr", hwnd, "UInt", message, "UPtr", wparam,
            "Ptr", lparam, "Ptr", this.Callback, "UPtr", token) {
            this.Pending.Delete(token)
            return false
        }
        started := A_TickCount
        while !request.Done && A_TickCount - started < 20
            Sleep -1 ; pump callback replies without a 10-15ms sleep per query
        if !request.Done {
            lease.Deferred := true
            ; Completion can interrupt between the Done check and handoff.
            ; In that case it saw Deferred=false: finish its cleanup here.
            if request.Done {
                lease.Close()
                if this.Pending.Has(token)
                    this.Pending.Delete(token)
            } else
                SetTimer this.Reaper, 250
            return false
        }
        this.Pending.Delete(token)
        result := request.Result
        return true
    }

    static Complete(hwnd, message, token, result) {
        try request := this.Pending[token]
        catch
            return
        request.Result := result
        request.Done := true
        if request.Lease.Deferred {
            request.Lease.Close()
            if this.Pending.Has(token)
                this.Pending.Delete(token)
        }
    }

    static Reap() {
        ; A dead receiving thread cannot finish an outstanding window message.
        ; Release abandoned leases even when no completion callback arrives.
        for token, request in this.Pending.Clone() {
            lease := request.Lease
            if lease.Deferred && lease.Thread
                && DllCall("WaitForSingleObject", "Ptr", lease.Thread, "UInt", 0, "UInt") = 0 {
                lease.Close()
                if this.Pending.Has(token)
                    this.Pending.Delete(token)
            }
        }
        if !this.Pending.Count
            SetTimer this.Reaper, 0
    }
}
