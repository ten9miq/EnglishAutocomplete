#Requires AutoHotkey v2.0+

class EacApplication {
    Visible := false
    Sending := false
    Selected := 1
    ShownGeneration := -1
    Target := false
    Pending := []
    Items := []
    Fault := ""
    InputModifierMask := 0
    LastInputAt := 0

    __New(config, start := true) {
        this.Config := config
        this.User := EacUserDictionary(config.DataDirectory "\user.db", config.PromotionCount)
        this.Engine := EacSuggestionEngine(config.Root "\data\dictionary.db", config, this.User)
        this.Tracker := EacInputTracker()
        this.Gui := EacSuggestionGui(config)
        this.Caret := EacCaretProvider(config.CaretMode)
        this.Ime := EacImeStateProvider()
        this.Ime.NativePriority := true
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
        for binding in this.KeyBindings {
            HotIf binding.Condition
            Hotkey binding.Key, "Off"
        }
        HotIf
    }

    Reset(*) {
        this.InputModifierMask := 0
        this.Visible := false
        this.Gui.Hide()
        this.Tracker.Reset()
        this.Pending := []
        this.Items := []
        this.Target := false
    }

    Hide() {
        this.Visible := false
        this.Gui.Hide()
    }

    OnChar(hook, text) {
        if this.Sending
            return
        ; Injected hotkey handling may release modifiers at SendLevel 0, whose
        ; key-up notifications are deliberately ignored by this InputHook.
        this.InputModifierMask &= this.Modifiers()
        this.LastInputAt := A_TickCount
        context := EacFieldGuard.Context()
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
            if !verified || verified.Position != field.Position
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
                if !snapshot && this.SafetyReason = "TextChanged" {
                    this.Hide()
                    SetTimer this.RefreshCallback, -this.Config.DebounceMs
                    return
                }
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
            if StrLen(prefix) < this.Config.MinLength || !EacUserDictionary.Valid(prefix, true) {
                this.Hide()
                return
            }
            if this.ShownGeneration != this.Tracker.Generation {
                items := this.Engine.Search(prefix)
                if generation != this.Tracker.Generation
                    return
                this.Items := items
                this.Selected := 1
            }
            if !this.Items.Length {
                this.Hide()
                return
            }
            anchor := this.Caret.GetPosition(snapshot.Context)
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
        if !this.Visible || this.Sending || this.ShownGeneration != this.Tracker.Generation || !this.Target
            return false
        if !this.Target.Policy.Keys || !this.Config.Enabled
            return false
        if binding.Key = "Tab" && !this.Target.Policy.Tab
            return false
        if binding.Key = "Enter" && !this.Target.Policy.Enter
            return false
        if binding.Action = "number" && binding.Number > this.Items.Length
            return false
        snapshot := this.Snapshot()
        return snapshot && snapshot.Context.Key = this.Target.Context.Key
            && snapshot.Ime.Key = this.Target.Ime.Key
            && EacFieldGuard.Matches(snapshot.Field, this.Tracker.Word)
    }

    Action(binding, *) {
        if !this.CanIntercept(binding)
            return
        if binding.Action = "cancel" {
            this.Reset()
            return
        }
        if binding.Action = "next" || binding.Action = "previous" {
            this.Selected := Mod(this.Selected - 1 + (binding.Action = "next" ? 1 : -1) + this.Items.Length, this.Items.Length) + 1
            this.Refresh()
            return
        }
        if binding.Action = "number"
            this.Selected := binding.Number
        if binding.Action = "first"
            this.Selected := 1
        this.Commit()
    }

    Commit() {
        snapshot := this.Snapshot()
        prefix := this.Tracker.Word
        if !snapshot || !this.Target || snapshot.Context.Key != this.Target.Context.Key
            || snapshot.Ime.Key != this.Target.Ime.Key || !EacFieldGuard.Matches(snapshot.Field, prefix)
            || !this.Visible || this.Selected > this.Items.Length {
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
        } finally {
            this.Sending := false
        }
        SetTimer this.RefreshCallback, -this.Config.DebounceMs
        return true
    }

    InstallKeys() {
        definitions := [[this.Config.AcceptKey, "accept"], [this.Config.NextKey, "next"],
            [this.Config.PreviousKey, "previous"], [this.Config.CancelKey, "cancel"],
            ["Tab", "first"], ["Enter", "accept"]]
        loop 9
            definitions.Push([this.Config.DirectModifier A_Index, "number", A_Index])
        used := Map()
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
            binding := {Key: key, Action: definition[2], Number: definition.Length = 3 ? definition[3] : 0,
                Vk: GetKeyVK(match[2]), Modifiers: mask}
            binding.Condition := ObjBindMethod(this, "CanIntercept", binding)
            HotIf binding.Condition
            Hotkey "$" key, ObjBindMethod(this, "Action", binding)
            HotIf
            this.KeyBindings.Push(binding)
        }
    }

    Modifiers() => (GetKeyState("Ctrl") ? 1 : 0) | (GetKeyState("Alt") ? 2 : 0)
        | (GetKeyState("Shift") ? 4 : 0) | ((GetKeyState("LWin") || GetKeyState("RWin")) ? 8 : 0)
}
