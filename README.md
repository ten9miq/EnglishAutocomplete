# EnglishAutocomplete (AutoHotkey v2)

ローカル辞書とSQLite学習による英文単語補完。**通常のWin32 Edit/RichEdit欄向けの動作するMVP**であり、すべてのWindowsアプリに対応した完成版ではない。既存IMEインジケーターのソース・プロセス・設定は変更しない。

専用リポジトリ: [ten9miq/EnglishAutocomplete](https://github.com/ten9miq/EnglishAutocomplete)。元のAutoHotkeyリポジトリから分離した独立プロジェクトで、外部のAHKライブラリを要求しない。cloneまたはZIP展開したこのディレクトリだけで利用できる。

## 現時点でできること

- 既定3文字から最大5件の候補。大小文字を無視した検索、入力済み大文字の保持、訳の表示切替。
- 入力を奪わないNoActivate GUI。候補がある間だけ確定・候補移動・番号選択・Escを有効化。
- 入力欄の実テキスト、選択状態、フォーカス、IMEを確定前に照合。既存文字を消さず**残りの文字だけ**送信。クリップボードを使用しない。
- SCOWL size 60 US + EJDict、113,438語。13,102フレーズは別テーブルへ分離して保存し、現版の候補には出さない。
- SQLite個人辞書、使用回数・最終日時・手動登録・禁止・削除・頻度初期化。未知語は既定3回で昇格。
- Backspace後の実テキスト再検証。Delete、移動、クリック、ショートカット、IME切替、フォーカス変更で古い候補を破棄。
- 本体の実行時にPython、Webサーバー、クラウドAPI、追加SQLite DLL、管理者権限は不要。

## 明確な制限

ENGと日本語IMEを閉じた直接入力で動作する。**IME ONでは変換とキー操作をMS IME等へ任せ、スクリプトの候補・選択・確定は停止する**。ONの半角英数も同じ。モード不明・照会失敗時も停止する。IME OFFの半角英数で、対応入力欄の英文を補完する。

ENGの追加は不要。本体はキーボードレイアウトを追加・切替しない。自動試験の専用fixtureは一時的に英語US配列を読み込むが、終了時に元の配列へ戻し、そのfixtureが追加した配列だけを解除する。既に登録・読み込み済みの配列は削除しない。

安全判定できるクラスは `Edit`、`RichEdit`、`RichEdit20A/W`、`RichEdit50A/W`、`RichEditD2DPT`。ES_PASSWORD/EM_GETPASSWORDCHAR、読み取り専用、選択範囲、32767文字を超える欄、タイムアウトは拒否する。カスタム入力欄への強制有効化設定はない。Scintilla、サクラ本文、Chromium/Electron、Chrome/Braveのフォーム、Excel本文・数式バー、VS Code、Google Docs/Sheets/Slidesは**現版の入力プロバイダーで対応していない**。単に実入力未検証という意味ではない。

Windows 11の新しいメモ帳の内部コントロールが対応クラスかどうかは環境依存。専用のネイティブEdit試験窓では動作確認済みだが、インストールされているメモ帳アプリ自体は未検証。一般アプリを無条件に保証しない。

## 起動

1. このフォルダをユーザーが書込み可能な場所に置く。
2. AutoHotkey **v2 x64**を用意する。v1では動かない。
3. `EnglishAutocomplete.ahk` を実行する。初回に `user/settings.ini` と `user/user.db` を作る。
4. ENGまたはIME OFFの対応入力欄で `confi` などを入力する。

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" '/restart' '.\EnglishAutocomplete.ahk'
```

| 既定キー | 動作 |
|---|---|
| Ctrl+Alt+Space | 選択候補を確定 |
| Ctrl+Alt+Down / Up | 次 / 前の候補 |
| Ctrl+Alt+1～9 | 表示中の対応番号を直接確定 |
| Esc | 現在の候補をキャンセル |
| Tab / Enter | 本来のアプリ操作を維持(既定) |

候補がない場合・対象外欄・アプリ無効時には確定キーを横取りしない。状態が変わった直後の確定は再検証でキャンセルされることがある。通常の矢印キーを候補移動に割り当てていないため、エディタのカーソル移動を維持する。Tabを有効化すると先頭候補を確定し、Enterを有効化すると選択候補を確定する。どちらも改行・セル移動は送らない。

トレイから全体ON/OFF、単語登録、設定ファイル表示、設定再読込、状態表示、終了を操作できる。全体OFFでは学習も停止する。スタートアップ登録は自動で行わない。

## 設定

正本の例は `settings.default.ini`。変更対象は `user/settings.ini`。トレイの「設定を再読込」で反映する。

| セクション / キー | 用途 |
|---|---|
| General / Enabled | 全体ON/OFF |
| MinLength / MaxCandidates | 2～32文字 / 1～9件 |
| FontSize / OffsetX / OffsetY | 表示サイズと96DPI基準のオフセット。既定32,80で既存IME表示の下側にずらす |
| ShowTranslation / SCOWL / EJDict | 訳、各辞書ソースの有効化 |
| Learning / PromotionCount | 自動学習、未知語昇格(2～100回) |
| DebounceMs | 入力後の更新待ち(既定30ms) |
| CaretMode | `Win32` または `Off`。Offは候補表示を停止する診断用 |
| DataDirectory | 個人DBの場所。既定`user`。絶対パス指定も可。設定ファイルの場所は変わらない |
| Debug | 例外時の日時と固定診断文だけを`status.log`へ記録。入力・単語・文章は記録しない |
| Keys / Accept, Next, Previous, Cancel | 例: `^!Space`。`^` Ctrl、`!` Alt、`+` Shift、`#` Win。1キーと単純な修飾だけ対応 |
| DirectModifier / Tab / Enter | 番号キーの修飾(既定`^!`)、Tab/Enter確定 |
| Applications / DefaultEnabled, DefaultLearning | 未登録アプリの既定値。安全のため両方0 |
| Applications / Excluded | カンマ区切りの除外exe名。明示許可より優先 |
| app:実行ファイル名 / Enabled, Learning, Keys | アプリ別の補完・学習・候補キーON/OFF |
| app:実行ファイル名 / Tab, Enter | アプリ別のTab/Enter確定ON/OFF |

メモ帳・Notepad++・サクラのプロファイルは許可しているが、**プロファイル許可はそのアプリの独自コントロールに対応したことを意味しない**。上記の安全判定を通るネイティブ欄だけが対象。Excel/VS Code/Chrome/Braveは初期設定で無効。新しいアプリを許可する際は、学習を先に無効のまま `docs/MANUAL_TESTS.md` を確認する。

## 個人辞書とデータ管理

トレイの手動登録は即座に有効。CamelCaseは保存する。自動学習は空白・改行・Tabで確定した単語を実テキストと照合した後に行い、キーごとにDBへ書き込まない。補完確定後も実際の挿入を再検証して使用回数を更新する。高速入力中に検証できなかった観測は捨てる。

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

`Lib/All.ahk`から、Config、SQLite、FieldGuard、ImeStateProvider、CaretProvider、SuggestionEngine、UserDictionary、InputTracker、SuggestionGui、Applicationを読む。`EnglishAutocomplete.ahk`が常駐入口、`ManageDictionary.ahk`が管理入口。

候補生成はInputHookコールバックから30msのタイマーへ集約する。コールバック内で辞書SQL・IMEメッセージ・UIA・ファイルI/Oを行わない。確定前には実テキストとの一致を必須にする。非同期通知より先にアプリのテキストが変わった場合は候補を隠して短時間再検証する。通知と一致しないテキストを無条件に置換しない。

既存の `GoogleIME風入力モード表示.ahk` と `IME入力モード表示.ahk` を実際に調査した。現に稼働していた前者はCaretGetPos→GUIThreadInfo→MSAA→フォーカスUIAを利用し、180/350msでIME監視、モード変化時に60ms集約して座標を解決する。後者には75/100/150/400msの可変監視、1000msの入力コンテキストキャッシュ、UIA/MSAAの失敗時待機、手動IA2診断等がある。

これは分離前の設計調査であり、これらのスクリプトは本リポジトリの依存ファイルではない。設計上の注意点は [ARCHITECTURE.md](docs/ARCHITECTURE.md) にまとめた。

| 統合案 | 利点 | 欠点 / 判断 |
|---|---|---|
| A: 1プロセスへ統合 | 高コスト探索とキャッシュを完全共有できる | 既存ホットキー・常駐ライフサイクルへの影響が大きい。今回不採用 |
| B: IME表示がIPCで配信 | プロセス分離とキャッシュ共有を両立 | 既存側への変更と世代/フォーカス/鮮度管理が必要。将来候補 |
| C: 既存無変更・候補時に軽量取得 | 既存環境への影響が最小 | カスタム欄は停止。**今回採用**。Win32のみなのでUIA/IA2の重複探索は0回 |

CaretProvider.GetPosition(context)はFound/X/Y/Method/Hwnd/Focus/Tick/Ageを返す。GUIThreadInfoの座標変換は既存コードの構造体配置と同じ方式。30msキャッシュをHWND+focusで分離し、不明時は古い座標を返さない。候補がない待機中には位置を取得しない。UIA/IA2は読み込まない。位置取得不能時のマウス位置への推測表示も行わない。DPI・モニター作業領域で位置を補正するが、実際の複数モニター・DPI混在は未検証。

## 辞書の再生成

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

```powershell
./tools/verify.ps1
# 専用の破棄可能なGUIにだけ自動入力する。試験中はキーボード/マウスを操作しない
./tools/verify.ps1 -Integration
# 大小文字だけを短時間で実入力確認する
./tools/verify.ps1 -CaseOnly
```

AHK構文検証は100msで終了する一時絶対Includeラッパーと`/ErrorStdOut`を使用し、終了コード0を要求する。ラッパーと一時出力はfinallyで削除する。テストは個人DBではなく専用の一時DBを使う。入力試験は新しいネイティブEdit窓だけに合成イベントを送り、終了時に窓とDBを削除し、元のフォーカスとテストスレッドのHKLを戻す。

現機の結果・測定条件は [検証記録](docs/VALIDATION.md)、アプリ別とIME別の未実施手順は [手動テスト](docs/MANUAL_TESTS.md)。構文検証と実入力試験は別々に記録している。検索P95の自動試験は実際の113,438語の配布辞書を対象にする。

## Portable / EXE化

このフォルダ全体を保持し、AHK v2 x64 Portableランタイムから入口スクリプトを指定する。Ahk2Exeでは`EnglishAutocomplete.ahk`を同じフォルダのEXEへ変換し、`data/`・`settings.default.ini`・`licenses/`・`LICENSES.md`を隣接配置する。個人データを含む`user/`は配布しない。Python・ソースZIP・tests/は実行時に不要。ランタイム自体の再配布条件は [LICENSES.md](LICENSES.md) を参照。Ahk2Exeによるビルドそのものは未実施。

`python tools/package_portable.py`で`dist/EnglishAutocomplete-portable.zip`を生成できる。辞書、ライセンス、コード、再生成/テスト手順を含み、個人設定/DB・ソースZIP・試験結果を除外する。AutoHotkey実行ファイルは含まない。

実機のプロセス情報を含む`docs/resident-metrics*.json`もGitHubと配布ZIPから除外する。共存負荷を計測する場合は、独立プロジェクト側から `./tools/measure_resident.ps1 -IndicatorScript '既存IMEスクリプトの絶対パス'` と指定する。未指定なら補完本体だけを計測する。

## 次の改善

1. Google/MS-IMEそれぞれの実入力とON/OFF切替を確認する。IME ONはネイティブIMEへ任せる。
2. IPC(B案)で既存インジケーターの座標を共有し、UIA/IA2を重複させずカスタム欄へ広げる。同時に入力欄の安全性とテキスト照合プロバイダーを追加する。
3. Excel、Scintilla、Chromium/Electronごとの安全な挿入とフィールド識別を実装し、実アプリ別に試験する。
4. 異なるDPI/複数モニター、長時間常駐、複数IME、物理キーボードでの高負荷入力を確認する。

本体は既存IME表示を自動変更せず、無関係なAHKの終了・再起動やスタートアップ登録も行わない。
