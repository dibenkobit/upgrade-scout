# Changelog

## 1.2.0

New:

- **Best set for a budget**: tick **Best set for** under the list of upgrades, and the list shows
  the offers that, bought together, add the most for the gold you have, or for a smaller sum you
  type. No more of a kind than you can wear at once: one chest, two rings, what two hands hold.
  - The answer is exact. A set can need an offer the list hides (a weaker chest that leaves gold
    for boots), so ticking the box may look up a few more prices.
  - What you buy from the set counts as worn from then on, and a sum you typed goes down by what
    you paid: the rest of the set stays as it was.
- **Purchases for another character go to it by mail**: gear you buy while the lists are for
  another character of yours is remembered. At a mailbox a button under the mail window puts what
  is in your bags into a letter to that character, name and all; you check the letter and press
  Send.

## 1.1.0

New:

- **Consumables** tab: the potions, elixirs, flasks, food and drink, bandages, scrolls and other
  consumables on the auction house that you can use right now.
  - What an elixir, a flask, a scroll, an oil or a meal adds is scored by Pawn on your scale, in
    the same points as gear.
  - **Best for me** (on by default) keeps one row per kind, the one worth the most to your
    character, and leaves out what is of no use to it.
  - **Buy** asks how many pieces and shows what that many cost before you confirm.
- **For another character**: both lists can be made for another character of your account. Log in
  to it once with the addon; after that its Pawn scales are in the scale dropdown of all your
  characters. Upgrades are measured against the gear that character wears, at its level, with the
  weapons and armor it has learned.
- **A look of its own** for the tab: a dark plate in a gold edge, headings in gold capitals, its
  own buttons and tick boxes.
  - A slot's heading folds the slot away at a click; folded slots are remembered for the character.
  - A meter under each upgrade shows how big it is next to the best one in the slot.
  - Progress bars show how far the scan is.
- `/upscout forget Name` takes a character that no longer exists out of the scale dropdown.

Fixed:

- Prices such as 2g 90s 0c had a gap before a single digit of silver or copper.

## 1.0.1

- Fixed: the status line always said "Scanned 1 Sec ago". The age of the scan now counts up while
  the tab is open.

## 1.0.0

First release, for World of Warcraft Forever 1.60.1 (interface 16001).

- **Upgrades** tab in the auction house: one scan lists, slot by slot, the gear you can buy out and
  equip right now that scores higher than what you wear.
- Scores are Pawn's own numbers for the scale you choose; Pawn is required.
- **Best upgrade** and **Best value** are marked in every slot.
- **Top 5 per slot** (on by default) keeps only the options worth considering: an item is left out
  when a stronger one costs the same or less per point.
- **Only what I can afford** (on by default) hides what costs more than you have.
- Buyout prices only, each one confirmed against the actual auctions before it is shown.
- Prices are looked up only for the items the list can show: tens of requests to the auction house
  instead of hundreds.
- With Top 5 off the scan looks up every price; the status line then shows about how much time is left.
- **Buy** checks that the auction is still there and asks before paying.
- Weapon rows say how the weapon is held (one-hand, two-hand, main hand, off hand).
- English, Russian, German, French, Spanish, Brazilian Portuguese, Italian and Simplified Chinese.
