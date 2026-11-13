# Upgrade Scout

<img src="logo/logo.png" alt="Logo d'Upgrade Scout" width="128" align="right">

**Trouve à l'hôtel des ventes l'équipement meilleur que le vôtre et dans vos moyens.** Un addon pour World of Warcraft Forever.

**[Télécharger sur CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [Русский](README.ru.md) · [Deutsch](README.de.md) · Français · [Español](README.es.md) · [Português](README.pt-BR.md) · [简体中文](README.zh-CN.md)

Ouvrez l'hôtel des ventes, cliquez sur l'onglet **Améliorations** et appuyez sur **Scanner**. Vous
obtenez la liste de l'équipement meilleur que celui que vous portez, emplacement par emplacement,
avec les prix. Appuyez sur **Acheter** pour l'objet que vous voulez.

## Ce qu'il fait

- Évalue l'équipement avec [Pawn](https://www.curseforge.com/wow/addons/pawn) : la liste correspond donc aux
  flèches vertes de Pawn.
- Montre seulement ce que vous pouvez équiper tout de suite et payer.
- Marque deux objets par emplacement. **Meilleure amélioration** est le plus fort.
  **Meilleure affaire** est le moins cher par point d'amélioration.
- **Meilleur ensemble pour** choisit les améliorations qui, ensemble, apportent le plus pour votre
  or, ou pour une somme que vous saisissez.
- L'onglet **Consommables** liste les potions, élixirs, nourritures et bandages que vous pouvez
  utiliser. Les plus utiles pour votre personnage viennent en premier.
- Les deux onglets fonctionnent aussi pour vos autres personnages.

Toutes les classes, tous les niveaux. Français, anglais, russe, allemand, espagnol, portugais du
Brésil et chinois simplifié.

## Installation

**[Installer depuis CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

L'application CurseForge s'occupe de tout, Pawn compris.

Il vous faut World of Warcraft Forever (1.60.1) et [Pawn](https://www.curseforge.com/wow/addons/pawn).
Sans Pawn, l'addon ne se charge pas.

À la main :

1. Téléchargez `UpgradeScout-<version>-forever.zip` sur [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   ou dans les [versions GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Décompressez-le dans `World of Warcraft\_forever_\Interface\AddOns`.
3. Relancez le jeu.

## Bon à savoir

- Les prix sont des prix d'achat immédiat. Les enchères sans achat immédiat sont ignorées.
- **Top 5 par emplacement** garde la liste courte. Désactivez-le pour voir toutes les améliorations.
  Le scan dure alors plus longtemps, jusqu'à quelques minutes dans un hôtel des ventes bien rempli.
- Un `*` jaune après un nom : l'objet a des effets que Pawn ne sait pas évaluer.
- Les potions de vie et de mana n'ont pas de score : Pawn n'a pas de valeur pour « rend 700 points
  de vie ».
- Des bottes « du tigre » et des bottes « de la baleine » sont des objets différents, à des prix
  différents. L'onglet « Vente » du jeu les montre tous dans une seule liste. Le prix le plus bas
  peut donc y être celui d'un autre objet.

## Acheter pour un autre personnage

1. Connectez-vous une fois avec l'autre personnage, l'addon installé. L'addon retient son
   équipement, son niveau et ses compétences.
2. Avec le personnage qui est à l'hôtel des ventes, choisissez l'échelle de l'autre personnage dans
   la liste **Échelle Pawn** et appuyez sur **Scanner**.

La liste est maintenant faite pour ce personnage. C'est toujours celui que vous jouez qui paie.

À une boîte aux lettres, récupérez l'équipement acheté dans votre courrier. Un bouton sous la
fenêtre du courrier le met alors dans une lettre pour ce personnage. Vérifiez la lettre et appuyez
sur **Envoyer**. Les consommables, vous les envoyez vous-même.

L'addon connaît l'autre personnage tel qu'il était la dernière fois que vous l'avez joué.
Reconnectez-vous avec lui quand il a pris un niveau ou changé d'équipement.

## Commandes

- `/upscout` ouvre l'onglet « Améliorations ». L'hôtel des ventes doit être ouvert.
- `/upscout stats` montre combien de temps a pris le dernier scan.
- `/upscout forget Nom` retire un personnage supprimé de la liste.

## Développement

Les tests et la publication des versions sont décrits dans la [version anglaise](../README.md#development).

## Licence

Tous droits réservés, voir [LICENSE](../LICENSE). Pawn est un addon à part, de Vger, et n'est pas
inclus.
