# qlang-std

Des modules en qlang pur pour le langage [qlang](https://github.com/quenti77/qlang), à installer
comme un paquet : **CSV**, **gabarits de texte**, **TOML** et de quoi écrire des **applications web**
(`web/` : conteneur d'injection, routes à paramètres injectés, middleware, validation, constructeur de
requêtes, migrations, sessions).

## Installation

Dans le projet qui les utilise :

```sh
qlang add std --git https://github.com/quenti77/qlang-std --tag v0.2.0
```

puis, dans un fichier `.q` :

```
import "@std/csv.q" as csv
import "@std/template.q" as template
import "@std/toml.q" as toml
```

(Il faut `qlang` 0.49 ou plus.)

## Les modules

| Module | Rôle |
| --- | --- |
| [`csv.q`](csv.q) | lire et écrire du CSV (RFC 4180) : guillemets, séparateur au choix, retours à la ligne dans un champ, en-têtes |
| [`template.q`](template.q) | gabarits de texte : `{{ valeur }}`, filtres, `{% if %}`, `{% for %}`, échappement HTML |
| [`toml.q`](toml.q) | lire du TOML dans un `Json` : tables, tableaux de tables, tableaux, tables en ligne, chaînes multilignes |

## Commandes et traductions

| Module | Rôle |
| --- | --- |
| [`cli.q`](cli.q) | commandes en ligne de commande : une fonction `#[cli.Command("db:migrate", "…")]` dont les paramètres sont `#[cli.Arg]` (positionnels, `array<T>` pour le reste), `#[cli.Opt(short: "n")]` (options ; `bool` = drapeau), une `Console` (`line`, `error`, `table`, `ask`, `confirm`) ou un service du conteneur ; code de sortie, aide générée (`help`, `commande --help`), suggestion en cas de faute de frappe, `Cli.run(args, console)` testable |
| [`queue.q`](queue.q) | file de tâches dans la base (`Queue.new(db, "sqlite")`) **ou dans Redis** (`Queue.redis(redis, "default")` : le worker attend sur la liste, une nouvelle tâche part tout de suite) : `queue.handle<T>(fun(job: T) -> string? ...)`, `queue.push(job)`, `push_in(job, secondes)`, reprises espacées (10 s, 1 min, 5 min, 15 min), tâches abandonnées (`failed`, `retry_failed`), une tâche laissée « en cours » par un worker mort est redonnée ; options par type de tâche (`#[queue.Retry(tries: 5, backoff: [10, 60])]`, `#[queue.Unique]`, `#[queue.Delay]`), intergiciels de tâche (`queue.use(rate_limited(...))`, `without_overlapping`, `Outcome.release`), **files nommées** avec priorités (`queue.lane("high", driver)`, `#[queue.OnQueue(name: "high")]`, `WorkOptions { queues: ["high", "default"] }`), **chaînes** (`queue.chain().add(a).add(b).dispatch()`) et **lots** (`queue.batch().add(a).add(b).when_done(c).when_failed(d).dispatch()`), `work_with(WorkOptions)` et arrêt propre du worker sur Ctrl-C/`kill` ; `queue.work(once)` dans un processus à part ou la commande `queue:work` |
| [`i18n.q`](i18n.q) | traductions : fichiers JSON par langue, `{nom}` à remplir, formes du pluriel selon la langue (`tn`), repli `fr-CA` → `fr` → langue par défaut → la clé, choix de la langue d'après `Accept-Language`, nombres écrits à la manière de la langue, `missing` liste ce qui reste à traduire |

```
#[cli.Command("greet", "Says hello")]
fun greet(#[cli.Arg] name: string, #[cli.Opt(short: "l")] loud: bool, console: cli.Console) -> int
  console.line(if loud then "HELLO {name}" else "Hello {name}" end)
  0
end
```

`examples/chat` est un salon de discussion WebSocket qui marche avec plusieurs workers : `CHAT_DB=sqlite://chat.db qlang serve examples/chat/main.q --workers 2`, ou avec Redis `CHAT_REDIS=redis://127.0.0.1:6379 qlang serve examples/chat/main.q --workers 2`. Les tests qui demandent un serveur Redis lisent `QLANG_TEST_REDIS` (sans lui ils se terminent aussitôt).

`examples/blog/console.q` met ces commandes à côté de l'API : `qlang run examples/blog/console.q -- help`.

## Le paquet `web`

```
import "@std/web/app.q" as web
import "@std/web/middleware.q" as mw
```

| Module | Rôle |
| --- | --- |
| [`web/container.q`](web/container.q) | conteneur d'injection : une fonction qui rend un `T` *fournit* un `T`, ses paramètres sont ses besoins ; singleton, `#[Scoped]` (par requête), `#[Transient]` ; `validate()` trouve ce qui manque ou boucle avant la première requête |
| [`web/app.q`](web/app.q) | l'application : routes `#[web.Get("/users/:id")]`, paramètres remplis par `#[web.Path]`, `#[web.Query]`, `#[web.Body]` (JSON lu comme le type du paramètre, puis validé), `#[web.Header]`, `#[web.CookieValue]` ou par un service ; le résultat devient la réponse (JSON, `Result`, `HttpError`, `404` pour `none`) |
| [`web/middleware.q`](web/middleware.q) | `logging`, `security_headers`, `cors` / `cors_with` (méthodes, en-têtes, identifiants), `bearer_token`, `request_id` |
| [`web/validate.q`](web/validate.q) | règles en annotations sur les champs : `#[NotBlank]`, `#[Length(2, 40)]`, `#[Min(18)]`, `#[Email]`, `#[Pattern(...)]`, `#[OneOf([...])]`, `#[Valid]` (structures imbriquées) et les vôtres |
| [`web/query.q`](web/query.q) | constructeur de requêtes SQL avec `?` partout et noms vérifiés ; lignes lues comme des structures |
| [`web/relations.q`](web/relations.q) | relations sans N+1 : `has_many<P, C>(db, parents, "id", "posts", "user_id")`, `has_one`, `belongs_to`, `belongs_to_many` (table pivot) : **une requête par relation**, chaque parent revient avec ses lignes liées (`With<P, R>`), `has_many_where` pour filtrer ou trier |
| [`web/migrate.q`](web/migrate.q) | migrations (`up` / `down`) appliquées dans une transaction, mémorisées dans `schema_migrations` |
| [`web/session.q`](web/session.q) | sessions dans un cookie signé, messages flash, protection CSRF |
| [`web/testing.q`](web/testing.q) | `Client` : envoie des requêtes à `App.handle` sans serveur, garde les cookies, `post_json`, `post_form`, `json<T>()`, `expect_status` |
| [`web/events.q`](web/events.q) | `Events` : `listen<E>(f)`, `dispatch(événement)`, par type d'événement |
| [`web/cache.q`](web/cache.q) | `Cache` (texte ou valeurs en JSON, durée de vie, `remember`, `increment`) sur un `Store` : mémoire du worker, fichiers de la machine ou Redis |
| [`web/limit.q`](web/limit.q) | `rate_limit(cache, 100, 60, by_header("x-forwarded-for"))` : `429` avec `Retry-After` ; avec `Cache.redis(...)` le compte est exact pour toutes les machines |
| [`web/locale.q`](web/locale.q) | la langue de la requête (`?lang=`, cookie, `Accept-Language`) et un service `Lang` pour les gestionnaires : `use_locale(app, traducteur, ["en", "fr"])` |
| [`web/commands.q`](web/commands.q) | commandes prêtes à l'emploi : `routes:list`, `db:migrate`, `db:rollback`, `db:status`, `locale:missing` |
| [`jwt.q`](jwt.q) | JSON Web Tokens (HS256/384/512, RS, **PS**, ES, EdDSA) : `sign(claims, Key.hs256(secret))`, `verify(token, [keys], Options)` (signature, algorithme imposé par *tes* clés, `kid`, `exp`/`nbf`/`iss`/`aud`, marge d'horloge), clés RSA/ECDSA/Ed25519 (PEM ou JWK) pour signer et vérifier les jetons d'un fournisseur d'identité, `keys_from_jwks` |
| [`web/auth.q`](web/auth.q) | `jwt_guard(keys, options)` (401 avec `WWW-Authenticate`), `scope_guard(["admin"])` (403), `claims_of<T>(req)`, `fetch_jwks(url, cache, ttl)` |
| [`web/refresh.q`](web/refresh.q) | jetons de rafraîchissement : `Refresh.new(db)`, `issue(user)`, `rotate(token)` (chaque usage donne un nouveau jeton et brûle l'ancien ; un jeton brûlé qui revient ferme toute la session), `revoke`, `revoke_user`, `purge` ; la base ne garde qu'un hachage |
| [`web/ws.q`](web/ws.q) | WebSocket : `Hub` (salons d'un worker), `Relay` (une lecture par worker et par salon, pas par connexion) sur un `Feed` : `Bus`/`DbFeed` (la base de données) ou `RedisBus`/`RedisFeed` (publier/s'abonner, sans lecture à vide), `origin_guard` ; `WsClient` de `testing.q` teste un WebSocket sans réseau |
| [`web/queue_admin.q`](web/queue_admin.q) | tableau de bord de la file : `queue_admin.mount(app, queue, "/admin/queue", garde)` : une page HTML, `GET …/stats` en JSON, `POST …/retry/:id` et `…/forget/:id` |
| [`web/openapi.q`](web/openapi.q) | `openapi(app, titre, version)` : le document OpenAPI 3.1 d'après les routes, `openapi_route(app, "/openapi.json", ...)` |

Un exemple complet (une API JSON avec SQLite) est dans [`examples/blog`](examples/blog) :

```
qlang serve examples/blog/main.q --dev
curl localhost:8080/posts
curl -X POST localhost:8080/posts -H 'X-User: ada' -d '{"title": "Second", "body": "Hi"}'
```

```
#[web.Post("/posts")]
#[web.Status(201)]
fun create(#[web.Body] input: NewPost, #[web.Header("X-User")] user: string, posts: Posts) -> Post
  posts.add(input.title, input.body, user)
end
```

Des routes peuvent aussi être les méthodes d'une structure : `#[web.Controller("/posts")]` sur la
structure, `#[web.Get("/:id")]` sur ses méthodes publiques, puis `app.controller(Posts { ... })`
(ou `app.controller_from_container<Posts>()` si un fournisseur rend une `Posts`). L'instance vit
autant que l'application : ce qui change à chaque requête arrive en paramètre de la méthode.

Des **gardes** protègent des routes : `app.guard("auth", fun(req: Request) -> Response? ... end)`
rend `none` pour laisser passer ou une réponse pour arrêter ; `#[web.Guard("auth")]` sur une
fonction, une méthode ou toute une structure contrôleur les applique. `#[web.Body]` lit aussi un
formulaire `application/x-www-form-urlencoded`. Un exemple complet avec comptes, sessions, mots de
passe et tâches est dans [`examples/tasks`](examples/tasks) ; le guide du site le suit pas à pas.

Les annotations s'écrivent avec le nom du module (`web.Get`) : `Post`, `Delete`... sont des noms de
modèles trop courants pour les prendre.

### Ce que le paquet ne fait pas (encore)

ORM à relations, JWT tout fait, un courtier de messages pour des milliers de connexions WebSocket. Le
serveur lui-même (`qlang serve`) reste derrière un proxy inverse pour TLS.

La documentation de chaque fonction est dans [API.md](API.md) (générée par `qlang doc`).

```
let rows = csv.parse("nom,ville\nAna,Lyon\n").unwrap()            -- [["nom", "ville"], ["Ana", "Lyon"]]
let people = csv.parse_records("nom,ville\nAna,Lyon\n").unwrap()   -- [{ "nom": "Ana", "ville": "Lyon" }]
print(csv.to_text(rows))

let page = template.render_text("Bonjour \{\{ nom | upper }}", { "nom": "ana" }).unwrap()   -- Bonjour ANA

let config = toml.parse("[serveur]\nport = 8080\n").unwrap()
print(config.get("serveur").unwrap().get("port").unwrap().as_number())   -- 8080.0
```

Une erreur de lecture est un `Err` avec le numéro de ligne ; rien ne s'arrête sur une donnée
invalide.

## Développer

```sh
qlang test          # tous les tests (fichiers *_test.q)
qlang doc -o API.md # régénérer l'API
```

## Pas encore

- **YAML** : un sous-ensemble courant reste à décider ; le format complet est très long à lire
  correctement.
- **Envoyer un mail (SMTP), S3** : impossible en qlang pur, il faut des fournisseurs d'`extern`
  (des programmes externes), qui demandent leur propre dépôt.

## Licence

MIT.
