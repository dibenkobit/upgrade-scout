# Upgrade Scout

<img src="logo/logo.png" alt="Logo d'Upgrade Scout" width="128" align="right">

**Trouve à l'hôtel des ventes l'équipement meilleur que le vôtre et dans vos moyens.** Un addon pour World of Warcraft Forever.

**[Télécharger sur CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · Français · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Ouvrez l'hôtel des ventes, cliquez sur l'onglet **Améliorations** et appuyez sur **Scanner**. Vous
obtenez la liste de l'équipement meilleur que celui que vous portez, emplacement par emplacement,
avec les prix. Appuyez sur **Acheter** pour l'objet que vous voulez.

## Ce qu'il fait

- Évalue l'équipement avec ses propres poids pour chaque arbre de talents, calculés avec le
  simulateur [wowsims/forever](https://github.com/wowsims/forever). Pawn n'est pas nécessaire.
- Montre seulement ce que vous pouvez équiper tout de suite et payer.
- Marque deux objets par emplacement. **Meilleure amélioration** est le plus fort.
  **Meilleure affaire** est le moins cher par point d'amélioration.
- **Meilleur ensemble pour** choisit les améliorations qui, ensemble, apportent le plus pour votre
  or, ou pour une somme que vous saisissez.
- L'onglet **Consommables** liste les potions, élixirs, nourritures et bandages que vous pouvez
  utiliser. Les plus utiles pour votre personnage viennent en premier.
- Les deux onglets fonctionnent aussi pour vos autres personnages.

Toutes les classes, tous les niveaux. Anglais, chinois (simplifié et traditionnel), allemand,
russe, français, espagnol, portugais du Brésil et coréen.

## Installation

**[Installer depuis CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

L'application CurseForge s'occupe de tout.

Il vous faut World of Warcraft Forever (1.60.1). Aucun autre addon n'est nécessaire.

À la main :

1. Téléchargez `UpgradeScout-<version>-forever.zip` sur [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   ou dans les [versions GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Décompressez-le dans `World of Warcraft\_forever_\Interface\AddOns`.
3. Relancez le jeu.

## Bon à savoir

- Le score d'un objet est la somme de ses caractéristiques, chacune multipliée par son poids dans le
  profil. Le profil se choisit dans la liste **Profil** ; au départ, elle indique celui qui convient
  à votre classe. Choisissez celui de votre arbre de talents. L'infobulle de la liste dit d'où
  viennent les poids.
- Les poids sont calculés pour un personnage de niveau 60 : c'est une approximation. Sous le
  niveau 60, le toucher, le critique, la hâte et l'expertise comptent moins, d'après des simulations
  de personnages qui montent de niveau.
- L'endurance (sauf pour les tanks), et pour un soigneur l'intelligence, l'esprit et la régénération de mana, sont fixés à la main : une simulation de dégâts ne dit pas ce que coûte de rester en vie ou de manquer de mana.
- Un `~` après le nom d'un profil signifie qu'aucune simulation ne couvre encore cet
  arbre et que ses poids sont estimés.
- Les prix sont des prix d'achat immédiat. Les enchères sans achat immédiat sont ignorées.
- **Top 5 par emplacement** garde la liste courte. Désactivez-le pour voir toutes les améliorations.
  Le scan dure alors plus longtemps, jusqu'à quelques minutes dans un hôtel des ventes bien rempli.
- Un `*` jaune après un nom : l'objet a des effets que le score ne compte pas.
- Les potions de vie et de mana n'ont pas de score : aucun poids ne chiffre « rend 700 points
  de vie ».
- Des bottes « du tigre » et des bottes « de la baleine » sont des objets différents, à des prix
  différents. L'onglet « Vente » du jeu les montre tous dans une seule liste. Le prix le plus bas
  peut donc y être celui d'un autre objet.

## Acheter pour un autre personnage

1. Connectez-vous une fois avec l'autre personnage, l'addon installé. L'addon retient son
   équipement, son niveau et ses compétences.
2. Avec le personnage qui est à l'hôtel des ventes, choisissez le profil de l'autre personnage dans
   la liste **Profil** et appuyez sur **Scanner**.

La liste est maintenant faite pour ce personnage. C'est toujours celui que vous jouez qui paie.

À une boîte aux lettres, récupérez l'équipement acheté dans votre courrier. Un bouton sous la
fenêtre du courrier le met alors dans une lettre pour ce personnage. Vérifiez la lettre et appuyez
sur **Envoyer**. Les consommables, vous les envoyez vous-même.

L'addon connaît l'autre personnage tel qu'il était la dernière fois que vous l'avez joué.
Reconnectez-vous avec lui quand il a pris un niveau ou changé d'équipement.

## Commandes

- `/upscout` ouvre l'onglet « Améliorations ». L'hôtel des ventes doit être ouvert.
- `/upscout stats` montre combien de temps a pris le dernier scan.
- `/upscout stats` suivi d'un objet (Maj-clic pour l'insérer dans la ligne de discussion) montre
  chaque caractéristique de l'objet, son poids dans le profil et leur total.
- `/upscout forget Nom` retire un personnage supprimé de la liste.

## Développement

Les tests et la publication des versions sont décrits dans la [version anglaise](../README.md#development).

## Licence

Tous droits réservés, voir [LICENSE](../LICENSE). Les poids ont été calculés avec
[wowsims/forever](https://github.com/wowsims/forever), et leur part sous le niveau 60 avec [MythicSim](https://github.com/sage3648/mythicsim-forever-engine).
Tous deux sont sous licence MIT.
