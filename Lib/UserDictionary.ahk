#Requires AutoHotkey v2.0+

class EacUserDictionary {
    __New(path, promotion := 2) {
        this.Enabled := false
        this.Db := false
        this.Promotion := promotion
        this.Fault := ""
        try {
            this.Db := EacSQLite(path)
            version := Integer(this.Db.Query("PRAGMA user_version")[1][1])
            if version > 1
                throw Error("Unsupported future user database schema")
            if !version {
                this.Db.Query("BEGIN IMMEDIATE")
                try {
                    this.Db.Query("CREATE TABLE IF NOT EXISTS personal(norm TEXT PRIMARY KEY, word TEXT NOT NULL, uses INTEGER NOT NULL DEFAULT 0, last_used INTEGER NOT NULL DEFAULT 0, manual INTEGER NOT NULL DEFAULT 0, blocked INTEGER NOT NULL DEFAULT 0) WITHOUT ROWID")
                    this.Db.Query("PRAGMA user_version=1")
                    this.Db.Query("COMMIT")
                } catch {
                    this.Db.Query("ROLLBACK")
                    throw Error("User database migration failed")
                }
            }
            this.Db.Query("PRAGMA secure_delete=ON")
            this.Enabled := true
        } catch as err {
            this.Fault := "User database unavailable (" err.Extra ")"
            if this.Db
                this.Db.Close()
        }
    }

    static Valid(word, manual := false) {
        if !RegExMatch(word, "^[A-Za-z][A-Za-z0-9_]*(?:['.-][A-Za-z0-9_]+)*$")
            || StrLen(word) < 2 || StrLen(word) > (manual ? 64 : 32)
            return false
        if !manual && (RegExMatch(word, "[0-9.-]") || RegExMatch(word, "i)^(?:token|secret|password|apikey|bearer|authorization)[_A-Za-z0-9]*$"))
            return false
        ; Conservative high-entropy/token heuristic, never claimed exhaustive.
        if !manual && StrLen(word) > 20 && RegExMatch(word, "[a-z]") && RegExMatch(word, "[A-Z]")
            return false
        return true
    }

    Observe(word, manual := false) {
        if !this.Enabled || !EacUserDictionary.Valid(word, manual)
            return false
        try {
            norm := StrLower(word)
            existing := this.Db.Query("SELECT blocked FROM personal WHERE norm=?", [norm])
            if existing.Length && Integer(existing[1][1])
                return false
            if !existing.Length && Integer(this.Db.Query("SELECT count(*) FROM personal")[1][1]) >= 10000
                return false
            this.Db.Query("INSERT INTO personal(norm,word,uses,last_used,manual) VALUES(?,?,1,strftime('%s','now'),?) ON CONFLICT(norm) DO UPDATE SET word=CASE WHEN excluded.manual=1 THEN excluded.word ELSE personal.word END,uses=uses+1,last_used=excluded.last_used,manual=max(manual,excluded.manual)", [norm, word, manual ? 1 : 0])
            return true
        } catch {
            this.Enabled := false
            this.Fault := "User database write failed; learning stopped"
            return false
        }
    }

    Find(prefix) {
        if !this.Enabled
            return []
        try return this.Db.Query("SELECT norm,word,uses,manual,last_used,blocked FROM personal WHERE blocked=0 AND norm>=? AND norm<? ORDER BY manual DESC,uses DESC,last_used DESC,norm LIMIT 64", [StrLower(prefix), StrLower(prefix) "{"])
        catch {
            this.Enabled := false
            this.Fault := "User database read failed; learning stopped"
            return []
        }
    }

    IsBlocked(norm) {
        if !this.Enabled
            return false
        rows := this.Db.Query("SELECT blocked FROM personal WHERE norm=?", [norm])
        return rows.Length && Integer(rows[1][1])
    }

    Block(word) {
        if !this.Enabled || !EacUserDictionary.Valid(word, true)
            return false
        this.Db.Query("INSERT INTO personal(norm,word,blocked) VALUES(?,?,1) ON CONFLICT(norm) DO UPDATE SET blocked=1,uses=0,manual=0", [StrLower(word), word])
        return true
    }

    Delete(word) {
        if this.Enabled
            this.Db.Query("DELETE FROM personal WHERE norm=?", [StrLower(word)])
    }

    ForgetLearned(word) {
        if !this.Enabled
            return false
        transaction := false
        try {
            this.Db.Query("BEGIN IMMEDIATE")
            transaction := true
            rows := this.Db.Query("SELECT uses,manual,blocked FROM personal WHERE norm=?", [StrLower(word)])
            eligible := rows.Length && Integer(rows[1][1]) > 0 && !Integer(rows[1][2]) && !Integer(rows[1][3])
            if eligible
                this.Db.Query("DELETE FROM personal WHERE norm=? AND manual=0 AND blocked=0", [StrLower(word)])
            this.Db.Query("COMMIT")
            return !!eligible
        } catch {
            if transaction
                try this.Db.Query("ROLLBACK")
            this.Enabled := false
            this.Fault := "User database delete failed; learning stopped"
            return false
        }
    }

    ResetFrequency() {
        if this.Enabled
            this.Db.Query("UPDATE personal SET uses=0,last_used=0")
    }

    Clear() {
        if this.Enabled {
            this.Db.Query("DELETE FROM personal")
            this.Db.Query("VACUUM")
        }
    }
}
