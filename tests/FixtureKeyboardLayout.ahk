#Requires AutoHotkey v2.0+

; LoadKeyboardLayout changes the session's available layouts on Windows 8+.
; Only unload the layout if this fixture introduced it; preserve user layouts.
class EacFixtureKeyboardLayout {
    __New() {
        this.Previous := DllCall("GetKeyboardLayout", "UInt", 0, "Ptr")
        this.Existing := Map()
        this.English := 0
        count := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0, "Int")
        if count <= 0
            throw Error("Cannot snapshot keyboard layouts before fixture")
        layouts := Buffer(count * A_PtrSize)
        count := DllCall("GetKeyboardLayoutList", "Int", count, "Ptr", layouts, "Int")
        if count <= 0
            throw Error("Cannot read keyboard layouts before fixture")
        loop count
            this.Existing[NumGet(layouts, (A_Index - 1) * A_PtrSize, "Ptr")] := true
        OnExit ObjBindMethod(this, "Restore")
    }

    UseEnglish() {
        layout := DllCall("LoadKeyboardLayoutW", "Str", "00000409", "UInt", 0, "Ptr")
        if !layout || (layout & 0xFFFF) != 0x409
            throw Error("Cannot load English US layout for fixture")
        this.English := layout
        if !DllCall("ActivateKeyboardLayout", "Ptr", layout, "UInt", 0, "Ptr")
            throw Error("Cannot activate English US layout for fixture")
    }

    Restore(*) {
        if !this.English
            return
        layout := this.English
        this.English := 0
        DllCall "ActivateKeyboardLayout", "Ptr", this.Previous, "UInt", 0, "Ptr"
        if !this.Existing.Has(layout)
            if !DllCall("UnloadKeyboardLayout", "Ptr", layout, "Int")
                FileAppend "Fixture could not unload temporary English US layout`n", "**"
    }
}
