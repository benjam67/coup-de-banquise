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
