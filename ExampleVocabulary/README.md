# Custom Vocabulary

Plain-text vocabulary files for Detto. Point **Settings → Vocabulary → Custom Vocabulary** at any folder containing `.txt` files. Detto loads them at session start.

## File format

- One entry per line
- Lines starting with `#` are comments
- Blank lines ignored
- Files load alphabetically (later files override earlier ones for the same correction key)

## Two entry types

**Terms** (no `=` separator):

```
Cowichan
PostgreSQL
San Francisco
```

- Get **case normalization**: ASR output "cowichan" becomes "Cowichan".
- Single-word terms with 4+ characters also get **fuzzy matching** for near-misses (Levenshtein within `term.count / 4` edits, unambiguous candidates only).
- Multi-word terms get case normalization only (no fuzzy match).

**Corrections** (` = ` separator, note the spaces):

```
Post Grass = PostgreSQL
Couch and = Cowichan
```

- Applied first, before case normalization
- Case-insensitive, word-boundary aware
- Longest pattern matches first

## Danger rule

**Don't use bare real-English-word patterns** like `Barrack = Barrick`. They cause false corrections on legitimate uses ("barrack" is military housing). Use disambiguating multi-word patterns instead: `Barrack Mining = Barrick Mining`.

The same logic applies to short terms that resemble common words. If "Soft" gets wrongly produced by ASR when you mean "SAF", a `Soft = SAF` correction would mangle every legitimate use of "soft." For those cases, prefer to spell out the term in context rather than force a correction.

## File organization

Group files however you like. Detto concatenates them at load time:

```
vocabulary/
  clients.txt          # Client and contact names
  industry.txt         # Industry-specific terms
  corrections.txt      # Known ASR error patterns
```

See `example.txt` in this folder for a working starting point.

## Bundled packs

Detto ships with a bundled Canadian Politics pack (53 terms, 30 corrections) covering federal leaders, premiers, departments, trade agreements, and BC-specific names. Enable or disable bundled packs in Settings. Custom vocabulary loads **in addition to** any enabled bundled packs.
