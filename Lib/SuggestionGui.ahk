#Requires AutoHotkey v2.0+

class EacSuggestionGui {
    __New(config) {
        this.Config := config
        previous := EacDpi.Enter()
        try {
            this.Window := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020 -DPIScale", "EnglishAutocomplete candidates")
            this.Window.BackColor := "BFC4CC"
            this.Window.MarginX := 0, this.Window.MarginY := 0
            this.Panel := this.Window.AddText("x1 y1 w1 h1 BackgroundFFFFFF", "")
            this.Rows := [], this.Numbers := [], this.Labels := []
            loop config.MaxCandidates
                this.Rows.Push(this.Window.AddText("x0 y0 w1 h1 BackgroundFFFFFF", ""))
            ; NOPREFIX | LEFTNOWORDWRAP | ENDELLIPSIS | CENTERIMAGE.
            loop config.MaxCandidates {
                this.Numbers.Push(this.Window.AddText("x0 y0 w1 h1 +0x428C c777777", ""))
                this.Labels.Push(this.Window.AddText("x0 y0 w1 h1 +0x428C", ""))
            }
            this.DeleteControl := this.Window.AddText("x0 y0 w1 h1 +0x4201 c777777 BackgroundE5F1FB", "×")
            this.DeleteControl.Visible := false
        } finally {
            EacDpi.Restore(previous)
        }
        this.Dpi := 0, this.FontSize := 0
        this.NormalFont := 0, this.BoldFont := 0
        this.Visible := false, this.Rendered := "", this.LastLayout := false
        this.Disposed := false
        this.DeleteItem := false
    }

    Show(items, selected, anchor, count := 0) {
        ; Invalidate the old hit target before moving/redrawing controls. Publish
        ; the new row only after its final physical geometry is on screen.
        this.DeleteItem := false
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
                loop Min(items.Length, this.Labels.Length, count > 0 ? count : items.Length) {
                    item := items[A_Index]
                    word := EacSuggestionGui.SingleLine(item.Word)
                    translation := this.Config.ShowTranslation ? EacSuggestionGui.SingleLine(SubStr(item.Translation, 1, 512)) : ""
                    body := word (translation != "" ? "    " translation : "")
                    texts.Push(body)
                    extent := EacSuggestionGui.Measure(dc, this.NormalFont, body)
                    measuredWidth := Max(measuredWidth, extent.Width)
                    textHeight := Max(textHeight, extent.Height)
                }
            } finally {
                DllCall "ReleaseDC", "Ptr", this.Window.Hwnd, "Ptr", dc
            }
            layout := EacSuggestionGui.Layout(surface, anchor, measuredWidth, textHeight, texts.Length, this.Config, selected)
            deleteItem := selected >= 1 && selected <= items.Length && items[selected].HasOwnProp("Learned")
                && items[selected].Learned ? items[selected] : false
            if !layout.Rows {
                this.Hide()
                return
            }
            stamp := surface.Dpi ":" layout.Width ":" layout.RowHeight ":" layout.Rows ":" layout.First ":" selected ":" (!!deleteItem)
            for value in texts
                stamp .= "|" value
            if changed || !(stamp == this.Rendered) {
                this.Panel.Move(1, 1, Max(1, layout.Width - 2), Max(1, layout.Height - 2))
                for index, label in this.Labels {
                    row := this.Rows[index], number := this.Numbers[index]
                    row.Visible := number.Visible := index <= layout.Rows
                    label.Visible := index <= layout.Rows
                    if index > layout.Rows
                        continue
                    itemIndex := layout.First + index - 1
                    top := layout.MarginY + (index - 1) * layout.RowHeight
                    row.Move(1, top, Max(1, layout.Width - 2), layout.RowHeight)
                    number.Move(layout.MarginX, top, layout.NumberWidth, layout.RowHeight)
                    label.Move(layout.MarginX + layout.NumberWidth, top,
                        Max(1, layout.Width - 2 * layout.MarginX - layout.NumberWidth - layout.DeleteWidth), layout.RowHeight)
                    background := itemIndex = selected ? "BackgroundE5F1FB" : "BackgroundFFFFFF"
                    row.Opt(background)
                    number.Opt(background (itemIndex = selected ? " c005A9E" : " c777777"))
                    label.Opt(background " c202020")
                    number.Text := itemIndex
                    label.Text := texts[itemIndex]
                    DllCall "SendMessageW", "Ptr", number.Hwnd, "UInt", 0x30,
                        "Ptr", this.NormalFont, "Ptr", true
                    DllCall "SendMessageW", "Ptr", label.Hwnd, "UInt", 0x30,
                        "Ptr", itemIndex = selected ? this.BoldFont : this.NormalFont, "Ptr", true
                }
                this.Rendered := stamp
            }
            this.DeleteControl.Visible := !!deleteItem
            if deleteItem {
                this.DeleteControl.Move(layout.Width - layout.MarginX - layout.DeleteWidth,
                    layout.MarginY + (selected - layout.First) * layout.RowHeight, layout.DeleteWidth, layout.RowHeight)
                DllCall "SendMessageW", "Ptr", this.DeleteControl.Hwnd, "UInt", 0x30,
                    "Ptr", this.NormalFont, "Ptr", true
            }
            this.Window.Show("NA x" layout.X " y" layout.Y " w" layout.Width " h" layout.Height)
            this.LastLayout := layout
            this.Visible := true
            this.DeleteItem := deleteItem
        } finally {
            EacDpi.Restore(previous)
        }
    }

    SetFonts(dpi) {
        if dpi = this.Dpi && this.FontSize = this.Config.FontSize
            return false
        normal := EacSuggestionGui.CreateFont(this.Config.FontSize, dpi, 400)
        bold := EacSuggestionGui.CreateFont(this.Config.FontSize, dpi, 400)
        if !normal || !bold {
            for handle in [normal, bold]
                if handle
                    DllCall "DeleteObject", "Ptr", handle
            throw Error("Candidate font unavailable")
        }
        ; Detach old fonts before deleting them; STATIC does not own its HFONT.
        for label in this.Labels
            DllCall "SendMessageW", "Ptr", label.Hwnd, "UInt", 0x30, "Ptr", normal, "Ptr", false
        for label in this.Numbers
            DllCall "SendMessageW", "Ptr", label.Hwnd, "UInt", 0x30, "Ptr", normal, "Ptr", false
        DllCall "SendMessageW", "Ptr", this.DeleteControl.Hwnd, "UInt", 0x30, "Ptr", normal, "Ptr", false
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
        numberWidth := Max(1, Min(Round(22 * scale), Max(1, workWidth - 2 * marginX - 1)))
        deleteWidth := Max(1, Round(24 * scale))
        rowHeight := Max(1, textHeight + Round(6 * scale))
        rows := Max(0, Min(count, (workHeight - 2 * marginY) // rowHeight))
        width := Min(workWidth, Max(Round(180 * scale),
            Min(Round(520 * scale), textWidth + 2 * marginX + numberWidth + deleteWidth + Round(4 * scale))))
        height := rows * rowHeight + 2 * marginY
        ; Align the candidate word, leaving its number and padding to the left
        ; of the caret. Clamp the complete popup at work-area edges.
        x := Min(Max(surface.Left, anchor.X + Round(config.OffsetX * scale) - marginX - numberWidth), surface.Right - width)
        ; Anchors use physical coordinates. Measure the same gap from the
        ; nearest caret edge on either side, rather than from its bottom twice.
        caretBottom := anchor.HasOwnProp("Bottom") ? anchor.Bottom : anchor.Y
        caretTop := anchor.HasOwnProp("Top") ? Min(anchor.Top, caretBottom) : caretBottom
        gap := Round(config.OffsetY * scale)
        y := caretBottom + gap
        if y + height > surface.Bottom
            y := caretTop - height - gap
        y := Max(surface.Top, Min(y, surface.Bottom - height))
        return {X: x, Y: y, Width: width, Height: height, RowHeight: rowHeight,
            Rows: rows, First: Max(1, Min(count - rows + 1, selected - rows + 1)),
            MarginX: marginX, MarginY: marginY, NumberWidth: numberWidth, DeleteWidth: deleteWidth, Dpi: surface.Dpi, Surface: surface}
    }

    DeleteAtPointer() {
        if !this.Visible || !this.DeleteItem || !this.DeleteControl.Visible
            return false
        cursor := Buffer(8, 0)
        if !DllCall("GetCursorPos", "Ptr", cursor)
            return false
        x := NumGet(cursor, 0, "Int"), y := NumGet(cursor, 4, "Int")
        point := (x & 0xFFFFFFFF) | ((y & 0xFFFFFFFF) << 32)
        hwnd := DllCall("WindowFromPoint", "Int64", point, "Ptr")
        if DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != this.Window.Hwnd
            return false
        rect := Buffer(16, 0)
        DllCall "GetWindowRect", "Ptr", this.DeleteControl.Hwnd, "Ptr", rect
        return x >= NumGet(rect, 0, "Int") && x < NumGet(rect, 8, "Int")
            && y >= NumGet(rect, 4, "Int") && y < NumGet(rect, 12, "Int") ? this.DeleteItem : false
    }

    Hide() {
        if this.Visible
            this.Window.Hide()
        this.Visible := false
        this.DeleteItem := false
        this.DeleteControl.Visible := false
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
