# Project rules

- 日本語で回答する。確認済みの事実と未検証の範囲を区別する。
- このプロジェクトは単独で動作する。元のAutoHotkeyリポジトリや外部の共通Libへ依存させない。
- 個人データの `user/`、取得元の `tools/sources/`、`tests/results/`、`dist/`、実機診断JSONをcommit/pushしない。
- 配布辞書 `data/dictionary.db` と原ライセンス全文はGit管理する。
- 機能や対応アプリの安全制限を変更する場合はREADMEと手動試験表も更新する。
- 他のAHKスクリプトやIMEを終了・再起動しない。

## AutoHotkey v2 verification

- v2 x64実行ファイルのバージョンを確認する。標準候補は `%LOCALAPPDATA%/Programs/AutoHotkey/v2/AutoHotkey64.exe`。
- `.ahk`変更後は `tools/verify.ps1` を実行する。ライブラリ変更は影響する入口も検証する。
- 構文試験は絶対パスの一時Includeラッパー、短時間のExitAppタイマー、`/ErrorStdOut`を使い、終了コード0を必須とする。一時ファイルはfinallyで削除する。
- 変更対象が実行中だった場合だけその本体を `/restart` し、PID・対象CommandLine・単一プロセス・応答・遅延後生存を確認する。開始時に停止していた場合は、起動確認後も停止状態を維持する。
- GUI/IME/アプリ互換性の実入力試験と構文試験を混同しない。長いGUI試験は利用者の操作と競合させない。変更に応じて `-CaseOnly` 等の短い試験を選ぶ。
- `git diff --check` を実行する。成功した試験を理由なく繰り返さない。

## Dictionary / packaging

- 生成はPython 3.8+標準ライブラリで行う。完成ツールの実行時にPythonを要求しない。
- 上流のコミットとSHA256を固定し、辞書のソース・ライセンスを保持する。
- `tools/package_portable.py` の出力に個人設定/DB、診断JSON、ソースZIP、試験結果を含めない。
- 生成辞書を更新する前に本体を終了し、辞書ファイルを閉じる。
