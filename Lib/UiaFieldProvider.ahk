#Requires AutoHotkey v2.0+

; Bounded, read-only UIA access. Never SetValue, Select, focus a control, traverse
; descendants, read a document's full text, or substitute unsupported properties.
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
        Loop 32 {
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
            element := api.Out(client, 8)
            type := this.LastControlType := api.Property(element, 30003, 3)
            ; Document is also used by rich text editors. Its type alone does
            ; not prove editability: require writable Text ranges below. A page
            ; viewer remains rejected even if it contains editable descendants.
            isDocument := type = 50030
            if (type != 50004 && type != 50003 && !isDocument)
                || !api.Property(element, 30008, 11) || !api.Property(element, 30009, 11)
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
            current := api.Out(client, 8)
            if !api.Same(element, current) || !api.Property(element, 30008, 11)
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
                EofLength: eofValue ? StrLen(eofValue.Text) : -1}
        } catch as error {
            if error.Message = "UIA deadline" || EacUia.LastHresult = -2146233083
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
    static IsFocused(field, context) {
        api := this.Api
        try {
            api.Begin()
            this.FocusStage := 1
            current := api.Out(api.Client(), 8)
            this.FocusStage := 2
            type := api.Property(current, 30003, 3)
            if (type != 50004 && type != 50003 && type != 50030)
                || (type = 50003 && api.Property(current, 30046, 11))
                || !api.Same(field.Element, current) || !api.Property(current, 30008, 11)
                || api.Property(current, 30019, 11) || !api.Property(current, 30010, 11)
                return false
            this.FocusStage := 3
            ; Navigation/idle checks only maintain target identity. They never
            ; insert text. Re-querying the transient MSAA caret here can let a
            ; native Tab through while the accessibility caret is refreshing.
            ; Read()/Commit still require fresh visible system-caret proof.
            if api.Property(current, 30022, 11) && (type != 50004 || !field.HasOwnProp("AccessibilityProxy")
                || !field.AccessibilityProxy || api.Property(current, 30046, 11))
                return false
            this.FocusStage := 4
            native := api.Context()
            if !native || native.Key != context.Key
                return false
            this.FocusStage := 5
            return true
        } catch {
            return false
        } finally {
            api.Deadline := 0
        }
    }
}
