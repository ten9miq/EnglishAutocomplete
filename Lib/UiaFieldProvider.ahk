#Requires AutoHotkey v2.0+

; Bounded, read-only UIA access. Never SetValue, Select, focus a control, traverse
; arbitrary descendants, read a document's full text, or substitute unsupported
; properties. For Excel's legacy focus proxy only, inspect the formula bar or
; one addressed grid cell. Neighboring grid items supply indices only.
class EacUia {
    static Automation := false
    static Deadline := 0
    static LastProperty := 0
    static LastVariantType := 0
    static LastHresult := 0
    static MsaaStage := 0
    static MsaaState := 0

    static Context() => EacFieldGuard.Context()
    static Begin() => this.Deadline := A_TickCount + 200
    static Check() {
        if this.Deadline && A_TickCount > this.Deadline
            throw Error("UIA deadline")
    }
    static Client() {
        if !this.Automation {
            client := ComObject("{E22AD333-B25F-460C-83D0-0581107395C9}", "{34723AFF-0C9D-49D0-9896-7AB52DF8CD8A}")
            ComCall 59, client, "Int", false
            ComCall 61, client, "UInt", 50
            ComCall 63, client, "UInt", 50
            this.Automation := client
        }
        return this.Automation
    }
    static ExcelCellContext(context, focusClass := "EXCEL6") {
        try return WinGetClass("ahk_id " context.Focus) = focusClass
            && WinGetClass("ahk_id " context.Hwnd) = "XLMAIN"
            && StrLower(WinGetProcessName("ahk_id " context.Hwnd)) = "excel.exe"
            && DllCall("GetAncestor", "Ptr", context.Focus, "UInt", 2, "Ptr") = context.Hwnd
        return false
    }
    static ExcelFormulaElement(context) {
        bar := 0
        for index, hwnd in WinGetControlsHwnd("ahk_id " context.Hwnd) {
            this.Check()
            if index > 256
                throw Error("Excel native control limit")
            if WinGetClass("ahk_id " hwnd) != "EXCEL<" || !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
                continue
            if bar || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != context.Hwnd
                throw Error("Excel formula bar ambiguous")
            bar := hwnd
        }
        return bar ? this.Out(this.Client(), 6, "Ptr", bar) : false
    }
    static FocusedElement(context, previous := false, &virtualFocus := false) {
        virtualFocus := false
        element := this.Out(this.Client(), 8)
        type := this.Property(element, 30003, 3)
        if type = 50007 {
            input := this.CaretControlledInput(context, element)
            if input {
                virtualFocus := element
                return input
            }
            return element
        }
        if type != 50033 || !this.ExcelCellContext(context)
            return element
        walker := this.Out(this.Client(), 16)
        if previous && this.Property(parent := this.RawChild(walker, previous, 3), 30003, 3) = 50029 {
            ; Revisit the proven cell during focus/commit validation. Grid
            ; hit-testing again can stall while Excel is processing the key.
            found := this.ExcelFocusedChild(walker, parent)
            if !found || !this.Same(found, previous)
                throw Error("Excel cell focus changed")
        } else {
            root := this.ExcelFormulaElement(context)
            if root && (this.Property(root, 30003, 3) != 50004 || this.Property(root, 30022, 11)
                || !this.Property(root, 30010, 11) || this.Property(root, 30019, 11))
                throw Error("Excel formula bar unsafe")
            found := root ? this.ExcelFocusedChild(walker, root) : false
            if !found
                found := this.ExcelFocusedChild(walker, this.ExcelEditingCell(context, walker))
        }
        if !found
            throw Error("Excel editable focus unavailable")
        current := this.Out(this.Client(), 8), native := this.Context()
        if !this.Same(element, current) || !this.Property(current, 30008, 11)
            || !native || native.Key != context.Key
            throw Error("Excel focus changed")
        return found
    }
    static ControllerPeers(element) {
        ; Use the typed getter: some providers return the reserved unsupported
        ; value through GetCurrentPropertyValueEx for the same relation.
        peers := this.Out(element, 48)
        hr := ComCall(3, peers, "Int*", &count := 0, "Int")
        this.Check()
        if hr != 0 || count < 1 || count > 8
            throw Error("UIA controller relation unavailable")
        result := []
        Loop count
            result.Push(this.Out(peers, 4, "Int", A_Index - 1))
        return result
    }
    static CaretElement(context, caret) {
        packed := (Round((caret.Top + caret.Bottom) / 2) << 32) | (caret.X & 0xffffffff)
        hwnd := DllCall("WindowFromPoint", "Int64", packed, "Ptr")
        if !hwnd || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != context.Hwnd
            throw Error("UIA caret window mismatch")
        return this.Out(this.Client(), 7, "Int64", packed)
    }
    static CaretControlledInput(context, focused) {
        ; ARIA active-descendant can expose a suggestion ListItem as UIA focus
        ; while typing still goes to its controlling ComboBox. Never treat the
        ; ListItem itself as editable or search unrelated inputs/page content.
        if !this.Property(focused, 30008, 11) || !this.Property(focused, 30010, 11)
            || this.Property(focused, 30019, 11) || this.Property(focused, 30022, 11)
            return false
        caret := this.MsaaAnchor(context)
        if !caret
            return false
        candidate := this.CaretElement(context, caret)
        walker := this.Out(this.Client(), 16)
        Loop 8 {
            type := this.Property(candidate, 30003, 3)
            if type = 50003 {
                if !this.Property(candidate, 30009, 11) || !this.Property(candidate, 30010, 11)
                    || this.Property(candidate, 30019, 11) || this.Property(candidate, 30022, 11)
                    || this.Property(candidate, 30046, 11) || !this.AncestorMatches(candidate, context)
                    return false
                rect := this.ElementRectangle(candidate)
                if rect.Length != 4 || !(rect[3] > 0 && rect[4] > 0
                    && caret.X >= rect[1] && caret.X < rect[1] + rect[3]
                    && caret.Top >= rect[2] && caret.Bottom <= rect[2] + rect[4])
                    return false
                related := false
                for peer in this.ControllerPeers(candidate) {
                    peerType := this.Property(peer, 30003, 3)
                    if (peerType = 50008 || peerType = 50032) && this.ElementWithin(focused, peer)
                        && this.AncestorMatches(peer, context) {
                        related := true
                        break
                    }
                }
                if !related
                    return false
                current := this.Out(this.Client(), 8), native := this.Context()
                finalCaret := this.MsaaAnchor(context)
                if !this.Same(current, focused) || !this.Property(current, 30008, 11)
                    || !native || native.Key != context.Key || !finalCaret
                    || finalCaret.X != caret.X || finalCaret.Top != caret.Top || finalCaret.Bottom != caret.Bottom
                    || !this.ElementWithin(this.CaretElement(context, finalCaret), candidate)
                    return false
                return candidate
            }
            if type = 50030
                return false
            candidate := this.RawChild(walker, candidate, 3)
        }
        return false
    }
    static ExcelFocusedChild(walker, root) {
        child := this.ExcelRawChild(walker, root, 4), found := false
        Loop 8 {
            if !child
                break
            if this.Property(child, 30008, 11) {
                if found || this.Property(child, 30003, 3) != 50004
                    throw Error("Excel editable focus ambiguous")
                found := child
            }
            child := this.ExcelRawChild(walker, child, 6)
        }
        if child || (found && !this.Same(this.RawChild(walker, found, 3), root))
            throw Error("Excel raw child limit or parent changed")
        return found
    }
    static ExcelRawChild(walker, element, slot) {
        try return this.RawChild(walker, element, slot)
        catch as error {
            if error.Message = "UIA interface unavailable" && this.LastHresult = 0
                return false
            throw error
        }
    }
    static ExcelGridNeighbor(context, walker, points, property) {
        for point in points {
            this.Check()
            packed := (point[2] << 32) | (point[1] & 0xffffffff)
            hwnd := DllCall("WindowFromPoint", "Int64", packed, "Ptr")
            if !hwnd || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != context.Hwnd
                || WinGetClass("ahk_id " hwnd) != "EXCEL7"
                continue
            item := this.Out(this.Client(), 7, "Int64", packed)
            if this.Property(item, 30003, 3) != 50029
                continue
            grid := this.RawChild(walker, item, 3)
            if this.Property(grid, 30003, 3) = 50028
                return {Grid: grid, Index: this.Property(item, property, 3), Sheet: hwnd}
        }
        throw Error("Excel grid coordinate unavailable")
    }
    static ExcelEditingCell(context, walker) {
        previous := EacDpi.Enter()
        try WinGetPos &x, &y, &width, &height, "ahk_id " context.Focus
        finally EacDpi.Restore(previous)
        if width < 6 || height < 6
            throw Error("Excel edit rectangle unavailable")
        ; EXCEL6 covers the actual editor. Sample the same row horizontally
        ; and column vertically outside it. Grid.GetItem addresses one cell
        ; even on large sheets, scrolled grids and non-default cell sizes.
        row := this.ExcelGridNeighbor(context, walker, [[x+width+2,y+4],[x-3,y+4]], 30064)
        col := this.ExcelGridNeighbor(context, walker, [[x+4,y+height+2],[x+4,y-3]], 30065)
        return this.ExcelCellAt(walker, row, col)
    }
    static ExcelCellAt(walker, row, col) {
        if row.Index < 0 || col.Index < 0 || row.Sheet != col.Sheet || !this.Same(row.Grid, col.Grid)
            throw Error("Excel grid mismatch")
        pattern := this.Pattern(row.Grid, 10006, "{414C3CDC-856B-4F5B-8538-3131C6302550}")
        cell := this.Out(pattern, 3, "Int", row.Index, "Int", col.Index)
        if this.Property(cell, 30003, 3) != 50029 || !this.Same(this.RawChild(walker, cell, 3), row.Grid)
            throw Error("Excel cell outside grid")
        return cell
    }
    static RawChild(walker, element, slot) => this.Out(walker, slot, "Ptr", ComObjValue(element))
    static Out(object, slot, args*) {
        this.Check()
        pointer := 0, params := [slot, object]
        for value in args
            params.Push(value)
        params.Push("Ptr*", &pointer, "Int")
        hr := ComCall(params*)
        this.LastHresult := hr
        if hr != 0 || !pointer {
            if pointer
                ObjRelease pointer
            throw Error("UIA interface unavailable")
        }
        result := ComValue(13, pointer, 1)
        this.Check()
        return result
    }
    static Pattern(element, id, iidText) {
        iid := Buffer(16)
        DllCall "ole32\CLSIDFromString", "WStr", iidText, "Ptr", iid
        return this.Out(element, 14, "Int", id, "Ptr", iid)
    }
    static Property(element, id, type) {
        this.Check()
        this.LastProperty := id
        value := Buffer(24, 0)
        try {
            hr := ComCall(11, element, "Int", id, "Int", true, "Ptr", value, "Int")
            this.LastHresult := hr
            this.LastVariantType := NumGet(value, 0, "UShort")
            this.Check()
            if hr != 0 || NumGet(value, 0, "UShort") != type
                throw Error("UIA property unsupported")
            return type = 11 ? NumGet(value, 8, "Short") != 0 : NumGet(value, 8, "Int")
        } finally {
            DllCall "oleaut32\VariantClear", "Ptr", value
        }
    }
    static ReadOnly(range) {
        this.Check()
        this.LastProperty := 40015
        value := Buffer(24, 0)
        try {
            hr := ComCall(9, range, "Int", 40015, "Ptr", value, "Int")
            this.LastHresult := hr
            this.LastVariantType := NumGet(value, 0, "UShort")
            this.Check()
            if hr != 0 || NumGet(value, 0, "UShort") != 11
                throw Error("UIA editability unsupported")
            return NumGet(value, 8, "Short") != 0
        } finally {
            DllCall "oleaut32\VariantClear", "Ptr", value
        }
    }
    static Same(a, b) {
        this.Check()
        if ComCall(3, this.Client(), "Ptr", ComObjValue(a), "Ptr", ComObjValue(b), "Int*", &same := 0, "Int") != 0
            throw Error("UIA element comparison unavailable")
        this.Check()
        return !!same
    }
    static Compare(a, endpoint, b, otherEndpoint) {
        this.Check()
        if ComCall(5, a, "Int", endpoint, "Ptr", ComObjValue(b), "Int", otherEndpoint, "Int*", &comparison := 0, "Int") != 0
            throw Error("UIA endpoint comparison unavailable")
        this.Check()
        return comparison
    }
    static Within(range, document) => this.Compare(range, 0, document, 0) >= 0 && this.Compare(range, 1, document, 1) <= 0
    static Move(range, endpoint, count) {
        this.Check()
        if ComCall(14, range, "Int", endpoint, "Int", 0, "Int", count, "Int*", &moved := 0, "Int") != 0
            throw Error("UIA endpoint movement unavailable")
        this.Check()
    }
    static Clamp(range, document) {
        if this.Compare(range, 0, document, 0) < 0
            if ComCall(15, range, "Int", 0, "Ptr", ComObjValue(document), "Int", 0, "Int") != 0
                throw Error("UIA range clamp unavailable")
        if this.Compare(range, 1, document, 1) > 0
            if ComCall(15, range, "Int", 1, "Ptr", ComObjValue(document), "Int", 1, "Int") != 0
                throw Error("UIA range clamp unavailable")
        if !this.Within(range, document)
            throw Error("UIA range outside input")
    }
    static Text(range, limit) {
        this.Check()
        value := 0
        try {
            hr := ComCall(12, range, "Int", limit, "Ptr*", &value, "Int")
            this.Check()
            if hr != 0
                throw Error("UIA text unavailable")
            if !value
                return ""
            length := DllCall("oleaut32\SysStringLen", "Ptr", value, "UInt")
            if length > limit
                throw Error("UIA text limit")
            return length ? StrGet(value, length, "UTF-16") : ""
        } finally {
            if value
                DllCall "oleaut32\SysFreeString", "Ptr", value
        }
    }
    static Identity(element) {
        this.Check()
        ComCall 4, element, "Ptr*", &pointer := 0
        if !pointer
            throw Error("UIA identity unavailable")
        ids := ComValue(0x2003, pointer, 1)
        if DllCall("oleaut32\SafeArrayGetDim", "Ptr", pointer, "UInt") != 1
            throw Error("UIA identity invalid")
        low := ids.MinIndex(), high := ids.MaxIndex()
        if high < low || high - low > 31
            throw Error("UIA identity invalid")
        key := "UIA"
        Loop high - low + 1
            key .= ":" ids[low + A_Index - 1]
        this.Check()
        return key
    }
    static AncestorMatches(element, context) {
        root := this.Out(this.Client(), 6, "Ptr", context.Hwnd)
        walker := this.Out(this.Client(), 16)
        current := element
        ; Deeply nested web editors can exceed 32 raw ancestors. Keep both a
        ; finite traversal and the existing 200ms/COM-call deadlines.
        Loop 64 {
            if this.Same(current, root)
                return true
            current := this.Out(walker, 3, "Ptr", ComObjValue(current))
        }
        return false
    }
    static ElementWithin(element, parent) {
        walker := this.Out(this.Client(), 16)
        current := element
        Loop 32 {
            if this.Same(current, parent)
                return true
            try current := this.Out(walker, 3, "Ptr", ComObjValue(current))
            catch as error {
                if error.Message = "UIA interface unavailable" && this.LastHresult = 0
                    return false
                throw error
            }
        }
        return false
    }
    static RangeWithin(range, element) => this.ElementWithin(this.Out(range, 11), element)
    static ConfinedRange(selection, element, endpoint, amount) {
        range := this.Out(selection, 3)
        this.Move(range, endpoint, amount)
        if this.RangeWithin(range, element)
            return range
        ; Find the largest character span wholly contained in this input. No
        ; text is read while searching, including failed/outside trial ranges.
        low := 0, high := Abs(amount), sign := amount < 0 ? -1 : 1
        best := this.Out(selection, 3)
        if !this.RangeWithin(best, element)
            throw Error("UIA caret outside input")
        while low < high {
            middle := (low + high + 1) // 2
            trial := this.Out(selection, 3)
            this.Move(trial, endpoint, sign * middle)
            if this.RangeWithin(trial, element)
                low := middle, best := trial
            else
                high := middle - 1
        }
        return best
    }
    static Value(element) {
        this.Check()
        value := Buffer(24, 0)
        this.LastProperty := 30045
        try {
            hr := ComCall(11, element, "Int", 30045, "Int", true, "Ptr", value, "Int")
            this.LastHresult := hr
            this.LastVariantType := NumGet(value, 0, "UShort")
            this.Check()
            if hr != 0 || this.LastVariantType != 8
                throw Error("UIA input value unavailable")
            pointer := NumGet(value, 8, "Ptr")
            length := pointer ? DllCall("oleaut32\SysStringLen", "Ptr", pointer, "UInt") : 0
            if length > 32767
                throw Error("UIA input value limit")
            return length ? StrGet(pointer, length, "UTF-16") : ""
        } finally {
            DllCall "oleaut32\VariantClear", "Ptr", value
        }
    }
    static Selection(pattern) {
        ranges := this.Out(pattern, 5)
        if ComCall(3, ranges, "Int*", &count := 0, "Int") != 0
            throw Error("UIA selection unavailable")
        if count != 1
            throw Error("UIA ambiguous selection")
        range := this.Out(ranges, 4, "Int", 0)
        if this.Compare(range, 0, range, 1) != 0
            throw Error("UIA selected text")
        return range
    }
    static CaretRange(pattern) {
        active := 0
        range := this.Out(pattern, 10, "Int*", &active)
        if !active || this.Compare(range, 0, range, 1) != 0
            throw Error("UIA inactive caret")
        return range
    }
    static ActiveCaret(element, selection) {
        try {
            pattern := this.Pattern(element, 10024, "{506A921A-FCC9-409F-B23B-37EB74106872}")
            range := this.CaretRange(pattern)
            if this.Compare(range, 0, selection, 0) = 0 && !this.ReadOnly(range) && this.RangeWithin(range, element)
                return range
        }
        this.Check()
        return false
    }
    static CaretAnchor(element, selection, context) {
        anchor := this.Anchor(selection, context)
        if anchor
            return anchor
        ; Some editors expose no rectangles on GetSelection's empty range but
        ; do expose an active TextPattern2 caret. It must be the same endpoint,
        ; remain writable and belong to this exact focused editor.
        range := this.ActiveCaret(element, selection)
        if range {
            anchor := this.Anchor(range, context)
            if anchor
                return anchor
        }
        return this.FieldAnchor(element, context)
    }
    static ElementRectangle(element) {
        this.Check()
        value := Buffer(24, 0)
        this.LastProperty := 30001
        try {
            hr := ComCall(11, element, "Int", 30001, "Int", true, "Ptr", value, "Int")
            this.LastHresult := hr
            this.LastVariantType := NumGet(value, 0, "UShort")
            this.Check()
            if hr != 0 || this.LastVariantType != 0x2005
                throw Error("UIA field rectangle unavailable")
            array := NumGet(value, 8, "Ptr")
            if !array || DllCall("oleaut32\SafeArrayGetDim", "Ptr", array, "UInt") != 1
                throw Error("UIA field rectangle invalid")
            if DllCall("oleaut32\SafeArrayGetLBound", "Ptr", array, "UInt", 1, "Int*", &low := 0, "Int") != 0
                || DllCall("oleaut32\SafeArrayGetUBound", "Ptr", array, "UInt", 1, "Int*", &high := 0, "Int") != 0
                || high - low != 3
                throw Error("UIA field rectangle invalid")
            result := []
            Loop 4 {
                index := low + A_Index - 1
                if DllCall("oleaut32\SafeArrayGetElement", "Ptr", array, "Int*", index, "Double*", &number := 0, "Int") != 0
                    throw Error("UIA field rectangle unavailable")
                result.Push(number)
            }
            return result
        } finally {
            DllCall "oleaut32\VariantClear", "Ptr", value
        }
    }
    static ClientBounds(context) {
        previous := EacDpi.Enter()
        try {
            WinGetClientPos &x, &y, &width, &height, "ahk_id " context.Hwnd
            return {Left: x, Top: y, Right: x + width, Bottom: y + height}
        } finally {
            EacDpi.Restore(previous)
        }
    }
    static FieldAnchor(element, context) {
        try {
            ; Logical caret safety has already been established by TextPattern.
            ; For a visible editing field without a caret rectangle, position
            ; the popup below the field, not at a guessed text character.
            type := this.Property(element, 30003, 3)
            if (type != 50004 && type != 50003) || this.Property(element, 30022, 11)
                return false
            rect := this.ElementRectangle(element), bounds := this.ClientBounds(context)
            x := rect[1], y := rect[2], width := rect[3], height := rect[4]
            if !(width > 0 && height > 0 && width <= 100000 && height <= 10000
                && x >= bounds.Left && y >= bounds.Top && x + width <= bounds.Right && y + height <= bounds.Bottom)
                return false
            return {Found: true, X: Round(x), Y: Round(y + height), Top: Round(y), Bottom: Round(y + height),
                Method: "UIAField", Hwnd: context.Hwnd, Focus: context.Focus, Tick: A_TickCount, Age: 0}
        }
        this.Check()
        return false
    }
    static MsaaObject(context) {
        this.Check()
        iid := Buffer(16), pointer := 0
        DllCall "ole32\CLSIDFromString", "WStr", "{618736E0-3C3D-11CF-810C-00AA00389B71}", "Ptr", iid
        hr := DllCall("oleacc\AccessibleObjectFromWindow", "Ptr", context.Focus, "UInt", 0xFFFFFFF8,
            "Ptr", iid, "Ptr*", &pointer, "Int")
        if hr != 0 || !pointer {
            if pointer
                ObjRelease pointer
            throw Error("MSAA caret unavailable")
        }
        result := ComValue(13, pointer, 1)
        this.Check()
        return result
    }
    static MsaaOwner(caret) {
        this.Check()
        if DllCall("oleacc\WindowFromAccessibleObject", "Ptr", ComObjValue(caret), "Ptr*", &owner := 0, "Int") != 0
            throw Error("MSAA caret owner unavailable")
        this.Check()
        return owner
    }
    static MsaaInt(caret, slot) {
        this.Check()
        child := Buffer(24, 0), value := Buffer(24, 0)
        NumPut "UShort", 3, child ; VT_I4 / CHILDID_SELF, passed by value
        try {
            hr := A_PtrSize = 8 ? ComCall(slot, caret, "Ptr", child, "Ptr", value, "Int")
                : ComCall(slot, caret, "Int64", 3, "Int64", 0, "Ptr", value, "Int")
            this.Check()
            if hr != 0 || NumGet(value, 0, "UShort") != 3
                throw Error("MSAA caret metadata unavailable")
            return NumGet(value, 8, "Int")
        } finally {
            DllCall "oleaut32\VariantClear", "Ptr", value
        }
    }
    static MsaaRectangle(caret) {
        this.Check()
        child := Buffer(24, 0)
        NumPut "UShort", 3, child
        x := 0, y := 0, width := 0, height := 0
        hr := A_PtrSize = 8 ? ComCall(22, caret, "Int*", &x, "Int*", &y,
            "Int*", &width, "Int*", &height, "Ptr", child, "Int")
            : ComCall(22, caret, "Int*", &x, "Int*", &y,
                "Int*", &width, "Int*", &height, "Int64", 3, "Int64", 0, "Int")
        this.Check()
        if hr != 0
            throw Error("MSAA caret rectangle unavailable")
        return [x, y, width, height]
    }
    static MsaaAnchor(context) {
        try {
            this.MsaaStage := 1
            caret := this.MsaaObject(context)
            ; Only the focused HWND's own visible, unprotected system caret.
            ; Never inspect an accessible document, name, value or descendant.
            this.MsaaStage := 2
            if this.MsaaOwner(caret) != context.Focus
                return false
            this.MsaaStage := 3
            if this.MsaaInt(caret, 13) != 7
                return false
            this.MsaaStage := 4
            this.MsaaState := this.MsaaInt(caret, 14)
            if this.MsaaState & 0x20018001
                return false
            this.MsaaStage := 5
            rect := this.MsaaRectangle(caret), bounds := this.ClientBounds(context)
            x := rect[1], y := rect[2], width := rect[3], height := rect[4]
            if !(width >= 0 && width <= 100000 && height > 0 && height <= 10000
                && x >= bounds.Left && y >= bounds.Top && x + width <= bounds.Right && y + height <= bounds.Bottom)
                return false
            this.MsaaStage := 6
            return {Found: true, X: x, Y: y + height, Top: y, Bottom: y + height, Method: "MSAACaret",
                Hwnd: context.Hwnd, Focus: context.Focus, Tick: A_TickCount, Age: 0}
        }
        this.Check()
        return false
    }
    static Anchor(range, context) {
        this.Check()
        ComCall 10, range, "Ptr*", &pointer := 0
        if !pointer
            return false
        rects := ComValue(0x2005, pointer, 1)
        if rects.MaxIndex() - rects.MinIndex() != 3
            return false
        first := rects.MinIndex()
        x := rects[first], y := rects[first+1], width := rects[first+2], height := rects[first+3]
        if !(x >= -1000000 && x <= 1000000 && y >= -1000000 && y <= 1000000
            && width >= 0 && width <= 100000 && height > 0 && height <= 10000)
            return false
        this.Check()
        return {Found: true, X: Round(x), Y: Round(y+height), Top: Round(y), Bottom: Round(y+height), Method: "UIACaret",
            Hwnd: context.Hwnd, Focus: context.Focus, Tick: A_TickCount, Age: 0}
    }
}

class EacUiaFieldProvider {
    static Busy := false
    static Api := EacUia
    static Stage := 0
    static LastControlType := 0
    static BoundsStart := 0
    static BoundsEnd := 0
    static BoundsFlags := 0
    static FocusStage := 0
    static Read(context) {
        if this.Busy
            return EacFieldGuard.Reject("TextChanged")
        this.Busy := true
        api := this.Api
        api.Begin()
        try {
            this.Stage := 1
            client := api.Client()
            this.Stage := 2
            element := api.FocusedElement(context, false, &virtualFocus)
            type := this.LastControlType := api.Property(element, 30003, 3)
            ; Document is also used by rich text editors. Its type alone does
            ; not prove editability: require writable Text ranges below. A page
            ; viewer remains rejected even if it contains editable descendants.
            isDocument := type = 50030
            if (type != 50004 && type != 50003 && !isDocument)
                || (!api.Property(element, 30008, 11) && !virtualFocus) || !api.Property(element, 30009, 11)
                || !api.Property(element, 30010, 11) || api.Property(element, 30019, 11)
                return EacFieldGuard.Reject("UIAUnsafeField")
            offscreen := api.Property(element, 30022, 11)
            if offscreen && type != 50004
                return EacFieldGuard.Reject("UIAUnsafeField")
            if type = 50003 && api.Property(element, 30046, 11)
                return EacFieldGuard.Reject("UIAReadOnlyOrRange")
            this.Stage := 3
            if !api.AncestorMatches(element, context)
                return EacFieldGuard.Reject("UIAWindowMismatch")
            this.Stage := 4
            identity := api.Identity(element)
            ; Accessibility editors may keep their focused Edit offscreen while
            ; exposing text/selection there and the real caret via MSAA. This is
            ; not permission for hidden inputs generally: require explicit
            ; writable Value plus a visible, focus-owned system caret before
            ; any text access, then repeat the proof after the bounded read.
            if offscreen {
                if api.Property(element, 30046, 11)
                    return EacFieldGuard.Reject("UIAReadOnlyOrRange")
                if !api.MsaaAnchor(context)
                    return EacFieldGuard.Reject("UIACaretUnavailable")
            }
            this.Stage := 5
            pattern := api.Pattern(element, 10014, "{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}")
            this.Stage := 6
            document := api.Out(pattern, 7)
            selection := api.Selection(pattern)
            this.Stage := 7
            ; Chromium can deliver a new caret event before its text bounds are
            ; refreshed. Reacquire the bounds after obtaining the selection.
            if !api.Within(selection, document)
                document := api.Out(pattern, 7)
            this.BoundsStart := api.Compare(selection, 0, document, 0)
            this.BoundsEnd := api.Compare(selection, 1, document, 1)
            this.BoundsFlags := api.Compare(document, 0, document, 1) = 0 ? 1 : 0
            structural := false, eofValue := false
            ; Rich document editors need no ValuePattern and may be very large.
            ; Never use the Edit-specific full-Value EOF fallback for a document.
            if isDocument && (this.BoundsStart < 0 || this.BoundsEnd > 0
                || !api.RangeWithin(document, element) || !api.RangeWithin(selection, element))
                return EacFieldGuard.Reject("UIAReadOnlyOrRange")
            if type = 50003 || this.BoundsStart < 0 || this.BoundsEnd > 0 {
                try {
                    owner := api.Out(selection, 11)
                    docOwner := api.Out(document, 11)
                    this.BoundsFlags |= (api.Same(element, owner) ? 2 : 0) | (api.Same(element, docOwner) ? 4 : 0)
                    this.BoundsFlags |= (api.ElementWithin(owner, element) ? 8 : 0)
                        | (api.ElementWithin(docOwner, element) ? 16 : 0)
                }
                ; Rich editable providers can use different but related anchor
                ; representations. Prove actual element containment instead.
                if !api.RangeWithin(selection, element)
                    return EacFieldGuard.Reject("TextChanged")
                if api.Property(element, 30046, 11)
                    return EacFieldGuard.Reject("UIAReadOnlyOrRange")
                structural := true
            }
            if (!structural && api.ReadOnly(document)) || api.ReadOnly(selection)
                return EacFieldGuard.Reject("UIAReadOnlyOrRange")
            this.Stage := 8
            if structural {
                left := api.ConfinedRange(selection, element, 0, -128)
                right := api.ConfinedRange(selection, element, 1, 1)
            } else {
                left := api.Out(selection, 3)
                right := api.Out(selection, 3)
                api.Move(left, 0, -128)
                api.Move(right, 1, 1)
                api.Clamp(left, document), api.Clamp(right, document)
            }
            if api.Compare(left, 1, selection, 0) != 0 || api.Compare(right, 0, selection, 1) != 0
                || api.ReadOnly(left) || api.ReadOnly(right)
                || (isDocument && (!api.RangeWithin(left, element) || !api.RangeWithin(right, element)))
                return EacFieldGuard.Reject("UIARange")
            this.Stage := 9
            before := api.Text(left, 129), after := api.Text(right, 2)
            if StrLen(before) > 128 || StrLen(after) > 1
                return EacFieldGuard.Reject("UIATextUnit")
            if structural && after = "" {
                ; An empty clipped right range alone does not prove EOF (a
                ; provider could promote Character to a larger unit). Corroborate
                ; against only this editable field's bounded Value, never a page.
                value := api.Value(element)
                fullLeft := api.ConfinedRange(selection, element, 0, -(StrLen(value) + 1))
                if api.ReadOnly(fullLeft) || !(api.Text(fullLeft, StrLen(value) + 1) == value)
                    return EacFieldGuard.Reject("UIARange")
                eofValue := {Text: value}
            }
            this.Stage := 10
            anchor := offscreen ? api.MsaaAnchor(context) : api.CaretAnchor(element, selection, context)
            if !anchor
                return EacFieldGuard.Reject("UIACaretUnavailable")
            this.Stage := 11
            verified := api.Selection(pattern)
            if api.Compare(selection, 0, verified, 0) != 0
                || !(before == api.Text(left, 129)) || !(after == api.Text(right, 2))
                return EacFieldGuard.Reject("TextChanged")
            if structural && (!api.RangeWithin(selection, element) || !api.RangeWithin(left, element)
                || !api.RangeWithin(right, element) || (eofValue && !(api.Value(element) == eofValue.Text)))
                return EacFieldGuard.Reject("TextChanged")
            if isDocument && (api.ReadOnly(document) || api.ReadOnly(selection)
                || api.ReadOnly(left) || api.ReadOnly(right) || !api.RangeWithin(selection, element)
                || !api.RangeWithin(left, element) || !api.RangeWithin(right, element))
                return EacFieldGuard.Reject("TextChanged")
            ; Focus is the final remote check: earlier range/text calls may pump
            ; browser events and move DOM focus without changing the Win32 HWND.
            this.Stage := 12
            current := api.FocusedElement(context, element, &verifiedVirtualFocus)
            if !api.Same(element, current) || (!api.Property(element, 30008, 11) && !verifiedVirtualFocus)
                || api.Property(element, 30003, 3) != type
                || (type = 50003 && api.Property(element, 30046, 11))
                || api.Property(element, 30022, 11) != offscreen
                || (offscreen && api.Property(element, 30046, 11))
                return EacFieldGuard.Reject("FocusChanged")
            this.Stage := 13
            native := api.Context()
            if !native || native.Key != context.Key
                return EacFieldGuard.Reject("FocusChanged")
            EacFieldGuard.LastReason := "OK"
            this.Stage := 14
            return {Before: before, After: after, Position: identity, Identity: identity,
                Selection: selection, Element: element, Anchor: anchor, Context: context, Provider: "UIA",
                AccessibilityProxy: offscreen,
                VirtualFocusCandidate: type = 50003, FocusVerifiedAt: A_TickCount,
                EofLength: eofValue ? StrLen(eofValue.Text) : -1}
        } catch as error {
            if error.Message = "UIA deadline" || EacUia.LastHresult = -2146233083
                return EacFieldGuard.Reject("TextChanged")
            ; Chromium can publish the old selection briefly after replacing
            ; it with a typed character. Reject the snapshot, but let preview
            ; use its existing bounded retry instead of losing that character.
            ; A persistent selection still expires; commit never retries it.
            if error.Message = "UIA selected text" || error.Message = "UIA ambiguous selection"
                || error.Message = "UIA selection unavailable"
                return EacFieldGuard.Reject("TextChanged")
            ; While a cell is entering edit mode Excel can briefly return
            ; VT_UNKNOWN for IsReadOnly. Permit the existing bounded preview
            ; retry, never a read or commit using the unknown attribute.
            if error.Message = "UIA editability unsupported" && api.LastHresult = 0
                && api.LastVariantType = 13 && api.ExcelCellContext(context)
                return EacFieldGuard.Reject("TextChanged")
            return EacFieldGuard.Reject("UIAUnavailable")
        } finally {
            api.Deadline := 0
            this.Busy := false
        }
    }
    static SamePosition(a, b) {
        api := this.Api
        try {
            api.Begin()
            if a.Identity == b.Identity && a.HasOwnProp("EofLength") && b.HasOwnProp("EofLength")
                && a.EofLength >= 0 && b.EofLength >= 0
                return a.EofLength = b.EofLength
            return a.Identity == b.Identity && api.Compare(a.Selection, 0, b.Selection, 0) = 0
        } catch {
            return false
        } finally {
            api.Deadline := 0
        }
    }
    static NavigationFocused(field, context) {
        if !field.HasOwnProp("VirtualFocusCandidate") || !field.VirtualFocusCandidate
            return this.IsFocused(field, context)
        ; Navigation inserts no characters. Reuse only the recent owned-caret
        ; proof maintained by the 400ms idle check (200ms maximum UIA lease),
        ; and recheck exact current focus + critical input properties now.
        ; MSAA inside HotIf can fail while Windows is waiting for the key hook.
        if context.Key != field.Context.Key || A_TickCount - field.FocusVerifiedAt > 650
            return false
        api := this.Api
        try {
            api.Begin()
            current := api.Out(api.Client(), 8)
            if !api.Property(current, 30008, 11) || !api.Property(current, 30010, 11)
                || api.Property(current, 30019, 11) || api.Property(current, 30022, 11)
                || api.Property(field.Element, 30003, 3) != 50003
                || !api.Property(field.Element, 30009, 11) || !api.Property(field.Element, 30010, 11)
                || api.Property(field.Element, 30019, 11) || api.Property(field.Element, 30022, 11)
                || api.Property(field.Element, 30046, 11)
                return false
            if !api.Same(current, field.Element) {
                if api.Property(current, 30003, 3) != 50007
                    return false
                related := false
                for peer in api.ControllerPeers(field.Element) {
                    type := api.Property(peer, 30003, 3)
                    if (type = 50008 || type = 50032) && api.ElementWithin(current, peer)
                        && api.AncestorMatches(peer, context) {
                        related := true
                        break
                    }
                }
                if !related
                    return false
            }
            native := api.Context()
            verified := api.Out(api.Client(), 8)
            return native && native.Key = context.Key && api.Same(verified, current)
        } catch {
            return false
        } finally api.Deadline := 0
    }
    static IsFocused(field, context) {
        api := this.Api
        try {
            api.Begin()
            this.FocusStage := 1
            current := api.FocusedElement(context, field.Element, &virtualFocus)
            this.FocusStage := 2
            type := api.Property(current, 30003, 3)
            if (type != 50004 && type != 50003 && type != 50030)
                || (type = 50003 && api.Property(current, 30046, 11))
                || !api.Same(field.Element, current) || (!api.Property(current, 30008, 11) && !virtualFocus)
                || api.Property(current, 30019, 11) || !api.Property(current, 30010, 11)
                return false
            this.FocusStage := 3
            ; Ordinary navigation/idle checks maintain target identity without
            ; repeating the offscreen editor's MSAA anchor. Virtual ListItem
            ; focus is different: FocusedElement must reprove its owned caret
            ; and controller relation when renewing that proof. Never insert here.
            if api.Property(current, 30022, 11) && (type != 50004 || !field.HasOwnProp("AccessibilityProxy")
                || !field.AccessibilityProxy || api.Property(current, 30046, 11))
                return false
            this.FocusStage := 4
            native := api.Context()
            if !native || native.Key != context.Key
                return false
            this.FocusStage := 5
            field.VirtualFocusCandidate := type = 50003
            field.FocusVerifiedAt := A_TickCount
            return true
        } catch {
            return false
        } finally {
            api.Deadline := 0
        }
    }
}
