# Upgrade Scout

<img src="logo/logo.png" alt="Logo d'Upgrade Scout" width="128" align="right">

**Trouve à l'hôtel des ventes les améliorations d'équipement et les consommables que vous pouvez utiliser et qui sont dans vos moyens.** Un addon pour World of Warcraft Forever.

**Télécharger sur [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) ou [Wago](https://addons.wago.io/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · Français · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Ouvrez l'hôtel des ventes, cliquez sur l'onglet **Améliorations** et appuyez sur **Scanner**. Vous
obtenez la liste de l'équipement meilleur que celui que vous portez, emplacement par emplacement,
avec les prix. Appuyez sur **Acheter** pour l'objet que vous voulez.

L'onglet **Consommables** fait de même pour les potions, élixirs, flacons, nourritures, bandages et
huiles. Il liste ceux qui apportent quelque chose à votre personnage et évalue ce que chacun
apporte. **Le meilleur pour moi** n'en garde qu'un de chaque type : celui qui vous apporte le plus,
à son prix le plus bas. **Tout ce que je peux utiliser** ajoute ce qui n'a pas de score :
nourriture et boissons simples, potions de soins et de mana, bandages.

En dehors de l'hôtel des ventes, l'infobulle de chaque objet montre de combien il est meilleur que
ce que vous portez : dans vos sacs, dans le butin, dans une récompense de quête et dans un lien du
chat.

## Ce qu'il fait

- Le scan montre seulement ce que vous pouvez équiper tout de suite et payer.
- L'onglet **Consommables** liste les potions, élixirs, flacons, nourritures et huiles qui
  apportent quelque chose à votre personnage. Les plus utiles viennent en premier. **Tout ce que
  je peux utiliser**, dans le menu **Filtres**, ajoute ce qui n'a pas de score : nourriture et
  boissons simples, potions de soins et de mana, bandages.
- Marque deux objets par emplacement. **Meilleure amélioration** est le plus fort.
  **Meilleure affaire** est le moins cher par point d'amélioration.
- Chaque ligne a deux prix : l'**Achat immédiat** et le **Coût net**, ce qu'un objet vous coûte au
  final : son achat immédiat moins ce qu'un marchand vous en donne quand vous n'en avez plus
  besoin. Acheté 4 pièces d'argent et revendu 3, il vous en a coûté 1.
- **Meilleur ensemble pour** choisit les améliorations qui, ensemble, apportent le plus pour votre
  or, ou pour une somme que vous saisissez.
- Le menu **Filtres** resserre la liste. **Meilleur type d'armure pour la classe** écarte les
  armures plus légères que la plus lourde que porte votre personnage. **Amélioration d'au moins**
  écarte les améliorations inférieures au pourcentage que vous saisissez. **Achat immédiat
  jusqu'à** écarte les objets qui coûtent plus que la somme que vous saisissez : la **Meilleure
  amélioration** de chaque emplacement est alors la meilleure à ce prix. **Équipement d'au plus
  10 niveaux en dessous** écarte l'équipement prévu pour des niveaux bien inférieurs à celui de
  votre personnage, et le scan est plus court. **Armes** dit comment votre personnage occupe ses
  mains, avec une arme à deux mains ou avec une arme à une main et un bouclier, et quels types
  d'armes lui sont proposés.
- Sert aussi à acheter pour vos autres personnages. Un bouton à la boîte aux lettres met
  l'équipement acheté dans une lettre pour eux.
- L'infobulle de chaque objet montre de combien il est meilleur que ce que vous portez, pour chaque
  arbre de talents de votre classe, par exemple Armes, Fureur et Protection pour un guerrier.
  Dans la fenêtre de l'addon, vous pouvez ne garder qu'une ligne, celle de votre arbre, et
  choisir où ces lignes s'affichent : dans les onglets de l'addon à l'hôtel des ventes, dans le
  reste du jeu, ou nulle part.
- Une flèche verte sur l'icône d'un objet dans vos sacs ou à la banque signale une amélioration
  que vous pouvez équiper tout de suite. Une flèche grise : une amélioration dès que vous aurez
  atteint son niveau. Les flèches s'affichent aussi dans les fenêtres de sacs et de banque
  d'EllesmereUI.
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
- Vous utilisez Forever Companion ? Choisissez **Forever Companion** au même endroit : l'équipement
  est alors évalué selon ses échelles. Les listes les suivent, et la ligne de l'infobulle et les
  flèches des sacs sont celles de Forever Companion.
- Vous utilisez Forever Leveling BiS ? Choisissez **Forever Leveling BiS** au même endroit :
  l'équipement est alors évalué comme il l'évalue, pour la spé principale que vous y avez choisie.
  Les lignes de l'infobulle et les flèches des sacs sont celles de Forever Leveling BiS.
- Vous utilisez GearQuest ? Choisissez **GearQuest** au même endroit : l'équipement est alors
  évalué comme il l'évalue. Un objet de ses listes reçoit son propre score, tout autre objet est
  évalué selon ses poids. Les listes et les flèches des sacs les suivent, et pour les objets de
  ses listes la ligne de l'infobulle est celle de GearQuest.

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
- La liste s'affiche avant la vérification des prix. Tant qu'un objet n'est pas vérifié, son prix
  est le plus bas parmi ses enchères et peut se révéler être une simple mise. Vous pouvez acheter
  tout de suite : le prix est vérifié avant tout achat.
- Avec **Meilleure affaire selon le coût net** coché, la **Meilleure affaire** suit le coût net et
  non l'achat immédiat. Ce que vous pouvez payer et **Meilleur ensemble pour** suivent toujours
  l'achat immédiat : c'est ce que vous payez.
- **Top 5 par emplacement** garde les cinq plus grandes améliorations de chaque emplacement, plus
  la **Meilleure affaire** lorsqu'elle n'en fait pas partie. Vous pouvez saisir un autre nombre
  à la place du 5, de 1 à 99. Désactivez-le pour voir toutes les améliorations. Vérifier tous
  leurs prix dure alors plus longtemps, jusqu'à quelques minutes dans un hôtel des ventes bien
  rempli.
- **Masquer les moins bonnes affaires**, juste en dessous, est désactivé tant que vous ne
  cochez pas la case. Il masque un objet lorsque le même emplacement en a un autre qui est à
  la fois plus puissant et une meilleure affaire. Exemple : +30 % pour 5 pièces d'or et +20 %
  pour 4 pièces d'or. Le second est plus faible, et vous payez plus cher ce qu'il apporte : il
  est masqué. Restent la **Meilleure amélioration**, la **Meilleure affaire** et ce qui se
  trouve entre les deux. Si **Top 5 par emplacement** est coché aussi, ses plus grandes
  améliorations sont prises parmi ce qui reste. Avec cette case cochée, moins de prix sont
  vérifiés après l'apparition de la liste.
- **Amélioration** dit de combien l'objet est meilleur que celui qu'il remplace, en pour cent.
  **Nouveau** : l'emplacement est vide. Des points, comme `+6 pts` : ce que vous y portez
  n'apporte rien à votre profil.
- **Meilleur type d'armure pour la classe** garde l'armure la plus lourde que votre personnage a
  appris à porter : le cuir pour un chasseur, les mailles une fois qu'il les a apprises. Capes,
  anneaux, armes et boucliers restent dans la liste. Un mage, un prêtre et un démoniste ne
  portent que du tissu et n'ont pas cette case.
- **Amélioration d'au moins** suit le pourcentage de la colonne **Amélioration**. Un objet pour un
  emplacement vide reste toujours.
- **Achat immédiat jusqu'à** est le prix maximum d'un seul objet. **Meilleur ensemble pour** a
  son propre budget et n'en tient pas compte.
- **Équipement d'au plus 10 niveaux en dessous** est désactivé tant que vous ne cochez pas la
  case. Il écarte l'équipement prévu pour un niveau inférieur de plus que ce nombre à celui de
  votre personnage. Vous pouvez saisir un autre nombre, de 1 à 59. Un scan avec ce filtre saute
  lui aussi cet équipement, il est donc plus court : plus votre niveau est élevé, plus il y
  gagne. L'équipement qui ne demande aucun niveau n'est pas concerné : il figure dans la liste
  s'il est une amélioration. Si vous augmentez le nombre ou décochez la case après un scan,
  relancez le scan : la ligne d'état dit à partir de quel niveau le dernier scan a lu. Les
  flèches des sacs ne suivent pas ce filtre.
- **Armes** ouvre son propre menu. **Toutes** propose les armes à une main comme les armes à
  deux mains. **Deux mains** écarte les armes à une main, les boucliers et les objets de main
  gauche. **Une main, bouclier et main gauche** écarte les armes à deux mains. En dessous, il y
  a une case pour chaque type d'arme que votre classe peut manier : case décochée, les armes de
  ce type sont écartées. Les flèches des sacs suivent tout cela.
- Chaque profil d'un personnage a son propre choix et ses propres cases dans **Armes** : un
  guerrier peut prendre les armes à deux mains en Fureur et un bouclier en Protection. Le menu
  porte en tête le profil qu'il montre, par exemple **Profil : Protection**.
- Un type d'arme que votre personnage n'a pas appris porte **(compétence non apprise)** après
  son nom et reste décoché tant que vous ne le cochez pas. Coché, ses armes figurent quand même
  dans la liste, sauf si autre chose les interdit à votre personnage, par exemple le niveau
  qu'elles demandent. L'infobulle de la ligne dit que la compétence doit être apprise.
  **Meilleur ensemble pour** n'en prend aucune.
- Un guerrier ou un paladin sur le profil **Protection** commence sur **Une main, bouclier et
  main gauche** tant que ce sont les poids de l'addon qui évaluent : ce sont ceux d'un tank au
  bouclier. Choisissez **Toutes** pour voir aussi les armes à deux mains.
- Avec **Une main, bouclier et main gauche**, un personnage qui tient une arme à deux mains se
  voit proposer les armes à une main, les boucliers et les objets de main gauche comme
  **Nouveau** : chacun compte pour ce qu'il vaut seul, et non par rapport à l'arme à deux
  mains. Quand Forever Leveling BiS évalue, une arme reste comparée à l'arme à deux mains.
- Chaque personnage a sa propre case **Meilleur type d'armure pour la classe**, son propre
  nombre pour **Amélioration d'au moins**, sa propre somme pour **Achat immédiat jusqu'à**,
  ainsi que sa propre case et son propre nombre pour **Équipement d'au plus 10 niveaux en
  dessous**. Les choix dans **Armes** sont gardés pour chacun de ses profils. Quand vous
  achetez pour un autre personnage, vous voyez et réglez les siens.
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
