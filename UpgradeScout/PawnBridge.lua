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

-- The scales Pawn shows for this character: { { name = internal name, title = display name }, ... }
function P.Scales()
    local out = {}
    local all = PawnGetAllScalesEx()
    if type(all) ~= "table" then return out end
    for i = 1, #all do
        local scale = all[i]
        if scale.IsVisible then
            out[#out + 1] = { name = scale.Name, title = scale.LocalizedName or scale.Name }
        end
    end
    return out
end

-- The scale to score with: the saved choice if Pawn still shows it, otherwise the first one.
function P.CurrentScale()
    local scales = P.Scales()
    local saved = ns.db.scale
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

-- True when Pawn found lines in the tooltip that it cannot turn into a number
-- (procs, on-use effects and the like).
function P.HasUnscoredEffects(item)
    return type(item.UnknownLines) == "table" and next(item.UnknownLines) ~= nil
end

-- False only when Pawn knows the player's class can never use the item.
function P.ClassCanUse(item)
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

-- What the player wears, scored on the given scale, plus the facts the comparison needs.
-- This is the "context" that Compare.Place takes.
function P.Context(scaleName)
    local equipped = {}
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
    return {
        scale = scaleName,
        level = UnitLevel("player"),
        equipped = equipped,
        dualWield = CanDualWield() and true or false,
        show1H = ShowsWeaponSet(scaleName, 1),
        show2H = ShowsWeaponSet(scaleName, 2),
    }
end
