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

## Le paquet `web`

```
import "@std/web/app.q" as web
import "@std/web/middleware.q" as mw
```

| Module | Rôle |
| --- | --- |
| [`web/container.q`](web/container.q) | conteneur d'injection : une fonction qui rend un `T` *fournit* un `T`, ses paramètres sont ses besoins ; singleton, `#[Scoped]` (par requête), `#[Transient]` ; `validate()` trouve ce qui manque ou boucle avant la première requête |
| [`web/app.q`](web/app.q) | l'application : routes `#[web.Get("/users/:id")]`, paramètres remplis par `#[web.Path]`, `#[web.Query]`, `#[web.Body]` (JSON lu comme le type du paramètre, puis validé), `#[web.Header]`, `#[web.CookieValue]` ou par un service ; le résultat devient la réponse (JSON, `Result`, `HttpError`, `404` pour `none`) |
| [`web/middleware.q`](web/middleware.q) | `logging`, `security_headers`, `cors`, `bearer_token`, `request_id` |
| [`web/validate.q`](web/validate.q) | règles en annotations sur les champs : `#[NotBlank]`, `#[Length(2, 40)]`, `#[Min(18)]`, `#[Email]`, `#[Pattern(...)]`, `#[OneOf([...])]`, `#[Valid]` (structures imbriquées) et les vôtres |
| [`web/query.q`](web/query.q) | constructeur de requêtes SQL avec `?` partout et noms vérifiés ; lignes lues comme des structures |
| [`web/migrate.q`](web/migrate.q) | migrations (`up` / `down`) appliquées dans une transaction, mémorisées dans `schema_migrations` |
| [`web/session.q`](web/session.q) | sessions dans un cookie signé, messages flash, protection CSRF |

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

Les annotations s'écrivent avec le nom du module (`web.Get`) : `Post`, `Delete`... sont des noms de
modèles trop courants pour les prendre.

### Ce que le paquet ne fait pas (encore)

Événements, cache, traductions, commandes en ligne de commande, files de tâches, OpenAPI,
WebSocket, contrôleurs en classes (les gestionnaires sont des fonctions), ORM à relations. Le
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
