#Requires AutoHotkey v2.0+

class EacImeStateProvider {
    ; Existing indicator uses these same bounded WM_IME_CONTROL reads.
    ; No mode writes, no TSF/UIA traversal, no ImmGetContext of a foreign process.
    GetState(context) {
        hkl := DllCall("GetKeyboardLayout", "UInt", context.Thread, "Ptr")
        language := hkl & 0xFFFF
        if (language & 0x3FF) = 9
            return {Allowed: true, Reason: "ENG", Layout: hkl}
        if language != 0x411
            return {Allowed: false, Reason: "UnknownLayout", Layout: hkl}
        ime := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", context.Focus, "Ptr")
        if !ime || !this.Read(ime, 5, &open)
            return {Allowed: false, Reason: "UnknownIME", Layout: hkl}
        ; Open Japanese IME is deliberately disabled even in reported mode 0/16:
        ; IMM cannot establish that TSF has no active composition in foreign apps.
        if open
            return {Allowed: false, Reason: "IMEOpenOrComposition", Layout: hkl}
        return {Allowed: true, Reason: "IMEClosed", Layout: hkl}
    }

    Read(ime, command, &value) {
        value := 0
        return !!DllCall("SendMessageTimeoutW", "Ptr", ime, "UInt", 0x283,
            "Ptr", command, "Ptr", 0, "UInt", 0x22, "UInt", 20,
            "Ptr*", &value, "Ptr")
    }
}
