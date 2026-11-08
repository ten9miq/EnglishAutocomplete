#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; Headless tests only. No UIA client, GUI, focus change, or input is created.
; The backend models character offsets independently of provider control flow.
Checks := 0
OnError Fail
EacUiaFieldProvider.Api := UiaTestApi
try {
    TestRead()
    TestStructuralRead()
    TestComHelpers()
    FileAppend "PASS uia_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
} finally {
    EacUiaFieldProvider.Api := EacUia
    EacUiaFieldProvider.Busy := false
    EacUia.Deadline := 0
    UiaTestApi.Array := false
}
ExitApp 0

TestRead() {
    api := UiaTestApi
    api.Reset()
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "alpha confi" && field.After == "!", "local text around caret")
    Assert(field.Identity == "UIA:42:1" && field.Position == field.Identity && field.Provider = "UIA", "stable runtime identity")
    Assert(field.Context = api.Native && field.Anchor.Method = "MockCaret", "context and anchor retained")
    Assert(api.TextCalls = 4 && api.SelectionCalls = 2 && api.FocusCalls = 2, "text selection and focus rechecked")
    Assert(api.TextLimits = "129,2,129,2," && api.Moves = "0:-128,1:1,", "separate bounded left and right reads")
    Assert(InStr(api.Events, "Text,Text,Focus,PropertyFocus,Context,"), "focus and native context checked after final text reads")
    Assert(!api.Deadline && !EacUiaFieldProvider.Busy && EacFieldGuard.LastReason = "OK", "success clears lease")

    api.Reset(), api.Props[30003] := 50030
    Rejected("document viewer is not an input", "UIAUnsafeField", true)
    api.Reset(), api.Content := Repeat("x", 220) "!", api.Caret := 220
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && StrLen(field.Before) = 128 && field.After == "!", "long document exposes at most local 128 characters")
    api.Reset(), api.Content := "", api.Caret := 0
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "" && field.After == "", "empty input accepted")
    api.Reset(), api.Caret := 0
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "" && field.After == "a", "start of input clamps left range")
    api.Reset(), api.Caret := StrLen(api.Content)
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.After == "", "end of input clamps right range")
    api.Reset(), api.NoAnchor := true
    Rejected("unavailable caret anchor", "UIACaretUnavailable")

    for pair in [[30003, 50020], [30008, false], [30009, false], [30010, false], [30019, true], [30022, true]] {
        api.Reset(), api.Props[pair[1]] := pair[2]
        Rejected("unsafe property " pair[1], "UIAUnsafeField", true)
    }
    api.Reset(), api.UnknownProperty := 30019
    Rejected("unknown password property", "UIAUnavailable", true)
    api.Reset(), api.Ancestor := false
    Rejected("different root ancestor", "UIAWindowMismatch", true)
    api.Reset(), api.SelectionCount := 0
    Rejected("missing selection", "UIAUnavailable", true)
    api.Reset(), api.SelectionCount := 2
    Rejected("multiple selections", "UIAUnavailable", true)
    api.Reset(), api.SelectionLength := 1
    Rejected("noncollapsed selection", "UIAUnavailable", true)
    api.Reset(), api.DocumentReadOnly := true
    Rejected("readonly document", "UIAReadOnlyOrRange", true)
    api.Reset(), api.SelectionReadOnly := true
    Rejected("readonly caret range", "UIAReadOnlyOrRange", true)
    api.Reset(), api.LeftReadOnly := true
    Rejected("readonly left neighborhood", "UIARange", true)
    api.Reset(), api.RightReadOnly := true
    Rejected("readonly right neighborhood", "UIARange", true)
    api.Reset(), api.UnknownReadOnly := true
    Rejected("unsupported readonly attribute", "UIAUnavailable", true)
    api.Reset(), api.Caret := StrLen(api.Content) + 1
    Rejected("selection outside document end", "TextChanged", true)
    api.Reset(), api.Caret := -1
    Rejected("selection outside document start", "TextChanged", true)
    api.Reset(), api.BadLeftEnd := true
    Rejected("provider moves opposite left endpoint", "UIARange", true)
    api.Reset(), api.BadRightStart := true
    Rejected("provider moves opposite right endpoint", "UIARange", true)

    api.Reset(), api.Content := Repeat("x", 300), api.Caret := 250, api.UnitSize := 200
    Rejected("character unit larger than text limit on left", "UIATextUnit")
    Assert(api.TextCalls = 2, "truncated left GetText is rejected before revalidation")
    api.Reset(), api.Content := Repeat("x", 300), api.Caret := 0, api.UnitSize := 200
    Rejected("character unit larger than text limit on right", "UIATextUnit")
    api.Reset(), api.CurrentElement := {Id: "UIA:42:2"}
    Rejected("focused UIA field changes in same native window", "FocusChanged")
    api.Reset(), api.CurrentNative := {Hwnd: 7, Focus: 9, Key: "7:9"}
    Rejected("native focus window changes", "FocusChanged")
    api.Reset(), api.CurrentNative := false
    Rejected("native focus disappears", "FocusChanged")
    api.Reset(), api.LoseFieldFocus := true
    Rejected("field loses focus after text reads", "FocusChanged")
    api.Reset(), api.CaretShift := 1
    Rejected("caret changes during read", "TextChanged")
    api.Reset(), api.VerifiedSelectionLength := 1
    Rejected("selection becomes noncollapsed", "UIAUnavailable")
    api.Reset(), api.ChangeTextCall := 3
    Rejected("left text changes during read", "TextChanged")
    api.Reset(), api.ChangeTextCall := 4
    Rejected("right text changes during read", "TextChanged")
    for stage in ["Client", "Focus", "Identity", "Pattern", "Document", "Clone", "Move", "Clamp", "ReadOnly", "Text", "Anchor", "Context"] {
        api.Reset(), api.Failure := stage
        Rejected("RPC failure at " stage, "UIAUnavailable", !InStr("Text,Anchor,Context", stage))
    }
    api.Reset(), EacUiaFieldProvider.Busy := true
    Assert(!EacUiaFieldProvider.Read(api.Native) && !api.BeginCalls && EacFieldGuard.LastReason = "TextChanged", "busy guard never touches backend")
    EacUiaFieldProvider.Busy := false
    api.Reset(), api.Reenter := true
    Assert(EacUiaFieldProvider.Read(api.Native) && api.NestedRejected, "reentrant callback cannot read another field")

    api.Reset()
    first := EacUiaFieldProvider.Read(api.Native)
    second := EacUiaFieldProvider.Read(api.Native)
    Assert(EacFieldGuard.SameTarget(first, second) && EacFieldGuard.SamePosition(first, second), "same field and caret match")
    second.Identity := "UIA:42:2"
    Assert(!EacFieldGuard.SameTarget(first, second) && !EacFieldGuard.SamePosition(first, second), "same HWND different runtime field is rejected")
    second.Identity := first.Identity, second.Selection.Start += 1
    Assert(EacFieldGuard.SameTarget(first, second) && !EacFieldGuard.SamePosition(first, second), "same field moved caret is rejected")
    second.Selection.Start := first.Selection.Start, api.Failure := "Compare"
    Assert(!EacFieldGuard.SamePosition(first, second) && !api.Deadline, "position comparison RPC failure fails closed")
    Assert(!EacFieldGuard.SameTarget(first, {Position: first.Position}), "UIA and native providers never match")

    api.Reset()
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(EacUiaFieldProvider.IsFocused(field, api.Native) && !api.Deadline, "final focus verifier accepts same field")
    api.CurrentElement := {Id: "UIA:42:2"}
    Assert(!EacUiaFieldProvider.IsFocused(field, api.Native) && !api.Deadline, "final focus verifier rejects same HWND different field")
    api.CurrentElement := api.Element, api.LoseFieldFocus := true
    Assert(!EacUiaFieldProvider.IsFocused(field, api.Native), "final focus verifier rejects unfocused field")
    api.LoseFieldFocus := false, api.CurrentNative := {Key: "other"}
    Assert(!EacUiaFieldProvider.IsFocused(field, api.Native), "final focus verifier rejects changed native target")
    api.CurrentNative := api.Native, api.Failure := "Focus"
    Assert(!EacUiaFieldProvider.IsFocused(field, api.Native) && !api.Deadline, "final focus verifier RPC failure fails closed")
}

TestStructuralRead() {
    api := UiaTestApi
    api.Reset(), api.StaleDocument := true, api.RefreshDocument := true
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && api.DocumentCalls = 2 && !api.RangeChecks && !api.ValueCalls, "fresh bounds after selection restore normal path")

    StructuralFixture()
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "alpha confi" && field.After == "!", "descendant-owned caret uses confined input neighborhood")
    Assert(EacUiaFieldProvider.BoundsFlags = 24, "selection and document owners are input descendants")
    Assert(api.RejectedTrials > 0 && api.OutsideTextCalls = 0, "binary search rejects outside trials before any GetText")
    Assert(!api.ValueCalls, "nonempty right character needs no input Value")
    Assert(api.RangeChecks > 4 && api.DocumentCalls = 2, "production ConfinedRange searches after bounds retry")
    for range in api.ReadRanges
        Assert(api.PhysicallyWithin(range), "every text read stays in focused Edit")

    StructuralFixture(), api.DocumentReadOnly := true
    Assert(EacUiaFieldProvider.Read(api.Native) && !api.DocumentReadOnlyCalls, "structural path does not trust unrelated document readonly")
    StructuralFixture(), api.Props[30046] := true
    Rejected("structural input Value is readonly", "UIAReadOnlyOrRange", true)
    Assert(!api.ValueCalls, "readonly input does not read Value")
    StructuralFixture(), api.UnknownProperty := 30046
    Rejected("structural input readonly property unknown", "UIAUnavailable", true)
    StructuralFixture(), api.Failure := "RangeWithin"
    Rejected("structural containment unavailable", "UIAUnavailable", true)
    StructuralFixture(), api.Caret := api.FieldEnd() + 1
    Rejected("caret belongs to another element", "TextChanged", true)
    StructuralFixture(), api.LeftReadOnly := true
    Rejected("confined left range readonly", "UIARange", true)
    StructuralFixture(), api.LoseContainmentAfterRead := true
    Rejected("input ownership changes after reads", "TextChanged")
    Assert(!api.OutsideTextCalls, "ownership recheck does not expose outside text")

    StructuralFixture(), api.Caret := api.FieldEnd()
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "alpha confi!" && field.After == "", "actual EOF confirmed by complete input Value")
    Assert(api.ValueCalls = 2 && api.TextCalls = 5, "EOF proof reads confined full prefix and rechecks Value")
    Assert(api.RejectedTrials > 0 && !api.OutsideTextCalls, "EOF proof never reads surrounding page text")
    fullPrefix := api.ReadRanges[3]
    Assert(fullPrefix.Start = api.FieldStart && fullPrefix.End = api.FieldEnd(), "EOF proof covers exactly focused input")

    StructuralFixture(""), api.Caret := api.FieldStart
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "" && field.After == "" && api.ValueCalls = 2, "empty Edit EOF is proven without page text")
    Assert(!api.OutsideTextCalls, "empty Edit never reads neighboring page")

    StructuralFixture(), api.UnitSize := 200
    Rejected("empty clipped right range in middle is not EOF", "UIARange")
    Assert(api.ValueCalls = 1 && !api.OutsideTextCalls, "false EOF fails input Value proof before revalidation")
    StructuralFixture(), api.Caret := api.FieldEnd(), api.HasValueOverride := true, api.ValueText := "another input"
    Rejected("EOF Value does not match confined prefix", "UIARange")
    StructuralFixture(), api.Caret := api.FieldEnd(), api.ChangeValueCall := 2
    Rejected("input Value changes after EOF proof", "TextChanged")
    Assert(api.ValueCalls = 2 && !api.OutsideTextCalls, "EOF Value is revalidated without escaping input")
    StructuralFixture(), api.Caret := api.FieldEnd(), api.EofReadOnly := true
    Rejected("EOF proof range readonly", "UIARange")
    StructuralFixture(), api.Caret := api.FieldEnd(), api.Failure := "Value"
    Rejected("EOF Value unavailable", "UIAUnavailable")

    StructuralFixture(Repeat("x", 200)), api.Caret := api.FieldEnd()
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && StrLen(field.Before) = 128 && api.ReadRanges[3].End - api.ReadRanges[3].Start = 200,
        "long EOF proof may read only the complete focused Edit")
    Assert(!api.OutsideTextCalls && api.ValueCalls = 2, "long EOF proof remains within input")
}

StructuralFixture(value := "alpha confi!") {
    api := UiaTestApi
    api.Reset()
    prefix := "private page prefix ", suffix := " private page suffix"
    api.Content := prefix value suffix
    api.FieldStart := StrLen(prefix), api.FieldEndOverride := StrLen(prefix) + StrLen(value)
    api.Caret := api.FieldStart + Min(11, StrLen(value))
    api.StaleDocument := true
}

Rejected(description, reason, beforeText := false) {
    api := UiaTestApi
    Assert(!EacUiaFieldProvider.Read(api.Native), description " rejected")
    Assert(EacFieldGuard.LastReason = reason, description " rejection reason")
    if beforeText {
        Assert(api.TextCalls = 0, description " reads no text")
        Assert(api.ValueCalls = 0, description " reads no input Value")
    }
    Assert(api.OutsideTextCalls = 0, description " never reads outside Edit")
    Assert(!api.Deadline && !EacUiaFieldProvider.Busy, description " clears lease")
}

TestComHelpers() {
    ; Exercise production COM marshalling with owned in-process IUnknown stubs.
    fixture := UiaComStub("values")
    object := fixture.Object()
    Assert(EacUia.Property(object, 30019, 11) = false && fixture.LastId = 30019 && fixture.IgnoreDefault, "BOOL property uses ignoreDefault")
    fixture.BoolValue := -1
    Assert(EacUia.Property(object, 30019, 11), "VARIANT_TRUE decoded")
    fixture.VarType := 3, fixture.IntValue := 50004
    Assert(EacUia.Property(object, 30003, 3) = 50004, "control type INT decoded")
    AssertThrows(() => EacUia.Property(object, 30019, 11), "wrong property variant type")
    fixture.VarType := 0
    AssertThrows(() => EacUia.Property(object, 30019, 11), "empty property unsupported")
    fixture.VarType := 10
    AssertThrows(() => EacUia.Property(object, 30019, 11), "error property unsupported")
    fixture.VarType := 11, fixture.HResult := -2147467259
    AssertThrows(() => EacUia.Property(object, 30019, 11), "failed property HRESULT")
    fixture.HResult := 0, fixture.BoolValue := 0
    Assert(!EacUia.ReadOnly(object) && fixture.LastId = 40015, "readonly attribute ID and editable false")
    fixture.BoolValue := -1
    Assert(EacUia.ReadOnly(object), "readonly attribute true")
    fixture.VarType := 0
    AssertThrows(() => EacUia.ReadOnly(object), "unsupported readonly attribute fails closed")
    fixture.VarType := 11, fixture.HResult := -2147467259
    AssertThrows(() => EacUia.ReadOnly(object), "readonly RPC failure")
    fixture.HResult := 0, fixture.NullText := true
    Assert(EacUia.Text(object, 2) == "", "NULL BSTR is legal empty text")
    fixture.NullText := false, fixture.Value := "α🙂B"
    Assert(EacUia.Text(object, 4) == fixture.Value, "BSTR UTF16 text decoded")
    AssertThrows(() => EacUia.Text(object, 2), "oversized BSTR rejected")
    fixture.Value := "abc", fixture.HResult := -2147467259
    AssertThrows(() => EacUia.Text(object, 3), "text RPC failure rejects even returned BSTR")
    fixture.HResult := 0, fixture.VarType := 8, fixture.Value := "α🙂B"
    Assert(EacUia.Value(object) == fixture.Value && fixture.LastId = 30045 && fixture.IgnoreDefault, "input Value requires BSTR property with ignoreDefault")
    fixture.Value := Repeat("x", 32767)
    Assert(StrLen(EacUia.Value(object)) = 32767, "input Value permits bounded 32767 UTF16 units")
    fixture.Value .= "x"
    AssertThrows(() => EacUia.Value(object), "input Value rejects 32768 UTF16 units")
    fixture.NullText := true
    Assert(EacUia.Value(object) == "", "input Value permits NULL empty BSTR")
    fixture.NullText := false, fixture.VarType := 11
    AssertThrows(() => EacUia.Value(object), "input Value rejects BOOL variant")
    fixture.VarType := 0
    AssertThrows(() => EacUia.Value(object), "input Value rejects unsupported property")
    fixture.VarType := 8, fixture.Value := "abc", fixture.HResult := -2147467259
    AssertThrows(() => EacUia.Value(object), "input Value rejects failed HRESULT with BSTR")
    fixture.HResult := 0, fixture.ExpireDeadline := true
    AssertThrows(() => EacUia.Value(object), "input Value deadline checked after COM call")
    EacUia.Deadline := 0, fixture.ExpireDeadline := false, fixture.VarType := 11
    fixture.HResult := 0, fixture.IdentityValues := [42, 7, 9]
    Assert(EacUia.Identity(object) == "UIA:42:7:9", "SAFEARRAY runtime identity decoded")
    fixture.IdentityValues := []
    AssertThrows(() => EacUia.Identity(object), "empty runtime identity rejected")
    fixture.IdentityValues := []
    Loop 33
        fixture.IdentityValues.Push(A_Index)
    AssertThrows(() => EacUia.Identity(object), "oversized runtime identity rejected")
    fixture.HResult := -2147467259
    AssertThrows(() => EacUia.Out(object, 5), "failed interface result")
    fixture.HResult := 0, fixture.NullInterface := true
    AssertThrows(() => EacUia.Out(object, 5), "NULL interface rejected")
    fixture.NullInterface := false
    returned := EacUia.Out(object, 5)
    Assert(ComObjValue(returned) = fixture.Instance.Ptr, "interface pointer wrapped")
    returned := false
    fixture.ExpireDeadline := true
    AssertThrows(() => EacUia.Text(object, 3), "deadline expiring during COM call rejects result")
    EacUia.Deadline := 0, fixture.ExpireDeadline := false
    EacUia.Deadline := A_TickCount - 1
    AssertThrows(() => EacUia.Text(object, 3), "expired deadline rejects COM access")
    EacUia.Deadline := 0
    object := false
    Assert(fixture.References = 1, "all interface references released")
}

class UiaTestApi extends EacUia {
    static Reset() {
        this.Deadline := 0, this.Failure := "", this.BeginCalls := 0
        this.FocusCalls := 0, this.TextCalls := 0, this.SelectionCalls := 0, this.CloneCalls := 0
        this.DocumentCalls := 0, this.RangeChecks := 0, this.ValueCalls := 0, this.OutsideTextCalls := 0
        this.RejectedTrials := 0, this.DocumentReadOnlyCalls := 0, this.ReadRanges := []
        this.TextLimits := "", this.Moves := "", this.Events := "", this.ChangeTextCall := 0
        this.Content := "alpha confi!", this.Caret := 11, this.UnitSize := 1
        this.FieldStart := 0, this.FieldEndOverride := -1, this.StaleDocument := false, this.RefreshDocument := false
        this.LoseContainmentAfterRead := false, this.EofReadOnly := false
        this.HasValueOverride := false, this.ValueText := "", this.ChangeValueCall := 0
        this.Native := {Hwnd: 7, Focus: 8, Key: "7:8"}, this.CurrentNative := this.Native
        this.Element := {Id: "UIA:42:1"}, this.CurrentElement := this.Element
        this.ClientValue := {}, this.PatternValue := {}
        this.Props := Map(30003, 50004, 30008, true, 30009, true, 30010, true, 30019, false, 30022, false, 30046, false)
        this.UnknownProperty := 0, this.Ancestor := true, this.SelectionCount := 1
        this.SelectionLength := 0, this.VerifiedSelectionLength := 0, this.CaretShift := 0
        this.DocumentReadOnly := false, this.SelectionReadOnly := false
        this.LeftReadOnly := false, this.RightReadOnly := false, this.UnknownReadOnly := false
        this.BadLeftEnd := false, this.BadRightStart := false, this.NoAnchor := false
        this.Reenter := false, this.NestedRejected := false
        this.LoseFieldFocus := false
        this.Array := UiaComStub("array", this)
    }
    static FailAt(stage) {
        if this.Failure = stage
            throw Error("mock RPC " stage)
    }
    static Begin() {
        this.BeginCalls += 1
        this.Deadline := A_TickCount + 200
    }
    static Client() {
        this.FailAt("Client")
        return this.ClientValue
    }
    static Out(object, slot, args*) {
        if object = this.ClientValue && slot = 8 {
            this.FailAt("Focus"), this.FocusCalls += 1
            this.Events .= "Focus,"
            return this.FocusCalls = 1 ? this.Element : this.CurrentElement
        }
        if object = this.PatternValue && slot = 7 {
            this.FailAt("Document"), this.DocumentCalls += 1
            stale := this.StaleDocument && !(this.RefreshDocument && this.DocumentCalls > 1)
            return {Start: stale ? 0 : this.FieldStart, End: stale ? 1 : this.FieldEnd(), Kind: "Document"}
        }
        if object = this.PatternValue && slot = 5
            return this.Array.Object()
        if object is ComValue && slot = 4 {
            this.SelectionCalls += 1
            caret := this.Caret + (this.SelectionCalls > 1 ? this.CaretShift : 0)
            length := this.SelectionCalls > 1 ? this.VerifiedSelectionLength : this.SelectionLength
            return {Start: caret, End: caret + length, Kind: "Selection"}
        }
        if slot = 3 {
            this.FailAt("Clone"), this.CloneCalls += 1
            return {Start: object.Start, End: object.End, Kind: object.Kind}
        }
        if slot = 11
            return {Id: "UIA:42:child", Parent: this.Element.Id}
        throw Error("unexpected mock interface slot " slot)
    }
    static Property(element, id, type) {
        if id = this.UnknownProperty
            throw Error("mock unsupported property")
        if id = 30008 {
            this.Events .= "PropertyFocus,"
            if this.LoseFieldFocus && this.FocusCalls > 1
                return false
        }
        return this.Props[id]
    }
    static AncestorMatches(*) => this.Ancestor
    static Identity(element) {
        this.FailAt("Identity")
        return element.Id
    }
    static Pattern(*) {
        this.FailAt("Pattern")
        return this.PatternValue
    }
    ; Inherit production Selection(): real COM count + collapse validation.
    static Compare(a, endpoint, b, otherEndpoint) {
        this.FailAt("Compare")
        return (endpoint ? a.End : a.Start) - (otherEndpoint ? b.End : b.Start)
    }
    static ReadOnly(range) {
        this.FailAt("ReadOnly")
        if this.UnknownReadOnly
            throw Error("mock unknown readonly attribute")
        if range.Kind = "Document"
            this.DocumentReadOnlyCalls += 1
        if this.EofReadOnly && this.ValueCalls && range.Kind = "Left"
            return true
        return this.%range.Kind "ReadOnly"%
    }
    static Move(range, endpoint, count) {
        this.FailAt("Move")
        range.Kind := endpoint ? "Right" : "Left"
        this.Moves .= endpoint ":" count ","
        if endpoint
            range.End := Min(StrLen(this.Content), range.End + count * this.UnitSize)
        else
            range.Start := Max(0, range.Start + count * this.UnitSize)
        if this.BadLeftEnd && range.Kind = "Left"
            range.End += 1
        if this.BadRightStart && range.Kind = "Right"
            range.Start -= 1
    }
    static Clamp(range, document) {
        this.FailAt("Clamp")
        range.Start := Max(range.Start, document.Start), range.End := Min(range.End, document.End)
    }
    static Text(range, limit) {
        this.FailAt("Text"), this.TextCalls += 1
        this.ReadRanges.Push({Start: range.Start, End: range.End})
        if !this.PhysicallyWithin(range) {
            this.OutsideTextCalls += 1
            throw Error("test observed GetText outside focused Edit")
        }
        this.Events .= "Text,"
        this.TextLimits .= limit ","
        if this.Reenter && this.TextCalls = 1 {
            nested := EacUiaFieldProvider.Read(this.Native)
            this.NestedRejected := !nested && EacFieldGuard.LastReason = "TextChanged"
        }
        text := SubStr(this.Content, range.Start + 1, range.End - range.Start)
        if this.TextCalls = this.ChangeTextCall
            text := text = "!" ? "?" : "changed"
        return SubStr(text, 1, limit)
    }
    static FieldEnd() => this.FieldEndOverride >= 0 ? this.FieldEndOverride : StrLen(this.Content)
    static PhysicallyWithin(range) => range.Start >= this.FieldStart && range.End <= this.FieldEnd()
    static RangeWithin(range, element) {
        this.FailAt("RangeWithin"), this.RangeChecks += 1
        contained := this.PhysicallyWithin(range) && !(this.LoseContainmentAfterRead && this.TextCalls >= 4)
        if !contained
            this.RejectedTrials += 1
        return contained
    }
    static ElementWithin(element, parent) => element.Id == parent.Id || (element.HasOwnProp("Parent") && element.Parent == parent.Id)
    ; Inherit production ConfinedRange(): only the independent offset and
    ; enclosing-element observations above are supplied by this backend.
    static Value(element) {
        this.FailAt("Value"), this.ValueCalls += 1
        this.Events .= "Value,"
        value := this.HasValueOverride ? this.ValueText : SubStr(this.Content, this.FieldStart + 1, this.FieldEnd() - this.FieldStart)
        return this.ValueCalls = this.ChangeValueCall ? value "changed" : value
    }
    static Anchor(*) {
        this.FailAt("Anchor")
        return this.NoAnchor ? false : {Found: true, X: 10, Y: 20, Method: "MockCaret"}
    }
    static Context() {
        this.FailAt("Context")
        this.Events .= "Context,"
        return this.CurrentNative
    }
    static Same(a, b) => a.Id == b.Id
}

class UiaComStub {
    References := 1
    HResult := 0
    VarType := 11
    BoolValue := 0
    IntValue := 0
    LastId := 0
    IgnoreDefault := false
    NullText := false
    Value := ""
    NullInterface := false
    ExpireDeadline := false
    IdentityValues := []
    __New(kind, owner := false) {
        this.Owner := owner, this.Callbacks := []
        this.Vtable := Buffer(13 * A_PtrSize, 0), this.Instance := Buffer(A_PtrSize, 0)
        NumPut "Ptr", this.Vtable.Ptr, this.Instance
        this.SetSlot(0, "Query", 3), this.SetSlot(1, "AddRef", 1), this.SetSlot(2, "Release", 1)
        if kind = "array"
            this.SetSlot(3, "Count", 2)
        else {
            this.SetSlot(4, "RuntimeId", 2), this.SetSlot(5, "Interface", 2)
            this.SetSlot(9, "Attribute", 3), this.SetSlot(11, "Property", 4), this.SetSlot(12, "Text", 3)
        }
    }
    SetSlot(slot, method, count) {
        callback := CallbackCreate(ObjBindMethod(this, method), "", count)
        this.Callbacks.Push(callback)
        NumPut "Ptr", callback, this.Vtable, slot * A_PtrSize
    }
    Object() {
        this.References += 1
        return ComValue(13, this.Instance.Ptr, 1)
    }
    Query(pointer, iid, output) {
        NumPut "Ptr", 0, output
        return -2147467262
    }
    AddRef(*) => ++this.References
    Release(*) => --this.References
    Count(pointer, output) {
        NumPut "Int", this.Owner.SelectionCount, output
        return 0
    }
    Variant(id, output) {
        this.LastId := id
        NumPut "UShort", this.VarType, output
        if this.VarType = 8 {
            bstr := this.NullText ? 0 : DllCall("oleaut32\SysAllocStringLen", "Ptr", StrPtr(this.Value), "UInt", StrLen(this.Value), "Ptr")
            NumPut "Ptr", bstr, output, 8
        } else
            NumPut "Int", this.VarType = 11 ? this.BoolValue : this.IntValue, output, 8
        if this.ExpireDeadline
            EacUia.Deadline := A_TickCount - 1
        return this.HResult
    }
    Property(pointer, id, ignoreDefault, output) {
        this.IgnoreDefault := !!ignoreDefault
        return this.Variant(id, output)
    }
    Attribute(pointer, id, output) => this.Variant(id, output)
    Text(pointer, limit, output) {
        ; Intentionally ignore the limit to test a misbehaving provider too.
        bstr := this.NullText ? 0 : DllCall("oleaut32\SysAllocStringLen", "Ptr", StrPtr(this.Value), "UInt", StrLen(this.Value), "Ptr")
        NumPut "Ptr", bstr, output
        if this.ExpireDeadline
            EacUia.Deadline := A_TickCount - 1
        return this.HResult
    }
    RuntimeId(pointer, output) {
        array := DllCall("oleaut32\SafeArrayCreateVector", "UShort", 3, "Int", 0, "UInt", this.IdentityValues.Length, "Ptr")
        for value in this.IdentityValues {
            index := A_Index - 1
            DllCall "oleaut32\SafeArrayPutElement", "Ptr", array, "Int*", index, "Int*", value
        }
        NumPut "Ptr", array, output
        return this.HResult
    }
    Interface(pointer, output) {
        if !this.NullInterface
            this.References += 1
        NumPut "Ptr", this.NullInterface ? 0 : this.Instance.Ptr, output
        return this.HResult
    }
    ; Callbacks retain their bound owner until process exit. These short-lived
    ; fixtures own no OS handles and never expose their pointers externally.
}

Repeat(value, count) {
    result := ""
    Loop count
        result .= value
    return result
}

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}

AssertThrows(action, description) {
    threw := false
    try action.Call()
    catch
        threw := true
    Assert(threw, description)
}

Fail(e, *) {
    FileAppend "FAIL " e.Message " at " e.Line "`n" e.Stack "`n", "*"
    ExitApp 1
}
