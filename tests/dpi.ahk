#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

Checks := 0
Popup := false
OnError Fail
OnExit Cleanup
Settings := {FontSize: 11, MaxCandidates: 9, ShowTranslation: true, OffsetX: 0, OffsetY: 24}
Popup := EacSuggestionGui(Settings)
Popup.Window.Title := "EnglishAutocomplete DPI test"
Items := []
Loop 9
    Items.Push({Word: "configuration", Translation: "設定・構成 & 表示倍率 " StrReplace(Format("{:080}", 0), "0", "長い訳文")})
dc := DllCall("GetDC", "Ptr", 0, "Ptr")
try {
    for dpi in [96, 120, 144, 168, 192, 216, 240, 288] {
        Popup.SetFonts(dpi)
        logfont := Buffer(92, 0)
        Assert(DllCall("GetObjectW", "Ptr", Popup.NormalFont, "Int", 92, "Ptr", logfont), "native font readable")
        Assert(NumGet(logfont, 0, "Int") = -Round(Settings.FontSize * dpi / 72), "font has exactly one DPI conversion " dpi)
        extent := EacSuggestionGui.Measure(dc, Popup.BoldFont, "▶ 5. configuration 設定・構成 & 表示倍率")
        TestSpacing(dpi, extent.Height)
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
        Popup.Show(Items, 3, point, 5)
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
        Items[3].Learned := true
        Popup.Show(Items, 3, point, 5)
        Assert(Popup.DeleteControl.Visible && Popup.DeleteItem = Items[3], "selected learned row owns delete cross")
        ControlGetPos &dx, &dy, &dw, &dh, Popup.DeleteControl.Hwnd
        ControlGetPos &lx, &ly, &lw, &lh, Popup.Labels[3].Hwnd
        Assert(dx >= lx + lw && dx + dw <= Popup.LastLayout.Width && dy = ly && dh = lh,
            "delete cross fits selected row without covering candidate text")
        Assert(WinExist("A") != Popup.Window.Hwnd, "delete affordance keeps popup NoActivate")
        Popup.Show(Items, 0, point, 5)
        Assert(!Popup.DeleteControl.Visible && !Popup.DeleteItem, "unselected preview has no actionable delete cross")
        Items[3].Learned := false
        Popup.Hide()
    }
    Popup.Show(Items, 5, {X: 100, Y: 100, Hwnd: 0}, 9)
    Assert(Popup.LastLayout.Rows = 9, "expanded popup displays nine actual rows")
    Popup.Hide()
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
            info := Buffer(8 + 6 * A_PtrSize + 16, 0)
            NumPut "Ptr", hwnd, info, 8 + 5 * A_PtrSize
            NumPut "Int", 10, "Int", 10, "Int", 11, "Int", 30, info, 8 + 6 * A_PtrSize
            anchor := EacCaretProvider().GetPosition({Hwnd: hwnd, Focus: hwnd, Info: info})
            Assert(anchor && anchor.Found && anchor.X = physical.X && anchor.Top = physical.Y
                && anchor.Y = anchor.Bottom
                && Abs(anchor.Bottom - anchor.Top - Round(20*surface.Dpi/sourceDpi)) <= 1,
                "native caret retains physical top and bottom awareness " awareness)
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

TestSpacing(dpi, textHeight) {
    global Settings
    scale := dpi / 96, gap := Round(Settings.OffsetY * scale)
    surface := {Left: -1920, Top: -1080, Right: 0, Bottom: 0, Dpi: dpi}
    for offset in [-20, 0, 20] {
        horizontal := Settings.Clone(), horizontal.OffsetX := offset
        for count in [5, 9] {
            aligned := EacSuggestionGui.Layout(surface, {X: -1000, Y: -800}, 300, textHeight, count, horizontal, 0)
            Assert(aligned.X + aligned.MarginX + aligned.NumberWidth = -1000 + Round(offset * scale),
                "candidate text aligns with caret and one scaled horizontal offset " dpi)
        }
    }
    ; Model both native and UIA caret heights, plus a point-only fallback.
    for caretHeight in [0, Round(16 * scale), Round(40 * scale)] {
        anchor := {X: -400, Y: -800, Top: -800 - caretHeight, Bottom: -800}
        below := EacSuggestionGui.Layout(surface, anchor, 300, textHeight, 5, Settings, 0)
        Assert(below.Y - anchor.Bottom = gap, "below gap measured from caret bottom " dpi)
        anchor.Y := anchor.Bottom := -1, anchor.Top := -1 - caretHeight
        above := EacSuggestionGui.Layout(surface, anchor, 300, textHeight, 5, Settings, 0)
        Assert(anchor.Top - above.Y - above.Height = gap, "above gap measured from caret top " dpi)
        Assert(above.Y + above.Height < anchor.Top, "above popup clears full caret height " dpi)
    }
    fallback := {X: -400, Y: -1}
    layout := EacSuggestionGui.Layout(surface, fallback, 300, textHeight, 5, Settings, 0)
    Assert(fallback.Y - layout.Y - layout.Height = gap, "point-only anchor retains configured above gap " dpi)
    ; Five -> nine rows must grow away from the caret when placed above it.
    short := EacSuggestionGui.Layout(surface, anchor, 300, textHeight, 5, Settings, 0)
    tall := EacSuggestionGui.Layout(surface, anchor, 300, textHeight, 9, Settings, 5)
    Assert(short.Y + short.Height = tall.Y + tall.Height, "expanded popup keeps upper caret clearance " dpi)
    cramped := {Left: -500, Top: -100, Right: 0, Bottom: 0, Dpi: dpi}
    clipped := EacSuggestionGui.Layout(cramped, anchor, 300, textHeight, 9, Settings, 9)
    Assert(clipped.Y >= cramped.Top && clipped.Y + clipped.Height <= cramped.Bottom,
        "insufficient vertical space clamps popup inside work area " dpi)
}

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
