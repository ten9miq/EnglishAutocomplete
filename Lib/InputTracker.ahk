#Requires AutoHotkey v2.0+

class EacInputTracker {
    Word := ""
    ContextKey := ""
    Generation := 0
    Learned := false
    Blocked := false

    Reset() {
        this.Word := "", this.ContextKey := "", this.Learned := false, this.Blocked := false
        this.Generation += 1
    }

    Feed(text, contextKey) {
        if this.ContextKey != contextKey
            this.Reset(), this.ContextKey := contextKey
        completed := []
        loop parse text {
            character := A_LoopField
            if RegExMatch(character, "\s") {
                if this.Word != "" && !this.Blocked && !this.Learned
                    completed.Push(this.Word)
                this.Word := "", this.Learned := false, this.Blocked := false
            } else if !this.Blocked {
                this.Word .= character
                if StrLen(this.Word) > 64 || RegExMatch(character, "[^A-Za-z0-9_'.@:/+?=&#%!-]") {
                    this.Word := "", this.Blocked := true
                }
            }
        }
        this.Generation += 1
        return completed
    }

    Backspace() {
        if this.Blocked || this.Word = "" {
            this.Reset()
            return
        }
        this.Word := SubStr(this.Word, 1, StrLen(this.Word) - 1)
        this.Learned := false
        this.Generation += 1
        ; The application must verify this shortened prefix against real text
        ; before showing it. Custom deletion/selection changes fail that check.
    }
}

; Separate learning boundaries from the completion token (it-des, etc.).
; Absolute offsets refer only to observed input, retained in a bounded tail.
class EacLearningTracker {
    Epoch := 0
    Tail := ""
    Total := 0
    ContextKey := ""
    Unit := ""
    UnitStart := 0
    GuardStart := 0
    Suppressed := false
    PreviousCR := false

    Reset() {
        this.Epoch += 1
        this.Tail := "", this.Total := 0, this.ContextKey := ""
        this.Unit := "", this.UnitStart := 0, this.GuardStart := 0, this.Suppressed := false
        this.PreviousCR := false
    }
    Feed(text, contextKey) {
        if this.ContextKey != contextKey
            this.Reset(), this.ContextKey := contextKey
        completed := []
        loop parse text {
            character := A_LoopField
            if character = "`n" && this.PreviousCR {
                this.PreviousCR := false
                continue
            }
            this.PreviousCR := character = "`r"
            if this.PreviousCR
                character := "`n"
            this.Tail := SubStr(this.Tail character, -128)
            this.Total += 1
            hard := RegExMatch(character, "^[\s,]$")
            if hard || character = "." || character = "-" {
                this.Finish(completed)
                this.Unit := "", this.UnitStart := this.Total
                if hard
                    this.GuardStart := this.Total, this.Suppressed := false
            } else if StrLen(this.Unit) <= 64
                this.Unit .= character
        }
        return completed
    }
    Finish(completed) {
        if this.Suppressed || this.Unit = ""
            return
        word := RTrim(this.Unit, "!?;:")
        ; Delay case pieces until the unit ends, so a full identifier's
        ; credential/length checks apply to every piece before any DB write.
        parts := RegExReplace(word, "([a-z])([A-Z])", "$1`n$2")
        parts := RegExReplace(parts, "([A-Z])([A-Z][a-z])", "$1`n$2")
        seen := Map()
        this.Add(completed, seen, word, this.UnitStart)
        position := this.UnitStart
        for part in StrSplit(parts, "`n") {
            this.Add(completed, seen, part, position)
            position += StrLen(part)
        }
    }
    Add(completed, seen, word, start) {
        norm := StrLower(word)
        if !EacUserDictionary.Valid(word) || seen.Has(norm)
            return
        seen[norm] := true
        completed.Push({Word: word, Start: start, End: start + StrLen(word),
            GuardStart: this.GuardStart, Epoch: this.Epoch, Journal: true, Boundary: true, ContextKey: this.ContextKey})
    }
    Complete(suffix, word, contextKey) {
        ; Injected completion is observed separately exactly once. Its later
        ; separator must not count the whole word or its case pieces again.
        if this.ContextKey != contextKey
            this.Reset(), this.ContextKey := contextKey
        this.Suppressed := true
        this.Feed(suffix, contextKey)
        return {Word: word, Start: this.Total - StrLen(word), End: this.Total,
            GuardStart: this.GuardStart, Epoch: this.Epoch, Journal: true, Boundary: false, ContextKey: contextKey}
    }
    static SafeGuard(raw) {
        if RegExMatch(LTrim(raw, ".-"), "i)^www\.")
            return false
        raw := LTrim(RTrim(raw, ".-!?;:"), ".-")
        if !RegExMatch(raw, "^[A-Za-z][A-Za-z_'.-]*$") || StrLen(raw) > 64
            || RegExMatch(raw, "i)^(?:token|secret|password|api[_.-]?key|bearer|authorization)[_A-Za-z0-9.-]*$")
            || (StrLen(raw) > 20 && RegExMatch(raw, "[a-z]") && RegExMatch(raw, "[A-Z]"))
            return false
        return true
    }
    Verify(field, observation) {
        first := this.Total - StrLen(this.Tail)
        if observation.Epoch != this.Epoch || observation.ContextKey != this.ContextKey || observation.GuardStart < first
            || observation.Start < observation.GuardStart || observation.End > this.Total
            return "Discard"
        expected := SubStr(this.Tail, observation.GuardStart - first + 1)
        if expected = ""
            return "Discard"
        RegExMatch(expected, "^[^\s,]*", &guard)
        if !EacLearningTracker.SafeGuard(guard[0])
            return "Discard"
        before := StrReplace(StrReplace(field.Before, "`r`n", "`n"), "`r", "`n")
        offset := StrLen(before) - StrLen(expected)
        if offset < 0 || !(SubStr(before, offset + 1) == expected)
            return "Wait"
        preceding := offset > 0 ? SubStr(before, offset, 1) : ""
        if RegExMatch(preceding, "[A-Za-z0-9_@:/.'\\-]")
            return "Discard"
        if StrLen(guard[0]) = StrLen(expected) && field.After != "" && !RegExMatch(field.After, "^[\s,]")
            return "Discard" ; don't learn an unfinished fragment of existing text
        localStart := observation.Start - observation.GuardStart + 1
        if !(SubStr(expected, localStart, StrLen(observation.Word)) == observation.Word)
            return "Discard"
        if !observation.Boundary {
            following := SubStr(expected, observation.End - observation.GuardStart + 1, 1)
            if following != "" && !RegExMatch(following, "^[\s,.-]$")
                return "Discard"
        }
        return "Ready"
    }
}
