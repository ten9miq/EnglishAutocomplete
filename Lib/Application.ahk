#Requires AutoHotkey v2.0+

class EacApplication {
    Visible := false
    Sending := false
    Selected := 0
    ShownGeneration := -1
    Target := false
    Pending := []
    Items := []
    Fault := ""
    InputModifierMask := 0
    LastInputAt := 0
    Navigating := false
    CommitCount := 0
    TextRetryAt := 0
    Accepting := false
    AcceptScopeKey := ""
    EnterLatched := false
    EnterActionArmed := false
    EnterReleaseSerial := 0
    EnterArmedSerial := 0
    ReleaseBindings := []

    __New(config, start := true) {
        this.Config := config
        this.User := EacUserDictionary(config.DataDirectory "\user.db", config.PromotionCount)
        this.Engine := EacSuggestionEngine(config.Root "\data\dictionary.db", config, this.User)
        this.Tracker := EacInputTracker()
        this.Gui := EacSuggestionGui(config)
        this.Caret := EacCaretProvider(config.CaretMode)
        this.Ime := EacImeStateProvider()
        this.Ime.NativePriority := true ; an open IME owns conversion and its keys
        this.RefreshCallback := ObjBindMethod(this, "Refresh")
        this.TickCallback := ObjBindMethod(this, "Tick")
        this.KeyBindings := []
        if start
            this.Start()
    }

    Start(watchMouse := true) {
        this.Hook := InputHook("V L0 I1")
        this.Hook.KeyOpt("{All}", "N")
        this.Hook.OnChar := ObjBindMethod(this, "OnChar")
        this.Hook.OnKeyDown := ObjBindMethod(this, "OnKeyDown")
        this.Hook.OnKeyUp := ObjBindMethod(this, "OnKeyUp")
        this.InstallKeys()
        ; Mouse handlers pass through and invalidate without reading app text.
        if watchMouse {
            for key in ["~*LButton", "~*RButton", "~*MButton", "~*WheelUp", "~*WheelDown"]
                Hotkey key, ObjBindMethod(this, "Reset")
        }
        this.Hook.Start()
        SetTimer this.TickCallback, 400
    }

    Stop() {
        if this.HasOwnProp("Hook")
            this.Hook.Stop()
        SetTimer this.TickCallback, 0
        SetTimer this.RefreshCallback, 0
        this.Reset()
        for group in [this.KeyBindings, this.ReleaseBindings] {
            for binding in group {
                if binding.Condition
                    HotIf binding.Condition
                else
                    HotIf
                Hotkey binding.Key, "Off"
            }
        }
        HotIf
        this.EnterLatched := false, this.EnterActionArmed := false, this.Accepting := false
    }

    Reset(*) {
        this.InputModifierMask := 0
        this.ClearSelection()
        this.Visible := false
        this.Gui.Hide()
        this.Tracker.Reset()
        this.Pending := []
        this.Items := []
        this.Target := false
    }

    Hide() {
        this.ClearSelection()
        this.Visible := false
        this.Gui.Hide()
    }

    OnChar(hook, text) {
        if this.Sending
            return
        if (this.EnterLatched || this.Accepting) && (text = "`r" || text = "`n" || text = "`r`n")
            return
        ; Some InputHook notifications can precede the hotkey action for the
        ; same key. Candidate-control characters must not finish the prefix.
        if this.Visible && this.Target {
            policy := this.Target.Policy
            if (text = "`t" && (policy.ImeStyleKeys || policy.Tab))
                || ((text = "`r" || text = "`n" || text = "`r`n")
                    && this.Navigating && this.Selected > 0 && (policy.Enter || policy.ImeStyleKeys))
                return
        }
        this.ClearSelection()
        this.TextRetryAt := 0
        ; Injected hotkey handling may release modifiers at SendLevel 0, whose
        ; key-up notifications are deliberately ignored by this InputHook.
        this.InputModifierMask &= this.Modifiers()
        this.LastInputAt := A_TickCount
        context := this.CurrentContext()
        if !context {
            this.Reset()
            return
        }
        this.Visible := false ; invalidate hotkeys immediately, render on timer
        for word in this.Tracker.Feed(text, context.Key) {
            if this.Pending.Length < 8
                this.Pending.Push({Word: word, ContextKey: context.Key, Tick: A_TickCount, Boundary: true})
        }
        SetTimer this.RefreshCallback, -this.Config.DebounceMs
    }

    OnKeyDown(hook, vk, sc) {
        if this.Sending
            return
        bit := this.ModifierBit(vk)
        if bit {
            this.InputModifierMask |= bit
            return
        }
        if this.Visible {
            for binding in this.KeyBindings
                if binding.Vk = vk && (this.Modifiers() | this.InputModifierMask) = binding.Modifiers
                    && this.BindingPermitted(binding)
                    return
        }
        if this.InputModifierMask & 11 || GetKeyState("Ctrl") || GetKeyState("Alt")
            || GetKeyState("LWin") || GetKeyState("RWin") {
            this.Reset() ; copy/paste/undo/shortcuts invalidate observed text
            return
        }
        if vk = 8 {
            this.LastInputAt := A_TickCount
            this.Tracker.Backspace()
            this.Hide()
            SetTimer this.RefreshCallback, -this.Config.DebounceMs
            return
        }
        if vk = 13 || vk = 9 {
            context := EacFieldGuard.Context()
            if context {
                for word in this.Tracker.Feed(" ", context.Key)
                    this.Pending.Push({Word: word, ContextKey: context.Key, Tick: A_TickCount, Boundary: true})
                this.Hide()
                SetTimer this.RefreshCallback, -this.Config.DebounceMs
            }
            return
        }
        ; Delete/navigation, IME keys, layout switch, escape, function keys.
        if vk = 0x2E || (vk >= 0x21 && vk <= 0x28) || vk = 0x1B
            || (vk >= 0x15 && vk <= 0x1F) || (vk >= 0x70 && vk <= 0x87)
            || (vk >= 0xF0 && vk <= 0xF4)
            || vk = 0x5B || vk = 0x5C
            this.Reset()
    }

    OnKeyUp(hook, vk, sc) {
        bit := this.ModifierBit(vk)
        if bit
            this.InputModifierMask &= ~bit
    }

    ModifierBit(vk) {
        if vk = 0x11 || vk = 0xA2 || vk = 0xA3
            return 1
        if vk = 0x12 || vk = 0xA4 || vk = 0xA5
            return 2
        if vk = 0x10 || vk = 0xA0 || vk = 0xA1
            return 4
        if vk = 0x5B || vk = 0x5C
            return 8
        return 0
    }

    Snapshot() {
        this.SafetyReason := "Disabled"
        if !this.Config.Enabled
            return false
        this.SafetyReason := "NoContext"
        context := EacFieldGuard.Context()
        if !context
            return false
        try policy := this.Config.Policy(WinGetProcessName("ahk_id " context.Hwnd))
        catch
            return false
        if !policy.Enabled
            return false
        ime := this.Ime.GetState(context)
        if !ime.Allowed {
            this.SafetyReason := ime.Reason
            return false
        }
        this.SafetyReason := "Field"
        field := EacFieldGuard.Read(context)
        if !field {
            this.SafetyReason := EacFieldGuard.LastReason
            return false
        }
        if ime.Reason = "IMEHalfwidthAlphanumeric" {
            ; Composition queries must not validate text captured before a
            ; remote provider changed it. Keep the same local text/caret snapshot.
            verified := EacFieldGuard.Read(context)
            if !verified || !EacFieldGuard.SamePosition(verified, field)
                || !(verified.Before == field.Before) || !(verified.After == field.After) {
                this.SafetyReason := "TextChanged"
                return false
            }
        }
        current := EacFieldGuard.Context()
        if !current || current.Key != context.Key
            return false
        verifiedIme := this.Ime.GetState(context)
        if !verifiedIme.Allowed || verifiedIme.Key != ime.Key {
            this.SafetyReason := verifiedIme.Allowed ? "IMEChanged" : verifiedIme.Reason
            return false
        }
        this.SafetyReason := "OK"
        return {Context: context, Field: field, Policy: policy, Ime: ime}
    }

    Tick() {
        if this.Tracker.Word = "" && !this.Visible && !this.Pending.Length
            return ; no caret or UIA work while idle
        if this.Visible && this.Target && this.Target.Field.HasOwnProp("Identity")
            && this.ShownGeneration = this.Tracker.Generation {
            ; A stable preview/selection needs only a lightweight focus/IME
            ; keepalive. Re-reading rich text every 400ms can race AX updates and
            ; erase the conversion state even though the user changed no text.
            context := this.CurrentContext()
            if !context || context.Key != this.Target.Context.Key {
                this.Reset()
                return
            }
            ime := this.Ime.GetState(context)
            if !ime.Allowed {
                if ime.Reason != "UnknownIME"
                    this.Reset()
                return
            }
            if ime.Key != this.Target.Ime.Key {
                this.Reset()
                return
            }
            if !EacFieldGuard.StillFocused(this.Target.Field, context) {
                if EacUia.LastHresult != -2146233083
                    this.Reset()
                return
            }
            this.Gui.Show(this.Items, this.Selected, this.Target.Field.Anchor)
            return
        }
        this.Refresh()
    }

    Refresh() {
        if this.Sending
            return
        try {
            generation := this.Tracker.Generation
            snapshot := this.Snapshot()
            if generation != this.Tracker.Generation
                return ; a newer input callback already armed its own refresh
            if !snapshot || (this.Tracker.ContextKey != "" && snapshot.Context.Key != this.Tracker.ContextKey) {
                if !snapshot && (this.SafetyReason = "TextChanged" || this.SafetyReason = "UnknownIME") {
                    this.Hide()
                    if !this.TextRetryAt
                        this.TextRetryAt := A_TickCount
                    if A_TickCount - this.TextRetryAt > 350 {
                        this.Reset()
                        return
                    }
                    SetTimer this.RefreshCallback, -this.Config.DebounceMs
                    return
                }
                this.Reset()
                return
            }
            this.TextRetryAt := 0
            if this.Target && !EacFieldGuard.SameTarget(snapshot.Field, this.Target.Field) {
                this.Reset()
                return
            }
            for observation in this.Pending {
                if snapshot.Policy.Learning && observation.ContextKey = snapshot.Context.Key
                    && A_TickCount - observation.Tick < 500
                    && EacFieldGuard.Matches(snapshot.Field, observation.Word, observation.Boundary)
                    this.User.Observe(RTrim(observation.Word, ".,!?;:"))
            }
            this.Pending := []
            prefix := this.Tracker.Word
            if prefix != "" && !EacFieldGuard.Matches(snapshot.Field, prefix) {
                this.Hide()
                ; Native text can precede its asynchronous InputHook callback.
                ; Keep only the bounded, untrusted current token until its next
                ; event/boundary; never display or commit an unmatched token.
                return
            }
            if StrLen(prefix) < this.Config.MinLength || !EacSuggestionEngine.ValidPrefix(prefix) {
                this.Hide()
                return
            }
            if this.ShownGeneration != this.Tracker.Generation {
                items := this.Engine.Search(prefix)
                if generation != this.Tracker.Generation
                    return
                this.Items := items
                this.ClearSelection()
            }
            if !this.Items.Length {
                this.Hide()
                return
            }
            anchor := snapshot.Field.HasOwnProp("Anchor") && snapshot.Field.Anchor
                ? snapshot.Field.Anchor : this.Caret.GetPosition(snapshot.Context)
            if generation != this.Tracker.Generation
                return
            if !anchor.Found {
                this.Hide()
                return
            }
            this.Target := snapshot
            this.ShownGeneration := this.Tracker.Generation
            this.Gui.Show(this.Items, this.Selected, anchor)
            this.Visible := generation = this.Tracker.Generation
            if !this.Visible
                this.Gui.Hide()
        } catch {
            this.Fault := "Autocomplete suspended after runtime error; reload from tray"
            this.Reset()
            this.Config.Enabled := false
            if this.Config.Debug
                try FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " runtime fault; no input text recorded`n", this.Config.DataDirectory "\status.log", "UTF-8"
        }
    }

    CanIntercept(binding, *) {
        plainEnter := binding.Vk = 13 && binding.Modifiers = 0
        if plainEnter && this.EnterLatched
            return true ; the entire consumed press remains ours until key-up
        if plainEnter && this.Accepting {
            context := this.CurrentContext()
            if !context || context.Key != this.AcceptScopeKey
                return false
            ime := this.Ime.GetState(context)
            if !ime.Allowed && ime.Reason != "UnknownIME"
                return false ; a new press with native IME ON belongs to that IME
            return this.ArmEnter()
        }
        if !this.Visible || this.Sending || this.ShownGeneration != this.Tracker.Generation || !this.Target
            return false
        if !this.BindingPermitted(binding)
            return false
        if binding.Action = "number" && binding.Number > this.Items.Length
            return false
        if binding.Vk = 13 && binding.Modifiers = 0 && this.Navigating {
            ; Once conversion has started, a failed text validation must cancel
            ; it, not fall through to a chat application's Send/Submit action.
            context := this.CurrentContext()
            if !context || context.Key != this.Target.Context.Key
                return false
            ime := this.Ime.GetState(context)
            allowed := (ime.Allowed && ime.Key = this.Target.Ime.Key) || (!ime.Allowed && ime.Reason = "UnknownIME")
            return allowed && this.ArmEnter()
        }
        if this.Target.Field.HasOwnProp("Identity")
            && (binding.Action = "next" || binding.Action = "previous") {
            ; Navigation changes only our popup. Fresh focus/safety metadata is
            ; sufficient; defer expensive text/endpoint checks to Commit.
            context := this.CurrentContext()
            if !context || context.Key != this.Target.Context.Key
                return false
            ime := this.Ime.GetState(context)
            return ime.Allowed && ime.Key = this.Target.Ime.Key
                && EacFieldGuard.StillFocused(this.Target.Field, context)
        }
        snapshot := this.Snapshot()
        return snapshot && snapshot.Context.Key = this.Target.Context.Key
            && snapshot.Ime.Key = this.Target.Ime.Key
            && EacFieldGuard.SameTarget(snapshot.Field, this.Target.Field)
            && (!snapshot.Field.HasOwnProp("Identity") || EacFieldGuard.SamePosition(snapshot.Field, this.Target.Field))
            && EacFieldGuard.Matches(snapshot.Field, this.Tracker.Word)
            && EacFieldGuard.StillFocused(snapshot.Field, snapshot.Context)
    }

    BindingPermitted(binding) {
        if !this.Target || !this.Config.Enabled || !this.Target.Policy.Keys
            return false
        policy := this.Target.Policy
        if binding.StyleOnly && !policy.ImeStyleKeys
            return false
        if binding.Vk = 9 && (binding.Modifiers & ~4) = 0 && !policy.ImeStyleKeys && !policy.Tab
            return false
        if binding.Vk = 13 && binding.Modifiers = 0
            && (!this.Navigating || this.Selected < 1 || (!policy.Enter && !policy.ImeStyleKeys))
            return false
        return true
    }

    CurrentContext() => EacFieldGuard.Context()

    Action(binding, *) {
        plainEnter := binding.Vk = 13 && binding.Modifiers = 0
        if plainEnter {
            ; The hotkey condition armed exactly one action. Repeats do nothing.
            ; A key-up which ran before this handler invalidates only the latch,
            ; not the already captured confirm action.
            if !this.EnterActionArmed
                return
            this.EnterActionArmed := false
            this.EnterLatched := this.EnterReleaseSerial = this.EnterArmedSerial
            if this.Accepting || !this.Visible || !this.Navigating || this.Selected < 1
                return
        } else {
            if this.Accepting {
                if binding.Action = "cancel"
                    this.Reset()
                return
            }
            if !this.CanIntercept(binding)
                return
        }
        if binding.Action = "cancel" {
            this.Reset()
            return
        }
        if binding.Action = "next" || binding.Action = "previous" {
            if !this.Navigating || this.Selected < 1
                this.Selected := binding.Action = "previous" ? this.Items.Length : 1
            else
                this.Selected := Mod(this.Selected - 1 + (binding.Action = "previous" ? -1 : 1) + this.Items.Length, this.Items.Length) + 1
            this.Navigating := true
            this.RenderSelection()
            return
        }
        if binding.Action = "number"
            this.Selected := binding.Number
        if binding.Action = "first" || this.Selected < 1
            this.Selected := 1
        this.Navigating := true
        this.AcceptScopeKey := this.Target.Context.Key
        this.Accepting := true
        try this.Commit()
        finally this.Accepting := false
    }

    ClearSelection() {
        this.Selected := 0, this.Navigating := false
    }
    ArmEnter() {
        if !this.EnterActionArmed {
            this.EnterArmedSerial := this.EnterReleaseSerial
            this.EnterActionArmed := true
        }
        return true
    }
    CanReleaseEnter(*) => this.EnterLatched
    ReleaseEnter(*) {
        this.EnterReleaseSerial += 1
        this.EnterLatched := false
    }

    RenderSelection() {
        if this.Target && this.Target.Field.HasOwnProp("Identity") && this.Target.Field.Anchor {
            this.Gui.Show(this.Items, this.Selected, this.Target.Field.Anchor)
            this.Visible := true
        } else
            this.Refresh()
    }

    Commit() {
        if this.Accepting && this.Selected < 1
            return false
        generation := this.Tracker.Generation
        snapshot := this.Snapshot()
        prefix := this.Tracker.Word
        if !snapshot || !this.Target || snapshot.Context.Key != this.Target.Context.Key
            || snapshot.Ime.Key != this.Target.Ime.Key || !EacFieldGuard.Matches(snapshot.Field, prefix)
            || !EacFieldGuard.SameTarget(snapshot.Field, this.Target.Field)
            || (snapshot.Field.HasOwnProp("Identity") && !EacFieldGuard.SamePosition(snapshot.Field, this.Target.Field))
            || !this.Visible || this.Selected < 1 || this.Selected > this.Items.Length {
            this.Reset()
            return false
        }
        word := EacSuggestionEngine.ApplyCase(this.Items[this.Selected].Word, prefix)
        if StrLower(SubStr(word, 1, StrLen(prefix))) != StrLower(prefix) {
            this.Reset()
            return false
        }
        suffix := SubStr(word, StrLen(prefix) + 1)
        if suffix = ""
            return false
        verifiedIme := this.Ime.GetState(snapshot.Context)
        if !verifiedIme.Allowed || verifiedIme.Key != snapshot.Ime.Key
            || !EacFieldGuard.StillFocused(snapshot.Field, snapshot.Context) {
            this.Reset()
            return false
        }
        current := EacFieldGuard.Context()
        finalIme := this.Ime.GetState(snapshot.Context)
        if !current || current.Key != snapshot.Context.Key || !finalIme.Allowed
            || finalIme.Key != snapshot.Ime.Key || generation != this.Tracker.Generation || !this.Visible {
            this.Reset()
            return false
        }
        this.Sending := true
        this.Hide()
        try {
            ; Never erase existing text or use the clipboard.
            SendLevel 0
            SendText suffix
            this.Tracker.Word := prefix suffix
            this.Tracker.Learned := true
            this.Tracker.Generation += 1
            this.Pending.Push({Word: prefix suffix, ContextKey: snapshot.Context.Key,
                Tick: A_TickCount, Boundary: false})
            this.CommitCount += 1
        } finally {
            this.Sending := false
        }
        SetTimer this.RefreshCallback, -this.Config.DebounceMs
        return true
    }

    InstallKeys() {
        for binding in this.BuildBindings() {
            HotIf binding.Condition
            Hotkey "$" binding.Key, ObjBindMethod(this, "Action", binding)
            HotIf
            this.KeyBindings.Push(binding)
        }
        ; Key-up must not depend on InputHook: suppressed hotkey events can
        ; bypass its notifications. The passive fallback observes ordinary key
        ; releases without changing their native behavior.
        condition := ObjBindMethod(this, "CanReleaseEnter")
        HotIf condition
        Hotkey "$*Enter up", ObjBindMethod(this, "ReleaseEnter")
        this.ReleaseBindings.Push({Key: "*Enter up", Condition: condition})
        HotIf
        Hotkey "~*Enter up", ObjBindMethod(this, "ReleaseEnter")
        this.ReleaseBindings.Push({Key: "~*Enter up", Condition: false})
    }

    BuildBindings() {
        definitions := [[this.Config.AcceptKey, "accept"], [this.Config.NextKey, "next"],
            [this.Config.PreviousKey, "previous"], [this.Config.CancelKey, "cancel"],
            ["Enter", "accept"]]
        ; Standard conversion keys are candidate-only aliases. Explicit custom
        ; shortcuts remain authoritative when an alias has the same spelling.
        aliases := [["Tab", "next"], ["+Tab", "previous"], ["Down", "next"], ["Up", "previous"]]
        primary := Map()
        for definition in definitions
            primary[StrLower(definition[1])] := true
        for alias in aliases
            if !primary.Has(StrLower(alias[1]))
                definitions.Push([alias[1], alias[2], 0, true])
        loop 9
            definitions.Push([this.Config.DirectModifier A_Index, "number", A_Index])
        used := Map(), bindings := []
        for definition in definitions {
            key := definition[1]
            if key = ""
                continue
            if used.Has(StrLower(key))
                throw Error("Duplicate candidate hotkey: " key)
            used[StrLower(key)] := true
            if !RegExMatch(key, "^([\^!+#]*)([A-Za-z0-9]+)$", &match)
                throw Error("Candidate keys support simple ^!+# modifiers and one key")
            if match[1] = "" && !RegExMatch(match[2], "i)^(?:Tab|Enter|Esc|Escape|Up|Down|F\d+)$")
                throw Error("Unmodified text keys cannot be candidate hotkeys")
            mask := (InStr(match[1], "^") ? 1 : 0) | (InStr(match[1], "!") ? 2 : 0)
                | (InStr(match[1], "+") ? 4 : 0) | (InStr(match[1], "#") ? 8 : 0)
            binding := {Key: key, Action: definition[2], Number: definition.Length >= 3 ? definition[3] : 0,
                StyleOnly: definition.Length >= 4 ? definition[4] : false,
                Vk: GetKeyVK(match[2]), Modifiers: mask}
            binding.Condition := ObjBindMethod(this, "CanIntercept", binding)
            bindings.Push(binding)
        }
        return bindings
    }

    Modifiers() => (GetKeyState("Ctrl") ? 1 : 0) | (GetKeyState("Alt") ? 2 : 0)
        | (GetKeyState("Shift") ? 4 : 0) | ((GetKeyState("LWin") || GetKeyState("RWin")) ? 8 : 0)

    DiagnosticPacket(query := 0, *) {
        ; Read-only, cached numeric status. No field text, word, URL or title.
        if query = 2
            return EacUiaFieldProvider.Stage | (EacUia.LastProperty << 8) | (EacUia.LastVariantType << 32)
        if query = 3
            return EacUia.LastHresult
        if query = 4
            return EacUiaFieldProvider.BoundsStart
        if query = 5
            return EacUiaFieldProvider.BoundsEnd
        if query = 6
            return EacUiaFieldProvider.BoundsFlags
        reasons := ["OK", "Disabled", "NoContext", "UnknownField", "UIAUnsafeField",
            "UIAWindowMismatch", "UIAReadOnlyOrRange", "UIARange", "UIATextUnit",
            "UIACaretUnavailable", "TextChanged", "FocusChanged", "UIAUnavailable",
            "NativeIMEPriority", "IMEChanged", "UnknownIME", "UnknownLayout", "Field"]
        code := 0
        if this.HasOwnProp("SafetyReason")
            for index, reason in reasons
                if reason = this.SafetyReason
                    code := index
        return (this.Config.Enabled ? 1 : 0) | (this.Visible ? 2 : 0) | (this.Navigating ? 4 : 0)
            | (this.HasOwnProp("Hook") && this.Hook.InProgress ? 8 : 0)
            | (this.Items.Length << 4) | (this.Selected << 8) | (code << 16) | (this.CommitCount << 32)
    }
}
