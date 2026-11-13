local _, ns = ...
local L = ns.L

-- Consumables for sale, as the Consumables tab lists them. The scanner finds the ones the
-- player can use (Scanner.StartSupplies); this file says which of them do the same thing,
-- what each is worth to this character, which of a kind is the best, and builds the rows.
--
-- Two consumables are of one kind when the game's text for what they do is the same but for
-- the numbers ("Restores 70 to 90 health." and "Restores 700 to 900 health."), in whatever
-- language the game runs in.
--
-- What a consumable is worth comes from two things the scanner attaches to it out of the
-- game's own tables (SupplyData.lua), where the tables have them:
--   stats     what its effect adds, for Pawn to score on the player's scale: the number is in
--             the same points as a piece of gear, so +25 Agility from an elixir and from a ring
--             are worth the same
--   restores  what it gives back (health, mana...): no score, but mana is of no use to a
--             character without it
-- A consumable is of no use when Pawn scores what it adds at nothing and it restores nothing
-- the character has. One the tables say nothing about is listed without a score.
-- Food with a bonus that is worth nothing to the character is still food: all such food under
-- a heading counts as one kind, so that a warrior is not shown the best meal for Intellect,
-- the best for Spirit and so on, each as the best of its kind.
--
-- Within a kind the best is the one with the highest score. Where there is no score, it is
-- the one that asks for the higher level; equal levels are settled by the bigger number in the
-- text (that is how bandages differ, which ask for a skill and not a level).
local P = {}
ns.Supplies = P

local CONSUMABLE = Enum.ItemClass.Consumable
local SubClassInfo = C_Item.GetItemSubClassInfo or GetItemSubClassInfo

-- The subcategories of Consumables in the order the tab lists them (potions, elixirs,
-- flasks, food and drink, bandages, scrolls, then what goes on gear and what engineers
-- make). A subcategory that is not named here comes after these, by its number.
local ORDER = { 1, 2, 3, 5, 7, 4, 15, 6, 0, 14, 8 }
local RANK = {}
for i = 1, #ORDER do RANK[ORDER[i]] = i end

local function Rank(sub)
    return RANK[sub] or (#ORDER + 1 + sub)
end

-- The game's own name of a subcategory ("Potions", "Food & Drink").
function P.SubLabel(sub)
    local text = SubClassInfo and SubClassInfo(CONSUMABLE, sub)
    if type(text) == "string" and text ~= "" then return text end
    return L.SUP_OTHER
end

-- What the game's language puts between thousands, if anything: "1,050", "1.050", "1 050".
local SEPARATORS = { ",", "." }
if type(LARGE_NUMBER_SEPERATOR) == "string" and LARGE_NUMBER_SEPERATOR ~= "" then
    table.insert(SEPARATORS, 1, LARGE_NUMBER_SEPERATOR)
end

-- Where the number whose first digits end at `last` really ends: a separator belongs to the
-- number when exactly three digits follow it.
local function NumberEnd(text, last)
    while true do
        local joined
        for i = 1, #SEPARATORS do
            local separator = SEPARATORS[i]
            local from = last + 1
            if text:sub(from, from + #separator - 1) == separator
                and text:find("^%d%d%d%f[%D]", from + #separator) then
                joined = from + #separator + 2
                break
            end
        end
        if not joined then return last end
        last = joined
    end
end

-- "Restores 700 to 900 health." -> "Restores # to # health.", 900
-- The first is the same for every consumable of a kind; the second tells two of them apart.
function P.Describe(text)
    local parts, biggest, at = {}, 0, 1
    while true do
        local first, last = text:find("%d+", at)
        if not first then break end
        last = NumberEnd(text, last)
        local value = tonumber((text:sub(first, last):gsub("%D", ""))) or 0
        if value > biggest then biggest = value end
        parts[#parts + 1] = text:sub(at, first - 1)
        parts[#parts + 1] = "#"
        at = last + 1
    end
    parts[#parts + 1] = text:sub(at)
    return table.concat(parts), biggest
end

-- The stronger of two consumables of one kind first; of two equally strong, the cheaper.
local function Stronger(a, b)
    local x, y = a.supply, b.supply
    if x.reqLevel ~= y.reqLevel then return x.reqLevel > y.reqLevel end
    if x.power ~= y.power then return x.power > y.power end
    if x.price ~= y.price then return x.price < y.price end
    return x.id < y.id
end

-- The same for a kind whose every member has a score: the higher score first.
local function Worthier(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return Stronger(a, b)
end

-- What the list makes of one consumable.
--   value  Pawn's score for what it adds, when that is more than nothing
--   use    true = of use to this character, false = of none, nil = the tables do not say
--   why    of no use because: "WEIGHT" the scale gives what it adds no weight,
--          "MANA" all it restores is mana and the character has none
--   plain  of use only for what it restores: what it adds besides is worth nothing
local function Judge(supply, opts)
    local stats, restores = supply.stats, supply.restores
    local score = nil
    if stats and opts.value then score = opts.value(stats) end
    if score and score > 0 then return score, true end
    if restores then
        if restores ~= "M" or opts.mana then return nil, true, nil, score ~= nil end
        if not stats then return nil, false, "MANA" end
    end
    if score then return nil, false, "WEIGHT" end
    return nil, nil
end

-- The key of the kind that is all the food with a bonus of no use (see Build): the last byte
-- there is, which no text begins with, so the key is nobody else's and sorts after any text.
local PLAIN = string.char(255)

-- Kinds come in this order within a subcategory:
--   1  what restores something (healing potions, food), health before mana
--   2  what Pawn scores, the highest score first
--   3  what the tables say nothing about, the highest level first
--   4  what is of no use to this character (listed only when everything is)
-- None of it depends on how much is for sale, so the list keeps its order from scan to scan.
local RESTORES = { H = 1, HM = 2, M = 3 }

local function Place(kind)
    local best = kind.entries[1]
    kind.best = best
    if best.useless then
        kind.class = 4
    elseif best.value then
        kind.class = 2
    elseif best.use then
        kind.class = 1
        kind.restores = RESTORES[best.supply.restores] or 4
    else
        kind.class = 3
    end
end

local function ByPlace(a, b)
    if a.class ~= b.class then return a.class < b.class end
    if a.class == 2 and a.best.value ~= b.best.value then return a.best.value > b.best.value end
    if a.class == 1 and a.restores ~= b.restores then return a.restores < b.restores end
    local x, y = a.best.supply, b.best.supply
    if x.reqLevel ~= y.reqLevel then return x.reqLevel > y.reqLevel end
    if x.power ~= y.power then return x.power > y.power end
    return a.key < b.key
end

-- supplies: id -> consumable (see Scanner.StartSupplies)
-- opts:     { money = copper the player has, affordableOnly = bool,
--             value = function(stats) -> Pawn's score for them; nil when Pawn cannot be asked,
--             mana = the character has mana,
--             bestOnly = bool: one row per kind, its best, and nothing that is of no use }
-- Returns rows, summary
--   rows:    { { kind = "header", group = "SUB1", title = "Potions", shown = n, total = n },
--              { kind = "supply", entry = { supply = {...}, affordable = bool, best = bool,
--                                           value = score or nil, useless = bool, why = ... } }, ... }
--            best: the first of its kind among what the list may show.
--   summary: { items = rows listed, groups = subcategories listed,
--              hidden = left out for their price, useless = left out as of no use }
function P.Build(supplies, opts)
    local rows = {}
    local summary = { items = 0, groups = 0, hidden = 0, useless = 0 }
    local money = opts.money or 0

    local bySub, subs = {}, {}
    for _, supply in pairs(supplies) do
        local affordable = supply.price <= money
        local value, use, why, plain = Judge(supply, opts)
        if opts.bestOnly and use == false then
            summary.useless = summary.useless + 1
        elseif opts.affordableOnly and not affordable then
            summary.hidden = summary.hidden + 1
        else
            local kinds = bySub[supply.sub]
            if not kinds then
                kinds = { list = {}, byKey = {} }
                bySub[supply.sub] = kinds
                subs[#subs + 1] = supply.sub
            end
            -- Of two kinds equal in everything else the one with a text of its own comes first.
            local key = plain and PLAIN .. supply.restores or supply.kind
            local kind = kinds.byKey[key]
            if not kind then
                kind = { key = key, entries = {}, scored = true }
                kinds.byKey[key] = kind
                kinds.list[#kinds.list + 1] = kind
            end
            kind.entries[#kind.entries + 1] = {
                supply = supply, affordable = affordable,
                value = value, use = use, useless = use == false, why = why,
            }
            if not value then kind.scored = false end
        end
    end
    table.sort(subs, function(a, b) return Rank(a) < Rank(b) end)

    for s = 1, #subs do
        local sub = subs[s]
        local kinds = bySub[sub].list
        local total = 0
        for k = 1, #kinds do
            local kind = kinds[k]
            -- A kind with a member the tables do not know (a new rank of an old elixir) is
            -- ordered the old way throughout: a score cannot be compared with the lack of one.
            table.sort(kind.entries, kind.scored and Worthier or Stronger)
            kind.entries[1].best = true
            Place(kind)
            total = total + #kind.entries
        end
        table.sort(kinds, ByPlace)

        local header = { kind = "header", group = "SUB" .. sub, title = P.SubLabel(sub), shown = 0, total = total }
        rows[#rows + 1] = header
        for k = 1, #kinds do
            local entries = kinds[k].entries
            for i = 1, opts.bestOnly and 1 or #entries do
                rows[#rows + 1] = { kind = "supply", entry = entries[i] }
                header.shown = header.shown + 1
            end
        end
        summary.items = summary.items + header.shown
        summary.groups = summary.groups + 1
    end
    return rows, summary
end
