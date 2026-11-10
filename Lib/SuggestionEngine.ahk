#Requires AutoHotkey v2.0+

class EacSuggestionEngine {
    __New(path, config, personal) {
        this.Config := config
        this.Personal := personal
        this.Db := EacSQLite(path, true)
        if this.Db.Query("PRAGMA user_version")[1][1] != "2"
            throw Error("Unsupported dictionary schema; rebuild dictionary")
    }

    Search(prefix) {
        items := this.SearchWhole(prefix)
        if items.Length
            return items
        tail := EacSuggestionEngine.SegmentPrefix(prefix)
        if tail = "" || StrLen(tail) < this.Config.MinLength
            return items
        items := this.SearchWhole(tail)
        for item in items {
            ; Keep the entire observed token for field/commit validation. Only
            ; the last segment is looked up; existing text is never replaced.
            item.InputPrefix := prefix
            item.CompletionPrefix := tail
        }
        return items
    }

    SearchWhole(prefix) {
        prefix := StrLower(prefix)
        if StrLen(prefix) < this.Config.MinLength || !EacSuggestionEngine.ValidPrefix(prefix)
            return []
        pool := Map(), blocked := Map()
        ; At most 12 static rows per source; never scan a prefix range of words.
        for source in [1, 2, 4, 8] {
            if (source = 1 && !this.Config.SCOWL) || (source = 2 && !this.Config.EJDict)
                || (source >= 4 && !this.Config.IT) || (source = 8 && !this.Config.AISupplement)
                continue
            lists := this.Db.Query("SELECT ids FROM prefix_top WHERE prefix=? AND source=?", [prefix, source])
            if !lists.Length
                continue
            ids := lists[1][1]
            if !RegExMatch(ids, "^\d+(?:,\d+)*$")
                throw Error("Invalid dictionary index")
            if source < 4 {
                rows := this.Db.Query("SELECT norm,word,score,translation FROM words WHERE id IN (" ids ")")
                boost := 0
            } else {
                rows := this.Db.Query("SELECT w.norm,it.word,it.score,it.translation FROM it_entries it "
                    "JOIN words w ON w.id=it.word_id WHERE it.source=? AND w.id IN (" ids ")", [source])
                boost := this.Config.ITScoreBoost + (source = 8 ? this.Config.AIScoreBoost : 0)
            }
            for row in rows {
                norm := row[1], score := Integer(row[3]) + boost
                if !pool.Has(norm)
                    pool[norm] := {Norm: norm, Word: row[2], Score: score, Translation: row[4], Learned: false}
                else {
                    ; A shared word keeps its best enabled score, with IT/AI spelling.
                    pool[norm].Word := row[2]
                    pool[norm].Score := Max(pool[norm].Score, score)
                    if row[4] != ""
                        pool[norm].Translation := row[4]
                }
                if source >= 4 && pool[norm].Translation = ""
                    pool[norm].Translation := "[IT]"
            }
        }
        for row in this.Personal.Find(prefix) {
            norm := row[1]
            if Integer(row[6]) {
                blocked[norm] := true
                continue
            }
            if Integer(row[3]) < this.Personal.Promotion && !Integer(row[4]) && !pool.Has(norm)
                continue
            if !pool.Has(norm)
                pool[norm] := {Norm: norm, Word: row[2], Score: 0, Translation: "[個人辞書]"}
            item := pool[norm]
            item.Learned := Integer(row[3]) > 0 && !Integer(row[4])
            if Integer(row[4])
                item.Word := row[2]
            age := Max(0, DateDiff(A_NowUTC, "19700101000000", "Seconds") - Integer(row[5]))
            item.Score += (Integer(row[4]) ? 10000 : 0) + Min(5000, Integer(row[3]) * 100)
                + Max(0, 200 - Floor(age / 86400) * 10)
        }
        result := []
        for norm, item in pool {
            if blocked.Has(norm) || this.Personal.IsBlocked(norm) || norm = prefix || SubStr(norm, 1, StrLen(prefix)) != prefix
                continue
            position := 1
            while position <= result.Length && (result[position].Score > item.Score
                || (result[position].Score = item.Score && StrCompare(result[position].Norm, norm, true) < 0))
                position += 1
            result.InsertAt(position, item)
        }
        while result.Length > this.Config.MaxCandidates
            result.Pop()
        return result
    }

    static SegmentPrefix(prefix) {
        ; A safe compound token may contain filename/identifier separators.
        ; Emails, URLs, paths and credential-shaped tokens never use fallback.
        if !EacUserDictionary.Valid(prefix, true)
            || RegExMatch(prefix, "i)^(?:token|secret|password|apikey|bearer|authorization)[_A-Za-z0-9.-]*$")
            return ""
        return RegExMatch(prefix, "[-._]([A-Za-z][A-Za-z0-9]*)$", &part) ? part[1] : ""
    }

    static CompletionWord(item, prefix) {
        if !item.HasOwnProp("InputPrefix")
            return this.ApplyCase(item.Word, prefix)
        if !(item.InputPrefix == prefix)
            return ""
        tail := this.SegmentPrefix(prefix)
        if tail = "" || !(tail == item.CompletionPrefix)
            return ""
        return SubStr(prefix, 1, StrLen(prefix) - StrLen(tail)) this.ApplyCase(item.Word, tail)
    }

    static ApplyCase(word, prefix) {
        if prefix == StrUpper(prefix)
            return StrUpper(word)
        if RegExMatch(prefix, "^[A-Z][a-z]+$") && word == StrLower(word)
            return StrUpper(SubStr(word, 1, 1)) SubStr(word, 2)
        return word
    }

    static ValidPrefix(prefix) => EacUserDictionary.Valid(prefix, true)
        || (StrLen(prefix) <= 64 && SubStr(prefix, -1) = "'" && EacUserDictionary.Valid(SubStr(prefix, 1, -1), true))
}
