# Journal des changements

## 1.1.0

Un formulaire à champs répétés, un `else` sur `for`, des chemins de contrôleur sans `//`, et une limitation de débit par client. Rien de cassant, mais **il faut maintenant qlang 1.12 ou plus** (`req.form_all()` et `req.remote_addr`).

- **`#[web.Body]` lit un champ répété dans un `array<string>`** (ou `array<int>`, `array<float>`), comme un groupe de cases à cocher ; un champ absent donne un tableau vide (#43).
- **`{% for x in items %}...{% else %}...{% end %}`** : la partie `else` est rendue quand la liste est vide ou n'existe pas (#44).
- **Un préfixe de contrôleur et une route se rejoignent avec une seule `/`** : `#[Controller("/")]` avec `"/login"` donne `/login`, pas `//login` (#42). Une route `"/"` d'un contrôleur sous `/api` répond sur `/api`.
- **`limit.q`** : `by_remote_addr()`, `by_client_ip()` (l'adresse de `X-Forwarded-For` derrière un proxy, sinon celle de la connexion) et `rate_limit_on(methods, paths, ...)` pour ne limiter que le login (#45).

## 1.0.1

Le tag `v1.0.0` contenait encore `div` (avertissement `W001` à chaque import de `jwt.q`) ; cette version est la même avec `//` (#32), pour que qlang 1.9, qui retire `div`, puisse l'utiliser. Rien ne change pour un programme. **Il faut maintenant qlang 1.6 ou plus** (`//` n'existe pas avant).

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
