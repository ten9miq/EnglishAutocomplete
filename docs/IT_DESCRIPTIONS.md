# IT日本語説明の正本

`data/it-descriptions.jsonl` を唯一の正本とする。UTF-8（BOMなし）のJSONLで、1語を1物理行のJSONオブジェクトに記述する。空行、コメント、外側の配列、重複キーは認めない。行末はLFまたはCRLF、最終行の改行は任意。語の大文字・小文字を無視した順で並べる。

各行には次の7項目を過不足なく指定する。

| 項目 | 条件 |
| --- | --- |
| `word` | 既存CSpell語彙に含まれる2〜64文字の見出し。正規化後の重複不可 |
| `description` | 独自に記述した短い日本語説明。1〜100文字、前後空白・制御文字・改行不可 |
| `reference_url` | 事実照合に使った公式一次資料のHTTPS URL。認証情報・空白不可 |
| `license` | `MIT` |
| `verified_on` | 事実を確認した日付。`YYYY-MM-DD` |
| `origin` | `original` |
| `review_status` | `draft` または `reviewed` |

説明は一般的な技術上の事実を独自の短文にまとめる。参照先の定義文を転載・翻訳して説明とするものではない。MITはこの独自説明に適用し、参照先の文章やソフトウェアのライセンスを変更しない。各語のURLは出典確認用であり、実行時にアクセスしない。

追加・修正時は公式資料の内容と説明の意味を照合し、確認日を記録する。作成途中は`draft`とし、確認を完了してから`reviewed`へ変更する。ビルダーは全行を検証するが、辞書へ反映するのは`reviewed`だけ。`draft`を含む重複語や不正メタデータもビルドエラーとし、該当行番号を表示する。

JSONLは説明と出典だけを管理する。CSpellの語彙・表示表記・点数・補完索引は変更しない。AI補助語の正本は従来どおり`data/ai-supplement.json`。

生成DBとmanifestには`it_descriptions_file`（正本ファイル名）、`it_descriptions_sha256`（全JSONLのバイト列のSHA256）、`it_description_count`（採用済み件数）、`it_description_license`を記録する。配布ZIPにはJSONLも含める。
