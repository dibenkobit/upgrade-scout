local _, ns = ...
local L = ns.L

-- Consumables for sale, as the Consumables tab lists them. The scanner finds the ones the
-- player can use (Scanner.StartSupplies); this file says which of them do the same thing,
-- which of those is the strongest, and builds the rows.
--
-- Nothing in here knows what a potion is. Two consumables are of one kind when the game's
-- text for what they do is the same but for the numbers ("Restores 70 to 90 health." and
-- "Restores 700 to 900 health."), in whatever language the game runs in. Within a kind the
-- one that asks for the higher level is the stronger. Equal levels are settled by the bigger
-- number in the text: that is how bandages differ, which ask for a skill and not a level.
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

-- The kinds there is most of for sale first: healing potions before the rare ones.
local function ByStock(a, b)
    if a.stock ~= b.stock then return a.stock > b.stock end
    return a.key < b.key
end

-- supplies: id -> consumable (see Scanner.StartSupplies)
-- opts:     { money = copper the player has, affordableOnly = bool,
--             bestOnly = bool: one row per kind, its strongest }
-- Returns rows, summary
--   rows:    { { kind = "header", group = "SUB1", title = "Potions", shown = n, total = n },
--              { kind = "supply", entry = { supply = {...}, affordable = bool, best = bool } }, ... }
--            best: the strongest of its kind among what the list may show.
--   summary: { items = rows listed, groups = subcategories listed, hidden = left out for their price }
function P.Build(supplies, opts)
    local rows = {}
    local summary = { items = 0, groups = 0, hidden = 0 }
    local money = opts.money or 0

    local bySub, subs = {}, {}
    for _, supply in pairs(supplies) do
        local affordable = supply.price <= money
        if opts.affordableOnly and not affordable then
            summary.hidden = summary.hidden + 1
        else
            local kinds = bySub[supply.sub]
            if not kinds then
                kinds = { list = {}, byKey = {} }
                bySub[supply.sub] = kinds
                subs[#subs + 1] = supply.sub
            end
            local kind = kinds.byKey[supply.kind]
            if not kind then
                kind = { key = supply.kind, entries = {}, stock = 0 }
                kinds.byKey[supply.kind] = kind
                kinds.list[#kinds.list + 1] = kind
            end
            kind.entries[#kind.entries + 1] = { supply = supply, affordable = affordable }
            kind.stock = kind.stock + supply.quantity
        end
    end
    table.sort(subs, function(a, b) return Rank(a) < Rank(b) end)

    for s = 1, #subs do
        local sub = subs[s]
        local kinds = bySub[sub].list
        local total = 0
        for k = 1, #kinds do
            local entries = kinds[k].entries
            table.sort(entries, Stronger)
            entries[1].best = true
            total = total + #entries
        end
        table.sort(kinds, ByStock)

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
