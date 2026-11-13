# Upgrade Scout

<img src="docs/logo/logo.png" alt="Upgrade Scout logo" width="128" align="right">

**Finds gear upgrades on the auction house that you can equip and afford.** An addon for World of Warcraft Forever.

**[Download on CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

English · [Русский](docs/README.ru.md) · [Deutsch](docs/README.de.md) · [Français](docs/README.fr.md) · [Español](docs/README.es.md) · [Português](docs/README.pt-BR.md) · [Italiano](docs/README.it.md) · [简体中文](docs/README.zh-CN.md)

Open the auction house, click the **Upgrades** tab and press **Scan**. You get a list of gear that is
better than what you wear, slot by slot, with prices. Press **Buy** on the one you want.

## What it does

- Scores gear with [Pawn](https://www.curseforge.com/wow/addons/pawn), so the list matches Pawn's green arrows.
- Shows only what you can equip right now and can pay for.
- Marks two items in every slot: the **Best upgrade** is the strongest, the **Best value** is the
  cheapest per point of improvement.
- **Best set for** picks the upgrades that give the most together for your gold, or for a sum you type.
- The **Consumables** tab lists potions, elixirs, food and bandages you can use, the most useful for
  your character first.
- Both tabs work for your other characters too.

Any class, any level. English, Russian, German, French, Spanish, Brazilian Portuguese, Italian and
Simplified Chinese.

## Install

**[Install from CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

The CurseForge app does it all for you, Pawn included.

You need World of Warcraft Forever (1.60.1) and [Pawn](https://www.curseforge.com/wow/addons/pawn).
Without Pawn the addon does not load.

To install by hand:

1. Download `UpgradeScout-<version>-forever.zip` from [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   or from [GitHub releases](https://github.com/dibenkobit/upgrade-scout/releases).
2. Unpack it into `World of Warcraft\_forever_\Interface\AddOns`.
3. Restart the game.

## Good to know

- Prices are buyouts. Auctions that only take bids are skipped.
- **Top 5 per slot** keeps the list short. Turn it off to see every upgrade. The scan then takes
  longer, up to a few minutes on a busy auction house.
- A yellow `*` after a name means the item has effects Pawn can't score, such as procs.
- Health and mana potions have no score: Pawn has no number for "restores 700 health".
- Boots "of the Tiger" and boots "of the Whale" are different items with different prices. The
  game's Sell tab shows all of them in one list, so the lowest price there can be for another item.

## Buying for another character

1. Log in to the other character once with the addon installed. The addon saves its gear, level
   and skills.
2. On the character at the auction house, pick the other character's scale in the **Pawn scale**
   dropdown and press **Scan**.

The list is now for that character. The one you are playing still pays.

At a mailbox, take the gear you bought out of the mail. A button under the mail window then puts it
into a letter to that character. Check the letter and press **Send**. Consumables you send yourself.

The addon knows the other character as it was when you last played it. Log in to it again after it
levels up or changes gear.

## Commands

- `/upscout` opens the Upgrades tab. The auction house must be open.
- `/upscout stats` shows how long the last scan took.
- `/upscout forget Name` removes a deleted character from the dropdown.

## Development

The tests run outside the game and need Lua 5.1:

```
lua5.1 tests/run.lua
```

Each script in `scripts/` says at the top what it does and how to run it.

To release, push a tag with the version from `UpgradeScout.toc`, for example `1.2.0`. GitHub Actions
runs the tests and uploads the zip to CurseForge and GitHub.

## License

All rights reserved, see [LICENSE](LICENSE). Pawn is a separate addon by Vger and is not included.
