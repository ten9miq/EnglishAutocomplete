# 検証記録 — 2026-11-08

動作するネイティブ入力欄向けMVPを検証した記録。Google/MSの開いた半角英数、ブラウザ等の独自欄への未対応はREADMEの制限どおりであり、この記録で対応済みとは扱わない。

## 環境・コマンド

- Windows 11 x64、OSの報告値 `10.0.26300.0`。
- AutoHotkey `%LOCALAPPDATA%/Programs/AutoHotkey/v2/AutoHotkey64.exe`、v2.0.28。
- OSの `C:/Windows/System32/winsqlite3.dll`、ファイルversion 3.53.4。追加SQLite DLLは配布しない。
- Python `%LOCALAPPDATA%/Programs/Thonny/python.exe`、3.14.4。生成とPython試験でのみ使用。
- 既存GoogleIME風入力モード表示PID 4060と他のAHKスクリプトが稼働したまま測定した。ユーザーの他アプリも動いている通常セッション。専有ベンチマーク環境ではない。

```powershell
& "$env:LOCALAPPDATA/Programs/Thonny/python.exe" tools/build_dictionary.py
& "$env:LOCALAPPDATA/Programs/Thonny/python.exe" -m unittest discover -s tests -p 'test_*.py' -v
./tools/verify.ps1 -Integration
./tools/measure_resident.ps1
git diff --check
```

サンドボックス内のAHK起動はシステムDLL再配置エラーになったため、AHKの実機試験は通常のWindowsセッションで実施した。構文試験ではGUI実行ファイルを `Start-Process -PassThru` で待ち、終了コードを採取した。PowerShellの単なる`&`はGUIプロセスの終了を待たないことがあるため、早く一時ラッパーを削除しない。

## 結果

| 試験 | 結果 | 対象 |
|---|---|---|
| 構文 | 両入口の一時Include wrapperが終了コード0、finallyで削除 | `EnglishAutocomplete.ahk`, `ManageDictionary.ahk` とそこから読む全Lib |
| Python | 9 tests PASS | 実辞書の抽出・重複・大小文字・頻度・活用形・訳・phrase分離・prefix索引上限/検索計画・速度・再生成のbyte一致 |
| AHK core (最終版) | 75 checks PASS / exit 0 | 本物のSQLite、Unicodeパス、昇格、未知語、手動技術語、CamelCase、回数、重複、永続化、禁止、削除、頻度初期化、DB破損/ロック/未来schema、入力状態、境界、順位、検索P95。文字列比較は厳密比較 |
| AHK基本integration | 63 checks PASS / exit 0 (表記比較強化前) | 別プロセスの実Edit欄、実InputHook、NoActivate、語尾だけの挿入、直後の入力、実確定/移動/番号/Escキー、BS、Delete、移動、フォーカス、アプリ側変更、ショートカット、通常Tab、パスワード/readonly拒否、学習、メール拒否、全体OFF/ON、高速合成入力、候補表示 |
| AHK短時間integration (最終版) | 18 checks PASS / exit 0 | `--case-only`。実OSのENG判定とnative安全判定、小文字・全部大文字・先頭大文字・混在・CamelCaseを実際の入力欄で厳密比較。学習後も元表記が維持されること |
| 常駐 | PASS | `/restart`した新規本体が1個、正しいコマンドライン、WM_NULLの200ms応答、遅延後生存 |
| 既存プロセス維持 | PASS | 測定前の無関係AHK PID 10個が測定後も存在。既存IMEを含め停止・再起動していない |

実入力試験は作成した専用fixtureだけにSendLevel 1の合成イベントを送った。本体のSendLevel 0がInputHookへ戻らないことを検証した。対象欄は別プロセスであり、各文字送信前に試験窓のフォーカスを確認する。実ユーザーの文書・認証情報には入力していない。試験用ウィンドウとDBは終了時に削除し、元のフォーカスへ戻した。

最終のキーボード/GUI試験では無関係な物理ホイール操作を分離するため、製品のマウス監視を試験インスタンスだけで無効にした。製品入口は常に通常のマウス監視を有効にする。マウス競合を含む完全な物理入力試験としては扱わない。途中の試験では実際のLButton/WheelDown割込みを検出して候補を破棄・安全中断したが、これは体系的なマウス試験の代用ではない。

大小文字の最終修正後は、通常の`=`比較が表記の差を見落とすため`==`へ変更し、自動学習が元表記を上書きしないよう修正した。ユーザーの作業と長時間競合しないよう、必要なcoreと短い表記試験に絞って再検証した。全項目を含む長いintegrationは最終修正後には完走確認していない。途中の中断・タイムアウトを合格件数へ含めていない。

## 性能

AHKの細粒度測定はQueryPerformanceCounterを使用。SQLite辞書は113,438語、17,707,008 bytes、prefix行271,819。Pythonの再ビルド結果は配布物とbyte一致。

| 指標 | 最終測定値 | 条件・範囲 |
|---|---:|---|
| 辞書open / schema照会 | 0.400ms | 最終版AHK core。全辞書をRAMにロードする方式ではない |
| 検索P95 | 2.826ms | 最終版AHK 1000検索。静的索引+SQLite個人辞書+順位付け。短/長/未知prefixを混在 |
| 検索P95 (参考) | 0.6173ms | Python 3000検索、3文字prefix、静的索引のみ。AHKの値とは別 |
| 本体初期化 (参考) | 29.781ms | 基本統合版のDB/GUI/Hook等。プロセス生成時間は含まない |
| プロセス生成→応答窓 | 306.28ms | 最終版の実常駐入口、PowerShellから起動しhidden AutoHotkey窓のWM_NULL応答まで |
| 確定処理 (参考) | 13.454ms | 基本統合版の1回。入力欄/IME照合と語尾送信。P95とは主張しない |
| Win32キャレット取得P95 (参考) | 0.039ms | 基本統合版100回、キャッシュを強制回避。GetGUIThreadInfo+ClientToScreen |
| GUI更新P95 (参考) | 14.355ms | 基本統合版100回、選択表示を更新する専用fixture |
| 候補表示P95 (参考) | 82.780ms | 基本統合版30回。最後の合成キー送信開始→候補GUI表示。キー送信の待ち時間も含む |
| core試験後Working Set | 21.63MiB | 最終版テストプロセス。1000検索後 |
| 常駐本体Working Set / Private | 19.22 / 4.73MiB | 最終版の起動直後の3秒待機測定。プロセス単位 |
| 補完の待機CPU | 1.0375% | 最終版、1論理CPU基準、3秒。全CPU平均値ではなく短時間の粗いサンプル |
| 既存IME CPU (共存中) | 1.0375% | 最終版との共存中、同じ3秒・1論理CPU基準 |
| 既存IME CPU (補完起動前→共存、参考) | 1.0354%→1.0370% | 初期の基本統合版、各3秒。短いサンプルなので統計的な負荷差の証明ではない |

検索P95 10ms以内の目標は最終版で満たした。通常表示P95 100ms以内は基本統合版の専用fixture測定で満たしたが、大小文字の最終修正後には表示P95を再採取していない。すべてのアプリ・IME・DPIや長時間負荷での達成は未確認。高速入力は基本統合版の合成イベントの連続入力で欠落がないことを確認したが、物理キーボードの極端な連打・アプリ固有の入力遅延測定は未実施。

常駐計測の詳細は `resident-metrics.json`、比較用の初期計測は `resident-metrics-initial.json`。最終修正版の新規本体PIDは **45356**、1個、対象コマンドラインは `/restart .../EnglishAutocomplete/EnglishAutocomplete.ahk`、WM_NULL応答と約3秒後の生存を確認。修正前の本体PID52496だけを置き換え、既存IMEはPID **4060**のまま。PIDは再起動で変わるため、将来の現状確認には再計測する。

## 未検証・残課題

- Google日本語入力/MS-IMEをそれぞれ使った実入力、開いた半角英数の安全な許可、TSF変換中の厳密判定。
- 実際のWindowsメモ帳・サクラ・Excel・Chrome・Brave・VS Code・Electron・Google各Webアプリ。現版で独自コントロールは未対応。
- 物理キーボード、全マウス操作、IME表示GUIとの視覚的重なり、混在DPI・複数モニター、スリープ復帰、長時間常駐。
- 補完だけの環境での比較。既存IMEを停止しない条件のため採取していない。共存中の各プロセス値だけを記録。
- 既存IMEのUIA/IA2呼出し回数の厳密な動的計測。補完側にこれらの読込・呼出しがないことはソースで確認。
- Ahk2Exeビルド、AHK Portableランタイムそのものを含む配布物の生成、SCOWL size70生成物の配布・実行性能。size70の生成オプションは実装済み。

手動試験は [MANUAL_TESTS.md](MANUAL_TESTS.md) を使用する。

実機診断JSONは利用者のローカル環境にだけ保存し、GitHubとPortable ZIPには含めない。上記は分離前の測定記録であり、PIDや当時のプロセス構成を現状とは扱わない。
