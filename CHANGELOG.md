# Journal des changements

## 1.0.0

Première version stable. Ce que la 1.x promet : les fichiers **stables** ne cassent rien sans cycle de dépréciation (deux versions
mineures) ; les **provisoires** peuvent changer avec une ligne « Cassant » ici. La règle est dans `docs/stability.md` de qlang.

- **Stable** : `csv`, `toml`, `template`, `jwt`, `i18n`, `cli`, `queue`, `schedule`, `mail`, `notify`, `s3` et le cœur web (`web/app`,
  `session`, `validate`, `migrate`, `query`, `cache`, `middleware`, `health`, `limit`, `auth`, `upload`, `testing`). Tous ont leurs tests
  (`*_test.q`) et leur section d'`API.md` ; `web/health` en a de nouveaux (`web/health_test.q`).
- **Provisoire** : `yaml` et `xml` (des sous-ensembles des formats) et le reste de `web/` (`container`, `openapi`, `ws`, `relations`,
  `policy`, `resource`, `seed`, `queue_admin`, `metrics`, `events`, `commands`, `locale`, `refresh`, `proxy`, `accounts`, `admin`,
  passés d'expérimental). Plus aucun fichier n'est expérimental.
- **Avec qlang** : écrit et testé pour qlang 1.1 et plus (331 tests) ; un nouveau qlang mineur ne casse pas la std (voir le README).
- **Formatage.** Les fichiers sont écrits avec `qlang fmt` 1.0 (quatre espaces par niveau).

## 0.20.0 et avant

Voir les releases du dépôt.
