#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

Checks := 0
OnError((e, *) => (FileAppend("FAIL " e.Message " at " e.Line "`n" e.Stack, "**"), ExitApp(1)))
context := {Focus: 1, Thread: 2, Key: "1:1"}
for reason in ["ENG", "IMEClosed"] {
    provider := TestIme([State(0, -1, reason)])
    Assert(provider.GetState(context).Allowed, reason " remains allowed")
    Assert(provider.Composition.Calls = 0, reason " does not invoke UIA")
}
for mode in [0, 16] {
    provider := TestIme([State(1, mode)])
    result := provider.GetState(context)
    Assert(result.Allowed && result.Reason = "IMEHalfwidthAlphanumeric", "open halfwidth mode " mode)
    Assert(provider.Composition.Calls = 1 && provider.Reads = 2, "composition + mode recheck")
    for proof in [{Known: false, Active: false}, {Known: true, Active: true}] {
        provider.Composition.Proof := proof
        Assert(!provider.GetState(context).Allowed, "unknown/active composition refused")
    }
}
for mode in [1, 3, 8, 9, 17, 19, 24, 25, 27, 32, 256, 0x1000, -1] {
    provider := TestIme([State(1, mode)])
    Assert(!provider.GetState(context).Allowed, "unsafe mode refused " mode)
    Assert(provider.Composition.Calls = 0, "unsafe mode does not invoke UIA")
}
for reason in ["UnknownLayout", "UnknownIME", "UnknownConversionMode"] {
    provider := TestIme([{Known: false, Reason: reason, Layout: 0}])
    Assert(!provider.GetState(context).Allowed, reason " refused")
}
for changed in [State(0), State(1, 16), {Known: false, Reason: "UnknownIME", Layout: 0},
    {Known: true, Reason: "ENG", Layout: 0x409, Open: 0, Mode: -1}] {
    provider := TestIme([State(1, 0), changed])
    Assert(!provider.GetState(context).Allowed, "mode/layout/read change during UIA refused")
}
provider := TestIme([State(1, 0)])
provider.Current := false
Assert(!provider.GetState(context).Allowed, "focus change during UIA refused")
closed := TestIme([State(0)]).GetState(context)
opened := TestIme([State(1, 0)]).GetState(context)
Assert(closed.Key != opened.Key, "open transition invalidates old candidate identity")
Assert(opened.Key != TestIme([State(1, 16)]).GetState(context).Key, "mode transition invalidates identity")
for mode in [0, 16, 9, 25] {
    provider := TestIme([State(1, mode)])
    provider.NativePriority := true
    result := provider.GetState(context)
    Assert(!result.Allowed && result.Reason = "NativeIMEPriority", "open IME always owns conversion keys " mode)
    Assert(provider.Composition.Calls = 0, "native-priority mode does not query composition")
}
FileAppend "PASS ime_checks=" Checks " AHK=" A_AhkVersion "`n", "*"
ExitApp 0

State(open, mode := -1, reason := "IMEOpen") =>
    {Known: true, Reason: reason, Layout: 0x411, Open: open, Mode: mode}

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}

class TestIme extends EacImeStateProvider {
    Reads := 0
    Current := true
    __New(states) {
        this.States := states
        this.Composition := TestComposition()
    }
    ReadState(context) {
        this.Reads += 1
        return this.States[Min(this.Reads, this.States.Length)]
    }
    IsCurrent(context) => this.Current
}

class TestComposition {
    Calls := 0
    Proof := {Known: true, Active: false}
    GetState(context) {
        this.Calls += 1
        return this.Proof
    }
}
