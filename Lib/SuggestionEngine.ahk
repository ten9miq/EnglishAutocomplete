#Requires AutoHotkey v2.0+

class EacSuggestionEngine {
    __New(path, config, personal) {
        this.Config := config
        this.Personal := personal
        this.Db := EacSQLite(path, true)
        if this.Db.Query("PRAGMA user_version")[1][1] != "1"
            throw Error("Unsupported dictionary schema; rebuild dictionary")
    }

    Search(prefix) {
        prefix := StrLower(prefix)
        if StrLen(prefix) < this.Config.MinLength || !EacSuggestionEngine.ValidPrefix(prefix)
            return []
        pool := Map(), blocked := Map()
        ; At most 12 static rows per source; never scan a prefix range of words.
        for source in [1, 2] {
            if (source = 1 && !this.Config.SCOWL) || (source = 2 && !this.Config.EJDict)
                continue
            lists := this.Db.Query("SELECT ids FROM prefix_top WHERE prefix=? AND source=?", [prefix, source])
            if !lists.Length
                continue
            ids := lists[1][1]
            if !RegExMatch(ids, "^\d+(?:,\d+)*$")
                throw Error("Invalid dictionary index")
            for row in this.Db.Query("SELECT norm,word,score,translation FROM words WHERE id IN (" ids ")")
                pool[row[1]] := {Norm: row[1], Word: row[2], Score: Integer(row[3]), Translation: row[4], Learned: false}
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
