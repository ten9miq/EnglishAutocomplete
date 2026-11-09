# EnglishAutocomplete (AutoHotkey v2)

ローカル辞書とSQLite学習による英文単語補完。**アプリ名に依らず、Win32 Edit/RichEdit、共有データ版182のサクラ本文、UI Automationで安全な入力情報を取得できる入力欄に対応するMVP**。すべてのアプリやWebエディターへの対応を保証するものではない。既存IMEインジケーターのソース・プロセス・設定は変更しない。

専用リポジトリ: [ten9miq/EnglishAutocomplete](https://github.com/ten9miq/EnglishAutocomplete)。元のAutoHotkeyリポジトリから分離した独立プロジェクトで、外部のAHKライブラリを要求しない。cloneまたはZIP展開したこのディレクトリだけで利用できる。

## 現時点でできること

- 既定2文字から初期5件の候補。5番目を選択した瞬間に最大9件へ展開。大小文字を無視した検索、入力済み大文字の保持、訳の表示切替。
- 入力を奪わないNoActivate GUI。白地・細い枠・番号列・淡い選択背景でIMEの候補欄に寄せた表示。候補がある間だけ確定・候補移動・番号選択・Escを有効化。
- キャレット側モニターのDPIで文字と行高を実測。長い訳文は単行の省略表示にし、候補全体をそのモニターの作業領域へ収める。
- 入力欄の実テキスト、選択状態、フォーカス、IMEを確定前に照合。既存文字を消さず**残りの文字だけ**送信。クリップボードを使用しない。
- SCOWL size 60 US + EJDict、113,438語。13,102フレーズは別テーブルへ分離して保存し、現版の候補には出さない。
- SQLite個人辞書、使用回数・最終日時・手動登録・禁止・削除・頻度初期化。未知語は既定2回で昇格。アプリ名に依らず安全な対応欄で学習する。
- 学習した候補を選択してCtrl+Delete、またはその行の右端の「×」をクリックすると学習履歴を削除。手動登録した単語は保護する。
- Backspace後の実テキスト再検証。通常のDelete、移動、削除用×以外のクリック、ショートカット、IME切替、フォーカス変更で古い候補を破棄。
- 本体の実行時にPython、Webサーバー、クラウドAPI、追加SQLite DLL、管理者権限は不要。

## 明確な制限

ENGと日本語IMEを閉じた直接入力で動作する。**IME ONでは変換とキー操作をMS IME等へ任せ、スクリプトの候補・選択・確定は停止する**。ONの半角英数も同じ。モード不明・照会失敗時も停止する。IME OFFの半角英数で、対応入力欄の英文を補完する。

ENGの追加は不要。本体はキーボードレイアウトを追加・切替しない。自動試験の専用fixtureは一時的に英語US配列を読み込むが、終了時に元の配列へ戻し、そのfixtureが追加した配列だけを解除する。既に登録・読み込み済みの配列は削除しない。

候補キーの判定と確定直前にも本文・フォーカス・IMEを再照合し、表示後のモード変更や変換開始時には古い候補を確定しない。開いたIMEの未確定入力照会はライブラリ試験として残しているが、常駐本体はIME ONの候補を許可しない。

通常欄で安全判定できるクラスは `Edit`、`RichEdit`、`RichEdit20A/W`、`RichEdit50A/W`、`RichEditD2DPT`。ES_PASSWORD/EM_GETPASSWORDCHAR、読み取り専用、選択範囲、32767文字を超える欄、タイムアウトは拒否する。それ以外のクラスはアプリ名を制限せずUIAで判定する。カスタム入力欄への強制有効化設定はない。Scintilla、Excel本文・数式バー、VS Code本文、Google Docs/Sheets/Slides等は個別の動作を保証していない。必要な安全情報を公開しない欄では停止する。

Chrome/Brave/Edge、Codex等に加え、他のアプリやUIフレームワークでも同じUIAプロバイダーを使用する。**フォーカス中のEdit・編集可能なComboBoxで、パスワードでないこと、編集可能、単一の空選択、入力欄内の本文近傍、前面ウィンドウの祖先との一致を確認できた欄だけ**が対象。textareaやcontenteditableも同じ情報を公開すれば扱う。通常の読み取りは直前128文字・直後1文字。下記のEOF確認を除きValue全文は読まず、SetValue・クリップボード操作は行わない。同じウィンドウ内の別欄への移動もruntime identityで区別し、確定前に再照会する。Document、リスト専用ComboBox、情報が不足する独自Webエディターは停止する。

Google検索欄はBrave実機でUIAのComboBox（50003）、編集可能・空選択として公開されることを確認した。以前はEdit（50004）だけを許可していたため停止していた。ComboBoxではValueIsReadOnly=falseを必須とし、選択・左右近傍の範囲がその入力欄内に含まれることも確認する。[MicrosoftのComboBox仕様](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-supportcomboboxcontroltype)のとおり、選択だけのComboBoxは入力欄として扱わない。

Chrome/Brave/EdgeとCodexのプロファイルを既定有効・自動学習ONにしている。Codexデスクトップの`ChatGPT.exe`と`Codex.exe`の両プロセス名を用意する。IME ONはネイティブIMEへ任せる。2026-11-09、Codex実画面で9候補表示・候補選択・Enterでのconfi→confident確定（送信なし）を確認した。その後Spaceの候補操作は廃止し、現在はTab/↑↓で選択する。Chrome156では専用フォームのUIA公開属性を確認済み。後続の利用者による手入力で、Chrome専用localhostフォームの候補表示・Tab後数字・Enter確定・未選択Enterの通常改行を確認した。初期5行→9行の実表示、任意のWebアプリ、合成OSキー自動試験は未確認。対応範囲と残る7項目の進捗は[TODO](docs/TODO.md)に記録する。

rich fieldのDocumentRangeが実際のcaret端点と整合しない場合は、読む範囲がfocused Edit内に構造的に含まれることを検証する。EOFの追加確認で、そのEdit自身のValueだけを上限32767文字で一時参照することがある。ページ全文を読まず、Value全文をログや学習DBには保持しない。

**サクラエディタ本文は専用プロバイダーで対応**する。共有データ版182の`SakuraView182`と正規の`sakura.exe`/親クラス/共有領域/実行ファイル版の一致を必須とする。サクラ32bit 2.4.3.7173でIME OFFの半角英数による候補表示・確定を確認した。64bitは同版の形式を実装しているが実機未検証。未知の共有データ版は停止する。独立した非表示メニューへの状態照会で「選択なし・編集可能」を確認し、排他した共有領域を読み取り専用で参照して行近傍とカーソルを二度照合する。本文・クリップボード・マクロ設定には手を加えない。IME ONのままの半角英数は、従来どおり未確定入力を照会できなければ停止する。

Windows 11の新しいメモ帳の内部コントロールが対応クラスかどうかは環境依存。専用のネイティブEdit試験窓では動作確認済みだが、インストールされているメモ帳アプリ自体は未検証。一般アプリを無条件に保証しない。

## 起動

1. このフォルダをユーザーが書込み可能な場所に置く。
2. AutoHotkey **v2 x64**を用意する。v1では動かない。
3. `EnglishAutocomplete.ahk` を実行する。初回に `user/settings.ini` と `user/user.db` を作る。
4. ENGまたは日本語IME OFFの半角英数で、対応欄に`confi`などを入力する。IME ONでは候補を停止する。

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" '/restart' '.\EnglishAutocomplete.ahk'
```

| 既定キー | 動作 |
|---|---|
| Ctrl+Alt+Space | 選択候補を確定 |
| Space / Shift+Space | 通常の空白入力。候補操作には使わない |
| Tab / ↓ | 未選択なら1件目を選択。その後は次候補 |
| Shift+Tab / ↑ | 未選択なら最後を選択。その後は前候補 |
| Enter | 選択モード中だけ確定。選択開始前は入力先へ渡す |
| 1～9 / テンキー1～9 | Tab/矢印等で選択を始めた後、表示中の対応番号を確定 |
| Ctrl+Delete / 選択行右端の× | 選択中の自動学習候補の履歴を削除。入力文字は変更しない |
| Ctrl+Alt+1～9 | 選択開始前でも最大9件の対応番号を直接確定 |
| Esc | 現在の候補をキャンセル |

候補が出ただけのときは**初期5件・未選択（ハイライトなし）**。5番目へ到達した時点で9件へ展開し、その語の選択中は展開を維持する。最初のShift+Tab/↑は最後の候補を選び、同時に展開する。通常文字・取消・次の語では初期表示へ戻る。候補が少ないときは実件数まで。最初のTab/↓で1件目を選んでからEnterで語尾だけを挿入する。未選択のEnterは補完せず、入力先の通常動作になる。確定したEnterを押し続けても、キーを離すまではリピートを入力先へ流さない。離してからの別のEnterは通常の改行/送信へ戻る。

候補がない場合・対象外欄・アプリ無効時・IME ONでは新しいキー押下を横取りしない。数字単独は選択開始前と非表示番号では通常入力へ渡す。SpaceとShift+Spaceは候補表示中・選択中も空白入力へ渡し、単語区切りとして選択を終了する。左右移動・通常文字入力・削除用×以外のクリック・Escでも選択を終了する。Ctrl+Alt+Tabは登録しない。Ctrl+Alt+Spaceは未選択でも明示的に1件目を確定するショートカットとして残す。状態が変わった直後の確定は再検証で中止される。`ImeStyle=0`で標準キーによる操作をアプリ別にも無効化できる。

トレイから全体ON/OFF、単語登録、設定ファイル表示、設定再読込、状態表示、終了を操作できる。全体OFFでは学習も停止する。スタートアップ登録は自動で行わない。

学習候補の削除はTab/矢印で選んだ行だけに対して行う。「×」は選択中の自動学習候補だけに表示し、クリックしても入力先のフォーカスを維持する。削除後は候補を更新して未選択に戻す。未知語は候補から消え、再び2回学習すると戻る。配布辞書にもある語は使用回数・最終日時による加点だけ消え、通常候補に残る。手動登録語と禁止設定はこの操作では削除しない。未選択・未学習・対象外欄・IME ONの新しいCtrl+Delete押下は入力先へ渡す。削除に使った押下のリピートはキーを離すまで抑止する。アプリの`Keys=0`ではクリック削除も無効。明示的なカスタムキーがCtrl+Deleteを使う場合はその設定を優先する。

## 設定

正本の例は `settings.default.ini`。変更対象は `user/settings.ini`。トレイの「設定を再読込」で反映する。

| セクション / キー | 用途 |
|---|---|
| General / Enabled | 全体ON/OFF |
| MinLength / MaxCandidates / InitialCandidates | 2～32文字 / 最大1～9件 / 初期1～9件（最大件数以下、既定5） |
| FontSize / OffsetX / OffsetY | FontSizeはポイント数（既定11pt）。オフセットは96DPI基準、既定0,24。横は候補文字の開始位置をキャレットに合わせ、番号欄・左余白はその左へ配置。OffsetXで文字開始位置を左右調整する。縦はキャレットの端から候補まで24px相当の余白。下置きはキャレット下端、上置きは上端から離す（負値は入力行へ寄せる）。キャレット側モニターのDPIで一度だけ換算 |
| ShowTranslation / SCOWL / EJDict | 訳、各辞書ソースの有効化 |
| Learning / PromotionCount | 自動学習（既定ON）、未知語昇格（既定2回、2～100回） |
| DebounceMs | 入力後の更新待ち(既定30ms) |
| CaretMode | `Win32` または `Off`。Offは候補表示を停止する診断用 |
| DataDirectory | 個人DBの場所。既定`user`。絶対パス指定も可。設定ファイルの場所は変わらない |
| Debug | 例外時の日時と固定診断文だけを`status.log`へ記録。入力・単語・文章は記録しない |
| Keys / Accept, Next, Previous, Cancel | 例: `^!Space`。`^` Ctrl、`!` Alt、`+` Shift、`#` Win。1キーと単純な修飾だけ対応 |
| Keys / ImeStyle | 既定1。Tab/↑↓から選択モードへ入りEnterまたは表示中の番号で確定。Spaceは空白入力。アプリ別の同名設定でも無効化可能 |
| DirectModifier / Tab / Enter | 番号キーの修飾(既定`^!`)と個別キー許可。Enter=1でも未選択候補は自動確定しない |
| Applications / DefaultEnabled, DefaultLearning | 未登録アプリの既定値。候補表示・学習とも1。安全な対応欄だけで動作する |
| Applications / Excluded | カンマ区切りの除外exe名。明示許可より優先 |
| app:実行ファイル名 / Enabled, Learning, Keys | アプリ別の補完・学習・候補キーON/OFF |
| app:実行ファイル名 / Tab, Enter | アプリ別のTab/Enter確定ON/OFF |

プロファイル許可は、そのアプリの独自コントロールすべてに対応したことを意味しない。上記の安全判定を通る通常欄、対応版のサクラ本文、UIAのEdit/編集可能ComboBoxが対象。未登録アプリやExcel/VS Codeもアプリ単位では候補表示を許可するが、本文等の個別欄が安全判定を通るかは別に確認する。候補表示の`Enabled`と学習の`Learning`は独立し、`Enabled=0`でも`Learning=1`なら安全な対応欄で学習する。`Excluded`とアプリ別の明示OFFを優先する。未対応の独自欄は学習しない。新しいアプリを試す際は必要に応じて`Learning=0`にし、`docs/MANUAL_TESTS.md`を確認する。既存の設定ファイルは自動移行しないため、旧版から候補表示を広げる場合は`DefaultEnabled=1`と対象アプリの`Enabled=1, Keys=1`を指定する（今回の手元設定は反映済み）。

## 個人辞書とデータ管理

トレイの手動登録は即座に有効。CamelCaseは保存する。自動学習は空白・改行・Tabで確定した単語を実テキストと照合した後に行い、キーごとにDBへ書き込まない。補完確定後も実際の挿入を再検証して使用回数を更新する。高速入力中に検証できなかった観測は捨てる。

選択候補の優先表示と未知語の自動登録は実装済み。標準候補にも使用回数1回につき100点（上限5000点）と直近使用の加点を付け、標準辞書の点数と合算する。未知語は`PromotionCount=2`回の確認後に候補へ加える。既存DBに2回以上の履歴がある未知語も、設定再読込後から候補になる。DBの再生成・削除は不要。アプリ別の`Learning=0`では選択時の回数更新も未知語の登録も行わない。Chrome/Brave/Edge/Codex、サクラ/メモ帳、未登録アプリを含め学習は既定ON。アプリ別に止める場合は`[app:実行ファイル名] Learning=0`、全体を止める場合は`[General] Learning=0`へ変更して再読込する。`Applications/Excluded`は補完・学習の両方を停止する。

自動学習は2～32文字の保守的な単語に限定し、URL、メール、数字混在、`.`/`-`入り、認証情報を示す接頭辞、長い混合大小文字などを除外する。`php-fpm`、`config.toml`、数字入り技術語は手動登録を使う。機密トークンを文字列の形だけで完全識別することはできないため、機密アプリは除外し、不適切な文章を学習しうるアプリではLearning=0を使う。

管理コマンドは本体と別の `ManageDictionary.ahk`。常駐本体のSingleInstance処理を発生させずにDBを操作する。

```powershell
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
& $ahk '.\ManageDictionary.ahk' '--add' 'MyInternalTool'
& $ahk '.\ManageDictionary.ahk' '--add' 'config.toml'
& $ahk '.\ManageDictionary.ahk' '--block' 'unwantedWord'
& $ahk '.\ManageDictionary.ahk' '--delete' 'unwantedWord'
& $ahk '.\ManageDictionary.ahk' '--reset-frequency'
& $ahk '.\ManageDictionary.ahk' '--reset-user'
```

`--block`は標準候補からも除外。`--delete`は履歴と禁止状態を削除するため再学習できる。頻度初期化は手動登録・禁止を保持する。`--reset-user`は全単語・禁止・頻度を削除する明示的な初期化。個人DBは外部送信せずGit対象にも含めない。DB破損・ロック・将来スキーマでは学習を停止し、エラーで本体を落とさない。DBを読み出せない間は個人順位や禁止情報も利用できない。

## 構成と既存IME表示との関係

`Lib/All.ahk`から、Config、SQLite、Dpi、FieldGuard、UiaFieldProvider、SakuraFieldProvider、ImeStateProvider、CaretProvider、SuggestionEngine、UserDictionary、InputTracker、SuggestionGui、Applicationを読む。`EnglishAutocomplete.ahk`が常駐入口、`ManageDictionary.ahk`が管理入口。

候補生成はInputHookコールバックから30msのタイマーへ集約する。InputHookコールバック内で辞書SQL・IMEメッセージ・UIA・ファイルI/Oを行わない。開いた半角英数に限り、入力欄のHWND・PID・フォーカス一致とTextEditPatternの未確定範囲をUIAで照会する。接続/取引のタイムアウトは各50ms、IMEメッセージは20ms。UIAのツリー探索・本文取得・イベント購読・他プロセスのHIMC参照・IMEモード書換えは行わない。IMEモードはUIA照会の前後で照合し、本文と選択位置も再確認する。許可結果をキャッシュせず、候補キーの条件判定と確定前に再照会する。外部照会から送信までを原子的に固定する方式ではない。

確定前には実テキストとの一致を必須にする。非同期通知より先にアプリのテキストが変わった場合は候補を隠して短時間再検証する。通知と一致しないテキストを無条件に置換しない。未確定範囲の判定仕様は[MicrosoftのTextEdit仕様](https://learn.microsoft.com/en-us/windows/win32/winauto/textedit-control-pattern)と[GetActiveComposition](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationtexteditpattern-getactivecomposition)に従う。

既存の `GoogleIME風入力モード表示.ahk` と `IME入力モード表示.ahk` を実際に調査した。現に稼働していた前者はCaretGetPos→GUIThreadInfo→MSAA→フォーカスUIAを利用し、180/350msでIME監視、モード変化時に60ms集約して座標を解決する。後者には75/100/150/400msの可変監視、1000msの入力コンテキストキャッシュ、UIA/MSAAの失敗時待機、手動IA2診断等がある。

これは分離前の設計調査であり、これらのスクリプトは本リポジトリの依存ファイルではない。設計上の注意点は [ARCHITECTURE.md](docs/ARCHITECTURE.md) にまとめた。

| 統合案 | 利点 | 欠点 / 判断 |
|---|---|---|
| A: 1プロセスへ統合 | 高コスト探索とキャッシュを完全共有できる | 既存ホットキー・常駐ライフサイクルへの影響が大きい。今回不採用 |
| B: IME表示がIPCで配信 | プロセス分離とキャッシュ共有を両立 | 既存側への変更と世代/フォーカス/鮮度管理が必要。将来候補 |
| C: 既存無変更・候補時に取得 | 既存環境への影響が最小 | **採用**。native欄の座標はWin32。非native欄はUIAの安全情報が取れた場合だけ扱う |

CaretProvider.GetPosition(context)はFound/X/Y/Top/Bottom/Method/Hwnd/Focus/Tick/Ageを返す（Yは下端）。GUIThreadInfoのキャレット上下端を、そのHWND自身のDPI認識方式で画面座標へ変換し、物理ピクセルへ正規化する。UIA入力欄では既存のUIAキャレット矩形から同じ上下端を保持する。入力先移動時に古い位置を使わないよう毎回確認する。候補がない待機中には位置を取得しない。Win32経路の位置取得にUIA/IA2は使用せず、マウス位置へ推測表示しない。

候補GUIはキャレットの物理点があるモニターを選び、入力先の主ウィンドウのDPIに依存せず対象モニターの実効DPIを取得する。候補文字開始位置をキャレットX＋OffsetXへ合わせ、枠の左端は番号列と余白の分だけ左へ出す。下側に収まらなければ上側へ表示し、どちら側もキャレットの近い端からOffsetYの余白を取る。画面が狭い場合は位置合わせ・余白より作業領域内への収まりを優先する。計測と描画で同じフォントを使用し、DPIを二重換算しない。行高は日本語・太字を含む実測値＋余白、幅は内容に応じて180～520px相当（96DPI基準、作業領域が上限）。長い訳文は改行せず末尾を省略する。高さが足りない場合も選択行が見える範囲を表示する。

実環境の4モニター（全150%、負座標・上下配置を含む）で配置と文字の収まりを確認済み。100～300%のフォント寸法・配置、入力先のDPI認識方式別の座標変換も自動試験済み。異なる実モニター倍率間の移動や表示設定の動的変更は未検証。

## 辞書の再生成

通常の接頭辞候補では、ベース語が存在し訳のない「単語+'s」を除外する。辞書の語データは保持し、`teacher'`まで入力した場合は`teacher's`を補完できる。`it's`等の短縮形と訳のある語は残す。個人辞書へ明示的に登録・学習した形は個人候補として扱う。

通常利用に再生成は不要。生成時だけPython 3.8+標準ライブラリを使う。

再生成前に本体をトレイから終了し、辞書ファイルを閉じる。生成後に本体を起動する。個人DBは辞書再生成で変更しない。

```powershell
python tools/build_dictionary.py --fetch
python -m unittest discover -s tests -p 'test_*.py' -v
# 拡張語彙は同じ固定ソースから別のsizeで生成する
python tools/build_dictionary.py --size 70
```

`python`は利用可能なPython 3の実行ファイルに置き換える。検証機ではWindowsAppsのpythonエイリアスは実行不可だったため、Thonny同梱のPython 3.14.4を使った。ネットワークが必要なのは`--fetch`でソースZIPを取得するときだけ。固定コミットとSHA256を照合し、上流のPythonコードは実行しない。ソースZIPは`tools/sources/`へキャッシュする(Git対象外)。

正規化・カンマ区切り見出し分離・元表記保持・小文字優先による重複整理・文字検証・頻度階層統合・フレーズ分離・prefix上位索引を生成する。出力は`data/dictionary.db`とmanifest、ライセンス全文。DBスキーマversion=1。語のsourceビットを保つ。

| 検索方式 | 評価 |
|---|---|
| ソート配列+二分探索 | 起点は高速だが短prefixの大量一致を順位付けするコストが残る |
| 範囲prefix index | SQLの範囲を狭められるが、短prefixの全候補走査が残る |
| 全prefixの上位リスト | ビルド時の容量が増える。実行時の仕事量が語彙全体に依存しないため採用 |

各prefix(2文字以上)・ソースごとに上位12語を事前保存し、通常は最大24語と個人候補を統合する。標準辞書全体をAHKのMap/Objectに展開しない。禁止語などで減った場合に12位より後の静的候補を再取得する仕組みは未実装。個人辞書は新規自動登録を10000語に制限し、prefix範囲の上位64語を取得する。非常に大きい個人辞書での追加順位最適化は今後の課題。

## 自動試験・性能・未検証

削除のDB・状態ガードは通常の検証にも含む。`-ForgetIntegration`は使い捨てEditに実キー・クリックを送り、削除と入力/フォーカス維持を確認する。自動で前面にならない環境では`AutoHotkey64.exe /ErrorStdOut tests/forget-integration.ahk --wait-foreground`を使い、開いた試験窓の一番上の入力欄をクリックする（120秒待機）。その後数秒は操作しない。前面・入力欄・物理操作のガードを満たさなければ入力せず中止する。

```powershell
./tools/verify.ps1
# 専用の破棄可能なGUIにだけ自動入力する。試験中はキーボード/マウスを操作しない
./tools/verify.ps1 -Integration
# 大小文字だけを短時間で実入力確認する
./tools/verify.ps1 -CaseOnly
# 表示設定を変更せずDPI別フォント・配置と接続中モニターを検証する
./tools/verify.ps1 -Dpi
# 未選択→初回Tab→Enterと長押しを専用Editで約2秒確認する
./tools/verify.ps1 -SelectionIntegration
# 選択した学習候補のCtrl+Delete・右端×を専用Editで確認する
./tools/verify.ps1 -ForgetIntegration
```

AHK構文検証は100msで終了する一時絶対Includeラッパーと`/ErrorStdOut`を使用し、終了コード0を要求する。ラッパーと一時出力はfinallyで削除する。テストは個人DBではなく専用の一時DBを使う。入力試験は新しいネイティブEdit窓だけに合成イベントを送り、終了時に窓とDBを削除し、元のフォーカスとテストスレッドのHKLを戻す。

現機の結果・測定条件は [検証記録](docs/VALIDATION.md)、アプリ別とIME別の未実施手順は [手動テスト](docs/MANUAL_TESTS.md)。構文検証と実入力試験は別々に記録している。検索P95の自動試験は実際の113,438語の配布辞書を対象にする。

## Portable / EXE化

このフォルダ全体を保持し、AHK v2 x64 Portableランタイムから入口スクリプトを指定する。Ahk2Exeでは`EnglishAutocomplete.ahk`を同じフォルダのEXEへ変換し、`data/`・`settings.default.ini`・`licenses/`・`LICENSES.md`を隣接配置する。個人データを含む`user/`は配布しない。Python・ソースZIP・tests/は実行時に不要。ランタイム自体の再配布条件は [LICENSES.md](LICENSES.md) を参照。Ahk2Exeによるビルドそのものは未実施。

`python tools/package_portable.py`で`dist/EnglishAutocomplete-portable.zip`を生成できる。辞書、ライセンス、コード、再生成/テスト手順を含み、個人設定/DB・ソースZIP・試験結果を除外する。AutoHotkey実行ファイルは含まない。

実機のプロセス情報を含む`docs/resident-metrics*.json`もGitHubと配布ZIPから除外する。共存負荷を計測する場合は、独立プロジェクト側から `./tools/measure_resident.ps1 -IndicatorScript '既存IMEスクリプトの絶対パス'` と指定する。未指定なら補完本体だけを計測する。

## 次の改善

1. Google/MS-IMEそれぞれで、開いた半角英数・未確定入力・再変換・モード切替の実入力を検証する。標準Edit等のTextEditPattern非対応欄を許可するには、別の信頼できる未確定入力判定が必要。
2. IPC(B案)で既存インジケーターの座標を共有し、UIA/IA2を重複させずカスタム欄へ広げる。同時に入力欄の安全性とテキスト照合プロバイダーを追加する。
3. Excel、Scintilla、Chromium/Electronごとの安全な挿入とフィールド識別を実装し、実アプリ別に試験する。
4. 異なるDPI/複数モニター、長時間常駐、複数IME、物理キーボードでの高負荷入力を確認する。

本体は既存IME表示を自動変更せず、無関係なAHKの終了・再起動やスタートアップ登録も行わない。
