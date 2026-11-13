local _, ns = ...
local L = ns.L

-- Decides which equipment slot an item would go into and how much better it is than what is
-- there now. No game calls in here except reading localized slot names: the caller passes in
-- the scored item and a snapshot of the player's gear (see PawnBridge.Context).
local C = {}
ns.Compare = C

-- Slot groups in the order they are listed. `slots` are inventory slot numbers.
C.GROUPS = {
    { id = "HEAD", slots = { 1 }, global = "HEADSLOT" },
    { id = "NECK", slots = { 2 }, global = "NECKSLOT" },
    { id = "SHOULDER", slots = { 3 }, global = "SHOULDERSLOT" },
    { id = "BACK", slots = { 15 }, global = "BACKSLOT" },
    { id = "CHEST", slots = { 5 }, global = "CHESTSLOT" },
    { id = "WRIST", slots = { 9 }, global = "WRISTSLOT" },
    { id = "HANDS", slots = { 10 }, global = "HANDSSLOT" },
    { id = "WAIST", slots = { 6 }, global = "WAISTSLOT" },
    { id = "LEGS", slots = { 7 }, global = "LEGSSLOT" },
    { id = "FEET", slots = { 8 }, global = "FEETSLOT" },
    { id = "FINGER", slots = { 11, 12 }, global = "FINGER0SLOT" },
    { id = "TRINKET", slots = { 13, 14 }, global = "TRINKET0SLOT" },
    { id = "MAINHAND", slots = { 16 }, global = "MAINHANDSLOT" },
    { id = "OFFHAND", slots = { 17 }, global = "SECONDARYHANDSLOT" },
    { id = "RANGED", slots = { 18 }, global = "RANGEDSLOT" },
}

local GROUP_BY_ID = {}
for i = 1, #C.GROUPS do
    GROUP_BY_ID[C.GROUPS[i].id] = C.GROUPS[i]
end

function C.GroupLabel(id)
    local group = GROUP_BY_ID[id]
    local text = group and _G[group.global]
    if type(text) == "string" and text ~= "" then return text end
    return L[id]
end

-- Item types that fill exactly one slot.
local SINGLE = {
    INVTYPE_HEAD = "HEAD",
    INVTYPE_NECK = "NECK",
    INVTYPE_SHOULDER = "SHOULDER",
    INVTYPE_CLOAK = "BACK",
    INVTYPE_CHEST = "CHEST",
    INVTYPE_ROBE = "CHEST",
    INVTYPE_WRIST = "WRIST",
    INVTYPE_HAND = "HANDS",
    INVTYPE_WAIST = "WAIST",
    INVTYPE_LEGS = "LEGS",
    INVTYPE_FEET = "FEET",
    INVTYPE_RANGED = "RANGED",
    INVTYPE_RANGEDRIGHT = "RANGED",
    INVTYPE_THROWN = "RANGED",
    INVTYPE_RELIC = "RANGED",
}

-- Item types the player wears two of.
local PAIRED = {
    INVTYPE_FINGER = "FINGER",
    INVTYPE_TRINKET = "TRINKET",
}

local WEAPON = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}

local MAIN_HAND, OFF_HAND = 16, 17

-- True for item types this addon knows how to place (shirts, tabards, bags and ammo are not).
function C.Handles(invType)
    return invType ~= nil and (SINGLE[invType] ~= nil or PAIRED[invType] ~= nil or WEAPON[invType] == true)
end

-- How a weapon, shield or held item is carried, in the words its tooltip uses: "One-Hand",
-- "Two-Hand", "Main Hand", "Off Hand". nil for everything else. The two hand slots list all
-- of these together, so the list names the kind on every row.
function C.HandLabel(invType)
    if not WEAPON[invType] then return nil end
    local text = _G[invType]
    if type(text) == "string" and text ~= "" then return text end
    return L[invType]
end

-- Pawn only calls an item an upgrade when it scores at least 0.5% higher; same rule here.
local MIN_GAIN = 1.005

local function Beats(value, base)
    if base <= 0 then return value > 0 end
    return value > base * MIN_GAIN
end

local function Placement(group, value, base, replaced, note)
    return {
        group = group,
        delta = value - base,
        base = base,
        percent = base > 0 and (value - base) / base or nil,
        replaced = replaced,   -- links of the items that come off, nil for an empty slot
        note = note,           -- "BOTH_HANDS" | "OFFHAND_EMPTY" | nil
    }
end

local function IsWorn(equipped, itemID)
    for _, worn in pairs(equipped) do
        if worn.itemID == itemID then return true end
    end
    return false
end

-- item: { invType, value, itemID, unique }
-- ctx:  { equipped = { [slot] = { link, itemID, invType, value } }, dualWield, show1H, show2H }
-- Returns a list of placements; empty when the item is not an upgrade anywhere.
-- A one-hand weapon can appear twice (main hand and off hand) for a dual wielder.
function C.Place(item, ctx)
    local out = {}
    local value = item.value
    local invType = item.invType
    if not value or value <= 0 or not invType then return out end

    local equipped = ctx.equipped
    -- A second copy of a unique item cannot be equipped next to the first.
    if item.unique and IsWorn(equipped, item.itemID) then return out end

    local single = SINGLE[invType]
    if single then
        local worn = equipped[GROUP_BY_ID[single].slots[1]]
        local base = worn and worn.value or 0
        if Beats(value, base) then
            out[1] = Placement(single, value, base, worn and { worn.link } or nil)
        end
        return out
    end

    local paired = PAIRED[invType]
    if paired then
        -- The new item takes the place of the weaker of the two (or of an empty slot).
        local slots = GROUP_BY_ID[paired].slots
        local first, second = equipped[slots[1]], equipped[slots[2]]
        local firstValue = first and first.value or 0
        local secondValue = second and second.value or 0
        local worn, base = first, firstValue
        if secondValue < firstValue then worn, base = second, secondValue end
        if Beats(value, base) then
            out[1] = Placement(paired, value, base, worn and { worn.link } or nil)
        end
        return out
    end

    if not WEAPON[invType] then return out end

    local main, off = equipped[MAIN_HAND], equipped[OFF_HAND]
    local mainValue = main and main.value or 0
    local offValue = off and off.value or 0
    local holdingTwoHander = main ~= nil and main.invType == "INVTYPE_2HWEAPON"

    if invType == "INVTYPE_2HWEAPON" then
        -- A two-hander replaces both hands, so it has to beat both together.
        if ctx.show2H ~= false then
            local base = mainValue + offValue
            if Beats(value, base) then
                local replaced = {}
                if main then replaced[#replaced + 1] = main.link end
                if off then replaced[#replaced + 1] = off.link end
                out[1] = Placement("MAINHAND", value, base, #replaced > 0 and replaced or nil, off and "BOTH_HANDS" or nil)
            end
        end
        return out
    end

    if ctx.show1H == false then return out end

    if invType == "INVTYPE_WEAPON" or invType == "INVTYPE_WEAPONMAINHAND" then
        -- Against a two-hander the comparison is honest only if the off hand is counted as empty.
        if Beats(value, mainValue) then
            out[#out + 1] = Placement("MAINHAND", value, mainValue, main and { main.link } or nil,
                holdingTwoHander and "OFFHAND_EMPTY" or nil)
        end
    end

    if invType ~= "INVTYPE_WEAPONMAINHAND" and not holdingTwoHander then
        local isWeapon = invType == "INVTYPE_WEAPON" or invType == "INVTYPE_WEAPONOFFHAND"
        if (not isWeapon or ctx.dualWield) and Beats(value, offValue) then
            out[#out + 1] = Placement("OFFHAND", value, offValue, off and { off.link } or nil)
        end
    end

    return out
end
