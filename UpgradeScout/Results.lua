local _, ns = ...

-- Turns the offers found by the scanner into the rows the tab shows: one block per slot,
-- best upgrade first, with the two picks marked.
local Results = {}
ns.Results = Results

-- "Best value" is the cheapest gold per point among upgrades that are worth having: an item
-- must give at least this share of the biggest improvement available for the slot, so that a
-- +0.1 upgrade for two copper never wins.
Results.VALUE_MIN_SHARE = 0.25

-- How many of its biggest upgrades a slot shows when "Top N per slot" is ticked: the number
-- the buyer typed into that line of the Filters menu, from 1 to TOP_MAX, and TOP_DEFAULT
-- until one is typed. The best value has a row besides when it is not one of them (see
-- Shortlist).
Results.TOP_DEFAULT, Results.TOP_MAX = 5, 99

-- That number, whether its box is ticked or not (ns.db.topCount). It comes out of a saved
-- file: whatever stands there that is no such number reads as the default.
function Results.TopCount()
    local count = ns.db.topCount
    if type(count) ~= "number" or count ~= count then return Results.TOP_DEFAULT end
    return math.max(1, math.min(Results.TOP_MAX, math.floor(count)))
end

-- What gear costs in the end: its buyout less what a vendor pays for it (`sell`) once the
-- character is done with it. Bought for 4 silver and sold for 3, it cost 1. Never less than
-- nothing: an auction below the vendor's price is free, and the list does not call it a gain.
function Results.Net(buyout, sell)
    return math.max(buyout - (sell or 0), 0)
end

-- What the list prices an offer at: its buyout, or with `net` (the "Net cost" box of the tab)
-- its net cost. The price per point, and so the best value, the row "Top N per slot" keeps
-- for it and what "Hide worse deals" leaves out, go by the same, and so does the order of two
-- offers that gain the same. What the player can pay for is always a matter of the buyout.
function Results.Cost(offer, net)
    if net then return Results.Net(offer.buyout, offer.sell) end
    return offer.buyout
end

local function ByDelta(a, b)
    if a.delta ~= b.delta then return a.delta > b.delta end
    if a.cost ~= b.cost then return a.cost < b.cost end
    if a.offer.buyout ~= b.offer.buyout then return a.offer.buyout < b.offer.buyout end
    return a.offer.id < b.offer.id
end

-- The rows a slot shows under "Hide worse deals": an entry stays only if it costs less per
-- point than everything stronger. What is left reads top to bottom as "weaker, but cheaper
-- per point", which also means cheaper outright. Comparing prices alone is not enough: +0.5
-- for one copper less than +2.7 would stay in the list.
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

-- Would Sensible() drop an item that gives `delta` in this slot and costs at least `minCost`,
-- whatever its real price turns out to be and whatever else is found for the slot after
-- this? `entries` are offers the slot is known to have, in any order. True when one of them
-- gives more for no more per point than the item's best case, `minCost` for its gain, or
-- gives the same for less than `minCost`. That entry stands before the item in the order of
-- ByDelta whatever the item costs, so the lowest price per point above the item is never
-- more than the item's own. Whether the entry has a row itself is no matter, and more
-- offers in the slot can only lower that price. Nor is the item a pick at any such price:
-- the entry is weighed for the best value wherever the item is, and MarkPicks prefers it.
-- The scanner uses this to skip item searches whose result "Hide worse deals" would hide,
-- with "Top N per slot" or without it (the N rows are then taken from what Sensible()
-- leaves); it must stay in step with Sensible(), MarkPicks() and ByDelta().
-- `net` says which list is asked about, the one by buyout or the one by net cost (see
-- Results.Cost): `minCost` is a cost of that kind, and the entries are priced the same way
-- here, however they were priced when they were made.
function Results.Dominated(entries, delta, minCost, net)
    local bestCase = minCost / delta
    for i = 1, #entries do
        local entry = entries[i]
        if entry.delta >= delta then
            local cost = Results.Cost(entry.offer, net)
            if entry.delta > delta then
                if cost / entry.delta <= bestCase then return true end
            elseif cost < minCost then
                return true
            end
        end
    end
    return false
end

-- entries must already be sorted by ByDelta.
local function MarkPicks(entries)
    local bestUpgrade = entries[1]
    local floor = bestUpgrade.delta * Results.VALUE_MIN_SHARE
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

-- The rows a slot shows under "Top N per slot": its `limit` biggest upgrades, whatever they
-- cost, and the best value as well when it is not one of them. So a slot takes one row more
-- than `limit` at most, and the best value then stands last, where its gain puts it.
-- entries must be sorted by ByDelta, with the picks marked (MarkPicks). With "Hide worse
-- deals" ticked as well they are what Sensible() left of the slot, which the best value is
-- always one of.
local function Shortlist(entries, limit)
    if #entries <= limit then return entries end
    local kept = {}
    for i = 1, limit do kept[i] = entries[i] end
    for i = limit + 1, #entries do
        if entries[i].pick == "VALUE" then
            kept[#kept + 1] = entries[i]
            break
        end
    end
    return kept
end

-- Would Shortlist() leave out an item that gives `delta` in this slot and costs at least
-- `minCost`, whatever its real price turns out to be and whatever else is found for the slot
-- after this? `entries` are offers the slot is known to have, in any order. True when both
-- of these hold:
--   * `limit` of the entries stand before the item in the order of ByDelta whatever it
--     costs: they give more, or the same for less than `minCost`. The item is then not one
--     of the `limit` biggest upgrades, and more offers in the slot cannot make it one.
--   * It cannot be the best value. Either one of those entries costs no more per point than
--     the item's best case, `minCost` for its gain: that entry gives at least as much, so it
--     is weighed for the best value wherever the item is, and MarkPicks prefers it. Or the
--     item gives less than the share of the strongest entry's gain that a best value must
--     give (VALUE_MIN_SHARE): a stronger offer found later only asks for more.
-- An entry that gives the same for exactly `minCost` proves neither: which of the two stands
-- first is not a matter of the price then.
-- The scanner uses this to skip item searches whose result "Top N per slot" would not show;
-- it must stay in step with Shortlist(), MarkPicks() and ByDelta().
-- It proves nothing once "Hide worse deals" is ticked too. The `limit` rows are then taken
-- from what Sensible() leaves, and the entries counted here may have no row there. With
-- +100 for 10 a point and +90 for 20 a point known, and rows for two, +10 for 1 a point is
-- third by its gain and too small to be the best value; and yet it has the second row, the
-- +90 being left out for its price. Results.Dominated is the question to ask then.
-- `net` says which list is asked about, the one by buyout or the one by net cost (see
-- Results.Cost): `minCost` is a cost of that kind, and the entries are priced the same way
-- here, however they were priced when they were made.
function Results.LeftOut(entries, delta, minCost, net, limit)
    local bestCase = minCost / delta
    local before, strongest, undersold = 0, 0, false
    for i = 1, #entries do
        local entry = entries[i]
        if entry.delta > strongest then strongest = entry.delta end
        if entry.delta >= delta then
            local cost = Results.Cost(entry.offer, net)
            if entry.delta > delta then
                before = before + 1
                if cost / entry.delta <= bestCase then undersold = true end
            elseif cost < minCost then
                before = before + 1
                undersold = true
            end
            -- (Both proven: the entries still unread can only add to them.)
            if undersold and before >= limit then return true end
        end
    end
    if before < limit then return false end
    -- (No entry undersells it: only too small a gain can rule it out as the best value.)
    return delta < strongest * Results.VALUE_MIN_SHARE
end

-- What the list shows of an offer in one of the slots it would go into (see Compare.Place).
-- `cost` is what the list prices it at, the buyout or with `net` the net cost (Results.Cost),
-- and `costPer` that for a point of the gain.
function Results.Entry(offer, placement, affordable, net)
    local cost = Results.Cost(offer, net)
    return {
        offer = offer,
        group = placement.group,
        delta = placement.delta,
        base = placement.base,
        percent = placement.percent,
        replaced = placement.replaced,
        note = placement.note,
        cost = cost,
        costPer = cost / placement.delta,
        affordable = affordable,
    }
end

-- The offers the list can show, as entries per slot group (unsorted): one entry for every
-- slot an offer is an upgrade in, unless a filter leaves it out: the character's own
-- (Wants.lua), which may also leave out one slot of two, or one of the two price filters.
-- (An offer may be an upgrade nowhere as the character fills its hands: a scan keeps what
-- another choice of that would have a place for, see Compare.Possible. It is no row then,
-- and is not counted as left out either.)
-- opts: { money = copper the player has, affordableOnly = bool, net = bool (see Results.Cost),
--         cap = the most an offer may cost, in copper ("Buyout up to", Wants.Price), nil for any sum,
--         wants = what the character wants of its gear (Wants.Of), nil for anything }
-- Returns byGroup, hidden (upgrades left out for their price), unwanted (upgrades the
-- character's own filters leave out; one of those is not counted for its price as well)
-- What a price filter leaves out is out before the picks are chosen: under a sum, the best
-- upgrade of a slot is the best one for that sum.
function Results.Collect(offers, ctx, opts)
    local byGroup, hidden, unwanted = {}, 0, 0
    local money = opts.money or 0
    local cap = opts.cap
    -- (How the character means to fill its hands has a say in where an item can go.)
    local hands = opts.wants and opts.wants.hands
    for _, offer in pairs(offers) do
        local placements = ns.Compare.Place(offer, ctx, hands)
        if #placements > 0 then
            placements = ns.Wants.Keep(opts.wants, offer, placements)
            -- (Whether it can be paid for is a matter of the purse alone: a row says so.)
            local affordable = offer.buyout <= money
            if #placements == 0 then
                unwanted = unwanted + 1
            elseif (opts.affordableOnly and not affordable) or (cap and offer.buyout > cap) then
                hidden = hidden + 1
            else
                for i = 1, #placements do
                    local p = placements[i]
                    local list = byGroup[p.group]
                    if not list then
                        list = {}
                        byGroup[p.group] = list
                    end
                    list[#list + 1] = Results.Entry(offer, p, affordable, opts.net)
                end
            end
        end
    end
    return byGroup, hidden, unwanted
end

-- offers: offer id -> offer (see Scanner)
-- ctx:    comparison context (see Score.Context)
-- opts:   { money = copper the player has, affordableOnly = bool,
--             cap = the most an offer may cost ("Buyout up to", see Results.Collect),
--             net = the offers are priced at their net cost (see Results.Cost),
--             wants = what the character wants of its gear (Wants.Of),
--             frontier = an offer is left out when a stronger one costs the same or less per
--                     point ("Hide worse deals", see Sensible),
--             limit = nil for everything, or how many of its biggest upgrades a slot shows,
--                     with the best value besides (see Shortlist): of what `frontier` leaves,
--                     when both are asked for,
--             unchecked = upgrades whose price the scanner has not looked up (Scanner.Unchecked) }
-- Returns rows, summary
--   rows:    { { kind = "header", group = id, shown = n, total = n, approx = bool },
--              { kind = "item", entry = {...} }, ... }
--            total counts unchecked upgrades too; approx says that some of them, or of the
--            offers, go by a price that was not looked up, and may turn out to have no
--            buyout price.
--   summary: { upgrades = offers listed, slots = blocks listed, hidden = upgrades left out for price,
--              unwanted = upgrades the character's own filters leave out }
-- The picks are chosen among everything found for the slot, so neither `frontier` nor
-- `limit` changes them.
function Results.Build(offers, ctx, opts)
    local rows = {}
    local summary = { upgrades = 0, slots = 0, hidden = 0, unwanted = 0 }
    if not ctx then return rows, summary end

    local byGroup, hidden, unwanted = Results.Collect(offers, ctx, opts)
    local unchecked = opts.unchecked
    summary.hidden = hidden + (unchecked and unchecked.tooDear or 0)
    summary.unwanted = unwanted + (unchecked and unchecked.unwanted or 0)

    local listed = {}
    for g = 1, #ns.Compare.GROUPS do
        local group = ns.Compare.GROUPS[g]
        local entries = byGroup[group.id]
        if entries then
            table.sort(entries, ByDelta)
            MarkPicks(entries)
            summary.slots = summary.slots + 1

            local shown = entries
            if opts.frontier then shown = Sensible(shown) end
            if opts.limit then shown = Shortlist(shown, opts.limit) end
            local more = unchecked and unchecked.groups[group.id] or 0
            -- How many there are is a guess while some go by a price that was not looked up
            -- (an offer that is `unsure`, see ListCandidates in Scanner.lua).
            local approx = more > 0
            for i = 1, #entries do
                if entries[i].offer.unsure then
                    approx = true
                    break
                end
            end
            rows[#rows + 1] = {
                kind = "header", group = group.id,
                shown = #shown, total = #entries + more, approx = approx,
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
