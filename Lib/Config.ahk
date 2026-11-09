#Requires AutoHotkey v2.0+

class EacConfig {
    __New(root, path := "") {
        this.Root := root
        this.Path := path != "" ? path : root "\user\settings.ini"
        if !FileExist(this.Path) {
            SplitPath this.Path, , &directory
            DirCreate directory
            FileCopy root "\settings.default.ini", this.Path
        }
        this.Enabled := this.Int("General", "Enabled", 1, 0, 1)
        this.MinLength := this.Int("General", "MinLength", 2, 2, 32)
        this.MaxCandidates := this.Int("General", "MaxCandidates", 9, 1, 9)
        this.InitialCandidates := Min(this.MaxCandidates, this.Int("General", "InitialCandidates", 5, 1, 9))
        this.FontSize := this.Int("General", "FontSize", 11, 8, 24)
        this.OffsetX := this.Int("General", "OffsetX", 0, -1000, 1000)
        this.OffsetY := this.Int("General", "OffsetY", 24, -1000, 1000)
        this.ShowTranslation := this.Int("General", "ShowTranslation", 1, 0, 1)
        this.Learning := this.Int("General", "Learning", 1, 0, 1)
        this.PromotionCount := this.Int("General", "PromotionCount", 2, 2, 100)
        this.SCOWL := this.Int("General", "SCOWL", 1, 0, 1)
        this.EJDict := this.Int("General", "EJDict", 1, 0, 1)
        this.Debug := this.Int("General", "Debug", 0, 0, 1)
        this.CaretMode := this.Read("General", "CaretMode", "Win32")
        if this.CaretMode != "Win32" && this.CaretMode != "Off"
            throw Error("CaretMode must be Win32 or Off")
        this.DebounceMs := this.Int("General", "DebounceMs", 30, 10, 250)
        data := this.Read("General", "DataDirectory", "user")
        this.DataDirectory := RegExMatch(data, "i)^(?:[a-z]:|\\\\)") ? data : root "\" data
        DirCreate this.DataDirectory
        this.AcceptKey := this.Read("Keys", "Accept", "^!Space")
        this.NextKey := this.Read("Keys", "Next", "Tab")
        this.PreviousKey := this.Read("Keys", "Previous", "^!Up")
        this.CancelKey := this.Read("Keys", "Cancel", "Esc")
        this.DirectModifier := this.Read("Keys", "DirectModifier", "^!")
        if !RegExMatch(this.DirectModifier, "^[\^!#]+$")
            throw Error("DirectModifier must contain Ctrl/Alt/Win modifiers")
        this.Tab := this.Int("Keys", "Tab", 0, 0, 1)
        this.Enter := this.Int("Keys", "Enter", 0, 0, 1)
        this.ImeStyleKeys := this.Int("Keys", "ImeStyle", 1, 0, 1)
        this.DefaultEnabled := this.Int("Applications", "DefaultEnabled", 1, 0, 1)
        this.DefaultLearning := this.Int("Applications", "DefaultLearning", 1, 0, 1)
        this.Excluded := "," StrLower(StrReplace(this.Read("Applications", "Excluded", ""), " ", "")) ","
        this.Policies := Map()
    }

    Read(section, key, fallback) => IniRead(this.Path, section, key, fallback)
    Int(section, key, fallback, low, high) {
        value := this.Read(section, key, fallback)
        if !IsInteger(value)
            throw Error("Invalid numeric setting: " section "/" key)
        return Min(high, Max(low, Integer(value)))
    }

    Policy(process) {
        process := StrLower(process)
        if this.Policies.Has(process)
            return this.Policies[process]
        section := "app:" process
        policy := {Enabled: this.Int(section, "Enabled", this.DefaultEnabled, 0, 1),
            Learning: this.Learning && this.Int(section, "Learning", this.DefaultLearning, 0, 1),
            Keys: this.Int(section, "Keys", 1, 0, 1),
            Tab: this.Int(section, "Tab", this.Tab, 0, 1),
            Enter: this.Int(section, "Enter", this.Enter, 0, 1),
            ImeStyleKeys: this.Int(section, "ImeStyle", this.ImeStyleKeys, 0, 1)}
        if InStr(this.Excluded, "," process ",")
            policy.Enabled := false, policy.Learning := false
        this.Policies[process] := policy
        return policy
    }
}
