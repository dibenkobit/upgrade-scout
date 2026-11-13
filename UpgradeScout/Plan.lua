local _, ns = ...

-- The best set of upgrades for a sum of money.
-- The list answers "what is the best for this slot". This answers the question of a buyer
-- with five gold: which of these offers, taken together, make the character strongest for
-- that money. It is a choice of offers, no more of a kind than can be worn at once (one chest,
-- two rings, what two hands hold), whose prices add up to no more than the budget and whose
-- gains add up to as much as can be.
--
-- It is worked out exactly, in two steps:
--   1. For each kind of item, every way to wear the offers of that kind (one of them, or two
--      where two can be worn) is tried on a copy of the gear, by the rule the list itself
--      goes by (Compare.Place). A way that costs more than another and gives no more is
--      dropped.
--   2. The kinds are joined one after another: every way of the one with every way of the
--      other, again without what costs more and gives no more.
-- What is left is a ladder of sets, each rung dearer and stronger than the one below it. The
-- set for a budget is the highest rung that costs no more. The ladder is made once for all
-- the money the buyer has, so another budget needs no new sum.
local P = {}
ns.Plan = P

-- More rungs than this are thinned out, so that a huge auction house cannot stall the game.
-- (The best set for all the money is always kept.)
local MAX_RUNGS = 1000

local function CopyGear(equipped)
    local out = {}
    for slot, worn in pairs(equipped) do out[slot] = worn end
    return out
end

-- The context `ctx` with other gear on.
local function On(ctx, equipped)
    local out = {}
    for key, value in pairs(ctx) do out[key] = value end
    out.equipped = equipped
    return out
end

-- Puts the items on one after another, each where it gains the most, on a copy of the gear.
-- Returns what they gain together and where each went; nil when one of them would not be
-- worn, or would take the place of another of them: a set never pays for that.
local function Try(ctx, items)
    local view = On(ctx, CopyGear(ctx.equipped))
    local gain, placed, used = 0, {}, {}
    for i = 1, #items do
        local item = items[i]
        local placements = ns.Compare.Place(item, view)
        local best
        for p = 1, #placements do
            local placement = placements[p]
            if not used[placement.slot] and (not best or placement.delta > best.delta) then best = placement end
        end
        if not best then return nil end
        -- A two-hander empties the off hand, whatever was just put there.
        if item.invType == "INVTYPE_2HWEAPON" and used[17] then return nil end
        ns.Compare.Wear(view.equipped, item, best)
        used[best.slot] = true
        gain = gain + best.delta
        placed[i] = best
    end
    return gain, placed
end

local function ByCost(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.gain > b.gain
end

-- The ways worth having, cheapest first: each gives more than every cheaper one.
local function Ladder(options)
    table.sort(options, ByCost)
    local out, best = {}, -1
    for i = 1, #options do
        local option = options[i]
        if option.gain > best + 1e-9 then
            best = option.gain
            out[#out + 1] = option
        end
    end
    return out
end

local function ByID(a, b)
    return a.id < b.id
end

-- The offers of one kind that a set can need. One is left out when `room` others that are
-- worn the same way are at least as strong and cost no more: whatever set it is in, one of
-- those could stand in its place.
local function Needed(offers, room)
    local out = {}
    for i = 1, #offers do
        local offer = offers[i]
        local better = 0
        for j = 1, #offers do
            local other = offers[j]
            if j ~= i and other.invType == offer.invType and other.value >= offer.value and other.buyout <= offer.buyout
                and (other.value > offer.value or other.buyout < offer.buyout or j < i) then
                better = better + 1
                if better >= room then break end
            end
        end
        if better < room then out[#out + 1] = offer end
    end
    return out
end

-- Every way to wear the offers of one kind for no more than `cap`, as a ladder. Its first
-- rung is to buy none of them.
local function Ways(ctx, offers, room, cap)
    local out = { { cost = 0, gain = 0 } }
    for i = 1, #offers do
        local offer = offers[i]
        local gain, placed = Try(ctx, { offer })
        if gain then
            out[#out + 1] = { cost = offer.buyout, gain = gain, picks = { { offer = offer, placement = placed[1] } } }
        end
    end
    if room > 1 then
        for i = 1, #offers - 1 do
            local a = offers[i]
            for j = i + 1, #offers do
                local b = offers[j]
                if a.buyout + b.buyout <= cap then
                    -- Which of the two goes on first can decide where each ends up.
                    local gain, placed = Try(ctx, { a, b })
                    local first, second = a, b
                    local other, otherPlaced = Try(ctx, { b, a })
                    if other and (not gain or other > gain) then
                        gain, placed, first, second = other, otherPlaced, b, a
                    end
                    if gain then
                        out[#out + 1] = {
                            cost = a.buyout + b.buyout, gain = gain,
                            picks = { { offer = first, placement = placed[1] }, { offer = second, placement = placed[2] } },
                        }
                    end
                end
            end
        end
    end
    return Ladder(out)
end

-- Every rung of the one ladder with every rung of the other.
local function Join(a, b, cap)
    local out = {}
    for i = 1, #a do
        local x = a[i]
        local room = cap - x.cost
        for j = 1, #b do
            local y = b[j]
            if y.cost > room then break end
            out[#out + 1] = { cost = x.cost + y.cost, gain = x.gain + y.gain, left = x, right = y }
        end
    end
    out = Ladder(out)
    if #out > MAX_RUNGS then
        local thin, step = {}, #out / MAX_RUNGS
        for k = 1, MAX_RUNGS do thin[k] = out[math.floor(k * step + 0.5)] end
        out = thin
    end
    return out
end

local function Unfold(option, out)
    if option.picks then
        for i = 1, #option.picks do out[#out + 1] = option.picks[i] end
    elseif option.left then
        Unfold(option.left, out)
        Unfold(option.right, out)
    end
end

-- The gear of `ctx` with `items` on as well: what the character has bought and not yet put
-- on. An upgrade is then measured against those, and no second chest is bought to replace the
-- one that is still in the mail. Returns a context of its own; `ctx` is left as it is.
--   items   { { link, itemID, invType, value, unique }, ... }
function P.Wearing(ctx, items)
    if not items or #items == 0 then return ctx end
    local view = On(ctx, CopyGear(ctx.equipped))
    for i = 1, #items do
        local item = items[i]
        local placements = ns.Compare.Place(item, view)
        local best
        for p = 1, #placements do
            if not best or placements[p].delta > best.delta then best = placements[p] end
        end
        if best then ns.Compare.Wear(view.equipped, item, best) end
    end
    return view
end

-- The ladder of sets that can be bought from `offers` for no more than `cap` copper.
--   offers   offer id -> offer (see Scanner)
--   ctx      comparison context (see PawnBridge.Context)
function P.Ladder(offers, ctx, cap)
    local kinds, names = {}, {}
    for _, offer in pairs(offers) do
        if offer.buyout <= cap then
            local name, room = ns.Compare.Kind(offer.invType)
            if name then
                local kind = kinds[name]
                if not kind then
                    kind = { room = room, offers = {} }
                    kinds[name] = kind
                    names[#names + 1] = name
                end
                kind.offers[#kind.offers + 1] = offer
            end
        end
    end
    -- The same offers always make the same ladder, in whatever order they were found.
    table.sort(names)
    local ladder = { { cost = 0, gain = 0 } }
    for i = 1, #names do
        local kind = kinds[names[i]]
        table.sort(kind.offers, ByID)
        local ways = Ways(ctx, Needed(kind.offers, kind.room), kind.room, cap)
        if #ways > 1 then ladder = Join(ladder, ways, cap) end
    end
    return ladder
end

-- The strongest set on the ladder that costs no more than `budget`; nil when not one upgrade
-- can be had for it.
function P.Choose(ladder, budget)
    local best
    for i = 1, #ladder do
        if ladder[i].cost > budget then break end
        best = ladder[i]
    end
    if not best or best.gain <= 0 then return nil end
    return best
end

local function ByDelta(a, b)
    if a.entry.delta ~= b.entry.delta then return a.entry.delta > b.entry.delta end
    return a.entry.offer.id < b.entry.offer.id
end

-- The rows of a set for the list: its offers under the headings of their slots, in the order
-- the list has its slots.
-- Returns rows, summary
--   rows      as Results.Build makes them. A heading is `plain`: nothing is folded away under
--             it and it counts nothing. An item's `share` is its gain next to the biggest gain
--             of the set, for its meter.
--   summary   { upgrades, slots, hidden = 0, cost = copper for the set, gain = points it adds }
function P.Rows(set)
    local rows = {}
    local summary = { upgrades = 0, slots = 0, hidden = 0, cost = 0, gain = 0 }
    if not set then return rows, summary end

    local picks = {}
    Unfold(set, picks)
    local byGroup, top = {}, 0
    for i = 1, #picks do
        local offer, placement = picks[i].offer, picks[i].placement
        local list = byGroup[placement.group]
        if not list then
            list = {}
            byGroup[placement.group] = list
        end
        list[#list + 1] = { kind = "item", entry = {
            offer = offer,
            group = placement.group,
            delta = placement.delta,
            base = placement.base,
            percent = placement.percent,
            replaced = placement.replaced,
            note = placement.note,
            costPer = offer.buyout / placement.delta,
            affordable = true,
        } }
        if placement.delta > top then top = placement.delta end
    end

    for g = 1, #ns.Compare.GROUPS do
        local group = ns.Compare.GROUPS[g]
        local list = byGroup[group.id]
        if list then
            table.sort(list, ByDelta)
            summary.slots = summary.slots + 1
            rows[#rows + 1] = { kind = "header", group = group.id, shown = #list, total = #list, plain = true }
            for i = 1, #list do
                list[i].share = top > 0 and list[i].entry.delta / top or 1
                rows[#rows + 1] = list[i]
            end
        end
    end
    summary.upgrades = #picks
    summary.cost, summary.gain = set.cost, set.gain
    return rows, summary
end
