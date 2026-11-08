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
