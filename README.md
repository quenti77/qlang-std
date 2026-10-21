# qlang-std

Des modules en qlang pur pour le langage [qlang](https://github.com/quenti77/qlang), à installer
comme un paquet : **CSV**, **gabarits de texte** et **TOML**.

## Installation

Dans le projet qui les utilise :

```sh
qlang add std --git https://github.com/quenti77/qlang-std --tag v0.1.0
```

puis, dans un fichier `.q` :

```
import "@std/csv.q" as csv
import "@std/template.q" as template
import "@std/toml.q" as toml
```

(Il faut `qlang` 0.32 ou plus.)

## Les modules

| Module | Rôle |
| --- | --- |
| [`csv.q`](csv.q) | lire et écrire du CSV (RFC 4180) : guillemets, séparateur au choix, retours à la ligne dans un champ, en-têtes |
| [`template.q`](template.q) | gabarits de texte : `{{ valeur }}`, filtres, `{% if %}`, `{% for %}`, échappement HTML |
| [`toml.q`](toml.q) | lire du TOML dans un `Json` : tables, tableaux de tables, tableaux, tables en ligne, chaînes multilignes |

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
