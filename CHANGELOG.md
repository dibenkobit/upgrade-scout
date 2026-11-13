# Changelog

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
