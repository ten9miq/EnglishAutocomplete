# 改善TODO（2026-11-09）

## 追加依頼: Googleドキュメント / スプレッドシート / Word

- [x] 実機のUIA属性と本体numeric statusで3アプリの停止原因を切り分け。WordはDocument型の拒否、Sheetsは空選択の矩形不足、Docsはアクセシビリティ用の画面外Editと可視caretの分離。
- [x] 編集可能Documentを局所範囲だけ検証。TextPattern2 caretと可視入力欄矩形の位置fallback、UIA本文/選択＋同じfocus所有の可視MSAA system caretによるアクセシビリティ用Edit対応を実装。native拒否・password・readonly・選択・IME・identity制限を維持。
- [x] Word実画面でconfi→5候補→Tab青選択→Enterでconfidence（改行なし）。Sheetsは利用者の手入力で候補表示・Tab→Enter確定・セル編集維持と本体CommitCount増加を照合。
- [x] Docsはスクリーンリーダー/点字ON環境で候補表示、Tab青選択→Enterで改行せず確定を利用者確認。本体のTabDecision=7/Selected=1/CommitCount増加と照合。軽いkeepaliveと確定時の物理caret再照合を分離し、監視側もcached numericだけにした。設定片方だけ・他ブラウザーは未検証。
- [x] AHK v2.0.28 x64、構文4入口とcore115/IME56/navigation107/forget29/UIA646/サクラ27=980 checksをPASS。実機診断と試験結果はGit対象外、他のAHK/IMEは再起動しない。

## 追加依頼: Google検索欄とアプリ名に依らない補完

- [x] BraveのGoogle検索欄がEditではなく編集可能ComboBox（50003）として公開されることを数値UIA診断で確認。安全なComboBox対応後、利用者の手入力で候補表示・Tab選択を確認し、Reason=OK/selected=1と照合した。
- [x] 非nativeクラスのUIA判定をChromium限定から全アプリへ広げる。未登録アプリとExcel/VS Codeも候補表示を既定ONとし、手元設定にも反映。個々の本文・独自欄はUIAの安全条件を通る場合だけ対象。Excluded、password、readonly、選択範囲、IME ON等の制限は維持。
- [x] 構文4入口、core115・IME56・navigation107・forget29・UIA425・サクラ27項目をPASS。実機の本体のみPID58912→58624へ再起動、単一・応答・Hook・3秒後生存と他AHK10本維持を確認。診断専用プロセスは終了。README/手動試験表/設計書/検証記録を更新。
- [ ] 各独自エディターの実入力、Chrome版Google検索欄・Edge、Google欄でのEnter/数字確定は今回未検証。全アプリの全入力欄を保証するものではない。

## 追加依頼：選択した学習候補を削除

- [x] Tab/矢印で選んだ自動学習候補をCtrl+Delete、または右端の×で削除。未知語の学習履歴を消し、配布辞書語は加点だけ初期化。手動登録・禁止を保持し、削除後は未選択へ戻す。入力先/位置/IME/行の同一性を再確認し、長押しで本文や別候補を消さない。
- [x] 独立DB29・状態遷移107・DPI455、専用Editの実キー/×クリック20項目PASS。本体最終PID59340、単一・応答・Hook・3秒後生存・他AHK10本維持。README/手動試験表も更新。Chrome/Codexでの削除の実入力は未検証。

依頼された7項目。自動試験と実アプリの実入力確認を区別する。

- [x] **1. Chrome対応の実入力確認** — Chrome/Brave/Edgeのプロファイルは既定で有効、学習ON（下記の手入力試験時は旧既定OFF）。UIAの安全条件を維持したまま、利用者の手入力と本体の読み取り専用診断を照合し、Chrome専用localhostフォームで候補表示、TextareaのTab→3による3番確定、Tab→Enterによる1番確定（余計な改行なし）、未選択Enterの通常改行を確認した。Chrome前面・Reason=OK・Selected=1・確定回数の増加とフォームの実値を記録。先行DevTools試験はDOM入力がOS InputHookに届かなかったため、手入力試験とは区別する。Chromeへの合成OSキー自動試験、初期5行→9行の実表示、任意のWebアプリの互換性は今回未検証。詳細は`docs/VALIDATION.md`の手入力検証節。
- [x] **2. Tab後の数字入力** — Tab/↓等で選択を始めた後、数字1～9（テンキーも対応）で表示中の該当候補を確定。選択前と非表示番号は通常入力。Ctrl+Alt+1～9も維持。
- [x] **3. 候補欄をIME風に** — 白地・細い灰色枠・独立した番号列・淡い青の選択背景・通常ウェイトの文字へ変更。三角マーカーは廃止。見た目の好みについては利用者の実画面で調整余地あり。
- [x] **4. 初期5件→5番選択で9件** — `InitialCandidates=5`、`MaxCandidates=9`。5番へ到達したその表示で9件へ展開し、同じ語の選択中は展開状態を維持。入力・取消・次の語で初期表示へ戻る。候補が少ない場合は実件数まで。
- [x] **5. 表示位置** — 縦余白を`OffsetY=24`（96DPI基準）へ修正し、上下とも近いキャレット端から24px相当を空ける。手元設定も反映。利用者から縦は「おおむねちょうどいい」と回答あり。追加の横位置の指摘を受け、`OffsetX=0`を候補枠左端ではなく候補文字開始位置がキャレットXに合う計算へ修正。番号欄と余白の分だけ枠を左へ出す（150%では42物理px）。画面端では画面内への収まりを優先。横も修正反映後に利用者から「おおむねちょうどよい」と回答があり、縦横の調整を完了。
- [x] **6. 不要な「's」候補** — ベース語があり、訳がなく、短縮形でもない所有格は通常の候補索引から除外。辞書本体の語は保持し、`teacher'`のようにアポストロフィまで入力すれば候補に出る。`it's`/`he's`等の短縮形と訳のある見出しは保持。上流の固定コミット・SHA256・原ライセンスは維持して再生成。
- [x] **7. 自動学習の実装確認と説明** — 既実装。選択確定・語境界で実テキストを再確認した単語を個人DBへ記録し、使用回数と最終使用日時で順位を加点。未知語は既定2回で候補へ昇格、手動登録は即有効。追加依頼によりChrome/Brave/Edge/Codexを含む全アプリの学習を既定ONへ変更。未登録・補完無効アプリも安全な対応欄なら学習だけ行う。除外アプリ・未対応欄・パスワード・readonly・IME ON等は対象外。数字・URL・メール・一部技術語や認証情報らしい文字列は自動登録しない。

## 検証結果

- AutoHotkey v2.0.28 x64、`tools/verify.ps1 -Dpi -SelectionIntegration`：構文4入口、core 87、IME 56、navigation 92、UIA 369、サクラ27、DPI 292、専用Edit実キー28項目を通過。構文ラッパーは削除済み。
- `tests/test_dictionary.py`：10試験を通過。実配布辞書と再生成結果のバイト一致、所有格の通常候補除外、アポストロフィ指定・短縮形の保持を確認。
- DPI試験：4モニター（すべて150%）で新GUIの実配置を確認。100～300%の模擬作業領域・文字寸法も通過。異なる実モニター倍率の組合せと実IMEとの見た目の比較は未確認。
- 本体：開始時のPID 51908だけを辞書更新前に停止。更新後PID 59300で復帰し、対象CommandLine、単一プロセス、応答、2秒後の生存を確認。他のAHK/IMEは操作していない。
- README・手動試験表を更新。個人設定は表示件数・オフセットのみ変更し、学習設定・個人DBは手動変更していない。commit/pushは実施していない。
- 接続済みChrome DevToolsによる追試：`type_text`/`fill`/`press_key`のDOM入力を確認。候補表示・数字選択・選択後Enterはこの入力経路で不成立、未選択EnterはDOM上で通常改行を確認。OS実キーでの成功とは扱わない。証拠はGit除外の`tests/results/chrome-devtools/cdp-events.json`と各`*-observer.json`。本体コード・安全制限は変更していない。
- Chrome手入力による追試：候補表示、Tab→3、Tab→Enter（改行なし）、未選択Enter（確定なし・通常改行）の4項目を利用者の回答と本体数値診断・専用フォームの読み取りで照合しPASS。証拠はGit除外の`tests/results/chrome-devtools/manual-monitor.jsonl`と`manual-*-snapshot.json`、`manual-enter-events.json`。エージェントはChromeの前面化・フォーカス変更・キー注入を行っていない。読み取り監視だけを終了し、本体・Chrome等は維持した。
- 上下の距離修正後：`tools/verify.ps1 -Dpi`で構文4入口、core 87・IME 56・navigation 92・UIA 372・サクラ27・DPI 391を通過。上下のキャレット端から24px相当の余白、行高・5→9行展開・画面端を検証。実4モニター全150%の非アクティブ配置を確認。稼働中だった本体だけPID 59300→59216へ再起動し、単一・応答・Hook・2秒後生存と他AHKの維持を確認。修正後のChrome・サクラ・Codexでの距離は利用者の目視確認待ち。
- その後、利用者から縦位置は「おおむねちょうどいい」と回答あり。横位置を候補文字開始基準へ修正した後も同じ検証を行い、DPIは439 checksへ増加、他の回帰もすべてPASS。本体だけPID 59216→16500へ再起動し、単一・応答・Hook・2秒後生存と他AHK維持を確認。横も修正後に利用者から「おおむねちょうどよい」と回答があり、実際の距離感の調整を完了。証拠はGit除外の`tests/results/candidate-spacing/restart-horizontal.json`。

依頼された7項目の実装・指定されたChrome専用フォームでの主要操作確認は完了。Chromeの手入力では補完が動作することを確認した。任意のWebアプリでの互換性、Chromeへの合成OSキー自動試験、初期5行→9行や配置の実表示確認は今回の確認範囲に含めない。

## 追加依頼：全アプリでの学習・未知語2回

- 候補表示とは独立して、アプリ名に依らず安全な対応欄で学習。Chrome/Codex等・補完無効・未登録アプリも学習ONとし、手元設定へ反映した。Excluded・未対応欄・パスワード・readonly・IME ON等の制限は維持。
- 未知語は既定2回。既存DBに2回以上記録済みの未知語も候補になる。個人DBの手動変更・再生成は不要。
- `tools/verify.ps1 -LearningOnly`：構文4入口、core 102・IME 56・navigation 92・UIA 372・サクラ27・実キー学習55項目をすべてPASS。本体だけPID 16500→55736へ復帰し、単一・応答・Hook・2秒後生存・他AHK10本維持を確認。
- 今回の学習書込みの実入力試験は専用Win32 Edit。Chrome/Codexでの新設定の実入力学習は未検証。詳細は`docs/VALIDATION.md`の追加節。commit/pushは行っていない。
