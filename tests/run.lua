-- Runs Upgrade Scout against the stand-in client in tests/wow.lua.
--   lua5.1 tests/run.lua            every scenario, each in its own process
--   lua5.1 tests/run.lua <name>     one scenario
-- Run from the project folder (the one that contains UpgradeScout/ and tests/).
local realPrint = print
local scenario = arg[1]
local ADDON_DIR = "UpgradeScout/"

local names = {
    "compare", "picks", "scan_sorted", "scan_order", "scan_unsorted", "scan_async", "scan_no_sample",
    "scan_suffix_rows", "scan_varying_rows", "scan_no_answer", "scan_interrupted",
    "scan_lazy", "scan_bad_floor", "scan_pages", "scan_halt", "scan_eta",
    "buy", "buy_gone", "ui", "pawn_missing", "locale_ru", "locale_de", "locale_fr", "locale_zh",
    "locale_pt", "locale_es", "locale_mx", "locale_it",
}

if not scenario then
    local lua = arg[-1] or "lua5.1"
    local failed = 0
    for _, name in ipairs(names) do
        local code = os.execute('"' .. lua .. '" tests/run.lua ' .. name)
        if code ~= 0 then failed = failed + 1 end
    end
    realPrint(failed == 0 and ("ALL " .. #names .. " SCENARIOS PASSED") or (failed .. " SCENARIO(S) FAILED"))
    os.exit(failed == 0 and 0 or 1)
end

local W = dofile("tests/wow.lua")
local ns = {}
local checks = 0

local function check(condition, label)
    checks = checks + 1
    if not condition then error("check failed: " .. label, 2) end
end

local function eq(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function near(actual, expected, label)
    checks = checks + 1
    if type(actual) ~= "number" or math.abs(actual - expected) > 1e-6 then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

-- Loads the addon's files in .toc order, the way the game does.
local function LoadAddon()
    for line in io.lines(ADDON_DIR .. "UpgradeScout.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local chunk = assert(loadfile(ADDON_DIR .. line:gsub("\\", "/")))
            chunk("UpgradeScout", ns)
        end
    end
    W.AddOnLoaded("UpgradeScout")
end

local function Offer(name)
    for _, offer in pairs(ns.Scanner.offers) do
        if offer.name == name then return offer end
    end
end

local function OfferCount()
    local n = 0
    for _ in pairs(ns.Scanner.offers) do n = n + 1 end
    return n
end

local function ScanToEnd()
    check(ns.Scanner.Start(), "scan starts")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 600)
end

-- The two checkboxes of the tab. With both off the list shows every upgrade, so the scan has
-- to look up every price.
local function SetView(affordableOnly, topOnly)
    ns.db.affordableOnly = affordableOnly
    ns.db.topOnly = topOnly
end

-- A level 10 warrior with a chest (score 10), one ring (score 4) and a one-hand sword (score 20).
local function StandardWorld()
    W.AddItem({ id = 100, name = "Worn Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 10, level = 5 })
    W.AddItem({ id = 101, name = "Worn Ring", equipLoc = "INVTYPE_FINGER", value = 4, level = 5 })
    W.AddItem({ id = 102, name = "Worn Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, value = 20, level = 5 })
    W.equipped[5] = W.Link(100)
    W.equipped[11] = W.Link(101)
    W.equipped[16] = W.Link(102)

    -- For sale
    W.AddItem({ id = 200, name = "Good Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 18, level = 8 })
    W.AddItem({ id = 201, name = "Great Chest", equipLoc = "INVTYPE_ROBE", subClassID = 1, value = 30, level = 10, effects = true })
    W.AddItem({ id = 202, name = "Weak Chest", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 9, level = 4 })
    W.AddItem({ id = 203, name = "Future Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 60, level = 14 })
    W.AddItem({ id = 204, name = "Unlearned Mail", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 40, level = 9, red = true })
    W.AddItem({ id = 205, name = "Bid Only Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 50, level = 9 })
    W.AddItem({ id = 206, name = "My Own Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 55, level = 9 })
    W.AddItem({ id = 207, name = "Plain Shirt", equipLoc = "INVTYPE_BODY", subClassID = 0, value = 99, level = 1 })
    W.AddItem({ id = 208, name = "Statless Chest", equipLoc = "INVTYPE_CHEST", subClassID = 1, value = 0, level = 1, noStats = true })
    W.AddItem({ id = 210, name = "New Ring", equipLoc = "INVTYPE_FINGER", value = 6, level = 9 })
    W.AddItem({ id = 211, name = "Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 12, level = 10 })
    W.AddItem({ id = 212, name = "Big Axe", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 1, value = 26, level = 10 })
    W.AddItem({ id = 213, name = "Shield", equipLoc = "INVTYPE_SHIELD", subClassID = 6, value = 7, level = 6 })
    W.AddItem({ id = 214, name = "Potion", equipLoc = "", classID = 0, value = 0, level = 1 })

    W.AddAuction(200, 5000)
    W.AddAuction(200, 4000)             -- cheapest Good Chest
    W.AddAuction(200, 0)                -- bid only
    W.AddAuction(201, 90000)
    W.AddAuction(202, 100)
    W.AddAuction(203, 100)
    W.AddAuction(204, 100)
    W.AddAuction(205, 0)
    W.AddAuction(206, 100, { own = true })
    W.AddAuction(207, 100)
    W.AddAuction(208, 100)
    W.AddAuction(210, 800)
    W.AddAuction(211, 2500)
    W.AddAuction(212, 3000)
    W.AddAuction(213, 700)
    W.AddAuction(214, 50)
end

-- Many rows above the player's level, so that a level-sorted browse has a reason to stop early.
local function AddHighLevelFiller(count)
    for i = 1, count do
        local id = 5000 + i
        W.AddItem({ id = id, name = "High Item " .. i, equipLoc = "INVTYPE_LEGS", subClassID = 3, value = 100 + i, level = 20 + (i % 30) })
        W.AddAuction(id, 1000 + i)
    end
end

local function CheckStandardOffers(label)
    local S = ns.Scanner
    eq(S.state, "idle", label .. ": scan finished")
    local good = Offer("Good Chest")
    check(good ~= nil, label .. ": Good Chest found")
    eq(good.buyout, 4000, label .. ": cheapest buyout kept")
    eq(good.count, 2, label .. ": bid-only auction not counted")
    near(good.value, 18, label .. ": base (unenchanted) Pawn value used")
    check(Offer("Great Chest") ~= nil, label .. ": robe counts as chest")
    eq(Offer("Great Chest").effects, true, label .. ": unscored effects flagged")
    check(Offer("New Ring") ~= nil, label .. ": ring found")
    check(Offer("Helm") ~= nil, label .. ": empty slot item found")
    check(Offer("Big Axe") ~= nil, label .. ": two-hander found")
    check(Offer("Shield") ~= nil, label .. ": shield found")
    eq(Offer("Weak Chest"), nil, label .. ": not an upgrade")
    eq(Offer("Future Chest"), nil, label .. ": level too high")
    eq(Offer("Unlearned Mail"), nil, label .. ": red tooltip line")
    eq(Offer("Bid Only Chest"), nil, label .. ": no buyout")
    eq(Offer("My Own Chest"), nil, label .. ": own auction")
    eq(Offer("Plain Shirt"), nil, label .. ": shirts ignored")
    eq(Offer("Statless Chest"), nil, label .. ": nothing for Pawn to score")
    eq(OfferCount(), 6, label .. ": offer count")
end

local scenarios = {}

---------------------------------------------------------------------------
function scenarios.compare()
    LoadAddon()
    local Place = ns.Compare.Place
    local function ctx(equipped, extra)
        local c = { equipped = equipped, dualWield = false, show1H = true, show2H = true }
        for k, v in pairs(extra or {}) do c[k] = v end
        return c
    end
    local function worn(value, invType, itemID)
        return { link = "L" .. tostring(itemID or value), value = value, invType = invType, itemID = itemID or 1 }
    end

    -- single slot
    local p = Place({ invType = "INVTYPE_HEAD", value = 12, itemID = 9 }, ctx({}))
    eq(#p, 1, "empty head slot"); eq(p[1].group, "HEAD", "group"); near(p[1].delta, 12, "delta"); eq(p[1].percent, nil, "no percent for empty slot")
    p = Place({ invType = "INVTYPE_HEAD", value = 12, itemID = 9 }, ctx({ [1] = worn(10, "INVTYPE_HEAD") }))
    near(p[1].delta, 2, "head delta"); near(p[1].percent, 0.2, "head percent"); eq(p[1].replaced[1], "L10", "replaced link")
    eq(#Place({ invType = "INVTYPE_HEAD", value = 10.04, itemID = 9 }, ctx({ [1] = worn(10, "INVTYPE_HEAD") })), 0, "under 0.5% is not an upgrade")
    eq(#Place({ invType = "INVTYPE_HEAD", value = 0, itemID = 9 }, ctx({})), 0, "zero score is nothing")
    eq(#Place({ invType = "INVTYPE_TABARD", value = 5, itemID = 9 }, ctx({})), 0, "tabard ignored")
    eq(Place({ invType = "INVTYPE_ROBE", value = 5, itemID = 9 }, ctx({}))[1].group, "CHEST", "robe is chest")
    eq(Place({ invType = "INVTYPE_RANGEDRIGHT", value = 5, itemID = 9 }, ctx({}))[1].group, "RANGED", "wand is ranged")

    -- rings: the weaker one is replaced
    local rings = { [11] = worn(8, "INVTYPE_FINGER", 1), [12] = worn(3, "INVTYPE_FINGER", 2) }
    p = Place({ invType = "INVTYPE_FINGER", value = 5, itemID = 9 }, ctx(rings))
    near(p[1].delta, 2, "ring vs weaker"); eq(p[1].replaced[1], "L2", "weaker ring replaced")
    p = Place({ invType = "INVTYPE_FINGER", value = 5, itemID = 9 }, ctx({ [11] = worn(8, "INVTYPE_FINGER", 1) }))
    near(p[1].delta, 5, "ring into empty second slot"); eq(p[1].replaced, nil, "nothing replaced")
    eq(#Place({ invType = "INVTYPE_FINGER", value = 50, itemID = 1, unique = true }, ctx(rings)), 0, "second copy of a unique ring")
    eq(#Place({ invType = "INVTYPE_FINGER", value = 50, itemID = 1, unique = false }, ctx(rings)), 1, "second copy of a normal ring")

    -- weapons
    local oneHand = { [16] = worn(20, "INVTYPE_WEAPON", 1), [17] = worn(7, "INVTYPE_SHIELD", 2) }
    p = Place({ invType = "INVTYPE_2HWEAPON", value = 26, itemID = 9 }, ctx(oneHand))
    eq(#p, 0, "two-hander must beat both hands together")
    p = Place({ invType = "INVTYPE_2HWEAPON", value = 30, itemID = 9 }, ctx(oneHand))
    near(p[1].delta, 3, "two-hander delta"); eq(#p[1].replaced, 2, "both replaced"); eq(p[1].note, "BOTH_HANDS", "note")
    eq(#Place({ invType = "INVTYPE_2HWEAPON", value = 30, itemID = 9 }, ctx(oneHand, { show2H = false })), 0, "scale hides two-handers")

    p = Place({ invType = "INVTYPE_WEAPON", value = 24, itemID = 9 }, ctx(oneHand))
    eq(#p, 1, "one-hander without dual wield: main hand only"); eq(p[1].group, "MAINHAND", "main hand")
    p = Place({ invType = "INVTYPE_WEAPON", value = 24, itemID = 9 }, ctx(oneHand, { dualWield = true }))
    eq(#p, 2, "dual wielder: both hands"); near(p[2].delta, 17, "off hand delta")
    eq(#Place({ invType = "INVTYPE_WEAPON", value = 24, itemID = 9 }, ctx(oneHand, { show1H = false })), 0, "scale hides one-handers")
    p = Place({ invType = "INVTYPE_SHIELD", value = 9, itemID = 9 }, ctx(oneHand))
    eq(p[1].group, "OFFHAND", "shield"); near(p[1].delta, 2, "shield delta")
    eq(#Place({ invType = "INVTYPE_WEAPONOFFHAND", value = 9, itemID = 9 }, ctx(oneHand)), 0, "off-hand weapon needs dual wield")
    eq(#Place({ invType = "INVTYPE_HOLDABLE", value = 9, itemID = 9 }, ctx(oneHand)), 1, "held item does not")

    local twoHand = { [16] = worn(30, "INVTYPE_2HWEAPON", 1) }
    eq(#Place({ invType = "INVTYPE_SHIELD", value = 9, itemID = 9 }, ctx(twoHand)), 0, "no off hand next to a two-hander")
    p = Place({ invType = "INVTYPE_WEAPONMAINHAND", value = 33, itemID = 9 }, ctx(twoHand))
    near(p[1].delta, 3, "one-hander vs two-hander"); eq(p[1].note, "OFFHAND_EMPTY", "off hand note")
    eq(#Place({ invType = "INVTYPE_WEAPON", value = 25, itemID = 9 }, ctx(twoHand, { dualWield = true })), 0, "weaker than the two-hander")

    check(ns.Compare.Handles("INVTYPE_TRINKET") and not ns.Compare.Handles("INVTYPE_BAG") and not ns.Compare.Handles(nil) and not ns.Compare.Handles(""), "Handles")
    eq(ns.Compare.GroupLabel("CHEST"), "Chest", "label from the game")
    eq(ns.Compare.GroupLabel("TRINKET"), "Trinket", "label from the addon when the game has none")
end

---------------------------------------------------------------------------
function scenarios.picks()
    LoadAddon()
    local ctx = { equipped = { [5] = { link = "WORN", value = 10, invType = "INVTYPE_CHEST", itemID = 1 } }, show1H = true, show2H = true }
    local function offer(id, value, buyout, invType)
        return { id = id, name = id, value = value, buyout = buyout, invType = invType or "INVTYPE_CHEST", itemID = 100, count = 1 }
    end
    local offers = {
        a = offer("a", 50, 500000),     -- +40, 12500 per point
        b = offer("b", 22, 10000),      -- +12, 833 per point
        c = offer("c", 19, 2000),       -- +9, 222 per point: below a quarter of +40
        d = offer("d", 10, 1),          -- not an upgrade
        h = offer("h", 5, 300, "INVTYPE_HEAD"),
    }
    local rows, summary = ns.Results.Build(offers, ctx, { money = 1e9, affordableOnly = true })
    eq(summary.upgrades, 4, "upgrades"); eq(summary.slots, 2, "slots"); eq(summary.hidden, 0, "hidden")
    eq(rows[1].kind, "header", "first row is a header"); eq(rows[1].group, "HEAD", "head block first")
    eq(rows[2].entry.pick, "BOTH", "single item is both picks")
    eq(rows[3].group, "CHEST", "chest block")
    eq(rows[4].entry.offer.id, "a", "biggest upgrade first"); eq(rows[4].entry.pick, "UPGRADE", "best upgrade")
    eq(rows[5].entry.offer.id, "b", "then b"); eq(rows[5].entry.pick, "VALUE", "best value honors the minimum share")
    eq(rows[6].entry.pick, nil, "c is too small an upgrade to be best value")
    near(rows[5].entry.costPer, 10000 / 12, "cost per point")
    eq(#rows, 6, "row count")

    -- With 30 gold, the 50 gold item is hidden and the picks move.
    rows, summary = ns.Results.Build(offers, ctx, { money = 300000, affordableOnly = true })
    eq(summary.hidden, 1, "one hidden for price"); eq(summary.upgrades, 3, "three listed")
    eq(rows[4].entry.offer.id, "b", "b leads"); eq(rows[4].entry.pick, "UPGRADE", "b best upgrade")
    eq(rows[5].entry.pick, "VALUE", "c is best value now")

    rows, summary = ns.Results.Build(offers, ctx, { money = 300000, affordableOnly = false })
    eq(summary.hidden, 0, "nothing hidden"); eq(rows[4].entry.affordable, false, "a marked as too expensive")

    rows = ns.Results.Build(offers, nil, { money = 1 })
    eq(#rows, 0, "no context, no rows")

    -- Top N per slot. u1..u8 each cost less per point than the one before; x1 and x2 are poor buys.
    local many = {
        u1 = offer("u1", 50, 800000), u2 = offer("u2", 48, 700000), u3 = offer("u3", 46, 600000),
        u4 = offer("u4", 44, 500000), u5 = offer("u5", 42, 400000), u6 = offer("u6", 40, 300000),
        u7 = offer("u7", 30, 100),      -- +20 for a silver: best value
        u8 = offer("u8", 12, 1),        -- +2: too small to be best value
        x1 = offer("x1", 47, 900000),   -- weaker than u2, dearer than u1
        x2 = offer("x2", 45, 590000),   -- a little cheaper than u3, but weaker and dearer per point
        h = offer("h", 5, 300, "INVTYPE_HEAD"),
    }
    local function Ids(from)
        local out = {}
        for i = from, #rows do
            if rows[i].kind == "item" then out[#out + 1] = rows[i].entry.offer.id end
        end
        return table.concat(out, " ")
    end
    rows, summary = ns.Results.Build(many, ctx, { money = 1e9, limit = 5 })
    eq(summary.upgrades, 6, "six offers listed: one head, five chest")
    eq(rows[1].shown, 1, "head block untouched"); eq(rows[1].total, 1, "head total")
    eq(rows[3].group, "CHEST", "chest block"); eq(rows[3].shown, 5, "five rows kept"); eq(rows[3].total, 10, "of ten")
    eq(Ids(4), "u1 u2 u3 u7 u8", "best upgrade and two steps down, best value and one step down")
    eq(rows[4].entry.pick, "UPGRADE", "best upgrade marked"); eq(rows[7].entry.pick, "VALUE", "best value marked")

    -- Nothing is cheaper than the best value: its spare row goes to the steps below the best upgrade.
    many.u8 = nil
    rows = ns.Results.Build(many, ctx, { money = 1e9, limit = 5 })
    eq(Ids(4), "u1 u2 u3 u4 u7", "best value last")

    -- Few offers worth looking at: the block is not padded with pointless ones.
    many.u7 = nil
    many.u2.buyout = 100            -- +38 for a silver beats everything below it
    rows = ns.Results.Build(many, ctx, { money = 1e9, limit = 5 })
    eq(Ids(4), "u1 u2", "only the best upgrade and the best value are left")
    eq(rows[3].shown, 2, "two rows"); eq(rows[3].total, 8, "of eight"); eq(rows[5].entry.pick, "VALUE", "u2 is the best value")

    rows = ns.Results.Build(many, ctx, { money = 1e9 })
    eq(rows[3].shown, 8, "no limit: everything listed"); eq(#rows, 2 + 1 + 8, "row count without the limit")
    eq(Ids(4), "u1 u2 x1 u3 x2 u4 u5 u6", "in order of size")

    -- Small numbers keep two digits, so that a tiny upgrade does not read as zero.
    eq(ns.Num(12.44), "12.4", "one decimal"); eq(ns.Num(7), "7", "whole number"); eq(ns.Num(0), "0", "zero")
    eq(ns.Num(4.73), "4.7", "one decimal below ten"); eq(ns.Num(0.548), "0.55", "two decimals below one")
    eq(ns.Num(0.5), "0.5", "no trailing zero"); eq(ns.Num(0.048), "0.048", "three decimals below a tenth")
    eq(ns.Num(1.548, 3), "1.548", "precision on request"); eq(ns.Num(1.5, 3), "1.5", "trailing zeros dropped")
    eq(ns.Num(10, 3), "10", "whole number with a precision")

    -- Headings are written in capitals, in every alphabet the addon's languages use.
    eq(ns.Upper("Best value"), "BEST VALUE", "Latin")
    eq(ns.Upper("Лучшее улучшение, ёж"), "ЛУЧШЕЕ УЛУЧШЕНИЕ, ЁЖ", "Cyrillic")
    eq(ns.Upper("Amélioration à l'hôtel"), "AMÉLIORATION À L'HÔTEL", "accented Latin")
    eq(ns.Upper("Größe ÷ 2"), "GRÖßE ÷ 2", "letters without a capital of their own stay as they are")
    eq(ns.Upper("装备提升"), "装备提升", "Chinese has no capitals")
end

---------------------------------------------------------------------------
function scenarios.scan_sorted()
    StandardWorld()
    AddHighLevelFiller(400)
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("sorted")
    eq(W.AH.calls.browse, 1, "one browse query")
    check(W.AH.calls.more <= 3, "stopped early instead of reading all " .. (#W.AH.rows) .. " rows (extra pages: " .. W.AH.calls.more .. ")")
    eq(ns.Scanner.partial, false, "an early stop is a complete scan")
    -- One item search per row whose item scores above the player's gear and has no red line
    -- in its tooltip: the six that end up as offers plus two that only the search can rule
    -- out (bid only, own auction). The other rows, and all 400 high-level ones, are never
    -- searched.
    eq(W.AH.calls.search, 8, "item searches")
    local stats = ns.Scanner.stats
    eq(stats.searches, 8, "statistics: item searches"); eq(stats.candidates, 8, "statistics: candidates")
    eq(stats.skipped, 0, "statistics: nothing skipped"); eq(stats.timeouts, 0, "statistics: no timeouts")
    check(stats.requests >= 1 and stats.rows > 0 and stats.verify > 0 and stats.browse > 0, "statistics: browse and timing")
    eq(UpgradeScoutCharDB.lastScan, stats, "statistics kept with the character's settings")
    check(ns.Scanner.StatsText():find("8 item searches", 1, true) ~= nil, "statistics as text")
    eq(#W.AH.lastQuery.itemClassFilters, 2, "weapon and armor filters")
    eq(#W.AH.lastQuery.filters, 7, "all quality filters")
    check(ns.Scanner.finishedAt ~= nil, "finish time recorded")
end

-- With the "afford" order, rows the player can pay for are checked before the rest.
function scenarios.scan_order()
    StandardWorld()
    W.player.money = 3500                -- only the Great Chest row (9g) starts above this
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    local order = {}
    hooksecurefunc(C_AuctionHouse, "SendSearchQuery", function(key) order[#order + 1] = key.itemID end)
    ScanToEnd()
    local position = {}
    for i, id in ipairs(order) do position[id] = i end
    eq(position[201], #order, "the row that costs more than the player has is searched last")
    -- Helm is +12 (empty slot); the axe and the ring (into the empty second ring slot) are +6 each.
    check(position[211] < position[212] and position[211] < position[210], "bigger upgrades first among the rest")
    eq(OfferCount(), 6, "everything is still found")
end

function scenarios.scan_unsorted()
    StandardWorld()
    AddHighLevelFiller(400)
    W.AH.honorLevelSort = false
    W.AH.bidsIgnored = true              -- this server's rows show the cheapest buyout, never a bid
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("unsorted")
    local pages = math.ceil(#W.AH.rows / W.AH.pageSize)
    eq(W.AH.calls.more, pages - 1, "read every page when the server does not sort by level")
end

function scenarios.scan_async()
    StandardWorld()
    W.items["200:0"].cached = false      -- Good Chest arrives half a second later
    W.items["211:0"].cached = false      -- so does the Helm
    W.AddItem({ id = 300, name = "Ghost", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 70, level = 9, uncached = true })
    W.AddAuction(300, 100)
    W.neverLoad = { [300] = true }       -- and this one never loads
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("async")
    eq(Offer("Ghost"), nil, "an item the client never loads is left out, and the scan still ends")
end

function scenarios.scan_no_sample()
    StandardWorld()
    W.AH.sampleLinks = false             -- the client has no sample link for any row
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("no sample link")
    check(W.AH.calls.search > 6, "falls back to searching every candidate row")
end

function scenarios.scan_suffix_rows()
    StandardWorld()
    -- One browse row that hides three random-suffix variants of the same item.
    W.AH.bucketBySuffix = false
    W.AddItem({ id = 400, name = "Belt", equipLoc = "INVTYPE_WAIST", subClassID = 3, value = 1, level = 8 })
    W.AddItem({ id = 400, suffix = 7, name = "Belt of the Bear", equipLoc = "INVTYPE_WAIST", subClassID = 3, value = 9, level = 8 })
    W.AddItem({ id = 400, suffix = 8, name = "Belt of the Owl", equipLoc = "INVTYPE_WAIST", subClassID = 3, value = 0.2, level = 8 })
    W.AddAuction(400, 50, { suffix = 8 })       -- the cheapest one is the sample, and it is poor
    W.AddAuction(400, 900, { suffix = 7 })
    W.AddAuction(400, 700, { suffix = 7 })
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    local bear = Offer("Belt of the Bear")
    check(bear ~= nil, "the good variant is found behind a poor sample")
    eq(bear.buyout, 700, "cheapest of that variant"); eq(bear.count, 2, "two of that variant")
    local owl = Offer("Belt of the Owl")
    check(owl ~= nil and owl.buyout == 50, "the other variant is its own offer")
end

function scenarios.scan_varying_rows()
    StandardWorld()
    -- Two rows whose auctions are not all the same item although their keys say so. The first
    -- row gets searched because its sample is an upgrade; that search reveals the difference,
    -- and the scan then goes back to the second row, whose sample alone was not an upgrade.
    W.AH.bucketBySuffix = false
    W.AddItem({ id = 500, suffix = 0, name = "Cape", equipLoc = "INVTYPE_CLOAK", subClassID = 1, value = 5, level = 8 })
    W.AddItem({ id = 500, suffix = 3, name = "Cape of Power", equipLoc = "INVTYPE_CLOAK", subClassID = 1, value = 8, level = 8 })
    W.AddAuction(500, 100)
    W.AddAuction(500, 300, { suffix = 3 })
    W.equipped[8] = nil
    W.AddItem({ id = 510, name = "Old Boots", equipLoc = "INVTYPE_FEET", subClassID = 3, value = 15, level = 5 })
    W.equipped[8] = W.Link(510)
    W.AddItem({ id = 501, suffix = 0, name = "Boots", equipLoc = "INVTYPE_FEET", subClassID = 3, value = 6, level = 8 })
    W.AddItem({ id = 501, suffix = 4, name = "Boots of Speed", equipLoc = "INVTYPE_FEET", subClassID = 3, value = 21, level = 8 })
    W.AddAuction(501, 100)
    W.AddAuction(501, 400, { suffix = 4 })
    -- Make the sample link of each row the plain item, as if the key gave no hint of variants.
    local original = C_AuctionHouse.GetItemKeySampleLink
    C_AuctionHouse.GetItemKeySampleLink = function(key)
        if key.itemID == 500 or key.itemID == 501 then return W.Link(key.itemID, 0) end
        return original(key)
    end
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    check(Offer("Cape of Power") ~= nil, "variant in the searched row")
    check(Offer("Boots of Speed") ~= nil, "variant in a row that was first skipped")
    eq(Offer("Boots"), nil, "the plain boots are still not an upgrade")
end

function scenarios.scan_no_answer()
    StandardWorld()
    W.AH.answerBrowse = false
    LoadAddon()
    W.OpenAuctionHouse()
    check(ns.Scanner.Start(), "scan starts")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 120)
    eq(W.AH.calls.browse, 2, "tried the level-sorted search, then the plain one")
    eq(ns.Scanner.message, ns.L.ERR_BROWSE, "says the auction house did not answer")
    eq(OfferCount(), 0, "no offers")

    -- Closed auction house
    W.CloseAuctionHouse()
    eq(ns.Scanner.Start(), false, "cannot scan when closed")
    eq(ns.Scanner.message, ns.L.ERR_AH_CLOSED, "says to open it")
end

function scenarios.scan_interrupted()
    StandardWorld()
    AddHighLevelFiller(300)
    W.AH.honorLevelSort = false
    LoadAddon()
    W.OpenAuctionHouse()
    check(ns.Scanner.Start(), "scan starts")
    W.Run(0.5)
    eq(ns.Scanner.state, "browse", "still browsing")
    W.RunUntil(function() return W.AH.ready end, 5)
    C_AuctionHouse.SendBrowseQuery({ searchString = "x", sorts = {}, itemClassFilters = {} })   -- somebody else searches
    eq(ns.Scanner.state, "idle", "our scan stops")
    eq(ns.Scanner.message, ns.L.ST_INTERRUPTED, "and says why")

    -- A scan cut short by closing the window keeps what it found and is marked incomplete.
    W.RunUntil(function() return W.AH.ready end, 5)
    W.AH.honorLevelSort = true
    check(ns.Scanner.Start(), "second scan starts")
    W.RunUntil(function() return ns.Scanner.state == "verify" and OfferCount() >= 2 end, 60)
    W.CloseAuctionHouse()
    eq(ns.Scanner.state, "idle", "closing stops the scan")
    eq(ns.Scanner.halted, true, "marked as stopped during the price checks")
    check(OfferCount() >= 2, "offers found so far are kept")
end

---------------------------------------------------------------------------
-- A busy auction house: 150 items over six slots, one to three auctions each, so that most
-- offers in a slot are poor deals next to a few good ones. Some rows have a bid-only auction
-- (their lowest price then says nothing about buyouts), in some the cheapest auction is the
-- player's own.
local function BusyWorld()
    local seed = 20261113
    local function rnd(n)                       -- 1..n, the same numbers on every run
        seed = (seed * 16807) % 2147483647
        return seed % n + 1
    end
    W.AddItem({ id = 100, name = "Worn Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 10, level = 5 })
    W.equipped[5] = W.Link(100)
    local slots = { "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_WAIST" }
    for i = 1, 150 do
        local id = 2000 + i
        W.AddItem({ id = id, name = "Item " .. i, equipLoc = slots[rnd(#slots)], subClassID = 3, value = rnd(400) / 10, level = rnd(10) })
        local base = rnd(30000)
        for _ = 1, rnd(3) do
            W.AddAuction(id, base + rnd(2000))
        end
        local kind = rnd(10)
        if kind == 1 then
            W.AddAuction(id, 0)
        elseif kind == 2 then
            W.AddAuction(id, math.floor(base / 2), { own = true })
        end
    end
end

-- The scan looks up only the prices the list can show, and the list is the same as if it had
-- looked up all of them.
function scenarios.scan_lazy()
    BusyWorld()
    W.player.money = 15000
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner

    -- What the list shows, as text: slot blocks, offers with their prices, picks.
    local function Shown(affordableOnly, topOnly)
        local rows = ns.Results.Build(S.offers, S.ctx, {
            money = GetMoney(), affordableOnly = affordableOnly, limit = topOnly and ns.Results.TOP_COUNT or nil,
        })
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "header" then
                out[#out + 1] = "[" .. row.group .. "]"
            else
                local entry = row.entry
                out[#out + 1] = entry.offer.id .. "@" .. entry.offer.buyout .. (entry.pick and ("!" .. entry.pick) or "")
            end
        end
        return table.concat(out, " ")
    end
    local function Name(view) return "afford=" .. tostring(view[1]) .. " top=" .. tostring(view[2]) end
    local function Scan(view)
        SetView(view[1], view[2])
        W.RunUntil(function() return W.AH.ready end, 5)
        local before = W.AH.calls.search
        ScanToEnd()
        return W.AH.calls.search - before
    end

    -- Reference: both filters off, so every candidate's price is looked up.
    local all = Scan({ false, false })
    local offers = OfferCount()
    eq(S.stats.skipped, 0, "the reference scan skips nothing")
    eq(S.stats.checked, all, "statistics: every row read is counted")
    eq(S.stats.belowFloor, 0, "statistics: no row had a buyout below its lowest price")
    check(all >= 60, "enough candidates for the comparison to mean something (" .. all .. ")")
    local views = { { true, true }, { true, false }, { false, true }, { false, false } }
    local want = {}
    for _, view in ipairs(views) do want[Name(view)] = Shown(view[1], view[2]) end
    check(want["afford=true top=true"] ~= want["afford=true top=false"], "'top five' hides something in this world")
    check(want["afford=true top=true"] ~= want["afford=false top=true"], "so does the price filter")

    -- Scanned with a filter on, the list is the same and the searches are fewer.
    local used = {}
    for i = 1, 3 do
        local view = views[i]
        used[i] = Scan(view)
        eq(Shown(view[1], view[2]), want[Name(view)], "same list as the full scan with " .. Name(view))
        check(used[i] < all, "fewer item searches with " .. Name(view) .. " (" .. used[i] .. " of " .. all .. ")")
        eq(S.stats.searches + S.stats.skipped, S.stats.candidates, "every candidate is either searched or skipped, " .. Name(view))
    end
    check(used[1] * 3 <= all, "the list as it is by default needs under a third of the searches (" .. used[1] .. " of " .. all .. ")")

    -- Switching a filter off afterwards looks up only what is still missing.
    local first = Scan({ true, true })
    eq(first, used[1], "the same scan costs the same")
    eq(S.Demand(), false, "nothing more is needed for the list as it is")
    check(S.Unchecked().tooDear > 0, "rows that cost too much are counted without a search")
    local before = W.AH.calls.search
    SetView(true, false)
    eq(S.Demand(), true, "'top five' off: the offers it was hiding get their prices looked up")
    eq(S.mode, "more", "as a follow-up, not as a new scan")
    eq(S.Demand(), false, "one lookup run at a time")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(Shown(true, false), want["afford=true top=false"], "then the list matches the full scan")
    SetView(false, false)
    eq(S.Demand(), true, "price filter off: the rest follow")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(Shown(false, false), want["afford=false top=false"], "everything is listed")
    eq(OfferCount(), offers, "the same offers as the full scan")
    eq(first + W.AH.calls.search - before, all, "and in all each candidate was searched exactly once")
    eq(S.Demand(), false, "nothing left to look up")
    eq(S.Unchecked().tooDear, 0, "nothing left uncounted")
    eq(W.AH.calls.browse, 5, "five scans, five browse queries")
    realPrint(string.format("      item searches: %d with both filters off, %d by default, %d with only the price filter, %d with only top five",
        all, used[1], used[2], used[3]))
end

-- If the rows' lowest price turns out not to be a floor under their buyouts, the scan notices
-- and goes back to looking every price up.
function scenarios.scan_bad_floor()
    BusyWorld()
    W.player.money = 15000
    W.AH.minPriceFactor = 4
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local function Shown()
        local rows = ns.Results.Build(S.offers, S.ctx, { money = GetMoney(), affordableOnly = true, limit = ns.Results.TOP_COUNT })
        local out = {}
        for _, row in ipairs(rows) do
            out[#out + 1] = row.kind == "header" and row.group or (row.entry.offer.id .. "@" .. row.entry.offer.buyout)
        end
        return table.concat(out, " ")
    end
    SetView(false, false)
    ScanToEnd()
    local want, all = Shown(), W.AH.calls.search
    SetView(true, true)
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    check(S.stats.belowFloor >= 3, "buyouts below the rows' lowest price were noticed (" .. S.stats.belowFloor .. ")")
    eq(Shown(), want, "the list is still right")
    eq(W.AH.calls.search - all, all, "because every price was looked up after all")
    eq(S.Unchecked().tooDear, 0, "and nothing is counted as too dear on the strength of that number")
end

-- An item with more auctions than fit on one page of an item search.
function scenarios.scan_pages()
    W.AddItem({ id = 100, name = "Worn Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 10, level = 5 })
    W.equipped[5] = W.Link(100)
    W.AddItem({ id = 700, name = "Common Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 20, level = 8 })
    for i = 1, 120 do W.AddAuction(700, 1000 + i) end
    -- The same, but the cheapest one is the player's own auction.
    W.AddItem({ id = 701, name = "Common Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 9, level = 8 })
    W.AddAuction(701, 500, { own = true })
    for i = 1, 119 do W.AddAuction(701, 2000 + i) end
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    local chest, helm = Offer("Common Chest"), Offer("Common Helm")
    eq(chest.buyout, 1001, "cheapest chest"); eq(chest.more, true, "more of it for sale, not counted")
    eq(helm.buyout, 2001, "cheapest helm that is not the player's own")
    eq(helm.count, 119, "all of them counted"); eq(helm.more, nil, "read in full")
    eq(W.AH.calls.search, 2, "one item search each")
    eq(W.AH.calls.itemMore, 2, "the chest's first page settled its price; the helm took all three pages")
    eq(ns.Scanner.stats.pages, 2, "statistics: extra pages")

    -- Before a purchase, the first auction at the known price answers "is it still there".
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ns.Scanner.Buy(chest)
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(W.AH.calls.itemMore, 2, "no further pages for that lookup")
    eq(#W.popups, 1, "asks for confirmation")
    W.AcceptPopup(W.popups[1])
    W.RunUntil(function()
        local now = Offer("Common Chest")
        return ns.Scanner.state == "idle" and now ~= nil and now.buyout == 1002
    end, 60)
    eq(Offer("Common Chest").count, 119, "after the purchase the rest are read in full")
end

-- Price checks can be stopped and picked up again.
function scenarios.scan_halt()
    StandardWorld()
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    local S = ns.Scanner
    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "verify" and OfferCount() >= 2 end, 60)
    S.Stop("stopped")
    eq(S.state, "idle", "stopped")
    eq(S.halted, true, "the price checks are on hold"); eq(S.partial, false, "nothing was lost")
    check(OfferCount() < 6, "not every price was looked up")
    eq(S.Demand(), false, "no lookups while on hold")
    S.Resume()
    eq(S.message, nil, "the note about stopping is gone")
    eq(S.Demand(), true, "picked up again")
    W.RunUntil(function() return S.state == "idle" end, 120)
    CheckStandardOffers("resumed")
    eq(S.Demand(), false, "nothing left")

    -- A server that stops answering ends the price checks after three silent searches.
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "second scan starts")
    W.RunUntil(function() return S.state == "verify" and OfferCount() >= 1 end, 60)
    W.AH.dropSearches = 1000
    W.RunUntil(function() return S.state == "idle" end, 120)
    eq(S.message, ns.L.ERR_BROWSE, "says the auction house did not answer")
    eq(S.halted, true, "on hold"); eq(S.partial, true, "and marked incomplete")
    eq(S.stats.timeouts, 3, "statistics: three searches without an answer")
end

-- With "top 5" off every remaining price is looked up, so the status line can say how long
-- that will take.
function scenarios.scan_eta()
    BusyWorld()
    W.player.money = 15000
    LoadAddon()
    W.OpenAuctionHouse()
    W.Run(0.5)
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local S = ns.Scanner
    local function Status()
        for _, text in ipairs(W.texts) do
            local said = text:GetText()
            if said and said:find("Checking buyout prices", 1, true) then return said end
        end
        return ""
    end
    local function Close(guess, took, what)
        check(math.abs(guess - took) < took * 0.25, string.format("%s: said %.1f s, took %.1f s", what, guess, took))
    end

    eq(ns.Duration(3), "5 Sec", "short waits to the nearest five seconds, in the game's units")
    eq(ns.Duration(42), "40 Sec", "seconds")
    eq(ns.Duration(449), "7 Min", "minutes")
    eq(ns.Ago(7200), "2 Hr", "hours")

    -- The first scan ever has nothing to go by until a few searches have been timed.
    SetView(false, false)
    check(S.Start(), "scan starts")
    eq(S.TimeLeft(), nil, "no estimate before the price checks")
    W.RunUntil(function() return S.state == "verify" and S.info.toVerify > 0 end, 60)
    eq(S.TimeLeft(), nil, "nor before any search has been timed")
    check(Status():find("left", 1, true) == nil, "and the status line says nothing about it")
    W.RunUntil(function() return S.info.verified >= 10 end, 60)
    W.Run(0.2)
    local started, guess = W.now, S.TimeLeft()
    check(type(guess) == "number" and guess > 0, "an estimate once searches come back")
    check(Status():find(", about " .. ns.Duration(guess) .. " left", 1, true) ~= nil, "shown in the status line: " .. Status())
    W.RunUntil(function() return S.state == "idle" end, 600)
    Close(guess, W.now - started, "the estimate after ten searches")
    eq(S.TimeLeft(), nil, "nothing to estimate when idle")

    -- The next scan starts from the last one's pace.
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "second scan starts")
    W.RunUntil(function() return S.state == "verify" and S.info.toVerify > 0 end, 60)
    started, guess = W.now, S.TimeLeft()
    check(type(guess) == "number", "an estimate from the first search on")
    W.RunUntil(function() return S.state == "idle" end, 600)
    Close(guess, W.now - started, "the estimate at the start of the second scan")

    -- With "top 5" on most of the waiting candidates get ruled out on the way, so their number
    -- says nothing about the time left.
    SetView(false, true)
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "third scan starts")
    W.RunUntil(function() return S.state == "verify" and S.info.verified >= 3 end, 60)
    eq(S.TimeLeft(), nil, "no estimate with top five on")
    W.Run(0.2)
    check(Status():find("left", 1, true) == nil, "and none in the status line")
    W.RunUntil(function() return S.state == "idle" end, 600)
end

---------------------------------------------------------------------------
function scenarios.buy()
    StandardWorld()
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    local good = Offer("Good Chest")
    local searches = W.AH.calls.search

    -- The question is for a player who is looking at the list. If they left the tab while the
    -- item was being looked up, nothing pops up, and the scanner is free again.
    ns.Scanner.Buy(good)
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(#W.popups, 0, "no question away from the tab")
    W.RunUntil(function() return W.AH.ready end, 5)
    searches = W.AH.calls.search
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ns.Scanner.Buy(good)
    eq(ns.Scanner.state, "verify", "looks the item up again first")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(W.AH.calls.search, searches + 1, "one fresh item search")
    eq(#W.popups, 1, "asks for confirmation")
    local box = W.popups[1]
    eq(box.which, "UPGRADESCOUT_BUY", "our dialog")
    eq(StaticPopupDialogs.UPGRADESCOUT_BUY.text, "Buyout auction for:", "worded as the game's own buyout question")
    eq(box.data.link, good.link, "shows the item")
    eq(box.dialog.MoneyFrame._amount, 4000, "and the price as coins")
    eq(#W.AH.calls.bids, 0, "nothing bought before the player agrees")
    W.AcceptPopup(box)
    eq(#W.AH.calls.bids, 1, "bought")
    eq(W.AH.calls.bids[1].amount, 4000, "at the buyout price")
    eq(box.shown, true, "the box waits for the auction house to answer")
    W.RunUntil(function() return not box.shown end, 5)
    W.RunUntil(function() return ns.Scanner.state == "idle" and Offer("Good Chest") ~= nil and Offer("Good Chest").buyout == 5000 end, 30)
    eq(Offer("Good Chest").count, 1, "the next copy is listed at its own price")
    check(W.printed[#W.printed]:find("Bought", 1, true) ~= nil, "purchase reported in chat")

    -- Too expensive
    W.player.money = 10
    local count = #W.popups
    ns.Scanner.Buy(Offer("Great Chest"))
    eq(#W.popups, count, "no dialog when the player cannot pay")
    eq(ns.Scanner.state, "idle", "and no search")
end

function scenarios.buy_gone()
    StandardWorld()
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    -- Someone buys the helm, and the cheap Good Chest, between the scan and the click.
    for i = #W.AH.auctions, 1, -1 do
        local a = W.AH.auctions[i]
        if a.id == 211 or (a.id == 200 and a.buyout == 4000) then table.remove(W.AH.auctions, i) end
    end
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ns.Scanner.Buy(Offer("Helm"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(#W.popups, 0, "no dialog for an item that is gone")
    eq(Offer("Helm"), nil, "and it leaves the list")
    check(W.printed[#W.printed]:find("no longer for sale", 1, true) ~= nil, "says it is gone")

    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(#W.popups, 0, "no dialog when the price changed")
    eq(Offer("Good Chest").buyout, 5000, "list shows the new price")
    check(W.printed[#W.printed]:find("now costs", 1, true) ~= nil, "says the price changed")

    -- The server never answers the lookup.
    W.AH.dropSearches = 5
    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 60)
    eq(#W.popups, 0, "no dialog without an answer")
end

---------------------------------------------------------------------------
function scenarios.ui()
    local PAGE, ROW = 14, 30             -- rows in view and the height of one (see W.listHeight)
    StandardWorld()
    W.player.money = 50000               -- 5 gold: the 9 gold robe is out of reach
    LoadAddon()
    eq(UpgradeScoutFrame, nil, "nothing is built before the game has its auction window")
    W.OpenAuctionHouse()
    local frame = UpgradeScoutFrame
    check(frame ~= nil, "the tab is built the moment the auction window loads")
    local lib = LibStub("LibAHTab-1-0")
    check(lib:DoesIDExist("UpgradeScout"), "tab registered")
    eq(lib:GetButton("UpgradeScout"):GetText(), "Upgrades", "tab text")
    eq(frame:IsShown(), false, "hidden until the tab is clicked")
    lib:SetSelected("UpgradeScout")
    eq(frame:IsShown(), true, "shown when selected")

    -- The tab's own parts are on its frame by name; what the game provides is found by the
    -- template it is made from.
    local function Made(template)
        local out = {}
        for _, w in ipairs(W.frames) do
            if w._template == template then out[#out + 1] = w end
        end
        return out
    end
    -- The name of a texture's file, without its folder.
    local function Art(texture) return texture:GetTexture():match("[^\\]+$") end
    local list, scan = frame.List, frame.ScanButton
    eq(scan.Label:GetText(), "SCAN", "the scan button, in capitals like every heading")
    eq(scan.Face.file, "ButtonRed", "red: the one button that matters")
    check(Art(scan.Face.parts[1]):find("ButtonRed", 1, true) ~= nil and scan.Face.parts[1]:GetTexture():find("AddOns\\UpgradeScout\\Media\\", 1, true) ~= nil,
        "drawn with the addon's own art")

    -- Before the first scan the middle of the list says what the tab is for.
    eq(list.Intro:IsShown(), true, "the emblem before the first scan")
    check(list.Hint:GetText():find("Press Scan", 1, true) ~= nil and list.Hint:GetText():find("\"Arms\"", 1, true) ~= nil,
        "with what to do and the scale it will use: " .. list.Hint:GetText())
    eq(list.Progress:IsShown(), false, "no progress bar before a scan")
    eq(frame.Progress:IsShown(), false, "nor beside the status line")
    local sounds = #W.sounds
    scan:Click()
    eq(#W.sounds, sounds + 1, "the button clicks")
    eq(ns.Scanner.state, "browse", "the button starts a scan")
    eq(list.Intro:IsShown(), false, "the emblem goes")
    eq(list.Progress:IsShown(), true, "a bar in the middle of the list while it is empty")
    eq(frame.Progress:IsShown(), true, "and a small one beside the status line")
    eq(list.Progress.value, nil, "reading the auction list has no known end: the gold goes to and fro")
    check(list.Progress:GetScript("OnUpdate") ~= nil, "moved by the clock")
    check(list.Hint:GetText():find("Reading the auction list", 1, true) ~= nil, "the status stands over the bar")
    W.Run(0.2)
    eq(scan.Label:GetText(), "STOP", "and the button turns into Stop")
    eq(scan.Face.file, "ButtonDark", "in the dark face")
    W.RunUntil(function() return ns.Scanner.state == "verify" and ns.Scanner.info.verified >= 2 end, 120)
    W.Run(0.2)
    local filled = frame.Progress.value
    check(type(filled) == "number" and filled > 0 and filled <= 1, "the bar fills as prices are checked")
    eq(frame.Progress:GetScript("OnUpdate"), nil, "and stands still at what is done")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 120)
    W.Run(0.3)
    eq(scan.Label:GetText(), "SCAN", "back to Scan")
    eq(scan.Face.file, "ButtonRed", "and to red")
    eq(list.Progress:IsShown(), false, "the bar in the list goes once there is a list")
    eq(frame.Progress:IsShown(), false, "the one beside the status line goes with the scan")
    eq(list.Hint:GetText(), "", "nothing is written over a list with rows")

    -- Column titles: words in capitals, nothing to click, the list having one order.
    eq(#list.Titles, 5, "a title for every column")
    eq(list.Titles[1]:GetText(), "ITEM", "first column"); eq(list.Titles[4]:GetText(), "BUYOUT", "price column")

    -- Read the list as the player would.
    local box = Made("WowScrollBoxList")[1]
    check(box ~= nil, "the list is the game's scroll box")
    local function Rows()
        local out = {}
        for _, w in ipairs(box:GetFrames()) do
            if w._shown then out[#out + 1] = w end
        end
        return out
    end
    local function Data(row) return row:GetElementData().data end
    local rows = Rows()
    eq(Data(rows[1]).kind, "header", "first row is a slot header"); eq(rows[1].Title:GetText(), "HEAD", "head first, in capitals")
    eq(rows[1]._kind, "Frame", "a heading is a frame of its own kind")
    eq(rows[1].Toggle._kind, "Button", "under a button that folds the slot away")
    eq(Art(rows[1].Arrow), "Chevron", "its arrow points down: the slot is open")
    eq(rows[2]._kind, "Button", "an offer is a button")
    eq(rows[2].Name:GetText(), "|cff1eff00Helm|r", "item name in quality colour")
    eq(rows[2].Upgrade:GetText(), "+12", "the gain"); eq(rows[2].Share:GetText(), "new", "an empty slot shown as new")
    eq(rows[2].Pick:IsShown(), true, "a plate for the pick"); eq(rows[2].Pick.Text:GetText(), "Best of both", "single offer is both picks")
    eq(rows[2].Buy.Label:GetText(), "BUY", "the buy button")
    eq(rows[2].Price._template, "MoneyDisplayFrameTemplate", "the price is the game's coin display")
    eq(rows[2].Price:GetAmount(), 2500, "25 silver")
    eq(rows[2].Price._font, PriceFontWhite, "in white: the player can pay")
    eq(rows[2].PerPoint:GetAmount(), 208, "price per point, in whole copper")
    eq(rows[2].Buy:IsEnabled(), true, "can buy")
    eq(rows[3].Title:GetText(), "CHEST", "chest block")
    eq(rows[4].Name:GetText(), "|cff1eff00Good Chest|r", "the robe is hidden: too expensive")
    eq(rows[4].Upgrade:GetText(), "+8", "delta"); eq(rows[4].Share:GetText(), "+80%", "and percent")

    -- Weapon rows say how the weapon is held; the hand slots mix one-hand and two-hand items.
    local function RowNamed(text)
        for _, row in ipairs(rows) do
            if Data(row).kind == "item" and row.Name:GetText():find(text, 1, true) then return row end
        end
    end
    local axe, shield = RowNamed("Big Axe"), RowNamed("Shield")
    check(axe ~= nil and shield ~= nil, "the two-hander and the shield are listed")
    local nameWidth = rows[2].Name:GetWidth()
    check(nameWidth > 200, "armor keeps the whole name column")
    eq(rows[2].Hand:IsShown(), false, "and has no label")
    eq(axe.Hand:IsShown(), true, "a weapon row has a label")
    eq(axe.Hand:GetText(), "Two-Hand (game)", "in the game's own words")
    eq(axe.Name:GetWidth(), nameWidth - #"Two-Hand (game)" * 6 - 8, "and its name makes room for it")
    eq(shield.Hand:GetText(), "Off Hand", "the addon's words where the game has none")
    eq(ns.Compare.HandLabel("INVTYPE_WEAPON"), "One-Hand", "one-hand weapons are named too")
    eq(ns.Compare.HandLabel("INVTYPE_CHEST"), nil, "nothing for armor")

    -- The two filters: tick boxes with their labels beside them.
    local checkbox, topBox = frame.AffordCheck, frame.TopCheck
    eq(checkbox._kind, "CheckButton", "a filter is a tick box")
    eq(checkbox.Text:GetText(), "Only what I can afford", "the price filter"); eq(topBox.Text:GetText(), "Top 5 per slot", "and top five")
    eq(topBox:GetChecked(), true, "top five on by default"); eq(topBox.Tick:IsShown(), true, "with its tick showing")
    eq(rows[3].Count:GetText(), "", "nothing cut, so no count in the header")
    eq(checkbox:GetChecked(), true, "afford filter on by default")
    local function Status()
        for _, text in ipairs(W.texts) do
            local said = text:GetText()
            if said and (said:find("Scanned", 1, true) or said:find("Checking", 1, true)) then return said end
        end
        return ""
    end
    -- Helm, Good Chest, New Ring, Big Axe and Shield are listed; the robe costs 9 gold.
    check(Status():find("5 upgrades in 5 slots. 1 more cost more than you have.", 1, true) ~= nil, "status counts the robe that was not looked up: " .. Status())
    check(Status():find("Sec ago", 1, true) ~= nil, "the age of the scan in the game's units: " .. Status())
    -- The age goes on counting while the tab is only looked at: no event comes with a second.
    local finished = ns.Scanner.finishedAt
    W.Run(7)
    check(time() - finished >= 7, "seven seconds on")
    check(Status():find("Scanned " .. ns.Ago(time() - finished) .. " ago.", 1, true) ~= nil, "the age keeps up with the clock: " .. Status())
    W.Run(120, 0.5)
    check(Status():find("Scanned 2 Min ago.", 1, true) ~= nil, "and goes on to minutes: " .. Status())
    -- Not while the tab is out of view.
    frame:Hide()
    local said = Status()
    W.Run(60, 0.5)
    eq(Status(), said, "nothing is written while the tab is hidden")
    frame:Show()
    check(Status():find("Scanned 3 Min ago.", 1, true) ~= nil, "the age is right again when the tab comes back: " .. Status())

    -- Showing everything brings the robe back, marked as too expensive.
    local searches = W.AH.calls.search
    sounds = #W.sounds
    checkbox:SetChecked(false)
    checkbox:Click()
    eq(W.sounds[#W.sounds], SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "unticking sounds like unticking")
    eq(#W.sounds, sounds + 1, "once")
    eq(ns.db.affordableOnly, false, "setting saved")
    eq(checkbox.Tick:IsShown(), false, "the tick is gone")
    -- The robe's price was not looked up while it was hidden; now it is.
    eq(ns.Scanner.mode, "more", "the list asks for the missing price")
    W.Run(0.2)
    check(Status():find("Checking buyout prices", 1, true) ~= nil, "and says so")
    eq(scan.Label:GetText(), "STOP", "the lookup can be stopped")
    eq(frame.Progress:IsShown(), true, "its bar is beside the status line")
    eq(list.Progress:IsShown(), false, "and not over the list, which has rows")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    W.Run(0.3)
    eq(W.AH.calls.search, searches + 1, "one item search, for the robe")
    rows = Rows()
    eq(rows[4].Name:GetText(), "|cff1eff00Great Chest|r |cffffd100*|r", "robe listed first, with the effects mark")
    eq(rows[4].Price:GetAmount(), 90000, "its price")
    eq(rows[4].Price._font, PriceFontRed, "in red")
    eq(rows[4].Buy:IsEnabled(), false, "cannot buy it")
    eq(rows[4].Pick.Text:GetText(), "Best upgrade", "robe is the best upgrade")
    eq(rows[5].Pick.Text:GetText(), "Best value", "Good Chest is the best value")
    -- The meter under a gain measures it against the best one in the slot: +8 against +20.
    near(rows[5].Meter:GetWidth() / rows[4].Meter:GetWidth(), 8 / 20, "the meter of the smaller gain is shorter by as much")

    -- Tooltip
    rows[5]:GetScript("OnEnter")(rows[5])
    local seen = {}
    for _, line in ipairs(GameTooltip._lines) do seen[#seen + 1] = line.text end
    local tip = table.concat(seen, "\n")
    check(tip:find("Pawn score: 18, yours: 10 (+8)", 1, true) ~= nil, "tooltip score line")
    check(tip:find("Replaces: ", 1, true) ~= nil and tip:find("Cost per point: 5s", 1, true) ~= nil, "tooltip replaces and cost")
    check(tip:find("1 more for sale", 1, true) ~= nil, "tooltip count")
    eq(W.compared, GameTooltip, "worn item shown for comparison")
    eq(rows[5].UpdateTooltip ~= nil, true, "the game can redraw the tooltip while it is up")
    -- With the try-on key held the cursor says what a click would do.
    W.modified = "DRESSUP"
    rows[5]:GetScript("OnUpdate")(rows[5])
    eq(W.cursor, "inspect", "magnifying glass while the try-on key is held")
    W.modified = false
    rows[5]:GetScript("OnUpdate")(rows[5])
    eq(W.cursor, nil, "and the plain cursor without it")

    -- Buy button -> the question; leaving the tab takes the question down.
    rows[5].Buy:Click()
    W.RunUntil(function() return #W.popups == 1 end, 30)
    eq(W.popups[1].data.offer.name, "Good Chest", "confirmation for the clicked item")
    eq(W.popups[1].shown, true, "the question is up")
    frame:Hide()
    eq(W.popups[1].shown, false, "it does not outlive the tab")
    frame:Show()

    -- Shift-click links the item; a plain click does nothing.
    rows = Rows()
    rows[5]:Click()
    eq(W.linked, nil, "a plain click on a row does nothing")
    W.modified = true
    rows[5]:Click()
    check(W.linked and W.linked:find("Good Chest", 1, true), "a modified click hands the link to the game")
    W.modified = false

    -- The scale: one of the game's dropdowns. Choosing another scale rescans with it.
    local dropdown = Made("WowStyle1DropdownTemplate")[1]
    check(dropdown ~= nil, "the scale is chosen in a dropdown")
    eq(dropdown:GetText(), "Arms", "which shows the scale in use")
    eq(#dropdown.radios, 2, "and offers only the scales Pawn shows for this character")
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(2)
    eq(ns.db.scale, "S2", "choice saved")
    eq(ns.Scanner.state, "browse", "rescans")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 120)
    W.Run(0.3)
    eq(dropdown:GetText(), "Protection", "the dropdown shows the new scale")
    eq(OfferCount(), 0, "nothing scores on a scale that values none of it")

    -- Scrolling a long list
    ns.db.scale = "S1"
    for i = 1, 40 do
        W.AddItem({ id = 900 + i, name = "Legs " .. i, equipLoc = "INVTYPE_LEGS", subClassID = 3, value = i, level = 5 })
        W.AddAuction(900 + i, i * i)     -- i copper per point: weaker legs are cheaper per point
    end
    -- Weaker than Legs 40 and far dearer per point: "top five" never shows it.
    W.AddItem({ id = 990, name = "Poor Deal Legs", equipLoc = "INVTYPE_LEGS", subClassID = 3, value = 20, level = 5 })
    W.AddAuction(990, 5000)
    ns.Scanner.offers, ns.Scanner.ctx, ns.Scanner.finishedAt = {}, nil, nil
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.3)
    eq(dropdown:GetText(), "Arms", "the dropdown follows a scale changed elsewhere")

    -- Top five: the forty legs shrink to five, and the header says how many there are.
    -- Best upgrade (40) and two steps down, best value (10: the cheapest per point that gives
    -- at least a quarter of +40) and one step down.
    local legs
    rows = Rows()
    for i, row in ipairs(rows) do
        if Data(row).kind == "header" and Data(row).group == "LEGS" then legs = i end
    end
    eq(rows[legs].Title:GetText(), "LEGS", "the legs block")
    eq(rows[legs].Count:GetText(), "5 of about 41", "its header counts the cut and the one not looked up")
    eq(Offer("Poor Deal Legs"), nil, "no item search for an offer the list would hide")
    eq(rows[legs + 1].Name:GetText(), "|cff1eff00Legs 40|r", "best legs first")
    eq(rows[legs + 3].Name:GetText(), "|cff1eff00Legs 38|r", "two steps below the best")
    eq(rows[legs + 4].Name:GetText(), "|cff1eff00Legs 10|r", "best value")
    eq(rows[legs + 4].Pick.Text:GetText(), "Best value", "marked as best value")
    eq(rows[legs + 3].Pick:IsShown(), false, "no plate on a row that is neither pick")
    eq(rows[legs + 4].PerPoint:GetAmount(), 10, "ten copper a point")
    eq(rows[legs + 5].Name:GetText(), "|cff1eff00Legs 9|r", "one step below the best value")
    check(rows[legs + 6] == nil or Data(rows[legs + 6]).kind == "header", "no sixth legs row")
    topBox:GetScript("OnEnter")(topBox)
    eq(GameTooltip._lines[1].text, "Top 5 per slot", "the filter's tooltip is titled with its label")
    check(GameTooltip._lines[2].text:find("Up to 5 options", 1, true) ~= nil, "and explains it")
    topBox:GetScript("OnLeave")(topBox)

    -- Unticked, everything is listed again.
    topBox:SetChecked(false)
    topBox:Click()
    eq(ns.db.topOnly, false, "top five setting saved")
    W.RunUntil(function() return ns.Scanner.state == "idle" and Offer("Poor Deal Legs") ~= nil end, 30)
    W.Run(0.3)
    rows = Rows()
    eq(rows[legs].Count:GetText(), "", "everything listed, nothing left to count")
    eq(#rows, PAGE, "a full page of rows")

    -- Scrolling is the scroll box's own; the bar beside it is the game's too.
    local bar = Made("MinimalScrollBar")[1]
    check(bar ~= nil, "the list has the game's scroll bar")
    local all = ns.Results.Build(ns.Scanner.offers, ns.Scanner.ctx, { money = GetMoney(), affordableOnly = ns.db.affordableOnly })
    local scrollable = #all - PAGE
    check(scrollable > 20, "a long list (" .. #all .. " rows)")
    near(bar:GetVisibleExtentPercentage(), PAGE / #all, "the bar knows how much of the list is in view")
    eq(bar:GetScrollPercentage(), 0, "and starts at the top")
    local function Same(row, wanted)
        local have = Data(row)
        if wanted.kind == "header" then return have.kind == "header" and have.group == wanted.group end
        return have.kind == "item" and have.entry.offer.id == wanted.entry.offer.id
    end
    for i = 1, PAGE do check(Same(rows[i], all[i]), "row " .. i .. " is in its place") end
    box:OnMouseWheel(-1)
    check(Same(Rows()[1], all[3]), "the mouse wheel moves two rows")
    near(bar:GetScrollPercentage(), 2 / scrollable, "and the bar follows")
    bar:ClickArrow(1)
    check(Same(Rows()[1], all[4]), "an arrow moves one row")
    bar:ClickArrow(-1)
    box:OnMouseWheel(1)
    check(Same(Rows()[1], all[1]), "and back to the top")
    bar:Drag(1)
    rows = Rows()
    check(Same(rows[#rows], all[#all]), "dragging the thumb to the end shows the last row")
    bar:Drag(0)

    -- A refresh leaves the rows in view alone: same frames, nothing made or let go. This is
    -- what keeps the tooltip of the row under the mouse up while a scan refreshes the list.
    local stats = W.scrollBoxStats
    rows = Rows()
    rows[2]:GetScript("OnEnter")(rows[2])
    check(GameTooltip:IsOwned(rows[2]), "tooltip of the hovered row")
    local acquired, released = stats.acquired, stats.released
    ns.UI.Refresh()
    local now = Rows()
    for i = 1, #rows do check(now[i] == rows[i], "row " .. i .. " kept its frame over a refresh") end
    eq(stats.acquired, acquired, "no frame was made")
    eq(stats.released, released, "and none let go")
    check(GameTooltip:IsOwned(rows[2]) and GameTooltip:IsShown(), "the tooltip is still up")

    -- An offer in the middle of the page sells: the rows above keep their frames, the one row
    -- leaves, one comes into view at the bottom.
    local k                                     -- an item row with another item row below it
    for i = 4, 12 do
        if not k and Data(rows[i]).kind == "item" and Data(rows[i + 1]).kind == "item" then k = i end
    end
    check(k ~= nil, "two item rows in a row on the page")
    local gone = Data(rows[k]).entry.offer
    local belowID = Data(rows[k + 1]).entry.offer.id
    ns.Scanner.offers[gone.id] = nil
    ns.UI.Refresh()
    now = Rows()
    for i = 1, k - 1 do check(now[i] == rows[i], "row " .. i .. " above it kept its frame") end
    check(now[k] == rows[k + 1] and Data(now[k]).entry.offer.id == belowID, "the row below moved up, frame and all")
    eq(stats.released - released, 1, "one frame let go")
    eq(stats.acquired - acquired, 1, "one made for the row that came into view")
    eq(#now, PAGE, "the page is full again")
    check(GameTooltip:IsOwned(rows[2]) and GameTooltip:IsShown(), "the hovered row was not touched")
    ns.Scanner.offers[gone.id] = gone
    ns.UI.Refresh()
    eq(Data(Rows()[k]).entry.offer.id, gone.id, "and it comes back in its place")

    -- A row that is taken away while the mouse is on it takes its tooltip with it.
    rows = Rows()
    rows[2]:GetScript("OnLeave")(rows[2])
    eq(GameTooltip:IsShown(), false, "the tooltip goes when the mouse leaves")
    rows[2]:GetScript("OnEnter")(rows[2])
    box:OnMouseWheel(-1)
    eq(GameTooltip:IsShown(), false, "and when its row scrolls out of view")

    -- Scrolled down, the list stays where it is in pixels when a row above the page goes.
    box:OnMouseWheel(-1)
    local size = #Rows()
    near(box:GetScrollPercentage() * (#all - PAGE) * ROW, 4 * ROW, "four rows down")
    local first = nil
    for _, offer in pairs(ns.Scanner.offers) do
        if offer.id == all[2].entry.offer.id then first = offer end
    end
    check(first ~= nil, "the first offer of the list, now above the page")
    ns.Scanner.offers[first.id] = nil
    ns.UI.Refresh()
    local shorter = ns.Results.Build(ns.Scanner.offers, ns.Scanner.ctx, { money = GetMoney(), affordableOnly = ns.db.affordableOnly })
    check(#shorter < #all, "the list got shorter")
    near(box:GetScrollPercentage() * (#shorter - PAGE) * ROW, 4 * ROW, "still four rows down, in the shorter list")
    eq(#Rows(), size, "with a full page")
    ns.Scanner.offers[first.id] = first
    ns.UI.Refresh()
    bar:Drag(0)

    -- A click on a slot's heading folds the slot away: the heading stays, its offers go.
    rows = Rows()
    local heading = rows[legs]
    sounds = #W.sounds
    heading.Toggle:Click()
    eq(#W.sounds, sounds + 1, "the heading clicks")
    eq(ns.db.collapsed.LEGS, true, "folded, and kept with the character's settings")
    eq(UpgradeScoutCharDB.collapsed.LEGS, true, "which are the saved ones")
    rows = Rows()
    check(rows[legs] == heading, "the heading keeps its frame")
    eq(Art(heading.Arrow), "ChevronRight", "its arrow points to the side")
    eq(heading.Count:GetText(), "41", "and it says how many upgrades are folded away")
    eq(Data(rows[legs + 1]).kind, "header", "the next slot follows at once")
    for _, row in ipairs(rows) do
        check(not (Data(row).kind == "item" and Data(row).entry.group == "LEGS"), "no legs are listed")
    end
    check(Status():find("upgrades in 6 slots", 1, true) ~= nil, "the status line counts a folded slot as before: " .. Status())
    -- What is left is a short list with nothing to scroll: the bar shows no thumb.
    eq(bar:GetVisibleExtentPercentage(), 1, "everything in view")
    -- A refresh leaves the slot folded.
    ns.UI.Refresh()
    eq(Data(Rows()[legs + 1]).kind, "header", "still folded after a refresh")
    -- Another click brings the slot back.
    heading.Toggle:Click()
    eq(ns.db.collapsed.LEGS, nil, "unfolded")
    rows = Rows()
    eq(Art(heading.Arrow), "Chevron", "the arrow points down again")
    eq(heading.Count:GetText(), "", "nothing to count")
    eq(Data(rows[legs + 1]).kind, "item", "the legs are back")
    eq(#rows, PAGE, "and the page is full")

    -- A filter change starts the list from the top.
    box:OnMouseWheel(-1)
    topBox:SetChecked(true)
    topBox:Click()
    W.Run(0.3)
    eq(box:GetScrollPercentage(), 0, "at the top")
    topBox:SetChecked(false)
    topBox:Click()
    W.Run(0.3)
    eq(box:GetScrollPercentage(), 0, "the long list starts from the top too")
    eq(#Rows(), PAGE, "and fills the page")

    -- Slash command
    SlashCmdList.UPGRADESCOUT("")
    eq(frame:IsShown(), true, "/upscout shows the tab")
    W.CloseAuctionHouse()
    local printed = #W.printed
    SlashCmdList.UPGRADESCOUT("")
    eq(#W.printed, printed + 1, "/upscout away from the auction house explains itself")
end

---------------------------------------------------------------------------
function scenarios.pawn_missing()
    StandardWorld()
    LoadAddon()
    W.OpenAuctionHouse()
    W.pawnReady = false
    eq(ns.Scanner.Start(), false, "no scan while Pawn is loading")
    eq(ns.Scanner.message, ns.L.ERR_PAWN_NOT_READY, "says so")
    W.pawnReady = true
    local saved = PawnGetSingleValueFromItem
    PawnGetSingleValueFromItem = nil
    eq(ns.Scanner.Start(), false, "no scan when a Pawn function is gone")
    check(ns.Scanner.message:find("PawnGetSingleValueFromItem", 1, true) ~= nil, "names the missing function")
    PawnGetSingleValueFromItem = saved
    local savedScales = PawnGetAllScalesEx
    PawnGetAllScalesEx = function() return { { Name = "S3", LocalizedName = "Hidden", IsVisible = false } } end
    eq(ns.Scanner.Start(), false, "no scan without an active scale")
    eq(ns.Scanner.message, ns.L.ERR_NO_SCALE, "says to enable one")
    PawnGetAllScalesEx = savedScales
    check(ns.Scanner.Start(), "scans once Pawn is in order")
end

-- A translation loads, and a scan works with it. `scan` is its text for the Scan button.
local function CheckLocale(locale, language, scan)
    W.locale = locale
    StandardWorld()
    LoadAddon()
    eq(ns.L.SCAN, scan, language .. " strings load")
    eq(ns.L.NOT_A_KEY, "NOT_A_KEY", "unknown keys fall back to the key")
    -- Every English key has a translated text, and format placeholders match.
    W.locale = "enUS"
    local chunk = assert(loadfile(ADDON_DIR .. "Locale.lua"))
    local enNs = {}
    chunk("UpgradeScout", enNs)
    for key, text in pairs(enNs.L) do
        local translated = rawget(ns.L, key)
        check(translated ~= nil, language .. " text for " .. key)
        local function Slots(s) local n = 0 for _ in s:gmatch("%%[sd]") do n = n + 1 end return n end
        eq(Slots(translated), Slots(text), "placeholders in " .. key)
    end
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers(locale)
end

function scenarios.locale_ru()
    CheckLocale("ruRU", "Russian", "Скан")
end

function scenarios.locale_de()
    CheckLocale("deDE", "German", "Scannen")
end

function scenarios.locale_fr()
    CheckLocale("frFR", "French", "Scanner")
end

function scenarios.locale_zh()
    CheckLocale("zhCN", "Simplified Chinese", "扫描")
end

function scenarios.locale_pt()
    CheckLocale("ptBR", "Brazilian Portuguese", "Escanear")
end

function scenarios.locale_es()
    CheckLocale("esES", "Spanish", "Escanear")
end

-- The Latin American client reports its own locale and gets the same Spanish text.
function scenarios.locale_mx()
    CheckLocale("esMX", "Latin American Spanish", "Escanear")
end

function scenarios.locale_it()
    CheckLocale("itIT", "Italian", "Scansiona")
end

---------------------------------------------------------------------------
local fn = scenarios[scenario]
if not fn then
    realPrint("unknown scenario: " .. tostring(scenario))
    os.exit(2)
end
local ok, err = xpcall(fn, debug.traceback)
if ok then
    realPrint(string.format("ok    %-20s %d checks", scenario, checks))
    os.exit(0)
else
    realPrint(string.format("FAIL  %-20s after %d checks", scenario, checks))
    realPrint(err)
    os.exit(1)
end
