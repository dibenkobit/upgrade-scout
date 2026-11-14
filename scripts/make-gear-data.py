"""Builds UpgradeScout/GearData.lua: what a piece of gear does beyond its stats, read out of the game's own tables.

    python scripts/make-gear-data.py --build 1.60.1.70938
    python scripts/make-gear-data.py --build 1.60.1.70938 --report     (also prints what it found)

The addon scores gear by the stats the game counts for it (C_Item.GetItemStats). Those are the
stats in the item's own row. What an item does through a spell is not among them: a use, a
chance on hit, an aura it keeps on its wearer. The game's tables say which items have such
spells and what each spell does, and wago.tools publishes the tables as CSV for every build
(the Forever client is its product "wowf"; https://wago.tools/api/builds lists the builds).
This script downloads the tables it needs into --tables (once per build) and writes:

  * extra:   item -> stats an on-equip spell adds as a plain, flat amount (attack power, spell
             damage, mana per 5 seconds...), under the game's own names for them. The addon adds
             these to the item's stats. Only a spell the tooltip shows is read: a spell without
             a text of its own is the hidden half of another one, which is on only at times
             ("tripled in Forest and Grassland areas"), and its amount is not the item's.
  * effects: the items that do something a sum of stats cannot count. The addon marks them.
  * newest:  the highest item number in the tables. An item above it is one the tables were
             made before; the addon asks its tooltip instead.

Run it again for every new build of the game: new items come with new numbers.
"""
import argparse
import collections
import csv
import os
import sys
import tempfile
import urllib.request

csv.field_size_limit(10 ** 9)

TABLES = ["Item", "ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellEffect", "Spell", "SpellShapeshift"]
URL = "https://wago.tools/db2/{table}/csv?build={build}"
AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

GEAR = {2, 4}                   # item classes: weapons, armor
ON_USE, ON_EQUIP = 0, 1         # when an item casts its spell; anything else is a chance of some kind
APPLY_AURA = 6

STATS = ["STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT"]        # by the game's stat number
SCHOOLS = [(2, "HOLY", 1), (4, "FIRE", 2), (8, "NATURE", 3), (16, "FROST", 4), (32, "SHADOW", 5), (64, "ARCANE", 6)]
ALL_MAGIC = 126


# Stats an item can have in its own row that no profile has a weight for, because the simulator
# the weights come from keeps them apart from the rest (tools/database/dbc/enums.go of
# wowsims/forever): a weapon skill, the penetration of one school, attack power or spell damage
# against one kind of creature. An item with one of them is starred like an item with an effect.
UNWEIGHED = set(range(90, 104)) | {119, 121} | set(range(125, 138))


def mod(name):
    return "ITEM_MOD_" + name + "_SHORT"


def aura_stats(aura, misc):
    """The game's names for what a flat aura adds, or None when it is not a plain stat."""
    if aura == 29:                                              # a stat; -1 is all five
        if misc == -1:
            return [mod(s) for s in STATS]
        return [mod(STATS[misc])] if 0 <= misc < len(STATS) else None
    if aura == 13:                                              # damage done, by school
        if misc & ALL_MAGIC == ALL_MAGIC:
            return [mod("SPELL_DAMAGE_DONE")]
        return [mod(name + "_DAMAGE_DONE") for bit, name, _ in SCHOOLS if misc & bit] or None
    if aura == 22:                                              # resistance; school 1 is armor
        names = (["RESISTANCE0_NAME"] if misc & 1 else []) + [f"RESISTANCE{n}_NAME" for bit, _, n in SCHOOLS if misc & bit]
        return names or None
    if aura == 85:                                              # regeneration of a power; 0 is mana
        return [mod("MANA_REGENERATION")] if misc == 0 else None
    if aura == 35:
        return [mod("MANA")] if misc == 0 else None
    return {
        135: [mod("SPELL_HEALING_DONE")],
        # Attack power with melee weapons, with ranged ones. Gear has one number for both
        # together (ITEM_MOD_ATTACK_POWER), and one for ranged alone; see together().
        99: [mod("MELEE_ATTACK_POWER")],
        124: [mod("RANGED_ATTACK_POWER")],
        34: [mod("HEALTH")],
        161: [mod("HEALTH_REGEN")],
    }.get(aura)


def together(found):
    """Attack power for melee and for ranged weapons alike is the one number gear has for both."""
    melee, ranged = mod("MELEE_ATTACK_POWER"), mod("RANGED_ATTACK_POWER")
    both = min(found.get(melee, 0), found.get(ranged, 0))
    if both <= 0:
        return found
    found[mod("ATTACK_POWER")] = found.get(mod("ATTACK_POWER"), 0) + both
    for name in (melee, ranged):
        found[name] -= both
        if found[name] <= 0:
            del found[name]
    return found


def rows(folder, table):
    with open(os.path.join(folder, table + ".csv"), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def download(build, folder):
    os.makedirs(folder, exist_ok=True)
    for table in TABLES:
        path = os.path.join(folder, table + ".csv")
        if os.path.exists(path) and os.path.getsize(path) > 0:
            continue
        print("downloading", table, file=sys.stderr)
        request = urllib.request.Request(URL.format(table=table, build=build), headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request) as response, open(path, "wb") as out:
            out.write(response.read())


def number(value):
    return str(int(value)) if value == int(value) else f"{value:g}"


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--build", required=True, help="the client build, as wago.tools names it: 1.60.1.70938")
    parser.add_argument("--tables", help="folder for the downloaded tables (default: a folder under the system's temp)")
    parser.add_argument("--out", default=os.path.join(here, "..", "UpgradeScout", "GearData.lua"))
    parser.add_argument("--report", action="store_true", help="print every item that was read")
    args = parser.parse_args()

    folder = args.tables or os.path.join(tempfile.gettempdir(), "upgrade-scout-tables", args.build)
    download(args.build, folder)

    item = {int(r["ID"]): r for r in rows(folder, "Item")}
    sparse = {int(r["ID"]): r for r in rows(folder, "ItemSparse")}
    item_effect = {int(r["ID"]): r for r in rows(folder, "ItemEffect")}
    effects_of = collections.defaultdict(list)
    for r in rows(folder, "ItemXItemEffect"):
        effects_of[int(r["ItemID"])].append(int(r["ItemEffectID"]))
    spell_effects = collections.defaultdict(list)
    for r in rows(folder, "SpellEffect"):
        if r["DifficultyID"] == "0":
            spell_effects[int(r["SpellID"])].append(r)
    described = {int(r["ID"]) for r in rows(folder, "Spell") if r["Description_lang"].strip()}
    # Spells that work in some shapes only: a druid's staff that adds attack power "in Cat,
    # Bear and Dire Bear forms only".
    in_forms = {int(r["SpellID"]) for r in rows(folder, "SpellShapeshift")
                if int(r["ShapeshiftMask_0"]) or int(r["ShapeshiftMask_1"])}

    extra, effects = {}, set()
    for i, row in sorted(item.items()):
        # (Not every item has a row of its own in ItemSparse as wago.tools gives it: those are
        # still read for their effects.)
        if int(row["ClassID"]) not in GEAR or int(row["InventoryType"]) == 0:
            continue
        found, other = {}, []
        for e in effects_of.get(i, []):
            r = item_effect.get(e)
            if not r or int(r["SpellID"]) <= 0:
                continue
            trigger, spell = int(r["TriggerType"]), int(r["SpellID"])
            if trigger != ON_EQUIP:
                other.append("use" if trigger == ON_USE else f"trigger {trigger}")
                continue
            if spell not in described:
                other.append("a spell the tooltip does not show")
                continue
            parts = spell_effects.get(spell, [])
            if not parts:
                other.append(f"spell {spell} without effects")
            for s in parts:
                aura, amount = int(s["EffectAura"]), float(s["EffectBasePointsF"])
                names = aura_stats(aura, int(s["EffectMiscValue_0"])) if int(s["Effect"]) == APPLY_AURA else None
                if names == [mod("MELEE_ATTACK_POWER")] and spell in in_forms:
                    names = [mod("FERAL_ATTACK_POWER")]
                if names and amount > 0:
                    for name in names:
                        found[name] = found.get(name, 0) + amount
                else:
                    other.append(f"aura {aura}" if int(s["Effect"]) == APPLY_AURA else f"effect {s['Effect']}")
        for n in range(10):
            if i not in sparse:
                break
            stat = int(sparse[i][f"StatModifier_bonusStat_{n}"])
            if stat in UNWEIGHED and int(sparse[i][f"StatPercentEditor_{n}"] or 0) != 0:
                other.append(f"stat {stat}")
        # The stats of an equip spell are added only for an item with a row of its own. For the
        # others the game counts its stats from data these tables do not show, and an auction
        # house full of them (an in-game check, 2026-11-14) had no equip spell for a stat left:
        # their stats had all gone into that data. Such a spell here is counted as an effect.
        if found and i in sparse:
            extra[i] = together(found)
        elif found:
            other.append("stats from a spell, for an item without a row")
        if other:
            effects.add(i)
        if args.report and (found or other):
            print(f"{i:7d} {sparse.get(i, {}).get('Display_lang', '?')[:40]:40} "
                  f"{', '.join(f'{k} {number(v)}' for k, v in sorted(found.items()))}"
                  f"{'  | not counted: ' + ', '.join(sorted(set(other))) if other else ''}")

    newest = max(item)
    lines = [
        "-- Made by scripts/make-gear-data.py from the game's tables, build " + args.build + ". Not written by hand:",
        "-- run the script again for every new build of the game.",
        "local _, ns = ...",
        "",
        "-- What a piece of gear does beyond the stats the game counts for it (see Score.lua).",
        "local D = { build = \"" + args.build + "\" }",
        "ns.GearData = D",
        "",
        "-- The highest item number the tables had. An item above it is newer than this file.",
        f"D.newest = {newest}",
        "",
        "-- item -> stats that a spell it keeps on its wearer adds, under the game's names for them.",
        "D.extra = {",
    ]
    for i in sorted(extra):
        pairs = ", ".join(f"{name} = {number(amount)}" for name, amount in sorted(extra[i].items()))
        lines.append(f"    [{i}] = {{ {pairs} }},")
    lines += [
        "}",
        "",
        "-- The items that do something a sum of stats does not count: a use, a chance on hit, an aura",
        "-- that is not a plain stat.",
        "D.effects = {}",
        "for id in ([[",
    ]
    ids = [str(i) for i in sorted(effects)]
    for at in range(0, len(ids), 16):
        lines.append(" ".join(ids[at:at + 16]))
    lines += ["]]):gmatch(\"%d+\") do D.effects[tonumber(id)] = true end", ""]
    with open(args.out, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))
    print(f"{os.path.normpath(args.out)}: {len(extra)} items with stats from a spell, {len(effects)} with effects "
          f"not counted, newest item {newest}", file=sys.stderr)


if __name__ == "__main__":
    main()
