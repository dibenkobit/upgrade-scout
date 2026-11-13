local _, ns = ...

-- Turns the offers found by the scanner into the rows the tab shows: one block per slot,
-- best upgrade first, with the two picks marked.
local R = {}
ns.Results = R

-- "Best value" is the cheapest gold per point among upgrades that are worth having: an item
-- must give at least this share of the biggest improvement available for the slot, so that a
-- +0.1 upgrade for two copper never wins.
R.VALUE_MIN_SHARE = 0.25

-- How many rows a slot keeps at most when "Top N per slot" is ticked.
R.TOP_COUNT = 5

local function ByDelta(a, b)
    if a.delta ~= b.delta then return a.delta > b.delta end
    if a.offer.buyout ~= b.offer.buyout then return a.offer.buyout < b.offer.buyout end
    return a.offer.id < b.offer.id
end

-- The offers worth looking at: an entry stays only if it costs less per point than everything
-- stronger. What is left reads top to bottom as "weaker, but cheaper per point", which also
-- means cheaper outright. Comparing prices alone is not enough: +0.5 for one copper less than
-- +2.7 would stay in the list.
-- The best upgrade is always the first of them, and the best value is always among them:
-- everything stronger than it costs more per point. entries must be sorted by ByDelta.
local function Sensible(entries)
    local kept, lowest = {}, math.huge
    for i = 1, #entries do
        local entry = entries[i]
        if entry.costPer < lowest then
            lowest = entry.costPer
            kept[#kept + 1] = entry
        end
    end
    return kept
end

-- Would Sensible() drop an item that gives `delta` in this slot and costs at least `minPrice`,
-- whatever its real price turns out to be? True when an entry that sorts before it already
-- costs no more per point than the item's best case. The scanner uses this to skip item
-- searches whose result "Top N per slot" would hide; it must stay in step with Sensible().
function R.Dominated(entries, delta, minPrice)
    local bestCase = minPrice / delta
    for i = 1, #entries do
        local entry = entries[i]
        if entry.delta > delta then
            if entry.costPer <= bestCase then return true end
        elseif entry.delta == delta and entry.offer.buyout < minPrice then
            return true
        end
    end
    return false
end

-- The rows a slot shows under "Top N per slot". When there are more sensible offers than rows,
-- the best upgrade, the best value and the step below the best value are kept, and the rest of
-- the rows go to the steps right below the best upgrade.
local function Shortlist(entries, limit)
    local sensible = Sensible(entries)
    if #sensible <= limit then return sensible end

    local take, left = {}, limit
    local function Take(i)
        if left > 0 and sensible[i] and not take[i] then
            take[i] = true
            left = left - 1
        end
    end
    Take(1)
    for i = 2, #sensible do
        if sensible[i].pick == "VALUE" then
            Take(i)
            Take(i + 1)
            break
        end
    end
    for i = 2, #sensible do Take(i) end

    local kept = {}
    for i = 1, #sensible do
        if take[i] then kept[#kept + 1] = sensible[i] end
    end
    return kept
end

-- entries must already be sorted by ByDelta.
local function MarkPicks(entries)
    local bestUpgrade = entries[1]
    local floor = bestUpgrade.delta * R.VALUE_MIN_SHARE
    local bestValue
    for i = 1, #entries do
        local entry = entries[i]
        if entry.delta >= floor then
            if not bestValue or entry.costPer < bestValue.costPer
                or (entry.costPer == bestValue.costPer and entry.delta > bestValue.delta) then
                bestValue = entry
            end
        end
    end
    if bestValue == bestUpgrade then
        bestUpgrade.pick = "BOTH"
    else
        bestUpgrade.pick = "UPGRADE"
        bestValue.pick = "VALUE"
    end
end

-- The offers the list can show, as entries per slot group (unsorted): one entry for every
-- slot an offer is an upgrade in, unless the price filter leaves the offer out.
-- opts: { money = copper the player has, affordableOnly = bool }
-- Returns byGroup, hidden (upgrades left out for their price)
function R.Collect(offers, ctx, opts)
    local byGroup, hidden = {}, 0
    local money = opts.money or 0
    for _, offer in pairs(offers) do
        local placements = ns.Compare.Place(offer, ctx)
        if #placements > 0 then
            local affordable = offer.buyout <= money
            if opts.affordableOnly and not affordable then
                hidden = hidden + 1
            else
                for i = 1, #placements do
                    local p = placements[i]
                    local list = byGroup[p.group]
                    if not list then
                        list = {}
                        byGroup[p.group] = list
                    end
                    list[#list + 1] = {
                        offer = offer,
                        group = p.group,
                        delta = p.delta,
                        base = p.base,
                        percent = p.percent,
                        replaced = p.replaced,
                        note = p.note,
                        costPer = offer.buyout / p.delta,
                        affordable = affordable,
                    }
                end
            end
        end
    end
    return byGroup, hidden
end

-- offers: offer id -> offer (see Scanner)
-- ctx:    comparison context (see PawnBridge.Context)
-- opts:   { money = copper the player has, affordableOnly = bool,
--             limit = nil for everything, or the most rows a slot may take (see Shortlist),
--             unchecked = upgrades whose price the scanner has not looked up (Scanner.Unchecked) }
-- Returns rows, summary
--   rows:    { { kind = "header", group = id, shown = n, total = n, approx = bool },
--              { kind = "item", entry = {...} }, ... }
--            total counts unchecked upgrades too; approx says so, because some of them may
--            turn out to have no buyout price.
--   summary: { upgrades = offers listed, slots = blocks listed, hidden = upgrades left out for price }
-- The picks are chosen among everything found for the slot, so `limit` never changes them.
function R.Build(offers, ctx, opts)
    local rows = {}
    local summary = { upgrades = 0, slots = 0, hidden = 0 }
    if not ctx then return rows, summary end

    local byGroup, hidden = R.Collect(offers, ctx, opts)
    local unchecked = opts.unchecked
    summary.hidden = hidden + (unchecked and unchecked.tooDear or 0)

    local listed = {}
    for g = 1, #ns.Compare.GROUPS do
        local group = ns.Compare.GROUPS[g]
        local entries = byGroup[group.id]
        if entries then
            table.sort(entries, ByDelta)
            MarkPicks(entries)
            summary.slots = summary.slots + 1

            local shown = opts.limit and Shortlist(entries, opts.limit) or entries
            local more = unchecked and unchecked.groups[group.id] or 0
            rows[#rows + 1] = {
                kind = "header", group = group.id,
                shown = #shown, total = #entries + more, approx = more > 0,
            }
            for i = 1, #shown do
                local entry = shown[i]
                rows[#rows + 1] = { kind = "item", entry = entry }
                if not listed[entry.offer.id] then
                    listed[entry.offer.id] = true
                    summary.upgrades = summary.upgrades + 1
                end
            end
        end
    end
    return rows, summary
end
