"""Builds UpgradeScout/SupplyData.lua: what every consumable gives, read out of the game's own tables.

    python scripts/make-supply-data.py --build 1.60.1.70938
    python scripts/make-supply-data.py --build 1.60.1.70938 --report     (also prints what it found)

The addon cannot ask the game what an elixir adds: the client only has the sentence in its
tooltip, in the player's language. The numbers behind that sentence are in the client's data
tables, and wago.tools publishes those as CSV for every build (the Forever client is its
product "wowf"; https://wago.tools/api/builds lists the builds). This script downloads the
tables it needs into --tables (once per build) and writes one Lua table: item -> stats under
the names Pawn knows them by, and item -> what the item restores.

Run it again when the game gets new consumables. An item that is not in the table is still
listed by the addon, only without a score.

What is read, and what is left out on purpose:
  * the first on-use spell of an item, and the spells it triggers (food: "Well Fed");
  * auras that add a flat amount of something Pawn has a weight for;
  * for oils and the like (a temporary enchantment), what the enchantment adds;
  * NOT percentages of a stat, procs, damage, weapon damage, and permanent enchantments
    (what an armor kit is worth depends on what the piece it goes on has now);
  * amounts of zero: the client fills those in by place or by level, and a table cannot.
"""
import argparse
import collections
import csv
import os
import sys
import tempfile
import urllib.request

csv.field_size_limit(10 ** 9)

TABLES = ["Item", "ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellEffect", "SpellMisc",
          "SpellDuration", "SpellItemEnchantment"]
URL = "https://wago.tools/db2/{table}/csv?build={build}"
AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

CONSUMABLE = 0          # item class
# How an item binds: 0 not at all, 2 when equipped, 3 when used. The rest cannot be sold.
SELLABLE = {0, 2, 3}

STATS = ["Strength", "Agility", "Stamina", "Intellect", "Spirit"]       # by the game's stat number
SCHOOLS = [(2, "Holy"), (4, "Fire"), (8, "Nature"), (16, "Frost"), (32, "Shadow"), (64, "Arcane")]
ALL_MAGIC = 126
POWERS = {0: "M", 1: "R", 2: "F", 3: "E"}                               # mana, rage, focus, energy
# A regeneration aura that lasts no longer than this is a meal or a drink, not a buff.
MEAL_SECONDS = 120

# Spell effects
HEAL, ENERGIZE, TRIGGER_SPELL, APPLY_AURA = 10, 30, 64, 6
ENCHANT_TEMPORARY = {54, 360}
# Auras that only hand over to another spell
PERIODIC_TRIGGER, PERIODIC_TRIGGER_WITH_VALUE = 23, 227

# Enchantment effects
ENCHANT_SPELL, ENCHANT_RESISTANCE, ENCHANT_STAT = 3, 4, 5
# The game's numbers for what an enchantment can add (ITEM_MOD_*), where Pawn has a name for it.
ITEM_MODS = {0: "Mana", 1: "Health", 3: "Agility", 4: "Strength", 5: "Intellect", 6: "Spirit", 7: "Stamina",
             38: "Ap", 39: "Rap", 41: "Healing", 42: "SpellDamage", 43: "Mp5", 46: "Hp5", 50: "Armor",
             51: "FireResist", 52: "FrostResist", 54: "ShadowResist", 55: "NatureResist", 56: "ArcaneResist"}


def by_school(mask, all_name, suffix):
    """Names for a mask of magic schools: one name for all of them where Pawn has one."""
    if mask & ALL_MAGIC == ALL_MAGIC and all_name:
        return [all_name]
    return [name + suffix for bit, name in SCHOOLS if mask & bit]


def aura_stats(aura, misc):
    """Pawn's names for what a flat aura adds, or None when it is not one this script reads."""
    if aura == 29:                                              # a stat; -1 is all five
        return STATS if misc == -1 else [STATS[misc]] if 0 <= misc < len(STATS) else None
    if aura == 13:                                              # spell damage, by school
        return by_school(misc, "SpellDamage", "SpellDamage") or None
    if aura in (22, 674):                                       # resistance; school 1 is armor
        names = (["Armor"] if misc & 1 else []) + by_school(misc, None, "Resist")
        return [n for n in names if n != "HolyResist"] or None
    return {
        135: ["Healing"],
        99: ["Ap"], 124: ["Rap"],
        34: ["Health"], 230: ["Health"], 250: ["Health"],
        35: ["Mana"] if misc == 0 else None, 418: ["Mana"] if misc == 0 else None,
        161: ["Hp5"],
        # Chances and speeds are percentages, and so are Pawn's weights for them in this game.
        # Pawn weighs them apart for weapons and for spells; an aura for both counts as both.
        290: ["CritRating", "SpellCritRating"], 52: ["CritRating"], 57: ["SpellCritRating"],
        54: ["HitRating"], 55: ["SpellHitRating"],
        193: ["HasteRating", "SpellHasteRating"], 65: ["SpellHasteRating"], 342: ["HasteRating"],
        240: ["ExpertiseRating"],
        49: ["DodgeRating"], 47: ["ParryRating"], 51: ["BlockRating"],
    }.get(aura)


class Tables:
    def __init__(self, folder):
        self.folder = folder
        self.item = {int(r["ID"]): r for r in self.rows("Item")}
        self.sparse = {int(r["ID"]): r for r in self.rows("ItemSparse")}
        self.item_effect = {int(r["ID"]): r for r in self.rows("ItemEffect")}
        self.item_effects = collections.defaultdict(list)
        for r in self.rows("ItemXItemEffect"):
            self.item_effects[int(r["ItemID"])].append(int(r["ItemEffectID"]))
        self.spell_effects = collections.defaultdict(list)
        for r in self.rows("SpellEffect"):
            if r["DifficultyID"] == "0":
                self.spell_effects[int(r["SpellID"])].append(r)
        for effects in self.spell_effects.values():
            effects.sort(key=lambda r: int(r["EffectIndex"]))
        durations = {int(r["ID"]): int(r["Duration"]) for r in self.rows("SpellDuration")}
        self.seconds = {}
        for r in self.rows("SpellMisc"):
            if r["DifficultyID"] == "0":
                self.seconds.setdefault(int(r["SpellID"]), durations.get(int(r["DurationIndex"]), 0) / 1000)
        self.enchant = {int(r["ID"]): r for r in self.rows("SpellItemEnchantment")}

    def rows(self, table):
        with open(os.path.join(self.folder, table + ".csv"), encoding="utf-8", newline="") as f:
            return list(csv.DictReader(f))

    def use_spell(self, item):
        """The spell the item casts when it is used: the first one, as the tooltip has it."""
        effects = [self.item_effect[e] for e in self.item_effects.get(item, []) if e in self.item_effect]
        effects.sort(key=lambda r: int(r["LegacySlotIndex"]))
        for r in effects:
            if r["TriggerType"] == "0" and int(r["SpellID"]) > 0:
                return int(r["SpellID"])
        return None


class Reading:
    """What one item gives: stats (name -> amount) and the letters of what it restores."""

    def __init__(self, tables):
        self.t = tables
        self.stats = {}
        self.restores = set()

    def add(self, found):
        for name, amount in found.items():
            self.stats[name] = self.stats.get(name, 0) + amount

    def spell(self, spell, depth=0, value=None):
        """`value`: the amount the spell was triggered with, which then stands in for its own."""
        found = {}
        seconds = self.t.seconds.get(spell, 0)
        for e in self.t.spell_effects.get(spell, []):
            effect, aura = int(e["Effect"]), int(e["EffectAura"])
            amount = value if value is not None else float(e["EffectBasePointsF"])
            misc, trigger = int(e["EffectMiscValue_0"]), int(e["EffectTriggerSpell"])
            if effect == HEAL:
                self.restores.add("H")
            elif effect == ENERGIZE:
                if misc in POWERS: self.restores.add(POWERS[misc])
            elif effect == TRIGGER_SPELL:
                if trigger and depth < 2: self.spell(trigger, depth + 1)
            elif effect in ENCHANT_TEMPORARY:
                self.enchantment(misc)
            elif effect == APPLY_AURA:
                if aura == PERIODIC_TRIGGER:
                    if trigger and depth < 2: self.spell(trigger, depth + 1)
                elif aura == PERIODIC_TRIGGER_WITH_VALUE:
                    if trigger and depth < 2: self.spell(trigger, depth + 1, float(e["EffectBasePointsF"]))
                elif aura == 8:                                 # healing over time: a bandage
                    self.restores.add("H")
                elif aura == 24:                                # the same for mana, rage...
                    if misc in POWERS: self.restores.add(POWERS[misc])
                elif aura == 84:                                # health while it lasts: food
                    if 0 < seconds <= MEAL_SECONDS: self.restores.add("H")
                    elif amount > 0: found["Hp5"] = max(found.get("Hp5", 0), amount)
                elif aura == 85:                                # mana while it lasts: a drink, or an elixir
                    if misc != 0: continue
                    if 0 < seconds <= MEAL_SECONDS: self.restores.add("M")
                    elif amount > 0: found["Mp5"] = max(found.get("Mp5", 0), amount)
                elif amount > 0:
                    # Two auras of one spell that Pawn knows by one name (chance to hit with
                    # weapons, with spells) are one bonus, not two.
                    for name in aura_stats(aura, misc) or []:
                        found[name] = max(found.get(name, 0), amount)
        self.add(found)

    def enchantment(self, enchant):
        r = self.t.enchant.get(enchant)
        if not r: return
        found = {}
        for i in range(3):
            kind, amount, arg = int(r[f"Effect_{i}"]), float(r[f"EffectPointsMin_{i}"]), int(r[f"EffectArg_{i}"])
            if kind == ENCHANT_SPELL and arg:
                self.spell(arg, 2)                              # what the enchantment's own spell adds; no further
            elif kind == ENCHANT_STAT and amount > 0 and arg in ITEM_MODS:
                found[ITEM_MODS[arg]] = found.get(ITEM_MODS[arg], 0) + amount
            elif kind == ENCHANT_RESISTANCE and amount > 0 and arg == 0:
                found["Armor"] = found.get("Armor", 0) + amount
        self.add(found)


def number(value):
    return str(int(value)) if value == int(value) else f"{value:g}"


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


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--build", required=True, help="the client build, as wago.tools names it: 1.60.1.70938")
    parser.add_argument("--tables", help="folder for the downloaded tables (default: a folder under the system's temp)")
    parser.add_argument("--out", default=os.path.join(here, "..", "UpgradeScout", "SupplyData.lua"))
    parser.add_argument("--report", action="store_true", help="print every item that was read")
    args = parser.parse_args()

    folder = args.tables or os.path.join(tempfile.gettempdir(), "upgrade-scout-tables", args.build)
    download(args.build, folder)
    tables = Tables(folder)

    stats, restores = {}, {}
    for item, row in sorted(tables.item.items()):
        if int(row["ClassID"]) != CONSUMABLE or item not in tables.sparse: continue
        if int(tables.sparse[item]["Bonding"]) not in SELLABLE: continue
        spell = tables.use_spell(item)
        if not spell: continue
        reading = Reading(tables)
        reading.spell(spell)
        if reading.stats: stats[item] = reading.stats
        if reading.restores: restores[item] = "".join(sorted(reading.restores))
        if args.report and (reading.stats or reading.restores):
            sparse = tables.sparse[item]
            print(f"{item:7d} sub{row['SubclassID']:>3} req{sparse['RequiredLevel']:>3} {sparse['Display_lang'][:38]:38} "
                  f"{restores.get(item, ''):3} {', '.join(f'{k} {number(v)}' for k, v in sorted(reading.stats.items()))}")

    lines = [
        "-- Made by scripts/make-supply-data.py from the game's tables, build " + args.build + ". Not written by hand:",
        "-- run the script again when the game gets new consumables.",
        "local _, ns = ...",
        "",
        "-- What a consumable gives, for the ones the tables say it of (see Supplies.lua).",
        "local D = { build = \"" + args.build + "\" }",
        "ns.SupplyData = D",
        "",
        "-- item -> what its effect adds, under Pawn's names for stats. Chances and haste are in percent.",
        "D.stats = {",
    ]
    for item in sorted(stats):
        pairs = ", ".join(f"{name} = {number(amount)}" for name, amount in sorted(stats[item].items()))
        lines.append(f"    [{item}] = {{ {pairs} }},")
    lines += [
        "}",
        "",
        "-- item -> what it restores: H health, M mana, R rage, E energy, F focus.",
        "D.restores = {",
    ]
    for item in sorted(restores):
        lines.append(f"    [{item}] = \"{restores[item]}\",")
    lines += ["}", ""]
    with open(args.out, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))
    print(f"{os.path.normpath(args.out)}: {len(stats)} items with stats, {len(restores)} that restore something",
          file=sys.stderr)


if __name__ == "__main__":
    main()
