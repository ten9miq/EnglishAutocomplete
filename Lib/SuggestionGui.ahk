#Requires AutoHotkey v2.0+

class EacSuggestionGui {
    __New(config) {
        this.Config := config
        previous := EacDpi.Enter()
        try {
            this.Window := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020 -DPIScale", "EnglishAutocomplete candidates")
            this.Window.BackColor := "F4F5F7"
            this.Window.MarginX := 0, this.Window.MarginY := 0
            this.Labels := []
            ; NOPREFIX | LEFTNOWORDWRAP | ENDELLIPSIS | CENTERIMAGE.
            loop config.MaxCandidates
                this.Labels.Push(this.Window.AddText("x0 y0 w1 h1 +0x428C", ""))
        } finally {
            EacDpi.Restore(previous)
        }
        this.Dpi := 0, this.FontSize := 0
        this.NormalFont := 0, this.BoldFont := 0
        this.Visible := false, this.Rendered := "", this.LastLayout := false
        this.Disposed := false
    }

    Show(items, selected, anchor) {
        if !items.Length {
            this.Hide()
            return
        }
        previous := EacDpi.Enter()
        try {
            surface := EacDpi.MonitorAt(anchor.X, anchor.Y)
            changed := this.SetFonts(surface.Dpi)
            texts := [], measuredWidth := 0, textHeight := 0
            dc := DllCall("GetDC", "Ptr", this.Window.Hwnd, "Ptr")
            if !dc
                throw Error("Candidate measurement unavailable")
            try {
                loop Min(items.Length, this.Labels.Length) {
                    item := items[A_Index]
                    word := EacSuggestionGui.SingleLine(item.Word)
                    translation := this.Config.ShowTranslation ? EacSuggestionGui.SingleLine(SubStr(item.Translation, 1, 512)) : ""
                    body := A_Index ". " word (translation != "" ? "  " translation : "")
                    texts.Push((A_Index = selected ? "▶ " : "   ") body)
                    ; Measure the widest marker and bold face for all rows so
                    ; selection changes do not resize the popup.
                    extent := EacSuggestionGui.Measure(dc, this.BoldFont, "▶ " body)
                    measuredWidth := Max(measuredWidth, extent.Width)
                    textHeight := Max(textHeight, extent.Height)
                }
            } finally {
                DllCall "ReleaseDC", "Ptr", this.Window.Hwnd, "Ptr", dc
            }
            layout := EacSuggestionGui.Layout(surface, anchor, measuredWidth, textHeight, texts.Length, this.Config, selected)
            if !layout.Rows {
                this.Hide()
                return
            }
            stamp := surface.Dpi ":" layout.Width ":" layout.RowHeight ":" layout.Rows ":" layout.First ":" selected
            for value in texts
                stamp .= "|" value
            if changed || !(stamp == this.Rendered) {
                for index, label in this.Labels {
                    label.Visible := index <= layout.Rows
                    if index > layout.Rows
                        continue
                    itemIndex := layout.First + index - 1
                    label.Move(layout.MarginX, layout.MarginY + (index - 1) * layout.RowHeight,
                        layout.Width - 2 * layout.MarginX, layout.RowHeight)
                    label.Opt(itemIndex = selected ? "BackgroundD7E9FF" : "BackgroundF4F5F7")
                    label.Text := texts[itemIndex]
                    DllCall "SendMessageW", "Ptr", label.Hwnd, "UInt", 0x30,
                        "Ptr", itemIndex = selected ? this.BoldFont : this.NormalFont, "Ptr", true
                }
                this.Rendered := stamp
            }
            this.Window.Show("NA x" layout.X " y" layout.Y " w" layout.Width " h" layout.Height)
            this.LastLayout := layout
            this.Visible := true
        } finally {
            EacDpi.Restore(previous)
        }
    }

    SetFonts(dpi) {
        if dpi = this.Dpi && this.FontSize = this.Config.FontSize
            return false
        normal := EacSuggestionGui.CreateFont(this.Config.FontSize, dpi, 400)
        bold := EacSuggestionGui.CreateFont(this.Config.FontSize, dpi, 700)
        if !normal || !bold {
            for handle in [normal, bold]
                if handle
                    DllCall "DeleteObject", "Ptr", handle
            throw Error("Candidate font unavailable")
        }
        ; Detach old fonts before deleting them; STATIC does not own its HFONT.
        for label in this.Labels
            DllCall "SendMessageW", "Ptr", label.Hwnd, "UInt", 0x30, "Ptr", normal, "Ptr", false
        for handle in [this.NormalFont, this.BoldFont]
            if handle
                DllCall "DeleteObject", "Ptr", handle
        this.NormalFont := normal, this.BoldFont := bold
        this.Dpi := dpi, this.FontSize := this.Config.FontSize
        return true
    }

    static CreateFont(points, dpi, weight) {
        ; Explicit pixel height avoids SetFont's additional system-DPI conversion.
        height := -DllCall("MulDiv", "Int", points, "Int", dpi, "Int", 72, "Int")
        return DllCall("CreateFontW", "Int", height, "Int", 0, "Int", 0, "Int", 0,
            "Int", weight, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1,
            "UInt", 0, "UInt", 0, "UInt", 5, "UInt", 0, "Str", "Segoe UI", "Ptr")
    }

    static SingleLine(value) => StrReplace(StrReplace(StrReplace(value, "`r", " "), "`n", " "), "`t", " ")

    static Measure(dc, font, value) {
        oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        try {
            rect := Buffer(16, 0)
            if !DllCall("DrawTextW", "Ptr", dc, "Str", value, "Int", -1, "Ptr", rect, "UInt", 0xC20)
                throw Error("Candidate text extent unavailable")
            return {Width: NumGet(rect, 8, "Int"), Height: NumGet(rect, 12, "Int")}
        } finally {
            DllCall "SelectObject", "Ptr", dc, "Ptr", oldFont
        }
    }

    static Layout(surface, anchor, textWidth, textHeight, count, config, selected := 1) {
        scale := surface.Dpi / 96
        workWidth := surface.Right - surface.Left, workHeight := surface.Bottom - surface.Top
        marginX := Max(0, Min(Round(6 * scale), (workWidth - 1) // 2))
        marginY := Max(0, Min(Round(4 * scale), (workHeight - 1) // 2))
        rowHeight := Max(1, textHeight + Round(6 * scale))
        rows := Max(0, Min(count, (workHeight - 2 * marginY) // rowHeight))
        width := Min(workWidth, Max(Round(180 * scale),
            Min(Round(520 * scale), textWidth + 2 * marginX + Round(4 * scale))))
        height := rows * rowHeight + 2 * marginY
        x := Min(Max(surface.Left, anchor.X + Round(config.OffsetX * scale)), surface.Right - width)
        y := anchor.Y + Round(config.OffsetY * scale)
        if y + height > surface.Bottom
            y := anchor.Y - height - Round(12 * scale)
        y := Max(surface.Top, Min(y, surface.Bottom - height))
        return {X: x, Y: y, Width: width, Height: height, RowHeight: rowHeight,
            Rows: rows, First: Max(1, Min(count - rows + 1, selected - rows + 1)),
            MarginX: marginX, MarginY: marginY, Dpi: surface.Dpi, Surface: surface}
    }

    Hide() {
        if this.Visible
            this.Window.Hide()
        this.Visible := false
    }

    Dispose() {
        if this.Disposed
            return
        this.Disposed := true
        this.Hide()
        this.Window.Destroy()
        for handle in [this.NormalFont, this.BoldFont]
            if handle
                DllCall "DeleteObject", "Ptr", handle
        this.NormalFont := 0, this.BoldFont := 0
    }

    __Delete() {
        try this.Dispose()
    }
}
