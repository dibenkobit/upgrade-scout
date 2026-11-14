"""Builds UpgradeScout/Weights.lua: the profiles gear is scored on, from the weights a simulator found.

    python scripts/make-weights.py --build 1.60.1.70938
    python scripts/make-weights.py --build 1.60.1.70938 --report     (also says what it left out)

--weights is what the weights run wrote (scripts/weights/run.sh); by default the run kept beside
it, scripts/weights/weights-60b.json.

A profile is what each stat is worth for one way of playing a class. The worth comes from the
wowsims/forever simulator (https://github.com/wowsims/forever, MIT): for every talent tree it
has a rotation for, the weights run (scripts/weights/) sims a level 60 character in its preset
gear and measures how much more damage one more point of each stat brings. --weights is what
that run wrote. A tree the simulator does not cover gets a profile estimated by role from the
trees it does (see HEALER), or from --approx, and the addon marks it as an approximation. Two
things are set by hand, because a simulation of damage cannot measure them (see BY_HAND); the
addon says so in the profile's tooltip.

The simulator knows stats by its own names (StatStrength) and the addon by the game's
(ITEM_MOD_STRENGTH_SHORT, as C_Item.GetItemStats has them). GAME below says which of the
simulator's stats each of the game's names adds, the way the simulator itself reads gear
(tools/database/dbc/maps.go): "Attack Power" on gear is melee and ranged attack power both,
"Spell Power" is spell damage and healing both.

The names of the talent trees are the game's own, in every language, from its TalentTab table
(downloaded from wago.tools for the build into --tables, once).

Below level 60 a rating is worth less than these weights say: see LEVELING.

Hit and expertise are measured below the cap (a step down from it where the preset gear reaches it),
since the players the addon is for are far from it. A tank's profile adds what a point is worth for
staying alive and what it is worth for threat: see TANK.
"""
import argparse
import csv
import json
import os
import sys
import tempfile
import urllib.request

csv.field_size_limit(10 ** 9)

URL = "https://wago.tools/db2/{table}/csv?build={build}&locale={locale}"
AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# The languages the addon speaks, and esMX, which the game has apart from esES.
LOCALES = ["enUS", "ruRU", "deDE", "frFR", "zhCN", "ptBR", "esES", "esMX", "koKR", "zhTW"]

SOURCE = "wowsims/forever"
APPROX_MARK = "~"
DIGITS = 2


def mod(name):
    return "ITEM_MOD_" + name + "_SHORT"


# The game's name for a stat -> the simulator's stats it adds a point of each of.
GAME = {
    mod("STRENGTH"): ["StatStrength"], mod("AGILITY"): ["StatAgility"], mod("STAMINA"): ["StatStamina"],
    mod("INTELLECT"): ["StatIntellect"], mod("SPIRIT"): ["StatSpirit"],
    mod("HEALTH"): ["StatHealth"], mod("MANA"): ["StatMana"],
    mod("HIT_RATING"): ["StatHitRating"], mod("CRIT_RATING"): ["StatCritRating"], mod("HASTE_RATING"): ["StatHasteRating"],
    mod("EXPERTISE_RATING"): ["StatExpertiseRating"], mod("ARMOR_PENETRATION_RATING"): ["StatArmorPenetration"],
    mod("DEFENSE_SKILL_RATING"): ["StatDefenseRating"], mod("DODGE_RATING"): ["StatDodgeRating"],
    mod("PARRY_RATING"): ["StatParryRating"], mod("BLOCK_RATING"): ["StatBlockRating"], mod("BLOCK_VALUE"): ["StatBlockValue"],
    mod("ATTACK_POWER"): ["StatAttackPower", "StatRangedAttackPower"],
    mod("RANGED_ATTACK_POWER"): ["StatRangedAttackPower"],
    mod("FERAL_ATTACK_POWER"): ["StatFeralAttackPower"],
    mod("SPELL_POWER"): ["StatSpellDamage", "StatHealingPower"],
    mod("SPELL_DAMAGE_DONE"): ["StatSpellDamage"], mod("SPELL_HEALING_DONE"): ["StatHealingPower"],
    mod("HOLY_DAMAGE_DONE"): ["StatHolyDamage"], mod("FIRE_DAMAGE_DONE"): ["StatFireDamage"],
    mod("NATURE_DAMAGE_DONE"): ["StatNatureDamage"], mod("FROST_DAMAGE_DONE"): ["StatFrostDamage"],
    mod("SHADOW_DAMAGE_DONE"): ["StatShadowDamage"], mod("ARCANE_DAMAGE_DONE"): ["StatArcaneDamage"],
    mod("PHYSICAL_DAMAGE_DONE"): ["StatPhysicalDamage"],
    mod("SPELL_PENETRATION"): ["StatSpellPiercing"],
    mod("MANA_REGENERATION"): ["StatMP5"], mod("POWER_REGEN0"): ["StatMP5"],
    mod("EXTRA_ARMOR"): ["StatBonusArmor"],
    "RESISTANCE0_NAME": ["StatArmor"],
    "RESISTANCE2_NAME": ["StatFireResistance"], "RESISTANCE3_NAME": ["StatNatureResistance"],
    "RESISTANCE4_NAME": ["StatFrostResistance"], "RESISTANCE5_NAME": ["StatShadowResistance"],
    "RESISTANCE6_NAME": ["StatArcaneResistance"],
    # What only a consumable adds (see make-supply-data.py): attack power with melee weapons alone.
    mod("MELEE_ATTACK_POWER"): ["StatAttackPower"],
}
# A consumable can add a chance with weapons alone, or with spells alone; gear has one rating for
# both. Each of those names is worth the shared rating to a profile that does that kind of damage,
# and nothing to one that does not.
KINDS = {"MELEE": "melee", "RANGED": "ranged", "SPELL": "spell"}
for what, shared in (("HIT", "StatHitRating"), ("CRIT", "StatCritRating"), ("HASTE", "StatHasteRating")):
    for kind in KINDS:
        GAME[mod(f"{what}_{kind}_RATING")] = [(shared, KINDS[kind])]

# Below level 60 a rating (a chance to hit or crit, haste, expertise) is worth a share of its
# level 60 worth, and the addon scales it by the character's level (Score.LevelFactor). The
# shares come from simulations of leveling characters on MythicSim's forever engine
# (https://github.com/sage3648/mythicsim-forever-engine, MIT; commit f9c5172 of 2026-11-14),
# which, unlike wowsims/forever, sims a character below 60: an Arms warrior, a Frost mage and a
# Beast Mastery hunter at levels 20, 40 and 60, solo against a creature two levels higher,
# 120 s, six seeds of 10,000 fights each. Relative to the main stat, hit, crit and haste rating
# were worth on average 0.17 of their level 60 worth at 20 (0.13 to 0.25 by class and rating)
# and 0.57 at 40 (0.38 to 0.78). Strength, attack power, weapon damage and spell damage kept
# their worth within about 40%, and are left as they are. Spell penetration was not part of the
# study, but it works the same way (it adds a share of the damage done, against the resistance a
# higher-level target has) and its level 60 weight, measured against a raid boss, is the heaviest of
# a caster's: it is scaled with the ratings.
LEVELING_POINTS = [(20, 0.17), (40, 0.57), (60, 1)]
LEVELING_STATS = [mod(f"{what}{kind}_RATING") for what in ("HIT", "CRIT", "HASTE")
                  for kind in ("", "_MELEE", "_RANGED", "_SPELL")] + [mod("EXPERTISE_RATING"), mod("SPELL_PENETRATION")]

# The weapon a profile's damage per second is worth this much for, by the simulator's pseudo-stats.
DPS = {"mh": "PseudoStatMainHandDps", "oh": "PseudoStatOffHandDps", "ranged": "PseudoStatRangedDps"}

# Set by hand (the profile's tooltip says so), because a simulation of damage cannot tell what
# they are worth:
#   Stamina, as a share of the profile's main stat, where the simulation gave it no worth: what
#   staying alive is worth while leveling, the more to one who fights in melee.
#   A healer's Intellect, Spirit and mana regeneration, relative to healing: a healer runs out of
#   mana, and the casters the healer's estimate comes from, simmed in a raid with every buff, do not.
STAMINA_SHARE = {"melee": 0.3, "ranged": 0.2, "spell": 0.1}
HEALER_MANA = {"StatIntellect": 0.6, "StatSpirit": 0.5, "StatMP5": 1.5}


def main_stat(worth, kind):
    """The worth of the profile's main stat: Strength or Agility, or spell damage or healing."""
    if kind == "spell":
        return max(worth.get("StatSpellDamage", 0), worth.get("StatHealingPower", 0)) or 1.0
    return max(worth.get("StatStrength", 0), worth.get("StatAgility", 0)) or 1.0


def by_hand(worth, kind):
    """The worth with Stamina set where the simulation gave it none."""
    worth = dict(worth)
    if worth.get("StatStamina", 0) <= 0:
        worth["StatStamina"] = STAMINA_SHARE[kind] * main_stat(worth, kind)
    return worth


# A tank's profile: what a point is worth for staying alive, by the simulator's TMI (with the
# tank tanking a level 63 target, relative to Stamina = 1), plus what it is worth for threat (TPS,
# relative to the tree's main stat = 1). A point of Stamina for staying alive counts as much as a
# point of Strength (Agility for a bear) for threat. Threat a stat costs (a tank who is hit less
# gets less rage) is not counted against it.
def tank(tree, report):
    """The tank's worth (simulator stat -> worth), or None when the tree has no tank metrics."""
    if not tree.get("tankMetrics"):
        return None
    survival, threat = eps(tree, report, "tmi"), eps(tree, report, "tps")
    stamina = survival.get("StatStamina", 0)
    if stamina <= 0:
        return None
    return {stat: survival.get(stat, 0) / stamina + threat.get(stat, 0) for stat in set(survival) | set(threat)}


# No simulator covers healing yet. A healer's profile is an estimate by role: what a point of a
# stat is worth to a caster who runs on mana, as the mean of the caster trees of the classes that
# heal, with the worth of spell damage given to healing instead (the reference, 1), and nothing for
# hit, which a heal does not need, or for what only adds damage.
HEALER_FROM = [("Priest", "Shadow"), ("Shaman", "Elemental"), ("Druid", "Balance")]
HEALER_KEEPS = ["StatIntellect", "StatSpirit", "StatMP5", "StatMana", "StatCritRating", "StatHasteRating",
                "StatStamina"]


def healer(trees, report):
    """The healer's estimate (simulator stat -> worth), or None when no caster tree has weights."""
    found = [trees[key][0] for key in HEALER_FROM if key in trees and not trees[key][1]]
    if not found:
        return None
    worth = {"StatHealingPower": 1.0}
    for stat in HEALER_KEEPS:
        values = [eps(tree, False).get(stat, 0.0) for tree in found]
        mean = sum(values) / len(values)
        if mean > 0:
            worth[stat] = mean
    worth.update(HEALER_MANA)
    if report:
        print("healer, from " + ", ".join(f"{t['class']} {t['tree']} (relative to {t['reference']})" for t in found),
              file=sys.stderr)
    return worth


# The profiles of each class, in the order of its talent trees in the game.
#   id     what the addon saves for the player's choice: never change one
#   tab    the talent tree (TalentTab), whose name is the profile's
#   role   instead of a tree: the role, for a profile that stands for more than one tree
#   form   a druid's shape, for a tree with two ways of playing it
#   sim    the class and tree in --weights
#   heals  no simulation of its own: the healer's estimate (HEALER_FROM), unless --weights has one
#   tank   scored as a tank (see TANK), from the run's tank metrics
#   kind   the damage it does, for the chances a consumable adds (KINDS)
CLASSES = {
    "WARRIOR": [
        dict(id="WARRIOR_ARMS", tab=161, sim=("Warrior", "Arms"), kind="melee"),
        dict(id="WARRIOR_FURY", tab=164, sim=("Warrior", "Fury"), kind="melee"),
        dict(id="WARRIOR_PROTECTION", tab=163, sim=("Warrior", "Protection"), tank=True, kind="melee"),
    ],
    "PALADIN": [
        dict(id="PALADIN_HOLY", tab=382, sim=("Paladin", "Holy"), heals=True, kind="spell"),
        dict(id="PALADIN_PROTECTION", tab=383, sim=("Paladin", "Protection"), tank=True, kind="melee"),
        dict(id="PALADIN_RETRIBUTION", tab=381, sim=("Paladin", "Retribution"), kind="melee"),
    ],
    "HUNTER": [
        dict(id="HUNTER_BEAST_MASTERY", tab=361, sim=("Hunter", "Beast Mastery"), kind="ranged"),
        dict(id="HUNTER_MARKSMANSHIP", tab=363, sim=("Hunter", "Marksmanship"), kind="ranged"),
        dict(id="HUNTER_SURVIVAL", tab=362, sim=("Hunter", "Survival"), kind="ranged"),
    ],
    "ROGUE": [
        dict(id="ROGUE_ASSASSINATION", tab=182, sim=("Rogue", "Assassination"), kind="melee"),
        dict(id="ROGUE_COMBAT", tab=181, sim=("Rogue", "Combat"), kind="melee"),
        dict(id="ROGUE_SUBTLETY", tab=183, sim=("Rogue", "Subtlety"), kind="melee"),
    ],
    "PRIEST": [
        dict(id="PRIEST_HEALER", role="HEALER", sim=("Priest", "Healer"), heals=True, kind="spell"),
        dict(id="PRIEST_SHADOW", tab=203, sim=("Priest", "Shadow"), kind="spell"),
    ],
    "SHAMAN": [
        dict(id="SHAMAN_ELEMENTAL", tab=261, sim=("Shaman", "Elemental"), kind="spell"),
        dict(id="SHAMAN_ENHANCEMENT", tab=263, sim=("Shaman", "Enhancement"), kind="melee"),
        dict(id="SHAMAN_RESTORATION", tab=262, sim=("Shaman", "Restoration"), heals=True, kind="spell"),
    ],
    "MAGE": [
        dict(id="MAGE_ARCANE", tab=81, sim=("Mage", "Arcane"), kind="spell"),
        dict(id="MAGE_FIRE", tab=41, sim=("Mage", "Fire"), kind="spell"),
        dict(id="MAGE_FROST", tab=61, sim=("Mage", "Frost"), kind="spell"),
    ],
    "WARLOCK": [
        dict(id="WARLOCK_AFFLICTION", tab=302, sim=("Warlock", "Affliction"), kind="spell"),
        dict(id="WARLOCK_DEMONOLOGY", tab=303, sim=("Warlock", "Demonology"), kind="spell"),
        dict(id="WARLOCK_DESTRUCTION", tab=301, sim=("Warlock", "Destruction"), kind="spell"),
    ],
    "DRUID": [
        dict(id="DRUID_BALANCE", tab=283, sim=("Druid", "Balance"), kind="spell"),
        dict(id="DRUID_FERAL_CAT", tab=281, form="CAT", sim=("Druid", "Feral Cat"), kind="melee"),
        dict(id="DRUID_FERAL_BEAR", tab=281, form="BEAR", sim=("Druid", "Feral Bear"), tank=True, kind="melee"),
        dict(id="DRUID_RESTORATION", tab=282, sim=("Druid", "Restoration"), heals=True, kind="spell"),
    ],
}
# The profile a character of the class starts on: the tree most of them level in.
START = {
    "WARRIOR": "WARRIOR_ARMS", "PALADIN": "PALADIN_RETRIBUTION", "HUNTER": "HUNTER_BEAST_MASTERY",
    "ROGUE": "ROGUE_COMBAT", "PRIEST": "PRIEST_SHADOW", "SHAMAN": "SHAMAN_ENHANCEMENT", "MAGE": "MAGE_FROST",
    "WARLOCK": "WARLOCK_AFFLICTION", "DRUID": "DRUID_FERAL_CAT",
}


def download(build, folder):
    """TalentTab in every language, each in a folder of its own."""
    for locale in LOCALES:
        path = os.path.join(folder, locale, "TalentTab.csv")
        if os.path.exists(path) and os.path.getsize(path) > 0:
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print("downloading TalentTab", locale, file=sys.stderr)
        request = urllib.request.Request(URL.format(table="TalentTab", build=build, locale=locale),
                                         headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request) as response, open(path, "wb") as out:
            out.write(response.read())


def tree_names(folder):
    """locale -> talent tree -> its name."""
    out = {}
    for locale in LOCALES:
        with open(os.path.join(folder, locale, "TalentTab.csv"), encoding="utf-8", newline="") as f:
            out[locale] = {int(r["ID"]): r["Name_lang"] for r in csv.DictReader(f)}
    return out


# Measured below the cap (see the top of this file).
BELOW_CAP = {"StatHitRating", "StatExpertiseRating"}


def eps(tree, report, metric="dps"):
    """The simulator's stat -> its worth relative to the tree's reference stat, on a metric: dps
    (damage, the default), tps (threat), tmi (a tank's risk of dying). A worth the run could not
    tell apart from nothing (its 90% interval reaches zero) is nothing, and so is one below zero:
    no stat makes a character worse."""
    out = {}
    for stat, w in tree["weights"].items():
        if stat in BELOW_CAP and isinstance(w.get("below"), dict):
            w = w["below"]
        if metric != "dps":
            w = w.get(metric) or {}
        ep, margin = w.get("ep", 0) or 0, w.get("epCi90", 0) or 0
        if w.get("identicalToBaseline") or ep <= margin:
            if ep > 0 and report:
                print(f"   {stat}: {ep:.3f} within {margin:.3f} of nothing; left out", file=sys.stderr)
            continue
        out[stat] = ep
    return out


def profile(spec, worth):
    """A profile's weights under the game's names, and its weights for damage per second."""
    weights = {}
    for name, sources in GAME.items():
        total = 0.0
        for source in sources:
            if isinstance(source, tuple):
                stat, kind = source
                if kind != spec["kind"]:
                    continue
                source = stat
            total += worth.get(source, 0.0)
        total = round(total, DIGITS)
        if total > 0:
            weights[name] = total
    dps = {hand: round(worth.get(stat, 0.0), DIGITS) for hand, stat in DPS.items()}
    return weights, {hand: value for hand, value in dps.items() if value > 0}


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def number(value):
    return str(int(value)) if value == int(value) else f"{value:g}"


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--weights", default=os.path.join(here, "weights", "weights-60b.json"),
                        help="what the weights run wrote (default: scripts/weights/weights-60b.json)")
    parser.add_argument("--approx", help="weights for trees the simulator does not cover, in the same form; "
                                         "their profiles are marked as approximations")
    parser.add_argument("--build", required=True, help="the client build, as wago.tools names it: 1.60.1.70938")
    parser.add_argument("--tables", help="folder for the downloaded tables (default: a folder under the system's temp)")
    parser.add_argument("--out", default=os.path.join(here, "..", "UpgradeScout", "Weights.lua"))
    parser.add_argument("--report", action="store_true", help="say what was left out, and print every profile")
    args = parser.parse_args()

    folder = args.tables or os.path.join(tempfile.gettempdir(), "upgrade-scout-tables", args.build)
    download(args.build, folder)
    names = tree_names(folder)

    run = json.load(open(args.weights, encoding="utf-8"))
    trees = {(t["class"], t["tree"]): (t, False) for t in run["trees"]}
    if args.approx:
        for t in json.load(open(args.approx, encoding="utf-8"))["trees"]:
            trees.setdefault((t["class"], t["tree"]), (t, True))

    healing = healer(trees, args.report)
    classes, start, titles, profiles, missing = {}, {}, {locale: {} for locale in LOCALES}, {}, []
    for cls, specs in CLASSES.items():
        for spec in specs:
            found = trees.get(spec["sim"])
            if found:
                tree, approx = found
                if args.report:
                    print(f"{spec['id']}: {tree['class']} {tree['tree']}, relative to {tree['reference']}"
                          f"{' (an approximation)' if approx else ''}", file=sys.stderr)
                worth = (spec.get("tank") and tank(tree, args.report)) or eps(tree, args.report)
            elif spec.get("heals") and healing:
                worth, approx = healing, True
            else:
                missing.append(spec["id"])
                continue
            weights, dps = profile(spec, by_hand(worth, spec["kind"]))
            entry = {"class": cls, "weights": weights, **dps}
            if approx:
                entry["approx"] = True
            for key in ("role", "form"):
                if key in spec:
                    entry[key] = spec[key]
            profiles[spec["id"]] = entry
            classes.setdefault(cls, []).append(spec["id"])
            if "tab" in spec:
                for locale in LOCALES:
                    titles[locale][spec["id"]] = names[locale][spec["tab"]]
        if cls in classes:
            start[cls] = START[cls] if START[cls] in classes[cls] else classes[cls][0]
    if missing:
        print("no weights for: " + ", ".join(missing), file=sys.stderr)

    engine = run.get("engine", {})
    used = sorted({name for p in profiles.values() for name in p["weights"]})
    local = {name: (name[9:-6] if name.startswith("ITEM_MOD_") else
                    "ARMOR" if name == "RESISTANCE0_NAME" else name.replace("RESISTANCE", "RESIST").replace("_NAME", ""))
             for name in used}
    assert len(set(local.values())) == len(local)

    lines = [
        "-- Made by scripts/make-weights.py from the weights the " + SOURCE + " simulator found: commit "
        + engine.get("commit", "?")[:10] + " of " + engine.get("commitDate", "?")[:10] + ", run at "
        + str(run.get("ranAt", "?"))[:10] + ".",
        "-- Not written by hand: run the script again on a new run of the weights (scripts/weights/).",
        "local _, ns = ...",
        "",
        "-- The profiles gear is scored on (see Score.lua). A weight is what a point of the stat is worth",
        "-- next to a point of the profile's main stat, for a level 60 character. `mh`, `oh` and `ranged`",
        "-- are the worth of a point of a weapon's damage per second in the main hand, the off hand and",
        "-- the ranged slot. `approx`: the weights are an estimate, not the simulator's for that tree.",
        "local W = {",
        f"    source = {lua_string(SOURCE)},",
        f"    APPROX_MARK = {lua_string(APPROX_MARK)},",
        "}",
        "ns.Weights = W",
        "",
        "-- The profiles of a class, in the order of its talent trees, and the one a character starts on.",
        "W.classes = {",
    ]
    for cls in CLASSES:
        if cls in classes:
            lines.append(f"    {cls} = {{ " + ", ".join(lua_string(i) for i in classes[cls]) + " },")
    lines += ["}", "W.start = {"]
    for cls in CLASSES:
        if cls in start:
            lines.append(f"    {cls} = {lua_string(start[cls])},")
    lines += [
        "}",
        "",
        "-- Below level 60 these ratings count for a share of their worth: the share at a level, from",
        "-- simulations of leveling characters on MythicSim's forever engine (see make-weights.py).",
        "W.leveling = {",
        "    points = { " + ", ".join(f"{{ {level}, {number(share)} }}" for level, share in LEVELING_POINTS) + " },",
        "    stats = {",
    ]
    for name in LEVELING_STATS:
        lines.append(f"        {name} = true,")
    lines += ["    },", "}", "", "-- The names of the talent trees, as the game has them in each language.", "W.titles = {"]
    for locale in LOCALES:
        pairs = ", ".join(f"{i} = {lua_string(t)}" for i, t in titles[locale].items())
        lines.append(f"    {locale} = {{ {pairs} }},")
    lines += ["}", "", "-- The game's names for stats, each written once here."]
    for name in used:
        lines.append(f"local {local[name]} = {lua_string(name)}")
    lines += ["", "W.profiles = {"]
    for cls in CLASSES:
        for i in classes.get(cls, []):
            p = profiles[i]
            head = [f"class = {lua_string(cls)}"]
            for key in ("role", "form"):
                if key in p:
                    head.append(f"{key} = {lua_string(p[key])}")
            if p.get("approx"):
                head.append("approx = true")
            for hand in DPS:
                if hand in p:
                    head.append(f"{hand} = {number(p[hand])}")
            weights = sorted(p["weights"].items(), key=lambda kv: (-kv[1], kv[0]))
            lines.append(f"    {i} = {{ " + ", ".join(head) + ",")
            lines.append("        weights = { " + ", ".join(f"[{local[n]}] = {number(v)}" for n, v in weights) + " } },")
            if args.report:
                print(f"{i}: " + ", ".join(f"{local[n]} {number(v)}" for n, v in weights)
                      + "  | " + ", ".join(f"{h} {number(p[h])}" for h in DPS if h in p), file=sys.stderr)
    lines += ["}", ""]
    with open(args.out, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))
    print(f"{os.path.normpath(args.out)}: {len(profiles)} profiles for {len(classes)} classes", file=sys.stderr)


if __name__ == "__main__":
    main()
