#Requires AutoHotkey v2.0+

class EacCaretProvider {
    __New(mode := "Win32") {
        this.Mode := mode
        this.Cache := false
    }

    GetPosition(context, force := false) {
        invalid := {Found: false, X: 0, Y: 0, Method: "Unavailable", Hwnd: context.Hwnd,
            Focus: context.Focus, Tick: A_TickCount, Age: 0}
        if this.Mode = "Off"
            return invalid
        if !force && this.Cache && this.Cache.Hwnd = context.Hwnd
            && this.Cache.Focus = context.Focus && A_TickCount - this.Cache.Tick < 30 {
            result := this.Cache.Clone()
            result.Age := A_TickCount - result.Tick
            return result
        }
        ; Same layout as the existing indicator's GetGuiThreadInfo; no UIA/IA2.
        info := context.Info
        caret := NumGet(info, 8 + 5 * A_PtrSize, "Ptr")
        if !caret
            return invalid
        offset := 8 + 6 * A_PtrSize
        point := Buffer(8, 0)
        NumPut "Int", NumGet(info, offset, "Int"), "Int", NumGet(info, offset + 12, "Int"), point
        if !DllCall("ClientToScreen", "Ptr", caret, "Ptr", point, "Int")
            return invalid
        this.Cache := {Found: true, X: NumGet(point, 0, "Int"), Y: NumGet(point, 4, "Int"),
            Method: "GUIThreadCaret", Hwnd: context.Hwnd, Focus: context.Focus,
            Tick: A_TickCount, Age: 0}
        return this.Cache.Clone()
    }
}
