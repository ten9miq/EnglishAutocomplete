#Requires AutoHotkey v2.0+

class EacSuggestionGui {
    __New(config) {
        this.Config := config
        this.Window := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020 -DPIScale", "EnglishAutocomplete candidates")
        this.Window.BackColor := "F4F5F7"
        this.Window.MarginX := 8, this.Window.MarginY := 6
        this.Labels := []
        this.Dpi := 0
        this.Visible := false
        this.Rendered := ""
        loop config.MaxCandidates
            this.Labels.Push(this.Window.AddText("x8 y" (6 + (A_Index - 1) * 24) " w560 h24 +0x80", ""))
    }

    Show(items, selected, anchor) {
        dpi := DllCall("GetDpiForWindow", "Ptr", anchor.Hwnd, "UInt") || 96
        scale := dpi / 96
        rowHeight := Round((this.Config.FontSize + 11) * scale)
        width := Round(560 * scale)
        height := rowHeight * items.Length + Round(12 * scale)
        stamp := dpi ":" selected
        for item in items
            stamp .= "|" item.Word ":" item.Translation
        if !(stamp == this.Rendered) {
            for index, label in this.Labels {
                label.SetFont("s" Round(this.Config.FontSize * scale) (index = selected ? " bold" : " norm"), "Segoe UI")
                label.Move(Round(8 * scale), Round(6 * scale) + (index - 1) * rowHeight, width - Round(16 * scale), rowHeight)
                label.Opt(index = selected ? "BackgroundD7E9FF" : "BackgroundF4F5F7")
                label.Text := index <= items.Length ? (index = selected ? "▶ " : "   ") index ". " items[index].Word
                    . (this.Config.ShowTranslation && items[index].Translation != "" ? "  " SubStr(items[index].Translation, 1, 70) : "") : ""
                label.Visible := index <= items.Length
            }
            this.Rendered := stamp
        }
        point := Buffer(8)
        NumPut "Int", anchor.X, "Int", anchor.Y, point
        monitor := DllCall("MonitorFromPoint", "Int64", NumGet(point, 0, "Int64"), "UInt", 2, "Ptr")
        info := Buffer(40, 0), NumPut("UInt", 40, info)
        DllCall "GetMonitorInfoW", "Ptr", monitor, "Ptr", info
        left := NumGet(info, 20, "Int"), top := NumGet(info, 24, "Int")
        right := NumGet(info, 28, "Int"), bottom := NumGet(info, 32, "Int")
        width := Min(width, right - left)
        x := Min(Max(left, anchor.X + Round(this.Config.OffsetX * scale)), right - width)
        y := anchor.Y + Round(this.Config.OffsetY * scale)
        if y + height > bottom
            y := anchor.Y - height - Round(12 * scale)
        y := Max(top, Min(y, bottom - height))
        this.Window.Show("NA x" x " y" y " w" width " h" height)
        this.Visible := true
    }

    Hide() {
        if this.Visible
            this.Window.Hide()
        this.Visible := false
    }
}
