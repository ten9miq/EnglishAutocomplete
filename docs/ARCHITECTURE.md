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

## 2026-11-09追加: アプリ名から入力欄の能力へ

現版は候補表示・学習を未登録アプリでも既定ONとする。native Edit/RichEditとサクラ専用経路を先に選び、それ以外のクラスはChromium限定を外してUIAへ渡す。native経路でpassword/readonly等を拒否した結果をUIAで再許可することはない。Excluded・アプリ別の明示OFFも優先する。後述の初期MVPのクラス制限は設計履歴であり、現行範囲はREADMEを正本とする。

Google検索欄はBrave実機でfocused ComboBox（50003）、ValueIsReadOnly=false、空選択・編集可能rangeとして公開された。Edit限定による拒否を解消するため、Editまたは編集可能ComboBoxを受け付ける。ComboBoxでは必ず入力欄内の構造的包含を確認した範囲だけを読み、EOFはその欄のValueとの照合で証明する。type/readonlyは最後のfocus照会時にも再確認する。リスト専用ComboBoxは引き続き拒否する。UIAから取得する情報が不足する独自エディターに対する推測や強制有効化は追加しない。

Word本文はDocument（50030）として公開される。DocumentRange・collapsed selection・左右の範囲の包含とreadonly=falseを必須とし、本文取得後にも再検証する。読み取りは128/1文字に限定し、Editの端点不整合向けValue全文経路はDocumentに適用しない。可視Edit/ComboBoxで空選択の矩形がない場合は、同じ端点のアクティブなTextPattern2 caret、次に前面client内の入力欄矩形を使う。後者の配置は欄の下端であり文字単位の座標ではない。Googleスプレッドシートの実機でこの経路を確認した。

Googleドキュメントのスクリーンリーダー/点字ON環境では、UIAが画面外のEditで本文近傍と選択を公開する一方、MSAAのOBJID_CARETが実文書の可視座標を公開した。offscreenを無条件許可せず、Edit・writable Value・UIAの従来の本文/選択検証に加え、WindowFromAccessibleObjectの所有HWND=現在focus、role=system caret、stateにunavailable/invisible/offscreen/protectedなし、矩形が前面client内、という証明を本文取得の前後に要求する。MSAAではrole/state/locationだけを取得し、name/value/本文や子孫を読まない。COM呼出し後にも200msの期限と最後のnative/UIA focusを確認する。候補選択とidle keepaliveはUIAの同一identity/focus・readonly・IMEだけを再確認し、MSAAの再照会は表示Snapshotと実Commitに集約する。選択キー自体は文字を挿入せず、Commitの厳格な再検証は省略しない。Win32/native経路や他のIMEスクリプトは変更しない。

## 判断

### IT説明JSONと生成データ

`data/it-descriptions.json`を独自説明の正本とし、CSpell語のうちreviewedのレコードだけを`it_entries.translation`へ反映する。確認URL・MIT・確認日・original/reviewedを`it_description_provenance`で語IDへ結び付ける。配布スキーマ2への追加テーブルであり、既存の入力時クエリは説明欄をそのまま使う。JSONに未知語、重複、空/複数行/長すぎる説明、不正なURL/日付/ライセンスがあれば生成を失敗させる。入力時にJSON読込・Web照会を追加しない。

通常辞書の意味とIT文脈の意味が異なる語は、有効なIT候補で独自説明を表示する。管理画面もAI補助→IT説明→通常の訳の優先順に合わせ、日本語説明を検索対象に含める。語彙・順位・表記・索引は説明の編集で変えない。AI補助は既存の別JSONで保持する。

### 2026-11-10: IT追加辞書の分離と順位

配布DBをversion 2へ拡張し、CSpell(4)・AI補助(8)を追加した。`words`の通常英語の表記・訳・点数を保持し、IT由来の表記と点数は`it_entries(word_id,source)`へ分離する。これにより、ITを無効化しただけで通常英語まで消えたり、AI製品の表記が通常英語へ残ることを防ぐ。AI補助は出典URL付きのプロジェクト管理JSONで保持する。

prefix索引は1/2/4/8の各ソースで12件ずつ。ITの全語に同じ`ITScoreBoost`、AIソースにはさらに同じ`AIScoreBoost`を加算するため、設定変更時に索引を作り直す必要はない。最大48件を読み、重複語は最高点を採用してから個人語の加点・禁止と統合する。IT/AI用の表記は有効なときだけ優先し、手動登録の表記はその後に適用する。個人DBのスキーマと入力欄・IMEの安全判定は変更しない。

### 2026-11-10: Excelの旧フォーカスとIME照会

Excel 16.0.19127.20860でGetFocusedElementが返すEXCEL6のPaneは、セル編集矩形と重なる。実際の書込み可能なEditは、数式バーの直下または編集中のDataItemの直下にある。excel.exe・XLMAIN・EXCEL6を照合して、一意な可視数式バーの直下にフォーカス済みEditがあるかを調べる。セル側では編集矩形の横と縦の外側から、同じEXCEL7と同じDataGridに属する行番号・列番号を得る。調べる位置は各軸最大2点で、周囲のセルの本文は取得しない。GridPattern.GetItemで指定した1セルに対して親と型を照合し、直下最大8要素から一意なフォーカス済みEditを確認する。フォーカスの再検証時も同じセル直下のEditを取り直す。通常のTextPattern・readonly・空選択・局所範囲・キャレット・IMEの検証を通った場合だけ候補を扱う。

空セルへ直接入力すると、先頭キーのOnCharはEXCEL7で届き、その後フォーカスがEXCEL6に移る。350ms以内に同じXLMAIN・スレッド・親の編集欄へ移った場合だけ、観測済みの先頭英字1字を引き継ぐ。編集開始直後にIsReadOnlyがVT_UNKNOWNを返した場合、その読み取りを拒否し、プレビュー時だけ既存の350msの枠内で新しい状態を照会する。

同じ実機ではIME OFFでもIMC_GETOPENSTATUSが単発でERROR_TIMEOUT（1460）になり、50msの独立診断でも失敗した。期限を広げず、20ms照会のtimeout時だけ同じnative context・HKL・default IME HWND・所有threadを確認し、メッセージ処理を一度譲って新しい20ms照会を最大1回行う。照会前後に同じ対象を再検証し、IME ON、再失敗、対象変更は許可しない。直前の成功状態やキャッシュを根拠にした確定は行わない。

VS Code 1.143.1ではaccessibilitySupport=onで本文を公開する。標準IntelliSenseの自動選択はfocused要素を非編集Groupへ移すため、Groupを許可する代わりにsuggest.selectionMode=neverを併用する。標準候補の表示と明示操作を維持し、本文のEditとしての安全条件を満たす間だけ補完する。設定は本体から自動変更しない。

既存IMEインジケーターと新規英文補完を統合せず、補完側は候補表示時だけGUIThreadInfoで位置を取得する(C案)。既存側はCaretGetPos/MSAA/UIA等を組み合わせるが、新規側がUIAv2を追加で読み込まなければUIA/IA2の重複探索は発生しない。共通ライブラリをIncludeするだけではプロセス間のキャッシュは共有されない。将来拡張するなら既存表示からフォーカス識別子・世代・鮮度を含むIPC配信(B案)を検討する。

本MVPは通常Edit/RichEditのみ許可する。パスワード判定、選択状態、実テキスト、HWND+focus、IME状態を確認できない欄では停止する。既存表示の「A」は、TSFの未確定入力が存在しないことまでは保証しない。Google/MSが開いた半角英数を許可するには別の変換中判定を実証する必要がある。現版はENGと閉じた日本語IMEだけ許可し、目標仕様の一部が未達であることをREADMEで明示している。

## 非同期InputHookの注意

実テキストの更新がOnChar通知より先になることが、別プロセスのEdit fixtureでも観測された。途中の一致失敗で直ちに観測中の単語を消すと、後から届いた末尾の文字だけが新しい単語になり、補完が単語境界まで復帰しない。対策は、不一致の間はGUIと確定を停止し、64文字に制限した未信頼の現単語を次のイベントまで保持すること。新しい通知が来ても実テキストに一致するまでは候補を表示しない。フォーカス・選択・ショートカット・IME等による無効化は別途行う。単語は空白等の境界でリセットされる。

確定時は実テキストを再照合して語尾だけ挿入し、Backspaceで既存文字を削除しない。L0でInputHook自身の全文バッファを無効にし、I1とSendLevel 0で補完の自己再帰を防ぐ。修飾キーの状態は非同期通知時点のGetKeyStateだけでは合成ショートカットを捉えられず、OnKeyDown/Upの追跡も必要だった。一方SendTextが修飾をSendLevel 0で復元するとそのKeyUpはI1に来ないため、通常文字通知と明示Reset時に古い修飾追跡をクリアする。

この機能の大小文字判定・実テキスト照合・表記テストにはAHKの厳密比較`==`を使う。`prefix = StrUpper(prefix)`は小文字でも真となり、普通の補完が大文字の語尾になる。テストまで`=`を使うと不正な大小文字を検出できない。`ApplyCase`、`FieldGuard.Matches`と実入力欄を比較するテストを厳密比較へ統一し、小文字・全部大文字・先頭大文字・混在・CamelCaseを別々に確認する。

大文字で一度補完した使用履歴が次回の普通表記を変えてしまわないよう、使用回数更新では登録済みの元表記を上書きしない。手動登録を明示し直した場合だけ表記を更新する。標準語は自動学習の表記より標準辞書の表記を優先し、手動登録だけがそれを上書きできる。coreの元表記保持試験と`verify.ps1 -CaseOnly`で確認する。

## 検証・再現

選択した自動学習候補には`Learned`を付け、Ctrl+Delete/選択行の×から`ForgetLearned`を呼ぶ。UIが保持した候補オブジェクト、入力世代、フォーカス、入力位置、IMEを再確認し、SQLの`BEGIN IMMEDIATE`内でも`manual=0/blocked=0/uses>0`を照合する。成功した単語だけ履歴行を削除し、保留学習を捨てて未選択の候補を再検索する。標準辞書は変更せず、手動登録・禁止行を保護する。×クリックだけ通常のマウスResetから分岐し、NoActivateを維持する。DB書込み失敗では候補を削除済み扱いにしない。

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

## サクラエディタ本文プロバイダー (2026-11-08追加)

冒頭の通常欄限定の判断を拡張し、`SakuraView182`だけを専用方式で扱う。UIA/MSAAに本文・選択が公開されず、標準Editメッセージも使えないため、単に許可クラスを増やす方式は採らない。

公式リビジョン[`119485ac9c4ce13989c27b570a3b835f49f5e1b9`](https://github.com/sakura-editor/sakura/tree/119485ac9c4ce13989c27b570a3b835f49f5e1b9)の共有データ版182に固定する。正規プロセス名と親クラス`TextEditorWindow[ M64 ]WP182`を検証し、共有領域の版とproduct versionが対象実行ファイルの版に一致することを必須とする。

- `MYWM_GETFILEINFO=WM_APP+203`で論理カーソル、`MYWM_GETLINECOUNT=WM_APP+226`で行数、`MYWM_GETLINEDATA=WM_APP+208`で行内オフセット以降を照会する。`DLLSHAREDATA`の先頭16バイト直後にWCHAR[32000]、その後に`EditInfo`があり、`EditInfo::m_ptCursor`のオフセットは556。読み取り先は64572/64576。ハンドルやポインターを含まないこの先頭部分だけを扱う。[公式レイアウト](https://github.com/sakura-editor/sakura/blob/119485ac9c4ce13989c27b570a3b835f49f5e1b9/sakura_core/env/DLLSHAREDATA.h)、[EditInfo](https://github.com/sakura-editor/sakura/blob/119485ac9c4ce13989c27b570a3b835f49f5e1b9/sakura_core/basis/EditInfo.h)
- `SakuraShareData[ M64 ]WP182`はFILE_MAP_READで開き、`MutexSakuraEditorShareWork[ M64 ]WP182`で排他する。アプリ側が共有ワーク領域へ返した結果を読む。こちらから領域への書込・他プロセスのメモリ書換えは行わない。受信文字列にNUL終端を仮定せず、返却長を制限して直前128文字と直後1文字だけを保持する。
- 独立した非表示HMENUに`F_DELETE_LINE=30245`と`F_COPYLINES=30610`を初期enabledで作る。`WM_INITMENUPOPUP(0x117), fSystemMenu=TRUE`で対象の状態更新だけを要求し、「前者enabled・後者disabled」だけを許可する。未処理なら両方enabledのままなので拒否される。既存メニューや本文は変更しない。この判定はサクラのIsEditableとIsTextSelectedを反映する。[公式状態更新](https://github.com/sakura-editor/sakura/blob/119485ac9c4ce13989c27b570a3b835f49f5e1b9/sakura_core/window/CEditWnd.cpp)、[有効条件](https://github.com/sakura-editor/sakura/blob/119485ac9c4ce13989c27b570a3b835f49f5e1b9/sakura_core/func/Funccode.cpp)
- タイムアウト後も対象が処理中の可能性があるため、元のSendMessageCallbackの完了でリソースを解放する。通常の待機上限は20ms。timeout時は結果を拒否し、完了まで共有mutex/メニューを保持して新規照会を止める。timeout引渡し直前の完了も回収し、対象スレッド終了時は監視で解放する。共有mutex待機も20ms、abandonedは拒否する。
- 状態・カーソル・近傍を前後で照合し、候補確定前にも既存Snapshotから再照会する。空文書と正規のEOF空行を扱う。カーソル座標は既存Win32 CaretProviderを使用する。IME制限は緩和しない。

このプロトコルはサクラの内部共有データ版に依存する。将来版は先頭レイアウトと状態照会の双方を確認してから追加する。32bit 2.4.3.7173のみ実機確認済み。source ZIPと照合用ヘッダーは`tools/sources/`、試験文書・結果は`tests/results/`に置き、Git/配布物へ含めない。

## Chromium/ElectronのUIA入力プロバイダー

`Chrome_WidgetWin_*`/`Chrome_RenderWidgetHostHWND`に対し、現在focusedなUIA要素を取得する。ControlType=Edit、HasKeyboardFocus/Focusable/Enabled=true、Password/Offscreen=falseを厳格なVARIANT型付きで要求する。NotSupportedやMixedをfalseへ変換しない。RawViewWalkerで祖先だけを上限32段・全体200msまで辿り、Win32前面HWNDの要素に一致することを確認する。RPCの接続・取引タイムアウトは各50ms。[Microsoft property仕様](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationelement-getcurrentpropertyvalueex)

TextPatternの単一collapsed選択を使用し、選択と左右の近傍がその入力欄のDocumentRange内であること、IsReadOnly属性40015がBOOL=falseであることを確認する。左128文字・右1文字を別rangeにし、GetTextの129/2文字制限で切詰めを検出する。Characterが別unitへ繰上がって長過ぎる場合は停止する。[範囲移動仕様](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationtextrange-moveendpointbyunit)

UIA runtime identity・collapsed rangeのendpointで同じHWND内の入力欄と位置を区別する。本文と位置の再照合後、最後にfresh focused要素/HasKeyboardFocusを確認する。UIAキャレット矩形がなければ停止し、共有renderer HWNDのWin32キャレットへ推測しない。Snapshot読取り後にもIMEを再照会し、Commitはさらにフォーカス・IME・入力世代を送信直前に確認する。外部アプリの状態とキー送信を原子的に固定する方式ではない。

アプリ既定許可はChrome/Brave/EdgeとChatGPT.exe/Codex.exe。自動学習はアプリ名に依らず既定ON。候補表示のEnabledとは独立し、未知アプリやEnabled=0でもLearning=1なら同じ安全判定を通った欄だけ学習する。Excludedは両方OFF。Refreshは検証済み観測を処理した後、Enabled=0なら検索・表示を行わず戻る。未知語の既定閾値は2回。入力欄へSetValue/Select/Focusを呼ばず、UIA本文全文やValueを一括取得せず、クリップボードにも依存しない。未知の文書型や独自エディターの強制許可は設けない。

### rich fieldの端点不整合に対する追加経路

Codex実入力で、DocumentRangeとselectionの端点比較が範囲外になる一方、両方のGetEnclosingElementがfocused Editの子孫になるケースを確認した。比較結果±1を許可せず、RangeWithinで範囲全体の最内包含要素からfocused Editへ到達することを要求する。左右の近傍は、包含に失敗した試行ではGetTextを呼ばず、二分探索で入力欄内の範囲だけに制限する。

右側が空の場合、より大きいtext unitへの繰上がり等で文中をEOFと誤認しないよう、追加でValueReadonly=falseを確認したEdit自身のValueを上限32767文字だけ一時取得する。caret左側の包含済み全範囲と完全一致すること、および最後のValue再照合を必須とする。この追加経路に限り上記のValue取得禁止を拡張するが、ページ全文は読まず、Value全文を返却データ・ログ・辞書へ保持しない。証明済みEOFは入力欄IDとUTF-16長で位置を比較する。

UIAの更新ずれ・照会timeoutは最大350msだけ再試行する。安定して表示済みの候補と選択の定期維持は、focus・password・enabled・offscreen・IMEの軽量確認を行う。本文を変更しない候補移動では全文の範囲再取得を行わず、Enter確定時には既存の厳密な本文・位置・focus・IME・入力世代の検証を必須とする。変換中に検証失敗したEnterをチャット送信へ流さない。
