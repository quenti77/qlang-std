# Journal des changements

## Non publié

- **Le reste de `web/` passe d'expérimental à provisoire** (`container`, `openapi`, `ws`, `relations`, `policy`, `resource`, `seed`,
  `queue_admin`, `metrics`, `events`, `commands`, `locale`, `refresh`, `proxy`, `accounts`, `admin`) : chacun a ses tests et sa
  section d'`API.md`. Plus aucun fichier n'est expérimental. La std reste en 0.x : elle passera en 1.0 quand le cœur web (`web/app`,
  `session`, `validate`, `migrate`, `query`, `cache`, `middleware`, `health`, `limit`, `auth`, `upload`, `testing`) sera stable, ce
  qui demande une version mineure sans changement cassant sur lui.
- **Niveaux de stabilité.** `csv`, `toml`, `template`, `jwt`, `i18n` et `cli` sont **stables** : leurs tests (`*_test.q`) et leur
  `API.md` sont complets, et le paquet passe tous ses tests avec qlang 1.1 (327). `yaml` et `xml` restent provisoires (des
  sous-ensembles des formats), de même que `queue`, `schedule`, `mail`, `notify`, `s3` et le cœur web ; le reste de `web/` est
  expérimental. La règle des niveaux est dans `docs/stability.md` de qlang.
- **Formatage.** Les fichiers sont écrits avec `qlang fmt` 1.0 (quatre espaces par niveau).

## 0.20.0 et avant

Voir les releases du dépôt.
