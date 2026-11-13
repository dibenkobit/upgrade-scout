local _, ns = ...
local L = ns.L

-- Everything this addon asks of Pawn goes through this file. Pawn is a hard dependency
-- (see the .toc), so its globals exist by the time this file runs; Problem() still checks
-- them by name so that a future Pawn that renames something fails with a clear message
-- instead of a Lua error.
local P = {}
ns.Pawn = P

local REQUIRED = {
    "PawnIsReady",
    "PawnGetItemData",
    "PawnGetSingleValueFromItem",
    "PawnGetAllScalesEx",
    "PawnGetItemDataForInventorySlot",
}

-- Returns nil when Pawn can be used, otherwise a message for the player.
function P.Problem()
    for i = 1, #REQUIRED do
        if type(_G[REQUIRED[i]]) ~= "function" then
            return L.ERR_PAWN_API:format(REQUIRED[i])
        end
    end
    if not PawnIsReady() then
        return L.ERR_PAWN_NOT_READY
    end
    return nil
end

-- Throughout this file `who` is the character the question is about: a card from Roster for
-- one that is not being played, nil for the one that is (the game and Pawn are then asked
-- about "the player" directly).

-- The scales to choose from for a character: { { name = internal name, title = display name }, ... }
-- For the character being played, the scales Pawn shows. For another one Pawn's own notes are
-- read: it keeps, for the whole account, which scales each character has switched on, and it
-- carries the scales of every class. A character Pawn has no notes about gets the scales of
-- its class, and failing that every scale there is.
function P.Scales(who)
    local out = {}
    local all = PawnGetAllScalesEx()
    if type(all) ~= "table" then return out end
    if not who then
        for i = 1, #all do
            local scale = all[i]
            if scale.IsVisible then
                out[#out + 1] = { name = scale.Name, title = scale.LocalizedName or scale.Name }
            end
        end
        return out
    end

    local records = type(PawnCommon) == "table" and type(PawnCommon.Scales) == "table" and PawnCommon.Scales or {}
    local classID = ns.Roster.ClassID(who)
    local ofClass = {}
    for i = 1, #all do
        local scale = all[i]
        local record = records[scale.Name]
        if type(record) == "table" then
            local entry = { name = scale.Name, title = scale.LocalizedName or scale.Name }
            local notes = type(record.PerCharacterOptions) == "table" and record.PerCharacterOptions[who.key] or nil
            if type(notes) == "table" and notes.Visible then out[#out + 1] = entry end
            if classID ~= nil and record.ClassID == classID then ofClass[#ofClass + 1] = entry end
        end
    end
    if #out > 0 then return out end
    if #ofClass > 0 then return ofClass end
    for i = 1, #all do
        out[i] = { name = all[i].Name, title = all[i].LocalizedName or all[i].Name }
    end
    return out
end

-- The scale to score with for a character: the one chosen for it if it is still among its
-- scales, otherwise the first of them.
function P.CurrentScale(who)
    local scales = P.Scales(who)
    local owner = who or ns.Roster.Me()
    local saved = owner and owner.scale
    for i = 1, #scales do
        if scales[i].name == saved then return scales[i], scales end
    end
    return scales[1], scales
end

-- Pawn's record for an item link, or nil when the item has no stats Pawn can read
-- (or the client has not loaded the item yet).
function P.Item(link)
    return PawnGetItemData(link)
end

-- Pawn's score for an item on one scale. Like Pawn's own upgrade arrows, this uses the base
-- item without enchantments, so an enchanted item you wear is not unfairly hard to beat.
function P.Value(item, scaleName)
    local value, baseValue = PawnGetSingleValueFromItem(item, scaleName)
    return baseValue or value or 0
end

-- Pawn has no word for these two on every scale: the scales it ships with weigh them, a scale
-- made by hand cannot. Where the scale has no weight, health counts as the Stamina that
-- gives it (at the rate Pawn itself uses for "+100 health" on gear) and mana as Intellect.
local HEALTH_PER_STAMINA = 12.5
local MANA_PER_INTELLECT = 15

-- Pawn's score for a set of stats that is not an item: what an elixir adds, say.
--   stats  { Strength = 25, CritRating = 2, ... } under Pawn's names (see SupplyData.lua)
-- The same sum Pawn makes for an item, so the number is in the points gear is scored in.
-- nil when this Pawn cannot be asked.
function P.StatsValue(stats, scaleName)
    if type(PawnGetItemValue) ~= "function" or type(PawnGetAllStatValues) ~= "function" then return nil end
    local weights = PawnGetAllStatValues(scaleName)
    if type(weights) ~= "table" then return nil end

    local set = stats
    if (stats.Health and not weights.Health) or (stats.Mana and not weights.Mana) then
        set = {}
        for name, amount in pairs(stats) do set[name] = amount end
        if set.Health and not weights.Health then
            set.Stamina = (set.Stamina or 0) + set.Health / HEALTH_PER_STAMINA
            set.Health = nil
        end
        if set.Mana and not weights.Mana then
            set.Intellect = (set.Intellect or 0) + set.Mana / MANA_PER_INTELLECT
            set.Mana = nil
        end
    end
    -- The arguments Pawn itself passes for an item of a scale it does not show.
    local value = PawnGetItemValue(set, nil, nil, scaleName, false, false, true)
    return type(value) == "number" and value or nil
end

-- True when Pawn found lines in the tooltip that it cannot turn into a number
-- (procs, on-use effects and the like).
function P.HasUnscoredEffects(item)
    return type(item.UnknownLines) == "table" and next(item.UnknownLines) ~= nil
end

-- False only when Pawn knows the character's class can never use the item.
function P.ClassCanUse(item, who)
    if who then
        -- Pawn's list of the kinds of item a class never wears, which is what it sets
        -- CanEquip from for the character being played. Whether this character has learned
        -- the kind of weapon or armor is Roster's to say (Roster.Wields).
        local never = type(PawnNeverUsableStats) == "table" and PawnNeverUsableStats[ns.Roster.ClassID(who) or 0] or nil
        local stats = item.UnenchantedStats or item.Stats
        if type(never) == "table" and type(stats) == "table" then
            for i = 1, #never do
                if stats[never[i]] then return false end
            end
        end
        return true
    end
    if item.CanEquip == false then return false end
    if type(PawnIsArmorBestTypeForPlayer) == "function" and not PawnIsArmorBestTypeForPlayer(item) then
        return false
    end
    return true
end

local function ShowsWeaponSet(scaleName, set)
    if type(PawnGetShowUpgradesForWeapons) ~= "function" then return true end
    return PawnGetShowUpgradesForWeapons(scaleName, set) ~= false
end

-- What a character wears, scored on the given scale, plus the facts the comparison needs.
-- This is the "context" that Compare.Place takes. On top of what Compare reads it says whom
-- it is about: who (see the top of this file), class, level.
-- For a character that is not being played the gear is what its card remembers. The client
-- may not have those items at hand: they are asked for and named in `pending` (item id ->
-- true), and until they come their slots score 0. The scanner makes the context again when
-- they do. `unread` counts the items the client has and Pawn still gave nothing for: an item
-- without stats, or one whose tooltip Pawn read a moment too early (the scanner asks again
-- a few times for that).
function P.Context(scaleName, who)
    local equipped = {}
    if who then
        local pending, unread
        for slot, link in pairs(type(who.gear) == "table" and who.gear or {}) do
            local itemID, _, _, equipLoc
            if type(slot) == "number" and type(link) == "string" then
                itemID, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            end
            if itemID then
                local item = PawnGetItemData(link)
                if item then
                    -- Pawn has read it.
                elseif C_Item.IsItemDataCachedByID(itemID) then
                    unread = (unread or 0) + 1
                else
                    pending = pending or {}
                    pending[itemID] = true
                    C_Item.RequestLoadItemDataByID(itemID)
                end
                equipped[slot] = {
                    link = link,
                    itemID = itemID,
                    invType = equipLoc,
                    value = item and P.Value(item, scaleName) or 0,
                }
            end
        end
        return {
            scale = scaleName,
            who = who,
            class = who.class,
            level = who.level or 1,
            equipped = equipped,
            pending = pending,
            unread = unread,
            dualWield = who.dualWield and true or false,
            show1H = ShowsWeaponSet(scaleName, 1),
            show2H = ShowsWeaponSet(scaleName, 2),
        }
    end

    for slot = 1, 18 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local item = PawnGetItemDataForInventorySlot(slot, true)
            local itemID, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            equipped[slot] = {
                link = link,
                itemID = itemID,
                invType = equipLoc,
                value = item and P.Value(item, scaleName) or 0,
            }
        end
    end
    local _, class = UnitClass("player")
    return {
        scale = scaleName,
        class = class,
        level = UnitLevel("player"),
        equipped = equipped,
        dualWield = CanDualWield() and true or false,
        show1H = ShowsWeaponSet(scaleName, 1),
        show2H = ShowsWeaponSet(scaleName, 2),
    }
end
