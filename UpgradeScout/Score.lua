local _, ns = ...

-- What a piece of gear is worth to a character.
--
-- The score of an item is a plain sum: each stat the item adds, as the game counts it
-- (Stats.lua), times the weight the character's profile gives that stat. A profile is a set
-- of weights for one way of playing a class, a talent tree for the most part; the weights
-- are in Weights.lua, which also says where they come from. The player chooses a profile and
-- nothing else: there are no weights to edit.
--
-- Throughout this file `who` is the character the question is about: a card from Roster for
-- one that is not being played, nil for the one that is.
local Score = {}
ns.Score = Score

local WEAPON_CLASS = Enum.ItemClass.Weapon
-- A weapon's damage per second is a stat like the others to the game, but what it is worth
-- depends on the hand: a profile has a weight for a weapon in the main hand (or both hands),
-- one for the off hand and one for a ranged weapon.
local DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
-- The name a profile is shown by, in the player's language: its talent tree as the game
-- names it, or its role for one that stands for more than one tree ("Healer"); a druid's
-- shape after the tree where it has two ways of playing it ("Feral Combat (Cat)"). A
-- profile whose weights are an estimate and not the outcome of a simulation says so.
function Score.Title(id)
    local data = ns.Weights
    local profile = data.profiles[id]
    if not profile then return id end
    local titles = data.titles[GetLocale()] or data.titles.enUS
    local title = titles[id] or data.titles.enUS[id]
    if not title and profile.role then title = ns.L["ROLE_" .. profile.role] end
    title = title or id
    if profile.form then title = title .. " (" .. (ns.L["FORM_" .. profile.form] or profile.form) .. ")" end
    if profile.approx then title = title .. " " .. data.APPROX_MARK end
    return title
end

-- The profiles to choose from for a character, those of its class:
-- { { name = the profile's id, title = the name it is shown by }, ... }
function Score.Profiles(who)
    local owner = who or ns.Roster.Me()
    local ids = owner and ns.Weights.classes[owner.class or ""] or nil
    local out = {}
    if ids then
        for i = 1, #ids do out[i] = { name = ids[i], title = Score.Title(ids[i]) } end
    end
    return out
end

-- The profile to score with for a character: the one chosen for it, otherwise the one its
-- class starts with. (A card written by version 1 has no profile on it, and gets the
-- class's own.)
function Score.Current(who)
    local list = Score.Profiles(who)
    local owner = who or ns.Roster.Me()
    local chosen = owner and owner.profile
    local start = owner and ns.Weights.start[owner.class or ""]
    local first
    for i = 1, #list do
        if list[i].name == chosen then return list[i], list end
        if list[i].name == start then first = list[i] end
    end
    return first or list[1], list
end

-- True when the profile's weights are an estimate (see Weights.lua).
function Score.IsApprox(id)
    local profile = ns.Weights.profiles[id]
    return profile ~= nil and profile.approx == true
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- What there is to score about an item link: { link, itemID, invType, classID, subClassID,
-- stats = { [the game's name for a stat] = amount } }. The stats are those of the item as
-- it would be for sale, without an enchantment, so that an enchanted piece that is worn is
-- not unfairly hard to beat. nil when the game has no answer yet.
function Score.Item(link)
    local itemID, _, _, invType, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil end
    local stats = ns.Stats.Read(ns.Stats.Bare(link))
    if not stats then return nil end
    -- What the item gives through a spell it keeps on its wearer, which its own stats do not
    -- list (see GearData.lua).
    local extra = ns.GearData.extra[itemID]
    if extra then
        for name, amount in pairs(extra) do stats[name] = (stats[name] or 0) + amount end
    end
    return { link = link, itemID = itemID, invType = invType, classID = classID, subClassID = subClassID, stats = stats }
end

-- How much of its level 60 worth a rating has for a character of this level (1 at 60, and
-- for no level given). A chance to hit or crit adds a share of the damage a character does,
-- and below 60 that damage is smaller, while a point of Strength or of weapon damage adds
-- about as much as ever. Simulations of characters while they level found the share's worth
-- at a few levels (Weights.lua); between those it is drawn as a straight line, and below the
-- lowest it stays at that one's.
function Score.LevelFactor(level)
    local points = ns.Weights.leveling and ns.Weights.leveling.points
    if not level or not points or #points == 0 then return 1 end
    if level <= points[1][1] then return points[1][2] end
    for i = 2, #points do
        local low, high = points[i - 1], points[i]
        if level <= high[1] then
            return low[2] + (high[2] - low[2]) * (level - low[1]) / (high[1] - low[1])
        end
    end
    return points[#points][2]
end

-- The weight a profile gives a point of the stat `name` for a character of the level, on
-- this item (nil for a set of stats that is not one).
local function Weight(profile, name, level, item)
    local weight
    if name == DPS then
        if not item or item.classID ~= WEAPON_CLASS then return 0 end
        if RANGED[item.invType] then
            weight = profile.ranged
        elseif item.invType == "INVTYPE_WEAPONOFFHAND" then
            weight = profile.oh
        else
            weight = profile.mh
        end
        return weight or 0
    end
    weight = profile.weights[name] or 0
    local leveling = ns.Weights.leveling
    if weight ~= 0 and leveling and leveling.stats[name] then weight = weight * Score.LevelFactor(level) end
    return weight
end

-- An item's score on a profile, for a character of the level. 0 for a profile there is not.
function Score.Value(item, id, level)
    local profile = ns.Weights.profiles[id]
    if not profile then return 0 end
    local total = 0
    for name, amount in pairs(item.stats) do
        total = total + amount * Weight(profile, name, level, item)
    end
    return total
end

-- The same sum, stat by stat, for /upscout stats: { { name, amount, weight, points }, ... }
-- with the heaviest first, and the total.
function Score.Parts(item, id, level)
    local profile = ns.Weights.profiles[id]
    local parts, total = {}, 0
    for name, amount in pairs(item.stats) do
        local weight = profile and Weight(profile, name, level, item) or 0
        parts[#parts + 1] = { name = name, amount = amount, weight = weight, points = amount * weight }
        total = total + amount * weight
    end
    table.sort(parts, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return parts, total
end

-- The score of a set of stats that is not an item: what an elixir adds, say (SupplyData.lua
-- has them under the game's names). The same sum as for an item, so the number is in the
-- points gear is scored in. nil for a profile there is not.
function Score.StatsValue(stats, id, level)
    local profile = ns.Weights.profiles[id]
    if not profile then return nil end
    local total = 0
    for name, amount in pairs(stats) do
        total = total + amount * Weight(profile, name, level)
    end
    return total
end

-- True when the item does something a sum of stats does not count: a use, a chance on hit,
-- an aura that is not a plain stat. The game's tables say so for the items they have
-- (GearData.lua). An item newer than the tables is asked of its tooltip, where the game
-- marks the lines that come from a spell of the item, in whatever language.
local LINE = Enum.TooltipDataLineType
local SPELL_LINES = {
    [LINE.ItemSpellTriggerOnUse or -1] = true,
    [LINE.ItemSpellTriggerOnEquip or -2] = true,
    [LINE.ItemSpellTriggerOnProc or -3] = true,
}
function Score.HasUnscoredEffects(item)
    local data = ns.GearData
    if item.itemID <= data.newest then return data.effects[item.itemID] == true end
    local tip = C_TooltipInfo.GetHyperlink(item.link)
    local lines = tip and tip.lines
    if type(lines) ~= "table" then return false end
    for i = 2, #lines do
        if SPELL_LINES[lines[i].type] then return true end
    end
    return false
end

-- False when the character's class can never wear or wield the item (plate on a mage, a
-- wand on a warrior), or not yet at its level (mail and plate come at 40). Whether the
-- character has learned the kind of weapon is another question, answered where the item's
-- tooltip is read.
function Score.ClassCanUse(item, who)
    local owner = who or ns.Roster.Me()
    if not owner then return true end
    return ns.Roster.Wields({ class = owner.class, level = owner.level }, item.classID, item.subClassID)
end

---------------------------------------------------------------------------
-- What a character wears
---------------------------------------------------------------------------
-- An item's number and the way it is worn ("INVTYPE_CHEST").
local function ItemSlot(link)
    local itemID, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    return itemID, equipLoc
end

-- What a character wears, scored on the given profile, plus the facts the comparison needs.
-- This is the "context" that Compare.Place takes. On top of what Compare reads it says whom
-- it is about: who (see the top of this file), class, level.
-- For a character that is not being played the gear is what its card remembers. The client
-- may not have those items at hand: they are asked for and named in `pending` (item id ->
-- true), and until they come their slots score 0. The scanner makes the context again when
-- they do. `unread` counts the items the client has and still gave no stats for; the scanner
-- asks again a few times for those.
function Score.Context(id, who)
    local equipped = {}
    if who then
        local level = who.level or 1
        local pending, unread
        for slot, link in pairs(type(who.gear) == "table" and who.gear or {}) do
            -- (A card comes out of a saved file: what is not a slot and a link is passed over.)
            local itemID, equipLoc
            if type(slot) == "number" and type(link) == "string" then
                itemID, equipLoc = ItemSlot(link)
            end
            if itemID then
                local item = Score.Item(link)
                if not item and C_Item.IsItemDataCachedByID(itemID) then
                    unread = (unread or 0) + 1
                elseif not item then
                    pending = pending or {}
                    pending[itemID] = true
                    C_Item.RequestLoadItemDataByID(itemID)
                end
                equipped[slot] = {
                    link = link,
                    itemID = itemID,
                    invType = equipLoc,
                    value = item and Score.Value(item, id, level) or 0,
                }
            end
        end
        return {
            profile = id,
            who = who,
            class = who.class,
            level = level,
            equipped = equipped,
            pending = pending,
            unread = unread,
            dualWield = who.dualWield and true or false,
        }
    end

    local level = UnitLevel("player")
    for slot = 1, ns.Roster.LAST_SLOT do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local item = Score.Item(link)
            local itemID, equipLoc = ItemSlot(link)
            equipped[slot] = {
                link = link,
                itemID = itemID,
                invType = equipLoc,
                value = item and Score.Value(item, id, level) or 0,
            }
        end
    end
    local _, class = UnitClass("player")
    return {
        profile = id,
        class = class,
        level = level,
        equipped = equipped,
        dualWield = CanDualWield() and true or false,
    }
end
