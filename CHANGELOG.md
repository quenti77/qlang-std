# Journal des changements

## Non publié

- **Niveaux de stabilité.** `csv`, `toml`, `template`, `jwt`, `i18n` et `cli` sont **stables** : leurs tests (`*_test.q`) et leur
  `API.md` sont complets, et le paquet passe tous ses tests avec qlang 1.1 (327). `yaml` et `xml` restent provisoires (des
  sous-ensembles des formats), de même que `queue`, `schedule`, `mail`, `notify`, `s3` et le cœur web ; le reste de `web/` est
  expérimental. La règle des niveaux est dans `docs/stability.md` de qlang.
- **Formatage.** Les fichiers sont écrits avec `qlang fmt` 1.0 (quatre espaces par niveau).

## 0.20.0 et avant

Voir les releases du dépôt.
