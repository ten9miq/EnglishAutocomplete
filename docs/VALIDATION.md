# 検証記録 — 2026-11-08

## 2026-11-09: 選択した学習候補の削除

選択した自動学習候補をCtrl+Deleteまたは行右端の×で削除できるようにした。個人DBの`manual=0/blocked=0/uses>0`だけをトランザクションで削除する。配布辞書は変更せず、その語の使用履歴だけ消す。手動登録・禁止を保護し、未知語は後で再学習できる。削除後は未選択に戻し、保留観測を消して即時の再学習を防ぐ。

- AHK v2 x64 2.0.28。最終版の`tools/verify.ps1 -Dpi`：構文4入口、core102・IME56・navigation107・forget29・UIA372・Sakura27・DPI455をすべて終了コード0。DB永続化、後からの再学習、通常辞書の残存/加点リセット、手動登録/禁止の保護、DBロック失敗時の表示維持、未選択/IME/入力世代/キャレット/フォーカス/行差替えの拒否を確認。検索P95は1.644ms（1000件、非専有環境）。
- `tests/forget-integration.ahk --wait-foreground`：使い捨てWin32 Editに実InputHook/実ホットキー/実マウスクリックで20項目PASS。未知語のCtrl+Delete・長押し抑制・×クリック、本文不変、フォーカス維持、配布語履歴削除後の候補保持、手動語の×非表示を確認。自動起動では前面取得できず、最初の試行は入力前に中止。利用者が試験窓の一番上の入力欄をクリックした後だけ入力試験を開始した。待機込み45.3秒、実操作は数秒。試験用DBと窓を後始末し、実ユーザーDBは試験データで変更していない。
- 先行の`-SelectionIntegration`も前面取得ガードで入力前に中止。選択/Enter等の既存実操作の成功記録は以前の節、今回追加した削除の実操作20項目と状態遷移107項目とは区別する。Chrome/Codex等における削除の実入力確認は未実施。
- DPIは100～300%の計算、実4モニター（150%）のGUIジオメトリを検証。×の表示対象、行位置、文字との非重複、NoActivate、未選択時の消去を追加確認。描画中は×の削除対象を無効にし、配置終了後に新しい対象を公開する。
- 本体のみPID55736→27032、最終の描画保護追加後27032→59340へ`/restart`。各回で正しいCommandLine・単一プロセス・WM_NULL応答・3秒後生存を確認。最終診断Status=9（有効、InputHook動作中）。他のAHK10プロセスは同じPIDを維持。個人データや診断JSONのcommit/pushは行っていない。
- `git diff --check`成功。README、手動試験表、設計メモ、TODOを更新した。

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

## 2026-11-09: 接続済みChrome DevToolsでの入力経路の実測

利用者の指定に従い、`mcp__chrome_devtools`だけで隔離Chromeの専用ページ`http://127.0.0.1:8765/uia-fixture.html`を操作した。`list_pages`/`take_snapshot`で対象を確認し、`select_page(bringToFront=true)`、`click`、`fill`/`fill_form`、`type_text`、`press_key`を使用した。Computer UseとOSキー注入は使用していない。試験後に専用ページの文字列を初期値へ戻し、フォーム送信回数は0のまま。

DOMのkeydown/keyup/beforeinput/input/focusinを記録し、別の短時間AHK監視でOS InputHookの通知件数だけを同時測定した。監視は文字内容を保存せず、本体の既存読み取り専用診断から候補数・選択位置・確定回数・Hook状態を取得した。AHK v2.0.28 x64を確認。sandbox内のAHK起動はDLL再配置エラーとなったため、診断だけを通常Windowsセッションで実行した。

| 試験 | DevToolsでの観測結果 | 補完機能の判定 |
|---|---|---|
| inputへ`type_text("confi")` | value=`confi`、DOMの5文字分のkeydown/input/keyupを確認 | 候補表示は不成立。本体Visible=0、Count=0 |
| inputの`confi`からTab→3 | Tabでtextareaへ移動、空textareaのvalue=`3` | 数字候補確定は不成立。Selected=0、Commits=0 |
| `confi`入力→Tab→Enter | input=`confi`、移動先の空textarea=`\n` | 選択後Enter確定は不成立。Commits=0 |
| textareaへ`confi`入力→未選択Enter | textarea=`confi\n`、insertLineBreak | 通常改行はDOM上でPASS。OSキー試験とは別 |
| textareaへ`fill("fill-route")` | valueを確認、DOMの10文字分のkeydown/input/keyup | OS通知なし。`fill`も本体入力の代替にはならない |
| 5件→9件展開・9番確定 | 候補が出ないため選択状態に到達できない | NOT_RUN |

DOMキーの`isTrusted=true`は確認したが、OS InputHook通知はkeydown=0、keyup=0、OnChar文字数=0だった。監視側HookInProgress=1、本体Hook=1、本体PID=59300を確認した。ページ内の`document.hasFocus()`はtrueでも、読み取り専用のWin32前面照会は`ShellExperienceHost.exe`であり、Chromeではなかった。`select_page(bringToFront=true)`とページ内clickを行っても、この測定結果だった。

本体はOS InputHookの`OnChar`から入力trackerを更新し、Win32前面・focus・IME・UIAを確認する。この試験経路はDOMに入力できてもOS通知とChromeのWin32前面条件を満たしていない。したがって、今回の候補不表示をChrome互換性の製品障害やUIA/IMEの不具合とは判定できない。本体診断のReasonCode=14（NativeIMEPriority）はキャッシュ値であり、今回Chromeの現在IME状態を表す証拠には使わない。UIAStage=0のままで、当該入力で本体のUIA検証まで進んだ証拠もない。

製品コードや安全条件を変更せず、CDP専用動作も追加していない。ChromeのOSキーによる候補表示・Tab後数字・Enter確定は残課題。以前のnative Edit試験の成功をChrome成功へ読み替えない。Git除外の証拠は`tests/results/chrome-devtools/cdp-events.json`、`candidate-observer.json`、`tab3-observer.json`、`tab-enter-observer.json`、`unselected-enter-observer.json`、`final-observer.json`。製品AHKの変更がないため、成功済みの製品回帰試験は再実行していない。

## 2026-11-09: Chromeへの手入力と読み取り専用診断の照合

上記DevTools入力とは別に、利用者が隔離Chromeの同じ専用localhostフォームを手動で前面にし、IME OFFで入力した。エージェントはChromeの前面化・フォーカス変更・キー送信を行わず、本体の既存数値診断と専用フォームの値・イベントだけを読んだ。Computer Useで停止された操作を別AHKからの送信で迂回していない。これは**手入力による実動作確認**であり、Chromeへの合成OSキー自動試験ではない。

AHK v2.0.28 x64、本体PID 59300、単一本体・応答・Hook=1を確認。本体の停止・再起動や製品コード・設定・安全条件の変更はない。200ms間隔の監視は候補数・選択位置・確定回数・安全判定とChrome前面の真偽だけを記録し、入力文・URL・タイトルを取得しない。フォームの読み取り対象は使い捨て試験欄に限定した。

| 試験 | 利用者の確認 | 診断・フォームでの照合 |
|---|---|---|
| `confi`入力で候補表示 | 候補が表示された | 13:53:13 JSTにChrome前面、Visible=1、Selected=0、Reason=OK、Commits=0。最初の確認はplain欄 |
| Textareaで`confi`→Tab→3 | 3番の候補で確定した | Selected=0→1、Navigating=1、Commits=0→1。欄は`confidence`、末尾位置10、数字3・改行の残留なし |
| Textareaで`confi`→Tab→Enter | 1番で確定し、改行も入らなかった | 13:57:45にSelected=1、13:57:47にCommits=1→2。置換後10文字、確定時のinsertLineBreakなし。後の利用者による再試行でもCommits=2→3 |
| Textareaで`confi`→未選択Enter | 確定せず通常どおり改行された | 13:58:18にVisible=1、Selected=0、Navigating=0。13:58:19にinsertLineBreak、欄は`confi\n`で改行1個。Commits=3のまま |

以上4項目はこの専用フォームの手入力試験でPASS。Tab/数字/確定Enterは本体に抑止されるためDOMのkeydownがない場合もある。利用者の操作報告・本体の状態遷移・置換入力を合わせて判定した。DOMの`isTrusted`だけをOS入力の証明にはしていない。

診断Count=9は`Items.Length`（候補総数）であり、実可視行数ではない。初期5行→9行展開、他のWebアプリ・contenteditable・パスワード/readonly等の実入力互換性、Chromeへの合成OSキー自動試験は今回未検証。確定後に1候補で再表示される状態も観測したが、今回の確定・改行試験は成立した。

Git除外の証拠は`tests/results/chrome-devtools/manual-monitor.jsonl`、`manual-tab3-snapshot.json`、`manual-tab-enter-snapshot.json`、`manual-enter-events.json`、`manual-run.md`。今回作成した読み取り監視だけを停止ファイルで終了し、exit 0を確認。本体・Chrome・HTTPサーバー・他のAHK/IMEは操作していない。製品AHKを変更していないため回帰試験は再実行せず、`git diff --check`で文書差分を確認した。

## 2026-11-09: 候補の上下配置とキャレットからの距離

利用者から「Chrome・サクラでは離れすぎ、Codexの上側表示は近すぎ」と実観測の報告があった。コードを確認すると、下置きは`OffsetY=96`を使う一方、下に収まらない場合の上置きは設定を無視した固定12px相当で、さらにキャレットの下端を基準にしていた。上側で実際に入力行から空く距離は`12px相当−キャレット高`となり、行高によっては重なる非対称な処理だった。

Win32のGUIThreadInfo、既存UIAのキャレット矩形とも、物理ピクセルの上端・下端を保持するよう変更。下置きはキャレット下端から候補上端、上置きはキャレット上端から候補下端へ同じ`OffsetY`を取る。既定値・手元設定を`OffsetX=0, OffsetY=24`へ変更した。150%では上下とも36物理px相当で、下側の旧144物理pxから108px近づく。画面が狭く余白を確保できない場合は、従来どおり作業領域への収まりを優先する。座標だけのアンカーもYを基準に同じ余白で扱う。アプリ名に応じた位置の特例や、新たなUIA探索は追加していない。

- AHK v2.0.28 x64を確認。`tools/verify.ps1 -Ahk "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" -Dpi`を実行し、構文4入口・core 87・IME 56・navigation 92・UIA 372・サクラ27・DPI 391 checksがすべてexit 0。一時構文ラッパーの削除も確認した。
- DPI試験では100～300%の各倍率で、0/16/40px相当のキャレット高、上下両方向の余白、上下端のないアンカー、5→9行展開時の上側余白維持、負座標・狭い作業領域への収まりを検証した。Win32のunaware/system/per-monitor各入力先の上下端変換と、COMスタブのUIA矩形から上下端を保持する経路も確認した。
- 4台の実モニター（全144DPI=150%）で非アクティブGUIの位置・文字寸法・画面内への収まりを確認。入力・フォーカス変更は行っていない。Chrome・サクラ・Codexの修正後の距離を実際に見比べる試験、実混在倍率のモニター移動は未実施で、利用者の目視確認待ち。
- 開始時の本体PID 59300を識別したうえで、その本体だけを`/restart`。新PID 59216の対象CommandLine、単一プロセス、WM_NULL応答、InputHook=1、2秒後生存を確認した。他のAHK 10プロセスのPIDも維持。証拠はGit除外の`tests/results/candidate-spacing/restart.json`。Chrome・HTTPサーバー・他のAHK・IMEは操作していない。
- README、手動試験表、TODOを更新。個人設定はOffsetYだけ96→24へ変更し、個人DB・学習条件は手動変更していない。既存未コミット差分を保持し、commit/pushは行っていない。`git diff --check`はPASS。

## 2026-11-09: 番号欄を含む候補枠の横位置

上記反映後、利用者から縦位置は「おおむねちょうどいい」、横はIME候補と比べて右へ寄って見えるとの回答があった。従来の配置は候補枠の左端をキャレットXへ合わせており、実際の候補文字開始は左余白6px＋番号欄22px相当だけ右だった。候補文字開始を`キャレットX＋OffsetX`へ合わせるよう、枠のXからその分を差し引いた。150%では42物理px左へ移る。設定は`OffsetX=0, OffsetY=24`のままで、縦計算は変更していない。画面端では枠全体を画面内へ収めるため文字開始位置がずれる場合がある。

- `tools/verify.ps1 -Ahk "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" -Dpi`を実行し、AHK v2.0.28 x64、構文4入口・core 87・IME 56・navigation 92・UIA 372・サクラ27・DPI 439がすべてexit 0。一時構文ラッパーは削除済み。
- 各100～300%で、OffsetX=-20/0/20の一度だけのDPI換算、候補文字開始とキャレットの一致、5/9行での横位置維持を追加検証。既存の上下余白・キャレット高・負座標・画面端・狭い作業領域の試験、実4モニター全150%の非アクティブ配置も通過した。Chromeへの前面化・キー送信・フォーカス変更は行っていない。
- 開始時に稼働していた本体PID 59216だけを`/restart`し、新PID 16500の対象CommandLine、単一プロセス、WM_NULL応答、InputHook=1、2秒後生存、他AHK 10プロセスの維持を確認。Git除外の`tests/results/candidate-spacing/restart-horizontal.json`に記録した。
- README・手動試験表・TODOを更新し、`git diff --check`はPASS。横位置修正後も利用者から「おおむねちょうどよい」と回答があり、縦・横とも実際の距離感の調整を完了した。この確認は利用者による目視評価であり、エージェントの画面取得やキー送信は行っていない。アプリ別のIME候補との厳密な座標比較や実混在DPIのモニター移動は未実施。

## アプリ名に依らない自動学習・未知語2回（2026-11-09）

利用者の追加依頼により、候補表示の`Enabled`と自動学習の`Learning`を分離した。既定は`DefaultEnabled=0`、`DefaultLearning=1`。Chrome/Brave/Edge/ChatGPT.exe/Codex.exeを含む全標準プロファイルのLearningを1とし、補完無効・未登録アプリも安全な対応欄なら学習だけ行う。Snapshotは両方OFFのとき停止し、学習だけの場合は実テキスト検証後に観測を記録して候補検索・表示を行わず戻る。候補キーとCommitにはEnabledを必須にした。Excludedは両方OFFを優先する。

`PromotionCount`とINI欠落時・個人辞書コンストラクターの既定値を2へ統一。`user/settings.ini`にもLearning設定と2回閾値を反映した。個人DBの削除・再生成・手動編集は行わず、既存の2回以上の未知語履歴は設定反映後に候補へ昇格する。

`tools/verify.ps1 -Ahk "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" -LearningOnly`を実行し、AHK v2.0.28 x64で以下をすべてPASS、終了コード0と確認した。

- 絶対パス一時Include構文4入口。短時間ExitApp、`/ErrorStdOut`、finallyでラッパー削除。
- core 102項目：1回では非候補・2回で候補、旧3回閾値のDBを2回既定で開き直した際の昇格、既知語の順位加点、各標準アプリ・未登録アプリの学習既定、除外・明示opt-out・全体Learning OFF・INI欠落時fallbackなど。
- IME 56・navigation 92・UIA 372・サクラprotocol 27項目の既存回帰。
- 学習専用integration 55項目：別プロセスの使い捨てWin32 Editへ実SendLevel 1キーを送信し、実InputHookと本体Snapshot/Refreshを使用。未登録アプリで語境界1回/2回の記録と候補化、候補非表示・全候補キーの非介入・Commit拒否、通常Tabによるフォーカス移動と未検証語の非学習、パスワード拒否・readonly拒否・アプリ学習OFF・全体無効の学習停止、補完を有効に戻した後の候補確定と使用回数更新、メール拒否を確認。個人DBとは別のfixture DBを使い、終了時に削除した。

実入力試験で個人DBに試験語が入らないよう、開始時に稼働中だったEnglishAutocomplete本体PID 16500だけを一時停止。試験後に`/restart /ErrorStdOut`でPID 55736として復帰し、対象CommandLine・単一プロセス・WM_NULL応答・InputHook稼働・2秒後生存を確認した。他の10本のAHKのPIDを維持し、IMEを終了・再起動していない。証拠はGit除外の`tests/results/learning-change/verify.txt`、`restart.json`。

今回の新しい学習設定についてChrome/Codexの実入力・実DB書込みは再試験していない。自動試験の入力欄は専用Win32 Editであり、UIA安全条件は既存のheadless回帰で検証した。未対応の独自入力欄、パスワード、readonly、選択範囲、IME ON/状態不明、フォーカス不一致・実テキスト不一致は引き続き対象外。README・手動試験表・設計書を更新した。commit/pushは行っていない。
