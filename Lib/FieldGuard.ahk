#Requires AutoHotkey v2.0+

class EacFieldGuard {
    static LastReason := ""
    static Context() {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if !hwnd
            return false
        thread := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        info := Buffer(24 + 6 * A_PtrSize, 0)
        NumPut "UInt", info.Size, info
        if !DllCall("GetGUIThreadInfo", "UInt", thread, "Ptr", info, "Int")
            return false
        focus := NumGet(info, 8 + A_PtrSize, "Ptr")
        if !focus || NumGet(info, 4, "UInt") & 0x1C ; menus/move-size: no input
            return false
        return {Hwnd: hwnd, Focus: focus, Thread: thread, Info: info,
            Key: hwnd ":" focus, Tick: A_TickCount}
    }

    static Message(hwnd, message, wparam, lparam, &result) {
        result := 0
        return !!DllCall("SendMessageTimeoutW", "Ptr", hwnd, "UInt", message,
            "Ptr", wparam, "Ptr", lparam, "UInt", 0x22, "UInt", 20,
            "Ptr*", &result, "Ptr")
    }

    static Read(context) {
        this.LastReason := "UnknownField"
        if !context
            return false
        try {
            cls := WinGetClass("ahk_id " context.Focus)
            if cls = "SakuraView182"
                return EacSakuraFieldProvider.Read(context)
            ; App/window class names do not establish text-field safety. Other
            ; frameworks may publish the same verifiable UIA Edit contract.
            ; Keep native controls on their stricter native path: a rejected
            ; password/readonly Edit must never fall through to another provider.
            if !RegExMatch(cls, "i)^(?:Edit|RichEdit(?:20[AW]|50[AW]|D2DPT)?)$")
                return EacUiaFieldProvider.Read(context)
            style := WinGetStyle("ahk_id " context.Focus)
            if style & 0x820 ; ES_PASSWORD or ES_READONLY
                return false
            if !this.Message(context.Focus, 0xD2, 0, 0, &password) || password
                return false
            if !this.Message(context.Focus, 0xB0, 0, 0, &selection)
                return false
            start := selection & 0xFFFF, end := (selection >> 16) & 0xFFFF
            if start != end || start = 0xFFFF
                return this.Reject("Selection")
            if !this.Message(context.Focus, 0xE, 0, 0, &length) || length > 32767
                return this.Reject("LengthOrTimeout")
            text := Buffer((length + 1) * 2, 0)
            if !this.Message(context.Focus, 0xD, length + 1, text.Ptr, &copied)
                return this.Reject("ReadTimeout")
            if copied != length || start > length
                return this.Reject("TextChanged")
            value := StrGet(text, length, "UTF-16")
            current := this.Context()
            if !current || current.Key != context.Key
                return this.Reject("FocusChanged")
            this.LastReason := "OK"
            ; Retain only the local token neighborhood, never the whole field.
            return {Before: SubStr(value, Max(1, start - 127), Min(128, start)), After: SubStr(value, start + 1, 1),
                Position: start, Context: context}
        }
        return false
    }

    static Reject(reason) {
        this.LastReason := reason
        return false
    }

    static SameTarget(a, b) {
        aProvider := a.HasOwnProp("Provider") ? a.Provider : "Native"
        bProvider := b.HasOwnProp("Provider") ? b.Provider : "Native"
        return aProvider = bProvider && (aProvider != "UIA" || a.Identity == b.Identity)
    }
    static SamePosition(a, b) {
        if !this.SameTarget(a, b)
            return false
        return a.HasOwnProp("Provider") && a.Provider = "UIA"
            ? EacUiaFieldProvider.SamePosition(a, b) : a.Position = b.Position
    }
    static StillFocused(field, context) => !field.HasOwnProp("Identity") || EacUiaFieldProvider.IsFocused(field, context)
    static NavigationFocused(field, context) => !field.HasOwnProp("Identity") || EacUiaFieldProvider.NavigationFocused(field, context)

    static ObservedSuffix(field, observed) {
        ; Modal editors may consume a printable command (Vim's i, for example)
        ; without inserting it. Drop only extra leading observations when the
        ; entire real word is their exact suffix. This never invents text or
        ; accepts an arbitrary mismatch, stale shorter prefix, URL, or email.
        if !field || !RegExMatch(field.Before, "[A-Za-z][A-Za-z'-]*$", &match)
            return ""
        actual := match[0]
        return StrLen(actual) < StrLen(observed) && SubStr(observed, StrLen(observed)-StrLen(actual)+1) == actual
            && this.Matches(field, actual) ? actual : ""
    }

    static Matches(field, word, boundary := false) {
        if !field || word = ""
            return false
        before := boundary ? RTrim(field.Before, " `t`r`n") : field.Before
        if boundary && before = field.Before
            return false
        offset := StrLen(before) - StrLen(word)
        if offset < 0 || !(SubStr(before, offset + 1) == word)
            return false
        preceding := offset > 0 ? SubStr(before, offset, 1) : ""
        if offset > 0 && RegExMatch(preceding, "[A-Za-z0-9_@:/.'-]")
            return false
        return boundary || !RegExMatch(SubStr(field.After, 1, 1), "[A-Za-z0-9_@:/.'-]")
    }
}
