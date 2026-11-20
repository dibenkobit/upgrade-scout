-- A check of UpgradeScout/Leveling.lua against Forever Leveling BiS's own code: the copy of
-- that addon a player has installed. Nothing of it is in this repository; its data and
-- scoring files are loaded from where it is installed, on top of the tests' stand-in for
-- the client (tests/wow.lua). Worth running again when Forever Leveling BiS has a new version.
--
-- A character of a class, spec and level is "played", and every item of its data is scored
-- twice by Upgrade Scout: as for the character being played (its ScoreItem), and as for
-- another character of the same class, spec and level (a sum on its GetWeights). The game's
-- count of an item's stats (GetItemStats) is made from its own data, stat for stat. The two
-- should agree but for what its API does not give out: an item's effect, armor an item has
-- as a bonus, and a chance to hit with ranged weapons only. It also says which weapons it
-- refuses the character where this addon's own rule has no objection, by kind.
--
-- Run from the project folder, with Lua 5.1:
--   lua5.1 scripts/check-leveling.lua <its folder> CLASS spec level [weapon setup]
--   lua5.1 scripts/check-leveling.lua "C:/Games/World of Warcraft/_forever_/Interface/AddOns/ForeverLevelingBiS" ROGUE combat 25
local realPrint = print
local FLB, CLASS, SPEC, LEVEL, SETUP = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
if not (FLB and CLASS and SPEC and LEVEL) then
    realPrint("usage: lua5.1 scripts/check-leveling.lua <folder of Forever Leveling BiS> CLASS spec level [weapon setup]")
    os.exit(2)
end
FLB = FLB:gsub("\\", "/"):gsub("/*$", "/")
local W = dofile("tests/wow.lua")

---------------------------------------------------------------------------
-- More of the client, as Forever Leveling BiS asks for it
---------------------------------------------------------------------------
bit = bit or { band = function(a, b)
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end }
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
W.player = { name = "Tester", level = LEVEL, class = CLASS, money = 100000, dualWield = true }
function UnitClass() return CLASS, CLASS, CLASS_ID[CLASS] end
-- An orc: a race whose traits add nothing to an item's worth there.
function UnitRace() return "Orc", "Orc", 2 end
function UnitFactionGroup() return "Horde" end
function GetUnitName() return W.player.name end
function GetInventoryItemID(_, slot)
    local link = W.equipped[slot]
    return link and tonumber(link:match("item:(%d+)")) or nil
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function geterrorhandler() return function(err) error(err, 0) end end

---------------------------------------------------------------------------
-- Forever Leveling BiS itself: its data and what scores
---------------------------------------------------------------------------
local flb = {}
flb.UI = { Refresh = function() end, ShowSkillRanks = function() end }
flb.QuestWindow = { Refresh = function() end, TipLines = function() end }
flb.Settings = { Update = function() end }
-- Its own lines and arrows are left out: this is about its numbers.
ForeverLevelingBiSDB = { tooltip = false, bagMarks = false }
for _, file in ipairs({ "Core.lua", "Locale.lua", "Player.lua", "Data/Tables.lua", "Data/Items.lua", "Data/Overrides.lua",
    "Data/ItemEffects.lua", "Data/ModelWeights.lua", "Weights.lua", "WeightProfiles.lua", "Racials.lua", "Scoring.lua",
    "Equipped.lua", "Tooltip.lua", "API.lua", "BagMarks.lua" }) do
    local chunk = assert(loadfile(FLB .. file))
    chunk("ForeverLevelingBiS", flb)
end
W.Fire("ADDON_LOADED", "ForeverLevelingBiS")
W.Fire("PLAYER_LOGIN")
W.Run(0.5)
local API = ForeverLevelingBiS_API
assert(type(API) == "table" and (API.version or 1) >= 2, "its API, version 2 or later")
local mine = ForeverLevelingBiSDB.chars["Tester-Testrealm"]
assert(type(mine) == "table", "it keeps the character under its full name and realm")
mine.spec = SPEC
if SETUP then mine.weapons = { [CLASS .. ":" .. SPEC] = SETUP } end
local spec, setup, class = API.GetSpec()
assert(spec == SPEC and class == CLASS, "its main spec is the one chosen: " .. tostring(spec))

---------------------------------------------------------------------------
-- Its items, as the game would have them
---------------------------------------------------------------------------
local EQUIP = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST",
    [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER",
    [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK",
    [17] = "INVTYPE_2HWEAPON", [20] = "INVTYPE_ROBE", [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND",
    [23] = "INVTYPE_HOLDABLE", [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC",
}
local function Mod(name) return "ITEM_MOD_" .. name .. "_SHORT" end
-- Its key for a stat -> the game's name for it, and how many of the game's points are one of its.
local GAME = {
    str = { Mod("STRENGTH") }, agi = { Mod("AGILITY") }, sta = { Mod("STAMINA") }, int = { Mod("INTELLECT") }, spi = { Mod("SPIRIT") },
    atkpwr = { Mod("ATTACK_POWER") }, rgdatkpwr = { Mod("RANGED_ATTACK_POWER") }, feratkpwr = { Mod("FERAL_ATTACK_POWER") },
    splpwr = { Mod("SPELL_POWER") }, spldmg = { Mod("SPELL_DAMAGE_DONE") }, splheal = { Mod("SPELL_HEALING_DONE") },
    arcsplpwr = { Mod("ARCANE_DAMAGE_DONE") }, firsplpwr = { Mod("FIRE_DAMAGE_DONE") }, frosplpwr = { Mod("FROST_DAMAGE_DONE") },
    holsplpwr = { Mod("HOLY_DAMAGE_DONE") }, natsplpwr = { Mod("NATURE_DAMAGE_DONE") }, shasplpwr = { Mod("SHADOW_DAMAGE_DONE") },
    splpen = { Mod("SPELL_PENETRATION") }, defrtng = { Mod("DEFENSE_SKILL_RATING") }, manargn = { Mod("MANA_REGENERATION") },
    healthrgn = { Mod("HEALTH_REGENERATION") }, hastertng = { Mod("HASTE_RATING") },
    critPct = { Mod("CRIT_RATING"), 14 }, hitPct = { Mod("HIT_RATING"), 10 }, expPct = { Mod("EXPERTISE_RATING"), 10 },
    dodgePct = { Mod("DODGE_RATING"), 12 }, parryPct = { Mod("PARRY_RATING"), 15 }, blockPct = { Mod("BLOCK_RATING"), 5 },
}
local function IsGear(item)
    return type(item) == "table" and EQUIP[item.slot or 0] ~= nil and (item.class == 2 or item.class == 4)
end
local unknown, count = {}, 0
for id, item in pairs(flb.Items) do
    if IsGear(item) then
        local game = {}
        local armor = 0
        local def = {
            id = id, name = flb.ItemName(id), equipLoc = EQUIP[item.slot], classID = item.class,
            subClassID = math.max(item.subclass or 0, 0), level = math.max(item.reqLevel or 1, 1), quality = item.quality or 2,
        }
        for key, amount in pairs(item.stats or {}) do
            local to = GAME[key]
            if to then
                game[to[1]] = (game[to[1]] or 0) + amount * (to[2] or 1)
            elseif key == "armor" or key == "armorbonus" then
                -- The game's count of armor is the two together.
                armor = armor + amount
            elseif key == "block" then
                -- Its `block` is the bonus to the block value that a few items have, which
                -- the game counts among an item's stats.
                game[Mod("BLOCK_VALUE")] = amount
            else
                unknown[key] = (unknown[key] or 0) + 1
            end
        end
        if armor ~= 0 then game.RESISTANCE0_NAME = armor end
        -- A shield's own block is a line of its tooltip and no stat of the game's. Forever
        -- Leveling BiS has none of it in its data, so the amount here is made up: a sum
        -- that counted it would differ from its score for every shield.
        if item.class == 4 and item.subclass == 6 then def.block = 40 end
        if item.weapon and item.weapon.dps then
            game[Mod("DAMAGE_PER_SECOND")] = item.weapon.dps
            def.speed = item.weapon.speed
        end
        def.game = game
        W.AddItem(def)
        count = count + 1
    end
end

---------------------------------------------------------------------------
-- Upgrade Scout, with Forever Leveling BiS chosen to score
---------------------------------------------------------------------------
UpgradeScoutDB = { engine = "leveling", welcomed = true, levelingOffered = true, pawnOffered = true, companionOffered = true }
local ns = {}
for line in io.lines("UpgradeScout/UpgradeScout.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
        local chunk = assert(loadfile("UpgradeScout/" .. line:gsub("\\", "/")))
        chunk("UpgradeScout", ns)
    end
end
-- (What an item gives through a spell is in the stats made above already.)
ns.GearData = { newest = 0, extra = {}, effects = {} }
W.AddOnLoaded("UpgradeScout")
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")
W.Run(1.5)
local Score = ns.Score
assert(Score.Engine() == "leveling", "Forever Leveling BiS scores")
local current = Score.Current()
local theirs = CLASS .. ":" .. SPEC .. ":" .. setup
realPrint(("%s %s %d: profile %s, shown as \"%s\"; weapon setup %s; %d items; its specs: %s"):format(CLASS, SPEC, LEVEL,
    current.name, current.title, tostring(setup), count, table.concat(API.GetSpecs(CLASS), " ")))

local same, differ, zero, why = 0, 0, 0, {}
local other = {}
local function Compare(id, item, offHand)
    local link = W.Link(id)
    local scored = Score.Item(link)
    if not scored then error("no reading of item " .. id) end
    local played = Score.Value(scored, current.name, LEVEL, offHand)
    -- (A weapon made for the off hand is scored as one held there, as its own tooltip scores it.)
    local direct = API.ScoreItem(link, offHand or item.slot == 22) or 0
    if math.abs(played - direct) > 1e-9 then
        error(("item %d: the score for the character played is not its own: %s, %s"):format(id, played, direct))
    end
    local summed = Score.Value(Score.Item(link), theirs, LEVEL, offHand)
    if played == 0 and summed == 0 then
        zero = zero + 1
    elseif math.abs(played - summed) <= 1e-6 * math.max(1, math.abs(played)) then
        same = same + 1
    else
        differ = differ + 1
        local reason = "another reason"
        if item.effects and item.effects[CLASS] and item.effects[CLASS][SPEC] then
            reason = "the item's effect, which only it knows"
        elseif item.stats and item.stats.armorbonus then
            reason = "bonus armor, which the game counts with the armor"
        elseif item.stats and item.stats.rhitPct then
            reason = "a chance to hit with ranged weapons only"
        end
        why[reason] = (why[reason] or 0) + 1
        if reason == "another reason" then
            other[#other + 1] = ("%d %s%s: its %.3f, the sum %.3f"):format(id, item.name, offHand and " (off hand)" or "", played, summed)
        end
    end
end
for id, item in pairs(flb.Items) do
    if IsGear(item) then
        Compare(id, item, false)
        if item.slot == 13 then Compare(id, item, true) end
    end
end
realPrint(("  the two ways agree on %d scores, differ on %d; %d score nothing either way"):format(same, differ, zero))
for reason, n in pairs(why) do realPrint(("    differ, %s: %d"):format(reason, n)) end
table.sort(other)
for i = 1, math.min(#other, 10) do realPrint("      " .. other[i]) end
local keys = {}
for key, n in pairs(unknown) do keys[#keys + 1] = key .. " x" .. n end
table.sort(keys)
realPrint("  stats of its data the game has no such name for: " .. table.concat(keys, ", "))

-- That it tells of a change, and the profile follows.
local told = 0
API.OnChanged(function() told = told + 1 end)
local specs = API.GetSpecs(CLASS)
mine.spec = specs[1] == SPEC and specs[2] or specs[1]
flb.Tooltip.Invalidate()
flb.BagMarks.Refresh()
W.Run(0.5)
realPrint(("  another main spec chosen: its listeners called %d time(s); Upgrade Scout's profile is now %s"):format(told, Score.Current().name))

-- Weapons it says are not for the character now, where this addon's own rule (what the class
-- can wield) has no objection: by kind of weapon.
mine.spec = SPEC
flb.Tooltip.Invalidate()
flb.BagMarks.Refresh()
W.Run(3)
local SUB = { [0] = "axe", [1] = "2H axe", [2] = "bow", [3] = "gun", [4] = "mace", [5] = "2H mace", [6] = "polearm", [7] = "sword",
    [8] = "2H sword", [10] = "staff", [13] = "fist", [15] = "dagger", [16] = "thrown", [18] = "crossbow", [19] = "wand" }
local refused, offered = {}, {}
for id, item in pairs(flb.Items) do
    if IsGear(item) and ns.Compare.Kind(EQUIP[item.slot]) == "HANDS" and (item.reqLevel or 0) <= LEVEL then
        local scored = Score.Item(W.Link(id))
        if ns.Roster.Wields({ class = CLASS, level = LEVEL }, scored.classID, scored.subClassID) then
            local kind = item.class == 2 and (SUB[item.subclass] or "weapon") or (item.slot == 14 and "shield" or "held")
            kind = kind .. (item.slot == 22 and " (off hand)" or item.slot == 21 and " (main hand)" or "")
            local into = ns.Leveling.Refuses(scored, nil) and refused or offered
            into[kind] = (into[kind] or 0) + 1
        end
    end
end
local function List(t)
    local out = {}
    for kind, n in pairs(t) do out[#out + 1] = kind .. " " .. n end
    table.sort(out)
    return table.concat(out, ", ")
end
realPrint("  for the hands, not refused: " .. List(offered))
realPrint("  for the hands, refused by it: " .. List(refused))

-- Its switch for its lines in a tooltip, as Leveling.Hushed sets it for the length of a call.
ForeverLevelingBiSDB.tooltip = nil
local during
ns.Leveling.Hushed(function() during = rawget(ForeverLevelingBiSDB, "tooltip") end)
realPrint(("  its switch for its tooltip lines during a hushed call: %s; afterwards: %s"):format(tostring(during),
    tostring(rawget(ForeverLevelingBiSDB, "tooltip"))))
if W.errors[1] then
    realPrint("ERRORS:\n" .. table.concat(W.errors, "\n"))
    os.exit(1)
end
