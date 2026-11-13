# Upgrade Scout

<img src="docs/logo/logo.png" alt="Upgrade Scout logo" width="128" align="right">

**Finds gear upgrades on the auction house that you can equip and afford, scored by Pawn.** An addon for World of Warcraft Forever.

[Русская версия](README.ru.md)

Open the auction house, click the **Upgrades** tab and press **Scan**. You get a list, slot by slot,
of the gear for sale that you can equip right now and that beats what you are wearing. In every slot
two picks are marked:

- **Best upgrade**: the biggest improvement, whatever it costs.
- **Best value**: the least gold per point of improvement.

## Features

- Scores are [Pawn](https://www.curseforge.com/wow/addons/pawn)'s own numbers for the scale you choose, so the list
  agrees with Pawn's tooltips and green arrows.
- Only gear you can use now: required level, class rules and nothing red in the item tooltip.
- Buyout prices only, each one checked against the actual auctions before it is shown. Bid-only
  auctions are ignored.
- **Top 5 per slot** keeps the options worth considering and drops the rest.
- **Only what I can afford** hides what costs more than you have.
- **Buy** from the list: the addon checks that the auction is still there and asks before paying.
- Works for any class and level. English, Russian, German, French, Spanish, Brazilian Portuguese, Italian and Simplified Chinese.

## Requirements

- World of Warcraft Forever, client 1.60.1 (interface 16001).
- **Pawn**, installed and enabled. Without it the game does not load Upgrade Scout and the AddOns
  list shows "Dependency missing: Pawn".

## Install

1. Download `UpgradeScout-<version>.zip` from the Releases page of this repository.
2. Unpack it into `World of Warcraft\_forever_\Interface\AddOns`, so that the folder
   `AddOns\UpgradeScout` holds `UpgradeScout.toc`.
3. Restart the game.

## Use

1. Open the auction house and click the **Upgrades** tab (or type `/upscout`).
2. Press **Scan**. The list fills in as prices are confirmed, best upgrades first.
3. Hover a row for the item tooltip, its Pawn score against yours, what it replaces and the cost per
   point. **Buy** looks the auction up again and asks for confirmation before paying.

- **Pawn scale**: the dropdown shows the scale in use. If Pawn shows more than one scale for the
  character, pick another there; the list is rescanned with the new scale.
- **Only what I can afford**: on by default. Turn it off to see everything; prices you cannot pay are red.
- **Top 5 per slot**: on by default. Turn it off to see every upgrade; the scan then looks up every
  price, which can take minutes on a busy auction house, and the status line shows about how much
  time is left. With it on:
  - An item is left out when a stronger one costs the same or less per point. What remains reads top
    to bottom as "weaker, but cheaper per point" (and so cheaper outright); the best upgrade and the
    best value are always part of it.
  - If more than five remain, the slot keeps the best upgrade and the next two steps below it, the
    best value and the next step below it.
  - The slot title shows how many upgrades there are in all, for example "Chest (5 of 17)".
- A yellow `*` after a name means the item has effects Pawn cannot score (procs, on-use effects).
- Blocks are equipment slots, so **Main Hand** holds everything that goes into that hand: one-hand,
  main-hand and two-hand weapons together. Each weapon row says which it is in grey after the name,
  in the same words as the item tooltip.

## How an item is judged

| Question | Answer comes from |
| --- | --- |
| How good is it? | Pawn's score for the base item on the chosen scale |
| Better than mine? | Score minus the score of the item it replaces; at least 0.5% higher, as in Pawn |
| Can I wear it now? | Required level, Pawn's class rules, and no red line in the item tooltip |
| What does it cost? | The cheapest buyout among identical items; bid-only auctions are ignored |

Which item it replaces:

- Rings and trinkets: the weaker of the two you wear, or an empty slot.
- Two-hand weapon: your main hand and off hand together.
- One-hand weapon: your main hand; also your off hand if you can dual wield.
- Shield or held item: your off hand. Not offered while you hold a two-hander.

"Best value" only considers items that give at least a quarter of the biggest improvement available in
that slot, so a tiny upgrade for a few copper does not win (`VALUE_MIN_SHARE` in `Results.lua`).

## How the scan works

1. **Browse**: one search for all weapons and armor, sorted by level. If the rows really arrive in
   level order, reading stops once they are past your level; otherwise every page is read.
2. **Score**: Pawn scores one real auction link per row. Rows that cannot beat your gear, or that have
   a red line in their tooltip, drop out. The rest are candidates.
3. **Check prices**: an item search reads the actual auctions of a candidate and keeps the cheapest
   buyout. The server answers one request at a time, so this is the slow step, and the scan sends
   only the searches whose answer the list can show:
   - With **Only what I can afford** on, a candidate is not searched when even the lowest price in
     its row is more than you have.
   - With **Top 5 per slot** on, a candidate is not searched when an offer already checked is
     stronger and costs no more per point than the candidate would at the lowest price in its row.
     Candidates are checked strongest first, so each checked offer rules out the weaker ones it beats.

   Skipping never changes the list: both rules only skip what the list would hide anyway. The
   candidates are kept, so when you switch a filter off, buy an offer or come into money, the prices
   the list now needs are looked up then. Until that happens a slot title reads "Chest (3 of about 19)":
   19 upgrades by score, some of them not checked for a buyout price.

Safety nets, because none of this was assumed about the server:

- If an item search shows that a row holds different items than its sample suggested, every candidate
  and every row dropped in step 2 is searched after all.
- If rows turn out to have buyouts below their own "lowest price", that number is no longer used to
  skip anything.
- Three item searches in a row without an answer end the price checks instead of waiting out the rest.

`/upscout stats` prints what the last scan sent and how long each step took.

## Development

The logic runs outside the game against a stand-in client (`tests/wow.lua`: frames, events, an auction
house with paging and a request throttle, a fake Pawn). Lua 5.1 is needed.

```
lua5.1 tests/run.lua            # every scenario
lua5.1 tests/run.lua buy        # one scenario
```

- `scripts\install.ps1` copies the addon into the game's AddOns folder (`-Game <path>` if the game is
  not in the default place).
- `scripts\release.ps1` builds `dist\UpgradeScout-<version>.zip`; the version is the one in the
  `.toc`.

| File | Purpose |
| --- | --- |
| `PawnBridge.lua` | The only place that calls Pawn |
| `Compare.lua` | Which slot an item goes into and how much better it is |
| `Results.lua` | Rows for the list and the two picks per slot |
| `Scanner.lua` | Auction house requests: browse, score, price check, buy |
| `UI.lua` | The tab |
| `icon.tga` | The icon in the game's AddOns list, exported from `docs/logo/logo.svg` |
| `Libs/` | LibStub (public domain) and LibAHTab (MIT), which adds auction house tabs without clashing with other addons' tabs |

## License

All rights reserved, see [LICENSE](LICENSE). The libraries in `Libs/` keep their own licenses. Pawn is
a separate addon by Vger and is not included.
