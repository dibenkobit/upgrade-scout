local _, ns = ...

-- What a piece of gear is worth to a character.
--
-- The score of an item is a plain sum: each stat the item adds, as the game counts it
-- (Stats.lua), times the weight the character's profile gives that stat. A profile is a set
-- of weights for one way of playing a class, a talent tree for the most part; the weights
-- are in Weights.lua, which also says where they come from. The player chooses a profile and
-- nothing else: there are no weights to edit.
--
-- A player who would sooner go by Pawn can say so in the welcome window (Welcome.lua). Then
-- Pawn scores (Pawn.lua), and the rest of the addon notices nothing: it asks this file the
-- same questions, and a "profile" is one of the character's Pawn scales. See Score.Engine.
--
-- Throughout this file `who` is the character the question is about: a card from Roster for
-- one that is not being played, nil for the one that is.
local Score = {}
ns.Score = Score

---------------------------------------------------------------------------
-- Who scores
---------------------------------------------------------------------------
-- nil: this addon, by its own weights. "pawn": Pawn, by the player's Pawn scales. Pawn does
-- only while it was chosen (ns.account.engine, for the whole account) and is there to be
-- asked: switched off or taken away, it leaves the addon scoring by itself, and the choice
-- stands for when it is back.
function Score.Engine()
    if ns.account.engine == "pawn" and ns.Pawn.Usable() then return "pawn" end
    return nil
end

-- The choice made in the welcome window: "pawn", or nil for the addon's own weights. Every
-- score there is was made by the other one, so everything that keeps scores hears
-- SCORING_CHANGED and makes them again. (The same is said when Pawn's scales change while
-- Pawn scores: see Pawn.lua.)
function Score.SetEngine(engine)
    local before = Score.Engine()
    ns.account.engine = engine == "pawn" and "pawn" or nil
    if Score.Engine() ~= before then ns.Fire("SCORING_CHANGED") end
    ns.Fire("SETTING_CHANGED", "engine")
end

-- Writes down the profile chosen for a character (its card): each of the two that score
-- remembers a choice of its own, so going over to Pawn and back loses neither.
function Score.Choose(card, id)
    if Score.Engine() then card.scale = id else card.profile = id end
end

local WEAPON_CLASS = Enum.ItemClass.Weapon
-- A weapon's damage per second is a stat like the others to the game, but what it is worth
-- depends on the hand: a profile has a weight for a weapon in the main hand (or both hands),
-- one for the off hand and one for a ranged weapon.
local DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- The lines of an item's tooltip as the game gives them, or nil while it has none to give.
local function TooltipLines(link)
    local tip = C_TooltipInfo.GetHyperlink(link)
    local lines = tip and tip.lines
    if type(lines) ~= "table" or #lines < 2 then return nil end
    return lines
end

-- A shield's block is a property of the shield, like its armor, and the game does not count
-- it among the stats GetItemStats gives. Its tooltip has a line for it written from the
-- game's own text (SHIELD_BLOCK_TEMPLATE, "%s Block"), which is found the same way in every
-- language.
local ARMOR_CLASS, SHIELD = Enum.ItemClass.Armor, 6
local BLOCK = "ITEM_MOD_BLOCK_VALUE_SHORT"
local blockPattern
local function ShieldBlock(link)
    if blockPattern == nil then
        local before, after = tostring(SHIELD_BLOCK_TEMPLATE or ""):match("^(.-)%%[sd](.*)$")
        blockPattern = before and ("^" .. before:gsub("%p", "%%%0") .. "(%d+)" .. after:gsub("%p", "%%%0") .. "$") or false
    end
    if not blockPattern then return nil end
    for _, line in ipairs(TooltipLines(link) or {}) do
        local amount = type(line.leftText) == "string" and line.leftText:match(blockPattern)
        if amount then return tonumber(amount) end
    end
    return nil
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
-- The name a profile is shown by, in the player's language: its talent tree as the game
-- names it, or its role for one that stands for more than one tree ("Healer"); a druid's
-- shape after the tree where it has two ways of playing it ("Feral Combat (Cat)"). A
-- profile whose weights are an estimate and not the outcome of a simulation says so.
local function OwnTitle(id)
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

-- The name a profile is shown by, whoever scores: with Pawn, the name Pawn shows the scale by.
function Score.Title(id)
    if Score.Engine() then return ns.Pawn.Title(id) end
    return OwnTitle(id)
end

-- The addon's own profiles for a character, those of its class, whoever scores:
-- { { name = the profile's id, title = the name it is shown by }, ... }
function Score.Trees(who)
    local owner = who or ns.Roster.Me()
    local ids = owner and ns.Weights.classes[owner.class or ""] or nil
    local out = {}
    if ids then
        for i = 1, #ids do out[i] = { name = ids[i], title = OwnTitle(ids[i]) } end
    end
    return out
end

-- The profiles to choose from for a character, in the same form: those the addon has for
-- its class or, with Pawn scoring, the Pawn scales the character has.
function Score.Profiles(who)
    if Score.Engine() then return ns.Pawn.Scales(who) end
    return Score.Trees(who)
end

-- The profile to score with for a character: the one chosen for it; otherwise the one for
-- the talent tree it had the most points in when it was last played (its card's `talents`,
-- see Roster.Update); otherwise the one its class starts with. Returns it, and the profiles
-- it was chosen from.
function Score.Current(who)
    if Score.Engine() then return ns.Pawn.Current(who) end
    local list = Score.Profiles(who)
    local owner = who or ns.Roster.Me()
    local chosen = owner and owner.profile
    local talents = owner and owner.talents
    local start = owner and ns.Weights.start[owner.class or ""]
    local byTalents, byClass
    for i = 1, #list do
        if list[i].name == chosen then return list[i], list end
        if list[i].name == talents then byTalents = list[i] end
        if list[i].name == start then byClass = list[i] end
    end
    return byTalents or byClass or list[1], list
end

-- The profile for a talent tree of a class: `name` is the tree as the game names it, `place`
-- its place among the class's trees from the left, `count` how many trees there are. A tree
-- is told by its name first, which is what the profiles are named by (Weights.titles). A
-- class with a profile for each of its trees can be told by the place as well. Where one
-- profile stands for more trees than one (a priest's Healer), a tree that none is named
-- after is one of its. nil when none of that tells.
function Score.ForTree(class, name, place, count)
    local data = ns.Weights
    local ids = data.classes[class or ""]
    if not ids then return nil end
    if name ~= nil then
        local titles, english = data.titles[GetLocale()] or data.titles.enUS, data.titles.enUS
        for i = 1, #ids do
            if titles[ids[i]] == name or english[ids[i]] == name then return ids[i] end
        end
    end
    if #ids == count then return ids[place] end
    local shared
    for i = 1, #ids do
        local profile = data.profiles[ids[i]]
        if profile and profile.role then
            if shared then return nil end
            shared = ids[i]
        end
    end
    return shared
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
-- With Pawn scoring, the same with Pawn's record of the item (`pawn`) in place of `stats`:
-- the functions below tell by it whose item they were given.
function Score.Item(link)
    if Score.Engine() then return ns.Pawn.Item(link) end
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
    if classID == ARMOR_CLASS and subClassID == SHIELD and not stats[BLOCK] then stats[BLOCK] = ShieldBlock(link) end
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
    if item.pawn ~= nil then return ns.Pawn.Value(item, id) end
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
    if item.pawn ~= nil then return ns.Pawn.Parts(item, id) end
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
    if Score.Engine() then return ns.Pawn.StatsValue(stats, id) end
    local profile = ns.Weights.profiles[id]
    if not profile then return nil end
    local total = 0
    for name, amount in pairs(stats) do
        total = total + amount * Weight(profile, name, level)
    end
    return total
end

-- True when the item does something a sum of stats does not count: a use, a chance on hit,
-- an aura that is not a plain stat. The item's tooltip says so: the game marks the lines that
-- come from a spell of the item, in whatever language, and writes its stats in lines of
-- their own. A line of what the item does while worn is left out when the score counts
-- what it adds (GearData.extra). Only without a tooltip to read are the game's tables asked
-- (GearData.effects): checked against a whole auction house, they were out of date for some
-- items, which the game no longer shows an effect for, or which they did not have at all.
local LINE = Enum.TooltipDataLineType
local USE, EQUIP, PROC = LINE.ItemSpellTriggerOnUse or -1, LINE.ItemSpellTriggerOnEquip or -2, LINE.ItemSpellTriggerOnProc or -3
function Score.HasUnscoredEffects(item)
    -- For Pawn, the lines of the tooltip it could not turn into a number.
    if item.pawn ~= nil then return ns.Pawn.HasUnscoredEffects(item) end
    local data = ns.GearData
    local lines = TooltipLines(item.link)
    if not lines then return item.itemID <= data.newest and data.effects[item.itemID] == true end
    local counted = data.extra[item.itemID] ~= nil
    for i = 2, #lines do
        local kind = lines[i].type
        if kind == USE or kind == PROC or (kind == EQUIP and not counted) then return true end
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
-- For a character that is not being played the gear is what its card remembers; for the one
-- being played, what it has on. Either way the client may not have the items at hand yet:
-- right after login the game knows what is worn but not what it adds (a link to it then has
-- an empty name). Those items are asked for and named in `pending` (item id -> true), and
-- until they come their slots score 0. The scanner makes the context again when they do.
-- `unread` counts the items the client has and still gave no stats for (or Pawn nothing at
-- all); the scanner asks again a few times for those.
-- With Pawn scoring the context also says what the scale wants no upgrades of: show1H and
-- show2H, false for the one-handed or the two-handed weapons it is not to be offered.
local function Finish(ctx)
    if Score.Engine() then
        ctx.show1H, ctx.show2H = ns.Pawn.ShowsWeapons(ctx.profile)
    end
    return ctx
end

function Score.Context(id, who)
    local equipped, pending, unread = {}, nil, nil
    local level = who and (who.level or 1) or UnitLevel("player")

    local function Wear(slot, link)
        local itemID, equipLoc = ItemSlot(link)
        if not itemID then return end
        local item = Score.Item(link)
        if not item and C_Item.IsItemDataCachedByID(itemID) then
            unread = (unread or 0) + 1
        elseif not item then
            pending = pending or {}
            pending[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        elseif item.pawn == false then
            unread = (unread or 0) + 1
        end
        equipped[slot] = {
            link = link,
            itemID = itemID,
            invType = equipLoc,
            value = item and Score.Value(item, id, level) or 0,
        }
    end

    if who then
        for slot, link in pairs(type(who.gear) == "table" and who.gear or {}) do
            -- (A card comes out of a saved file: what is not a slot and a link is passed over.)
            if type(slot) == "number" and type(link) == "string" then Wear(slot, link) end
        end
        return Finish({
            profile = id,
            who = who,
            class = who.class,
            level = level,
            equipped = equipped,
            pending = pending,
            unread = unread,
            dualWield = who.dualWield and true or false,
        })
    end

    for slot = 1, ns.Roster.LAST_SLOT do
        local link = GetInventoryItemLink("player", slot)
        if link then Wear(slot, link) end
    end
    local _, class = UnitClass("player")
    return Finish({
        profile = id,
        class = class,
        level = level,
        equipped = equipped,
        pending = pending,
        unread = unread,
        dualWield = CanDualWield() and true or false,
    })
end

-- The same gear scored on another profile: a context of its own, `ctx` left as it is. What
-- is worn is what `ctx` has on, the items bought for a set among it (see Plan.Wearing).
function Score.Rescore(ctx, id)
    local out = {}
    for key, value in pairs(ctx) do out[key] = value end
    out.profile = id
    out.equipped = {}
    for slot, worn in pairs(ctx.equipped) do
        local item = Score.Item(worn.link)
        out.equipped[slot] = {
            link = worn.link,
            itemID = worn.itemID,
            invType = worn.invType,
            value = item and Score.Value(item, id, ctx.level) or 0,
        }
    end
    return Finish(out)
end
