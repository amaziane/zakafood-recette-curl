# Recette zakafood.com en ligne de commande

Teste tout le parcours sans navigateur (curl + bash + python3), puis liste les e-mails partis.

## Mise en route
1. `cp .env.example .env` puis remplis : `TEST_EMAIL`, `WP_ADMIN_USER`, `WP_APP_PASSWORD`
   (Utilisateurs › Profil › Mots de passe d'application) et, si possible, `WP_ADMIN_PASSWORD`.
2. `./run.sh`

## Ce qui est testé
| Étape | Contenu |
|---|---|
| 01 | Pages publiques (200, temps, title), 404, robots.txt, sitemap, JSON-LD, API, prix masqués et panier/commande refusés aux visiteurs |
| 02 | Formulaire contact (cas incomplet + envoi réel), newsletter (adresse invalide + inscription) |
| 03 | Devenir client : refus sans TVA / sans CGV / e-mail invalide / doublon, création du compte, statut « en attente », connexion bloquée avant validation |
| 04 | Validation comme dans « Clients Zaka Food » (e-mail d'approbation + lien mot de passe) |
| 05 | Connexion, mauvais mot de passe, Mon compte, prix visibles, mot de passe perdu |
| 06 | Panier (arrondi au carton), commande virement et commande paiement à la livraison, statuts, passage en cours / note client / terminée / annulée |
| 07 | Suppression des commandes et du compte de test |
| 99 | Récap + liste des e-mails envoyés pendant le run (journal SureMails) |

Les e-mails sont vérifiés automatiquement dans le journal SureMails (envoyé / échec) ;
il te reste à regarder leur contenu dans les boîtes.

## Options
- `./run.sh --keep` : ne supprime rien à la fin (pour voir commandes et compte dans l'admin)
- `./run.sh 05 06` : rejoue seulement certaines étapes
- `./run.sh cleanup` : supprime ce qu'un run `--keep` a laissé

Fichiers de travail (cookies, réponses, état) dans `.work/` — à ne pas committer.
