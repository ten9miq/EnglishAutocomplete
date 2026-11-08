#Requires AutoHotkey v2.0+
#SingleInstance Off
#Include ..\Lib\All.ahk

Checks := 0
FixtureHwnd := 0
OnError Fail
OnExit Cleanup
DetectHiddenWindows true
Run '"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\sakura-protocol-fixture.ahk"', , "Hide", &fixturePid
FixtureHwnd := WinWait("EAC Sakura protocol fixture " fixturePid " ahk_pid " fixturePid, , 5)
Assert(FixtureHwnd, "hidden external receiver started")
context := {Hwnd: FixtureHwnd}
for pair in [[0, false], [1, true], [2, false], [3, false], [1, true]] {
    lease := EacSakuraLease()
    Assert(EacSakuraQuery.Call(FixtureHwnd, 0x8056, pair[1], 0, lease, &result), "set receiver state")
    lease.Close()
    Assert(EacSakuraFieldProvider.Editable(context) = pair[2], "fresh menu rejects noop selection readonly, permits editable state " pair[1])
    Assert(EacSakuraQuery.Pending.Count = 0, "successful menu query has no pending lease")
}
lease := EacSakuraLease()
lease.Menu := DllCall("CreatePopupMenu", "Ptr")
menuHandle := lease.Menu
lease.Mutex := DllCall("CreateMutexW", "Ptr", 0, "Int", true, "Ptr", 0, "Ptr")
lease.Locked := true
started := ClockMs()
Assert(!EacSakuraQuery.Call(FixtureHwnd, 0x8055, 150, 1234, lease, &result), "slow query is not accepted")
elapsed := ClockMs() - started
Assert(elapsed < 120, "caller returns before slow recipient finishes")
Assert(lease.Deferred && lease.Menu = menuHandle && DllCall("IsMenu", "Ptr", menuHandle), "timeout retains menu and mutex lease")
Assert(EacSakuraQuery.Pending.Count = 1, "original completion remains tracked")
deadline := A_TickCount + 3000
while EacSakuraQuery.Pending.Count && A_TickCount < deadline
    Sleep 10
Assert(EacSakuraQuery.Pending.Count = 0, "late completion received")
Assert(!lease.Menu && !lease.Mutex && !lease.Locked && !DllCall("IsMenu", "Ptr", menuHandle), "late completion safely frees lease")
lease.Close()
Assert(!lease.Menu && !lease.Mutex, "close is idempotent")
raceLease := HandoffRaceLease()
Assert(!EacSakuraQuery.Call(FixtureHwnd, 0x8055, 150, 1234, raceLease, &result), "handoff race is not accepted as a valid result")
Assert(raceLease.Closed, "completion just before Deferred assignment still closes lease")
Assert(EacSakuraQuery.Pending.Count = 0, "handoff race does not strand Pending")
Sleep 200 ; drain the fixture's real, now redundant completion before exit
lease := EacSakuraLease()
lease.Menu := DllCall("CreatePopupMenu", "Ptr")
accepted := EacSakuraQuery.Call(FixtureHwnd, 0x8057, 0, 0, lease, &result)
if accepted
    lease.Close()
deadline := A_TickCount + 3000
while EacSakuraQuery.Pending.Count && A_TickCount < deadline
    Sleep 10
Assert(!EacSakuraQuery.Pending.Count && !lease.Menu && !lease.Thread, "recipient exit does not strand a lease")
Record("PASS sakura_protocol_checks=" Checks " delayed_call_ms=" Round(elapsed, 2) " AHK=" A_AhkVersion)
Cleanup()
ExitApp 0

Assert(condition, description) {
    global Checks
    Checks += 1
    if !condition
        throw Error(description)
}

ClockMs() {
    static frequency := 0
    if !frequency
        DllCall "QueryPerformanceFrequency", "Int64*", &frequency
    DllCall "QueryPerformanceCounter", "Int64*", &counter := 0
    return counter * 1000 / frequency
}

Record(message) => FileAppend(message "`n", "*", "UTF-8")

Fail(e, *) {
    Record("FAIL " e.Message " at " e.Line "`n" e.Stack)
    Cleanup()
    ExitApp 1
}

Cleanup(*) {
    global FixtureHwnd
    if FixtureHwnd && WinExist("ahk_id " FixtureHwnd) {
        WinClose "ahk_id " FixtureHwnd
        FixtureHwnd := 0
    }
}

class HandoffRaceLease {
    Thread := 0
    Backing := false
    Closed := false
    Deferred {
        get => this.Backing
        set {
            ; Deterministically inject the completion in the timeout handoff
            ; gap. This lease owns no external resources or shared mutex.
            if value
                EacSakuraQuery.Complete(0, 0, EacSakuraQuery.Sequence, 1234)
            this.Backing := value
        }
    }
    Close() {
        if this.Thread {
            DllCall "CloseHandle", "Ptr", this.Thread
            this.Thread := 0
        }
        this.Closed := true
    }
}
