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
        ; Same layout as the existing indicator's GetGuiThreadInfo; no UIA/IA2.
        info := context.Info
        caret := NumGet(info, 8 + 5 * A_PtrSize, "Ptr")
        if !caret
            return invalid
        offset := 8 + 6 * A_PtrSize
        top := EacDpi.CaretToPhysical(caret, NumGet(info, offset, "Int"), NumGet(info, offset + 4, "Int"))
        point := EacDpi.CaretToPhysical(caret, NumGet(info, offset, "Int"), NumGet(info, offset + 12, "Int"))
        if !top || !point || top.Y > point.Y
            return invalid
        this.Cache := {Found: true, X: point.X, Y: point.Y, Top: top.Y, Bottom: point.Y,
            Method: "GUIThreadCaret", Hwnd: context.Hwnd, Focus: context.Focus,
            Tick: A_TickCount, Age: 0}
        return this.Cache.Clone()
    }
}
