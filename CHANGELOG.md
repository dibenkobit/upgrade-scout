# Changelog

## 2.0.0

- Pawn is no longer needed. The addon scores gear with its own stat weights for every talent tree,
  worked out with the [wowsims/forever](https://github.com/wowsims/forever) simulator.
- One setting: the **Profile** dropdown. It starts on a profile that suits your class. The Pawn
  scale chosen in 1.x is replaced by it.
- Below level 60, hit, crit, haste and expertise count for less, as simulations of leveling
  characters show.
- Stamina (except for tanks), and a healer's Intellect, Spirit and mana regeneration, are set by hand: a simulation
  of damage cannot tell what they are worth.
- `/upscout stats` and an item shows how the item gets its score, stat by stat.
- The **Upgrade** column shows one number: how much better the item is, in percent. **New**
  stands for an empty slot, and points for a slot whose item adds nothing on your profile. The points are in the tooltip.
- Gear with a weapon skill or a bonus against one kind of creature gets the yellow `*`: the score
  does not count those.
- The addon's lines in an item's tooltip start with its name and the profile the scores are on.
- Fixed: two variants of one item with the same score, such as "of the Tiger" and "of the Whale",
  showed as one offer, and the second took the place of the first.
- Fixed: gear you bought counted as already worn when you wore another variant of the same item.
- Fixed: a consumable sold as separate auctions showed a part of its price, and the chat named the
  wrong number bought.
- Fixed: the box for buying a consumable stayed open with a grey button when the auction house
  turned the purchase down.
- Fixed: on a big auction house, **Best set for** could find nothing for a small sum.
- Fixed: the spell crit of oils and flasks was left out of their score.
- A second copy of a Unique-Equipped item you wear is no longer offered.
- For another character: gear that asks for a rank or a reputation is left out, in every language.
- Fixed: gear sent to another character could stay on the mailbox button after the letter went.

## 1.3.0

- The addon now speaks Korean and Traditional Chinese.

## 1.2.0

- **Best set for a budget**: tick **Best set for** under the list of upgrades. The list then shows
  the upgrades that give the most together for your gold, or for a smaller sum you type.
- **Mail to another character**: the addon remembers the gear you buy for another character. At a
  mailbox, a button puts it into a letter to that character. You check the letter and press Send.

## 1.1.0

- **Consumables** tab: potions, elixirs, food, bandages and other consumables you can use right
  now. Pawn scores what they add, the same way as gear. **Best for me** keeps the best of each kind.
- **For another character**: both lists can be made for another character of yours. Log in to it
  once with the addon, then pick its scale in the Pawn scale dropdown.
- A new look for the tab. Click a slot's heading to fold the slot.
- `/upscout forget Name` removes a deleted character from the dropdown.
- Fixed: prices such as 2g 90s 0c had a gap in them.

## 1.0.1

- Fixed: the status line always said "Scanned 1 Sec ago".

## 1.0.0

First release, for World of Warcraft Forever 1.60.1.

- **Upgrades** tab in the auction house: gear you can equip right now that is better than what you
  wear, slot by slot.
- Scores come from Pawn. Pawn is required.
- **Best upgrade** and **Best value** are marked in every slot.
- **Top 5 per slot** keeps only the options worth considering.
- **Only what I can afford** hides what costs more than you have.
- Buyout prices only, each checked against the real auctions.
- **Buy** from the list. The addon asks before paying.
- English, Simplified Chinese, German, Russian, French, Spanish and Brazilian Portuguese.
