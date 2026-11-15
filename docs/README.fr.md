# Upgrade Scout

<img src="logo/logo.png" alt="Logo d'Upgrade Scout" width="128" align="right">

**Trouve à l'hôtel des ventes les améliorations d'équipement et les consommables que vous pouvez utiliser et qui sont dans vos moyens.** Un addon pour World of Warcraft Forever.

**Télécharger sur [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) ou [Wago](https://addons.wago.io/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · Français · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Ouvrez l'hôtel des ventes, cliquez sur l'onglet **Améliorations** et appuyez sur **Scanner**. Vous
obtenez la liste de l'équipement meilleur que celui que vous portez, emplacement par emplacement,
avec les prix. Appuyez sur **Acheter** pour l'objet que vous voulez.

L'onglet **Consommables** fait de même pour les potions, élixirs, flacons, nourritures, bandages et
huiles. Il liste ceux que votre personnage peut utiliser et évalue ce que chacun apporte.
**Le meilleur pour moi** n'en garde qu'un de chaque type : celui qui vous apporte le plus, à son
prix le plus bas.

En dehors de l'hôtel des ventes, l'infobulle de chaque objet montre de combien il est meilleur que
ce que vous portez : dans vos sacs, dans le butin, dans une récompense de quête et dans un lien du
chat.

## Ce qu'il fait

- Le scan montre seulement ce que vous pouvez équiper tout de suite et payer.
- L'onglet **Consommables** liste les potions, élixirs, flacons, nourritures, bandages et huiles
  que vous pouvez utiliser. Les plus utiles pour votre personnage viennent en premier. Ce qui ne
  vous sert à rien est écarté.
- Marque deux objets par emplacement. **Meilleure amélioration** est le plus fort.
  **Meilleure affaire** est le moins cher par point d'amélioration.
- **Coût net** affiche ce qu'un objet vous coûte au final : son achat immédiat moins ce qu'un
  marchand vous en donne quand vous n'en avez plus besoin. Acheté 4 pièces d'argent et revendu 3,
  il vous en a coûté 1.
- **Meilleur ensemble pour** choisit les améliorations qui, ensemble, apportent le plus pour votre
  or, ou pour une somme que vous saisissez.
- Le menu **Filtres** resserre la liste. **Cuir uniquement**, **Mailles uniquement** ou
  **Plaques uniquement** écarte les armures plus légères que la plus lourde que porte votre
  personnage. **Amélioration d'au moins** écarte les améliorations inférieures au pourcentage que
  vous saisissez.
- Sert aussi à acheter pour vos autres personnages. Un bouton à la boîte aux lettres met
  l'équipement acheté dans une lettre pour eux.
- L'infobulle de chaque objet montre de combien il est meilleur que ce que vous portez, pour chaque
  arbre de talents de votre classe, par exemple Armes, Fureur et Protection pour un guerrier.
  Dans la fenêtre de l'addon, vous pouvez ne garder qu'une ligne, celle de votre arbre, et
  choisir où ces lignes s'affichent : dans les onglets de l'addon à l'hôtel des ventes, dans le
  reste du jeu, ou nulle part.
- Une flèche verte sur l'icône d'un objet dans vos sacs ou à la banque signale une amélioration
  que vous pouvez équiper tout de suite. Une flèche grise : une amélioration dès que vous aurez
  atteint son niveau.
- Fonctionne dès l'installation. La liste **Profil** commence sur l'arbre de talents où vous avez
  le plus de points.
- À la première connexion, une fenêtre montre ce que fait l'addon. Vous pouvez y désactiver les
  lignes dans l'infobulle et les flèches dans les sacs. Le bouton de l'addon près de la minicarte
  la rouvre.
- Évalue l'équipement avec ses propres poids pour chaque arbre de talents, calculés avec le
  simulateur [wowsims/forever](https://github.com/wowsims/forever). Aucun autre addon n'est nécessaire.
- Vous utilisez Pawn ? Choisissez **Pawn** dans la fenêtre de l'addon : l'équipement est alors évalué
  selon vos échelles Pawn, et non selon les poids de l'addon. Les listes et les flèches des sacs les
  suivent, et les lignes de l'infobulle sont celles de Pawn.

Toutes les classes, tous les niveaux. Anglais, chinois (simplifié et traditionnel), allemand,
russe, français, espagnol, portugais du Brésil et coréen.

## Installation

**Installer depuis [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) ou [Wago](https://addons.wago.io/addons/upgrade-scout)**

L'application CurseForge ou Wago s'occupe de tout.

Il vous faut World of Warcraft Forever (1.60.1). Aucun autre addon n'est nécessaire.

À la main :

1. Téléchargez `UpgradeScout-<version>-forever.zip` sur [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout), [Wago](https://addons.wago.io/addons/upgrade-scout)
   ou dans les [versions GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Décompressez-le dans `World of Warcraft\_forever_\Interface\AddOns`.
3. Relancez le jeu.

## Bon à savoir

- Le score d'un objet est la somme de ses caractéristiques, chacune multipliée par son poids dans le
  profil. Le profil se choisit dans la liste **Profil** ; au départ, elle indique l'arbre de talents
  où vous avez le plus de points. Vous pouvez en choisir un autre.
- Les poids sont calculés pour un personnage de niveau 60 : c'est une approximation. Sous le
  niveau 60, le toucher, le critique, la hâte et l'expertise comptent moins, d'après des simulations
  de personnages qui montent de niveau.
- L'endurance (sauf pour les tanks), et pour un soigneur l'intelligence, l'esprit et la régénération de mana, sont fixés à la main : une simulation de dégâts ne dit pas ce que coûte de rester en vie ou de manquer de mana.
- L'armure, la valeur de blocage, la défense, l'esquive et la parade comptent dans chaque profil : par rapport à l'endurance, autant qu'elles servent au tank du simulateur.
- Un `~` après le nom d'un profil signifie qu'aucune simulation ne couvre encore cet
  arbre et que ses poids sont estimés.
- Les prix sont des prix d'achat immédiat. Les enchères sans achat immédiat sont ignorées.
- Avec **Coût net** coché, la colonne des prix et la **Meilleure affaire** suivent le coût net. Ce
  que vous pouvez payer et **Meilleur ensemble pour** suivent toujours l'achat immédiat : c'est ce
  que vous payez.
- **Top 5 par emplacement** garde la liste courte. Désactivez-le pour voir toutes les améliorations.
  Le scan dure alors plus longtemps, jusqu'à quelques minutes dans un hôtel des ventes bien rempli.
- **Amélioration** dit de combien l'objet est meilleur que celui qu'il remplace, en pour cent.
  **Nouveau** : l'emplacement est vide. Des points, comme `+6 pts` : ce que vous y portez
  n'apporte rien à votre profil.
- **Cuir uniquement** nomme l'armure la plus lourde que votre personnage a appris à porter : le
  cuir pour un chasseur, les mailles une fois qu'il les a apprises. Capes, anneaux, armes et
  boucliers restent dans la liste. Un mage, un prêtre et un démoniste ne portent que du tissu et
  n'ont pas cette case.
- **Amélioration d'au moins** suit le pourcentage de la colonne **Amélioration**. Un objet pour un
  emplacement vide reste toujours.
- Chaque personnage a sa propre case **Cuir uniquement** et son propre nombre pour
  **Amélioration d'au moins**. Quand vous achetez pour un autre personnage, vous voyez et réglez
  les siens.
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

- `/upscout` ouvre la fenêtre de l'addon : ce qu'il fait et ses réglages. À l'hôtel des ventes, il
  ouvre l'onglet « Améliorations ».
- `/upscout stats` montre combien de temps a pris le dernier scan.
- `/upscout stats` suivi d'un objet (Maj-clic pour l'insérer dans la ligne de discussion) montre
  chaque caractéristique de l'objet, son poids dans le profil et leur total.
- `/upscout forget Nom` retire un personnage supprimé de la liste.

## Développement

Les tests et la publication des versions sont décrits dans la [version anglaise](DEVELOPMENT.md).

## Licence

Tous droits réservés, voir [LICENSE](../LICENSE). Les poids ont été calculés avec
[wowsims/forever](https://github.com/wowsims/forever), et leur part sous le niveau 60 avec [MythicSim](https://github.com/sage3648/mythicsim-forever-engine).
Tous deux sont sous licence MIT.
