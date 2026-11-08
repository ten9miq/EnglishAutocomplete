# 辞書・実行環境のライセンス

本ディレクトリで新規作成したコードと文書は [MIT License](LICENSE)。辞書データには以下の独立した条件が適用される。

| 対象 | 固定ソース | 条件・同梱表示 |
|---|---|---|
| SCOWLv2 | [engramtech/scowl](https://github.com/engramtech/scowl/tree/3373b9f12dce7016c9df2713ef733131e9022bc1), commit `3373b9f12dce7016c9df2713ef733131e9022bc1` | 集合著作物はKevin Atkinsonほか。MIT類似の許諾と元データそれぞれの表示を含む [Copyright全文](licenses/SCOWL-Copyright.txt) を配布に必ず含める。単純なMIT表記だけで代替しない。 |
| EJDict・frequency | [kujirahand/EJDict](https://github.com/kujirahand/EJDict/tree/2dd9e71ffcefce89b4d946ce07bf51fa0573aac0), commit `2dd9e71ffcefce89b4d946ce07bf51fa0573aac0` | CC0 1.0。上流の [CC0全文](licenses/EJDict-CC0.txt) を同梱。日本語訳、追加語彙、100/850/2000語の頻度階層に使用。 |
| SQLite API | Windows所有の `%WINDIR%/System32/winsqlite3.dll` | OSのDLLを絶対パスでロードする。DLL自体は本成果物に再配布しない。[SQLite原著](https://sqlite.org/copyright.html) はpublic domain。Windowsコンポーネントの配布条件とは別。 |
| AutoHotkey v2 | 利用者が用意する [公式配布](https://www.autohotkey.com/) | 本成果物には実行ファイルを含めない。PortableランタイムやAhk2Exe生成物を第三者へ配布する場合はAutoHotkeyのGPL等の条件と対応するソース提供義務を別途満たす。 |

`data/dictionary.db` はSCOWLとEJDict双方を含む派生データである。語ごとのsourceビット(1=SCOWL、2=EJDict、3=両方)と、DB内`metadata`にソース・size・検索索引仕様を記録している。ZIPのSHA256は `tools/sources.lock.json`、生成物のSHA256は `data/dictionary.manifest.json` に記録する。

wordfreqや追加コーパスの頻度データは使っていない。EJDictのfrequencyは階層への所属として利用し、ファイル内の並び順を頻度順位とは解釈しない。SCOWLのsizeは語彙の一般性の目安であり、実際の使用回数ではない。

確認日: 2026-11-08。上流の [SCOWL Copyright](https://github.com/engramtech/scowl/blob/3373b9f12dce7016c9df2713ef733131e9022bc1/Copyright) と [EJDict LICENSE](https://github.com/kujirahand/EJDict/blob/2dd9e71ffcefce89b4d946ce07bf51fa0573aac0/LICENSE) を取得して同梱した。
