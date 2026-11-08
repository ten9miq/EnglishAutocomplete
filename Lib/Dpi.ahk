#Requires AutoHotkey v2.0+

class EacDpi {
    static Enter(context := -4) => DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
    static Restore(previous) {
        if previous
            DllCall "SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr"
    }
    static MonitorAt(x, y) {
        previous := this.Enter()
        try {
            point := Buffer(8)
            NumPut "Int", x, "Int", y, point
            monitor := DllCall("MonitorFromPoint", "Int64", NumGet(point, 0, "Int64"), "UInt", 2, "Ptr")
            info := Buffer(40, 0)
            NumPut "UInt", 40, info
            if !monitor || !DllCall("GetMonitorInfoW", "Ptr", monitor, "Ptr", info)
                throw Error("Monitor work area unavailable")
            result := {Handle: monitor, Left: NumGet(info, 20, "Int"), Top: NumGet(info, 24, "Int"),
                Right: NumGet(info, 28, "Int"), Bottom: NumGet(info, 32, "Int")}
            ; A fresh invisible PMv2 HWND supplies this monitor's effective DPI,
            ; independently of the input application's awareness or main HWND.
            probe := DllCall("CreateWindowExW", "UInt", 0, "Str", "Static", "Str", "",
                "UInt", 0x80000000, "Int", result.Left, "Int", result.Top, "Int", 1, "Int", 1,
                "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
            if !probe
                throw Error("Monitor DPI probe unavailable")
            try result.Dpi := DllCall("GetDpiForWindow", "Ptr", probe, "UInt")
            finally DllCall "DestroyWindow", "Ptr", probe
            if !result.Dpi
                throw Error("Monitor DPI unavailable")
            return result
        } finally {
            this.Restore(previous)
        }
    }
    static CaretToPhysical(hwnd, x, y) {
        context := DllCall("GetWindowDpiAwarenessContext", "Ptr", hwnd, "Ptr")
        if !context
            return false
        previous := this.Enter(context)
        try {
            point := Buffer(8)
            NumPut "Int", x, "Int", y, point
            ; rcCaret is in the caret HWND's own logical client coordinates.
            if !DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", point)
                || !DllCall("LogicalToPhysicalPointForPerMonitorDPI", "Ptr", hwnd, "Ptr", point)
                return false
            return {X: NumGet(point, 0, "Int"), Y: NumGet(point, 4, "Int")}
        } finally {
            this.Restore(previous)
        }
    }
}
