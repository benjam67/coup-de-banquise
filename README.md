# Coup de Banquise

Un yéti, une batte, un pingouin. Jeu 3D dans le navigateur (three.js), inspiré de Yeti Sports.

- Frappe le pingouin au bon moment, fais-le planer, ricocher et rebondir sur les mouettes.
- 10 univers, un tous les 1 000 m, jusqu'à la Lune à 10 000 m.
- Compétences, battes et tenues à débloquer avec des poissons et des défis.

## Jouer

Ouvre `index.html` dans un navigateur récent. Tout le jeu tient dans ce seul fichier
(three.js est chargé depuis un CDN, une connexion internet est donc nécessaire).

## Réglages et mesure

- La qualité de départ est choisie selon l'appareil (basse ou éco sur téléphone), puis ajustée et mémorisée automatiquement. La roue des paramètres permet de la forcer, et de limiter le jeu à 30 images par seconde pour économiser la batterie.
- Ajoute `?debug` à l'adresse pour afficher un compteur : images par seconde, 95e centile de la durée d'image, appels de dessin, triangles, géométries et textures en mémoire.

## Classement en ligne

Pseudo, compte anonyme, classement général et classement de la semaine (du lundi 0 h au dimanche minuit, heure de Paris). Le jeu reste un fichier statique : les données sont chez Supabase.

Tant que `SUPA_URL` et `SUPA_KEY` sont vides dans `index.html`, le classement est masqué et le jeu ne contacte aucun serveur.

Mise en service :

1. Créer un projet Supabase en région UE.
2. Authentication › Sign In / Providers : activer « Allow anonymous sign-ins ».
3. SQL Editor : coller et exécuter `supabase/schema.sql` (relançable sans dégât).
4. Project Settings › API Keys : copier l'URL du projet et la clé « publishable » dans `SUPA_URL` et `SUPA_KEY`, en haut de la section « Classement en ligne » de `index.html`. Cette clé est faite pour être publique.

À savoir :

- Offre gratuite : un projet sans activité pendant une semaine est mis en pause, il faut alors le relancer depuis le tableau de bord. Les créations de comptes anonymes sont limitées à 30 par heure et par adresse IP (réglable dans Authentication › Rate Limits).
- Le compte anonyme vit dans le stockage du navigateur : vider ses données ou changer de téléphone fait perdre le pseudo et les scores.
- Aucun contrôle de plausibilité des scores. Pour retirer une ligne à la main, voir les requêtes en bas de `supabase/schema.sql`.
- Un score qui n'a pas pu partir (pas de réseau) reste sur l'appareil et repart au lancer suivant.
