#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

Checks := 0
Popup := false
OnError Fail
OnExit Cleanup
Settings := {FontSize: 11, MaxCandidates: 5, ShowTranslation: true, OffsetX: 32, OffsetY: 80}
Popup := EacSuggestionGui(Settings)
Popup.Window.Title := "EnglishAutocomplete DPI test"
Items := []
Loop 5
    Items.Push({Word: "configuration", Translation: "設定・構成 & 表示倍率 " StrReplace(Format("{:080}", 0), "0", "長い訳文")})
dc := DllCall("GetDC", "Ptr", 0, "Ptr")
try {
    for dpi in [96, 120, 144, 168, 192, 216, 240, 288] {
        Popup.SetFonts(dpi)
        logfont := Buffer(92, 0)
        Assert(DllCall("GetObjectW", "Ptr", Popup.NormalFont, "Int", 92, "Ptr", logfont), "native font readable")
        Assert(NumGet(logfont, 0, "Int") = -Round(Settings.FontSize * dpi / 72), "font has exactly one DPI conversion " dpi)
        extent := EacSuggestionGui.Measure(dc, Popup.BoldFont, "▶ 5. configuration 設定・構成 & 表示倍率")
        for surface in [{Left: 0, Top: 0, Right: 1920, Bottom: 1040, Dpi: dpi},
            {Left: -1920, Top: -1080, Right: 0, Bottom: 0, Dpi: dpi},
            {Left: 100, Top: 1600, Right: 580, Bottom: 1800, Dpi: dpi}] {
            for point in [{X: surface.Left, Y: surface.Top}, {X: surface.Right-1, Y: surface.Bottom-1}] {
                layout := EacSuggestionGui.Layout(surface, point, 6000, extent.Height, 5, Settings, 5)
                Assert(layout.X >= surface.Left && layout.Y >= surface.Top
                    && layout.X + layout.Width <= surface.Right && layout.Y + layout.Height <= surface.Bottom,
                    "popup stays inside simulated work area " dpi)
                Assert(layout.RowHeight >= extent.Height, "row contains measured font height")
                Assert(layout.Rows = 0 || (layout.First <= 5 && layout.First + layout.Rows > 5), "selected candidate stays visible")
            }
        }
    }
} finally {
    DllCall "ReleaseDC", "Ptr", 0, "Ptr", dc
}
Assert(EacSuggestionGui.SingleLine("a`r`nb`t&c") == "a  b &c", "native static labels cannot wrap via newlines/tabs")

previous := EacDpi.Enter()
try {
    Loop MonitorGetCount() {
        MonitorGetWorkArea A_Index, &left, &top, &right, &bottom
        point := {X: right - 2, Y: bottom - 2, Hwnd: 0}
        Popup.Show(Items, 3, point)
        layout := Popup.LastLayout
        Assert(layout.Dpi >= 96 && layout.Surface.Left = left && layout.Surface.Top = top,
            "caret monitor is selected independently of input HWND")
        Assert(WinExist("A") != Popup.Window.Hwnd, "NoActivate popup does not take focus")
        WinGetPos &x, &y, &width, &height, "ahk_id " Popup.Window.Hwnd
        Assert(x = layout.X && y = layout.Y && width = layout.Width && height = layout.Height,
            "actual window uses physical pixel geometry")
        Assert(x >= left && y >= top && x + width <= right && y + height <= bottom,
            "actual popup fits actual monitor work area")
        for index, label in Popup.Labels {
            ControlGetPos &lx, &ly, &lw, &lh, label.Hwnd
            Assert(lx >= 0 && ly >= 0 && lx + lw <= width && ly + lh <= height, "actual child bounds fit popup")
            actualFont := DllCall("SendMessageW", "Ptr", label.Hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
            Assert(actualFont = (index = 3 ? Popup.BoldFont : Popup.NormalFont), "native STATIC uses measured font")
            Assert(WinGetStyle("ahk_id " label.Hwnd) & 0x4000, "long translation uses end ellipsis")
        }
        Record("MONITOR index=" A_Index " dpi=" layout.Dpi " rect=" x "," y "," width "," height)
        Popup.Hide()
    }
    ; Validate caret logical->physical conversion for different source awareness
    ; without changing Windows settings, foreground windows, or typing anything.
    for awareness in [-1, -2, -4] {
        old := EacDpi.Enter(awareness)
        hwnd := DllCall("CreateWindowExW", "UInt", 0, "Str", "Static", "Str", "",
            "UInt", 0x80000000, "Int", 100, "Int", 100, "Int", 200, "Int", 100,
            "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
        EacDpi.Restore(old)
        Assert(hwnd, "source-awareness fixture created")
        try {
            rect := Buffer(16)
            DllCall "GetWindowRect", "Ptr", hwnd, "Ptr", rect
            surface := EacDpi.MonitorAt(NumGet(rect, 0, "Int"), NumGet(rect, 4, "Int"))
            sourceDpi := DllCall("GetDpiForWindow", "Ptr", hwnd, "UInt")
            physical := EacDpi.CaretToPhysical(hwnd, 10, 10)
            Assert(physical && Abs(physical.X - NumGet(rect, 0, "Int") - Round(10*surface.Dpi/sourceDpi)) <= 1
                && Abs(physical.Y - NumGet(rect, 4, "Int") - Round(10*surface.Dpi/sourceDpi)) <= 1,
                "caret conversion matches physical window bounds awareness " awareness)
        } finally {
            DllCall "DestroyWindow", "Ptr", hwnd
        }
    }
} finally {
    EacDpi.Restore(previous)
}
Record("PASS dpi_checks=" Checks " monitors=" MonitorGetCount() " AHK=" A_AhkVersion)
Cleanup()
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}
Record(message) => FileAppend(message "`n", "*", "UTF-8")
Fail(e, *) {
    Record("FAIL " e.Message " at " e.Line "`n" e.Stack)
    Cleanup()
    ExitApp 1
}
Cleanup(*) {
    global Popup
    if Popup {
        Popup.Dispose()
        Popup := false
    }
}
