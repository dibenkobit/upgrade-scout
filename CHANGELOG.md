# Changelog

## 2.6.0

- **Pawn** can score your gear. In the addon's window, under **Who scores your gear?**, choose
  **Pawn**: the lists at the auction house and the bag arrows then go by your Pawn scales, not
  by the addon's own weights. The **Profile** dropdown lists the scales, for your other
  characters too.
- With Pawn chosen, Pawn's lines say what an item is worth, so the addon leaves its own out of
  the tooltip.
- The choice is for the whole account. Without Pawn, or with Pawn switched off, the addon
  scores by its own weights as before.
- If you have Pawn, the window comes up once after the update to show you the choice.
- The addon's window asks two things about item tooltips. How: **All specs** shows a line for
  every talent tree of your class, as before. **Only my spec** keeps one line: how much better
  the item is for the tree you play.
- Where: one box for the addon's tabs at the auction house, one for the rest of the game (bags,
  loot, chat). Untick both and the addon writes nothing into tooltips. Before, the lines on
  the addon's tabs could not be switched off.
- The window has a new layout: the auction house and the bags side by side, and the tooltip in
  a block of its own under them.

## 2.5.0

- A welcome window comes up on your first login. It shows what the addon puts into the game: the
  tabs at the auction house, the lines in item tooltips and the arrows in your bags.
- The tooltip lines and the bag arrows can be switched off in that window.
- A button at the minimap opens the window again. So does `/upscout`; at the auction house the
  command still goes to the Upgrades tab.
- The **Profile** starts on the talent tree you have the most points in, no longer on one fixed
  for your class. A profile you chose yourself stays.
- Ticking or unticking **Net cost** no longer sends for prices. The list is repriced on the
  spot: a scan now looks up what it needs either way.
- A scan leaves alone gear that is sold by the piece, like a grey necklace that stacks. One
  such item held every scan up, and the list then said that the scan had stopped early.
- A name in another alphabet than the game's language is written in letters, not in squares:
  a Russian character's name on an English client.
- When the auction house leaves a price check unanswered, the status line says how many.

## 2.4.0

- **Net cost**, a new box on the Upgrades tab. Ticked, the list prices gear at what it costs
  you in the end: the buyout less what a vendor pays for it when you are done with it. Bought
  for 4 silver and sold for 3, it cost you 1. **Best value** and **Top 5 per slot** go by that
  cost. What you can afford, and **Best set for**, still go by the buyout.
- The list of upgrades no longer shows the price per point. The buyout stands next to the
  **Buy** button, and item names have more room. **Best value** is picked as before.

## 2.3.1

- The profile menu no longer lists your characters of the other faction: nothing bought at
  your auction house can be mailed to them.

## 2.3.0

- An arrow on the icon of an item in your bags or bank marks an upgrade on your profile:
  green when you can put it on now, grey when it asks for a higher level than yours.
- Buying gear asks in the same box as buying consumables, with the item's gain and buyout. The
  strip at the mailbox, the profile menu and the list's scroll bar have the addon's own look too.
- The strip at the mailbox comes up with the mail window every time. It lets go of what you send,
  with its button or by hand, and of what left your bags some other way. An item already in the
  letter no longer reads as still in the mail.

## 2.2.3

- The addon's description in the AddOns list names consumables too.

## 2.2.2

- The addon's description in the AddOns list is the one from 2.2.0 again.

## 2.2.1

- The names of all profiles in the tooltip are in the colour of your class.
- The addon's description in the AddOns list is updated.

## 2.2.0

- The tooltip of any item shows how much better it is than what you wear, on every profile of
  your class: in your bags, loot, quest rewards, chat links and the auction house.
- In those lines the profile in use is in the colour of your class, no longer in gold.

## 2.1.0

- An item's tooltip shows how much better it is on every profile of your class, the one in use in
  gold. The raw scores, the price per point and the count of dearer auctions are gone from it.
- How long ago the scan was now stands at the right end of the bottom line, where the progress bar
  runs during a scan.

## 2.0.1

- Armor counts on every profile, not only a tank's, and so do shield block, defense, dodge and
  parry. 2.0.0 offered a warrior an off-hand item in place of a shield with 400 armor, and leather
  over better mail.

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
