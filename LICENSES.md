# 辞書・実行環境のライセンス

本ディレクトリで新規作成したコードと文書は [MIT License](LICENSE)。辞書データには以下の独立した条件が適用される。

| 対象 | 固定ソース | 条件・同梱表示 |
|---|---|---|
| SCOWLv2 | [engramtech/scowl](https://github.com/engramtech/scowl/tree/3373b9f12dce7016c9df2713ef733131e9022bc1), commit `3373b9f12dce7016c9df2713ef733131e9022bc1` | 集合著作物はKevin Atkinsonほか。MIT類似の許諾と元データそれぞれの表示を含む [Copyright全文](licenses/SCOWL-Copyright.txt) を配布に必ず含める。単純なMIT表記だけで代替しない。 |
| EJDict・frequency | [kujirahand/EJDict](https://github.com/kujirahand/EJDict/tree/2dd9e71ffcefce89b4d946ce07bf51fa0573aac0), commit `2dd9e71ffcefce89b4d946ce07bf51fa0573aac0` | CC0 1.0。上流の [CC0全文](licenses/EJDict-CC0.txt) を同梱。日本語訳、追加語彙、100/850/2000語の頻度階層に使用。 |
| CSpell software-terms | [streetsidesoftware/cspell-dicts](https://github.com/streetsidesoftware/cspell-dicts/tree/db01cf70052ad247fa7d8ea94a9d8e87af6e358a/dictionaries/software-terms), commit `db01cf70052ad247fa7d8ea94a9d8e87af6e358a` | MIT。Street Side Softwareの著作権表示・許諾を含む[原文全文](licenses/CSpell-software-terms-MIT.txt)を同梱。選定した8語彙ファイルを使用。CSpellの他パッケージのライセンスを一括してMITとは扱わない。 |
| AI補助語彙 | [data/ai-supplement.json](data/ai-supplement.json)、2026-11-10確認 | 本プロジェクトのMIT。公式の製品名・企業名・プロジェクト名を独自に選定し、短い説明を作成。各語のURLは確認元であり、サイト本文や定義文は転載していない。名称の商標権は各権利者に帰属。 |
| IT用語の独自説明 | [data/it-descriptions.json](data/it-descriptions.json)、各語に確認日を記録 | 本プロジェクトのMIT。技術的事実を公式資料で確認し、候補表示用の短い日本語説明を独自に作成。各語の参考URLは事実確認先であり、文書の転載・翻訳・外部ライセンスの再許諾を示さない。原文を取得・配布する辞書としては扱わない。 |
| SQLite API | Windows所有の `%WINDIR%/System32/winsqlite3.dll` | OSのDLLを絶対パスでロードする。DLL自体は本成果物に再配布しない。[SQLite原著](https://sqlite.org/copyright.html) はpublic domain。Windowsコンポーネントの配布条件とは別。 |
| AutoHotkey v2 | 利用者が用意する [公式配布](https://www.autohotkey.com/) | 本成果物には実行ファイルを含めない。PortableランタイムやAhk2Exe生成物を第三者へ配布する場合はAutoHotkeyのGPL等の条件と対応するソース提供義務を別途満たす。 |

`data/dictionary.db` は上記辞書を含む派生データである。語ごとのsourceビット(1=SCOWL、2=EJDict、4=CSpell、8=AI補助、重複時はビットOR)と、DB内`metadata`にソース・size・検索索引仕様を記録している。SCOWL/EJDictのZIPとCSpellの選定ファイルそれぞれのSHA256は `tools/sources.lock.json`、生成物とAI補助JSONのSHA256は `data/dictionary.manifest.json` に記録する。

IT説明JSONもSHA256・採用件数・MIT表記をmanifestへ記録する。DBの`it_description_provenance`には採用語ごとの参考URL・ライセンス・確認日・独自作成区分・確認状態を保存する。CSpellの語彙ライセンスと、この独自説明のライセンスを別に記録し、双方の条件とプロジェクトのLICENSEを保持する。将来外部文書を転載・翻訳して追加する場合は、元のライセンスを確認し、この独自作成MITデータへ混入させない。

CSpellの選定ファイルは`coding-terms.txt`、`software-terms.txt`、`computing-acronyms.txt`、`software-services.txt`、`network-os.txt`、`network-protocols.txt`、`cybersecurity-terms.txt`、`software-tools.txt`。出典は上記固定コミットの`dictionaries/software-terms/src/`。取得テキストは`tools/sources/cspell/`へ保持し、配布物には生成辞書と原ライセンスを含める。

wordfreqや追加コーパスの頻度データは使っていない。EJDictのfrequencyは階層への所属として利用し、ファイル内の並び順を頻度順位とは解釈しない。SCOWLのsizeは語彙の一般性の目安であり、実際の使用回数ではない。

確認日: 2026-11-08。上流の [SCOWL Copyright](https://github.com/engramtech/scowl/blob/3373b9f12dce7016c9df2713ef733131e9022bc1/Copyright) と [EJDict LICENSE](https://github.com/kujirahand/EJDict/blob/2dd9e71ffcefce89b4d946ce07bf51fa0573aac0/LICENSE) を取得して同梱した。
