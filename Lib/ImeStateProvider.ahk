#Requires AutoHotkey v2.0+

class EacImeStateProvider {
    NativePriority := false
    __New() {
        this.Composition := EacCompositionProvider()
    }

    GetState(context) {
        state := this.ReadState(context)
        denied := {Allowed: false, Reason: state.Reason, Layout: state.Layout, Key: ""}
        if !state.Known
            return denied
        key := state.Layout ":" state.Open ":" state.Mode
        if !state.Open
            return {Allowed: true, Reason: state.Reason, Layout: state.Layout, Key: key}
        if this.NativePriority {
            denied.Reason := "NativeIMEPriority"
            return denied
        }
        ; Accept only the exact half-width alphanumeric modes (ROMAN optional).
        ; Other/reserved flags must not silently opt an unknown mode in.
        if state.Mode != 0 && state.Mode != 0x10 {
            denied.Reason := "IMEConversionMode"
            return denied
        }
        composition := this.Composition.GetState(context)
        if !composition.Known || composition.Active {
            denied.Reason := composition.Known ? "IMEComposition" : "UnknownComposition"
            return denied
        }
        ; UIA is a cross-process call: reject a mode/focus change during it.
        current := this.ReadState(context)
        if !current.Known || current.Layout != state.Layout || current.Open != state.Open
            || current.Mode != state.Mode || !this.IsCurrent(context) {
            denied.Reason := "IMEChanged"
            return denied
        }
        return {Allowed: true, Reason: "IMEHalfwidthAlphanumeric", Layout: state.Layout, Key: key}
    }

    ReadState(context) {
        hkl := DllCall("GetKeyboardLayout", "UInt", context.Thread, "Ptr")
        language := hkl & 0xFFFF
        if (language & 0x3FF) = 9
            return {Known: true, Reason: "ENG", Layout: hkl, Open: 0, Mode: -1}
        if language != 0x411
            return {Known: false, Reason: "UnknownLayout", Layout: hkl}
        ime := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", context.Focus, "Ptr")
        if !ime || !this.Read(ime, 5, &open)
            return {Known: false, Reason: "UnknownIME", Layout: hkl}
        mode := -1
        if open && !this.Read(ime, 1, &mode)
            return {Known: false, Reason: "UnknownConversionMode", Layout: hkl}
        return {Known: true, Reason: open ? "IMEOpen" : "IMEClosed", Layout: hkl,
            Open: !!open, Mode: mode}
    }

    IsCurrent(context) {
        current := EacFieldGuard.Context()
        return current && current.Key = context.Key && current.Thread = context.Thread
    }

    Read(ime, command, &value) {
        value := 0
        return !!DllCall("SendMessageTimeoutW", "Ptr", ime, "UInt", 0x283,
            "Ptr", command, "Ptr", 0, "UInt", 0x22, "UInt", 20,
            "Ptr*", &value, "Ptr")
    }
}

class EacCompositionProvider {
    ; Focus HWND only, no tree traversal, text extraction, event subscription or
    ; foreign HIMC access. A missing pattern is UNKNOWN, never "no composition".
    GetState(context) {
        unknown := {Known: false, Active: false, Reason: "Automation"}
        try {
            if !this.HasOwnProp("Automation") {
                automation := ComObject("{E22AD333-B25F-460C-83D0-0581107395C9}",
                    "{34723AFF-0C9D-49D0-9896-7AB52DF8CD8A}") ; CUIAutomation8 / IUIAutomation2
                ComCall 59, automation, "Int", false ; AutoSetFocus
                ; This runtime rejects values below 50ms with E_INVALIDARG.
                ComCall 61, automation, "UInt", 50 ; ConnectionTimeout (ms)
                ComCall 63, automation, "UInt", 50 ; TransactionTimeout (ms)
                this.Automation := automation
            }
            unknown.Reason := "Element"
            ComCall 6, this.Automation, "Ptr", context.Focus, "Ptr*", &elementPtr := 0
            if !elementPtr
                return unknown
            element := ComValue(13, elementPtr, 1)
            unknown.Reason := "Identity"
            ComCall 36, element, "Ptr*", &hwnd := 0 ; CurrentNativeWindowHandle
            ComCall 26, element, "Int*", &focused := 0
            ComCall 20, element, "Int*", &pid := 0
            DllCall "GetWindowThreadProcessId", "Ptr", context.Focus, "UInt*", &expectedPid := 0
            if hwnd != context.Focus || !focused || !expectedPid || pid != expectedPid
                return unknown
            unknown.Reason := "Pattern"
            iid := Buffer(16)
            DllCall "ole32\CLSIDFromString", "WStr", "{17E21576-996C-4870-99D9-BFF323380C06}", "Ptr", iid
            patternPtr := 0
            hr := ComCall(14, element, "Int", 10032, "Ptr", iid, "Ptr*", &patternPtr, "Int")
            if !patternPtr
                return unknown
            pattern := ComValue(13, patternPtr, 1)
            if hr != 0
                return unknown
            unknown.Reason := "Composition"
            range := 0
            try {
                hr := ComCall(9, pattern, "Ptr*", &range, "Int") ; GetActiveComposition (inherits TextPattern)
                return {Known: hr = 0, Active: !!range, HResult: hr}
            } finally {
                if range
                    ObjRelease range
            }
        }
        return unknown
    }
}
