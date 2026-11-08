---
type: decision
status: current
summary: "英文補完は既存IME表示を変更せずWin32だけで開始し、InputHookと実テキストの一致を語尾挿入の必須条件とする"
tags: "autocomplete, ime, inputhook, caret, sqlite, asynchronous"
paths: "Lib/Application.ahk, Lib/FieldGuard.ahk, docs/ARCHITECTURE.md"
last_verified: "2026-11-08"
verified_commit: ""
freshness: version-sensitive
---

# 英文補完を安全なネイティブ入力欄から始める理由

この文書は元のAutoHotkeyプロジェクトでの調査・設計判断を移したもの。IME表示スクリプトは外部の任意の共存相手であり、本プロジェクトの実行依存ではない。

## 判断

既存IMEインジケーターと新規英文補完を統合せず、補完側は候補表示時だけGUIThreadInfoで位置を取得する(C案)。既存側はCaretGetPos/MSAA/UIA等を組み合わせるが、新規側がUIAv2を追加で読み込まなければUIA/IA2の重複探索は発生しない。共通ライブラリをIncludeするだけではプロセス間のキャッシュは共有されない。将来拡張するなら既存表示からフォーカス識別子・世代・鮮度を含むIPC配信(B案)を検討する。

本MVPは通常Edit/RichEditのみ許可する。パスワード判定、選択状態、実テキスト、HWND+focus、IME状態を確認できない欄では停止する。既存表示の「A」は、TSFの未確定入力が存在しないことまでは保証しない。Google/MSが開いた半角英数を許可するには別の変換中判定を実証する必要がある。現版はENGと閉じた日本語IMEだけ許可し、目標仕様の一部が未達であることをREADMEで明示している。

## 非同期InputHookの注意

実テキストの更新がOnChar通知より先になることが、別プロセスのEdit fixtureでも観測された。途中の一致失敗で直ちに観測中の単語を消すと、後から届いた末尾の文字だけが新しい単語になり、補完が単語境界まで復帰しない。対策は、不一致の間はGUIと確定を停止し、64文字に制限した未信頼の現単語を次のイベントまで保持すること。新しい通知が来ても実テキストに一致するまでは候補を表示しない。フォーカス・選択・ショートカット・IME等による無効化は別途行う。単語は空白等の境界でリセットされる。

確定時は実テキストを再照合して語尾だけ挿入し、Backspaceで既存文字を削除しない。L0でInputHook自身の全文バッファを無効にし、I1とSendLevel 0で補完の自己再帰を防ぐ。修飾キーの状態は非同期通知時点のGetKeyStateだけでは合成ショートカットを捉えられず、OnKeyDown/Upの追跡も必要だった。一方SendTextが修飾をSendLevel 0で復元するとそのKeyUpはI1に来ないため、通常文字通知と明示Reset時に古い修飾追跡をクリアする。

この機能の大小文字判定・実テキスト照合・表記テストにはAHKの厳密比較`==`を使う。`prefix = StrUpper(prefix)`は小文字でも真となり、普通の補完が大文字の語尾になる。テストまで`=`を使うと不正な大小文字を検出できない。`ApplyCase`、`FieldGuard.Matches`と実入力欄を比較するテストを厳密比較へ統一し、小文字・全部大文字・先頭大文字・混在・CamelCaseを別々に確認する。

大文字で一度補完した使用履歴が次回の普通表記を変えてしまわないよう、使用回数更新では登録済みの元表記を上書きしない。手動登録を明示し直した場合だけ表記を更新する。標準語は自動学習の表記より標準辞書の表記を優先し、手動登録だけがそれを上書きできる。coreの元表記保持試験と`verify.ps1 -CaseOnly`で確認する。

## 検証・再現

- `tests/core.ahk`: 本物のWindows SQLiteを使い、大小文字も厳密に比較する自動試験。
- `tests/integration.ahk` + `fixture.ahk`: 別プロセスの専用Editの実入力試験。各文字前に対象窓を確認する。無関係なホイール操作の影響を分離するため、この試験インスタンスだけマウス監視を無効にする。本体入口は有効。
- `tools/verify.ps1 -Integration`: 100ms一時Include構文検証、実AHK試験。一時ラッパーをfinallyで削除する。
- WindowsではGUI版AHKをPowerShellの`&`で呼ぶだけだとプロセス完了を待たずラッパーを削除してしまうことがある。Start-Process -PassThru と終了待ちで終了コードを採取する。
- 測定条件・実測値・未対応アプリは `docs/VALIDATION.md` とREADME。

## 外部根拠

- [AutoHotkey v2 InputHook公式仕様](https://github.com/AutoHotkey/AutoHotkeyDocs/blob/v2/docs/lib/InputHook.htm)、確認2026-11-08。L0/I1/V、OnChar/キー通知、SendLevelによる自己入力の除外。
- [AutoHotkey v2比較演算子](https://github.com/AutoHotkey/AutoHotkeyDocs/blob/v2/docs/Variables.htm#equal)、確認2026-11-08。`=`と`==`の大小文字の扱いの差。
- [EM_GETPASSWORDCHAR](https://learn.microsoft.com/en-us/windows/win32/controls/em-getpasswordchar)、確認2026-11-08。通常Edit/RichEditのパスワード文字判定。
- [EM_GETSEL](https://learn.microsoft.com/en-us/windows/win32/controls/em-getsel)、確認2026-11-08。選択位置と65535を超えた場合の制約。本MVPは32767文字で停止する。

## 再検証する条件

UIA/TSF/IA2や新しいフィールドプロバイダーの追加、既存表示との統合/IPC導入、AHK・Windows更新、対象アプリ拡大。現在の制限を外す際は入力欄の安全性と実テキスト照合を位置取得とは独立に検証する。
