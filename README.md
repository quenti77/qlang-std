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

(Il faut `qlang` 0.62 ou plus. Pour une application web, `qlang init --web mon-site` crée le projet, avec ce paquet.)

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
| [`mail.q`](mail.q) | courriel par l'API HTTP d'un service (`ResendMailer`, `PostmarkMailer`, `SendgridMailer`, `MailgunMailer`), `MemoryMailer` pour les tests, `LogMailer` pour le développement ; adresses et sujet vérifiés (pas d'injection d'en-tête) ; tâche `SendMail` pour la file |
| [`s3.q`](s3.q) | stockage S3 (Amazon, R2, MinIO, B2...) signé en AWS v4 : `put`, `get`, `put_bytes`, `get_bytes`, `exists`, `delete`, et `presign` (URL signée pour qu'un navigateur envoie ou lise lui-même) ; vérifié contre les exemples d'AWS et un vrai MinIO |
| [`schedule.q`](schedule.q) | tâches périodiques : `plan.cron("nuit", "0 3 * * *", f)`, `every_minutes`, `daily_at` ; une tâche ne tourne qu'une fois par minute même avec plusieurs machines (cache partagé) ; commandes `schedule:run` et `schedule:work` |
| [`notify.q`](notify.q) | une notification, plusieurs endroits : `MailChannel`, `WebhookChannel` (Slack, Discord, JSON), `InboxChannel` (boîte de réception en base : `list`, `unread_count`, `mark_read`) ; `Notifier.send(["mail", "inbox"], à, notification)` |

```
#[cli.Command("greet", "Says hello")]
fun greet(#[cli.Arg] name: string, #[cli.Opt(short: "l")] loud: bool, console: cli.Console) -> int
  console.line(if loud then "HELLO {name}" else "Hello {name}" end)
  0
end
```

`examples/deploy` montre comment l'exploiter : un Dockerfile, un `docker-compose.yml` (web, worker, planificateur, Redis), des unités systemd et un Caddyfile ; testé de bout en bout (arrêt propre inclus). `examples/chat` est un salon de discussion WebSocket qui marche avec plusieurs workers : `CHAT_DB=sqlite://chat.db qlang serve examples/chat/main.q --workers 2`, ou avec Redis `CHAT_REDIS=redis://127.0.0.1:6379 qlang serve examples/chat/main.q --workers 2`. Les tests qui demandent un serveur Redis lisent `QLANG_TEST_REDIS` (sans lui ils se terminent aussitôt).

`examples/blog/console.q` met ces commandes à côté de l'API : `qlang run examples/blog/console.q -- help`.

## Le paquet `web`

```
import "@std/web/app.q" as web
import "@std/web/middleware.q" as mw
```

| Module | Rôle |
| --- | --- |
| [`web/container.q`](web/container.q) | conteneur d'injection : une fonction qui rend un `T` *fournit* un `T`, ses paramètres sont ses besoins ; singleton, `#[Scoped]` (par requête), `#[Transient]` ; une structure marquée `#[Service]` est construite **à partir de ses champs** (`app.services(Reflect.constructors(module))`, `app.bind<Interface, Implémentation>()`) ; `validate()` trouve ce qui manque ou boucle avant la première requête |
| [`web/app.q`](web/app.q) | l'application : routes `#[web.Get("/users/:id")]`, paramètres remplis par `#[web.Path]`, `#[web.Query]`, `#[web.Body]` (JSON lu comme le type du paramètre, puis validé), `#[web.Header]`, `#[web.CookieValue]` ou par un service ; le résultat devient la réponse (JSON, `Result`, `HttpError`, `404` pour `none`) |
| [`web/middleware.q`](web/middleware.q) | `logging`, `security_headers`, `cors` / `cors_with` (méthodes, en-têtes, identifiants), `bearer_token`, `request_id` |
| [`web/validate.q`](web/validate.q) | règles en annotations sur les champs : `#[NotBlank]`, `#[Length(2, 40)]`, `#[Min(18)]`, `#[Email]`, `#[Pattern(...)]`, `#[OneOf([...])]`, `#[Valid]` (structures imbriquées) et les vôtres |
| [`web/query.q`](web/query.q) | constructeur de requêtes SQL avec `?` partout et noms vérifiés ; lignes lues comme des structures ; `paginate(db, page, per_page)` / `paginate_request` : une page avec le total, `Page.to_json(chemin)` (données, meta, liens) |
| [`web/relations.q`](web/relations.q) | relations sans N+1 : `has_many<P, C>(db, parents, "id", "posts", "user_id")`, `has_one`, `belongs_to`, `belongs_to_many` (table pivot) : **une requête par relation**, chaque parent revient avec ses lignes liées (`With<P, R>`), `has_many_where` pour filtrer ou trier |
| [`web/migrate.q`](web/migrate.q) | migrations (`up` / `down`) appliquées dans une transaction, mémorisées dans `schema_migrations` |
| [`web/seed.q`](web/seed.q) | données de test : `Factory.table("users")` avec `field("email", fun(n) ...)` (le numéro de la ligne rend les valeurs uniques), `state("admin", {...})`, `make()` / `create(db)` / `create_many(db, 25)` (tout ou rien) ; `Seeder` et `run_seeders` (chacun dans une transaction) ; la commande `db:seed` |
| [`web/session.q`](web/session.q) | sessions dans un cookie signé et **expirant**, ou **côté serveur** (`Options { store: ... }` : base de données, Redis ; le cookie ne porte qu'un identifiant signé) (`HttpOnly`, `SameSite=Lax`, `Secure` au choix), `regenerate()` à la connexion, messages flash, saisie du formulaire à remontrer après une erreur (`flash_input`, `old`), protection CSRF (`protect(app, secret, Options {})`, jeton lu aussi dans un formulaire avec fichiers) |
| [`web/upload.q`](web/upload.q) | fichiers envoyés par un formulaire `multipart/form-data` : `receive(req, Rules { max_size, max_files, types })` (taille, nombre, **type lu dans le contenu**), `Upload.save(dossier)` sous un nom aléatoire |
| [`web/resource.q`](web/resource.q) | ce qu'une API montre d'un modèle : `Resource.only([...])` ou `Resource.hide([...])`, `rename`, `add` (champ calculé), `one` / `many` / `of_value` ; plusieurs vues du même modèle, un champ non listé ne part jamais |
| [`web/policy.q`](web/policy.q) | autorisations par règle : `Policy<User, Post>.create()`, `allow("update", fun(user, post) ...)`, `before` (l'administrateur), `can` / `authorize` (403) / `filter` ; une capacité non définie est refusée |
| [`web/testing.q`](web/testing.q) | `Client` : envoie des requêtes à `App.handle` sans serveur, garde les cookies, `post_json`, `post_form`, `post_multipart` (fichiers), `json<T>()`, `expect_status` |
| [`web/events.q`](web/events.q) | `Events` : `listen<E>(f)`, `dispatch(événement)`, par type d'événement |
| [`yaml.q`](yaml.q) | YAML (blocs, collections en ligne, `|` et `>`, commentaires, plusieurs documents) lu en `Json` et écrit (`dump`) ; sans ancres, alias ni étiquettes |
| [`xml.q`](xml.q) | XML lu en arbre `XmlNode` et écrit (`to_text`, `write_pretty`), avec un XPath simple (`select`, `first`, `values` : `//item[@id='2']/text()`) ; les entités d'un `DOCTYPE` ne sont pas définies |
| [`web/accounts.q`](web/accounts.q) | le parcours d'un utilisateur, monté en une ligne : inscription, connexion/déconnexion (session), mot de passe oublié par courriel, vérification du courriel, gardes `require_login` / `require_verified` ; Argon2, jetons à usage unique dont seul le hachage est gardé, même réponse pour un courriel inconnu ou un mauvais mot de passe |
| [`web/admin.q`](web/admin.q) | un panneau d'administration : tu déclares tes tables (colonnes, recherche, tri), `mount(app, admin, "/admin", garde)` monte une API JSON (liste paginée, voir, créer, modifier, supprimer) et des pages HTML sans JavaScript ; garde obligatoire, texte échappé, colonnes vérifiées, jeton CSRF sur les écritures |
| [`web/proxy.q`](web/proxy.q) | derrière un proxy inverse (TLS) : `is_https`, `client_ip`, `host`, `redirect_to_https()` |
| [`web/cache.q`](web/cache.q) | `Cache` (texte ou valeurs en JSON, durée de vie, `remember`, `increment`) sur un `Store` : mémoire du worker, fichiers de la machine, base de données (`DbStore`) ou Redis |
| [`web/limit.q`](web/limit.q) | `rate_limit(cache, 100, 60, by_header("x-forwarded-for"))` : `429` avec `Retry-After` ; avec `Cache.redis(...)` le compte est exact pour toutes les machines |
| [`web/locale.q`](web/locale.q) | la langue de la requête (`?lang=`, cookie, `Accept-Language`) et un service `Lang` pour les gestionnaires : `use_locale(app, traducteur, ["en", "fr"])` |
| [`web/commands.q`](web/commands.q) | commandes prêtes à l'emploi : `routes:list`, `db:migrate`, `db:rollback`, `db:status`, `db:seed`, `locale:missing` |
| [`jwt.q`](jwt.q) | JSON Web Tokens (HS256/384/512, RS, **PS**, ES, EdDSA) : `sign(claims, Key.hs256(secret))`, `verify(token, [keys], Options)` (signature, algorithme imposé par *tes* clés, `kid`, `exp`/`nbf`/`iss`/`aud`, marge d'horloge), clés RSA/ECDSA/Ed25519 (PEM ou JWK) pour signer et vérifier les jetons d'un fournisseur d'identité, `keys_from_jwks` |
| [`web/auth.q`](web/auth.q) | `jwt_guard(keys, options)` (401 avec `WWW-Authenticate`), `scope_guard(["admin"])` (403), `claims_of<T>(req)`, `fetch_jwks(url, cache, ttl)` |
| [`web/refresh.q`](web/refresh.q) | jetons de rafraîchissement : `Refresh.new(db)`, `issue(user)`, `rotate(token)` (chaque usage donne un nouveau jeton et brûle l'ancien ; un jeton brûlé qui revient ferme toute la session), `revoke`, `revoke_user`, `purge` ; la base ne garde qu'un hachage |
| [`web/ws.q`](web/ws.q) | WebSocket : `Hub` (salons d'un worker), `Relay` (une lecture par worker et par salon, pas par connexion) sur un `Feed` : `Bus`/`DbFeed` (la base de données) ou `RedisBus`/`RedisFeed` (publier/s'abonner, sans lecture à vide), `origin_guard` ; `WsClient` de `testing.q` teste un WebSocket sans réseau |
| [`web/queue_admin.q`](web/queue_admin.q) | tableau de bord de la file : `queue_admin.mount(app, queue, "/admin/queue", garde)` : une page HTML, `GET …/stats` en JSON, `POST …/retry/:id` et `…/forget/:id` |
| [`web/metrics.q`](web/metrics.q) | métriques Prometheus : `Metrics.new(cache, app)`, `app.use(metrics.middleware())`, `metrics.mount(app, "/metrics", garde)` ; compteurs par **motif de route** (jamais par chemin), histogramme des durées, taille de la file ; partagés entre workers avec `Cache.redis` |
| [`web/health.q`](web/health.q) | `Health.new()`, `check("database", db_check(db))`, `mount(app, "/health")` : `…/live` (toujours 200) et `…/ready` (503 si un contrôle échoue, sans dire pourquoi) |
| [`web/openapi.q`](web/openapi.q) | `openapi(app, titre, version)` : le document OpenAPI 3.1 d'après les routes, `openapi_route(app, "/openapi.json", ...)` |

### Démarrer, et où mettre quoi

```sh
qlang init --web mon-site && cd mon-site
qlang serve main.q --watch --dev          # http://localhost:8080
qlang test
```

`App.boot` assemble l'application d'après ce que les modules **déclarent** : rien à enregistrer à la main.

```
import "@std/web/app.q" as web
import "providers.q" as providers
import "controllers.q" as controllers

let app = web.App.boot(Reflect.declared(providers).concat(Reflect.declared(controllers)))

fun handle(req: Request) -> Response
  app.handle(req)
end
```

- une **fonction** de `providers.q` est un fournisseur : elle rend un `T`, ses paramètres sont ses besoins ;
- une **structure** marquée `#[di.Service]` est un service, construit à partir de ses champs ;
- une **fonction** avec `#[web.Get(...)]` est une route ; une **structure** marquée `#[web.Controller("/x")]` est un
  contrôleur (ses champs sont ses dépendances, ses méthodes publiques annotées sont ses routes) ;
- `boot` s'arrête avec la liste des erreurs de câblage (service manquant, cycle, garde inconnue) plutôt que de
  démarrer à moitié ; `App.assemble` fait la même chose sans cette vérification (pour les tests qui ajoutent des
  services ensuite). Un contrôleur oublié n'existe plus : s'il est dans un module donné à `boot`, il est trouvé ;
  pour une application montée à la main, `app.declare(Reflect.declared(controllers))` fait signaler par
  `validate()` chaque contrôleur déclaré mais jamais enregistré, au lieu d'un `404` silencieux.

Organisation conseillée d'un projet qui grandit : `main.q` (la fonction `handle`, les middlewares du serveur),
`app.q` (`build()`, que les tests appellent aussi), `providers.q` ou un dossier `infrastructure/` (configuration,
base, dépôts), `domain/` (les structures et les règles, sans HTTP), `controllers/` (les routes, qui n'appellent
que des services), `*_test.q` à côté de ce qu'ils testent. `boot` accepte plusieurs modules :
`Reflect.declared(a).concat(Reflect.declared(b))`.

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
- **Sessions côté serveur** (base, Redis) : la session est un cookie signé, limité à environ 3 Ko et lisible par
  l'utilisateur (signé, pas chiffré) ; ni identifiant côté serveur à révoquer, ni partage entre appareils.

## Licence

MIT.
