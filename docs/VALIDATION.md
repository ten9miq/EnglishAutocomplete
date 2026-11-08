# 検証記録 — 2026-11-08

動作するネイティブ入力欄向けMVPを検証した記録。先行版の測定結果と、末尾のIME安全判定追加の検証を区別する。Google/MSの実IME入力、ブラウザ等の独自欄への対応をこの記録で確認済みとは扱わない。

## 2026-11-09: 試験fixtureのENG後始末

設定された入力言語は日本語/MS-IMEのみだったが、読み込み済み配列には日本語`0x04110411`と英語US`0x04090409`が存在した。常駐本体はレイアウトを読み込み・切替しない。2種類のfixtureには英語USを読み込む処理があり、解除処理がなかったため残留の原因候補と判断した。元の発生操作を直接観測したものではない。

`tests/FixtureKeyboardLayout.ahk`で開始前の配列を記録し、通常終了時に元の配列へ戻した後、そのfixtureが追加した英語USだけを解除するよう修正。強制終了時のOnExit実行は保証しない。

- `tools/verify.ps1`はAHK v2 x64 2.0.28で4入口の構文検証、core 80 / IME 56 / navigation 60 / UIA 369 / Sakura 27 checksがすべて終了コード0。
- 一時ドライバーから両fixtureを開閉し、開始前にENGなしの場合は終了後に消え、ENGありの場合は保持される4通りを実OSで確認。文字入力は行っておらず、IME変換の実入力試験ではない。一時ファイルはfinallyで削除。
- 登録されていなかった英語USを解除し、最終的な読み込み一覧は日本語のみ。元のAHK 11プロセスと日本語/MS-IME設定を維持。本体の変更・再起動は不要。
- `git diff --check`成功。

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

- Google日本語入力/MS-IMEをそれぞれ使った実入力。開いた半角英数の条件付き許可は末尾の追加検証を参照。実IME変換中のUIA範囲判定は未検証。
- 実際のWindowsメモ帳・サクラ・Excel・Chrome・Brave・VS Code・Electron・Google各Webアプリ。現版で独自コントロールは未対応。
- 物理キーボード、全マウス操作、IME表示GUIとの視覚的重なり、混在DPI・複数モニター、スリープ復帰、長時間常駐。
- 補完だけの環境での比較。既存IMEを停止しない条件のため採取していない。共存中の各プロセス値だけを記録。
- 既存IMEのUIA/IA2呼出し回数の厳密な動的計測。先行版では補完側に呼出しがなかったが、末尾の変更で開いた半角英数の安全確認用UIA照会を追加した。
- Ahk2Exeビルド、AHK Portableランタイムそのものを含む配布物の生成、SCOWL size70生成物の配布・実行性能。size70の生成オプションは実装済み。

手動試験は [MANUAL_TESTS.md](MANUAL_TESTS.md) を使用する。

実機診断JSONは利用者のローカル環境にだけ保存し、GitHubとPortable ZIPには含めない。上記は分離前の測定記録であり、PIDや当時のプロセス構成を現状とは扱わない。

## 2026-11-08: IME ON・半角英数の条件付き許可

`ImeStateProvider`を変更し、mode 0/16のみ、フォーカスHWNDのTextEditPattern.GetActiveCompositionがS_OKかつ範囲nullのとき許可する。UIA前後のIME一致、HWND/PID/フォーカス、本文/選択位置を照合する。候補キーの条件判定とCommitでも再照会し、開閉/変換モードを含む状態識別子が変われば古い候補を拒否する。未確定範囲が非null、パターン非対応、取得失敗、タイムアウトは候補/学習/確定を止める。接続/取引タイムアウトはそれぞれ50ms。このWindowsでは20ms設定がE_INVALIDARGとなることを確認した。ツリー探索や他プロセスのHIMC照会は行わない。

AHK v2.0.28 x64、Windows 10.0.26300。実行した検証:

```powershell
./tools/verify.ps1 -Ahk "$env:USERPROFILE/AppData/Local/Programs/AutoHotkey/v2/AutoHotkey64.exe" -CaseOnly
./tools/verify.ps1 -Ahk "$env:USERPROFILE/AppData/Local/Programs/AutoHotkey/v2/AutoHotkey64.exe" -ImeIntegration
git diff --check
```

| 対象 | 結果と範囲 |
|---|---|
| 両入口の構文 | 一時絶対Includeラッパー、短いExitAppタイマー、/ErrorStdOutでexit 0。finallyで削除 |
| 既存core | 75 checks PASS |
| 既存短時間integration | 初回18 checks PASS。ENGで実InputHook、語尾追加、大小文字を確認。その後の再実行では物理入力の混入で失敗したため、最終一括検証の合格項目には含めない |
| IME安全条件 | `tests/ime.ahk` 48 checks PASS。IME状態と未確定範囲の判定結果を模擬し、0/16許可、他モード/未知/変換中の拒否、照会中の状態変更、候補識別子を確認 |
| 外部RichEdit/UIA統合 | `tests/ime-integration.ahk` 22 checks PASS。実UIAで未確定範囲null、フォーカス変更の拒否、標準Editの非対応を確認。IME状態と文字通知は模擬、専用欄の本文設定と実SendTextで語尾追加・モード変更/変換中/未知状態の拒否・学習停止を確認 |
| 常駐状態 | 開始時は本体停止。他のAHK/IMEを終了・再起動せず、本体は停止状態を維持 |

実MS IMEを専用fixtureスレッド内で選択してONの半角英数を設定する試験も試みたが、照会結果はIMEClosedとなり、実ON状態を再現できなかった。この試行は対応確認の合格に含めない。実IMEの変換範囲・物理入力・既存アプリでの確認は手動試験表に残す。途中で利用者の操作によりfixtureがフォーカスを失った試験は安全中断し、文字通知を模擬する短い試験へ変更した。既存のキーボード試験の再実行でも予定外の文字とキー通知が混入したため、操作と競合する再試験を止めた。最終の`verify.ps1 -ImeIntegration`は構文・core 75・IME条件48・UIA統合22がexit 0。自動試験で実IMEの動作を確認したとは扱わない。

この環境では`RICHEDIT50W`で照会可能、標準`Edit`ではTextEditPattern非対応だった。したがって標準EditのIME ON・半角英数は引き続き停止する。UIA対応状況は入力欄ごとに異なる。外部照会と送信の間の状態を原子的に固定する保証はなく、実IME・アプリ別の試験と区別する。

### 同日: 常駐本体と実MS IMEの画面操作試験

利用者の依頼により実際の`EnglishAutocomplete.ahk`を起動し、別プロセスの使い捨てRichEditで試験した。試験中だけAHKプロセスの入力欄を許可し、当該欄のLearningは0にした。終了時に設定をbyte一致で復元し、元の設定で本体を起動状態にした。他のAHKやIMEは終了・再起動していない。

- 試験窓内でアクティブなTSFサービスのCLSIDを読み、Microsoft Japanese IME (`{03B5835F-F03C-411B-9CE2-AA23E1171E36}`)、HKL `0x4110411`であることを確認した。
- 実際のMS IMEが半角英数の状態で、キー入力により`compu`を作ると常駐本体の候補が表示され、Ctrl+Alt+Spaceで`compulsion`に補完された。既存の先頭文字は保持された。ただしこのときの実測値はIMMとWM_IME_CONTROLの両方で`open=0 / mode=0`であり、IME ONの新規分岐の合格には含めない。
- Alt+Backquoteで実際に`open=1 / mode=9`へ切り替わった。`c`キーで全角の未確定文字が生じ、自己プロセスのIMM照会でcompositionBytes=2となり、MS IME自身の候補が表示された。この間、英文補完の候補は表示されなかった。
- ONのひらがな状態から試験窓の自己HIMCに対して半角英数へ切り替えたところ、直後は`open=1 / mode=0`、次の定期照会では`open=0 / mode=0`となった。両照会方式で一致。この試験欄ではONの半角英数を持続させて入力する条件を確立できなかったため、**実MS IME ON・半角英数での補完は依然として未確認**とする。

入力と確定はComputer Useによる合成キーであり、物理キーボードの試験ではない。文字列一括入力では候補が出なかったため、成功判定には1文字ずつのキー入力と実確定キーを使用した。状態表示とログの一時AHKは`tests/results/`内だけに置き、配布・Git管理の対象外とする。使い捨て試験窓は終了した。

## 2026-11-08: サクラエディタ本文への対応

原因はIMEではなく、FieldGuardがサクラの独自本文`SakuraView182`を対象外としていたこと。Sakura 32bit 2.4.3.7173で確認した。専用プロバイダーを追加し、版と実行ファイルの一致、編集可能・選択なし、実カーソルと行近傍の二重照合を必須にした。共有データ版182以外は拒否する。設計根拠と固定リビジョンはARCHITECTURE.mdを参照。

| 検証 | 結果 |
|---|---|
| 両入口の一時Include構文検証 | AHK v2.0.28 x64、/ErrorStdOut、両方exit 0、finally削除 |
| 既存core / IME条件 | 75 / 48 checks PASS |
| サクラ用非表示プロトコル試験 | 27 checks PASS。無応答のno-op拒否、選択/編集不可の拒否、遅延結果の拒否と完了後解放、timeout引渡し境界の再現、受信側終了時の回収、再解放の冪等性 |
| 既存RichEdit/UIA統合 | 22 checks PASS。実UIAと模擬IME状態による既存安全条件の回帰 |
| 実サクラでの本文照会 | 空の専用文書と`confi`を照会。論理位置0:5、Before=confiと実画面が一致 |
| 実サクラでの候補・確定 | 使い捨て文書に半角英数で1文字ずつ`compu`を入力し候補を表示。Ctrl+Alt+Spaceで`compulsion`へ語尾だけ追加。保存後の内容も`confi compulsion`と一致 |
| 実サクラでの停止条件 | Ctrl+Aによる選択中とビューモードでRead=false、SakuraSelectionOrReadOnly。試験後ビューモードは解除 |
| 実IME状態 | サクラの対象スレッドでHKL=0x04110411、IMEClosed/open=0を確認。IME ONの半角英数を確認したとは扱わない |

GUI試験はComputer Useの合成キーと専用ファイル`tests/results/sakura-live-test.txt`だけを使用し、既存の未保存文書を変更していない。物理キーボード試験、64bit Sakura、他の共有データ版、矩形選択・分割・長い行などの組合せは未実施。自動試験では150ms遅延の照会に対して約23～30msで呼出元が拒否し、受信完了後にリソースが回収された。実アプリ全体の候補表示P95を再測定した結果ではない。

変更前に補完本体は稼働中だったため、本体だけを/restartして反映した。無関係なAHKとIMEは終了・再起動していない。`git diff --check`を実施し、取得元と試験データはGit/配布対象外のまま保持する。

## 2026-11-08: 候補の文字切れとモニター別DPI

原因は`SetFont`へのポイント数にモニター倍率を掛けたうえで、AHK内部でもシステムDPIによるポイント→ピクセル換算が行われること。固定計算の行高から拡大文字がはみ出していた。入力先の主HWNDからのDPI取得も、モニターを跨ぐ入力先では不適切だった。

`Lib/Dpi.ahk`を追加し、GUI作成・表示をPMv2コンテキスト内で行って呼出元を復元する。キャレットHWNDの論理座標を物理ピクセルへ変換し、その点のモニターを選ぶ。モニター内に非表示PMv2プローブHWNDを新規作成して実効DPIを取得する。フォントは`-MulDiv(FontSize,DPI,72)`の高さで明示生成し、計測・描画で同じHFONTを使用。行高と幅を実測し、単行・末尾省略・作業領域内への補正を行う。旧フォントをコントロールから外してから破棄し、古い位置の30msキャッシュは使用しない。

| 検証 | 結果と範囲 |
|---|---|
| 必須検証 | AHK v2.0.28 x64、両入口の一時Include構文検証exit 0、core 75・IME条件48・サクラprotocol 27 checks PASS |
| DPI/配置 | `tools/verify.ps1 -Dpi`、243 checks PASS。96/120/144/168/192/216/240/288DPIのnative font高さ、負座標/画面端/狭い作業領域での配置、選択行の表示を検証 |
| 実モニター | 4台すべて144DPI（150%）。作業領域は(0,0)-(3840,2112)、(-3840,1089)-(0,3201)、(3840,1067)-(7680,3179)、(0,2160)-(3840,4272)。右下端への候補780×207px配置、子ラベルの収まり、フォント一致、末尾省略スタイル、NoActivateを確認 |
| 入力先のDPI認識方式 | 非表示のunaware/system aware/PMv2テストHWNDで、変換結果が物理ウィンドウ矩形と一致することを確認 |
| 目視 | 専用プレビューで日本語・英字・太字の上下が欠けず、長い訳文が末尾省略されることを確認。ユーザー文書や表示設定は変更していない |

異なる実モニター倍率の組合せ、表示中の倍率変更やモニター着脱、物理キーボード、長時間負荷は未検証。100～300%は実フォント・計算配置の試験であり、Windowsの表示設定を切り替えて確認したものではない。一時プレビューとインベントリは`tests/results/`内だけに置き、Git/配布対象外とする。

## 2026-11-08: 9候補・IME優先・標準キーによる選択

候補数の既定を9件、次候補をTabに変更。Ctrl+Alt+Tabは登録しない。IME OFFで候補があるとき、Spaceで先頭の選択を開始し、Space/Tab/↓で次、Shift+Space/Shift+Tab/↑で前へ移動する。選択モード中のEnterで確定、選択前は入力先へ渡す。IME ONは半角英数を含め常駐本体の処理を停止し、ネイティブIMEへ任せる。

`tests/navigation.ahk`はホットキー登録も文字送信もしない状態遷移試験。9候補間の循環、最初のSpace、Enterの条件、通知の順序、Esc、アプリ無効・IME等の安全判定失敗、アプリ別ImeStyle無効を52項目で確認した。構文は両入口exit 0、core 80・IME条件56・navigation 52・サクラprotocol 27 checks PASS。既存の長いGUI integrationは期待値を更新したが、この変更後の実入力試験は未実施。

Chrome/Codex等へ一般化するため、UIAのfocused要素・編集可否・collapsed選択・限定した近傍・祖先とHWNDの照合方式を調査した。専用ローカルフォームをChromeに開いたが、画面操作ツールが現在のブラウザーURLを十分に確定できず、Computer Useが停止した。その後は画面操作を再開していない。汎用UIA入力プロバイダーは未実装で、Chrome/Codexのプロファイルや安全制限は緩和していない。これらのアプリへの対応は未完了。

## 追加: Chrome/CodexのUIA入力欄

上の未実装状態から、`Lib/UiaFieldProvider.ahk`を実装した。安全なfocused Edit、前面ウィンドウの祖先との一致、runtime identity、編集可否、空選択、入力欄内の直前128/直後1文字、UIAキャレット矩形を必須にする。別欄・別位置・本文変更・IME変更・入力割込みを確定前に再確認する。既定プロファイルをChrome/Brave/Edge/ChatGPT.exe/Codex.exeで有効にし、これらのLearningは0にする。IME ON優先と9候補・標準キー操作は維持する。

専用プロファイルのChrome156をlocalhost:9222だけでデバッグ接続し、localhost:8327の専用フォームURLをブラウザープラグインで照合した。実APIの能力照会では通常inputのControlType=50004、focus/focusable/enabled=true、password/offscreen/ValueReadonly=false（正しいVT_BOOL）、TextPattern、Readonly属性false、単一collapsed選択、矩形4要素、TextEditPatternが取得できた。Chromeでの完全なField.Readと実入力は、前面フォーカスを確保できず未確認。

Windows画面操作ツールは、今回も現在URLを安全に確定できず停止した。その後、同ツールの操作や別手段でのキー送信は行っていない。既存Codex入力内容の読取り・操作も行っていない。Codex等の実入力互換性は利用者環境での確認を要する。

`tests/uia.ahk`は既存アプリに接続しないヘッドレス試験。安全属性、password/readonly/Documentの拒否、選択/境界/長過ぎる文字単位、再照会中の変化、同じHWNDの別欄、caret欠落、再入/RPC失敗を範囲モデルで確認し、VARIANT/BSTR/SAFEARRAY/Interface/deadlineは所有するCOMスタブ経由で検証した。210 checks PASS、exit 0。両入口の構文、core 80・IME56・navigation52・サクラprotocol27もPASS。

## 2026-11-09: Codex実入力での修正と確認

利用者の明示的な実入力試験依頼と画面操作ツールのアプリ承認後、Codexの空の入力欄を使った。元からあった下書きはなく、入力した試験文字だけを終了後に消した。メッセージ送信は行っていない。

最初はIME ONで停止。その後IME OFFにしても、TextPatternの選択位置がDocumentRangeより後と比較されて停止していた。数値はstart=1/end=1、DocumentRangeは非空。GetEnclosingElementからの祖先確認では、選択・DocumentRangeの両方が同じfocused Edit内に属した（診断Flags=24）。この端点比較を無条件許可せず、読む各範囲全体の要素包含を証明する経路を追加した。

- 移動範囲が入力欄外なら、本文を読まずに二分探索し、入力欄内に含まれる最大の近傍だけを採用する。文字数上限とreadonly確認を維持。
- 右範囲が空の場合、文中の誤判定を避けるため、そのEdit自身のValueだけを上限32767文字で一時取得する。包含を証明したcaret左全体と完全一致し、再照会時にもValueが同じ場合だけEOFとする。ページ全体の本文は取得しない。返却・保持するのは近傍とEOF長であり、Value全文をログ・辞書へ保存しない。
- 同じ入力欄の証明済みEOFなら、その長さで位置を比較する。rich fieldの古いrange anchor表現だけに依存しない。
- UIAの一時的な更新ずれ/IME照会タイムアウトは最大350msだけ再照会。実際のIME ONは停止を維持。
- 表示後の定期更新と非破壊の候補移動はfocus/IME等の軽量確認を使用。確定時は本文・位置・focus・IME・入力世代をすべて再検証する。
- 変換中のEnterは検証失敗でもチャット送信へ流さず、候補操作を取り消す。既知のIME ONではMS IMEへ返す。

**Codexの実画面で確認:** 1文字ずつ`confi`を入力→9候補表示→Spaceで選択開始→Tabで2番目`confident`へ移動→Enterで入力欄が`confident`になること。画面とUIAの入力欄Valueを照合し、本体のCommitCount=1、Navigating=0、Hook=1を診断で確認。試験文字を消しEscで候補を閉じた。通常のメッセージは増えていない。Computer Useの合成OSキーによる試験であり、物理キーボードではない。

追加試験はUIA 369・navigation55 checks PASS。EOF誤判定、範囲外trialの本文非取得、readonly/Value変更/不明属性/RPC失敗を含む。診断は候補数・選択位置・確定回数・安全判定・COM段階などの数値だけを公開し、入力文・候補語・URL・タイトルを記録しない。

Chromeの実キー試験も専用プロファイルとlocalhostフォームで準備し、ブラウザープラグインではURL `http://127.0.0.1:8327/uia-fixture.html`を確認した。Windows画面操作ツールは、get_windowとactivate_windowまでは成功したが、get_window_stateで「現在のブラウザーURLを安全に確定できない」として当該ターンを停止した。以後Chromeへのキー送信は行っていない。Chromeの候補表示・選択・Enter確定の実入力確認は残課題。専用Chromeと試験HTTPサーバーだけを終了し、通常のChromeや無関係なAHKを維持する。

## 2026-11-09: Spaceの候補操作を廃止

利用者の指定により、Space/Shift+Spaceの候補操作エイリアスとconvertアクションを削除した。InputHookのSpace通知も無視せず通常の単語区切りとして処理し、選択中でも空白入力で候補を終了する。Tab/↑↓による選択、選択モードEnter、Ctrl+Alt+Spaceの明示確定は維持する。navigation試験はSpaceが未登録であること、実際の区切り通知がprefixを終えること、選択中のSpaceが確定しないことを検証する。GUIへの入力を伴う再試験は実施しない。

## 2026-11-09: 初期未選択・初回Tab・Enter押下の所有

Selected=1で初期表示していたため、未選択の予測表示とEnter確定可能な選択モードが見た目で区別できなかった。Selected=0を未選択とし、生成・通常入力・Hide/Resetで必ず未選択に戻す。初回Tab/↓は1件目を選択、初回Shift+Tab/↑は最後を選択。選択前Enterは通常入力のみ。Ctrl+Alt+Spaceと番号キーは明示的な確定操作として維持する。

別の問題経路として、確定でHideした直後にCanInterceptがfalseとなり、同じEnter押下の後続リピートが通常改行/送信へ流れることを確認した。抑止済みキーはInputHook通知を通らない場合があるため、InputHookだけで解放を追跡しない。受理時にrelease serialをarmし、Enter actionは1回だけ実行する。専用Enter-upと通常upのpassive listenerで解放を追跡し、消費済みpressのrepeatだけを解放まで抑止する。keyupがhandlerより先でもserial差でラッチを残さない。Commit中の再入を防ぎ、既知IME ONでの新しいEnter押下はnative IMEへ渡す。

- ヘッドレスnavigation: 60 checks PASS。初期未選択・初回Tab1・2回目Tab2・循環・確定後未選択・同押下repeat・解放後通常Enter・早いkeyup・IME ON新押下・Space非確定等。
- `tests/selection-integration.ahk`: fresh別プロセスの専用native multiline Editに、実InputHook/ホットキーを通るSendLevel1のキーだけを送った。24 checks PASS、約2079ms、AHK v2.0.28、exit0。
- 実入力結果: 初期9候補/Selected0/マーカーなし、未選択Enterは補完0回で改行のみ、Tabで1件目、Enter downは確定1回/改行0、repeat down3回でも内容不変、keyup後の別Enterは通常改行のみ、選択中Spaceは空白だけ。
- sandbox内のworker起動はDLL再配置エラーで未実行となったため、Rootが通常Windowsセッションで同じ試験を実行した。利用者文書への入力や無関係AHK/IMEの停止・再起動はない。これは専用Editでの合成OSキー試験であり、Chrome/Codexや物理キーボードによる長押しの確認とは区別する。

`tools/verify.ps1 -SelectionIntegration`で短時間試験を再現できる。構文と既存core/IME/UIA/サクラ回帰も通過。稼働中だった補完本体だけを/restartして反映する。
