-- A check of UpgradeScout/GearQuest.lua against GearQuest's own code: the copy of GearQuest
-- Forever a player has installed. Nothing of it is in this repository; its files are loaded
-- from where it is installed, on top of the tests' stand-in for the client (tests/wow.lua).
-- Worth running again when GearQuest has a new version: it keeps no table for other addons,
-- and what Upgrade Scout asks of it is the addon's own.
--
-- A character of a class, spec and level is "played". The client's items are made from
-- GearQuest's own stat rows (its GearQuestForever_ItemStats), stat for stat, a chance as the
-- points of rating the game counts for it. Every item it lists for that character is then
-- scored three ways:
--   its own number for the item at that level (the score its tooltip's rank is made from);
--   Upgrade Scout's for the character being played, which should be that number;
--   Upgrade Scout's for another character of the same class, spec and level: the sum on its
--     weights, which is all there is for an item it has no row for.
-- It says how often the sum is its number and why not where it is not, prints a handful of
-- items with the three side by side, and tries what else is asked of it: a random
-- enchantment, a piece it lists at another level only, its say on weapons, a spec chosen
-- from here, its lines in a tooltip, its simulation of another character.
--
-- Run from the project folder, with Lua 5.1:
--   lua5.1 scripts/check-gearquest.lua <the AddOns folder> CLASS level [spec] [Alliance|Horde]
--   lua5.1 scripts/check-gearquest.lua "C:/Games/World of Warcraft/_forever_/Interface/AddOns" ROGUE 30 combat
local realPrint = print
local ROOT, CLASS, LEVEL, SPEC, SIDE = arg[1], arg[2], tonumber(arg[3]), arg[4], arg[5] or "Horde"
if not (ROOT and CLASS and LEVEL) then
    realPrint("usage: lua5.1 scripts/check-gearquest.lua <the AddOns folder with GearQuestForever in it> CLASS level [spec] [Alliance|Horde]")
    os.exit(2)
end
ROOT = ROOT:gsub("\\", "/"):gsub("/*$", "/")
local W = dofile("tests/wow.lua")

---------------------------------------------------------------------------
-- More of the client, as GearQuest asks for it
---------------------------------------------------------------------------
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
W.player = { name = "Tester", level = LEVEL, class = CLASS, money = 100000, dualWield = true }
function UnitClass() return CLASS, CLASS, CLASS_ID[CLASS] end
function UnitFactionGroup() return SIDE, SIDE end
function UnitGUID() return "Player-1-00000001" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function geterrorhandler() return function(err) error(err, 0) end end
strtrim = function(text) return (text:gsub("^%s*(.-)%s*$", "%1")) end
-- It makes a tooltip of its own to read an item's lines from, after the game's pattern for one.
local MakeFrame = CreateFrame
function CreateFrame(kind, name, parent, template)
    if template == "GameTooltipTemplate" then template = nil end
    return MakeFrame(kind, name, parent, template)
end
-- Its tooltips ask a tooltip which item it shows, the old way.
local shown = getmetatable(GameTooltip).__index
function shown:GetItem()
    if not self._link then return nil end
    return (self._link:match("%[(.-)%]")), self._link
end

-- GearQuest and the addons it loads when it needs them (a class's lists, its item stats),
-- file by file as their .toc name them.
local loaded, private = {}, {}
local function Load(folder)
    private[folder] = private[folder] or {}
    for line in io.lines(ROOT .. folder .. "/" .. folder .. ".toc") do
        line = line:gsub("\r", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local chunk = assert(loadfile(ROOT .. folder .. "/" .. line:gsub("\\", "/")))
            chunk(folder, private[folder])
        end
    end
    loaded[folder] = true
    return true
end
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    LoadAddOn = function(name) return Load(name) end,
}

---------------------------------------------------------------------------
-- GearQuest itself
---------------------------------------------------------------------------
Load("GearQuestForever")
-- (Its lines in a tooltip are looked at further down; its arrows are left out.)
GearQuestForeverDB = { settings = { hideUpgradeArrows = true, hideChat = true } }
GearQuestForeverCharDB = { specPick = SPEC and { [CLASS] = SPEC } or nil }
W.Fire("ADDON_LOADED", "GearQuestForever")
W.Fire("PLAYER_LOGIN")
W.Run(2)
local GQ = GearQuest
assert(type(GQ) == "table" and GQ == private.GearQuestForever, "the addon's own table is the global GearQuest")
SPEC = GQ:GetEffectiveSpec()
assert(GQ:GetEffectiveClass() == CLASS and type(SPEC) == "string", "it knows the character: " .. tostring(SPEC))
assert(GQ.Data:EnsureItemStats(), "its item stats are there to make the client's items from")
local D = GQ.Data

---------------------------------------------------------------------------
-- Its items, as the game would have them
---------------------------------------------------------------------------
local function Mod(name) return "ITEM_MOD_" .. name .. "_SHORT" end
-- Its key for a stat -> the game's name for it, and how many of the game's points are one of its.
local GAME = {
    str = { Mod("STRENGTH") }, agi = { Mod("AGILITY") }, sta = { Mod("STAMINA") }, int = { Mod("INTELLECT") }, spi = { Mod("SPIRIT") },
    ap = { Mod("ATTACK_POWER") }, rap = { Mod("RANGED_ATTACK_POWER") }, feralAp = { Mod("FERAL_ATTACK_POWER") },
    sp = { Mod("SPELL_DAMAGE_DONE") }, damageDone = { Mod("SPELL_DAMAGE_DONE") }, heal = { Mod("SPELL_HEALING_DONE") },
    spArcane = { Mod("ARCANE_DAMAGE_DONE") }, spFire = { Mod("FIRE_DAMAGE_DONE") }, spFrost = { Mod("FROST_DAMAGE_DONE") },
    spHoly = { Mod("HOLY_DAMAGE_DONE") }, spNature = { Mod("NATURE_DAMAGE_DONE") }, spShadow = { Mod("SHADOW_DAMAGE_DONE") },
    hit = { Mod("HIT_RATING"), 10 }, crit = { Mod("CRIT_RATING"), 14 }, haste = { Mod("HASTE_RATING"), 10 },
    expertise = { Mod("EXPERTISE_RATING"), 10 }, dodge = { Mod("DODGE_RATING"), 12 }, parry = { Mod("PARRY_RATING"), 15 },
    blockRating = { Mod("BLOCK_RATING"), 5 }, blockPct = { Mod("BLOCK_RATING"), 5 }, blockValue = { Mod("BLOCK_VALUE") },
    defense = { Mod("DEFENSE_SKILL_RATING") }, armor = { "RESISTANCE0_NAME" }, resist = { "RESISTANCE2_NAME" },
    resArcane = { "RESISTANCE6_NAME" }, resFire = { "RESISTANCE2_NAME" }, resFrost = { "RESISTANCE4_NAME" },
    resNature = { "RESISTANCE3_NAME" }, resShadow = { "RESISTANCE5_NAME" },
    hp5 = { Mod("HEALTH_REGENERATION") }, mp5 = { Mod("MANA_REGENERATION") }, spellPen = { Mod("SPELL_PENETRATION") },
    health = { Mod("HEALTH") }, mana = { Mod("MANA") },
}
-- (What it works out from the others, or keeps beside them, is no stat of the game's.)
local DERIVED = { sp_from_heal = true, spSchool = true, dps = true, spd = true, ilvl = true, kind = true }
local unknown = {}
local function GameStats(row, into)
    for key, amount in pairs(row) do
        local to = GAME[key]
        if to and type(amount) == "number" then
            into[to[1]] = (into[to[1]] or 0) + amount * (to[2] or 1)
        elseif type(amount) == "number" and not DERIVED[key] then
            unknown[key] = (unknown[key] or 0) + 1
        end
    end
    return into
end

local ARMOR = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }
local RELIC = { Libram = 7, Idol = 8, Totem = 9 }
local WEAPON = { Axe = 0, Bow = 2, Gun = 3, Mace = 4, Polearm = 6, Sword = 7, Staff = 10, Fist = 13, ["Fist Weapon"] = 13,
    Dagger = 15, Thrown = 16, Crossbow = 18, Wand = 19 }
local PLAIN = { Head = "INVTYPE_HEAD", Neck = "INVTYPE_NECK", Shoulder = "INVTYPE_SHOULDER", Back = "INVTYPE_CLOAK",
    Chest = "INVTYPE_CHEST", Wrist = "INVTYPE_WRIST", Hands = "INVTYPE_HAND", Waist = "INVTYPE_WAIST", Legs = "INVTYPE_LEGS",
    Feet = "INVTYPE_FEET", Finger = "INVTYPE_FINGER", Trinket = "INVTYPE_TRINKET" }
-- What it knows of an item beside its stats: its name, the words of its effect, its set.
local function Fact(id) return D:GetItemFact(id) or {} end

-- The rows it has for the character's class and spec, whatever the level: one item may have
-- many, and stand in the list of the main hand and of the off hand both.
local rows, slotsOf, items = {}, {}, 0
for _, slot in ipairs(D:GetSlotsForClass(CLASS)) do
    for _, row in ipairs(D:GetClassSlotEntryList(slot)) do
        rows[#rows + 1] = row
        slotsOf[row.itemId] = slotsOf[row.itemId] or {}
        slotsOf[row.itemId][slot] = row
    end
end
local statless = 0
local function Define(id)
    if W.items[id .. ":0"] or not slotsOf[id] then return W.items[id .. ":0"] end
    -- (A few of its rows are of items it has no stat row for: there is nothing to make those of.)
    if not D.itemStats[id] then
        statless = statless + 1
        return nil
    end
    local stats = D.itemStats[id]
    local fact = Fact(id)
    local where = slotsOf[id]
    local def = { id = id, name = fact.name or ("Item " .. id), level = math.max(fact.reqLevel or 1, 1), quality = fact.quality or 2,
        classID = 4, subClassID = ARMOR[stats.kind or ""] or 0 }
    local row = where.MainHand or where.SecondaryHand or where.Ranged
    if row and (stats.dps or 0) > 0 then
        def.classID = 2
        def.subClassID = WEAPON[D:WeaponTypeOf(row) or D:RangedTypeOf(row) or ""] or 7
        if where.Ranged then
            def.equipLoc = "INVTYPE_RANGED"
        elseif row.hand == "two" then
            def.equipLoc = "INVTYPE_2HWEAPON"
        elseif row.hand == "main" then
            def.equipLoc = "INVTYPE_WEAPONMAINHAND"
        elseif row.hand == "off" then
            def.equipLoc = "INVTYPE_WEAPONOFFHAND"
        else
            def.equipLoc = "INVTYPE_WEAPON"
        end
        def.speed = stats.spd
    elseif where.Ranged then
        def.equipLoc, def.subClassID = "INVTYPE_RELIC", RELIC[stats.kind or ""] or 0
    elseif where.SecondaryHand then
        -- A shield's own block is a line of its tooltip and no stat of the game's; its rows
        -- have none of it, so the amount here is made up.
        if (stats.armor or 0) > 0 then
            def.equipLoc, def.subClassID, def.block = "INVTYPE_SHIELD", 6, 40
        else
            def.equipLoc = "INVTYPE_HOLDABLE"
        end
    else
        for slot, equipLoc in pairs(PLAIN) do
            if where[slot] then def.equipLoc = equipLoc end
        end
    end
    def.game = GameStats(stats, {})
    if (stats.dps or 0) > 0 then def.game[Mod("DAMAGE_PER_SECOND")] = stats.dps end
    def.stats = stats
    items = items + 1
    return W.AddItem(def)
end
for id in pairs(slotsOf) do Define(id) end
-- A random enchantment of an item, as the client has it: the item's own stats and the
-- roll's. Its rows name a roll by the words after the item's name.
local rolled = 0
local function DefineRoll(id, roll)
    local base = Define(id)
    if not base or type(roll.n) ~= "string" then return nil end
    rolled = rolled + 1
    local def = {}
    for key, value in pairs(base) do def[key] = value end
    def.suffix, def.name = rolled, base.name .. " " .. roll.n
    def.game = GameStats(roll, GameStats(base.stats, {}))
    if (base.stats.dps or 0) > 0 then def.game[Mod("DAMAGE_PER_SECOND")] = base.stats.dps end
    W.AddItem(def)
    return W.Link(id, rolled)
end


---------------------------------------------------------------------------
-- Upgrade Scout, with GearQuest chosen to score
---------------------------------------------------------------------------
UpgradeScoutDB = { engine = "gearquest", welcomed = true, gearquestOffered = true, levelingOffered = true, pawnOffered = true,
    companionOffered = true }
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
W.Fire("PLAYER_ENTERING_WORLD")
W.Run(1.5)
local Score = ns.Score
assert(Score.Engine() == "gearquest", "GearQuest scores")
local current, specs = Score.Current()
local MINE, THEIRS = current.name, CLASS .. ":" .. SPEC
local titles = {}
for i = 1, #specs do titles[i] = specs[i].title end
realPrint(("%s %s %d (%s): profile %s, shown as \"%s\"; its specs: %s; %d items and %d rows of its lists for the class")
    :format(CLASS, SPEC, LEVEL, SIDE, MINE, current.title, table.concat(titles, ", "), items, #rows))

local function Clean(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "^"):gsub("%s+", " "))
end
-- What GearQuest itself writes into the tooltip of a link: its lines after the item's own.
-- (The stand-in does not clear a tooltip the way the game does: its marks are taken off here.)
local function ItsLines(link)
    GameTooltip.gqScoreLineAdded, GameTooltip.gqEnchantAdded, GameTooltip.gqGearQuestHeader, GameTooltip.gqScoreBusy = nil, nil, nil, nil
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    local ok, problem = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not ok then return "(its tooltip fails on the stand-in: " .. tostring(problem):sub(1, 80) .. ")" end
    local out = {}
    for _, line in ipairs(GameTooltip._lines) do
        local text = Clean(line.text)
        if text:find("Rank #", 1, true) or text:find("GearQuest", 1, true) or text:find("ranked", 1, true) or text:find("Upgrade Scout", 1, true) then
            out[#out + 1] = text .. (line.right and (" " .. Clean(line.right)) or "")
        end
    end
    return #out > 0 and table.concat(out, " / ") or "(nothing)"
end

-- Every item it has a row for at the character's level, the three ways.
local ids = {}
for id in pairs(slotsOf) do
    if W.items[id .. ":0"] then ids[#ids + 1] = id end
end
table.sort(ids)
local same, differ, why, other, here, there, nowhere, rolledRows = 0, 0, {}, {}, 0, 0, 0, {}
local best = {}
local scored, random = 0, 0
local started = os.clock()
for _, id in ipairs(ids) do
    local link = W.Link(id)
    local row = D:EntryForItemLink(link)
    local its = type(row) == "table" and row.pipelineScore or nil
    local item = Score.Item(link)
    if not item then error("no reading of item " .. id) end
    local played = Score.Value(item, MINE, LEVEL)
    local summed = Score.Value(Score.Item(link), THEIRS, LEVEL)
    scored = scored + 1
    if D.itemRolls[id] then
        -- An item that comes with a random enchantment alone: the game has no link of it
        -- without one, and its rows are its enchantments'. Two of those are tried below.
        random = random + 1
    elseif type(its) == "number" then
        here = here + 1
        if math.abs(played - its) > 1e-9 then
            error(("item %d: the score for the character played is not its own: %s, %s"):format(id, played, its))
        end
        if math.abs(summed - its) <= 0.0051 then
            same = same + 1
        else
            differ = differ + 1
            local stats, fact = D.itemStats[id] or {}, Fact(id)
            local reason = "another reason"
            if fact.proc then
                reason = "an effect, which its rows have a worth for"
            elseif fact.setPiece then
                reason = "a piece of a set, which its rows count the set's worth into"
            elseif stats.apVs then
                reason = "attack power against one kind of creature"
            elseif stats.spellPen then
                reason = "spell penetration, which the weights it gives out have nothing for"
            elseif RELIC[stats.kind or ""] then
                reason = "a relic, which it ranks by other things than stats"
            elseif W.items[id .. ":0"].classID == 4 and ARMOR[stats.kind or ""] then
                reason = "a kind of armor its rows count for another share than the table it gives out says (" .. stats.kind .. ")"
            end
            why[reason] = (why[reason] or 0) + 1
            if reason == "another reason" then
                other[#other + 1] = ("%d %s: its %.2f, the sum %.2f"):format(id, W.items[id .. ":0"].name, its, summed)
            end
        end
        local slot = D:NormalizeSlotName(row.slot)
        if not best[slot] or its > best[slot].its then best[slot] = { id = id, its = its, played = played, summed = summed } end
    else
        -- No row at the level: the row of another level, as it takes one for a worn piece.
        -- (A weapon for one hand by the list of the main hand first, as Upgrade Scout asks.)
        local where = slotsOf[id]
        local stored
        for _, slot in ipairs({ "MainHand", "SecondaryHand", (next(where)) }) do
            if stored == nil and where[slot] then stored = D:EquippedPipelineScore(id, slot) end
        end
        if type(stored) == "number" then
            there = there + 1
            if math.abs(played - stored) > 1e-9 then
                error(("item %d, listed at another level: the score for the character played is not that row's: %s, %s"):format(id, played, stored))
            end
        else
            nowhere = nowhere + 1
            if math.abs(played - summed) > 1e-9 then error("item " .. id .. ": with no row to be had, the two ways differ") end
        end
    end
end
local spent = os.clock() - started
realPrint(("  items with a row at level %d: %d. Upgrade Scout's score for the character played is that row's for every one."):format(LEVEL, here))
realPrint(("  the sum on its weights (all there is for an item without a row) is the row's score for %d of them, and is not for %d:"):format(same, differ))
for reason, n in pairs(why) do realPrint(("    %d: %s"):format(n, reason)) end
table.sort(other)
for i = 1, math.min(#other, 8) do realPrint("      " .. other[i]) end
realPrint(("  items it lists at another level only: %d, scored by the row they have there; with no row for the spec at all: %d, scored by the sum")
    :format(there, nowhere))
realPrint(("  (and %d items that come with a random enchantment alone, which have no link without one; %d it has no stat row for were not made)")
    :format(random, statless))
realPrint(("  %d items scored both ways in %.1f s: %.2f ms an item, nearly all of it GearQuest finding its rows"):format(scored, spent, spent / scored * 1000))

-- A handful, side by side: the best it has for a slot.
realPrint("  the best of a slot: its row | Upgrade Scout for the character played | the sum on its weights | what it writes into the tooltip")
for _, slot in ipairs({ "Head", "Chest", "Legs", "Finger", "Trinket", "MainHand", "SecondaryHand", "Ranged" }) do
    local top = best[slot]
    if top then
        realPrint(("    %-13s %-30s %8.2f | %8.2f | %8.2f | %s"):format(slot, W.items[top.id .. ":0"].name:sub(1, 30), top.its, top.played, top.summed,
            ItsLines(W.Link(top.id))))
    end
end

-- A gain, against a worn piece: the two chests it ranks first and tenth.
local chests, listed = {}, {}
for _, row in ipairs(D:GetClassSlotEntryList("Chest", true)) do
    if LEVEL >= row.minLevel and LEVEL <= row.maxLevel and type(row.pipelineScore) == "number" and not row.suffix
        and W.items[row.itemId .. ":0"] and not listed[row.itemId] then
        chests[#chests + 1], listed[row.itemId] = row, true
    end
end
table.sort(chests, function(a, b) return a.pipelineScore > b.pipelineScore end)
if #chests >= 10 then
    local top, worn = chests[1], chests[10]
    W.equipped[5] = W.Link(worn.itemId)
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
    W.Run(1)
    local ctx = Score.Context(MINE)
    local topItem = Score.Item(W.Link(top.itemId))
    local gain = ns.Compare.Gain({ link = topItem.link, itemID = top.itemId, invType = topItem.invType, value = Score.Value(topItem, MINE, LEVEL) }, ctx, "CHEST")
    realPrint(("  wearing its tenth chest (%s, %.2f), its first (%s, %.2f): Upgrade Scout says %+.1f%% (%+.2f points); GearQuest writes: %s")
        :format(W.items[worn.itemId .. ":0"].name, worn.pipelineScore, W.items[top.itemId .. ":0"].name, top.pipelineScore,
            (gain.percent or 0) * 100, gain.delta, ItsLines(W.Link(top.itemId))))
    gain = ns.Compare.Gain({ link = W.Link(worn.itemId), itemID = chests[#chests].itemId, invType = "INVTYPE_CHEST",
        value = Score.Value(Score.Item(W.Link(chests[#chests].itemId)), MINE, LEVEL) }, ctx, "CHEST")
    realPrint(("  and its last (%s, %.2f): Upgrade Scout says %+.1f%%; GearQuest writes: %s"):format(W.items[chests[#chests].itemId .. ":0"].name,
        chests[#chests].pipelineScore, (gain.percent or 0) * 100, ItsLines(W.Link(chests[#chests].itemId))))
    W.equipped[5] = nil
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
    W.Run(1)
end

-- An item it knows nothing of: the sum, and its own word in the tooltip.
W.AddItem({ id = 999001, name = "Chest of Nobody's List", equipLoc = "INVTYPE_CHEST", subClassID = 2, level = math.max(1, LEVEL - 1),
    game = { [Mod("AGILITY")] = 10, [Mod("STAMINA")] = 10, [Mod("STRENGTH")] = 10, [Mod("INTELLECT")] = 10, [Mod("CRIT_RATING")] = 14 } })
local nobody = Score.Item(W.Link(999001))
realPrint(("  an item it lists nowhere (10 of each of four stats and 1%% to crit): Upgrade Scout %.2f, the sum %.2f; GearQuest writes: %s")
    :format(Score.Value(nobody, MINE, LEVEL), Score.Value(nobody, THEIRS, LEVEL), ItsLines(W.Link(999001))))
realPrint("    does it write a score for it itself: " .. tostring(Score.Writes(W.Link(999001))) .. "; for the best chest: "
    .. tostring(best.Chest and Score.Writes(W.Link(best.Chest.id))))
-- What its own way of scoring a link it has no row for makes of the same item: the one it
-- uses for a worn piece it lists nowhere. That goes by another table of weights than its
-- lists are made with, and is not what Upgrade Scout asks.
realPrint(("    its own score of that link, as for a worn piece it lists nowhere (Compare:ScoreItemLinkStats): %.2f")
    :format(GQ.Compare:ScoreItemLinkStats(W.Link(999001), "Chest") or 0))

-- A random enchantment: its row is the best roll's. The best roll and a lesser one.
local tried = 0
for _, row in ipairs(rows) do
    if tried < 2 and row.suffix and LEVEL >= row.minLevel and LEVEL <= row.maxLevel and type(row.pipelineScore) == "number"
        and D.itemRolls[row.itemId] then
        for _, roll in ipairs(D.itemRolls[row.itemId]) do
            if roll.n == row.suffix and not rolledRows[row.itemId .. roll.n] then
                rolledRows[row.itemId .. roll.n] = true
                tried = tried + 1
                local link = DefineRoll(row.itemId, roll)
                local found = D:EntryForItemLink(link)
                local lesser = {}
                for key, value in pairs(roll) do lesser[key] = type(value) == "number" and key ~= "c" and key ~= "id" and math.max(value - 1, 0) or value end
                lesser.n = roll.n
                local base = W.items[row.itemId .. ":0"]
                local kept = base.name
                -- (The lesser roll goes by the same name, as in the game.)
                local lesserLink = DefineRoll(row.itemId, lesser)
                realPrint(("  a random enchantment, %s %s (%s): its row %s%s; Upgrade Scout for the best roll %.2f, for a roll one less of each stat %.2f")
                    :format(kept, roll.n, tostring(roll.r), tostring(row.pipelineScore), found and "" or " (not found by the link's name)",
                        Score.Value(Score.Item(link), MINE, LEVEL), Score.Value(Score.Item(lesserLink), MINE, LEVEL)))
            end
        end
    end
end

-- Its say on weapons, and the spec's weights as it gives them.
local one, two = ns.GearQuest.ShowsWeapons(MINE)
realPrint(("  the spec in use is offered one-handed weapons: %s, two-handed ones: %s; daggers alone: %s"):format(tostring(one), tostring(two),
    tostring(D:AssassinationDaggerOnly())))
local keys = {}
for key, n in pairs(unknown) do keys[#keys + 1] = key .. " x" .. n end
table.sort(keys)
realPrint("  stats of its rows the game has no such name for: " .. table.concat(keys, ", "))

-- Another spec chosen in Upgrade Scout's field: picked in GearQuest by its own function.
local told = 0
ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
local another
for i = 1, #specs do
    if specs[i].name ~= MINE then another = another or specs[i] end
end
if another then
    Score.Choose(ns.Roster.Me(), another.name)
    W.Run(1)
    realPrint(("  %s chosen here: GearQuest's spec in use is now %s, Upgrade Scout's profile %s; told of a change of scores %d time(s)")
        :format(another.title, tostring(GQ:GetEffectiveSpec()), Score.Current().name, told))
    Score.Choose(ns.Roster.Me(), MINE)
    W.Run(1)
end

-- Its lines in a tooltip filled in for another character, and its simulation.
local quiet
Score.Hushed(function(tooltip, link)
    GameTooltip.gqScoreLineAdded, GameTooltip.gqEnchantAdded, GameTooltip.gqGearQuestHeader = nil, nil, nil
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetHyperlink(link)
    quiet = true
    for _, line in ipairs(tooltip._lines) do
        if Clean(line.text):find("GearQuest", 1, true) or Clean(line.text):find("Rank #", 1, true) then quiet = false end
    end
end, GameTooltip, W.Link(best.Chest and best.Chest.id or 999001))
realPrint("  a tooltip filled in for another character has none of its lines: " .. tostring(quiet) .. "; its mark is taken off again: "
    .. tostring(rawget(GameTooltip, "gqSkipScoreHook") == nil))
told = 0
GQ.Preview:SetEnabled(true)
W.Run(3)
local engine = Score.Engine()
W.Run(1)
realPrint(("  its simulation switched on: it can be asked: %s, who scores: %s, told %d time(s)"):format(tostring(ns.GearQuest.Usable()),
    tostring(engine or "Upgrade Scout"), told))
GQ.Preview:SetEnabled(false)
W.Run(3)
engine = Score.Engine()
W.Run(1)
realPrint(("  switched off: who scores: %s, on %s, told %d time(s)"):format(tostring(engine), tostring(Score.Current() and Score.Current().name), told))
if W.errors[1] then
    realPrint("ERRORS:\n" .. table.concat(W.errors, "\n"))
    os.exit(1)
end
