#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

; No external UIA client, visible GUI, focus change, or input is created.
; The backend models character offsets independently of provider control flow.
Checks := 0
OnError Fail
EacUiaFieldProvider.Api := UiaTestApi
try {
    TestRead()
    TestStructuralRead()
    TestComboRead()
    TestDocumentRead()
    TestExcelFocus()
    TestActiveCaret()
    TestFieldAnchor()
    TestAccessibilityProxy()
    TestMsaaAnchor()
    TestDispatch()
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

    api.Reset(), api.Props[30003] := 50030, api.DocumentReadOnly := true
    Rejected("readonly document viewer is not an input", "UIAReadOnlyOrRange", true)
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

    for pair in [[30003, 50020], [30008, false], [30009, false], [30010, false], [30019, true]] {
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

TestComboRead() {
    api := UiaTestApi
    api.Reset(), api.Props[30003] := 50003
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "alpha confi" && field.After == "!", "editable ComboBox reads bounded caret neighborhood")
    Assert(api.RangeChecks > 3 && !api.OutsideTextCalls && !api.ValueCalls, "ComboBox always confines ranges to input before reading")
    Assert(EacUiaFieldProvider.IsFocused(field, api.Native), "editable ComboBox keepalive")
    api.Props[30046] := true
    Assert(!EacUiaFieldProvider.IsFocused(field, api.Native), "ComboBox becoming list-only loses keepalive")
    api.Reset(), api.Props[30003] := 50003, api.Caret := StrLen(api.Content)
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.After == "" && api.ValueCalls = 2, "ComboBox EOF proven against same input Value")
    StructuralFixture(), api.Props[30003] := 50003
    Assert(EacUiaFieldProvider.Read(api.Native) && !api.OutsideTextCalls, "ComboBox with page-relative document bounds stays inside field")
    api.Reset(), api.Props[30003] := 50003, api.Props[30046] := true
    Rejected("list-only ComboBox", "UIAReadOnlyOrRange", true)
    api.Reset(), api.Props[30003] := 50003, api.UnknownProperty := 30046
    Rejected("ComboBox unknown editability", "UIAUnavailable", true)
    api.Reset(), api.Props[30003] := 50003, api.Props[30019] := true
    Rejected("password ComboBox", "UIAUnsafeField", true)
    api.Reset(), api.Props[30003] := 50003, api.SelectionLength := 1
    Rejected("ComboBox selected text", "UIAUnavailable", true)
    api.Reset(), api.Props[30003] := 50003, api.SelectionReadOnly := true
    Rejected("ComboBox readonly text range", "UIAReadOnlyOrRange", true)
    api.Reset(), api.Props[30003] := 50003, api.FinalReadOnly := true
    Rejected("ComboBox becomes readonly during read", "FocusChanged")
    api.Reset(), api.Props[30003] := 50003, api.FinalType := 50030
    Rejected("ComboBox becomes document during read", "FocusChanged")
}

TestDocumentRead() {
    api := UiaTestApi
    api.Reset(), api.Props[30003] := 50030, api.UnknownProperty := 30046
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "alpha confi" && field.After == "!", "writable focused Document exposes local editing context")
    Assert(!api.ValueCalls && api.TextLimits = "129,2,129,2,", "Document needs no ValuePattern or full document text")
    Assert(api.RangeChecks >= 7 && api.DocumentReadOnlyCalls = 2, "Document containment and editability rechecked")
    Assert(EacUiaFieldProvider.IsFocused(field, api.Native), "editable Document focus keepalive")
    for pair in [["DocumentReadOnly", "UIAReadOnlyOrRange"], ["SelectionReadOnly", "UIAReadOnlyOrRange"],
        ["LeftReadOnly", "UIARange"], ["RightReadOnly", "UIARange"], ["UnknownReadOnly", "UIAUnavailable"]] {
        api.Reset(), api.Props[30003] := 50030, api.%pair[1]% := true
        Rejected("Document " pair[1], pair[2], true)
    }
    api.Reset(), api.Props[30003] := 50030, api.SelectionLength := 1
    Rejected("Document selected text", "UIAUnavailable", true)
    api.Reset(), api.Props[30003] := 50030, api.NoAnchor := true
    Rejected("Document unknown caret rectangle", "UIACaretUnavailable")
    api.Reset(), api.Props[30003] := 50030, api.Props[30019] := true
    Rejected("password Document", "UIAUnsafeField", true)
    StructuralFixture(), api.Props[30003] := 50030
    Rejected("Document cannot borrow Edit full Value fallback for inconsistent bounds", "UIAReadOnlyOrRange", true)
    api.Reset(), api.Props[30003] := 50030, api.LoseContainmentAfterRead := true
    Rejected("Document owner changes after read", "TextChanged")
    api.Reset(), api.Props[30003] := 50030, api.FinalRangeReadOnly := true
    Rejected("Document becomes protected during read", "TextChanged")
    api.Reset(), api.Props[30003] := 50030, api.Content := Repeat("x", 40000) " confi!", api.Caret := 40006
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && StrLen(field.Before) = 128 && field.After == "!" && !api.ValueCalls,
        "large Document keeps bounded local read and no native Edit length limit")
    api.Reset(), api.Props[30003] := 50030, api.Caret := StrLen(api.Content)
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.After == "" && field.EofLength = -1 && !api.ValueCalls, "Document EOF uses valid document bounds without full text")
    api.Reset(), api.Props[30003] := 50030, api.Content := "", api.Caret := 0
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Before == "" && field.After == "" && !api.ValueCalls, "empty writable Document accepted")
}

TestExcelFocus() {
    api := ExcelFocusApi
    api.Reset()
    Assert(api.FocusedElement(api.Native) = api.Children[1], "Excel legacy Pane resolves one raw focused Edit")
    Assert(api.FocusCalls = 2 && api.SiblingCalls = 1, "Excel focus rechecked after complete bounded raw child scan")
    api.Reset(), api.Excel := false
    Assert(api.FocusedElement(api.Native) = api.Pane && !api.FormulaCalls, "other applications never use Excel proxy resolution")
    api.Reset(), api.Pane.Type := 50004
    Assert(api.FocusedElement(api.Native) = api.Pane && !api.FormulaCalls, "normal focused Edit retains ordinary route")
    for pair in [["Type",50030],["Offscreen",true],["Enabled",false],["Password",true]] {
        api.Reset(), api.Root.%pair[1]% := pair[2]
        AssertThrows(() => api.FocusedElement(api.Native), "unsafe formula root " pair[1] " rejected")
        Assert(!api.SiblingCalls, "unsafe formula root never reads children")
    }
    api.Reset(), api.Children := []
    AssertThrows(() => api.FocusedElement(api.Native), "missing raw editor rejected")
    api.Reset(), api.Children[1].Focus := false
    AssertThrows(() => api.FocusedElement(api.Native), "unfocused raw editor rejected")
    api.Reset(), api.Children[1].Type := 50030
    AssertThrows(() => api.FocusedElement(api.Native), "focused non-Edit raw child rejected")
    api.Reset(), api.Children.Push({Id:4,Type:50004,Focus:true})
    AssertThrows(() => api.FocusedElement(api.Native), "two focused Edit children rejected")
    api.Reset(), api.ParentChanged := true
    AssertThrows(() => api.FocusedElement(api.Native), "raw editor reparented during search rejected")
    api.Reset(), api.FocusChanged := true
    AssertThrows(() => api.FocusedElement(api.Native), "UIA legacy focus changes during resolution rejected")
    api.Reset(), api.NativeChanged := true
    AssertThrows(() => api.FocusedElement(api.Native), "native focus changes during resolution rejected")
    api.Reset(), api.EndHresult := -2146233083
    AssertThrows(() => api.FocusedElement(api.Native), "RPC failure is never mistaken for end of siblings")
    api.Reset()
    Loop 8
        api.Children.Push({Id:A_Index+4,Type:50004,Focus:false})
    AssertThrows(() => api.FocusedElement(api.Native), "more than eight raw children rejected")
    Assert(api.SiblingCalls = 8, "raw child traversal bounded independently of workbook size")
    api.Reset(), api.Children[1].Focus := false, api.CellChildren := [{Id:6, Type:50004, Focus:true}]
    editor := api.FocusedElement(api.Native)
    Assert(editor = api.CellChildren[1], "unfocused formula child resolves focused editor of addressed cell")
    Assert(api.FocusedElement(api.Native, editor) = editor && api.CellCalls = 1,
        "same cell is revalidated without another point lookup")
    api.CellChildren := [{Id:7, Type:50004, Focus:true}]
    AssertThrows(() => api.FocusedElement(api.Native, editor), "replacement cell editor invalidates selection")
    api.Reset(), api.CellChildren := [{Id:6, Type:50004, Focus:true},{Id:7, Type:50004, Focus:true}]
    AssertThrows(() => api.ExcelFocusedChild(api.Walker, api.Cell), "two focused editors in addressed cell rejected")
    row := {Index:23, Sheet:42, Grid:api.Grid}, col := {Index:9, Sheet:42, Grid:api.Grid}
    Assert(api.ExcelCellAt(api.Walker, row, col) = api.Cell && api.Address = "23:9", "single grid lookup uses observed row and column")
    col.Index := -1
    AssertThrows(() => api.ExcelCellAt(api.Walker, row, col), "negative grid index rejected")
    col.Index := 9, col.Sheet := 43
    AssertThrows(() => api.ExcelCellAt(api.Walker, row, col), "cross-sheet coordinates rejected")
    col.Sheet := 42, col.Grid := {Id:88}
    AssertThrows(() => api.ExcelCellAt(api.Walker, row, col), "different UIA grids rejected")
    col.Grid := api.Grid, api.ParentChanged := true
    AssertThrows(() => api.ExcelCellAt(api.Walker, row, col), "returned cell must belong to addressed grid")
}

TestActiveCaret() {
    api := UiaTestApi
    api.Reset(), api.NoAnchor := true, api.ActiveAvailable := true
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Anchor.Method = "MockCaret", "TextPattern2 active caret supplies missing selection rectangle")
    Assert(api.ActiveCalls = 1 && api.ActiveAnchorCalls = 1 && api.TextCalls = 4, "active caret fallback adds no text reads")
    for pair in [["CaretActive", false], ["ActiveShift", 1], ["CaretReadOnly", true], ["ActiveHasAnchor", false]] {
        api.Reset(), api.NoAnchor := true, api.ActiveAvailable := true, api.%pair[1]% := pair[2]
        Rejected("active caret " pair[1], "UIACaretUnavailable")
    }
    api.Reset(), api.NoAnchor := true, api.ActiveAvailable := true, api.ActiveShift := -20
    Rejected("active caret belongs to another range", "UIACaretUnavailable")
    api.Reset(), api.NoAnchor := true, api.ActiveAvailable := true, api.Failure := "RangeWithin"
    Rejected("active caret ownership unavailable", "UIACaretUnavailable")
    api.Reset(), api.ActiveAvailable := true
    Assert(EacUiaFieldProvider.Read(api.Native) && !api.ActiveCalls, "working selection rectangle avoids extra pattern lookup")
}

TestFieldAnchor() {
    api := UiaTestApi
    api.Reset(), api.NoAnchor := true, api.FieldRect := [10,20,200,25]
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.Anchor.Method = "UIAField" && field.Anchor.X = 10 && field.Anchor.Top = 20
        && field.Anchor.Bottom = 45 && field.Anchor.Y = 45, "missing caret rectangle falls back to actual focused field bounds")
    Assert(api.TextCalls = 4 && api.SelectionCalls = 2, "field placement retains logical caret and text revalidation")
    api.Reset(), api.NoAnchor := true, api.FieldRect := [10,20,200,25], api.Props[30003] := 50003
    Assert(EacUiaFieldProvider.Read(api.Native), "editable ComboBox can use field placement")
    for rect in [[-1,20,200,25],[10,-10000,200,25],[10,20,1000,25],[10,20,200,1000],[10,20,0,25],[10,20,200,0]] {
        api.Reset(), api.NoAnchor := true, api.FieldRect := rect
        Rejected("outside or empty field rectangle", "UIACaretUnavailable")
    }
    api.Reset(), api.NoAnchor := true, api.FieldRect := [10,20,200,25], api.Props[30003] := 50030
    Rejected("whole Document is not a field position fallback", "UIACaretUnavailable")
    api.Reset(), api.NoAnchor := true, api.FieldRect := [10,20,200,25], api.SelectionLength := 1
    Rejected("field rectangle never bypasses selected text", "UIAUnavailable", true)
    api.Reset(), api.NoAnchor := true, api.FieldRect := [10,20,200,25], api.Props[30022] := true
    Rejected("hidden editor never uses visible field fallback", "UIACaretUnavailable", true)
}

TestAccessibilityProxy() {
    api := UiaTestApi
    api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true
    field := EacUiaFieldProvider.Read(api.Native)
    Assert(field && field.AccessibilityProxy && field.Anchor.Method = "MSAACaret", "hidden accessibility Edit requires focus-owned visible MSAA caret")
    Assert(api.ProxyCalls = 2 && api.TextCalls = 4, "proxy caret checked before and after bounded text reads")
    Assert(EacUiaFieldProvider.IsFocused(field, api.Native), "verified proxy focus keepalive")
    Assert(api.ProxyCalls = 2, "proxy navigation keepalive performs no physical caret RPC")
    api.ProxyAvailable := false
    Assert(EacUiaFieldProvider.IsFocused(field, api.Native), "transient physical caret loss does not pass a navigation Tab into document")
    Rejected("fresh proxy snapshot still refuses missing physical caret before insertion", "UIACaretUnavailable")
    for pair in [[30003,50003],[30019,true]] {
        api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true, api.Props[pair[1]] := pair[2]
        Rejected("unsafe hidden proxy", "UIAUnsafeField", true)
    }
    api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true, api.Props[30046] := true
    Rejected("readonly hidden proxy", "UIAReadOnlyOrRange", true)
    api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true, api.UnknownProperty := 30046
    Rejected("unknown hidden proxy editability", "UIAUnavailable", true)
    api.Reset(), api.Props[30022] := true
    Rejected("hidden proxy without visible native caret", "UIACaretUnavailable", true)
    api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true, api.SelectionLength := 1
    Rejected("hidden proxy selected text", "UIAUnavailable", true)
    api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true, api.SelectionReadOnly := true
    Rejected("hidden proxy readonly caret", "UIAReadOnlyOrRange", true)
    api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true, api.ProxyGoneAfterRead := true
    Rejected("proxy loses physical caret during read", "UIACaretUnavailable")
    api.Reset(), api.Props[30022] := true, api.ProxyAvailable := true, api.FinalReadOnly := true
    Rejected("proxy becomes readonly before focus recheck", "FocusChanged")
    api.Reset(), api.FinalOffscreen := true
    Rejected("normal field becomes hidden during read", "FocusChanged")
}

TestMsaaAnchor() {
    api := MsaaTestApi
    context := {Hwnd: 7, Focus: 8}
    api.Reset()
    anchor := api.MsaaAnchor(context)
    Assert(anchor && anchor.X = 20 && anchor.Top = 30 && anchor.Bottom = 55 && anchor.Method = "MSAACaret", "system caret physical rectangle retained")
    for pair in [["Owner",9],["Role",42],["State",1],["State",0x8000],["State",0x10000],["State",0x20000000]] {
        api.Reset(), api.%pair[1]% := pair[2]
        Assert(!api.MsaaAnchor(context), "wrong-owner or unsafe system caret rejected")
    }
    for rect in [[20,-10000,1,25],[-1,30,1,25],[999,30,2,25],[20,999,1,25],[20,30,-1,25],[20,30,1,0]] {
        api.Reset(), api.Rect := rect
        Assert(!api.MsaaAnchor(context), "non-visible or empty system caret rejected")
    }
    api.Reset(), api.Fail := true
    Assert(!api.MsaaAnchor(context), "unavailable caret fails closed")
}

TestDispatch() {
    ; Actual HWND/class dispatch with a deterministic UIA backend. This proves
    ; the entry route, not a real application's UIA implementation or input.
    fixture := Gui("+ToolWindow -Caption")
    try {
        control := fixture.AddText(, "dispatch fixture")
        api := UiaTestApi
        api.Reset()
        api.Native := {Hwnd: fixture.Hwnd, Focus: control.Hwnd, Key: fixture.Hwnd ":" control.Hwnd}
        api.CurrentNative := api.Native
        field := EacFieldGuard.Read(api.Native)
        Assert(field && field.Provider = "UIA" && api.FocusCalls = 2, "non-Chromium HWND class reaches guarded UIA provider")
        for options in ["Password", "ReadOnly"] {
            control := fixture.AddEdit(options, "confi")
            api.Reset()
            context := {Hwnd: fixture.Hwnd, Focus: control.Hwnd, Key: fixture.Hwnd ":" control.Hwnd}
            Assert(!EacFieldGuard.Read(context) && !api.BeginCalls, "native " options " refusal never falls through to UIA")
        }
    } finally {
        fixture.Destroy()
    }
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
    fixture.VarType := 0x2005, fixture.RectValues := [10.5,-20.25,200,25]
    rect := EacUia.ElementRectangle(object)
    Assert(rect.Length = 4 && rect[1] = 10.5 && rect[2] = -20.25 && rect[3] = 200 && rect[4] = 25
        && fixture.LastId = 30001 && fixture.IgnoreDefault, "field rectangle SAFEARRAY decoded and default substitution disabled")
    fixture.RectValues := [1,2,3]
    AssertThrows(() => EacUia.ElementRectangle(object), "incomplete field rectangle rejected")
    fixture.VarType := 11
    AssertThrows(() => EacUia.ElementRectangle(object), "unsupported field rectangle rejected")
    fixture.RectValues := [-20.25, -100.5, 1, 25.5]
    anchor := EacUia.Anchor(object, {Hwnd: 1, Focus: 2})
    Assert(anchor && anchor.X = Round(-20.25) && anchor.Top = Round(-100.5)
        && anchor.Bottom = -75 && anchor.Y = anchor.Bottom,
        "UIA physical caret retains both edges without another DPI conversion")
    fixture.RectValues := [0, 0, 1, 0]
    Assert(!EacUia.Anchor(object, {Hwnd: 1, Focus: 2}), "zero-height UIA caret rejected")
    fixture.RectValues := [0, 0, 1]
    Assert(!EacUia.Anchor(object, {Hwnd: 1, Focus: 2}), "incomplete UIA caret rectangle rejected")
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
    rangeStub := UiaComStub("values"), caretStub := UiaComStub("caret", rangeStub)
    rangeStub.SetSlot(5, "EndpointCompare", 5)
    object := caretStub.Object()
    ; CaretRange compares endpoints after the active flag. The endpoint model
    ; is independently tested above; inactive/NULL/failure cover COM ownership.
    caretStub.BoolValue := 0
    AssertThrows(() => EacUia.CaretRange(object), "inactive TextPattern2 caret rejected")
    Assert(rangeStub.References = 1, "inactive caret releases returned interface")
    caretStub.BoolValue := 1
    range := EacUia.CaretRange(object)
    Assert(ComObjValue(range) = rangeStub.Instance.Ptr, "active collapsed TextPattern2 range returned")
    range := false
    Assert(rangeStub.References = 1, "active range releases after use")
    rangeStub.IntValue := 1
    AssertThrows(() => EacUia.CaretRange(object), "noncollapsed TextPattern2 caret rejected")
    rangeStub.IntValue := 0
    caretStub.NullInterface := true
    AssertThrows(() => EacUia.CaretRange(object), "NULL TextPattern2 range rejected")
    caretStub.NullInterface := false, caretStub.HResult := -2147467259
    AssertThrows(() => EacUia.CaretRange(object), "failed TextPattern2 call rejected")
    Assert(rangeStub.References = 1, "failed caret call releases returned interface")
    object := false
    Assert(caretStub.References = 1, "caret pattern interface released")
    msaaStub := UiaComStub("msaa"), object := msaaStub.Object()
    msaaStub.VarType := 3, msaaStub.IntValue := 7
    Assert(EacUia.MsaaInt(object,13) = 7 && msaaStub.ChildType = 3 && msaaStub.ChildId = 0,
        "MSAA role uses by-value CHILDID_SELF VARIANT and typed INT result")
    msaaStub.IntValue := 0
    Assert(EacUia.MsaaInt(object,14) = 0, "MSAA state typed INT result")
    msaaStub.VarType := 11
    AssertThrows(() => EacUia.MsaaInt(object,13), "unsupported MSAA role variant rejected")
    msaaStub.VarType := 3, msaaStub.HResult := -2147467259
    AssertThrows(() => EacUia.MsaaInt(object,14), "MSAA state HRESULT failure rejected")
    msaaStub.HResult := 0, msaaStub.RectValues := [-20,-30,1,25]
    rect := EacUia.MsaaRectangle(object)
    Assert(rect[1] = -20 && rect[2] = -30 && rect[3] = 1 && rect[4] = 25 && msaaStub.ChildType = 3 && msaaStub.ChildId = 0,
        "MSAA accLocation marshals four INT outputs and CHILDID_SELF")
    msaaStub.HResult := -2147467259
    AssertThrows(() => EacUia.MsaaRectangle(object), "MSAA location HRESULT failure rejected")
    object := false
    Assert(msaaStub.References = 1, "MSAA object reference released")
}

class ExcelFocusApi extends EacUia {
    static Reset() {
        this.Native := {Key:"7:8"}, this.Pane := {Id:1,Type:50033,Focus:true}
        this.Root := {Id:2,Type:50004,Offscreen:false,Enabled:true,Password:false}
        this.Children := [{Id:3,Type:50004,Focus:true}]
        this.Grid := {Id:99,Type:50028}, this.Cell := {Id:5,Type:50029}
        this.CellCalls := 0, this.CellChildren := []
        this.Excel := true, this.FormulaCalls := 0, this.FocusCalls := 0, this.SiblingCalls := 0
        this.FocusChanged := false, this.NativeChanged := false, this.ParentChanged := false
        this.EndHresult := 0, this.LastHresult := 0, this.ClientValue := {}, this.Walker := {}
    }
    static Client() => this.ClientValue
    static ExcelCellContext(context) => this.Excel
    static ExcelEditingCell(context,walker) {
        this.CellCalls += 1
        return this.Cell
    }
    static Pattern(element,id,iid) {
        if element = this.Grid && id = 10006
            return this.Grid
        throw Error("unexpected grid pattern")
    }
    static ExcelFormulaElement(context) {
        this.FormulaCalls += 1
        return this.Root
    }
    static Context() => this.NativeChanged ? {Key:"7:9"} : this.Native
    static Same(a,b) => a.Id = b.Id
    static Out(object,slot,args*) {
        if object = this.Grid && slot = 3 {
            this.Address := args[2] ":" args[4]
            return this.Cell
        }
        if object = this.ClientValue && slot = 8 {
            this.FocusCalls += 1
            return this.FocusChanged && this.FocusCalls > 1 ? {Id:9,Type:50033,Focus:true} : this.Pane
        }
        if object = this.ClientValue && slot = 16
            return this.Walker
        throw Error("unexpected Excel focus API call")
    }
    static Property(element,id,type) {
        names := Map(30003,"Type",30008,"Focus",30010,"Enabled",30019,"Password",30022,"Offscreen")
        return element.%names[id]%
    }
    static RawChild(walker,element,slot) {
        if slot = 3 {
            if this.ParentChanged
                return {Id:8}
            if element = this.Cell
                return this.Grid
            return element.Id = 3 ? this.Root : this.Cell
        }
        children := element = this.Cell || (slot = 6 && element.Id != 3 && this.CellChildren.Length)
            ? this.CellChildren : this.Children
        if slot = 4 {
            if children.Length
                return children[1]
        } else if slot = 6 {
            this.SiblingCalls += 1
            for index, child in children
                if child = element && index < children.Length
                    return children[index+1]
        }
        this.LastHresult := this.EndHresult
        throw Error("UIA interface unavailable")
    }
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
        this.FinalReadOnly := false, this.FinalType := 0
        this.FinalRangeReadOnly := false
        this.ActiveAvailable := false, this.CaretActive := true, this.ActiveShift := 0, this.CaretReadOnly := false
        this.ActiveHasAnchor := true, this.ActiveCalls := 0, this.ActiveAnchorCalls := 0
        this.FieldRect := false
        this.ProxyAvailable := false, this.ProxyCalls := 0, this.ProxyGoneAfterRead := false, this.FinalOffscreen := false
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
        if this.FocusCalls > 1 && id = 30046 && this.FinalReadOnly
            return true
        if this.FocusCalls > 1 && id = 30003 && this.FinalType
            return this.FinalType
        if this.FocusCalls > 1 && id = 30022 && this.FinalOffscreen
            return true
        return this.Props[id]
    }
    static AncestorMatches(*) => this.Ancestor
    static Identity(element) {
        this.FailAt("Identity")
        return element.Id
    }
    static Pattern(element, id, *) {
        this.FailAt("Pattern")
        if id = 10024 && !this.ActiveAvailable
            throw Error("mock TextPattern2 unavailable")
        return this.PatternValue
    }
    static CaretRange(pattern) {
        this.ActiveCalls += 1
        if !this.CaretActive
            throw Error("mock inactive caret")
        return {Start: this.Caret + this.ActiveShift, End: this.Caret + this.ActiveShift, Kind: "Caret"}
    }
    ; Inherit production Selection(): real COM count + collapse validation.
    static Compare(a, endpoint, b, otherEndpoint) {
        this.FailAt("Compare")
        return (endpoint ? a.End : a.Start) - (otherEndpoint ? b.End : b.Start)
    }
    static ReadOnly(range) {
        this.FailAt("ReadOnly")
        if this.FinalRangeReadOnly && this.TextCalls >= 4
            return true
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
    static Anchor(range, *) {
        this.FailAt("Anchor")
        if range.Kind = "Caret" {
            this.ActiveAnchorCalls += 1
            return this.ActiveHasAnchor ? {Found: true, X: 10, Y: 20, Method: "MockCaret"} : false
        }
        return this.NoAnchor ? false : {Found: true, X: 10, Y: 20, Method: "MockCaret"}
    }
    static Context() {
        this.FailAt("Context")
        this.Events .= "Context,"
        return this.CurrentNative
    }
    static ElementRectangle(element) {
        if !this.FieldRect
            throw Error("mock field rectangle unavailable")
        return this.FieldRect
    }
    static ClientBounds(context) => {Left: 0, Top: 0, Right: 1000, Bottom: 1000}
    static MsaaAnchor(context) {
        this.ProxyCalls += 1
        if !this.ProxyAvailable || (this.ProxyGoneAfterRead && this.TextCalls >= 2)
            return false
        return {Found: true, X: 20, Top: 30, Bottom: 55, Y: 55, Method: "MSAACaret"}
    }
    static Same(a, b) => a.Id == b.Id
}

class MsaaTestApi extends EacUia {
    static Reset() {
        this.Owner := 8, this.Role := 7, this.State := 0, this.Rect := [20,30,1,25], this.Fail := false
    }
    static MsaaObject(context) {
        if this.Fail
            throw Error("mock unavailable system caret")
        return {}
    }
    static MsaaOwner(caret) => this.Owner
    static MsaaInt(caret, slot) => slot = 13 ? this.Role : this.State
    static MsaaRectangle(caret) => this.Rect
    static ClientBounds(context) => {Left: 0, Top: 0, Right: 1000, Bottom: 1000}
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
    RectValues := []
    __New(kind, owner := false) {
        this.Owner := owner, this.Callbacks := []
        this.Vtable := Buffer(23 * A_PtrSize, 0), this.Instance := Buffer(A_PtrSize, 0)
        NumPut "Ptr", this.Vtable.Ptr, this.Instance
        this.SetSlot(0, "Query", 3), this.SetSlot(1, "AddRef", 1), this.SetSlot(2, "Release", 1)
        if kind = "msaa" {
            this.SetSlot(13, "AccVariant", 3), this.SetSlot(14, "AccVariant", 3), this.SetSlot(22, "AccLocation", 6)
        } else if kind = "caret"
            this.SetSlot(10, "Caret", 3)
        else if kind = "array"
            this.SetSlot(3, "Count", 2)
        else {
            this.SetSlot(4, "RuntimeId", 2), this.SetSlot(5, "Interface", 2)
            this.SetSlot(9, "Attribute", 3), this.SetSlot(11, "Property", 4), this.SetSlot(12, "Text", 3)
            this.SetSlot(10, "Bounds", 2)
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
        if this.VarType = 0x2005 {
            array := DllCall("oleaut32\SafeArrayCreateVector", "UShort", 5, "Int", 0, "UInt", this.RectValues.Length, "Ptr")
            for value in this.RectValues {
                index := A_Index - 1
                DllCall "oleaut32\SafeArrayPutElement", "Ptr", array, "Int*", index, "Double*", value
            }
            NumPut "Ptr", array, output, 8
        } else if this.VarType = 8 {
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
    Bounds(pointer, output) {
        array := DllCall("oleaut32\SafeArrayCreateVector", "UShort", 5, "Int", 0, "UInt", this.RectValues.Length, "Ptr")
        for value in this.RectValues {
            index := A_Index - 1
            DllCall "oleaut32\SafeArrayPutElement", "Ptr", array, "Int*", index, "Double*", value
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
    Caret(pointer, active, output) {
        NumPut "Int", this.BoolValue, active
        if !this.NullInterface
            this.Owner.References += 1
        NumPut "Ptr", this.NullInterface ? 0 : this.Owner.Instance.Ptr, output
        return this.HResult
    }
    EndpointCompare(pointer, endpoint, other, otherEndpoint, output) {
        NumPut "Int", this.IntValue, output
        return this.HResult
    }
    AccVariant(pointer, child, output) {
        this.ChildType := NumGet(child,0,"UShort"), this.ChildId := NumGet(child,8,"Int")
        return this.Variant(0,output)
    }
    AccLocation(pointer, x, y, width, height, child) {
        this.ChildType := NumGet(child,0,"UShort"), this.ChildId := NumGet(child,8,"Int")
        for pointer in [x,y,width,height]
            NumPut "Int", this.RectValues[A_Index], pointer
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
