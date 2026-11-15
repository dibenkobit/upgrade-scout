-- Runs Upgrade Scout against the stand-in client in tests/wow.lua.
--   lua5.1 tests/run.lua            every scenario, each in its own process
--   lua5.1 tests/run.lua <name>     one scenario
-- Run from the project folder (the one that contains UpgradeScout/ and tests/).
local realPrint = print
local scenario = arg[1]
local ADDON_DIR = "UpgradeScout/"

local names = {
    "events", "compare", "picks", "scan_sorted", "scan_order", "scan_unsorted", "scan_async", "scan_no_sample",
    "scan_suffix_rows", "scan_varying_rows", "scan_no_answer", "scan_interrupted",
    "scan_lazy", "scan_bad_floor", "scan_pages", "scan_halt", "scan_unanswered", "scan_pieces", "scan_eta",
    "buy", "buy_gone", "plan", "plan_ui", "net", "net_ui", "supplies", "supplies_scan", "supplies_buy", "supplies_ui", "ui", "fonts", "tooltips", "arrows",
    "roster", "roster_order", "alt", "mail", "worn_loading", "profiles", "weights_data", "item_stats", "locale_ru", "locale_de", "locale_fr", "locale_zh",
    "locale_pt", "locale_es", "locale_mx", "locale_ko", "locale_tw",
    "talents", "welcome", "minimap",
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

-- The profiles the tests score on, in place of the addon's own (Weights.lua). An item of the
-- stand-in client has a stat named after each profile it was given a score on (see
-- C_Item.GetItemStats in wow.lua), and a profile weighs its own at 1. The other weights are
-- for what a consumable adds.
local function TestWeights()
    return {
        source = "a simulator (a day)", APPROX_MARK = "~",
        classes = { WARRIOR = { "S1", "S2" }, DRUID = { "D1", "D2" }, MAGE = { "M1" } },
        start = { WARRIOR = "S1", DRUID = "D1", MAGE = "M1" },
        titles = { enUS = { S1 = "Arms", S2 = "Protection", D1 = "Balance", D2 = "Feral", M1 = "Frost" } },
        profiles = {
            S1 = { class = "WARRIOR", mh = 2, oh = 1, ranged = 0, weights = { TEST_S1 = 1, ITEM_MOD_STRENGTH_SHORT = 1.5,
                ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 0.5, ITEM_MOD_ATTACK_POWER_SHORT = 0.4,
                ITEM_MOD_CRIT_RATING_SHORT = 8, ITEM_MOD_HEALTH_SHORT = 0.05 } },
            S2 = { class = "WARRIOR", approx = true, weights = { TEST_S2 = 1, ITEM_MOD_INTELLECT_SHORT = 1,
                ITEM_MOD_STAMINA_SHORT = 0.5, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 0.8 } },
            D1 = { class = "DRUID", weights = { TEST_D1 = 1, ITEM_MOD_INTELLECT_SHORT = 1 } },
            D2 = { class = "DRUID", weights = { TEST_D2 = 1, ITEM_MOD_AGILITY_SHORT = 1 } },
            M1 = { class = "MAGE", weights = { TEST_M1 = 1, ITEM_MOD_INTELLECT_SHORT = 1 } },
        },
    }
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
    ns.Weights = TestWeights()
    -- No item of the stand-in client is in the game's tables: each is "newer" than them.
    ns.GearData = { newest = 0, extra = {}, effects = {} }
    W.AddOnLoaded("UpgradeScout")
end

-- The character being played logs out and another one of the account logs in: a new session
-- of the addon, with the account's saved variables as the last one left them.
--   player, equipped   as W.player and W.equipped
local function Relog(player, equipped)
    W.Logout()
    W.Login(player, equipped)
    ns = {}
    LoadAddon()
    -- The addon writes the character down a moment after it comes into the world.
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
end

local function Offer(name)
    for _, offer in pairs(ns.Scanner.offers) do
        if offer.name == name then return offer end
    end
end

-- How many of the textures made on a frame show this picture of the addon's.
local function Pictures(frame, name)
    local n = 0
    for _, texture in ipairs(frame._textures or {}) do
        if (texture:GetTexture() or ""):match("[^\\]+$") == name then n = n + 1 end
    end
    return n
end

-- The box that asks before a purchase of gear, while it is up.
local function Asking()
    local box = UpgradeScoutBuyBox
    if box and box:IsShown() and box.offer then return box end
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
    near(good.value, 18, label .. ": scored by its own stats")
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
    eq(Offer("Statless Chest"), nil, label .. ": no stats, nothing to score")
    eq(OfferCount(), 6, label .. ": offer count")
end

local scenarios = {}

---------------------------------------------------------------------------
-- A handler that fails is reported, and the handlers after it still hear what was said.
function scenarios.events()
    LoadAddon()
    local heard = {}
    ns.On("PLAYER_MONEY", function() error("a handler of a game event that fails") end)
    ns.On("PLAYER_MONEY", function() heard[#heard + 1] = "money" end)
    W.Fire("PLAYER_MONEY")
    eq(heard[1], "money", "the next handler of the game's event still runs")
    eq(#W.errors, 1, "and the error is reported")
    check(W.errors[1]:find("a handler of a game event that fails", 1, true) ~= nil, "in its own words")
    ns.Listen("WORD", function() error("a listener that fails") end)
    ns.Listen("WORD", function(first, second) heard[#heard + 1] = first .. second end)
    ns.Fire("WORD", "a", "b")
    eq(heard[2], "ab", "the same for the addon's own messages, with what was said passed on")
    eq(#W.errors, 2, "and reported as well")
    W.errors = {}
end

function scenarios.compare()
    LoadAddon()
    local Place = ns.Compare.Place
    local function ctx(equipped, extra)
        local c = { equipped = equipped, dualWield = false }
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
    p = Place({ invType = "INVTYPE_HEAD", value = 12, itemID = 9 }, ctx({ [1] = worn(0, "INVTYPE_HEAD") }))
    near(p[1].delta, 12, "against a helm that scores nothing"); eq(p[1].percent, nil, "there is no percent of nothing either")
    eq(p[1].replaced[1], "L0", "and the helm still comes off")
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

    -- What an item gains or loses in one slot group, upgrade or not (the tooltip's other profiles).
    local Gain = ns.Compare.Gain
    p = Gain({ invType = "INVTYPE_HEAD", value = 8, itemID = 9 }, ctx({ [1] = worn(10, "INVTYPE_HEAD") }), "HEAD")
    near(p.delta, -2, "a worse helm loses"); near(p.percent, -0.2, "in percent as well")
    p = Gain({ invType = "INVTYPE_HEAD", value = 10.04, itemID = 9 }, ctx({ [1] = worn(10, "INVTYPE_HEAD") }), "HEAD")
    near(p.delta, 0.04, "a gain too small for the list is still told")
    p = Gain({ invType = "INVTYPE_HEAD", value = 0, itemID = 9 }, ctx({}), "HEAD")
    near(p.delta, 0, "an item that scores nothing gains nothing"); eq(p.percent, nil, "and no percent of an empty slot")
    p = Gain({ invType = "INVTYPE_FINGER", value = 2, itemID = 9 }, ctx(rings), "FINGER")
    near(p.delta, -1, "a ring is measured against the weaker one"); eq(p.replaced[1], "L2", "which it would replace")
    eq(Gain({ invType = "INVTYPE_FINGER", value = 50, itemID = 1, unique = true }, ctx(rings), "FINGER"), nil,
        "nothing for a second copy of a unique ring")
    eq(Gain({ invType = "INVTYPE_HEAD", value = 12, itemID = 9 }, ctx({}), "CHEST"), nil, "nothing for a slot it does not go in")
    eq(Gain({ invType = "INVTYPE_WEAPON", value = 30, itemID = 9 }, ctx({}), "OFFHAND"), nil,
        "nor for the off hand of one who cannot hold two weapons")

    -- weapons
    local oneHand = { [16] = worn(20, "INVTYPE_WEAPON", 1), [17] = worn(7, "INVTYPE_SHIELD", 2) }
    p = Place({ invType = "INVTYPE_2HWEAPON", value = 26, itemID = 9 }, ctx(oneHand))
    eq(#p, 0, "two-hander must beat both hands together")
    p = Place({ invType = "INVTYPE_2HWEAPON", value = 30, itemID = 9 }, ctx(oneHand))
    near(p[1].delta, 3, "two-hander delta"); eq(#p[1].replaced, 2, "both replaced"); eq(p[1].note, "BOTH_HANDS", "note")
    near(p[1].percent, 3 / 27, "its percent is of what both hands hold")

    p = Place({ invType = "INVTYPE_WEAPON", value = 24, itemID = 9 }, ctx(oneHand))
    eq(#p, 1, "one-hander without dual wield: main hand only"); eq(p[1].group, "MAINHAND", "main hand")
    -- The main hand lists both kinds together. A two-hander that adds 6 and a sword that adds
    -- 5 must not read as +22% and +25%: both are a share of the same 27.
    near(p[1].delta, 4, "one-hander delta"); near(p[1].base, 20, "against the sword alone"); eq(#p[1].replaced, 1, "which alone comes off")
    near(p[1].percent, 4 / 27, "and its percent is of both hands too")
    local big = Place({ invType = "INVTYPE_2HWEAPON", value = 33, itemID = 9 }, ctx(oneHand))[1]
    local small = Place({ invType = "INVTYPE_WEAPON", value = 25, itemID = 9 }, ctx(oneHand))[1]
    check(big.delta > small.delta and big.percent > small.percent, "the bigger gain is the bigger percent")
    p = Place({ invType = "INVTYPE_WEAPON", value = 24, itemID = 9 }, ctx(oneHand, { dualWield = true }))
    eq(#p, 2, "dual wielder: both hands"); near(p[2].delta, 17, "off hand delta")
    near(p[2].percent, 17 / 7, "the off hand has one kind of thing: a share of what it holds")
    p = Place({ invType = "INVTYPE_SHIELD", value = 9, itemID = 9 }, ctx(oneHand))
    eq(p[1].group, "OFFHAND", "shield"); near(p[1].delta, 2, "shield delta"); near(p[1].percent, 2 / 7, "shield percent")
    eq(#Place({ invType = "INVTYPE_WEAPONOFFHAND", value = 9, itemID = 9 }, ctx(oneHand)), 0, "off-hand weapon needs dual wield")
    eq(#Place({ invType = "INVTYPE_HOLDABLE", value = 9, itemID = 9 }, ctx(oneHand)), 1, "held item does not")

    local twoHand = { [16] = worn(30, "INVTYPE_2HWEAPON", 1) }
    eq(#Place({ invType = "INVTYPE_SHIELD", value = 9, itemID = 9 }, ctx(twoHand)), 0, "no off hand next to a two-hander")
    p = Place({ invType = "INVTYPE_WEAPONMAINHAND", value = 33, itemID = 9 }, ctx(twoHand))
    near(p[1].delta, 3, "one-hander vs two-hander"); eq(p[1].note, "OFFHAND_EMPTY", "off hand note")
    near(p[1].percent, 0.1, "a share of the two-hander")
    eq(#Place({ invType = "INVTYPE_WEAPON", value = 25, itemID = 9 }, ctx(twoHand, { dualWield = true })), 0, "weaker than the two-hander")

    check(ns.Compare.Handles("INVTYPE_TRINKET") and not ns.Compare.Handles("INVTYPE_BAG") and not ns.Compare.Handles(nil) and not ns.Compare.Handles(""), "Handles")
    eq(ns.Compare.GroupLabel("CHEST"), "Chest", "label from the game")
    eq(ns.Compare.GroupLabel("TRINKET"), "Trinket", "label from the addon when the game has none")
end

---------------------------------------------------------------------------
function scenarios.picks()
    LoadAddon()
    local ctx = { equipped = { [5] = { link = "WORN", value = 10, invType = "INVTYPE_CHEST", itemID = 1 } } }
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
    -- A ring of which only one can be worn is on, and another copy of it is for sale. It would
    -- beat the weaker ring in the other slot, if it could be put there.
    W.AddItem({ id = 220, name = "Band of One", equipLoc = "INVTYPE_FINGER", value = 6, level = 9, uniqueEquipped = true })
    W.equipped[12] = W.Link(220)
    W.AddAuction(220, 300)
    W.AH.honorLevelSort = false
    W.AH.bidsIgnored = true              -- this server's rows show the cheapest buyout, never a bid
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    eq(Offer("Band of One"), nil, "a second copy of a unique-equipped ring is no upgrade: it cannot be worn beside the first")
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

-- A belt that comes in variants, as random-suffix gear does on Forever: the plain item has
-- nothing on it, each variant is an item of its own with a row of its own at the auction house.
local function AddBelts()
    local function Belt(suffix, name, value)
        W.AddItem({ id = 400, suffix = suffix, name = name, equipLoc = "INVTYPE_WAIST", subClassID = 3, level = 8,
            value = value or 0, noStats = value == nil })
    end
    Belt(0, "Belt")
    Belt(7, "Belt of the Bear", 9)
    Belt(8, "Belt of the Owl", 0.2)
    Belt(9, "Belt of the Tiger", 9)             -- scores the same as the Bear
    W.AddAuction(400, 50, { suffix = 8 })
    W.AddAuction(400, 900, { suffix = 7 })
    W.AddAuction(400, 700, { suffix = 7 })
    W.AddAuction(400, 800, { suffix = 9 })
end

function scenarios.scan_no_sample()
    StandardWorld()
    AddBelts()
    W.AH.sampleLinks = false             -- the client has no sample link for any row
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    check(W.AH.calls.search > 6, "falls back to searching every candidate row")
    -- A row's key cannot be made into a link of its variant: the plain belt would be scored,
    -- which has nothing on it, and the row dropped.
    check(Offer("Belt of the Bear") ~= nil, "a variant is found by its item search, not guessed from the row's key")
    for id, offer in pairs(ns.Scanner.offers) do
        if offer.itemID == 400 then ns.Scanner.offers[id] = nil end
    end
    CheckStandardOffers("no sample link")
end

function scenarios.scan_suffix_rows()
    StandardWorld()
    AddBelts()
    LoadAddon()
    SetView(false, false)                -- every upgrade is listed, not the best few of a slot
    W.OpenAuctionHouse()
    ScanToEnd()
    local S = ns.Scanner
    local bear, tiger, owl = Offer("Belt of the Bear"), Offer("Belt of the Tiger"), Offer("Belt of the Owl")
    check(bear ~= nil and tiger ~= nil and owl ~= nil, "each variant is an offer of its own")
    eq(bear.buyout, 700, "cheapest of that variant"); eq(bear.count, 2, "two of that variant")
    eq(tiger.buyout, 800, "a variant with the same score keeps its own price"); eq(tiger.count, 1, "and its own count")
    check(bear.id ~= tiger.id, "and is another offer")
    eq(owl.buyout, 50, "the poor variant at its price")
    eq(ns.ItemKey(bear.link), "400:Belt of the Bear", "a variant by its number and name")
    check(not bear.link:find(":7:", 1, true), "its link does not carry the suffix of the row's key")

    -- The character wears one variant and buys another: the one in the mail is not the one worn.
    W.equipped[6] = owl.link
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    S.Buy(Offer("Belt of the Bear"))
    W.RunUntil(Asking, 30)
    Asking().Buy:Click()
    W.RunUntil(function() return #S.acquired == 1 end, 30)
    W.RunUntil(function() return S.state == "idle" end, 30)
    eq(Offer("Belt of the Bear").buyout, 900, "the next Bear is listed at its own price")
    eq(Offer("Belt of the Tiger").buyout, 800, "and the Tiger is still there")
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    eq(#S.acquired, 1, "with the Owl on, the Bear that was bought is still on its way")
    W.equipped[6] = bear.link
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    eq(#S.acquired, 0, "put on, it is gear")
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
    check(Asking() ~= nil, "asks for confirmation")
    Asking().Buy:Click()
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
    eq(S.halted, true, "on hold"); eq(S.unanswered, 3, "with three prices missing")
    eq(S.stats.timeouts, 3, "statistics: three searches without an answer")
end

-- An item search that the auction house leaves unanswered does not end the scan. It goes on
-- without that price, and the status line says that one is missing: not that the scan stopped.
function scenarios.scan_unanswered()
    StandardWorld()
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    local function Status() return frame.Status:GetText() or "" end
    local missing = "Price checks without an answer: 1."

    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "verify" and OfferCount() >= 1 end, 60)
    W.AH.dropSearches = 2       -- a search and its second try
    W.RunUntil(function() return S.state == "idle" end, 120)
    W.Run(0.3)
    eq(S.stats.timeouts, 1, "one item search went unanswered, asked twice")
    eq(S.unanswered, 1, "the scanner counts it")
    eq(S.partial, false, "the scan did not stop early"); eq(S.halted, false, "nor do its price checks wait")
    eq(S.message, nil, "it has no note of its own")
    eq(OfferCount(), 5, "the other five prices are in the list")
    check(Status():find("5 upgrades in 5 slots.", 1, true) ~= nil, "which the status line counts: " .. Status())
    check(Status():find(missing, 1, true) ~= nil, "and it says a price is missing: " .. Status())
    check(Status():find(ns.L.ST_PARTIAL, 1, true) == nil, "not that the scan stopped early")
    eq(S.Demand(), false, "the search is not sent again by itself")

    -- The best set for a budget is drawn from the same prices, and says the same.
    frame.PlanBar.Check:SetChecked(true)
    frame.PlanBar.Check:Click()
    W.RunUntil(function() return S.state == "idle" end, 120)
    W.Run(0.3)
    check(Status():find(missing, 1, true) ~= nil, "with the best set shown: " .. Status())
    frame.PlanBar.Check:SetChecked(false)
    frame.PlanBar.Check:Click()
    W.Run(0.3)

    -- A scan that is stopped says that it was, and no more.
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "second scan starts")
    eq(S.unanswered, 0, "a new scan starts its count anew")
    W.RunUntil(function() return S.state == "verify" and OfferCount() >= 1 end, 60)
    W.AH.dropSearches = 2
    W.RunUntil(function() return S.unanswered == 1 end, 60)
    W.CloseAuctionHouse()
    W.OpenAuctionHouse()
    W.Run(0.3)
    eq(S.halted, true, "the window closed during the price checks")
    check(Status():find(ns.L.ST_PARTIAL, 1, true) ~= nil, "the scan stopped early: " .. Status())
    check(Status():find("without an answer", 1, true) == nil, "which says enough")

    -- Every answer in: nothing is said.
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.3)
    eq(S.unanswered, 0, "a scan with every answer")
    check(Status():find("6 upgrades in 5 slots.", 1, true) ~= nil, "lists all six: " .. Status())
    check(Status():find("incomplete", 1, true) == nil and Status():find("answer", 1, true) == nil, "and has nothing to add")
end

-- A piece of gear that stacks is sold by the piece out of one pile, as consumables are: the game
-- has a grey necklace like that. Its row has no sample link, and a search for it is answered
-- with a price list, under another event than the one for auctions. The scan for gear leaves
-- such a row alone: no wait for a sample, no search, nothing left unanswered.
function scenarios.scan_pieces()
    StandardWorld()
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    local S = ns.Scanner
    ScanToEnd()
    local rows, searches, candidates = S.info.rows, S.stats.searches, S.stats.candidates
    CheckStandardOffers("the world as it is")

    -- A price list that comes in for some other item (the game's own Buy tab asked for it) is
    -- no answer to a search of the scan.
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "verify" end, 60)
    for _ = 1, 2000 do
        if S.state == "idle" then break end
        W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 999)
        W.Run(0.05)
    end
    eq(S.stats.searches, searches, "the same searches"); eq(S.unanswered, 0, "each with its answer")
    CheckStandardOffers("with price lists for other items coming in")

    W.AddItem({ id = 230, name = "Tarnished Necklace", equipLoc = "INVTYPE_NECK", quality = 0, value = 3, level = 1, stack = 20 })
    W.AddAuction(230, 50, { quantity = 7 })
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    eq(S.info.rows, rows + 1, "the necklace is a row of the auction list")
    eq(S.stats.candidates, candidates, "and no candidate for the list of gear")
    eq(S.stats.searches, searches, "no search is sent for it")
    eq(S.stats.timeouts, 0, "so none goes unanswered"); eq(S.unanswered, 0, "and no price is missing")
    check(S.stats.score < 1, "the scoring did not wait for a sample link that never comes (" .. S.stats.score .. " s)")
    eq(Offer("Tarnished Necklace"), nil, "it is not an offer")
    CheckStandardOffers("with a necklace sold by the piece")

    -- An item the client has not loaded when the rows are scored cannot be told from gear by
    -- then. Its search is sent, as for any row nothing is known of, and the price list that
    -- comes back settles it at once: it holds no auctions.
    W.items["230:0"].cached = false
    W.neverLoad = { [230] = true }
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    eq(S.stats.searches, searches + 1, "one search more: for the row nothing was known of")
    eq(S.stats.timeouts, 0, "the price list is its answer"); eq(S.unanswered, 0, "and no price is missing")
    eq(S.partial, false, "a whole scan")
    eq(Offer("Tarnished Necklace"), nil, "still not an offer")
    CheckStandardOffers("with a necklace the client had not loaded")
end

-- The tabs write in font families of their own: the client's font file, and for an alphabet
-- that file is not for, the file the game's own font has for it. The name of a Russian
-- character on an English client is then written in letters, not in squares.
function scenarios.fonts()
    StandardWorld()
    LoadAddon()
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ScanToEnd()
    W.Run(0.3)
    local function Member(family, alphabet)
        for _, member in ipairs(family.members) do
            if member.alphabet == alphabet then return member end
        end
    end
    -- A row of the list that is in view.
    local function Row()
        for _, w in ipairs(W.frames) do
            if w._template == "WowScrollBoxList" then
                for _, row in ipairs(w:GetFrames()) do
                    if row._shown and row.entry and row.Name then return row end
                end
            end
        end
    end

    local frame = UpgradeScoutFrame
    local words = frame.Status._font
    eq(type(words), "table", "the status line is written in a font family")
    eq(#words.members, 5, "with a member for each of the game's alphabets")
    eq(Member(words, "roman").file, "Fonts\\FRIZQT__.TTF", "Latin letters in the client's standard font")
    eq(Member(words, "russian").file, "Fonts\\FRIZQT___CYR.TTF", "Cyrillic in the game's font for it")
    eq(Member(words, "korean").file, "Fonts\\2002.TTF", "Korean in the game's")
    eq(Member(words, "simplifiedchinese").file, "Fonts\\ARKai_T.ttf", "Chinese in the game's")
    eq(Member(words, "traditionalchinese").file, "Fonts\\blei00d.TTF", "in either writing")
    for _, member in ipairs(words.members) do
        eq(member.height, 11, "every member at the size of the line"); eq(member.flags, "", "and plain")
    end
    eq(frame.Age._font, words, "a text of the same font and size is in the same family")
    check(frame.AffordCheck.Text._font ~= nil, "a tick box's label has a font")
    -- The rows are in the narrow font the game writes numbers and auction lists in.
    local narrow = Row().Name._font
    eq(type(narrow), "table", "an item's name is in a family too")
    check(narrow ~= words, "another one")
    eq(Member(narrow, "roman").file, "Fonts\\ARIALN.TTF", "the narrow font")
    eq(Member(narrow, "korean").file, "Fonts\\K_Damage.TTF", "with the game's Korean file for that font")
    eq(Member(narrow, "roman").height, 13, "at the size of a row")
    local count = 0
    for name, family in pairs(W.fontFamilies) do
        eq(family.name, name, "a family is known by its name, which no other has")
        count = count + 1
    end
    check(count >= 2 and count <= 16, "a family for each font and size, not for each text (" .. count .. ")")

    -- On a Russian client, with a font of the player's own in place of the game's: the client's
    -- file writes Latin and Cyrillic, and the game's files the rest.
    local player, equipped = W.player, W.equipped
    W.Logout()
    W.locale = "ruRU"
    STANDARD_TEXT_FONT = "Interface\\AddOns\\SomeFont\\Mine.ttf"
    W.Login(player, equipped)
    ns = {}
    LoadAddon()
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    words = UpgradeScoutFrame.Status._font
    eq(Member(words, "roman").file, STANDARD_TEXT_FONT, "Latin letters in the font the player chose")
    eq(Member(words, "russian").file, STANDARD_TEXT_FONT, "and Cyrillic, the client's own writing")
    eq(Member(words, "korean").file, "Fonts\\2002.TTF", "Korean still in the game's")
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
    local searches

    -- The question is for a player who is looking at the list. If they left the tab while the
    -- item was being looked up, nothing pops up, and the scanner is free again.
    ns.Scanner.Buy(good)
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(Asking(), nil, "no question away from the tab")
    W.RunUntil(function() return W.AH.ready end, 5)
    searches = W.AH.calls.search
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ns.Scanner.Buy(good)
    eq(ns.Scanner.state, "verify", "looks the item up again first")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(W.AH.calls.search, searches + 1, "one fresh item search")
    local box = Asking()
    check(box ~= nil, "asks for confirmation, in a box of the addon's")
    eq(box.link, good.link, "about the item"); check(box.Name:GetText():find("Good Chest", 1, true) ~= nil, "named")
    eq(box.FirstLabel:GetText(), "UPGRADE", "what it gains"); eq(box.Gain:GetText(), "+80%", "as the list says: 18 against 10")
    eq(box.TotalLabel:GetText(), "BUYOUT", "and its buyout"); eq(box.Total:GetAmount(), 4000, "in coins")
    eq(box.NetLabel:IsShown(), false, "no line for a net cost: the list is by buyout"); eq(box.Net:IsShown(), false, "nor its coins")
    eq(box:GetHeight(), 162, "the box at its usual height")
    eq(box.Count:IsShown(), false, "nothing to count"); eq(box.Stock:IsShown(), false, "nor a stock")
    eq(box.Buy.Label:GetText(), "BUY", "its button says what it does")
    check(table.concat(UISpecialFrames, " "):find(box:GetName(), 1, true) ~= nil, "Escape closes it")
    box.Item:GetScript("OnEnter")(box.Item)
    eq(GameTooltip._link, good.link, "the item's tooltip over its name")
    box.Item:GetScript("OnLeave")(box.Item)

    -- "Cancel": nothing is bought, and the scanner is free again.
    box.Cancel:Click()
    eq(box:IsShown(), false, "the box goes")
    eq(#W.AH.calls.bids, 0, "nothing bought before the player agrees")
    W.RunUntil(function() return ns.Scanner.state == "idle" and W.AH.ready end, 30)
    ns.Scanner.Buy(good)
    W.RunUntil(Asking, 30)
    box.Buy:Click()
    eq(#W.AH.calls.bids, 1, "bought")
    eq(W.AH.calls.bids[1].amount, 4000, "at the buyout price")
    eq(box:IsShown(), true, "the box waits for the auction house to answer")
    eq(box.Buy:IsEnabled(), false, "its button greyed meanwhile")
    W.RunUntil(function() return not box:IsShown() end, 5)
    W.RunUntil(function() return ns.Scanner.state == "idle" and Offer("Good Chest") ~= nil and Offer("Good Chest").buyout == 5000 end, 30)
    eq(Offer("Good Chest").count, 1, "the next copy is listed at its own price")
    check(W.printed[#W.printed]:find("Bought", 1, true) ~= nil, "purchase reported in chat")

    -- Someone else was faster: the auction house turns the bid down, and the box goes.
    W.RunUntil(function() return ns.Scanner.state == "idle" and W.AH.ready end, 30)
    local bids = #W.AH.calls.bids
    W.AH.failBid = true
    ns.Scanner.Buy(Offer("Great Chest"))
    W.RunUntil(Asking, 30)
    box.Buy:Click()
    eq(#W.AH.calls.bids, bids + 1, "the bid went out")
    W.RunUntil(function() return not box:IsShown() end, 5)
    W.AH.failBid = nil
    check(Offer("Great Chest") ~= nil, "and nothing was bought")

    -- Too expensive
    W.player.money = 10
    W.RunUntil(function() return ns.Scanner.state == "idle" and W.AH.ready end, 30)
    ns.Scanner.Buy(Offer("Great Chest"))
    eq(Asking(), nil, "no box when the player cannot pay")
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
    eq(Asking(), nil, "no box for an item that is gone")
    eq(Offer("Helm"), nil, "and it leaves the list")
    check(W.printed[#W.printed]:find("no longer for sale", 1, true) ~= nil, "says it is gone")

    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(Asking(), nil, "no box when the price changed")
    eq(Offer("Good Chest").buyout, 5000, "list shows the new price")
    check(W.printed[#W.printed]:find("now costs", 1, true) ~= nil, "says the price changed")

    -- The server never answers the lookup.
    W.AH.dropSearches = 5
    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 60)
    eq(Asking(), nil, "no box without an answer")
end

---------------------------------------------------------------------------
function scenarios.ui()
    local PAGE, ROW = 14, 30             -- rows in view and the height of one (see W.listHeight)
    StandardWorld()
    W.player.money = 50000               -- 5 gold: the 9 gold robe is out of reach
    -- A second ring, which adds nothing the profile counts.
    W.AddItem({ id = 103, name = "Plain Band", equipLoc = "INVTYPE_FINGER", value = 0, level = 1, noStats = true })
    W.equipped[12] = W.Link(103)
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
    eq(list.Titles[1]:GetText(), "ITEM", "first column"); eq(list.Titles[2]:GetText(), "PICK", "second")
    eq(list.Titles[3]:GetText(), "UPGRADE", "third"); eq(list.Titles[4]:GetText(), "BUYOUT", "price column")
    -- Gear has four columns, the buyout the last of them. What a point of the gain costs is
    -- not shown: not in a column of its own, nor anywhere else on the tab.
    eq(list.Titles[5]:IsShown(), false, "no title after the buyout")
    for _, text in ipairs(W.texts) do
        local said = text:IsVisible() and text:GetText() or ""
        check(said:lower():find("per point", 1, true) == nil, "nothing on the tab is priced per point: " .. said)
    end

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
    eq(rows[2].Upgrade:GetText(), "New", "an empty slot: no percent to give, so a word")
    eq(rows[2].Share, nil, "one value in the column, not two")
    eq(rows[2].Pick:IsShown(), true, "a plate for the pick"); eq(rows[2].Pick.Text:GetText(), "Best of both", "single offer is both picks")
    eq(rows[2].Buy.Label:GetText(), "BUY", "the buy button")
    eq(rows[2].Price._template, "MoneyDisplayFrameTemplate", "the price is the game's coin display")
    eq(rows[2].Price:GetAmount(), 2500, "25 silver")
    eq(rows[2].Price._font, PriceFontWhite, "in white: the player can pay")
    eq(rows[2].PerPoint, nil, "one price on a row: the buyout")
    local coins = 0
    for _, w in ipairs(Made("MoneyDisplayFrameTemplate")) do
        if w:GetParent() == rows[2] then coins = coins + 1 end
    end
    eq(coins, 1, "and no other coin display on it")
    -- The coins of a price stand close together: each part of it a fixed step to the left of
    -- the part after it, not in the game's slots, which leave a hole before a single digit.
    local function Laid(money)
        local anchors = { [money] = "frame", [money.CopperDisplay] = "copper", [money.SilverDisplay] = "silver" }
        local out = {}
        for _, key in ipairs({ "GoldDisplay", "SilverDisplay", "CopperDisplay" }) do
            local part = money[key]
            eq(#part._points, 1, "one anchor for each part of a price")
            if part:IsShown() then
                local at = part._points[1]
                out[#out + 1] = key:sub(1, 1) .. part._amount .. " " .. at.point .. " to " .. tostring(anchors[at.to]) .. " " .. at.toPoint .. " " .. at.x
            end
        end
        return table.concat(out, ", ")
    end
    eq(Laid(rows[2].Price), "S25 RIGHT to copper LEFT -9, C0 RIGHT to frame RIGHT 0", "25 silver: the copper at the right edge, the silver close before it")
    eq(rows[2].Buy:IsEnabled(), true, "can buy")

    -- The columns of gear. How far along a part is anchored: a row's part from the row's left
    -- edge, a title from that of the plate, which the rows lie INSET inside.
    local INSET = 8
    local function At(part)
        eq(#part._points, 1, "one anchor")
        return part._points[1].x
    end
    local helm = rows[2]
    eq(At(helm.Price), 684, "the buyout ends close before the Buy button, with no column between them")
    eq(At(list.Titles[4]) - INSET, At(helm.Price), "its title ends where the prices do")
    eq(At(list.Titles[3]) - INSET, At(helm.Upgrade), "the title of the gain ends where the gains do")
    eq(At(helm.Trough), At(helm.Upgrade), "and so does the meter under a gain")
    eq(At(list.Titles[2]) - INSET, At(helm.Pick), "the title of the pick begins where the picks do")
    check(At(helm.Pick) >= At(helm.Name) + helm.Name:GetWidth() + 8, "a pick begins clear of the longest name")
    check(At(helm.Upgrade) - 72 >= At(helm.Pick) + 140 + 8, "the meter of a gain begins clear of the longest pick")
    check(At(helm.Price) - At(helm.Upgrade) >= 120, "and a price has room for thousands of gold")
    eq(rows[3].Title:GetText(), "CHEST", "chest block")
    eq(rows[4].Name:GetText(), "|cff1eff00Good Chest|r", "the robe is hidden: too expensive")
    eq(rows[4].Upgrade:GetText(), "+80%", "the gain, in percent of what is worn: 18 against 10")

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
    eq(axe.Upgrade:GetText(), "+30%", "the two-hander against the sword: 26 against 20")

    -- The lines of a row's tooltip with something on their right, by the words on their left.
    local function Gains()
        local out = {}
        for _, line in ipairs(GameTooltip._lines) do
            if line.right then out[line.text] = line end
        end
        return out
    end
    -- A ring in the place of one that scores nothing: no percent of nothing, in the list or in
    -- the tooltip.
    local ring = RowNamed("New Ring")
    eq(ring.Upgrade:GetText(), "+6 pts", "the worn ring scores nothing: not new, so the gain in points")
    ring:GetScript("OnEnter")(ring)
    local ringTip = Gains()
    eq(ringTip.Arms.right, "+6 pts", "the tooltip says the same on the profile in use")
    eq(ringTip["Protection ~"].right, "+0 pts", "the other profile counts nothing of either ring")
    eq(ringTip["Protection ~"].rightR, GRAY_FONT_COLOR.r, "and says so in grey")
    rows[2]:GetScript("OnEnter")(rows[2])
    eq(Gains().Arms.right, "+12 pts", "an empty slot: the helm's whole score, in points")
    rows[2]:GetScript("OnLeave")(rows[2])

    -- The two filters: tick boxes with their labels beside them.
    local checkbox, topBox = frame.AffordCheck, frame.TopCheck
    eq(checkbox._kind, "CheckButton", "a filter is a tick box")
    eq(checkbox.Text:GetText(), "Only what I can afford", "the price filter"); eq(topBox.Text:GetText(), "Top 5 per slot", "and top five")
    eq(topBox:GetChecked(), true, "top five on by default"); eq(topBox.Tick:IsShown(), true, "with its tick showing")
    eq(rows[3].Count:GetText(), "", "nothing cut, so no count in the header")
    eq(checkbox:GetChecked(), true, "afford filter on by default")
    local function Status()
        return frame.Status:GetText() or ""
    end
    -- The age of the scan stands on its own at the right end of the strip.
    local function Age()
        return frame.Age:IsShown() and frame.Age:GetText() or ""
    end
    -- Helm, Good Chest, New Ring, Big Axe and Shield are listed; the robe costs 9 gold.
    check(Status():find("5 upgrades in 5 slots. 1 more cost more than you have.", 1, true) ~= nil, "status counts the robe that was not looked up: " .. Status())
    check(Status():find("ago", 1, true) == nil, "the status line leaves the age out: " .. Status())
    check(Age():find("Sec ago", 1, true) ~= nil, "the age of the scan in the game's units: " .. Age())
    -- The age goes on counting while the tab is only looked at: no event comes with a second.
    local finished = ns.Scanner.finishedAt
    W.Run(7)
    check(time() - finished >= 7, "seven seconds on")
    eq(Age(), "Scanned " .. ns.Ago(time() - finished) .. " ago.", "the age keeps up with the clock")
    W.Run(120, 0.5)
    eq(Age(), "Scanned 2 Min ago.", "and goes on to minutes")
    -- Not while the tab is out of view.
    frame:Hide()
    local said = frame.Age:GetText()
    W.Run(60, 0.5)
    eq(frame.Age:GetText(), said, "nothing is written while the tab is hidden")
    frame:Show()
    eq(Age(), "Scanned 3 Min ago.", "the age is right again when the tab comes back")

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
    eq(frame.Age:IsShown(), false, "in the place of the age")
    eq(list.Progress:IsShown(), false, "and not over the list, which has rows")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    W.Run(0.3)
    eq(W.AH.calls.search, searches + 1, "one item search, for the robe")
    rows = Rows()
    eq(rows[4].Name:GetText(), "|cff1eff00Great Chest|r |cffffd100*|r", "robe listed first, with the effects mark")
    eq(rows[4].Price:GetAmount(), 90000, "its price")
    eq(rows[4].Price._font, PriceFontRed, "in red")
    eq(Laid(rows[4].Price), "G9 RIGHT to silver LEFT -9, S0 RIGHT to copper LEFT -9, C0 RIGHT to frame RIGHT 0",
        "with gold in a price its three parts still stand a step apart")
    eq(rows[4].Buy:IsEnabled(), false, "cannot buy it")
    eq(rows[4].Pick.Text:GetText(), "Best upgrade", "robe is the best upgrade")
    eq(rows[5].Pick.Text:GetText(), "Best value", "Good Chest is the best value")
    -- The meter under a gain measures it against the best one in the slot: +8 against +20.
    near(rows[5].Meter:GetWidth() / rows[4].Meter:GetWidth(), 8 / 20, "the meter of the smaller gain is shorter by as much")

    -- Tooltip: the gain on every profile of the class, as Pawn shows its scales. On the other
    -- profile the two chests score 9 and 12.
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    rows[5]:GetScript("OnEnter")(rows[5])
    local seen = {}
    for _, line in ipairs(GameTooltip._lines) do seen[#seen + 1] = line.text end
    local tip = table.concat(seen, "\n")
    -- Our lines are headed by the addon's name, apart from the item's own.
    local header, headers = nil, 0
    for i, line in ipairs(GameTooltip._lines) do
        if line.text:find("Upgrade Scout", 1, true) then
            header = header or i
            headers = headers + 1
        end
    end
    check(header ~= nil, "our lines have a header")
    eq(headers, 1, "once: the lines every item tooltip gets (Tooltip.lua) are not added under a row")
    local head = GameTooltip._lines[header]
    eq(head.text, "|TInterface\\AddOns\\UpgradeScout\\icon.tga:0|t Upgrade Scout", "the addon's icon and name")
    near(head.b, 0.96, "in blue")
    eq(head.right, nil, "with nothing on the right for the character's own list")
    eq(GameTooltip._lines[header - 1].text, " ", "a blank line sets them off from the item's")
    local arms, prot = GameTooltip._lines[header + 1], GameTooltip._lines[header + 2]
    eq(arms.text, "Arms", "then the profiles of the class, in the order of the menu")
    eq(arms.right, "+80%", "each with its gain: on the profile in use, the list's")
    eq(arms.r, RAID_CLASS_COLORS.WARRIOR.r, "in the colour of the class"); eq(arms.rightR, GREEN_FONT_COLOR.r, "a gain in green")
    eq(prot.text, "Protection ~", "the other one with its mark")
    eq(prot.right, "-25%", "measured on its own weights: 9 against the 12 of the worn chest")
    eq(prot.r, RAID_CLASS_COLORS.WARRIOR.r, "in it too"); eq(prot.rightR, RED_FONT_COLOR.r, "a loss in red")
    eq(GameTooltip._lines[header + 3], nil, "and no more for an item without notes")
    for _, gone in ipairs({ "Score", "Replaces", "per point", "for sale" }) do
        check(tip:find(gone, 1, true) == nil, "nothing of '" .. gone .. "' any more: " .. tip)
    end
    W.items["200:0"].value2, W.items["100:0"].value2 = nil, nil
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
    W.RunUntil(Asking, 30)
    eq(Asking().offer.name, "Good Chest", "confirmation for the clicked item")
    frame:Hide()
    eq(UpgradeScoutBuyBox:IsShown(), false, "it does not outlive the tab")
    frame:Show()

    -- Shift-click links the item; a plain click does nothing.
    rows = Rows()
    rows[5]:Click()
    eq(W.linked, nil, "a plain click on a row does nothing")
    W.modified = true
    rows[5]:Click()
    check(W.linked and W.linked:find("Good Chest", 1, true), "a modified click hands the link to the game")
    W.modified = false

    -- The profile: one of the game's dropdowns. Choosing another profile rescans with it.
    local dropdown = Made("WowStyle1DropdownTemplate")[1]
    check(dropdown ~= nil, "the profile is chosen in a dropdown")
    eq(dropdown:GetText(), "Arms", "which shows the profile in use")
    eq(#dropdown.radios, 2, "and offers the profiles of the character's class")
    eq(dropdown.radios[2].text, "Protection ~", "an estimated one with its mark")
    -- Its tooltip helps to choose, and no more: how the weights were made is in the README.
    -- (A level below 60 with the leveling data is where it once said how much less the ratings count.)
    ns.Weights.leveling = { stats = {}, points = { { 20, 0.2 }, { 60, 1 } } }
    dropdown._tooltip(GameTooltip)
    local about = {}
    for _, line in ipairs(GameTooltip._lines) do about[#about + 1] = line.text end
    about = table.concat(about, "\n")
    check(about:find("Choose the profile for your talent tree.", 1, true) ~= nil, "the tooltip says which profile to take: " .. about)
    check(about:find("~ means the weights are estimated.", 1, true) ~= nil, "and what the mark by a profile means")
    check(about:find("Your other characters are here too", 1, true) ~= nil, "and that the list has the other characters")
    for _, word in ipairs({ "simulat", "approximation", "by hand", "At level", "Pawn" }) do
        check(about:find(word, 1, true) == nil, "nothing of how the weights were made: " .. word)
    end
    check(#GameTooltip._lines <= 5, "a few lines: " .. #GameTooltip._lines)
    ns.Weights.leveling = nil

    -- Its menu opens on our plate. The game copies the dropdown's style onto the menu's frame
    -- and calls Generate, which may only attach what it draws: the plate goes on a frame of
    -- its own inside the menu, a frame no addon that restyles menus repaints.
    local style = dropdown.menuMixin
    eq(style, ns.Widgets.MenuStyle, "the menu has our style")
    local menu = W.Widget("Frame")
    function menu:AttachFrame(kind)
        local plate = W.Widget(kind, nil, self)
        function plate:AttachTexture() return self:CreateTexture() end
        self.plate = plate
        return plate
    end
    style.Generate(menu)
    eq(Pictures(menu.plate, "Panel"), 9, "the plate of the list, cut in nine")
    eq(Pictures(menu, "Panel"), 0, "and nothing on the menu's own frame")
    check(style.GetInset(menu).left >= 10 and style.GetChildExtentPadding(menu).width > 0, "the lines keep off its gold edge")
    -- Each line is dressed after the game has drawn it: a diamond where the game has its round
    -- mark, gold on the line chosen, the light of our rows under the mouse.
    local function Line(chosen)
        local line = W.Widget("Button")
        line.leftTexture1, line.highlight, line.fontString = line:CreateTexture(), line:CreateTexture(), line:CreateFontString()
        if chosen then line.leftTexture2 = line:CreateTexture() end
        for _, dress in ipairs(dropdown.radios[1].initializers) do dress(line) end
        return line
    end
    local chosen, other = Line(true), Line(false)
    eq(Pictures(chosen, "Diamond"), 2, "the line chosen: a diamond over the grey one")
    eq(chosen.leftTexture2._grey, nil, "in gold")
    eq(other.leftTexture1._grey, true, "the others: a grey one")
    eq(Pictures(other, "RowGlow"), 1, "the light of a row under the mouse")
    eq(#dropdown.radios[2].initializers, 1, "every line is dressed")
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(2)
    eq(ns.Roster.Me().profile, "S2", "choice saved")
    eq(ns.Scanner.state, "browse", "rescans")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 120)
    W.Run(0.3)
    eq(dropdown:GetText(), "Protection ~", "the dropdown shows the new profile")
    eq(OfferCount(), 0, "nothing scores on a profile that values none of it")

    -- Scrolling a long list
    ns.Roster.Me().profile = "S1"
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
    eq(rows[legs + 4].Price:GetAmount(), 100, "for a silver: ten copper a point, the least of them all")
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
    -- In our colours: the game's own pictures are see-through, ours are on the same parts.
    local track, knob = bar.Track, bar.Track.Thumb
    for _, part in ipairs({ track.Begin, track.Middle, track.End, knob.Begin, knob.Middle, knob.End, bar.Back.Texture, bar.Forward.Texture }) do
        eq(part:GetAlpha(), 0, "the game's own picture is see-through")
    end
    eq(Pictures(track, "ScrollTrack"), 3, "a dark rail, cut in three")
    eq(Pictures(knob, "ScrollThumb"), 6, "a gold knob in three pieces, and its light under the mouse")
    eq(Pictures(bar.Back, "Chevron"), 2, "a gold arrow at the top"); eq(Pictures(bar.Forward, "Chevron"), 2, "and at the bottom")
    bar.Back:SetEnabled(false)
    eq(bar.Back.Chevron:GetAlpha(), 0.35, "dim while there is nothing more that way")
    bar.Back:SetEnabled(true)
    eq(bar.Back.Chevron:GetAlpha(), 1, "and bright again when there is")
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
    UpgradeScoutWelcome:Hide()
    local printed = #W.printed
    SlashCmdList.UPGRADESCOUT("")
    eq(#W.printed, printed, "/upscout away from the auction house says nothing in the chat")
    eq(UpgradeScoutWelcome:IsShown(), true, "it opens the addon's own window (see the scenario welcome)")
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Consumables
---------------------------------------------------------------------------
-- What a level 30 character with 2 gold finds under Consumables. Prices are for one piece.
local function SuppliesWorld()
    W.player.level = 30
    W.player.money = 20000
    local function Add(def)
        def.classID, def.quality = 0, 1
        return W.AddItem(def)
    end
    -- Healing potions: three the character can drink and one it is too young for.
    Add({ id = 500, name = "Minor Healing Potion", subClassID = 1, level = 1, stack = 5, use = "Restores 70 to 90 health." })
    Add({ id = 501, name = "Healing Potion", subClassID = 1, level = 12, stack = 5, use = "Restores 280 to 360 health." })
    Add({ id = 502, name = "Greater Healing Potion", subClassID = 1, level = 21, stack = 5, use = "Restores 455 to 585 health." })
    Add({ id = 503, name = "Superior Healing Potion", subClassID = 1, level = 35, stack = 5, use = "Restores 700 to 900 health." })
    Add({ id = 504, name = "Mana Potion", subClassID = 1, level = 22, stack = 5, use = "Restores 455 to 585 mana." })
    -- Food: two of the same strength at different prices, and a weaker one.
    Add({ id = 510, name = "Wild Hog Shank", subClassID = 5, level = 25, stack = 20, use = "Restores 874 health over 27 sec. Must remain seated while eating." })
    Add({ id = 511, name = "Stormwind Brie", subClassID = 5, level = 25, stack = 20, use = "Restores 874 health over 27 sec. Must remain seated while eating." })
    Add({ id = 512, name = "Mutton Chop", subClassID = 5, level = 15, stack = 20, use = "Restores 552 health over 24 sec. Must remain seated while eating." })
    -- Bandages ask for a skill, not a level; the tooltip of one the character cannot use is red.
    Add({ id = 520, name = "Wool Bandage", subClassID = 7, level = 1, stack = 20, use = "Heals 161 damage over 7 sec." })
    Add({ id = 521, name = "Heavy Wool Bandage", subClassID = 7, level = 1, stack = 20, use = "Heals 301 damage over 7 sec." })
    Add({ id = 522, name = "Runecloth Bandage", subClassID = 7, level = 1, stack = 20, use = "Heals 1,360 damage over 8 sec.", red = true })
    -- Filed under Consumables with nothing to use, and a subcategory the game has no name for.
    Add({ id = 530, name = "Strange Dust", subClassID = 8, level = 1, stack = 20 })
    Add({ id = 531, name = "Rough Dynamite", subClassID = 0, level = 1, stack = 20, use = "Inflicts 26 to 34 Fire damage in a 5 yard radius." })
    -- Elixirs: what they add is worth something on a profile, or nothing (see SupplyFacts).
    Add({ id = 560, name = "Elixir of Ogre Strength", subClassID = 2, level = 20, stack = 5, use = "Increases Strength by 8 for 1 hr." })
    Add({ id = 561, name = "Elixir of Lesser Agility", subClassID = 2, level = 18, stack = 5, use = "Increases Agility by 8 for 1 hr." })
    Add({ id = 562, name = "Elixir of Agility", subClassID = 2, level = 27, stack = 5, use = "Increases Agility by 15 for 1 hr." })
    Add({ id = 563, name = "Elixir of Wisdom", subClassID = 2, level = 10, stack = 5, use = "Increases Intellect by 6 for 1 hr." })
    Add({ id = 564, name = "Elixir of Giants", subClassID = 2, level = 28, stack = 5, use = "Increases Strength by 25 for 1 hr." })

    W.AddAuction(500, 30, { quantity = 40 })
    W.AddAuction(501, 300, { quantity = 12 })
    W.AddAuction(502, 900, { quantity = 3 })
    W.AddAuction(502, 1000, { quantity = 10 })
    W.AddAuction(502, 800, { quantity = 5, own = true })   -- the character's own: cannot be bought
    W.AddAuction(503, 2500, { quantity = 8 })
    W.AddAuction(504, 30000, { quantity = 6 })             -- more than the character has
    W.AddAuction(510, 120, { quantity = 60 })
    W.AddAuction(511, 90, { quantity = 20 })
    W.AddAuction(512, 40, { quantity = 100 })
    W.AddAuction(520, 15, { quantity = 30 })
    W.AddAuction(521, 60, { quantity = 25 })
    W.AddAuction(522, 400, { quantity = 50 })
    W.AddAuction(530, 10, { quantity = 5 })
    W.AddAuction(531, 200, { quantity = 7 })
    W.AddAuction(560, 300, { quantity = 9 })
    W.AddAuction(561, 250, { quantity = 4 })
    W.AddAuction(562, 600, { quantity = 2 })
    W.AddAuction(563, 100, { quantity = 3 })
    W.AddAuction(564, 50000, { quantity = 1 })             -- more than the character has
end

-- What the game's tables say of the consumables above, in place of the real table: the test
-- items have numbers of their own. Call it after LoadAddon. (Nothing is said of the dynamite.)
local function SupplyFacts()
    ns.SupplyData.stats = {
        [560] = { ITEM_MOD_STRENGTH_SHORT = 8 }, [561] = { ITEM_MOD_AGILITY_SHORT = 8 }, [562] = { ITEM_MOD_AGILITY_SHORT = 15 },
        [563] = { ITEM_MOD_INTELLECT_SHORT = 6 }, [564] = { ITEM_MOD_STRENGTH_SHORT = 25 },
        [540] = { ITEM_MOD_AGILITY_SHORT = 8 }, [541] = { ITEM_MOD_STRENGTH_SHORT = 8 },
    }
    ns.SupplyData.restores = {
        [500] = "H", [501] = "H", [502] = "H", [503] = "H", [504] = "M",
        [510] = "H", [511] = "H", [512] = "H", [520] = "H", [521] = "H", [522] = "H",
    }
end

-- How the tab asks for the list: scores on a profile, and whether the character has mana.
local function SupplyOpts(profile, opts)
    opts.money = opts.money or GetMoney()
    opts.value = function(stats) return ns.Score.StatsValue(stats, profile) end
    return opts
end

local function Supply(name)
    for _, supply in pairs(ns.Scanner.supplies) do
        if supply.name == name then return supply end
    end
end

local function ScanSupplies()
    check(ns.Scanner.StartSupplies(), "consumables scan starts")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 120)
end

---------------------------------------------------------------------------
-- The best set for a budget (Plan.lua): which offers, bought together, add the most.
function scenarios.plan()
    StandardWorld()
    LoadAddon()
    local Plan = ns.Plan
    local GOLD = 10000
    local function Worn(id, invType, value)
        return { link = "worn" .. id, itemID = id, invType = invType, value = value }
    end
    local function For(id, invType, value, buyout)
        return { id = "o" .. id, itemID = id, invType = invType, value = value, buyout = buyout, link = "link" .. id, name = "Item " .. id, count = 1 }
    end
    local function Offers(list)
        local out = {}
        for _, offer in ipairs(list) do out[offer.id] = offer end
        return out
    end
    -- What a set holds, as "name:gain" in the order of the slots, with its sums.
    local function Read(set)
        local rows, summary = Plan.Rows(set)
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.itemID .. ":+" .. ns.Num(row.entry.delta) end
        end
        return table.concat(out, " "), summary, rows
    end
    local function Best(offers, ctx, budget, cap)
        return Read(Plan.Choose(Plan.Ladder(offers, ctx, cap or budget), budget))
    end

    -- A chest worth 10 and boots worth 10. For sale: a strong chest (+10) for 4 gold, a
    -- weaker one (+6) for 3 gold, which costs more per point, and boots (+8) for 2 gold.
    local ctx = { equipped = { [5] = Worn(1, "INVTYPE_CHEST", 10), [8] = Worn(2, "INVTYPE_FEET", 10) }, dualWield = false }
    local offers = Offers({
        For(11, "INVTYPE_CHEST", 20, 4 * GOLD), For(12, "INVTYPE_CHEST", 16, 3 * GOLD), For(13, "INVTYPE_FEET", 18, 2 * GOLD),
    })
    local set, summary, rows = Best(offers, ctx, 5 * GOLD)
    eq(set, "12:+6 13:+8", "five gold: the weaker chest and the boots add more than the strong chest alone")
    eq(summary.cost, 5 * GOLD, "for exactly five gold"); near(summary.gain, 14, "fourteen points")
    eq(summary.upgrades, 2, "two items"); eq(summary.slots, 2, "in two slots")
    eq(rows[1].kind, "header", "a heading first"); eq(rows[1].group, "CHEST", "the chest's, as the list orders its slots")
    eq(rows[1].plain, true, "with nothing to fold or count")
    near(rows[2].share, 6 / 8, "an item's meter measures its gain against the biggest of the set")
    eq(Best(offers, ctx, 6 * GOLD), "11:+10 13:+8", "six gold: the strong chest and the boots")
    eq(Best(offers, ctx, 4 * GOLD), "11:+10", "four gold: the strong chest alone, +10, beats the boots, +8")
    eq(Best(offers, ctx, 3 * GOLD), "13:+8", "three gold: the boots, +8, not the chest that fits, +6")
    eq(Best(offers, ctx, 1 * GOLD), "", "one gold: nothing")
    eq(Plan.Choose(Plan.Ladder(offers, ctx, GOLD), GOLD), nil, "which is no set at all")
    -- One ladder, made for all the money, answers every smaller budget.
    local ladder = Plan.Ladder(offers, ctx, 10 * GOLD)
    eq(Read(Plan.Choose(ladder, 5 * GOLD)), "12:+6 13:+8", "the same ladder at five gold")
    eq(Read(Plan.Choose(ladder, 10 * GOLD)), "11:+10 13:+8", "and at ten: more money buys nothing better")
    for i = 2, #ladder do
        check(ladder[i].cost > ladder[i - 1].cost and ladder[i].gain > ladder[i - 1].gain, "each rung dearer and stronger than the one below")
    end

    -- Rings: two are worn (4 and 6), so two can be bought, and the second replaces the better one.
    ctx = { equipped = { [11] = Worn(1, "INVTYPE_FINGER", 4), [12] = Worn(2, "INVTYPE_FINGER", 6) }, dualWield = false }
    offers = Offers({ For(21, "INVTYPE_FINGER", 10, GOLD), For(22, "INVTYPE_FINGER", 9, GOLD), For(23, "INVTYPE_FINGER", 5, 1000) })
    set, summary, rows = Best(offers, ctx, 2 * GOLD)
    eq(set, "21:+6 22:+3", "two gold: both strong rings, the first for the weak one worn, the second for the other")
    near(summary.gain, 9, "nineteen worn in place of ten")
    eq(rows[2].entry.replaced[1], "worn1", "the first takes the place of the weaker ring")
    eq(rows[3].entry.replaced[1], "worn2", "the second of the ring that was left")
    eq(Best(offers, ctx, GOLD + 1000), "21:+6", "one gold ten: the cheap ring would not be worn beside it, so it is not bought")
    eq(Best(offers, ctx, 1000), "23:+1", "ten silver: the cheap ring alone")
    -- A ring that two others outdo for no more money is no part of any set.
    offers.o24 = For(24, "INVTYPE_FINGER", 8, GOLD)
    eq(Best(offers, ctx, 3 * GOLD), "21:+6 22:+3", "three gold: still the two best")

    -- Hands: a sword (20) and a shield (5). A two-hander has to beat both; a sword and a shield
    -- are bought together.
    ctx = { equipped = { [16] = Worn(1, "INVTYPE_WEAPON", 20), [17] = Worn(2, "INVTYPE_SHIELD", 5) }, dualWield = false }
    offers = Offers({ For(31, "INVTYPE_2HWEAPON", 30, 2 * GOLD), For(32, "INVTYPE_WEAPON", 24, GOLD), For(33, "INVTYPE_SHIELD", 8, GOLD) })
    eq(Best(offers, ctx, 2 * GOLD), "32:+4 33:+3", "two gold: a sword and a shield, +7, not the two-hander, +5")
    eq(Best(offers, ctx, GOLD), "32:+4", "one gold: the sword")
    offers.o32 = nil
    eq(Best(offers, ctx, 3 * GOLD), "31:+5", "without the sword: the two-hander, and no shield with it")
    -- A dual wielder buys two one-handers.
    ctx = { equipped = { [16] = Worn(1, "INVTYPE_WEAPON", 20), [17] = Worn(2, "INVTYPE_WEAPON", 10) }, dualWield = true }
    offers = Offers({ For(41, "INVTYPE_WEAPON", 26, GOLD), For(42, "INVTYPE_WEAPON", 22, GOLD) })
    _, summary = Best(offers, ctx, 2 * GOLD)
    near(summary.gain, 18, "two swords for a dual wielder: 48 in place of 30"); eq(summary.upgrades, 2, "both bought")

    -- A second copy of a unique item is not worn, so not bought.
    ctx = { equipped = { [13] = Worn(1, "INVTYPE_TRINKET", 1) }, dualWield = false }
    local first, second = For(51, "INVTYPE_TRINKET", 9, GOLD), For(51, "INVTYPE_TRINKET", 9, GOLD + 1)
    first.unique, second.unique, second.id = true, true, "o51b"
    eq(Best(Offers({ first, second }), ctx, 3 * GOLD), "51:+9", "one of a unique trinket, not two")

    -- What was bought and is still in the mail counts as worn.
    ctx = { equipped = { [5] = Worn(1, "INVTYPE_CHEST", 10) }, dualWield = false }
    local wearing = Plan.Wearing(ctx, { { link = "bought", itemID = 12, invType = "INVTYPE_CHEST", value = 16 } })
    eq(ctx.equipped[5].value, 10, "the gear snapshot itself is left as it is")
    eq(wearing.equipped[5].link, "bought", "the chest that was bought is on in the copy")
    set, _, rows = Best(Offers({ For(11, "INVTYPE_CHEST", 20, GOLD), For(14, "INVTYPE_CHEST", 15, 100) }), wearing, 5 * GOLD)
    eq(set, "11:+4", "another chest is worth what it adds to the one bought; a weaker one is nothing")
    eq(rows[2].entry.replaced[1], "bought", "and replaces that one")
    eq(Plan.Wearing(ctx, {}), ctx, "nothing bought: the snapshot as it is")

    -- Nothing for sale, nothing worn.
    eq(Best({}, { equipped = {}, dualWield = false }, GOLD), "", "no offers, no set")

    -- A ladder with more rungs than are kept is thinned. Four kinds of six offers each, priced
    -- so that every choice among them is a rung of its own: 2401 rungs. Then a belt, which is
    -- joined to the thinned ladder.
    ctx = { equipped = {}, dualWield = false }
    local many, id = {}, 100
    for kind, invType in ipairs({ "INVTYPE_CLOAK", "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER" }) do
        for digit = 1, 6 do
            id = id + 1
            local worth = digit * 7 ^ (kind - 1)
            many[#many + 1] = For(id, invType, worth, worth)
        end
    end
    many[#many + 1] = For(200, "INVTYPE_WAIST", 10000, 5000)
    ladder = Plan.Ladder(Offers(many), ctx, 10000)
    check(#ladder <= 1002, "the ladder is thinned: " .. #ladder .. " rungs")
    eq(ladder[1].cost, 0, "its first rung is still to buy nothing")
    near(ladder[#ladder].gain, 10000 + 2400, "and its last the best set for all the money")
    eq(Read(Plan.Choose(ladder, 5000)), "200:+10000", "the belt alone is a set: it does not need the kinds joined before it")
    eq(Plan.Choose(ladder, 0), nil, "and no money is still no set")
    -- Whatever the budget, the set is close to the best there is: here the best for a sum is
    -- worth that sum (below the belt's price), and one part in a thousand of 12400 may be
    -- lost at each of the two joins that thinned.
    for _, budget in ipairs({ 1, 13, 500, 1234, 2400, 4999, 6000, 7399 }) do
        local best = budget < 5000 and math.min(budget, 2400) or 10000 + math.min(budget - 5000, 2400)
        local got = Plan.Choose(ladder, budget)
        check(got ~= nil and got.cost <= budget and got.gain > best - 2 * 12.4 - 1e-6,
            "a budget of " .. budget .. " gets " .. tostring(got and got.gain) .. " of " .. best)
    end
end

-- The strip under the list, and the list showing the set.
function scenarios.plan_ui()
    StandardWorld()
    -- A chest that "top five" has no use for: weaker than the Good Chest and dearer per point.
    W.AddItem({ id = 220, name = "Plain Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 13, level = 8 })
    W.AddAuction(220, 2000)
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local bar = frame.PlanBar
    check(bar ~= nil, "the strip is built with the tab")
    eq(bar:IsShown(), false, "and out of view before there is a scan")
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    -- The list as the player reads it: "[HEAD] Helm | [CHEST] ...".
    local function Listed()
        local out = {}
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry then
                out[#out + 1] = w.entry.offer.name
            elseif w._shown and w.Title then
                out[#out + 1] = "[" .. w.Title:GetText() .. "]"
            end
        end
        return table.concat(out, " ")
    end
    local function Row(name)
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry and w.entry.offer.name == name then return w end
        end
    end
    local function Settle()
        W.RunUntil(function() return S.state == "idle" end, 120)
        W.Run(0.3)
    end

    ScanToEnd()
    W.Run(0.3)
    eq(bar:IsShown(), true, "the strip comes with the first scan")
    eq(bar.Check.Text:GetText(), "Best set for", "its tick box")
    eq(bar.Check:GetChecked(), false, "not ticked")
    eq(bar.Gold:GetText(), "10", "the sum is all the gold there is"); eq(bar.Silver:GetText(), "00", "and its silver")
    eq(bar.Summary:GetText(), "", "nothing is summed while the list is the list")
    eq(Offer("Plain Chest"), nil, "the list had no use for the plain chest's price")
    check(Listed():find("[CHEST] Great Chest Good Chest", 1, true) ~= nil, "the list as ever: " .. Listed())

    -- Ticked: the prices the set can need are looked up, and the list is the set.
    local searches = W.AH.calls.search
    bar.Check:SetChecked(true)
    bar.Check:Click()
    eq(ns.db.plan, true, "the setting is kept")
    eq(S.mode, "more", "the missing price is asked for")
    Settle()
    eq(W.AH.calls.search, searches + 1, "one search: the plain chest")
    check(Offer("Plain Chest") ~= nil, "which now has its price")
    -- Ten gold: the robe (+20, 9 gold), the helm (+12), the ring (+6) and the shield (+7,
    -- which leaves the sword where it is; the two-hander would add +6).
    eq(Listed(), "[HEAD] Helm [CHEST] Great Chest [FINGER] New Ring [OFF HAND] Shield", "the set for ten gold: " .. Listed())
    eq(bar.Summary:GetText(), "4 items, +45 points, 9g 40s", "what it comes to")
    eq(frame.AffordCheck:IsEnabled(), false, "the price filter has no say in a set")
    eq(frame.TopCheck:IsEnabled(), false, "nor has top five")
    local heading = box:GetFrames()[1]
    eq(heading.Toggle:IsShown(), false, "a heading of the set does not fold"); eq(heading.Count:GetText(), "", "and counts nothing")
    eq(Row("Helm").Pick:IsShown(), false, "no picks in a set: all of it is the pick")
    eq(Row("Helm").Buy:IsEnabled(), true, "each item is bought from its row")
    -- A row of the set has the gains of every profile in its tooltip, as a row of the list.
    local helm = Row("Helm")
    helm:GetScript("OnEnter")(helm)
    local gains = {}
    for _, line in ipairs(GameTooltip._lines) do
        if line.right then gains[#gains + 1] = line.text .. " " .. line.right end
    end
    eq(table.concat(gains, ", "), "Arms +12 pts, Protection ~ +0 pts", "the helm for the empty head, on both profiles")
    helm:GetScript("OnLeave")(helm)

    -- A smaller sum.
    W.Type(bar.Gold, "0")
    eq(bar.Silver:GetText(), "00", "a sum typed in gold is in whole gold")
    W.Run(0.3)
    eq(S.budget, 0, "no gold: a budget of nothing")
    eq(Listed(), "", "which buys nothing")
    eq(bar.Summary:GetText(), "No upgrade fits this sum.", "and the strip says so")
    check(frame.List.Hint:GetText():find("No upgrade fits this sum.", 1, true) ~= nil, "as does the middle of the empty list")
    W.Type(bar.Silver, "60")
    W.Run(0.3)
    eq(S.budget, 6000, "sixty silver")
    -- Helm, ring and shield come to 40 silver; the 20 left buy the plain chest (+3), which
    -- the good chest (+8, 40 silver) had hidden from the list.
    eq(Listed(), "[HEAD] Helm [CHEST] Plain Chest [FINGER] New Ring [OFF HAND] Shield", "the set for sixty silver: " .. Listed())
    eq(bar.Summary:GetText(), "4 items, +28 points, 60s", "what it comes to")
    W.Type(bar.Silver, "45")
    W.Run(0.3)
    eq(Listed(), "[HEAD] Helm [FINGER] New Ring [OFF HAND] Shield", "forty-five silver: without a chest")

    -- Buying from the set: what is bought counts as worn, and the sum goes down by its price.
    W.Type(bar.Silver, "60")
    W.Run(0.3)
    Row("Helm").Buy:Click()
    Settle()
    check(Asking() ~= nil, "the usual question")
    Asking().Buy:Click()
    W.RunUntil(function() return #S.acquired == 1 end, 30)
    Settle()
    eq(S.budget, 3500, "the helm's 25 silver are spent")
    eq(bar.Gold:GetText(), "0", "the sum in the strip"); eq(bar.Silver:GetText(), "35", "follows")
    eq(Listed(), "[CHEST] Plain Chest [FINGER] New Ring [OFF HAND] Shield", "the rest of the set stays as it was: " .. Listed())
    eq(bar.Summary:GetText(), "3 items, +16 points, 35s", "and comes to the rest of the sum")
    -- The helm arrives and is put on: nothing changes for the set.
    W.equipped[1] = W.Link(211)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    eq(#S.acquired, 0, "what is worn is gear now")
    eq(Listed(), "[CHEST] Plain Chest [FINGER] New Ring [OFF HAND] Shield", "the set after the helm is on: " .. Listed())

    -- Both fields emptied: all the gold there is again.
    W.Type(bar.Gold, "")
    W.Type(bar.Silver, "")
    W.Run(0.3)
    eq(S.budget, nil, "no sum of one's own")
    eq(bar.Gold:GetText(), "9", "the strip shows the purse: ten gold less the helm"); eq(bar.Silver:GetText(), "75", "to the silver")
    eq(Listed(), "[CHEST] Great Chest [FINGER] New Ring [OFF HAND] Shield", "and the set is the one for all of it: " .. Listed())

    -- Unticked: the list again, filters and all.
    bar.Check:SetChecked(false)
    bar.Check:Click()
    W.Run(0.3)
    eq(ns.db.plan, false, "the setting is kept")
    eq(frame.AffordCheck:IsEnabled(), true, "the filters are back")
    eq(bar.Summary:GetText(), "", "nothing summed")
    check(Listed():find("[CHEST] Great Chest Good Chest", 1, true) ~= nil, "the list as ever: " .. Listed())
    check(box:GetFrames()[1].Toggle:IsShown(), "its headings fold again")

    -- A scan with the box ticked looks up what the set needs from the start.
    bar.Check:SetChecked(true)
    bar.Check:Click()
    ScanToEnd()
    W.Run(0.3)
    check(Offer("Plain Chest") ~= nil, "the plain chest is priced by the scan itself")
    eq(Listed(), "[CHEST] Great Chest [FINGER] New Ring [OFF HAND] Shield", "the set after a new scan: " .. Listed())

    -- The Consumables view has no strip.
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScoutSupplies")
    W.Run(0.3)
    eq(bar:IsShown(), false, "no strip over consumables")
    eq(frame.AffordCheck:IsEnabled(), true, "and their price filter works")
end

---------------------------------------------------------------------------
-- Net cost: gear priced at its buyout less what a vendor pays for it afterwards. What the
-- list makes of it, and that a scan looks up the prices the list needs by net cost and by
-- buyout alike, so that the box can be ticked afterwards without a search.
function scenarios.net()
    BusyWorld()
    -- What a vendor pays for each of the 150 items: from nothing up to two gold, so that many
    -- of them sell for more than they cost at auction.
    for i = 1, 150 do W.items[(2000 + i) .. ":0"].sell = (i * 7919) % 20000 end
    W.player.money = 15000
    LoadAddon()
    local R = ns.Results

    eq(R.Net(400, 300), 100, "bought for 4 silver and sold for 3: it cost 1")
    eq(R.Net(400, 0), 400, "an item no vendor buys costs its whole buyout")
    eq(R.Net(400), 400, "and so does one of which nothing is known")
    eq(R.Net(200, 300), 0, "an auction below the vendor's price costs nothing, and no less than that")
    eq(R.Cost({ buyout = 400, sell = 300 }, false), 400, "the list prices an offer at its buyout")
    eq(R.Cost({ buyout = 400, sell = 300 }, true), 100, "or, with the box ticked, at its net cost")

    -- Three chests against one worth 10. By buyout the cheap one is the best value. The dear
    -- one sells back for nearly all of its price: by net cost it is the cheapest per point.
    local ctx = { equipped = { [5] = { link = "WORN", value = 10, invType = "INVTYPE_CHEST", itemID = 1 } } }
    local function offer(id, value, buyout, sell)
        return { id = id, name = id, value = value, buyout = buyout, sell = sell, invType = "INVTYPE_CHEST", itemID = 100, count = 1 }
    end
    local offers = {
        a = offer("a", 50, 100000, 96000),  -- +40 for 10 gold, 40 silver net: 100 a point
        b = offer("b", 30, 20000, 2000),    -- +20 for 2 gold, 1 gold 80 net: 900 a point
        c = offer("c", 22, 6000, 0),        -- +12 for 60 silver, which no vendor gives back: 500 a point
    }
    local rows
    -- "a@100000!UPGRADE b@20000 ...": the offers of the chest slot with what the list prices them at.
    local function Read()
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then
                out[#out + 1] = row.entry.offer.id .. "@" .. row.entry.cost .. (row.entry.pick and ("!" .. row.entry.pick) or "")
            end
        end
        return table.concat(out, " ")
    end
    rows = R.Build(offers, ctx, { money = 1e9 })
    eq(Read(), "a@100000!UPGRADE b@20000 c@6000!VALUE", "by buyout: the cheap chest is the best value")
    near(rows[2].entry.costPer, 2500, "a point of the dear one costs 25 silver")
    rows = R.Build(offers, ctx, { money = 1e9, net = true })
    eq(Read(), "a@4000!BOTH b@18000 c@6000", "by net cost: the dear chest is the best value too")
    near(rows[2].entry.costPer, 100, "a point of it costs a silver in the end")
    eq(rows[2].entry.offer.buyout, 100000, "the offer keeps its buyout")
    -- "Top N per slot" goes by the same price: nothing weaker is cheaper per point than the dear chest.
    rows = R.Build(offers, ctx, { money = 1e9, net = true, limit = 5 })
    eq(Read(), "a@4000!BOTH", "top five by net cost: the dear chest alone")
    eq(rows[1].shown, 1, "one row"); eq(rows[1].total, 3, "of three")
    rows = R.Build(offers, ctx, { money = 1e9, limit = 5 })
    eq(Read(), "a@100000!UPGRADE b@20000 c@6000!VALUE", "top five by buyout: each cheaper per point than the one above")
    -- What can be paid for is a matter of the buyout: ten gold are not there, whatever comes back later.
    local summary
    rows, summary = R.Build(offers, ctx, { money = 50000, affordableOnly = true, net = true })
    eq(Read(), "b@18000!UPGRADE c@6000!VALUE", "five gold: the dear chest is left out for its buyout")
    eq(summary.hidden, 1, "and counted as too dear")
    rows = R.Build(offers, ctx, { money = 50000, net = true })
    eq(rows[2].entry.affordable, false, "listed, it is marked as too dear")

    -- Of two offers that gain the same, the one that costs less in the end stands first.
    offers = { d = offer("d", 30, 5000, 100), e = offer("e", 30, 6000, 2000) }
    rows = R.Build(offers, ctx, { money = 1e9 })
    eq(Read(), "d@5000!BOTH e@6000", "by buyout")
    rows = R.Build(offers, ctx, { money = 1e9, net = true })
    eq(Read(), "e@4000!BOTH d@4900", "by net cost")
    -- An offer below the vendor's price costs nothing a point: no better value than that.
    offers = { a = offer("a", 50, 100000, 96000), f = offer("f", 40, 300, 500), g = offer("g", 35, 300, 500) }
    rows = R.Build(offers, ctx, { money = 1e9, net = true, limit = 5 })
    eq(Read(), "a@4000!UPGRADE f@0!VALUE", "free in the end: the best value, and nothing weaker has a place beside it")

    -- What the scanner asks before an item search: would "top five" hide an item whatever its
    -- price turns out to be? It asks that of the list by net cost and of the one by buyout, and
    -- the least the item can cost is a cost of the same kind.
    local entries = R.Collect({ a = offer("a", 50, 100000, 96000) }, ctx, { money = 1e9 }).CHEST
    eq(R.Dominated(entries, 20, 2000, true), true, "by net cost, +20 for a silver a point at the least: no cheaper than the dear chest")
    eq(R.Dominated(entries, 20, 1999, true), false, "a copper less and it may be worth a row")
    eq(R.Dominated(entries, 40, 4001, true), true, "the same gain for more")
    eq(R.Dominated(entries, 40, 4000, true), false, "but not for the same")
    eq(R.Dominated(entries, 20, 2000, false), false, "by buyout the dear chest rules that item out no more")
    eq(R.Dominated(entries, 20, 50000, false), true, "+20 for 25 silver a point at the least: by buyout no cheaper than it")
    eq(R.Dominated(entries, 20, 49999, false), false, "a copper less and it may be worth a row there too")
    entries = R.Collect({ a = offer("a", 50, 100000, 96000) }, ctx, { money = 1e9, net = true }).CHEST
    eq(R.Dominated(entries, 20, 2000, false), false, "the answer is the same for entries that were priced at their net cost")
    eq(R.Dominated(entries, 20, 2000, true), true, "either way")

    -- A set is chosen by its buyouts, and says what it costs in the end.
    local plan = ns.Plan
    local worn = { equipped = { [5] = { link = "worn", itemID = 1, invType = "INVTYPE_CHEST", value = 10 } }, dualWield = false }
    local chest = { id = "o1", itemID = 11, invType = "INVTYPE_CHEST", value = 20, buyout = 40000, sell = 30000, link = "l1", name = "Chest", count = 1 }
    local boots = { id = "o2", itemID = 12, invType = "INVTYPE_FEET", value = 8, buyout = 20000, sell = 25000, link = "l2", name = "Boots", count = 1 }
    local set = plan.Choose(plan.Ladder({ o1 = chest, o2 = boots }, worn, 60000), 60000)
    rows, summary = plan.Rows(set, true)
    eq(summary.cost, 60000, "a set for six gold"); eq(summary.net, 10000, "costs one in the end: the boots sell for more than they cost")
    eq(Read(), "o1@10000 o2@0", "its rows are priced at their net cost")
    rows, summary = plan.Rows(set)
    eq(Read(), "o1@40000 o2@20000", "or at their buyouts"); eq(summary.net, 10000, "with the same net cost of the set")
    eq(plan.Choose(plan.Ladder({ o1 = chest, o2 = boots }, worn, 30000), 30000).cost, 20000,
        "three gold buy the boots alone: the chest's net cost of one gold does not make it fit")

    -- The scan. Reference: both filters off, so every price is looked up.
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local function Shown(net, topOnly)
        local list = R.Build(S.offers, S.ctx, { money = GetMoney(), affordableOnly = true, net = net, limit = topOnly and R.TOP_COUNT or nil })
        local out = {}
        for _, row in ipairs(list) do
            if row.kind == "header" then
                out[#out + 1] = "[" .. row.group .. "]"
            else
                local entry = row.entry
                out[#out + 1] = entry.offer.id .. "@" .. entry.cost .. (entry.pick and ("!" .. entry.pick) or "")
            end
        end
        return table.concat(out, " ")
    end
    local function Scan(net, affordableOnly, topOnly)
        ns.db.net = net
        SetView(affordableOnly, topOnly)
        W.RunUntil(function() return W.AH.ready end, 5)
        local before = W.AH.calls.search
        ScanToEnd()
        return W.AH.calls.search - before
    end
    local function Idle() return S.state == "idle" end

    local all = Scan(true, false, false)
    eq(S.stats.skipped, 0, "the reference scan skips nothing")
    local free, cheaper = 0, 0
    for _, found in pairs(S.offers) do
        eq(found.sell, W.items[found.itemID .. ":0"].sell, "an offer knows what a vendor pays for its item")
        if R.Net(found.buyout, found.sell) == 0 then free = free + 1 elseif found.sell > 0 then cheaper = cheaper + 1 end
    end
    check(free >= 10 and cheaper >= 10, "offers below the vendor's price and above it (" .. free .. ", " .. cheaper .. ")")
    local want = { net = Shown(true, true), buyout = Shown(false, true) }
    check(want.net ~= want.buyout, "the net cost changes what 'top five' shows in this world")

    -- Scanned with the filters on, the scan looks up the prices either list needs, the one by
    -- net cost and the one by buyout: fewer searches than all of them, and both lists as the
    -- full scan has them.
    local used = Scan(true, true, true)
    eq(Shown(true, true), want.net, "the same list by net cost as the full scan")
    eq(Shown(false, true), want.buyout, "and the same list by buyout")
    check(used < all, "for fewer item searches (" .. used .. " of " .. all .. ")")
    eq(S.stats.searches + S.stats.skipped, S.stats.candidates, "every candidate is either searched or skipped")

    -- The box has no say in what a scan looks up, so ticking it afterwards sends for nothing.
    local plain = Scan(false, true, true)
    eq(plain, used, "a scan with the box unticked sends the same searches")
    eq(Shown(false, true), want.buyout, "for the same list by buyout")
    eq(S.Demand(), false, "which needs nothing more")
    local before = W.AH.calls.search
    ns.db.net = true
    eq(S.Demand(), false, "ticked after the scan: no price is sent for")
    eq(Shown(true, true), want.net, "and the list is the one a scan with the box ticked makes")
    ns.db.net = false
    eq(S.Demand(), false, "unticked: nor then")
    eq(Shown(false, true), want.buyout, "and the list by buyout is back")
    W.RunUntil(Idle, 5)
    eq(W.AH.calls.search, before, "not one item search for all that")
    realPrint(string.format("      item searches: %d with both filters off, %d with them on", all, used))
end

-- The "Net cost" box of the Upgrades tab, and what it changes there.
function scenarios.net_ui()
    StandardWorld()
    -- What a vendor pays. The robe sells back for nearly all of its nine gold, the good chest
    -- for a quarter of its 40 silver. No vendor buys the helm. The ring is for sale below its
    -- vendor price. The axe and the shield sell for the stand-in's one silver.
    W.items["201:0"].sell = 88000
    W.items["200:0"].sell = 1000
    W.items["211:0"].sell = 0
    W.items["210:0"].sell = 900
    -- A chest that adds little, +4 for 18 silver. By buyout that is less per point than the
    -- good chest's 50 copper, so "top five" lists it; too small a gain to be the best value.
    -- By net cost the robe costs less per point, and the list has no use for it.
    W.AddItem({ id = 221, name = "Slight Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 14, level = 8 })
    W.AddAuction(221, 1800)
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    local tabs = LibStub("LibAHTab-1-0")
    tabs:SetSelected("UpgradeScout")
    local list, net, afford, top = frame.List, frame.NetCheck, frame.AffordCheck, frame.TopCheck
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    local function Row(name)
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry and w.entry.offer.name == name then return w end
        end
    end
    local function Heading(title)
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w.Title and w.Title:GetText() == title then return w end
        end
    end
    local function Settle()
        W.RunUntil(function() return S.state == "idle" end, 120)
        W.Run(0.3)
    end
    local function Tick(tickBox, on)
        tickBox:SetChecked(on)
        tickBox:Click()
        Settle()
    end
    -- The lines of the tooltip that is up, by the words on their left.
    local function Lines()
        local out = {}
        for _, line in ipairs(GameTooltip._lines) do out[line.text] = line end
        return out
    end

    -- The box: the last in the row of tick boxes above the list, off until it is ticked.
    check(net ~= nil, "the tab has the box")
    eq(net._kind, "CheckButton", "a tick box like the filters"); eq(net.Text:GetText(), "Net cost", "with its label")
    eq(net:IsShown(), true, "in view on the Upgrades tab")
    eq(net:GetChecked(), false, "not ticked"); eq(net.Tick:IsShown(), false, "no tick showing")
    eq(ns.db.net, nil, "off until the player says otherwise")
    net:GetScript("OnEnter")(net)
    eq(GameTooltip._lines[1].text, "Net cost", "its tooltip is titled with its label")
    check(GameTooltip._lines[2].text:find("less what a vendor pays for it", 1, true) ~= nil, "and says what a net cost is")
    check(GameTooltip._lines[2].text:find("Bought for 4 silver and sold for 3, it cost you 1.", 1, true) ~= nil, "with an example")
    net:GetScript("OnLeave")(net)
    -- Where the boxes stand, from the left edge of the window (800 wide): each a box, a gap and
    -- its label wide, 16 apart, the last one ending 14 short of the right edge. The profile
    -- field keeps clear of the first.
    local function Left(part)
        eq(#part._points, 1, "one anchor"); eq(part._points[1].point, "LEFT", "by its left edge")
        return 800 + part._points[1].x
    end
    local function Width(part) return 16 + 6 + part.Text:GetStringWidth() end
    eq(Left(net) + Width(net), 800 - 14, "the net cost box ends at the right end of the bar")
    eq(Left(top) + Width(top) + 16, Left(net), "top five stands before it")
    eq(Left(afford) + Width(afford) + 16, Left(top), "and the price filter before that")
    local dropdown, scan = frame.ProfileDropdown, frame.ScanButton
    eq(frame.ProfileLabel:IsShown(), true, "the profile field keeps its caption: its menu has no other characters")
    check(dropdown:GetWidth() >= 110, "and a width that shows a profile's name (" .. dropdown:GetWidth() .. ")")
    check(72 + scan:GetWidth() + dropdown._points[1].x + dropdown:GetWidth() + 16 <= Left(afford), "and ends clear of the first box")

    -- By buyout, as ever.
    ScanToEnd()
    W.Run(0.3)
    eq(list.Titles[4]:GetText(), "BUYOUT", "the price column is headed by what it shows")
    eq(Row("Great Chest").Price:GetAmount(), 90000, "the robe at its nine gold"); eq(Row("Great Chest").Pick.Text:GetText(), "Best upgrade", "the best upgrade")
    eq(Row("Good Chest").Price:GetAmount(), 4000, "the good chest at its 40 silver"); eq(Row("Good Chest").Pick.Text:GetText(), "Best value", "the best value")
    eq(Row("Slight Chest").Price:GetAmount(), 1800, "the slight chest under them")
    local robe = Row("Great Chest")
    robe:GetScript("OnEnter")(robe)
    eq(Lines().Buyout, nil, "a row's tooltip says nothing of the price: the row does"); eq(Lines()["Sell Price"], nil, "nor of what a vendor pays")
    robe:GetScript("OnLeave")(robe)

    -- Ticked: the column shows what each item costs in the end, and the picks go by that.
    local searches = W.AH.calls.search
    local sounds = #W.sounds
    Tick(net, true)
    eq(#W.sounds, sounds + 1, "the box clicks")
    eq(ns.db.net, true, "the setting is kept"); eq(UpgradeScoutCharDB.net, true, "with the character's saved ones")
    eq(net.Tick:IsShown(), true, "the tick shows")
    eq(W.AH.calls.search, searches, "nothing to look up: every price here was known")
    eq(list.Titles[4]:GetText(), "NET COST", "the column is headed anew")
    robe = Row("Great Chest")
    eq(robe.Price:GetAmount(), 2000, "the robe: nine gold less the 8 gold 80 a vendor pays")
    eq(robe.Price._font, PriceFontWhite, "in white: its buyout can be paid")
    eq(robe.Pick.Text:GetText(), "Best of both", "the strongest chest is the cheapest per point too: 20 silver for +20")
    eq(Row("Good Chest"), nil, "top five has no use for the good chest now: weaker, and 30 silver for +8")
    eq(Row("Slight Chest"), nil, "nor for the slight one: 17 silver for +4")
    eq(Heading("CHEST").Count:GetText(), "1 of 3", "the heading counts them")
    eq(Row("Helm").Price:GetAmount(), 2500, "no vendor buys the helm: its whole buyout")
    eq(Row("New Ring").Price:GetAmount(), 0, "the ring is for sale below its vendor price: it costs nothing in the end")
    eq(Row("Big Axe").Price:GetAmount(), 2900, "the axe less its silver"); eq(Row("Shield").Price:GetAmount(), 600, "and the shield")
    eq(Row("Helm").Upgrade:GetText(), "New", "the gains are what they were")

    -- A row's tooltip then has the two halves of its price, the second under the game's own name for it.
    robe:GetScript("OnEnter")(robe)
    local tip = Lines()
    check(tip.Buyout ~= nil, "what is paid now"); eq(tip.Buyout.right, "9g", "the buyout")
    eq(tip.Buyout.r, NORMAL_FONT_COLOR.r, "its name in the tooltip's gold"); eq(tip.Buyout.rightR, 1, "the sum in white")
    check(tip["Sell Price"] ~= nil, "what comes back, without the space the game's words end in"); eq(tip["Sell Price"].right, "8g 80s", "from a vendor")
    eq(tip.Arms.right, "+200%", "under the gains on every profile, which stay")
    robe:GetScript("OnLeave")(robe)
    local helm = Row("Helm")
    helm:GetScript("OnEnter")(helm)
    tip = Lines()
    eq(tip.Buyout.right, "25s", "the helm's buyout"); eq(tip["Sell Price"], nil, "and no sell price")
    check(tip["No sell price"] ~= nil, "the game's words for an item no vendor buys")
    eq(tip["No sell price"].r, DISABLED_FONT_COLOR.r, "in grey")
    helm:GetScript("OnLeave")(helm)

    -- A scan with the box ticked sends the searches a scan without it sends: it looks up what
    -- the list needs either way, so that the box can be ticked and unticked without one. (The
    -- list by net cost has no use for the slight chest; its price is looked up for the list
    -- by buyout, which has a row for it.)
    eq(searches, 9, "the scan by buyout: nine item searches")
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.3)
    eq(W.AH.calls.search - searches, 9, "the scan by net cost: the same nine")
    check(Offer("Slight Chest") ~= nil, "the slight chest's price is known")
    eq(Row("Slight Chest"), nil, "and the list by net cost has no row for it")
    eq(Heading("CHEST").Count:GetText(), "1 of 3", "its heading counts it")
    Tick(net, false)
    eq(W.AH.calls.search - searches, 9, "unticked: no search")
    check(Row("Slight Chest") ~= nil, "and the slight chest is in the list by buyout")
    eq(Row("Good Chest").Pick.Text:GetText(), "Best value", "under the best value")
    Tick(net, true)
    eq(W.AH.calls.search - searches, 9, "ticked again: no search")
    eq(Row("Slight Chest"), nil, "and it is out of the list once more")

    -- The best set for a budget is chosen by buyouts, as ever. Its rows are priced as the list's,
    -- and the strip says both sums.
    local bar = frame.PlanBar
    Tick(bar.Check, true)
    eq(bar.Summary:GetText(), "4 items, +45 points, 9g 40s, net cost 51s", "the set for ten gold: what is paid, and what it costs in the end")
    eq(Row("Great Chest").Price:GetAmount(), 2000, "a row of the set at its net cost")
    eq(list.Titles[4]:GetText(), "NET COST", "under the same heading")
    eq(net:IsEnabled(), true, "the box keeps its say in a set"); eq(top:IsEnabled(), false, "where the filters have none")
    Tick(net, false)
    eq(bar.Summary:GetText(), "4 items, +45 points, 9g 40s", "unticked: the set and its buyouts")
    eq(Row("Great Chest").Price:GetAmount(), 90000, "row by row")
    Tick(net, true)
    Tick(bar.Check, false)

    -- What can be paid for is a matter of the buyout. With five gold the robe is out of reach,
    -- whatever a vendor would give for it later.
    W.player.money = 50000
    W.Fire("PLAYER_MONEY")
    Settle()
    eq(Row("Great Chest"), nil, "five gold: the robe is left out, 20 silver in the end or not")
    eq(Row("Good Chest").Pick.Text:GetText(), "Best of both", "and the good chest is the pick of the slot")
    Tick(afford, false)
    robe = Row("Great Chest")
    eq(robe.Price:GetAmount(), 2000, "listed again, at its net cost"); eq(robe.Price._font, PriceFontRed, "in red: its buyout cannot be paid")
    eq(robe.Buy:IsEnabled(), false, "and it cannot be bought")
    robe:GetScript("OnEnter")(robe)
    check(Lines()["You are 4g short."] ~= nil, "the tooltip counts what is missing from the buyout")
    robe:GetScript("OnLeave")(robe)
    W.player.money = 100000
    W.Fire("PLAYER_MONEY")
    Tick(afford, true)

    -- The box that asks before a purchase: what is paid, and under it what it costs in the end.
    Row("Great Chest").Buy:Click()
    W.RunUntil(Asking, 30)
    local ask = Asking()
    eq(ask.TotalLabel:GetText(), "BUYOUT", "the buyout"); eq(ask.Total:GetAmount(), 90000, "is what is paid")
    eq(ask.NetLabel:IsShown(), true, "a third line"); eq(ask.NetLabel:GetText(), "NET COST", "headed as the column is")
    eq(ask.Net:IsShown(), true, "with its coins"); eq(ask.Net:GetAmount(), 2000, "the net cost, as the row has it")
    eq(ask:GetHeight(), 194, "the box is taller by the line")
    eq(ask.Gain:GetText(), "+200%", "above them the gain")
    -- The tick box is in reach while the box is up.
    net:SetChecked(false)
    net:Click()
    eq(ask.NetLabel:IsShown(), false, "unticked: the line goes"); eq(ask.Net:IsShown(), false, "with its coins")
    eq(ask:GetHeight(), 162, "and the box is as it was")
    net:SetChecked(true)
    net:Click()
    eq(ask.Net:IsShown(), true, "ticked: back again")
    ask.Buy:Click()
    eq(#W.AH.calls.bids, 1, "bought"); eq(W.AH.calls.bids[1].amount, 90000, "for the buyout")
    W.RunUntil(function() return not ask:IsShown() end, 5)
    Settle()

    -- A consumable is used up: no net cost in the other view.
    tabs:SetSelected("UpgradeScoutSupplies")
    W.Run(0.3)
    eq(net:IsShown(), false, "no such box over consumables")
    eq(list.Titles[4]:GetText(), "EACH", "whose price column is the price of a piece")
    local best = frame.BestCheck
    eq(Left(best) + Width(best), 800 - 14, "their own box stands at the right end")
    eq(Left(afford) + Width(afford) + 16, Left(best), "and the price filter before it")
    tabs:SetSelected("UpgradeScout")
    W.Run(0.3)
    eq(net:IsShown(), true, "back on the Upgrades tab"); eq(net:GetChecked(), true, "still ticked")
    eq(list.Titles[4]:GetText(), "NET COST", "and the column still by net cost")
    eq(Left(net) + Width(net), 800 - 14, "the boxes where they were")

    -- An auction house that deals in whole silver shows no copper in a buyout. A net cost has
    -- copper all the same: a vendor pays to the copper.
    W.AH.copper = false
    ns.UI.Refresh()
    local shield = Row("Shield")
    eq(shield.Price:GetAmount(), 600, "the shield at its net cost")
    eq(shield.Price.CopperDisplay:IsShown(), true, "to the copper")
    Tick(net, false)
    shield = Row("Shield")
    eq(shield.Price:GetAmount(), 700, "at its buyout"); eq(shield.Price.CopperDisplay:IsShown(), false, "in whole silver")
    eq(list.Titles[4]:GetText(), "BUYOUT", "under the old heading")
    eq(ns.db.net, false, "the setting is kept")

    -- Price checks that were stopped stay stopped when the box is ticked: it changes how the
    -- prices are read, and asks for none. A filter changes what the list shows, and they go on.
    Tick(afford, false)
    Tick(top, false)
    W.RunUntil(function() return W.AH.ready end, 5)
    scan:Click()
    W.RunUntil(function() return S.state == "verify" and OfferCount() >= 2 end, 60)
    scan:Click()
    eq(S.state, "idle", "a scan stopped during its price checks"); eq(S.halted, true, "which wait")
    W.Run(0.3)
    local sent, known = W.AH.calls.search, OfferCount()
    Tick(net, true)
    eq(S.halted, true, "the box ticked: they still wait"); eq(S.message, ns.L.ST_STOPPED, "under the same note")
    Tick(net, false)
    eq(S.halted, true, "unticked: the same")
    eq(W.AH.calls.search, sent, "no search was sent"); eq(OfferCount(), known, "and no price came in")
    Tick(top, true)
    eq(S.halted, false, "a filter ticked: they go on")
    check(W.AH.calls.search > sent, "with the searches that were left")
end

-- Which consumables do the same thing, which of them is the best, and the rows of the list.
function scenarios.supplies()
    LoadAddon()
    local P = ns.Supplies

    local kind, power = P.Describe("Restores 700 to 900 health.")
    eq(kind, "Restores # to # health.", "the numbers taken out"); eq(power, 900, "the biggest of them")
    eq((P.Describe("Restores 70 to 90 health.")), kind, "the same kind whatever the numbers")
    check(P.Describe("Restores 70 to 90 mana.") ~= kind, "another effect is another kind")
    kind, power = P.Describe("Heals 1,360 damage over 8 sec.")
    eq(kind, "Heals # damage over # sec.", "a thousands separator belongs to its number"); eq(power, 1360, "which is read whole")
    kind, power = P.Describe("Stellt 1.050 bis 1.750 Gesundheit wieder her.")
    eq(kind, "Stellt # bis # Gesundheit wieder her.", "the German separator too"); eq(power, 1750, "read whole")
    kind, power = P.Describe("Lasts 1.5 sec, 12 times.")
    eq(kind, "Lasts #.# sec, # times.", "a decimal point is not a separator"); eq(power, 12, "biggest number")
    kind, power = P.Describe("Eat me.")
    eq(kind, "Eat me.", "text without numbers stays"); eq(power, 0, "and has no number")

    -- What the game's tables say of an item: `facts` is its stats, or the letters of what it restores.
    local function Make(id, sub, effect, level, price, quantity, facts)
        local k, p = P.Describe(effect)
        return { id = id, name = id, sub = sub, kind = k, power = p, effect = effect, reqLevel = level, price = price, quantity = quantity,
            stats = type(facts) == "table" and facts or nil, restores = type(facts) == "string" and facts or nil }
    end
    local list = {
        a = Make("a", 1, "Restores 70 to 90 health.", 1, 30, 40, "H"),
        b = Make("b", 1, "Restores 455 to 585 health.", 21, 900, 13, "H"),
        c = Make("c", 1, "Restores 455 to 585 mana.", 22, 30000, 6, "M"),
        d = Make("d", 5, "Restores 874 health over 27 sec.", 25, 120, 60, "H"),
        e = Make("e", 5, "Restores 874 health over 27 sec.", 25, 90, 20, "H"),
        f = Make("f", 7, "Heals 161 damage over 7 sec.", 1, 15, 30, "H"),
        g = Make("g", 7, "Heals 301 damage over 7 sec.", 1, 60, 25, "H"),
        h = Make("h", 42, "Does 5 things.", 1, 10, 1),
        i = Make("i", 2, "Increases Agility by 8 for 1 hr.", 18, 500, 9, { Agility = 8 }),
        j = Make("j", 2, "Increases Agility by 15 for 1 hr.", 27, 700, 2, { Agility = 15 }),
        k = Make("k", 2, "Increases Intellect by 25 for 1 hr.", 37, 400, 5, { Intellect = 25 }),
        l = Make("l", 2, "Increases Strength by 8 for 1 hr.", 20, 300, 80, { Strength = 8 }),
        m = Make("m", 2, "Allows breathing under water for 30 min.", 8, 50, 3),
        n = Make("n", 1, "Restores 300 mana and 300 health.", 15, 200, 4, "HM"),
    }
    -- Weights for someone who hits things: nothing for Intellect.
    local weights = { Agility = 1, Strength = 1.5 }
    local function Value(stats)
        local total = 0
        for name, amount in pairs(stats) do total = total + amount * (weights[name] or 0) end
        return total
    end
    local function Text(rows)
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "header" then
                out[#out + 1] = string.format("[%s %d/%d]", row.title, row.shown, row.total)
            else
                local entry = row.entry
                out[#out + 1] = entry.supply.id .. (entry.best and "*" or "") .. (entry.affordable and "" or "!")
                    .. (entry.useless and "~" or "") .. (entry.value and "=" .. entry.value or "")
            end
        end
        return table.concat(out, " ")
    end

    -- The default view, for a character without mana: the best of each kind that is of use,
    -- among what the character can pay for.
    local rows, summary = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 3/4] j*=15 l*=12 m* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "what restores first, health before health and mana; then by score, the higher first; then what has none")
    eq(summary.items, 8, "rows counted"); eq(summary.groups, 5, "subcategories counted")
    eq(summary.useless, 2, "mana for a character without it and Intellect on a scale without it are left out")
    eq(summary.hidden, 0, "and are not counted among what costs too much")
    eq(rows[1].group, "SUB1", "a heading is known by its subcategory")

    -- The same for a character with mana: the mana potion is of use, only too dear.
    _, summary = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = true })
    eq(summary.useless, 1, "with mana, only the Intellect elixir is of no use"); eq(summary.hidden, 1, "and the mana potion costs too much")

    -- Everything: kinds stay together; what is of no use goes last and is marked.
    rows, summary = P.Build(list, { money = 20000, affordableOnly = false, bestOnly = false, value = Value, mana = false })
    eq(Text(rows), "[Potions 4/4] b* a n* c*!~ [Elixirs 5/5] j*=15 i=8 l*=12 m* k*~ [Food & Drink 2/2] e* d [Bandages 2/2] g* f [Other 1/1] h*",
        "every consumable, the best of its kind first and marked")
    eq(summary.items, 14, "all listed"); eq(summary.hidden, 0, "nothing left out"); eq(summary.useless, 0, "not even what is of no use")
    local why = {}
    for _, row in ipairs(rows) do
        if row.entry and row.entry.useless then why[row.entry.supply.id] = row.entry.why end
    end
    eq(why.c, "MANA", "the mana potion says why it is of no use"); eq(why.k, "WEIGHT", "and so does the elixir")

    -- Other weights turn the elixirs around without another scan.
    weights = { Intellect = 1 }
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = true })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 2/2] k*=25 m* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "on weights for Intellect its elixir is the one worth having")
    weights = { Agility = 1, Strength = 1.5 }

    -- Without a way to score, nothing has a score and nothing is left out; kinds keep an
    -- order all the same: what restores, then the rest from the highest level down.
    rows, summary = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, mana = true })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 4/5] k* j* l* m* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "no scores without a way to score, and no meter to order by: the level decides")
    eq(summary.useless, 0, "what cannot be scored is not called useless")

    -- A new rank the tables do not know yet: the kind goes by level, as before there were scores.
    list.o = Make("o", 2, "Increases Agility by 35 for 1 hr.", 29, 900, 1)
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 3/5] l*=12 o* m* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "the unknown stronger elixir stands for its kind, without a score")
    list.o = nil

    -- Food that restores health and adds a stat without a weight is still food.
    list.p = Make("p", 5, "Restores 874 health over 27 sec. Also increases your Intellect by 5.", 25, 100, 5)
    list.p.stats, list.p.restores = { Intellect = 5 }, "H"
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 3/4] j*=15 l*=12 m* [Food & Drink 2/3] e* p* [Bandages 1/2] g* [Other 1/1] h*",
        "it is listed for what it restores")
    -- And all such food is one kind, whatever the bonuses: the one for the higher level stands for it.
    list.q = Make("q", 5, "Restores 1392 health over 30 sec. Also increases your Spirit by 8.", 35, 150, 5)
    list.q.stats, list.q.restores = { Spirit = 8 }, "H"
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 3/4] j*=15 l*=12 m* [Food & Drink 2/4] q* e* [Bandages 1/2] g* [Other 1/1] h*",
        "one row for food with a bonus of no use, not one for every bonus")
    -- With a weight for one of the bonuses, that food is scored and stands apart.
    weights = { Agility = 1, Strength = 1.5, Spirit = 0.5 }
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 3/4] j*=15 l*=12 m* [Food & Drink 3/4] e* p* q*=4 [Bandages 1/2] g* [Other 1/1] h*",
        "food with a bonus of use has its score")
    weights = { Agility = 1, Strength = 1.5 }
    list.p, list.q = nil, nil

    rows, summary = P.Build({}, { money = 0, affordableOnly = true, bestOnly = true })
    eq(#rows, 0, "an empty list from nothing"); eq(summary.items, 0, "and nothing counted")

    -- The score itself is the sum gear is scored by (see the scenario "profiles").
    eq(ns.Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_AGILITY_SHORT = 4 }, "S1"), 16, "the sum for a set of stats")
    eq(ns.Score.StatsValue({ ITEM_MOD_INTELLECT_SHORT = 6 }, "S1"), 0, "nothing for a stat the profile has no weight for")
    eq(ns.Score.StatsValue({ ITEM_MOD_HEALTH_SHORT = 400 }, "S1"), 20, "health by the profile's weight for it")
    -- A chance with spells alone goes under a name of its own, which a profile for one who
    -- casts weighs and a warrior's does not.
    ns.Weights.profiles.Caster = { class = "MAGE", weights = { ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1,
        ITEM_MOD_CRIT_RATING_SHORT = 0.5, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 0.5 } }
    local wizardOil = { ITEM_MOD_SPELL_HEALING_DONE_SHORT = 36, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 36 }
    eq(ns.Score.StatsValue(wizardOil, "Caster"), 43, "a chance to crit with spells counts for one who casts")
    eq(ns.Score.StatsValue(wizardOil, "S1"), 0, "and for nothing for a warrior, whose crit is with a sword")
    eq(wizardOil.ITEM_MOD_CRIT_SPELL_RATING_SHORT, 14, "the stats that were passed in are left as they are")
    ns.Weights.profiles.Caster = nil

    -- The table that comes with the addon, made from the game's own: a few items everyone knows.
    local data = ns.SupplyData
    check(type(data.build) == "string" and data.build ~= "", "the table says which build of the game it was made from")
    local mongoose = data.stats[13452] or {}
    eq(mongoose.ITEM_MOD_AGILITY_SHORT, 25, "Elixir of the Mongoose: Agility")
    eq(mongoose.ITEM_MOD_CRIT_RATING_SHORT, 28, "and a chance to crit of 2%, as the rating that gives it")
    eq(mongoose.ITEM_MOD_CRIT_SPELL_RATING_SHORT, nil, "with spells as with weapons: under the one name gear has for it")
    local oil = data.stats[20749] or {}
    eq(oil.ITEM_MOD_CRIT_SPELL_RATING_SHORT, 14, "Brilliant Wizard Oil: a chance to crit with spells alone, under its own name")
    eq(oil.ITEM_MOD_CRIT_RATING_SHORT, nil, "and not under the one for both")
    eq(data.stats[18262] and data.stats[18262].ITEM_MOD_CRIT_MELEE_RATING_SHORT, 28, "Elemental Sharpening Stone: with weapons alone")
    eq(data.stats[13512] and data.stats[13512].ITEM_MOD_SPELL_DAMAGE_DONE_SHORT, 150, "Flask of Supreme Power")
    eq(data.stats[20007] and data.stats[20007].ITEM_MOD_MANA_REGENERATION_SHORT, 12, "Mageblood Elixir: mana every five seconds, not a drink")
    eq(data.stats[4592] and data.stats[4592].ITEM_MOD_ATTACK_POWER_SHORT, 10, "attack power with melee and ranged weapons: one number, as on gear")
    eq(data.stats[12820] and data.stats[12820].ITEM_MOD_MELEE_ATTACK_POWER_SHORT, 35, "Winterfall Firewater: with melee weapons alone")
    eq(data.restores[118], "H", "Minor Healing Potion restores health"); eq(data.restores[2455], "M", "Minor Mana Potion restores mana")
    eq(data.restores[159], "M", "water is a drink"); eq(data.stats[159], nil, "and adds nothing")
    eq(data.stats[724] and data.stats[724].ITEM_MOD_STRENGTH_SHORT, 3, "Goretusk Liver Pie: what being well fed adds"); eq(data.restores[724], "H", "and it is food")
    -- Every name in it is one the game has for a stat of gear, which is what a profile's weights go by.
    local count, strange = 0, nil
    for _, stats in pairs(data.stats) do
        count = count + 1
        for name, amount in pairs(stats) do
            local known = type(name) == "string" and (name:find("^ITEM_MOD_[%u_]+_SHORT$") or name:find("^RESISTANCE%d_NAME$"))
            if not known or type(amount) ~= "number" or amount <= 0 then strange = name end
        end
    end
    check(count > 100, "the table knows its elixirs, scrolls and food: " .. count)
    eq(strange, nil, "under the game's names for stats, with amounts above zero")
end

function scenarios.supplies_scan()
    SuppliesWorld()
    -- One the client has to load first, and one whose "Use:" line never arrives.
    W.AddItem({ id = 540, name = "Late Elixir", classID = 0, subClassID = 2, level = 10, stack = 20, quality = 1,
        use = "Increases Agility by 8 for 1 hr.", uncached = true })
    W.AddItem({ id = 541, name = "Silent Elixir", classID = 0, subClassID = 2, level = 10, stack = 20, quality = 1,
        use = "Increases Strength by 8 for 1 hr.", useLate = true })
    W.AddAuction(540, 700, { quantity = 4 })
    W.AddAuction(541, 650, { quantity = 2 })
    LoadAddon()
    SupplyFacts()
    local S = ns.Scanner

    eq(S.StartSupplies(), false, "no scan while the auction house is closed")
    eq(S.suppliesNote, ns.L.ERR_AH_CLOSED, "and the list says why")
    eq(S.message, nil, "the gear list has no note of it")

    W.OpenAuctionHouse()
    check(S.StartSupplies(), "scan starts")
    eq(S.mode, "supplies", "it is a scan for consumables")
    eq(S.suppliesNote, nil, "the note is gone")
    eq(S.Start(), false, "one scan at a time")
    W.RunUntil(function() return S.state == "idle" end, 120)

    local filters = W.AH.lastQuery.itemClassFilters
    eq(#filters, 1, "one category asked for"); eq(filters[1].classID, 0, "Consumables")
    eq(W.AH.calls.search, 0, "no item searches: the rows hold the price of a piece")
    check(S.suppliesAt ~= nil, "finish time recorded"); eq(S.suppliesPartial, false, "the scan saw everything")
    eq(S.finishedAt, nil, "the gear scan has a finish time of its own")
    eq(next(S.offers), nil, "and its list is untouched")

    local potion = Supply("Greater Healing Potion")
    check(potion ~= nil, "a potion the character can drink is listed")
    eq(potion.price, 800, "at the lowest price in its row"); eq(potion.quantity, 18, "with all the pieces for sale")
    eq(potion.sub, 1, "its subcategory"); eq(potion.stack, 5, "its stack size"); eq(potion.reqLevel, 21, "its level")
    eq(potion.effect, "Restores 455 to 585 health.", "what it does, without \"Use:\"")
    eq(potion.kind, "Restores # to # health.", "its kind"); eq(potion.power, 585, "and its strength")
    eq(Supply("Minor Healing Potion").kind, potion.kind, "a weaker potion is of the same kind")
    check(Supply("Mana Potion").kind ~= potion.kind, "a mana potion is not")

    eq(Supply("Superior Healing Potion"), nil, "above the character's level: left out")
    eq(Supply("Runecloth Bandage"), nil, "red in its tooltip: left out")
    eq(Supply("Strange Dust"), nil, "nothing to use: left out")
    check(Supply("Rough Dynamite") ~= nil, "a subcategory the game has no name for is listed all the same")
    check(Supply("Late Elixir") ~= nil, "an item the client had to load is listed")
    local silent = Supply("Silent Elixir")
    check(silent ~= nil, "an item whose effect line never came is listed too")
    eq(silent.effect, nil, "without an effect"); eq(silent.kind, "item:541", "as a kind of its own")
    local count = 0
    for _ in pairs(S.supplies) do count = count + 1 end
    eq(count, 17, "everything else is there")

    -- What the game's tables say of an item goes with it.
    eq(potion.restores, "H", "what the potion restores"); eq(potion.stats, nil, "it adds no stats")
    eq(Supply("Elixir of Agility").stats.ITEM_MOD_AGILITY_SHORT, 15, "what an elixir adds")
    eq(Supply("Rough Dynamite").stats, nil, "nothing where the tables say nothing"); eq(Supply("Rough Dynamite").restores, nil, "of either kind")

    -- The rows the tab would show a character without mana, on the profile "S1".
    local rows, summary = ns.Supplies.Build(S.supplies, SupplyOpts("S1", { affordableOnly = true, bestOnly = true, mana = false }))
    eq(rows[1].title, "Potions", "potions first"); eq(rows[2].entry.supply.name, "Greater Healing Potion", "the best healing potion")
    eq(rows[3].title, "Elixirs", "the mana potion is of no use, so elixirs come next")
    eq(rows[4].entry.supply.name, "Elixir of Agility", "the elixir that scores highest"); eq(rows[4].entry.value, 15, "with its score")
    eq(rows[5].entry.supply.name, "Elixir of Ogre Strength", "then the next kind"); eq(rows[5].entry.value, 12, "by its score")
    eq(rows[6].entry.supply.name, "Silent Elixir", "an item without its effect line is scored all the same")
    eq(rows[7].title, "Food & Drink", "nothing for the Intellect elixir on this profile")
    eq(summary.useless, 2, "it and the mana potion are of no use"); eq(summary.hidden, 1, "and the best Strength elixir costs too much")

    -- A scan that is stopped keeps what it read, and the note is the consumables list's own.
    check(S.StartSupplies(), "second scan starts")
    eq(next(S.supplies), nil, "a new scan starts from an empty list")
    W.RunUntil(function() return S.state == "score" end, 30)
    S.Stop(ns.L.ST_STOPPED)
    eq(S.state, "idle", "stopped"); eq(S.suppliesNote, ns.L.ST_STOPPED, "says it was stopped")
    eq(S.suppliesPartial, true, "and that the list may be incomplete"); eq(S.message, nil, "the gear list still has no note")

    -- The auction house does not answer.
    W.RunUntil(function() return W.AH.ready end, 5)
    W.AH.answerBrowse = false
    check(S.StartSupplies(), "third scan starts")
    W.RunUntil(function() return S.state == "idle" end, 120)
    eq(S.suppliesNote, ns.L.ERR_BROWSE, "says the auction house did not answer")
end

function scenarios.supplies_buy()
    SuppliesWorld()
    -- A consumable that does not stack is sold as separate auctions.
    W.AddItem({ id = 550, name = "Odd Flask", classID = 0, subClassID = 3, level = 20, stack = 1, quality = 1, use = "Does 1 thing." })
    W.AddAuction(550, 6000)
    local cheapFlask = W.AddAuction(550, 5000, { quantity = 3 })    -- one seller, three auctions at one price
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    ScanSupplies()

    local asked, quoted, done = {}, {}, 0
    ns.Listen("CONFIRM_SUPPLY", function(supply, tiers) asked[#asked + 1] = { supply = supply, tiers = tiers } end)
    ns.Listen("SUPPLY_QUOTED", function(total) quoted[#quoted + 1] = total end)
    ns.Listen("SUPPLY_DONE", function() done = done + 1 end)
    local function Lookup(supply)
        local before = #asked
        W.RunUntil(function() return S.Ready() end, 5)
        S.BuySupply(supply)
        W.RunUntil(function() return #asked > before or S.state == "idle" end, 30)
        W.RunUntil(function() return S.Ready() end, 5)
        return asked[before + 1]
    end
    local function Quote(supply, tiers, count)
        local before = #quoted
        S.QuoteSupply(supply, tiers, count)
        W.RunUntil(function() return #quoted > before end, 10)
        W.RunUntil(function() return S.Ready() end, 5)
        return quoted[#quoted]
    end

    -- Step one: who sells how many at what price.
    local potion = Supply("Greater Healing Potion")
    eq(potion.price, 800, "the row's lowest price is the character's own auction")
    S.BuySupply(potion)
    eq(S.mode, "supply", "a lookup for a consumable"); eq(S.state, "verify", "is under way")
    W.RunUntil(function() return #asked == 1 end, 30)
    eq(S.state, "idle", "the lookup is over when the question is asked")
    eq(asked[1].supply, potion, "the question is about the potion")
    local tiers = asked[1].tiers
    eq(#tiers, 2, "the character's own pieces are not in the price list")
    eq(tiers[1].price, 900, "cheapest first"); eq(tiers[1].quantity, 3, "three at that price")
    eq(tiers[2].price, 1000, "then the dearer ones"); eq(tiers[2].quantity, 10, "ten of them")
    eq(potion.price, 900, "the list now shows what can be bought"); eq(potion.quantity, 13, "and how many")
    eq(S.SupplyCost(tiers, 1), 900, "one piece"); eq(S.SupplyCost(tiers, 5), 3 * 900 + 2 * 1000, "five pieces, cheapest first")
    eq(S.SupplyCost(tiers, 13), 3 * 900 + 10 * 1000, "all of them"); eq(S.SupplyCost(tiers, 14), nil, "more than there are")

    -- Steps three and four: the server's price, then the purchase.
    W.RunUntil(function() return S.Ready() end, 5)
    eq(Quote(potion, tiers, 5), 4700, "the server prices five pieces")
    eq(W.AH.calls.quotes[1].quantity, 5, "it was asked about five")
    local money = W.player.money
    S.ConfirmSupply()
    S.ConfirmSupply()
    W.RunUntil(function() return done == 1 end, 10)
    eq(#W.AH.calls.bought, 1, "bought once, however often the button is pressed")
    eq(W.player.money, money - 4700, "for the price that was named")
    check(W.printed[#W.printed]:find("Bought 5 x", 1, true) ~= nil and W.printed[#W.printed]:find("47s", 1, true) ~= nil,
        "the chat says what was bought: " .. W.printed[#W.printed])
    eq(potion.price, 1000, "what is left costs more"); eq(potion.quantity, 8, "and there is less of it")

    -- The player closes the box after the server named a price.
    local second = Lookup(potion)
    eq(#second.tiers, 1, "one price left"); eq(second.tiers[1].quantity, 8, "eight pieces at it")
    Quote(potion, second.tiers, 2)
    S.CancelSupply()
    eq(W.AH.calls.cancelled, 1, "the server is told the purchase is off")
    S.ConfirmSupply()
    eq(#W.AH.calls.bought, 1, "and nothing is bought after that")

    -- Someone else was faster.
    local third = Lookup(potion)
    Quote(potion, third.tiers, 2)
    W.AH.failPurchase = true
    S.ConfirmSupply()
    W.RunUntil(function() return done == 2 end, 10)
    W.AH.failPurchase = nil
    check(W.printed[#W.printed]:find("did not go through", 1, true) ~= nil, "the chat says the purchase failed")
    eq(#W.AH.calls.bought, 1, "nothing bought")

    -- More than there is: the server refuses to name a price.
    local fourth = Lookup(potion)
    S.QuoteSupply(potion, fourth.tiers, 50)
    W.RunUntil(function() return done == 3 end, 10)
    check(W.printed[#W.printed]:find("did not go through", 1, true) ~= nil, "the chat says so")

    -- Buying all of it takes the potion off the list.
    local fifth = Lookup(potion)
    Quote(potion, fifth.tiers, 8)
    S.ConfirmSupply()
    W.RunUntil(function() return done == 4 end, 10)
    eq(Supply("Greater Healing Potion"), nil, "sold out: gone from the list")

    -- Sold out before the lookup: the chat says so and the list forgets it.
    local brie = Supply("Stormwind Brie")
    for i = #W.AH.auctions, 1, -1 do
        if W.AH.auctions[i].id == 511 then table.remove(W.AH.auctions, i) end
    end
    eq(Lookup(brie), nil, "nothing to ask about")
    check(W.printed[#W.printed]:find("no longer for sale", 1, true) ~= nil, "the chat says it is gone")
    eq(Supply("Stormwind Brie"), nil, "gone from the list")

    -- A consumable sold as separate auctions is bought one piece at a time. A buyout is the
    -- price of one piece, however many auctions the seller has at it.
    local flask = Supply("Odd Flask")
    check(flask ~= nil, "a consumable that does not stack is listed")
    eq(flask.price, 5000, "at the price of one"); eq(flask.quantity, 4, "four for sale in all")
    local sixth = Lookup(flask)
    eq(#sixth.tiers, 2, "two prices"); eq(sixth.tiers[1].auctionID, cheapFlask.auctionID, "the cheaper one first")
    eq(sixth.tiers[1].price, 5000, "a piece costs the buyout, not a third of it"); eq(sixth.tiers[1].quantity, 3, "three at that price")
    eq(S.SupplyCost(sixth.tiers, 4), 3 * 5000 + 6000, "the four of them")
    money = W.player.money
    S.BuySupplyAuction(flask, sixth.tiers)
    W.RunUntil(function() return done == 5 end, 10)
    eq(W.AH.calls.bids[#W.AH.calls.bids].auctionID, cheapFlask.auctionID, "that auction is bought out")
    eq(W.AH.calls.bids[#W.AH.calls.bids].amount, 5000, "for its buyout price")
    eq(W.player.money, money - 5000, "which is what was paid")
    check(W.printed[#W.printed]:find("Bought 1 x", 1, true) ~= nil, "the chat says one piece was bought: " .. W.printed[#W.printed])
    eq(flask.price, 5000, "the next one costs the same"); eq(flask.quantity, 3, "three left")

    -- In the box such a consumable is one piece for one press. A bid the auction house turns
    -- down (someone else was faster) closes the box and costs nothing.
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScoutSupplies")
    W.player.money = 20000
    W.Run(0.3)
    local box = UpgradeScoutFrame.BuyBox
    W.RunUntil(function() return S.Ready() end, 5)
    S.BuySupply(flask)
    W.RunUntil(function() return box:IsShown() end, 30)
    eq(box.Count:GetNumber(), 1, "one piece"); eq(box.Count:IsEnabled(), false, "and nothing to choose")
    eq(box.Total:GetAmount(), 5000, "for the price of one"); eq(box.Stock:GetText(), "of 3 for sale", "out of what is for sale")
    W.RunUntil(function() return box.Buy:IsEnabled() end, 5)
    W.AH.failBid = true
    money = W.player.money
    box.Buy:Click()
    eq(box.step, "wait", "the bid is out")
    W.RunUntil(function() return not box:IsShown() end, 10)
    W.AH.failBid = nil
    check(W.printed[#W.printed]:find("did not go through", 1, true) ~= nil, "the chat says the bid failed: " .. W.printed[#W.printed])
    eq(W.player.money, money, "nothing was paid"); eq(flask.quantity, 3, "and nothing left the list")
    W.RunUntil(function() return S.Ready() end, 5)
    S.BuySupply(flask)
    W.RunUntil(function() return box:IsShown() end, 30)
    W.RunUntil(function() return box.Buy:IsEnabled() end, 5)
    box.Buy:Click()
    W.RunUntil(function() return not box:IsShown() end, 10)
    eq(W.player.money, money - 5000, "the next press buys one"); eq(flask.quantity, 2, "two left")
    W.Run(0.3)

    -- The auction house closes in the middle of a lookup.
    local food = Supply("Wild Hog Shank")
    local questions = #asked
    W.RunUntil(function() return S.Ready() end, 5)
    S.BuySupply(food)
    W.CloseAuctionHouse()
    eq(S.state, "idle", "the lookup is dropped")
    W.Run(1)
    eq(#asked, questions, "and no question follows")
end

-- The Consumables tab: the frame of the Upgrades tab in its other view.
function scenarios.supplies_ui()
    SuppliesWorld()
    LoadAddon()
    SupplyFacts()
    W.OpenAuctionHouse()
    local frame = UpgradeScoutFrame
    local S = ns.Scanner
    local lib = LibStub("LibAHTab-1-0")
    check(lib:DoesIDExist("UpgradeScoutSupplies"), "a second tab is registered")
    eq(lib:GetButton("UpgradeScoutSupplies"):GetText(), "Consumables", "with its own text")
    local list, scan, box = frame.List, frame.ScanButton, frame.BuyBox
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    local function Rows()
        local out = {}
        for _, w in ipairs(scrollBox:GetFrames()) do
            if w._shown then out[#out + 1] = w end
        end
        return out
    end
    -- The rows as one line of text: headings in brackets, items by name.
    local function Listed()
        local out = {}
        for _, row in ipairs(Rows()) do
            if row._kind == "Frame" then
                out[#out + 1] = "[" .. row.Title:GetText() .. (row.Count:GetText() ~= "" and " " .. row.Count:GetText() or "") .. "]"
            else
                out[#out + 1] = row.Name:GetText()
            end
        end
        return table.concat(out, ", ")
    end
    local function Row(name)
        for _, row in ipairs(Rows()) do
            if row._kind == "Button" and row.Name:GetText() == name then return row end
        end
    end
    -- A text in view that holds these words.
    local function Said(words)
        for _, text in ipairs(W.texts) do
            local said = text:IsVisible() and text:GetText()
            if said and said:find(words, 1, true) then return said end
        end
    end
    local function Tick(tickBox, checked)
        tickBox:SetChecked(checked)
        tickBox:Click()
        W.Run(0.3)
    end

    -- The Upgrades tab has its own titles and controls.
    lib:SetSelected("UpgradeScout")
    -- How far along a part is anchored: a row's part from the row's left edge, a title from
    -- that of the plate, which the rows lie INSET inside.
    local INSET = 8
    local function At(part)
        eq(#part._points, 1, "one anchor")
        return part._points[1].x
    end
    eq(list.Titles[2]:GetText(), "PICK", "the Upgrades tab names its second column")
    eq(list.Titles[3]:IsShown(), true, "and has a column for the gain")
    eq(list.Titles[5]:IsShown(), false, "four columns: nothing after the buyout")
    local gearPrice = At(list.Titles[4])
    eq(frame.TopCheck:IsShown(), true, "its own second filter"); eq(frame.BestCheck:IsShown(), false, "not the other view's")
    eq(frame.ProfileDropdown:IsShown(), true, "and the profile")

    -- The Consumables tab shows the same frame, made over.
    lib:SetSelected("UpgradeScoutSupplies")
    eq(frame:IsShown(), true, "the same frame is up")
    eq(list.Titles[2]:GetText(), "EFFECT", "the second column is what the item does")
    eq(list.Titles[3]:IsShown(), true, "the third column stays"); eq(list.Titles[3]:GetText(), "SCORE", "for what the item is worth")
    eq(list.Titles[4]:GetText(), "EACH", "the price is that of one piece")
    eq(list.Titles[5]:IsShown(), true, "a fifth column here"); eq(list.Titles[5]:GetText(), "FOR SALE", "how many there are")
    check(At(list.Titles[4]) < gearPrice, "the price stands further left than gear's, to make room for it")
    eq(At(list.Titles[5]), gearPrice, "which ends where the price of gear does: close before the Buy button")
    eq(frame.ProfileDropdown:IsShown(), true, "the profile stays: consumables are scored on it")
    eq(frame.TopCheck:IsShown(), false, "the top-N filter is gone"); eq(frame.BestCheck:IsShown(), true, "another one is in its place")
    eq(frame.BestCheck.Text:GetText(), "Best for me", "with its label"); eq(frame.BestCheck:GetChecked(), true, "ticked by default")
    eq(frame.AffordCheck:IsShown(), true, "the price filter is shared")
    eq(list.Intro:IsShown(), true, "the emblem before the first scan")
    eq(list.Intro.Heading:GetText(), "CONSUMABLES FOR SALE", "under this view's title")
    check(list.Hint:GetText():find("consumables on the auction house", 1, true) ~= nil, "and what the view is for: " .. list.Hint:GetText())

    -- The scan button scans for consumables here.
    scan:Click()
    eq(S.mode, "supplies", "a scan for consumables")
    W.Run(0.2)
    eq(scan.Label:GetText(), "STOP", "which the button can stop")
    W.RunUntil(function() return S.state == "idle" end, 120)
    W.Run(0.3)
    eq(scan.Label:GetText(), "SCAN", "back to Scan")
    eq(Listed(), "[POTIONS 1 of 3], Greater Healing Potion, [ELIXIRS 2 of 3], Elixir of Agility, Elixir of Ogre Strength, "
        .. "[FOOD & DRINK 1 of 3], Stormwind Brie, [BANDAGES 1 of 2], Heavy Wool Bandage, [OTHER], Rough Dynamite",
        "the best of each kind that is of use and that the character can pay for, by subcategory")
    check(Said("6 consumables in 5 categories. 1 more cost more than you have.") ~= nil, "the status line counts them")
    check(Said("Sec ago") ~= nil, "and says how old the scan is")
    check(frame.Status:GetText():find("ago", 1, true) == nil, "at the right end, not in the status line: " .. frame.Status:GetText())
    check(frame.Age:GetText():find("Sec ago", 1, true) ~= nil, "but on its own: " .. frame.Age:GetText())
    eq(list.Intro:IsShown(), false, "the emblem is gone")

    local potion = Row("Greater Healing Potion")
    eq(potion.Effect:IsShown(), true, "a consumable's row says what it does"); eq(potion.Effect:GetText(), "Restores 455 to 585 health.", "in the game's words")
    eq(potion.Stock:IsShown(), true, "and how many are for sale"); eq(potion.Stock:GetText(), "18", "all of them")
    eq(potion.Price:GetAmount(), 800, "the price of one piece"); eq(potion.Price._font, PriceFontWhite, "in white: the character can pay")
    eq(potion.Pick:IsShown(), false, "no pick"); eq(potion.Upgrade:IsShown(), false, "no gain")
    eq(potion.Meter:IsShown(), false, "no meter")
    eq(potion.Buy:IsEnabled(), true, "it can be bought")
    eq(potion.Effect:GetWidth(), 216, "the words have the room of the score it does not have")
    -- Every title over its column.
    eq(At(list.Titles[2]) - INSET, At(potion.Effect), "the title of the effect begins where the words do")
    eq(At(list.Titles[3]) - INSET, At(potion.Upgrade), "the title of the score ends where a score does")
    eq(At(list.Titles[4]) - INSET, At(potion.Price), "that of the price where the prices do")
    eq(At(list.Titles[5]) - INSET, At(potion.Stock), "and that of the pieces where their numbers do")
    eq(At(potion.Effect) + 216, At(potion.Upgrade), "the words may run to where a score would end")

    -- An elixir is scored on the profile, in the points of gear, with a meter like a gain's.
    local agility, strength = Row("Elixir of Agility"), Row("Elixir of Ogre Strength")
    eq(agility.Upgrade:IsShown(), true, "a scored row shows its score"); eq(agility.Upgrade:GetText(), "+15", "the score of +15 Agility")
    eq(agility.Meter:IsShown(), true, "over a meter"); eq(agility.Meter:GetWidth(), 71, "full for the best under the heading")
    eq(agility.Effect:GetWidth(), 136, "the words make room for it")
    eq(strength.Upgrade:GetText(), "+12", "the next kind by its score"); check(math.abs(strength.Meter:GetWidth() - 71 * 12 / 15) < 0.01, "its meter to scale: " .. strength.Meter:GetWidth())
    eq(agility.Icon._grey, false, "in colour")

    -- The age of this view's scan goes on counting.
    W.Run(6)
    check(Said("Scanned " .. ns.Ago(time() - S.suppliesAt) .. " ago.") ~= nil, "the age keeps up with the clock")
    check(time() - S.suppliesAt >= 6, "six seconds on")

    -- Its tooltip is the item's own, with what is for sale under it.
    potion:GetScript("OnEnter")(potion)
    local seen = {}
    for _, line in ipairs(GameTooltip._lines) do seen[#seen + 1] = line.text end
    check(table.concat(seen, "\n"):find("18 for sale, from 8s each.", 1, true) ~= nil, "the tooltip says how much there is: " .. table.concat(seen, " | "))
    check(table.concat(seen, "\n"):find("Score of what it adds", 1, true) == nil, "and nothing of a score it does not have")
    potion:GetScript("OnLeave")(potion)
    local function Tooltip(row)
        row:GetScript("OnEnter")(row)
        local lines = {}
        for _, line in ipairs(GameTooltip._lines) do lines[#lines + 1] = line.text end
        row:GetScript("OnLeave")(row)
        return table.concat(lines, " | ")
    end
    check(Tooltip(agility):find("Score of what it adds: +15", 1, true) ~= nil, "an elixir's tooltip has its score: " .. Tooltip(agility))

    -- Every consumable instead of the best of each kind.
    Tick(frame.BestCheck, false)
    eq(ns.db.bestOnly, false, "the setting is saved")
    -- The list is now longer than the plate: it is read at its top and at its bottom.
    local top = Listed()
    scrollBox:SetScrollPercentage(1)
    local bottom = Listed()
    scrollBox:SetScrollPercentage(0)
    local first = "[POTIONS], Greater Healing Potion, Healing Potion, Minor Healing Potion, "
        .. "[ELIXIRS], Elixir of Agility, Elixir of Lesser Agility, Elixir of Ogre Strength, Elixir of Wisdom, "
        .. "[FOOD & DRINK], Stormwind Brie, Wild Hog Shank, Mutton Chop"
    local ending = "[BANDAGES], Heavy Wool Bandage, Wool Bandage, [OTHER], Rough Dynamite"
    eq(top:sub(1, #first), first, "each kind from its best down; of two equally strong the cheaper first; what is of no use last")
    eq(bottom:sub(-#ending), ending, "and so to the end of the list")
    local wisdom = Row("Elixir of Wisdom")
    eq(wisdom.Icon._grey, true, "what is of no use is grey"); eq(wisdom.Upgrade:IsShown(), false, "and has no score")
    check(Tooltip(wisdom):find("your profile gives no weight", 1, true) ~= nil, "its tooltip says why: " .. Tooltip(wisdom))
    eq(Row("Elixir of Lesser Agility").Upgrade:GetText(), "+8", "a weaker one of a kind has its own score")

    -- What costs too much comes back in red when the price filter is off.
    Tick(frame.AffordCheck, false)
    local mana = Row("Mana Potion")
    check(mana ~= nil, "the mana potion is listed")
    eq(mana.Price._font, PriceFontRed, "its price in red"); eq(mana.Buy:IsEnabled(), false, "and it cannot be bought")
    check(Tooltip(mana):find("you have none", 1, true) ~= nil, "a character without mana is told so: " .. Tooltip(mana))
    eq(Row("Elixir of Giants").Upgrade:GetText(), "+37.5", "the elixir that costs too much has the best score")
    check(math.abs(Row("Elixir of Agility").Meter:GetWidth() - 71 * 15 / 37.5) < 0.01, "and the meters now measure against it")
    Tick(frame.AffordCheck, true)
    Tick(frame.BestCheck, true)

    -- A heading folds its subcategory away, as a slot's heading does.
    local heading = Rows()[1]
    heading.Toggle:Click()
    eq(ns.db.collapsed.SUB1, true, "potions folded")
    eq(Listed(), "[POTIONS 1 of 3], [ELIXIRS 2 of 3], Elixir of Agility, Elixir of Ogre Strength, "
        .. "[FOOD & DRINK 1 of 3], Stormwind Brie, [BANDAGES 1 of 2], Heavy Wool Bandage, [OTHER], Rough Dynamite", "its rows are gone")
    Rows()[1].Toggle:Click()
    eq(ns.db.collapsed.SUB1, nil, "and unfolded again")

    -- Another profile: the list is scored again as it stands. No scan, of either kind.
    local scannedAt = S.suppliesAt
    frame.ProfileDropdown:Pick(2)
    W.Run(0.3)
    eq(ns.Roster.Me().profile, "S2", "the choice is saved"); eq(S.state, "idle", "nothing is scanned"); eq(S.suppliesAt, scannedAt, "the list is the same scan's")
    eq(Listed(), "[POTIONS 1 of 3], Greater Healing Potion, [ELIXIRS], Elixir of Wisdom, "
        .. "[FOOD & DRINK 1 of 3], Stormwind Brie, [BANDAGES 1 of 2], Heavy Wool Bandage, [OTHER], Rough Dynamite",
        "on a profile for Intellect its elixir is the one of use")
    eq(Row("Elixir of Wisdom").Upgrade:GetText(), "+6", "with its score on that profile")
    check(Said("5 consumables in 5 categories.") ~= nil, "nothing of use costs too much now: " .. tostring(Said("consumables in")))
    -- A character with mana has a use for the mana potion, which costs too much.
    W.player.mana = 400
    Tick(frame.BestCheck, true)
    check(Said("5 consumables in 5 categories. 1 more cost more than you have.") ~= nil, "the mana potion is counted: " .. tostring(Said("consumables in")))
    W.player.mana = nil
    frame.ProfileDropdown:Pick(1)
    W.Run(0.3)
    eq(ns.Roster.Me().profile, "S1", "back on the first profile"); check(Row("Elixir of Agility") ~= nil, "and to its elixirs")

    -- Buy: first the price list is read, then the box asks how many. (With "Net cost" ticked
    -- on the other tab: a consumable is used up, and its box has no line for a net cost.)
    ns.db.net = true
    eq(box:IsShown(), false, "no box before a purchase")
    potion = Row("Greater Healing Potion")
    potion.Buy:Click()
    eq(S.mode, "supply", "the price list is being read")
    W.RunUntil(function() return box:IsShown() end, 30)
    W.RunUntil(function() return S.Ready() end, 5)
    W.Run(0.3)
    eq(box.Name:GetText(), "Greater Healing Potion", "the box names the item")
    eq(box.Stock:GetText(), "of 13 for sale", "and how many can be bought: the character's own are not counted")
    eq(box.Count:GetNumber(), 5, "it starts at one stack")
    eq(box.TotalLabel:GetText(), "TOTAL", "with the price of that many")
    eq(box.Total:GetAmount(), 3 * 900 + 2 * 1000, "the cheapest pieces first")
    eq(box.NetLabel:IsShown(), false, "no net cost for what is used up"); eq(box:GetHeight(), 162, "the box at its usual height")
    eq(box.Buy.Label:GetText(), "BUY", "the button buys"); eq(box.Buy:IsEnabled(), true, "and is ready")
    potion = Row("Greater Healing Potion")
    eq(potion.Price:GetAmount(), 900, "the list now shows the price that can be had"); eq(potion.Stock:GetText(), "13", "and the pieces that can be bought")

    W.Type(box.Count, "2")
    eq(box.Total:GetAmount(), 1800, "two pieces")
    W.Type(box.Count, "14")
    eq(box.Total:IsShown(), false, "no price for more than there are"); eq(box.Buy:IsEnabled(), false, "and nothing to buy")
    W.Type(box.Count, "")
    eq(box.Buy:IsEnabled(), false, "nor for nothing")
    W.player.money = 1000
    W.Type(box.Count, "2")
    eq(box.Total._font, PriceFontRed, "a price out of reach is red"); eq(box.Buy:IsEnabled(), false, "and cannot be paid")
    W.player.money = 20000
    W.Type(box.Count, "2")
    eq(box.Total._font, PriceFontWhite, "white again with the money back"); eq(box.Buy:IsEnabled(), true, "and the button too")

    -- "Buy" asks the server for its price; the same button then confirms it.
    box.Buy:Click()
    eq(box.step, "quote", "the server is asked"); eq(box.Buy:IsEnabled(), false, "the button waits"); eq(box.Count:IsEnabled(), false, "and the number is settled")
    eq(#W.AH.calls.bought, 0, "nothing is bought yet")
    W.RunUntil(function() return box.step == "confirm" end, 10)
    eq(box.TotalLabel:GetText(), "FINAL PRICE", "the server's price"); eq(box.Total:GetAmount(), 1800, "for two pieces")
    eq(box.Buy.Label:GetText(), "CONFIRM", "the button now confirms")
    W.RunUntil(function() return box.Buy:IsEnabled() end, 5)
    box.Buy:Click()
    eq(box.Buy:IsEnabled(), false, "pressed once")
    W.RunUntil(function() return not box:IsShown() end, 10)
    eq(#W.AH.calls.bought, 1, "bought"); eq(W.AH.calls.bought[1].quantity, 2, "two pieces"); eq(W.player.money, 20000 - 1800, "paid for")
    W.Run(0.3)
    potion = Row("Greater Healing Potion")
    eq(potion.Stock:GetText(), "11", "the list has two fewer"); eq(potion.Price:GetAmount(), 900, "at the same lowest price")

    -- Cancel before anything was asked of the server: nothing to call off.
    potion.Buy:Click()
    W.RunUntil(function() return box:IsShown() end, 30)
    box.Cancel:Click()
    eq(box:IsShown(), false, "the box closes"); eq(W.AH.calls.cancelled, 0, "the server was never asked")

    -- Enter in the number field presses Buy; cancelling then calls the purchase off.
    W.RunUntil(function() return S.Ready() end, 5)
    W.Run(0.3)       -- the list redraws a moment after the scanner is free again
    Row("Greater Healing Potion").Buy:Click()
    W.RunUntil(function() return box:IsShown() end, 30)
    W.RunUntil(function() return box.Buy:IsEnabled() end, 5)
    W.Type(box.Count, "1")
    W.PressEnter(box.Count)
    eq(box.step, "quote", "Enter asks the server")
    W.RunUntil(function() return box.step == "confirm" end, 10)
    box.Cancel:Click()
    eq(W.AH.calls.cancelled, 1, "the server is told the purchase is off"); eq(#W.AH.calls.bought, 1, "nothing more was bought")

    -- Leaving the view takes the box down; the Upgrades tab is itself again.
    W.RunUntil(function() return S.Ready() end, 5)
    W.Run(0.3)       -- the list redraws a moment after the scanner is free again
    Row("Greater Healing Potion").Buy:Click()
    W.RunUntil(function() return box:IsShown() end, 30)
    lib:SetSelected("UpgradeScout")
    eq(box:IsShown(), false, "the box does not follow to the other tab")
    eq(list.Titles[2]:GetText(), "PICK", "the Upgrades tab has its titles back"); eq(list.Titles[5]:IsShown(), false, "all four of them")
    eq(At(list.Titles[4]), gearPrice, "each where it was")
    eq(frame.ProfileDropdown:IsShown(), true, "its profile"); eq(frame.TopCheck:IsShown(), true, "and its filter")
    eq(Listed(), "", "and its own, empty list")
    eq(list.Intro:IsShown(), true, "with the emblem: gear was never scanned"); eq(list.Intro.Heading:GetText(), "GEAR UPGRADES FOR SALE", "under its own title")
    eq(ns.Scanner.state, "idle", "nothing was started behind the view")

    -- And back: the consumables are still there.
    lib:SetSelected("UpgradeScoutSupplies")
    W.Run(0.3)
    check(Row("Greater Healing Potion") ~= nil, "the Consumables tab still has its list")
end

---------------------------------------------------------------------------
-- Lists for another character of the account
---------------------------------------------------------------------------
-- Tooltip lines as C_TooltipInfo gives them: the item's name, then these texts.
local function Lines(...)
    local lines = { { leftText = "Some Item" } }
    for i = 1, select("#", ...) do lines[#lines + 1] = { leftText = (select(i, ...)) } end
    return lines
end

-- The card of the character being played, and what a card says an item's owner must be.
function scenarios.roster()
    StandardWorld()
    W.player.last = "Mainsson"              -- Forever gives a character a surname
    -- Learned: cloth, leather, mail, shields; one-handed swords and axes.
    W.player.spells = { [9078] = true, [9077] = true, [8737] = true, [9116] = true, [201] = true, [196] = true }
    W.player.professions = { { "Mining", 75 }, { "Engineering", 150 }, { "Cooking", 40 } }
    LoadAddon()
    local R = ns.Roster

    local me = R.Me()
    eq(me.key, "Tester Mainsson", "the card is filed under the character's name and surname")
    eq(me.name, "Tester", "shown by the first name"); eq(me.class, "WARRIOR", "its class"); eq(me.level, 10, "its level")
    eq(UpgradeScoutDB.chars["Tester Mainsson"], me, "kept for the whole account")
    eq(ns.Score.Current().name, "S1", "the character is scored on the profile its class starts with")
    eq(me.gear, nil, "nothing is written down before the character is in the world")

    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(me.gear[5], W.Link(100), "what it wears"); eq(me.gear[16], W.Link(102), "in every slot"); eq(me.gear[1], nil, "an empty slot is empty")
    eq(me.weapons[7], true, "one-handed swords are learned"); eq(me.weapons[10], nil, "staves are not")
    eq(me.armor[3], true, "mail is learned"); eq(me.armor[4], nil, "plate is not")
    eq(me.skills.Engineering, 150, "how far a profession has got"); eq(me.skills.Mining, 75, "each of them")
    eq(me.skills.Cooking, 40, "cooking too, which the game lists after places this character has nothing in")
    eq(me.mana, false, "a warrior has no mana"); eq(me.dualWield, false, "and this one holds one weapon")
    eq(me.race, "Human", "its race, as the game names it"); eq(me.realm, "Testrealm", "its realm")
    check(type(me.seen) == "number", "and when it was written down")
    eq(#R.List(), 1, "one character so far"); eq(R.Target(), nil, "and the lists are for it")

    -- Nothing worn right after a login is the game not having the links yet; nothing worn
    -- after the gear changed is the truth.
    local worn = W.equipped
    W.equipped = {}
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(me.gear[5], W.Link(100), "an empty answer at login does not wipe the gear")
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1.5)
    eq(next(me.gear), nil, "taking everything off does")
    W.equipped = worn
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1.5)
    eq(me.gear[11], W.Link(101), "and it is written down again when put back on")
    -- A level gained is known from the event, even while UnitLevel is a moment behind.
    W.Fire("PLAYER_LEVEL_UP", 11)
    W.Run(1.5)
    eq(me.level, 11, "a level gained")
    -- In a fight the game keeps how much mana there is to itself: the card stays as it was.
    W.secrets = true
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1.5)
    W.secrets = nil
    eq(me.mana, false, "a number the game keeps secret is not gone by"); eq(me.gear[11], W.Link(101), "and the rest is written down as ever")
    -- A game that does not answer about spells leaves what was known.
    W.player.spells = nil
    W.Fire("SPELLS_CHANGED")
    W.Run(1.5)
    eq(me.weapons[7], true, "no answer about skills keeps the last one")
    -- So does an answer in part: a warrior wears leather and mail from the start, and an
    -- answer that has only cloth is not one to go by.
    W.player.spells = { [9078] = true, [750] = true, [202] = true }
    W.Fire("SPELLS_CHANGED")
    W.Run(1.5)
    eq(me.armor[3], true, "an answer about armor that lacks what the class starts with is not believed")
    eq(me.armor[4], nil, "none of it")
    eq(me.weapons[8], true, "weapons have no such check: the answer is taken"); eq(me.weapons[7], nil, "as it is")
    -- A whole answer, with plate learned at 40.
    W.player.spells = { [9078] = true, [9077] = true, [8737] = true, [9116] = true, [750] = true, [201] = true }
    W.Fire("SPELLS_CHANGED")
    W.Run(1.5)
    eq(me.armor[4], true, "a whole answer is: plate is learned now")

    -- What a class can ever learn decides for a card that has no record of what was learned.
    local mage = { key = "M", name = "Magey", class = "MAGE", level = 30 }
    eq(R.Wields(mage, 2, 7), true, "a mage can learn swords"); eq(R.Wields(mage, 2, 4), false, "never maces")
    eq(R.Wields(mage, 4, 1), true, "wears cloth"); eq(R.Wields(mage, 4, 3), false, "never mail")
    eq(R.Wields(mage, 4, 0), true, "a ring asks for no skill"); eq(R.Wields(mage, 2, 20), true, "nor does a fishing pole")
    mage.weapons = { [10] = true, [19] = true }
    eq(R.Wields(mage, 2, 7), false, "a record says this mage never went for swords"); eq(R.Wields(mage, 2, 19), true, "and has wands")
    local hunter = { class = "HUNTER", level = 39 }
    eq(R.Wields(hunter, 4, 3), false, "mail comes to a hunter at 40"); eq(R.Wields(hunter, 4, 2), true, "leather before that")
    hunter.level = 40
    eq(R.Wields(hunter, 4, 3), true, "at 40 it has come"); eq(R.Wields(hunter, 4, 4), false, "plate never does")
    local warrior = { class = "WARRIOR", level = 39 }
    eq(R.Wields(warrior, 4, 3), true, "a warrior has mail from the start"); eq(R.Wields(warrior, 4, 4), false, "and plate at 40")
    hunter.armor = { [1] = true, [2] = true }
    eq(R.Wields(hunter, 4, 3), false, "a hunter of 40 who never trained mail does not have it")
    eq(R.Wields({ class = "DRUID", level = 10 }, 4, 8), true, "an idol is a druid's"); eq(R.Wields(warrior, 4, 8), false, "and nobody else's")

    -- What an item's tooltip asks of its owner.
    local druid = { class = "DRUID", className = "Druid", race = "Night Elf", level = 20, skills = { Engineering = 150 } }
    eq(R.Allows(druid, Lines("Binds when equipped", "Requires Level 60")), true, "the level is not judged here")
    eq(R.Allows(druid, Lines("Classes: Druid, Shaman")), true, "an item for its class")
    eq(R.Allows(druid, Lines("Classes: Warrior, Shaman")), false, "an item for other classes")
    eq(R.Allows(druid, Lines("|cffff2020Classes: Druid|r")), true, "colour codes are not part of the text")
    eq(R.Allows(druid, Lines("Races: Night Elf, Tauren")), true, "an item for its race")
    eq(R.Allows(druid, Lines("Races: Orc, Troll")), false, "an item for other races")
    eq(R.Allows(druid, Lines("Requires Engineering (150)")), true, "a profession it has got far enough in")
    eq(R.Allows(druid, Lines("Requires Engineering (151)")), false, "not far enough")
    eq(R.Allows(druid, Lines("Requires Alchemy (1)")), false, "a profession it has not got")
    eq(R.Allows(druid, Lines("Requires Argent Dawn - Revered")), false, "standing with a faction is not on a card")
    -- The game says what kind of thing a line asks for, whatever its words.
    local function Asks(kind, text)
        local lines = Lines(text)
        lines[2].type, lines[2].requirementType = Enum.TooltipDataLineType.UsageRequirement, Enum.TooltipDataUsageRequirementType[kind]
        return lines
    end
    eq(R.Allows(druid, Asks("PvPRank", "Requires Sergeant")), false, "nor is a rank, told by the kind of its line")
    eq(R.Allows(druid, Asks("Reputation", "Honored with the Wardens")), false, "nor standing, in words no pattern knows")
    eq(R.Allows(druid, Asks("Level", "Requires Level 60")), true, "a line of a kind that is judged elsewhere bars nothing")
    eq(R.Allows(druid, Asks("Skill", "Requires Engineering (150)")), true, "and one a card can answer is read as before")
    eq(R.Allows(druid, Asks("Skill", "Requires Engineering (151)")), false, "to the same end")
    druid.skills = nil
    eq(R.Allows(druid, Lines("Requires Engineering (1)")), false, "professions unknown: not taken on trust")
    druid.className = "Druidess"
    eq(R.Allows(druid, Lines("Classes: Druidess")), true, "the class by the name the game gave the character")

    -- The profiles of a character that is not being played: those of its class.
    local alt = { key = "Alty-Testrealm", name = "Alty", class = "DRUID", level = 20 }
    local function Names(profiles)
        local out = {}
        for i = 1, #profiles do out[i] = profiles[i].name end
        return table.concat(out, " ")
    end
    eq(Names(ns.Score.Profiles(alt)), "D1 D2", "a card has the profiles of its class")
    eq(ns.Score.Current(alt).name, "D1", "the class's own until one is chosen")
    alt.profile = "D2"
    eq(ns.Score.Current(alt).name, "D2", "then the one chosen for it")
    alt.profile = "S1"
    eq(ns.Score.Current(alt).name, "D1", "a choice that is not among them does not count")
    eq(Names(ns.Score.Profiles({ key = "Nobody", class = "SHAMAN", level = 5 })), "", "a class without profiles has none")
    eq(Names(ns.Score.Profiles()), "S1 S2", "and for the character being played, those of its own class")
    eq(R.Colored(alt, "Alty"), "|cffff7c0aAlty|r", "a name in the colour of the class")

    -- What a class never wears.
    eq(ns.Score.ClassCanUse({ classID = 4, subClassID = 6 }, alt), false, "a druid never carries a shield")
    eq(ns.Score.ClassCanUse({ classID = 4, subClassID = 2 }, alt), true, "leather is fine")

    -- Time gone by: days for what was long ago.
    eq(ns.Ago(7200), "2 Hr", "hours"); eq(ns.Ago(3 * 86400), "3 Days", "and days")
end

-- Languages that number the places in a text ("%2$d ... %1$s") are read the right way round.
function scenarios.roster_order()
    ITEM_MIN_SKILL = "%2$d points of %1$s needed"
    LoadAddon()
    local card = { class = "DRUID", level = 20, skills = { Engineering = 150 } }
    eq(ns.Roster.Allows(card, Lines("150 points of Engineering needed")), true, "the profession and its rank, each from its place")
    eq(ns.Roster.Allows(card, Lines("151 points of Engineering needed")), false, "a rank it has not reached")
    eq(ns.Roster.Allows(card, Lines("1 points of Alchemy needed")), false, "a profession it has not got")
end

-- A druid of level 20: staves and daggers but no maces, cloth and leather, a leatherworker.
local function Druid()
    return {
        name = "Alty", level = 20, class = "DRUID", race = "Night Elf", money = 300, mana = 800, dualWield = false,
        spells = { [9078] = true, [9077] = true, [227] = true, [1180] = true },
        professions = { { "Leatherworking", 120 } },
    }
end

-- The whole road: the druid is played once, then the warrior stands at the auction house and
-- asks for the druid's lists.
function scenarios.alt()
    StandardWorld()
    local warriorGear = W.equipped
    local warrior = W.player

    -- What the druid wears. `values`: the score on the druid's two profiles.
    W.AddItem({ id = 300, name = "Alt's Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 12, D2 = 3 }, level = 15 })
    W.AddItem({ id = 301, name = "Alt's Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10, value = 0, values = { D1 = 15, D2 = 2 }, level = 15 })
    W.AddItem({ id = 302, name = "Alt's Charm", equipLoc = "INVTYPE_NECK", value = 0, values = { D1 = 1, D2 = 1 }, level = 5 })
    -- A trinket the game gives no stats for.
    W.AddItem({ id = 303, name = "Alt's Pebble", equipLoc = "INVTYPE_TRINKET", value = 0, level = 1, noStats = true })
    -- For sale, of no worth to a warrior.
    local function Sell(def, price)
        def.value = 0
        W.AddItem(def)
        W.AddAuction(def.id, price)
    end
    Sell({ id = 310, name = "Druid Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, values = { D1 = 20, D2 = 2 }, level = 18 }, 2000)
    Sell({ id = 311, name = "Bark Shield", equipLoc = "INVTYPE_SHIELD", subClassID = 6, values = { D1 = 50 }, level = 10 }, 100)
    Sell({ id = 312, name = "Elder Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10, values = { D1 = 40 }, level = 25 }, 100)
    Sell({ id = 313, name = "Carved Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10, values = { D1 = 22, D2 = 10 }, level = 19 }, 3000)
    Sell({ id = 314, name = "Stone Mace", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subClassID = 4, values = { D1 = 30 }, level = 10 }, 100)
    Sell({ id = 315, name = "Grove Ring", equipLoc = "INVTYPE_FINGER", values = { D1 = 6 }, level = 10, classes = "Druid" }, 500)
    Sell({ id = 316, name = "Totem Ring", equipLoc = "INVTYPE_FINGER", values = { D1 = 9 }, level = 10, classes = "Shaman" }, 100)
    Sell({ id = 317, name = "Tinker Goggles", equipLoc = "INVTYPE_HEAD", subClassID = 1, values = { D1 = 14 }, level = 10, skill = { "Engineering", 100 } }, 100)
    Sell({ id = 318, name = "Hide Belt", equipLoc = "INVTYPE_WAIST", subClassID = 2, values = { D1 = 7 }, level = 10, skill = { "Leatherworking", 100 } }, 400)
    Sell({ id = 319, name = "Dawn Cloak", equipLoc = "INVTYPE_CLOAK", subClassID = 1, values = { D1 = 8 }, level = 10, reputation = true }, 100)
    Sell({ id = 320, name = "Plain Buckler", equipLoc = "INVTYPE_SHIELD", subClassID = 6, values = { D1 = 45 }, level = 10 }, 100)
    Sell({ id = 321, name = "Sergeant's Cape", equipLoc = "INVTYPE_CLOAK", subClassID = 1, values = { D1 = 9 }, level = 10, rank = "Sergeant" }, 100)
    -- Consumables.
    local function Stock(def, price)
        def.classID, def.quality, def.value = 0, 1, 0
        W.AddItem(def)
        W.AddAuction(def.id, price, { quantity = 10 })
    end
    Stock({ id = 400, name = "Mana Draught", subClassID = 1, level = 15, stack = 5, use = "Restores 300 to 400 mana." }, 50)
    Stock({ id = 401, name = "Thick Bandage", subClassID = 7, level = 1, stack = 20, use = "Heals 301 damage over 7 sec.", skill = { "First Aid", 115 } }, 20)
    Stock({ id = 402, name = "Leather Salve", subClassID = 8, level = 1, stack = 20, use = "Softens a hide.", skill = { "Leatherworking", 100 } }, 30)
    Stock({ id = 403, name = "Elder Potion", subClassID = 1, level = 25, stack = 5, use = "Restores 700 to 900 health." }, 90)
    Stock({ id = 404, name = "Young Potion", subClassID = 1, level = 18, stack = 5, use = "Restores 280 to 360 health." }, 40)
    local function Facts()
        ns.SupplyData.stats = {}
        ns.SupplyData.restores = { [400] = "M", [403] = "H", [404] = "H" }
    end

    -- The druid is played.
    -- (Its gear after it has logged in: a link is written for the one who looks at the item.)
    W.Login(Druid())
    W.equipped = { [5] = W.Link(300), [13] = W.Link(303), [16] = W.Link(301) }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local card = UpgradeScoutDB.chars["Alty-Testrealm"]
    check(card ~= nil, "the druid is written down, under its name and realm")
    eq(card.class, "DRUID", "its class"); eq(card.level, 20, "its level"); eq(card.mana, true, "that it has mana")
    eq(card.gear[5], W.Link(300), "its chest"); eq(card.gear[16], W.Link(301), "its staff")
    eq(card.weapons[10], true, "staves learned"); eq(card.weapons[4], nil, "maces not")
    eq(card.skills.Leatherworking, 120, "its profession")
    eq(ns.Roster.Target(), nil, "its own lists are its own")
    -- It puts on a necklace and logs out at once: the logout is the last word.
    local charm = W.Link(302)
    W.equipped[2] = charm
    Relog(warrior, warriorGear)
    Facts()
    card = UpgradeScoutDB.chars["Alty-Testrealm"]
    eq(card.gear[2], charm, "what the druid wore when it logged out")
    eq(#ns.Roster.List(), 2, "the warrior knows of two characters"); eq(ns.Roster.List()[1].name, "Tester", "itself first")
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own until asked otherwise")
    -- A character of the other faction: nothing bought here can be mailed to it.
    UpgradeScoutDB.chars["Hordy-Testrealm"] = { key = "Hordy-Testrealm", name = "Hordy", realm = "Testrealm",
        faction = "Horde", class = "DRUID", level = 20 }
    eq(#ns.Roster.List(), 2, "a character of the Horde is not listed for one of the Alliance")
    UpgradeScoutDB.chars["Hordy-Testrealm"].faction = nil
    eq(#ns.Roster.List(), 3, "one whose card does not say its faction is")
    UpgradeScoutDB.chars["Hordy-Testrealm"] = nil

    -- The warrior at the auction house.
    W.OpenAuctionHouse()
    local frame = UpgradeScoutFrame
    local S = ns.Scanner
    local lib = LibStub("LibAHTab-1-0")
    lib:SetSelected("UpgradeScout")
    local dropdown, list = frame.ProfileDropdown, frame.List
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    -- The row of the item of this name, gear or consumable.
    local function Row(name)
        for _, w in ipairs(scrollBox:GetFrames()) do
            local entry = w._shown and w._kind == "Button" and w.entry or nil
            if entry and (entry.offer or entry.supply).name == name then return w end
        end
    end
    local function Said(words)
        for _, text in ipairs(W.texts) do
            local said = text:IsVisible() and text:GetText()
            if said and said:find(words, 1, true) then return said end
        end
    end
    local function Tooltip(tooltip)
        local seen = {}
        for _, line in ipairs(tooltip._lines or {}) do seen[#seen + 1] = line.text end
        return table.concat(seen, " | ")
    end
    local ALTY = "|cffff7c0aAlty|r"

    -- The scale field lists the druid's scales under the warrior's own.
    eq(#dropdown.radios, 4, "two scales of the warrior and two of the druid")
    eq(dropdown.radios[1].text, "Arms", "its own as before")
    eq(dropdown.radios[3].text, ALTY .. ": Balance", "the druid's by its name, in the colour of its class")
    eq(dropdown.radios[4].text, ALTY .. ": Feral", "each of them")
    eq(dropdown.dividers, 1, "a line between the characters"); eq(dropdown.dividersAfter[1], 2, "after the warrior's own")
    -- For another character the field shows a name and a profile, which takes its full width.
    -- The three tick boxes of the Upgrades tab leave no room for that and the field's caption
    -- both, so the field stands without its caption.
    eq(frame.ProfileLabel:IsShown(), false, "no caption before the field on the Upgrades tab")
    eq(dropdown:GetWidth(), 200, "which has its full width")
    local rule = W.Widget("Frame")
    rule.divider = rule:CreateTexture()
    for _, dress in ipairs(dropdown.rules[1].initializers) do dress(rule) end
    eq(Pictures(rule, "Line"), 1, "a gold rule of ours")
    eq(dropdown:GetText(), "Arms", "the field shows the warrior's scale")
    check(list.Hint:GetText():find("you can equip", 1, true) ~= nil, "and the list is to be the warrior's")

    -- Choosing the druid. Nothing was scanned, so nothing is scanned by itself. The client
    -- does not have the druid's chest at hand.
    W.items["300:0"].cached = false
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(3)
    eq(ns.Roster.Target(), card, "the lists are for the druid now")
    eq(dropdown:GetText(), ALTY .. ": Balance", "and the field says so")
    eq(S.state, "idle", "no scan by itself")
    check(list.Hint:GetText():find(ALTY .. " can equip", 1, true) ~= nil and list.Hint:GetText():find("\"Balance\"", 1, true) ~= nil,
        "the list says whose it will be: " .. list.Hint:GetText())
    dropdown._tooltip(GameTooltip)
    check(Tooltip(GameTooltip):find(ALTY .. ", level 20. Seen ", 1, true) ~= nil, "the field's tooltip says how old the druid's card is: " .. Tooltip(GameTooltip))

    frame.ScanButton:Click()
    eq(S.state, "browse", "the scan is the button's")
    check(S.ctx.pending ~= nil and S.ctx.pending[300], "the chest is on its way from the server")
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(1)
    eq(S.ctx.who, card, "the scan was for the druid"); eq(S.ctx.level, 20, "at its level"); eq(S.ctx.class, "DRUID", "and class")
    eq(S.ctx.pending, nil, "the chest came")
    -- The pebble has no stats: it is read, and scores nothing.
    eq(S.ctx.unread, nil, "an item without stats is read all the same"); near(S.ctx.equipped[13].value, 0, "and scores nothing")
    W.Run(5)
    local settled = S.ctx
    W.Run(5)
    eq(S.ctx, settled, "the gear is not read over and over for it")
    near(S.ctx.equipped[5].value, 12, "and is scored on the druid's profile")
    check(Offer("Druid Jerkin") ~= nil, "leather the druid can wear")
    check(Offer("Carved Staff") ~= nil, "a staff above the warrior's level and within the druid's")
    check(Offer("Grove Ring") ~= nil, "a ring for druids only")
    check(Offer("Hide Belt") ~= nil, "a belt for a leatherworker")
    eq(Offer("Elder Staff"), nil, "above the druid's level")
    eq(Offer("Stone Mace"), nil, "a kind of weapon the druid has not learned")
    eq(Offer("Bark Shield"), nil, "what a druid never carries")
    eq(Offer("Plain Buckler"), nil, "nor this one")
    eq(Offer("Totem Ring"), nil, "a ring for another class")
    eq(Offer("Tinker Goggles"), nil, "a profession the druid has not got")
    eq(Offer("Dawn Cloak"), nil, "standing with a faction is not known")
    eq(Offer("Sergeant's Cape"), nil, "nor is a rank")
    eq(Offer("Good Chest"), nil, "the warrior's upgrades are not the druid's")
    eq(OfferCount(), 4, "four upgrades for the druid")
    near(ns.Compare.Place(Offer("Druid Jerkin"), S.ctx)[1].delta, 8, "against the druid's chest")
    near(ns.Compare.Place(Offer("Carved Staff"), S.ctx)[1].delta, 7, "against the druid's staff")
    check(Said(ALTY .. ": 4 upgrades in 4 slots.") ~= nil, "the status line names the druid: " .. tostring(Said("upgrades in")))

    -- A row's tooltip: whose list, what is worn there, and the worn item beside it.
    local jerkin = Row("Druid Jerkin")
    check(jerkin ~= nil, "the jerkin is in the list")
    jerkin:GetScript("OnEnter")(jerkin)
    local doubles = {}
    for _, line in ipairs(GameTooltip._lines) do
        if line.right then doubles[#doubles + 1] = line end
    end
    eq(doubles[1].right, ALTY, "the header says whose list it is")
    eq(doubles[2].text, "Balance", "then the druid's profiles")
    eq(doubles[2].right, "+67%", "against what the druid wears: 20 against 12 on the profile in use")
    eq(doubles[2].r, RAID_CLASS_COLORS.DRUID.r, "in the colour of the druid's class")
    eq(doubles[3].r, RAID_CLASS_COLORS.DRUID.r, "every one of them")
    eq(doubles[3].text, "Feral", "and on the other one")
    eq(doubles[3].right, "-33%", "on its own weights: 2 against 3")
    eq(W.compared, nil, "the game's own comparison would show the warrior's chest")
    eq(ShoppingTooltip1:IsShown(), true, "the druid's chest is shown beside it instead")
    eq(ShoppingTooltip1._lines[1].text, "Alt's Jerkin", "in the game's second tooltip")
    jerkin:GetScript("OnLeave")(jerkin)
    eq(ShoppingTooltip1:IsShown(), false, "and goes with the tooltip")
    -- Where the parts that every row has stand on a row: how far from its left edge the gain
    -- (or the score) and the price end. The list hands its frames from one view to the
    -- other, and the two have their columns in different places.
    local function Columns(row)
        return row.Upgrade._points[1].x .. " " .. row.Trough._points[1].x .. " " .. row.Price._points[1].x
    end
    -- The frames that are rows of items now, by what they list: "offer" or "supply".
    local function ItemRows(what)
        local out = {}
        for _, w in ipairs(scrollBox:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry[what] then out[#out + 1] = w end
        end
        return out
    end
    -- One of `frames` that was a row of the other kind before: is in `before`.
    local function HandedOver(frames, before)
        for _, w in ipairs(frames) do
            for _, old in ipairs(before) do
                if w == old then return w end
            end
        end
    end
    local gearColumns, gearRows = Columns(jerkin), ItemRows("offer")

    -- Consumables for the druid: its level, its mana, its profession.
    lib:SetSelected("UpgradeScoutSupplies")
    check(list.Hint:GetText():find(ALTY .. " can use", 1, true) ~= nil, "the other view is the druid's too: " .. list.Hint:GetText())
    eq(frame.ProfileLabel:IsShown(), true, "two tick boxes leave room for the field's caption")
    eq(dropdown:GetWidth(), 200, "and for its full width")
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ScanButton:Click()
    W.RunUntil(function() return S.state == "idle" end, 120)
    W.Run(0.3)
    check(Supply("Mana Draught") ~= nil, "a potion above the warrior's level")
    check(Supply("Young Potion") ~= nil, "and another")
    check(Supply("Leather Salve") ~= nil, "what asks for the druid's profession")
    eq(Supply("Thick Bandage"), nil, "what asks for a profession it has not got")
    eq(Supply("Elder Potion"), nil, "what is above its level")
    check(Row("Mana Draught") ~= nil, "mana is of use to a druid: the potion is in the list")
    check(Said(ALTY .. ": 3 consumables in ") ~= nil, "and the status line names the druid: " .. tostring(Said("consumables in")))
    -- A frame that was a row of gear is a consumable's now, with its parts moved over.
    local supplyRows = ItemRows("supply")
    local handed = HandedOver(supplyRows, gearRows)
    check(handed ~= nil, "a frame that was a row of gear is the row of a consumable now")
    local supplyColumns = Columns(handed)
    check(supplyColumns ~= gearColumns, "with its score and price over this view's columns: " .. supplyColumns .. " (gear " .. gearColumns .. ")")
    for _, row in ipairs(supplyRows) do
        eq(Columns(row), supplyColumns, "as on every row of the view")
    end
    check(handed.Price._points[1].x < handed.Stock._points[1].x, "the price before the pieces for sale")

    -- Back to the warrior: both lists were the druid's and go; the view that had one scans.
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(1)
    eq(ns.Roster.Target(), nil, "the lists are the warrior's again")
    eq(dropdown:GetText(), "Arms", "the field shows its scale")
    eq(OfferCount(), 0, "the druid's upgrades are gone"); eq(S.finishedAt, nil, "with their scan")
    eq(S.state, "browse", "the Consumables view scans again"); eq(S.mode, "supplies", "for consumables")
    W.RunUntil(function() return S.state == "idle" end, 120)
    W.Run(0.3)
    eq(Supply("Mana Draught"), nil, "a level 10 warrior is too young for the potion")
    eq(Supply("Leather Salve"), nil, "and no leatherworker")
    lib:SetSelected("UpgradeScout")
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ScanButton:Click()
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(0.3)
    CheckStandardOffers("the warrior's own scan")
    -- The frames that listed the druid's consumables list gear again.
    gearRows = ItemRows("offer")
    check(HandedOver(gearRows, supplyRows) ~= nil, "a frame that was a consumable's is a row of gear now")
    for _, row in ipairs(gearRows) do
        eq(Columns(row), gearColumns, "with its gain and price over the columns of gear")
    end

    -- The druid's other profile: chosen from here, remembered with the druid, scanned at once.
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(4)
    eq(card.profile, "D2", "the druid's profile is kept on its card")
    eq(S.state, "browse", "the view had a list: it is made again")
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(0.3)
    check(Offer("Carved Staff") ~= nil, "on the other profile the staff is still better")
    eq(Offer("Druid Jerkin"), nil, "and the jerkin is not")
    eq(OfferCount(), 1, "one upgrade")
    -- And back to the first, for the same character: a change of profile.
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(3)
    eq(card.profile, "D1", "the choice follows"); eq(ns.Roster.Target(), card, "the druid stays")
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(0.3)
    eq(OfferCount(), 4, "four again")
    eq(ns.Roster.Me().profile, "S1", "the warrior's own profile is still the one it went back to")

    -- The druid logs in again: the profile chosen for it from afar is its profile.
    W.CloseAuctionHouse()
    Relog(Druid(), { [5] = W.Link(300), [16] = W.Link(301) })
    eq(ns.Roster.Me().key, "Alty-Testrealm", "the druid is played"); eq(ns.Roster.Target(), nil, "and the lists are its own")
    eq(ns.Score.Current().name, "D1", "on the profile chosen for it while the warrior was played")
    eq(#ns.Roster.List(), 2, "it knows of the warrior")
    -- A character that is gone is taken out of the list by name.
    SlashCmdList["UPGRADESCOUT"]("forget Nobody")
    check(W.printed[#W.printed]:find("Remembered: Tester", 1, true) ~= nil, "an unknown name gets the names there are: " .. W.printed[#W.printed])
    SlashCmdList["UPGRADESCOUT"]("forget Tester")
    check(W.printed[#W.printed]:find("Tester is forgotten", 1, true) ~= nil, "a known one is forgotten: " .. W.printed[#W.printed])
    eq(#ns.Roster.List(), 1, "and is out of the list"); eq(UpgradeScoutDB.chars["Tester-Testrealm"], nil, "and out of the saved file")
    SlashCmdList["UPGRADESCOUT"]("forget Alty")
    eq(#ns.Roster.List(), 1, "the character being played cannot be forgotten")
end

-- Gear bought for another character goes to it by mail: the purchase is written down, and at
-- a mailbox a button puts it into a letter.
function scenarios.mail()
    StandardWorld()
    local warriorGear = W.equipped
    local warrior = W.player
    W.AddItem({ id = 300, name = "Alt's Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 12 }, level = 15 })
    local function Sell(def, price)
        def.value = 0
        W.AddItem(def)
        W.AddAuction(def.id, price)
    end
    Sell({ id = 310, name = "Druid Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, values = { D1 = 20 }, level = 18 }, 2000)
    Sell({ id = 315, name = "Grove Ring", equipLoc = "INVTYPE_FINGER", values = { D1 = 6 }, level = 10 }, 500)

    -- The druid is played once, then the warrior.
    W.Login(Druid(), { [5] = W.Link(300) })
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    Relog(warrior, warriorGear)
    local S = ns.Scanner
    local ALTY = "|cffff7c0aAlty|r"
    local function Printed(words)
        return W.printed[#W.printed]:find(words, 1, true) ~= nil
    end

    -- Nothing bought: a mailbox is a mailbox.
    W.OpenMailbox()
    W.Run(0.5)
    eq(UpgradeScoutMailFrame, nil, "nothing is built while there is nothing to send")
    W.CloseMailbox()

    -- The warrior buys the helm for itself: that is no parcel.
    W.OpenAuctionHouse()
    local frame = UpgradeScoutFrame
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    SetView(false, false)
    ScanToEnd()
    local function Buy(name)
        W.RunUntil(function() return S.state == "idle" and W.AH.ready end, 30)
        S.Buy(Offer(name))
        W.RunUntil(Asking, 30)
        Asking().Buy:Click()
        W.RunUntil(function() return Offer(name) == nil and S.state == "idle" end, 30)
    end
    Buy("Helm")
    eq(#UpgradeScoutDB.parcels, 0, "what is bought for oneself is nobody's parcel")

    -- The lists are made for the druid, and its jerkin and ring are bought.
    frame.ProfileDropdown:Pick(3)
    eq(ns.Roster.Target().name, "Alty", "the lists are for the druid")
    -- (Choosing another character scans again by itself.)
    W.RunUntil(function() return S.state == "idle" and Offer("Druid Jerkin") ~= nil end, 600)
    Buy("Druid Jerkin")
    Buy("Grove Ring")
    local parcels = UpgradeScoutDB.parcels
    eq(#parcels, 2, "both purchases are written down for the account")
    eq(parcels[1].to, "Alty-Testrealm", "for the druid"); eq(parcels[1].from, "Tester-Testrealm", "held by the warrior")
    eq(parcels[1].link, W.Link(310), "the jerkin"); eq(parcels[2].link, W.Link(315), "and the ring")
    W.CloseAuctionHouse()

    -- At the mailbox, before the auction house's mail has been opened.
    W.OpenMailbox()
    W.Run(0.5)
    local panel = UpgradeScoutMailFrame
    check(panel ~= nil and panel:IsShown(), "a strip of the addon's under the mail window")
    local button = panel.Buttons[1]
    eq(button:IsShown(), true, "a button for the druid"); eq(panel.Buttons[2]:IsShown(), false, "and for nobody else")
    eq(Pictures(panel, "Panel"), 9, "on the plate of the addon's tabs")
    eq(button.Face.file, "ButtonDark", "its button in a gold rim, as the tab's are")
    eq(panel:GetHeight(), 36 + 22 + 10, "as tall as the one button it holds")
    eq(button.Label:GetText(), "For " .. ALTY .. ": 0 of 2 in your bags", "it says how much of it is at hand")
    button:Click()
    W.Run(0.5)
    check(Printed("Nothing bought for " .. ALTY .. " is in your bags."), "nothing to put in yet, and it says so")
    eq(W.mail.sendPage, false, "the mail window is left alone")

    -- The jerkin is taken out of the mail; the ring is still there. A jerkin the warrior
    -- wears is not for sending either.
    W.PutInBags(W.Link(200), { bound = true })
    W.TakeFromMail(W.Link(310))
    W.Run(0.5)
    eq(button.Label:GetText(), "For " .. ALTY .. ": 1 of 2 in your bags", "the button follows the bags")
    button:GetScript("OnEnter")(button)
    local seen = {}
    for _, line in ipairs(GameTooltip._lines) do seen[#seen + 1] = line.text end
    local tip = table.concat(seen, " | ")
    check(tip:find("Druid Jerkin", 1, true) ~= nil and tip:find("Grove Ring]|h|r (not in your bags", 1, true) ~= nil,
        "its tooltip lists the parcels and which of them is missing: " .. tip)
    button:Click()
    W.Run(1)
    eq(W.mail.sendPage, true, "the Send Mail page is brought up")
    eq(SendMailNameEditBox:GetText(), "Alty", "the letter is addressed to the druid")
    eq(SendMailSubjectEditBox:GetText(), "Upgrade Scout", "with a subject")
    eq(W.mail.attached[1].link, W.Link(310), "the jerkin is in it"); eq(W.mail.attached[2], nil, "and nothing else")
    check(Printed("Put 1 items into a letter to " .. ALTY .. ". Check it and press Send."), "the chat says what to do next")
    eq(#W.mail.sent, 0, "sending is left to the player")
    eq(#UpgradeScoutDB.parcels, 2, "nothing is struck off before the letter has gone")

    -- Something else about the mail goes wrong meanwhile (the game says so of any mail
    -- matter): the letter is still the letter. Then the player sends it.
    W.Fire("MAIL_FAILED")
    W.SendLetter()
    W.Run(1)
    eq(#W.mail.sent, 1, "one letter"); eq(W.mail.sent[1].to, "Alty", "to the druid"); eq(W.mail.sent[1].items[1], W.Link(310), "with the jerkin")
    eq(#UpgradeScoutDB.parcels, 1, "the jerkin is struck off"); eq(UpgradeScoutDB.parcels[1].link, W.Link(315), "the ring is still to go")
    eq(button.Label:GetText(), "For " .. ALTY .. ": 0 of 1 in your bags", "the button counts what is left")

    -- The ring comes out of the mail, is put into a letter and taken out of it again by hand:
    -- a letter sent without it leaves it a parcel.
    W.TakeFromMail(W.Link(315))
    local oldRing = W.PutInBags(W.Link(101))
    W.Run(0.5)
    button:Click()
    W.Run(1)
    eq(W.mail.attached[1].link, W.Link(315), "the ring is in the letter")
    W.Detach(1)
    C_Container.UseContainerItem(0, oldRing)    -- the player's own old ring instead
    W.SendLetter()
    W.Run(1)
    eq(#UpgradeScoutDB.parcels, 1, "the ring was not in the letter that went, so it is still a parcel")
    eq(button.Label:GetText(), "For " .. ALTY .. ": 1 of 1 in your bags", "and still at hand")

    -- A letter that already holds something for someone else is not touched.
    local sword = W.PutInBags(W.Link(102))
    MailFrameTab2:Click()
    SendMailNameEditBox:SetText("Somebody")
    C_Container.UseContainerItem(0, sword)
    button:Click()
    W.Run(1)
    check(Printed("The letter already holds items for Somebody. Send it first."), "it says why not")
    eq(W.mail.attached[2], nil, "nothing was added to the other letter")
    eq(SendMailNameEditBox:GetText(), "Somebody", "and its name stands")
    W.SendLetter()
    W.Run(1)

    -- The mailbox closed and opened again: the parcel is remembered. A right-click forgets it.
    W.CloseMailbox()
    eq(panel:IsShown(), false, "the strip goes with the mail window")
    W.OpenMailbox(true)
    W.Run(0.5)
    eq(panel:IsShown(), true, "and comes back with it, even when the window comes up after the game's word of a mailbox")
    button:GetScript("OnClick")(button, "RightButton")
    W.Run(0.5)
    eq(#UpgradeScoutDB.parcels, 0, "forgotten at a right-click")
    check(Printed("Forgot what was bought for " .. ALTY .. "."), "and said")
    eq(panel:IsShown(), false, "with nothing left to send, the strip goes")

    -- A parcel nobody sent for a month is dropped, and so is one for a character forgotten.
    UpgradeScoutDB.parcels = {
        { to = "Alty-Testrealm", from = "Tester-Testrealm", link = W.Link(310), itemID = 310, name = "Druid Jerkin", at = time() - 31 * 86400 },
        { to = "Nobody-Testrealm", from = "Tester-Testrealm", link = W.Link(310), itemID = 310, name = "Druid Jerkin", at = time() },
        { to = "Alty-Testrealm", from = "Tester-Testrealm", link = W.Link(315), itemID = 315, name = "Grove Ring", at = time() },
    }
    eq(#ns.Mail.Pending(), 1, "one character with parcels"); eq(#UpgradeScoutDB.parcels, 1, "of which one is left")
    eq(UpgradeScoutDB.parcels[1].link, W.Link(315), "the one that is neither old nor nobody's")
    -- A surname, as the characters of this game have: the letter is addressed with it.
    eq(ns.Mail.Address({ name = "Alty", last = "Greenleaf" }), "Alty Greenleaf", "a name and a surname")
    eq(ns.Mail.Address({ name = "Alty" }), "Alty", "a name alone")

    -- Sent by hand: the ring goes into a letter without the button, the name written in small
    -- letters. While it is in the letter it is still at hand, and the strip says where it is.
    ns.Mail.Refresh()
    eq(panel:IsShown(), true, "the ring's parcel is on the strip")
    local ringSlot
    for slot, held in pairs(W.bags[0]) do
        if held.link == W.Link(315) then ringSlot = slot end
    end
    MailFrameTab2:Click()
    C_Container.UseContainerItem(0, ringSlot)
    W.Fire("BAG_UPDATE", 0)
    W.Run(0.5)
    eq(button.Label:GetText(), "For " .. ALTY .. ": 1 of 1 in your bags", "the ring in the letter is still at hand")
    button:GetScript("OnEnter")(button)
    local inLetter = {}
    for _, line in ipairs(GameTooltip._lines) do inLetter[#inLetter + 1] = line.text end
    inLetter = table.concat(inLetter, " | ")
    check(inLetter:find("Grove Ring]|h|r (in the letter)", 1, true) ~= nil, "its tooltip says the ring is in the letter: " .. inLetter)
    check(inLetter:find("take it out of the mail", 1, true) == nil, "and not that it is in the mail")
    local said = #W.printed
    button:Click()
    W.Run(1)
    eq(#W.printed, said, "a click with everything in the letter already says nothing")
    eq(W.mail.attached[2], nil, "and puts nothing more in")
    SendMailNameEditBox:SetText("alty")
    W.mail.failSend = true
    W.SendLetter()
    W.Run(1)
    eq(#UpgradeScoutDB.parcels, 1, "a letter that did not go takes no parcel with it")
    W.SendLetter()
    W.Run(1)
    eq(W.mail.sent[#W.mail.sent].items[1], W.Link(315), "the letter went with the ring")
    eq(#UpgradeScoutDB.parcels, 0, "and the parcel with it, though the button had no part in it")
    eq(panel:IsShown(), false, "nothing left to send: the strip goes")

    -- Parcels from before: a jerkin that went in a letter the addon did not see, an hour ago; a
    -- ring still in the mail; a jerkin bought a moment ago, its letter maybe still on the way.
    -- At the next visit, once the game has listed all the mail, the first is struck off.
    W.CloseMailbox()
    W.mail.inbox = { { items = { W.Link(315) } } }
    local hourAgo = time() - 3600
    local function Parcel(id, name, at)
        return { to = "Alty-Testrealm", from = "Tester-Testrealm", link = W.Link(id), itemID = id, name = name, at = at }
    end
    UpgradeScoutDB.parcels = { Parcel(310, "Druid Jerkin", hourAgo), Parcel(315, "Grove Ring", hourAgo), Parcel(310, "Druid Jerkin", time()) }
    W.mail.inboxTotal = 60
    W.OpenMailbox()
    W.Run(1)
    eq(#UpgradeScoutDB.parcels, 3, "with more mail than the game lists, nothing is struck off")
    W.CloseMailbox()
    W.mail.inboxTotal = nil
    W.OpenMailbox()
    W.Run(1)
    eq(#UpgradeScoutDB.parcels, 2, "the old jerkin, which is nowhere, is struck off")
    eq(UpgradeScoutDB.parcels[1].link, W.Link(315), "the ring in the mail stays")
    eq(UpgradeScoutDB.parcels[2].link, W.Link(310), "and so does the jerkin just bought")
    check(UpgradeScoutDB.parcels[2].at > hourAgo, "(the new one)")
    eq(button.Label:GetText(), "For " .. ALTY .. ": 0 of 2 in your bags", "the strip shows what is left")
    -- One in the bank is still the character's to send.
    W.CloseMailbox()
    W.bank = { [310] = 1 }
    UpgradeScoutDB.parcels = { Parcel(310, "Druid Jerkin", hourAgo) }
    W.OpenMailbox()
    W.Run(1)
    eq(#UpgradeScoutDB.parcels, 1, "a jerkin in the bank keeps its parcel")

    -- The game's window comes up long after its word of a mailbox, and hides for a moment
    -- when another window takes its place: the strip follows it all the same.
    W.CloseMailbox()
    W.OpenMailbox(3)
    W.Run(1)
    eq(panel:IsShown(), false, "no strip before the window")
    W.Run(3)
    eq(panel:IsShown(), true, "the strip comes up with the window, however late")
    MailFrame:Hide()
    W.Run(0.5)
    eq(panel:IsShown(), false, "it goes when the window goes")
    MailFrame:Show()
    W.Run(0.5)
    eq(panel:IsShown(), true, "and comes back with it")
    W.bank = nil
end

-- Right after login the game knows what the character wears but not yet what it adds: the
-- gear is waited for, not taken for empty slots.
function scenarios.worn_loading()
    StandardWorld()
    W.items["100:0"].cached = false     -- the chest
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    check(S.Start(), "a scan")
    eq(S.ctx.pending and S.ctx.pending[100], true, "the chest that has not come yet is asked for")
    near(S.ctx.equipped[5].value, 0, "until then it scores nothing")
    W.RunUntil(function() return S.state == "idle" end, 600)
    W.Run(1)
    eq(S.ctx.pending, nil, "it came")
    near(S.ctx.equipped[5].value, 10, "and is scored as what is worn")
    near(ns.Compare.Place(Offer("Good Chest"), S.ctx)[1].delta, 8, "an offer is weighed against it, not against an empty slot")
end

-- Profiles and the score they give an item.
function scenarios.profiles()
    StandardWorld()
    LoadAddon()
    local Score = ns.Score

    local current, list = Score.Current()
    eq(#list, 2, "the profiles of the character's class"); eq(list[1].name, "S1", "in their order")
    eq(list[1].title, "Arms", "by name"); eq(list[2].title, "Protection ~", "an estimated one is marked")
    eq(Score.IsApprox("S2"), true, "and known as such"); eq(Score.IsApprox("S1"), false, "the others are not")
    eq(current.name, "S1", "a character starts on its class's own profile")
    ns.Weights.start.WARRIOR = "S2"
    eq(Score.Current().name, "S2", "which need not be the first of the list")
    ns.Roster.Me().profile = "S1"
    eq(Score.Current().name, "S1", "a choice is kept with the character")
    ns.Roster.Me().profile = "Gone"
    eq(Score.Current().name, "S2", "a choice that is no longer there gives way to the class's own")
    ns.Roster.Me().profile = nil
    ns.Weights.start.WARRIOR = "S1"
    ns.Weights.titles.ruRU = { S1 = "Оружие" }
    W.locale = "ruRU"
    eq(Score.Title("S1"), "Оружие", "a profile is named in the player's language")
    eq(Score.Title("S2"), "Protection ~", "or in English where that language has no name for it")
    W.locale = nil
    ns.Weights.profiles.R1 = { class = "PRIEST", role = "HEALER", approx = true, weights = {} }
    eq(Score.Title("R1"), "Healer ~", "a profile for more than one tree is named by its role")
    ns.Weights.profiles.D3 = { class = "DRUID", form = "BEAR", weights = {} }
    ns.Weights.titles.enUS.D3 = "Feral Combat"
    eq(Score.Title("D3"), "Feral Combat (Bear)", "a druid's shape after the tree it is played in")
    ns.Weights.profiles.R1, ns.Weights.profiles.D3, ns.Weights.titles.enUS.D3 = nil, nil, nil
    eq(#Score.Profiles({ class = "DRUID" }), 2, "another character has the profiles of its own class")
    eq(Score.Current({ class = "DRUID", profile = "D2" }).name, "D2", "and its own choice")
    eq(#Score.Profiles({ class = "ROGUE" }), 0, "a class without profiles has none")

    -- The score: each stat times its weight. A weapon's damage per second goes by the hand.
    local DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
    local sword = W.AddItem({ id = 900, name = "Test Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, level = 5,
        game = { ITEM_MOD_STRENGTH_SHORT = 4, [DPS] = 10, ITEM_MOD_UNHEARD_OF_SHORT = 99 } })
    local item = Score.Item(W.Link(900))
    eq(item.itemID, 900, "an item to score: its number"); eq(item.invType, "INVTYPE_WEAPON", "how it is worn")
    eq(item.classID, 2, "its kind"); eq(item.stats.ITEM_MOD_STRENGTH_SHORT, 4, "and its stats")
    near(Score.Value(item, "S1"), 4 * 1.5 + 10 * 2, "a one-hander: the main hand's weight for its damage")
    sword.equipLoc = "INVTYPE_WEAPONOFFHAND"
    near(Score.Value(Score.Item(W.Link(900)), "S1"), 4 * 1.5 + 10 * 1, "an off-hand weapon: the off hand's")
    sword.equipLoc = "INVTYPE_RANGED"
    near(Score.Value(Score.Item(W.Link(900)), "S1"), 4 * 1.5, "a ranged weapon: the ranged weight, which this profile has not")
    sword.equipLoc = "INVTYPE_2HWEAPON"
    near(Score.Value(Score.Item(W.Link(900)), "S2"), 0, "a profile without weights for any of it scores nothing")
    near(Score.Value(Score.Item(W.Link(900)), "Gone"), 0, "and so does a profile there is not")
    eq(Score.Item("a word"), nil, "what is not an item is not scored")

    local parts, total = Score.Parts(Score.Item(W.Link(900)), "S1")
    near(total, 26, "the same sum, stat by stat"); eq(#parts, 3, "every stat of the item")
    eq(parts[1].name, DPS, "the heaviest first"); near(parts[1].points, 20, "with what it comes to")
    eq(parts[3].name, "ITEM_MOD_UNHEARD_OF_SHORT", "a stat without a weight last"); near(parts[3].weight, 0, "at nothing")

    -- Worn gear is scored without its enchantment.
    local enchanted = W.Link(200):gsub("item:200:", "item:200:66", 1)
    eq(C_Item.GetItemStats(enchanted).TEST_S1, 1018, "(the stand-in client counts an enchantment)")
    near(Score.Value(Score.Item(enchanted), "S1"), 18, "an enchanted link is scored as the bare item")

    -- What an item gives through a spell it keeps on its wearer is in the game's tables.
    ns.GearData.extra[900] = { ITEM_MOD_ATTACK_POWER_SHORT = 10 }
    near(Score.Value(Score.Item(W.Link(900)), "S1"), 26 + 10 * 0.4, "stats from the tables are added to the item's own")
    ns.GearData.extra[900] = nil

    -- Effects a score does not count: the tooltip's marked lines say so, in whatever language.
    local great = Score.Item(W.Link(201))
    local good = W.items["200:0"]
    eq(Score.HasUnscoredEffects(great), true, "a marked line: what the item does when used")
    eq(Score.HasUnscoredEffects(Score.Item(W.Link(200))), false, "no marked line: nothing")
    ns.GearData.newest, ns.GearData.effects[200] = 1000, true
    eq(Score.HasUnscoredEffects(Score.Item(W.Link(200))), false, "the tooltip has the last word over the tables, which can be out of date")
    good.equipLine = true
    eq(Score.HasUnscoredEffects(Score.Item(W.Link(200))), true, "a line of what it does while worn")
    ns.GearData.extra[200] = { ITEM_MOD_ATTACK_POWER_SHORT = 10 }
    eq(Score.HasUnscoredEffects(Score.Item(W.Link(200))), false, "unless the score counts what that line adds")
    good.procLine = true
    eq(Score.HasUnscoredEffects(Score.Item(W.Link(200))), true, "and a chance on hit it never counts")
    good.equipLine, good.procLine, ns.GearData.extra[200] = nil, nil, nil
    -- Without a tooltip to read, the tables.
    local tooltip = C_TooltipInfo.GetHyperlink
    C_TooltipInfo.GetHyperlink = function() return nil end
    eq(Score.HasUnscoredEffects(Score.Item(W.Link(200))), true, "without a tooltip, the tables' list")
    eq(Score.HasUnscoredEffects(great), false, "where the item is not on it, nothing")
    C_TooltipInfo.GetHyperlink = tooltip
    ns.GearData.newest, ns.GearData.effects[200] = 0, nil

    -- A shield's block is not among the stats the game gives: its tooltip has it, in a line
    -- written from the game's own text.
    W.AddItem({ id = 902, name = "Block Shield", equipLoc = "INVTYPE_SHIELD", subClassID = 6, level = 5, block = 14,
        game = { ITEM_MOD_STAMINA_SHORT = 2 } })
    eq(Score.Item(W.Link(902)).stats.ITEM_MOD_BLOCK_VALUE_SHORT, 14, "a shield's block, off its tooltip")
    W.AddItem({ id = 903, name = "Blocky Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, level = 5, block = 14,
        game = { ITEM_MOD_STAMINA_SHORT = 2 } })
    eq(Score.Item(W.Link(903)).stats.ITEM_MOD_BLOCK_VALUE_SHORT, nil, "a shield's only")

    -- What a class can ever wear.
    local function Can(classID, subClassID, who)
        return Score.ClassCanUse({ classID = classID, subClassID = subClassID }, who)
    end
    eq(Can(2, 19), false, "a warrior never holds a wand"); eq(Can(2, 7), true, "a sword it can")
    eq(Can(4, 4), false, "plate comes to a warrior at 40"); eq(Can(4, 3), true, "mail before that")
    eq(Can(4, 4, { class = "WARRIOR", level = 40 }), true, "another character is judged by its own level")
    eq(Can(4, 3, { class = "MAGE", level = 60 }), false, "and class")
    eq(Can(4, 0), true, "a ring is for everyone")

    -- What a consumable adds is scored by the same sum.
    near(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_AGILITY_SHORT = 4 }, "S1"), 16, "a set of stats that is not an item")
    near(Score.StatsValue({ ITEM_MOD_SPIRIT_SHORT = 8 }, "S1"), 0, "nothing for what the profile gives no weight")
    eq(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8 }, "Gone"), nil, "no answer without a profile")

    -- Below level 60 a rating counts for a share of its worth; other stats count as ever.
    eq(Score.LevelFactor(10), 1, "without the simulations of leveling, a rating is worth all of it")
    ns.Weights.leveling = { stats = { ITEM_MOD_CRIT_RATING_SHORT = true }, points = { { 20, 0.2 }, { 40, 0.6 }, { 60, 1 } } }
    near(Score.LevelFactor(10), 0.2, "below the lowest level simulated: that level's share")
    near(Score.LevelFactor(30), 0.4, "between two levels: on a straight line")
    near(Score.LevelFactor(50), 0.8, "and so on up"); near(Score.LevelFactor(60), 1, "all of it at 60")
    near(Score.LevelFactor(nil), 1, "and for no level given")
    local keen = { ITEM_MOD_CRIT_RATING_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 4 }
    near(Score.StatsValue(keen, "S1", 30), 10 * 8 * 0.4 + 4 * 1.5, "a rating by its share, a stat at its weight")
    near(Score.StatsValue(keen, "S1"), 10 * 8 + 4 * 1.5, "the whole worth for no level")
    W.AddItem({ id = 901, name = "Keen Ring", equipLoc = "INVTYPE_FINGER", level = 5, game = { ITEM_MOD_CRIT_RATING_SHORT = 14 } })
    near(Score.Value(Score.Item(W.Link(901)), "S1", 20), 14 * 8 * 0.2, "an item's rating as well")
    local ringParts = Score.Parts(Score.Item(W.Link(901)), "S1", 40)
    near(ringParts[1].weight, 8 * 0.6, "and /upscout stats shows the weight that is used")
    W.equipped[11] = W.Link(901)
    near(Score.Context("S1").equipped[11].value, 14 * 8 * 0.2, "what is worn is scored at the character's level (10)")
    near(Score.Context("S1", { class = "WARRIOR", level = 40, gear = { [11] = W.Link(901) } }).equipped[11].value,
        14 * 8 * 0.6, "and another character's at its own")
    W.equipped[11] = nil
    ns.Weights.leveling = nil

    -- A class without a profile: no scan, and the reason.
    W.OpenAuctionHouse()
    ns.Weights.classes.WARRIOR = nil
    eq(ns.Scanner.Start(), false, "no scan for a character whose class has no profile")
    eq(ns.Scanner.message, ns.L.ERR_NO_PROFILE, "says so")
    ns.Weights.classes.WARRIOR = { "S1", "S2" }
    check(ns.Scanner.Start(), "scans once there is one")
end

-- Everything printed from line `from` on, as one text.
local function Said(from)
    local out = {}
    for i = from, #W.printed do out[#out + 1] = W.printed[i] end
    return table.concat(out, "\n")
end

-- What the game counts for an item, and the command that says how it comes by its score.
function scenarios.item_stats()
    StandardWorld()
    W.items["200:0"].game = { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 120.5,
        ITEM_MOD_NEW_THING_SHORT = 2, odd = "x" }
    W.items["203:0"].cached = false
    LoadAddon()
    local Stats = ns.Stats

    local stats = Stats.Read(W.Link(200))
    eq(stats.ITEM_MOD_STRENGTH_SHORT, 5, "a stat under the game's name for it")
    eq(stats.RESISTANCE0_NAME, 120.5, "armor as well")
    eq(stats.odd, nil, "what is not a number is left out")
    eq(next(Stats.Read(W.Link(208))), nil, "an item that adds nothing: an empty table")
    eq(Stats.Read(W.Link(203)), nil, "an item the game has not loaded: no answer")
    eq(Stats.Read("a word"), nil, "none for what is not an item")
    eq(Stats.Read(nil), nil, "or not a text")
    eq(Stats.Label("ITEM_MOD_STRENGTH_SHORT"), "Strength", "the game's word for a stat")
    eq(Stats.Label("ITEM_MOD_NEW_THING_SHORT"), "ITEM_MOD_NEW_THING_SHORT", "its name where the game has no word")
    eq(Stats.Bare("|cff1eff00|Hitem:6551:66::::::::15:::1:12727::::::|h[Boots]|h|r"),
        "|cff1eff00|Hitem:6551:::::::::15:::1:12727::::::|h[Boots]|h|r", "a link without its enchantment")
    eq(Stats.Bare(W.Link(200)), W.Link(200), "a link that has none is left as it is")

    -- /upscout stats <item>, the item shift-clicked into the chat line: the score, stat by stat
    local at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats " .. W.Link(200))
    local said = Said(at)
    check(said:find("Good Chest", 1, true) and said:find('on the profile "Arms": score 27', 1, true), "the item, the profile and its score")
    local own, strength, stamina = said:find("TEST_S1: 18 × 1 = 18", 1, true), said:find("Strength: 5 × 1.5 = 7.5", 1, true),
        said:find("Stamina: 3 × 0.5 = 1.5", 1, true)
    check(own and strength and stamina, "each stat, its weight and what the two come to")
    check(own < strength and strength < stamina, "the heaviest first")
    check(said:find("Armor: 120.5 × 0", 1, true) ~= nil and said:find("Armor: 120.5 × 0 =", 1, true) == nil,
        "a stat the profile gives no weight is listed as that")
    check(said:find("ITEM_MOD_NEW_THING_SHORT: 2 × 0", 1, true) ~= nil, "a stat the game has no word for goes by its name")
    check(said:find("Pawn", 1, true) == nil, "no word of Pawn where there is no Pawn")

    -- on the profile of the character the lists are for
    ns.Roster.Me().profile = "S2"
    at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats " .. W.Link(200))
    check(Said(at):find('on the profile "Protection ~": score 1.5', 1, true) ~= nil, "another profile, another score")
    ns.Roster.Me().profile = nil

    -- by its number; an item without stats
    at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats 208")
    said = Said(at)
    check(said:find("The game lists no stats for", 1, true) and said:find("Statless Chest", 1, true), "an item that adds nothing")

    -- an item the game has not loaded: it is asked for, and the next time it is there
    at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats 203")
    check(Said(at):find(ns.L.ITEM_STATS_WAIT, 1, true) ~= nil, "an item not loaded: try again")
    W.Run(1)
    at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats 203")
    check(Said(at):find("Future Chest", 1, true) ~= nil, "loaded by then")

    at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats nonsense")
    check(Said(at):find(ns.L.ITEM_STATS_HELP, 1, true) ~= nil, "not an item: how to name one")
    at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats")
    check(Said(at):find(ns.L.STATS_NONE, 1, true) ~= nil, "alone, the command is about the last scan as before")

    -- With Pawn installed it is the same: the addon asks nothing of it.
    PawnGetItemData = function() return { Stats = { Strength = 99 } } end
    at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats " .. W.Link(200))
    said = Said(at)
    check(said:find('score 27', 1, true) ~= nil and said:find("Pawn", 1, true) == nil, "Pawn installed changes nothing")
    PawnGetItemData = nil
end

-- The weights the addon comes with, made by scripts/make-weights.py: every class has
-- profiles, starts on one of its own, and every profile has a name in every language and
-- weights under the game's names for stats.
function scenarios.weights_data()
    local real = {}
    assert(loadfile(ADDON_DIR .. "Weights.lua"))("UpgradeScout", real)
    local data = real.Weights
    check(type(data.source) == "string" and data.source ~= "", "the weights say where they come from")
    check(type(data.APPROX_MARK) == "string" and data.APPROX_MARK ~= "", "and how an estimate is marked")
    local LOCALES = { "enUS", "ruRU", "deDE", "frFR", "zhCN", "ptBR", "esES", "esMX", "koKR", "zhTW" }
    local count = 0
    for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local ids = data.classes[class]
        check(type(ids) == "table" and #ids > 0, class .. " has profiles")
        local starts = false
        for _, id in ipairs(ids or {}) do
            count = count + 1
            local profile = data.profiles[id]
            check(profile ~= nil and profile.class == class, id .. " is a profile of " .. class)
            for _, locale in ipairs(LOCALES) do
                local title = data.titles[locale] and data.titles[locale][id]
                check((type(title) == "string" and title ~= "") or profile.role ~= nil, id .. " has a name in " .. locale)
            end
            local any = false
            for name, weight in pairs(profile.weights) do
                check(name:find("^ITEM_MOD_[%u%d_]+_SHORT$") or name:find("^RESISTANCE%d_NAME$"), id .. ": the game's name for a stat: " .. name)
                check(type(weight) == "number" and weight > 0, id .. ": a weight above nothing for " .. name)
                any = true
            end
            check(any, id .. " has weights")
            for _, hand in ipairs({ "mh", "oh", "ranged" }) do
                check(profile[hand] == nil or (type(profile[hand]) == "number" and profile[hand] > 0), id .. ": " .. hand)
            end
            if id == data.start[class] then starts = true end
        end
        check(starts, class .. " starts on a profile of its own")
    end
    local listed = 0
    for _ in pairs(data.profiles) do listed = listed + 1 end
    eq(listed, count, "every profile is in its class's list")
    -- Staying alive counts on every profile, a tank's or not: Stamina, and armor.
    for id, profile in pairs(data.profiles) do
        check((profile.weights.ITEM_MOD_STAMINA_SHORT or 0) > 0, id .. " has a weight for Stamina")
        check((profile.weights.RESISTANCE0_NAME or 0) > 0, id .. " and for armor")
    end
    -- As 2.0.0 had it, an Arms warrior was told to give up a shield of 411 armor for an item held
    -- in the off hand with no armor, because its Agility was worth more than the shield's Strength.
    local function Worth(id, stats)
        local sum, weights = 0, data.profiles[id].weights
        for name, amount in pairs(stats) do sum = sum + (weights[name] or 0) * amount end
        return sum
    end
    local shield = { ITEM_MOD_STRENGTH_SHORT = 3, RESISTANCE0_NAME = 411, ITEM_MOD_BLOCK_VALUE_SHORT = 7 }
    local held = { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_AGILITY_SHORT = 2 }
    check(Worth("WARRIOR_ARMS", shield) > Worth("WARRIOR_ARMS", held), "a shield's armor counts for a warrior who does damage")
    -- The share of a rating's worth below level 60: rising with the level, all of it at 60.
    local points = data.leveling and data.leveling.points or {}
    check(#points >= 2, "the share of a rating's worth is known at more than one level")
    for i = 2, #points do
        check(points[i][1] > points[i - 1][1] and points[i][2] >= points[i - 1][2], "the share rises with the level")
    end
    eq(points[#points] and points[#points][2], 1, "and is all of it at the last")
    for name in pairs(data.leveling and data.leveling.stats or {}) do
        check(name:find("^ITEM_MOD_[%u_]+_RATING_SHORT$") ~= nil or name == "ITEM_MOD_SPELL_PENETRATION_SHORT",
            "a rating, or spell penetration: " .. name)
    end
end

-- A translation loads, and a scan works with it. `scan` is its text for the Scan button.
-- Our lines in the tooltip of any item, wherever the game shows one (the bags, loot, a link in
-- the chat): for the character being played, the gain on every profile of its class.
function scenarios.tooltips()
    StandardWorld()
    -- A wand, which a warrior never uses.
    W.AddItem({ id = 220, name = "Oak Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subClassID = 19, value = 9, level = 5 })
    -- On the second profile the two chests score 9 (for sale) and 12 (worn).
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    LoadAddon()
    W.Run(1)

    -- Our lines in a tooltip that shows the item: from the line after our header, each as
    -- "left right", joined by " | "; nil when there is no header.
    local function Ours(tooltip, id)
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetHyperlink(W.Link(id))
        local header
        for i, line in ipairs(tooltip._lines) do
            if line.text:find("Upgrade Scout", 1, true) then
                eq(header, nil, "one header only")
                header = i
            end
        end
        if not header then return nil end
        eq(tooltip._lines[header].right, nil, "nothing on the right of the header: the lines are the player's own")
        eq(tooltip._lines[header - 1].text, " ", "a blank line before it")
        local out = {}
        for i = header + 1, #tooltip._lines do
            local line = tooltip._lines[i]
            out[#out + 1] = line.text .. (line.right and " " .. line.right or "")
        end
        return table.concat(out, " | ")
    end
    local function Line(tooltip, text)
        for _, line in ipairs(tooltip._lines) do
            if line.text == text then return line end
        end
    end

    eq(Ours(GameTooltip, 200), "Arms +80% | Protection ~ -25%", "a chest in the bags: 18 against 10, and 9 against 12")
    eq(Line(GameTooltip, "Arms").r, RAID_CLASS_COLORS.WARRIOR.r, "the profiles in the colour of the class")
    eq(Line(GameTooltip, "Protection ~").r, RAID_CLASS_COLORS.WARRIOR.r, "every one of them")
    eq(Line(GameTooltip, "Arms").rightR, GREEN_FONT_COLOR.r, "a gain in green")
    eq(Line(GameTooltip, "Protection ~").rightR, RED_FONT_COLOR.r, "a loss in red")
    eq(Ours(ItemRefTooltip, 200), "Arms +80% | Protection ~ -25%", "the same for a link clicked in the chat")
    eq(Ours(ShoppingTooltip1, 200), nil, "not in the tooltip beside, which shows what is worn")

    eq(Ours(GameTooltip, 211), "Arms +12 pts | Protection ~ +0 pts", "a helm for the empty head: in points")
    eq(Ours(GameTooltip, 201), "Arms +200% | Protection ~ -100% | Has effects the score does not count.",
        "the robe, with what its score leaves out")
    eq(Ours(GameTooltip, 212), "Arms +30% | Protection ~ +0 pts", "a two-hander against the sword")

    eq(Ours(GameTooltip, 100), nil, "nothing for the chest the character has on")
    eq(Ours(GameTooltip, 220), nil, "nothing for a wand: a warrior never uses one")
    eq(Ours(GameTooltip, 214), nil, "nothing for a potion")
    eq(Ours(GameTooltip, 207), nil, "nothing for a shirt")
    eq(Ours(GameTooltip, 208), nil, "nothing for a chest that is worth nothing on any profile")

    -- An item the client has not loaded gets its lines when the game draws the tooltip again.
    W.items["210:0"].cached = false
    eq(Ours(GameTooltip, 210), nil, "nothing while the ring is loading")
    W.items["210:0"].cached = true
    eq(Ours(GameTooltip, 210), "Arms +6 pts | Protection ~ +0 pts", "and then the ring, for the empty second finger")

    -- The game draws a tooltip that is up again and again: what was worked out is kept.
    local reads = W.tooltipReads
    Ours(GameTooltip, 201)
    eq(W.tooltipReads, reads, "the robe's tooltip is not read again")

    -- Another profile chosen: the lines stay as they were.
    ns.Roster.Me().profile = "S2"
    eq(Ours(GameTooltip, 200), "Arms +80% | Protection ~ -25%", "the same lines on another profile in use")
    ns.Roster.Me().profile = "S1"

    -- New gear: a shield in the off hand, and the good chest on.
    W.equipped[17] = W.Link(213)
    W.equipped[5] = W.Link(200)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    eq(Ours(GameTooltip, 200), nil, "the chest now worn has nothing to be compared with")
    eq(Ours(GameTooltip, 100), "Arms -44% | Protection ~ +33%", "the old chest against it: 10 against 18, 12 against 9")
    eq(Ours(GameTooltip, 212), "Arms -4% | Protection ~ +0 pts | Takes both hands.", "the two-hander against sword and shield, 26 against 27")
end

function scenarios.arrows()
    StandardWorld()
    W.AddItem({ id = 220, name = "Oak Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subClassID = 19, value = 9, level = 5 })
    -- On the second profile the good chest scores 9 against the worn chest's 12.
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    LoadAddon()
    W.Run(1)

    -- Whether the slot of the bag window, or of the bank, shows the arrow.
    local function Arrow(button)
        local arrow = button.UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local function Bag(slot) return Arrow(ContainerFrameCombinedBags.Items[slot]) end
    -- Whether the arrow of a slot of the bag window is the grey one.
    local function Grey(slot) return ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow._grey end
    -- Better than the worn chest, but it asks for level 14 and is mail not learned.
    W.AddItem({ id = 230, name = "Future Mail", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 70, level = 14, red = true })

    local slot = {}
    for _, id in ipairs({ 200, 211, 202, 203, 204, 220, 214, 208, 201, 230 }) do slot[id] = W.PutInBags(W.Link(id)) end
    W.OpenBags()
    eq(Bag(slot[200]), true, "a better chest: 18 against 10 on the profile in use")
    eq(ContainerFrameCombinedBags.Items[slot[200]].UpgradeScoutArrow._atlas, "bags-greenarrow", "the game's own green arrow")
    eq(Grey(slot[200]), false, "green: the character can put it on now")
    eq(Bag(slot[211]), true, "a helm for the empty head")
    eq(Bag(slot[201]), true, "the robe, whose effects the score leaves out")
    eq(Bag(slot[202]), false, "not a weaker chest")
    eq(Bag(slot[203]), true, "a better chest above the character's level")
    eq(Grey(slot[203]), true, "grey: its tooltip says in red that it asks for level 14")
    eq(Bag(slot[204]), false, "not mail the character has not learned")
    eq(Bag(slot[230]), false, "nor such mail of a higher level: more than the level is red")
    eq(Bag(slot[220]), false, "not a wand: a warrior never uses one")
    eq(Bag(slot[214]), false, "not a potion")
    eq(Bag(slot[208]), false, "not a chest worth nothing")
    eq(ContainerFrameCombinedBags.Items[slot[214]].UpgradeScoutArrow, nil, "a slot that never had an arrow gets no texture")
    eq(Bag(16), false, "not an empty slot")

    -- The item moved away: the game draws the bags again.
    W.bags[0][slot[201]] = nil
    W.DrawBags()
    eq(Bag(slot[201]), false, "the slot of the robe, now empty")

    -- An item the game is still loading gets its arrow once it has it.
    W.items["210:0"].cached = false
    local ring = W.PutInBags(W.Link(210))
    W.DrawBags()
    eq(Bag(ring), false, "nothing while the ring is loading")
    W.items["210:0"].cached = true
    W.Run(1.5)
    eq(Bag(ring), true, "then the ring, for the empty second finger")

    -- The bank's slots are made when it opens.
    W.bags[6] = { [3] = { link = W.Link(211) }, [4] = { link = W.Link(202) } }
    W.OpenBank(6)
    local bank = {}
    for button in BankPanel:EnumerateValidItems() do bank[button._slot] = button end
    eq(Arrow(bank[3]), true, "the helm in the bank")
    eq(Arrow(bank[4]), false, "not the weaker chest in the bank")

    -- Another profile chosen: on it the good chest is worse than the worn one (9 against 12).
    W.OpenAuctionHouse()
    UpgradeScoutFrame.ProfileDropdown:Pick(2)
    W.Run(1)
    eq(ns.Roster.Me().profile, "S2", "the second profile chosen")
    eq(Bag(slot[200]), false, "the good chest loses its arrow")
    UpgradeScoutFrame.ProfileDropdown:Pick(1)
    W.Run(1)
    eq(Bag(slot[200]), true, "and has it again on the first")

    -- A level up: the chest that asked for level 14.
    W.player.level = 14
    W.Fire("PLAYER_LEVEL_UP", 14)
    W.Run(2)
    eq(Bag(slot[203]), true, "the chest of level 14, now that the character has it")
    eq(Grey(slot[203]), false, "is green now")
    eq(Bag(slot[230]), false, "the mail still not learned")

    -- New gear: the future chest goes on, so the good chest is no better than what is worn.
    W.equipped[5] = W.Link(203)
    W.bags[0][slot[203]] = nil
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    eq(Bag(slot[200]), false, "the good chest against the chest now worn, 18 against 60")
    eq(Bag(slot[211]), true, "the helm still")
end

---------------------------------------------------------------------------
-- The welcome window, and what it sets
---------------------------------------------------------------------------
-- The profile a character is scored on while none is chosen for it: the one for the talent
-- tree it has the most points in.
function scenarios.talents()
    StandardWorld()
    -- Three trees, most points in the last. The tests' warrior has two profiles, named after
    -- the first tree and the last.
    W.player.talents = { { name = "Arms", points = 3 }, { name = "Fury", points = 0 }, { name = "Protection", points = 11 } }
    LoadAddon()
    local Score, me = ns.Score, ns.Roster.Me()
    eq(Score.Current().name, "S1", "before the character is written down: the profile its class starts with")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(me.talents, "S2", "the profile named after the tree with the most points")
    eq(Score.Current().name, "S2", "is the one the character is scored on"); eq(me.profile, nil, "without being chosen")
    me.profile = "S1"
    eq(Score.Current().name, "S1", "a choice of the player's stands above it")
    me.profile = nil

    -- Points go into the first tree: the profile follows, and the addon is told.
    local told = 0
    ns.Listen("PROFILE_CHANGED", function(card) if card == me then told = told + 1 end end)
    W.player.talents[1].points = 20
    W.Fire("TRAIT_CONFIG_UPDATED", 1)
    W.Run(1.5)
    eq(Score.Current().name, "S1", "talents learned: the profile of the tree now ahead"); eq(told, 1, "the addon is told of it")
    W.Fire("TRAIT_CONFIG_UPDATED", 1)
    W.Run(1.5)
    eq(told, 1, "and only when it changes")

    -- No answer leaves what was known: no points anywhere, an error in the game's functions,
    -- a game without them.
    W.player.talents = { { name = "Arms", points = 0 }, { name = "Fury", points = 0 }, { name = "Protection", points = 0 } }
    W.Fire("TRAIT_CONFIG_UPDATED", 1)
    W.Run(1.5)
    eq(me.talents, "S1", "no points spent: what was known stays")
    W.player.talents[3].points, W.talentsFail = 30, true
    W.Fire("TRAIT_CONFIG_UPDATED", 1)
    W.Run(1.5)
    eq(me.talents, "S1", "an error in the game's talent functions is no answer"); eq(#W.errors, 0, "and no error of ours")
    W.talentsFail, W.player.talents = nil, nil
    W.Fire("TRAIT_CONFIG_UPDATED", 1)
    W.Run(1.5)
    eq(me.talents, "S1", "nor is a game that says nothing of talents")

    -- Which profile a tree is: by its name, by its place, by the one profile that stands for several.
    eq(Score.ForTree("WARRIOR", "Protection", 3, 3), "S2", "a tree by its name")
    eq(Score.ForTree("WARRIOR", "Fury", 2, 3), nil, "none for a tree no profile is named after, in a class with fewer profiles than trees")
    eq(Score.ForTree("DRUID", "Wild", 2, 2), "D2", "by its place, where the class has a profile for each tree")
    eq(Score.ForTree("SHAMAN", "Elemental", 1, 3), nil, "none for a class without profiles")
    ns.Weights.classes.PRIEST = { "R1", "R2" }
    ns.Weights.profiles.R1 = { class = "PRIEST", role = "HEALER", weights = {} }
    ns.Weights.profiles.R2 = { class = "PRIEST", weights = {} }
    ns.Weights.titles.enUS.R2 = "Shadow"
    eq(Score.ForTree("PRIEST", "Shadow", 3, 3), "R2", "a priest's Shadow by its name")
    eq(Score.ForTree("PRIEST", "Holy", 2, 3), "R1", "its other trees are the profile that stands for several")
    ns.Weights.titles.ruRU = { S2 = "Защита" }
    W.locale = "ruRU"
    eq(Score.ForTree("WARRIOR", "Защита", 3, 3), "S2", "a tree by its name in the player's language")
    eq(Score.ForTree("WARRIOR", "Arms", 1, 3), "S1", "or in English")
    W.locale = nil

    -- The card of a character that is not being played carries it too.
    eq(Score.Current({ class = "DRUID", talents = "D2" }).name, "D2", "another character: the profile of its talents")
    eq(Score.Current({ class = "DRUID", talents = "D2", profile = "D1" }).name, "D1", "under the one chosen for it")
    eq(Score.Current({ class = "DRUID", talents = "Gone" }).name, "D1", "one that is no longer there gives way to the class's own")
end

-- The window that comes up the first time: what the addon does, the talent tree, and the two
-- things that can be switched off.
function scenarios.welcome()
    StandardWorld()
    -- The two rings of the window's pictures. The game has not loaded the second yet.
    W.AddItem({ id = 16999, name = "Royal Seal", equipLoc = "INVTYPE_FINGER", quality = 3, level = 54 })
    W.AddItem({ id = 5000, name = "Coral Band", equipLoc = "INVTYPE_FINGER", level = 21, uncached = true })
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.player.talents = { { name = "Arms", points = 2 }, { name = "Fury", points = 0 }, { name = "Protection", points = 9 } }
    W.combat = true
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(3)
    eq(UpgradeScoutWelcome, nil, "not the moment the character is in the world")
    W.Run(8)
    eq(UpgradeScoutWelcome, nil, "and not in the middle of a fight")
    W.combat = nil
    W.RunUntil(function() return UpgradeScoutWelcome ~= nil end, 6)
    local window = UpgradeScoutWelcome
    eq(window:IsShown(), true, "the window comes up by itself once the fight is over")
    eq(window.About:GetText(), ns.L.WELCOME_FIRST, "with a welcome")
    eq(UpgradeScoutDB.welcomed, nil, "not seen yet while it is up")
    local escape = false
    for _, name in ipairs(UISpecialFrames) do escape = escape or name == "UpgradeScoutWelcome" end
    check(escape, "Escape closes it")
    check(window:GetHeight() > 300, "as tall as what it holds")

    -- A button for each profile of the class; the one in use is the tree the talents are in.
    local trees = window.Trees
    eq(#trees, 2, "a button for each profile of the class")
    eq(trees[1].Label:GetText(), "Arms", "by its name"); eq(trees[2].Label:GetText(), "Protection ~", "an estimated one marked as in the field")
    eq(trees[2].Mark:IsShown(), true, "the one in use is lit: the tree the talents are in"); eq(trees[1].Mark:IsShown(), false, "the other is not")
    check(window.Ask:GetText():find("Tester", 1, true) ~= nil, "the question names the character")
    check(window.Ask:GetText():find(ns.L.WELCOME_TREE_WHY, 1, true) ~= nil, "and says what the answer is for")

    -- The pictures: the list, an item's tooltip, the bags.
    local list, tip, bag = window.Cards[1].Picture, window.Cards[2].Picture.Tip, window.Cards[3].Picture
    eq(list.Rows[1].Name:GetText(), "Royal Seal", "the list's picture: an item by the name the game has for it")
    eq(list.Rows[2].Name:GetText(), "", "no name for one the game has not loaded")
    eq(list.Rows[1].Gain:GetText(), "+36%", "its gain on the profile in use, the second of the class")
    eq(list.Rows[1].Price:GetText(), "1g 69s", "and a price")
    eq(tip.Name:GetText(), "Royal Seal", "the tooltip's picture: the same item")
    eq(tip.Lines[1].Title:GetText(), "Arms", "a line for each profile"); eq(tip.Lines[1].Gain:GetText(), "+31%", "with its gain")
    eq(tip.Lines[2].Title:GetText(), "Protection ~", "every one of them"); eq(tip.Lines[2].Gain:GetText(), "+36%", "each its own")
    eq(tip.Lines[3], nil, "and no more lines than profiles")
    eq(bag.Slots[1].Arrow._atlas, "bags-greenarrow", "the bags' picture: the game's arrow")
    eq(bag.Slots[1].Arrow._grey, false, "green on the first"); eq(bag.Slots[2].Arrow._grey, true, "grey on the second")
    W.Run(1)
    eq(list.Rows[2].Name:GetText(), "Coral Band", "the second ring, once the game has loaded it")
    check(window.Cards[1].Body:GetText():find("Scan", 1, true) and window.Cards[1].Body:GetText():find("Consumables", 1, true),
        "the auction house's card names the button and the tabs")
    eq(window.Cards[2].Title:GetText(), "IN ITEM TOOLTIPS", "a card's name in capitals")

    -- Another tree chosen: written on the character's card, as in the field on the tab.
    local told = 0
    ns.Listen("PROFILE_CHANGED", function() told = told + 1 end)
    trees[1]:Click()
    eq(ns.Roster.Me().profile, "S1", "a click on a tree chooses its profile"); eq(told, 1, "and the addon is told")
    eq(trees[1].Mark:IsShown(), true, "the button lights up"); eq(trees[2].Mark:IsShown(), false, "the other goes dark")
    eq(list.Rows[1].Gain:GetText(), "+31%", "the list's picture goes by the profile in use")
    eq(tip.Lines[2].Gain:GetText(), "+36%", "the tooltip's has every profile, as before")
    trees[1]:Click()
    eq(told, 1, "the profile in use clicked again: nothing changes")

    -- Our lines in the tooltip of any item, switched off and on.
    local function Ours(id)
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink(W.Link(id))
        for _, line in ipairs(GameTooltip._lines) do
            if line.text:find("Upgrade Scout", 1, true) then return true end
        end
        return false
    end
    local tips = window.Cards[2].Switch
    eq(tips:GetChecked(), true, "the tooltip's box is ticked to begin with"); eq(Ours(200), true, "and an item's tooltip has our lines")
    tips:SetChecked(false)
    tips:Click()
    eq(UpgradeScoutDB.tooltip, false, "unticked: written down for the account"); eq(Ours(200), false, "and the lines are gone")
    eq(tips.Tick:IsShown(), false, "the tick goes"); eq(window.Cards[2].Picture:GetAlpha(), 0.3, "and the picture fades")

    -- The arrows in the bags, the same way: they go and come at once.
    local slot = W.PutInBags(W.Link(200))
    W.OpenBags()
    local function Arrow()
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(Arrow(), true, "an arrow on the better chest")
    local arrows = window.Cards[3].Switch
    arrows:SetChecked(false)
    arrows:Click()
    eq(UpgradeScoutDB.arrows, false, "unticked: written down"); eq(Arrow(), false, "and the arrow is gone at once")
    W.DrawBags()
    eq(Arrow(), false, "it stays away when the bags are drawn again")
    arrows:SetChecked(true)
    arrows:Click()
    eq(UpgradeScoutDB.arrows, nil, "ticked again: nothing is left written"); eq(Arrow(), true, "and the arrow is back")
    eq(window.Cards[1].Switch, nil, "the auction house has no box: its tabs are in nobody's way")
    eq(ns.Tooltip.Upgrade(W.Link(200)), true, "the arrows do not need the tooltip's lines")

    -- Closed, it has been seen: it does not come up by itself again.
    window.Done:Click()
    eq(window:IsShown(), false, "the button closes it"); eq(UpgradeScoutDB.welcomed, true, "and it has been seen")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "it does not come up by itself again")

    -- /upscout brings it back, without the welcome and with the boxes as they were left.
    SlashCmdList.UPGRADESCOUT("")
    eq(window:IsShown(), true, "/upscout away from the auction house opens it")
    eq(window.About:GetText(), ns.L.WELCOME_ABOUT, "without the welcome this time")
    eq(tips:GetChecked(), false, "the boxes as they were left"); eq(arrows:GetChecked(), true, "both of them")
    window.Close:Click()
    eq(window:IsShown(), false, "the cross closes it")

    -- At the auction house the command goes to the tab first, and from the tab to the window.
    W.OpenAuctionHouse()
    local tab = UpgradeScoutFrame
    eq(tab:IsShown(), false, "the auction house is open on another tab")
    SlashCmdList.UPGRADESCOUT("")
    eq(tab:IsShown(), true, "/upscout: to the addon's tab"); eq(window:IsShown(), false, "not to the window")
    SlashCmdList.UPGRADESCOUT("")
    eq(window:IsShown(), true, "on the tab already: the window")

    -- A tree chosen there with a list made: as in the field, the list is made again.
    ScanToEnd()
    eq(ns.Scanner.ctx.profile, "S1", "a list on the first profile")
    trees[2]:Click()
    eq(ns.Roster.Me().profile, "S2", "the second tree chosen in the window")
    check(ns.Scanner.state ~= "idle", "the scan starts again")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 600)
    eq(ns.Scanner.ctx.profile, "S2", "and the list is on the profile chosen")
    eq(tab.ProfileDropdown:GetText(), "Protection ~", "the field on the tab shows it")
    eq(trees[2].Mark:IsShown(), true, "and so does the window")

    -- Another character of the account is not greeted again, and has the same boxes.
    Relog({ name = "Alty", level = 20, class = "DRUID", money = 5000 }, {})
    W.Run(12)
    eq(ns.Welcome.IsShown(), false, "another character of the account: no window by itself")
    eq(ns.Shows("tooltip"), false, "what was switched off stays off for it"); eq(ns.Shows("arrows"), true, "what was on stays on")
    ns.Welcome.Show()
    eq(#UpgradeScoutWelcome.Trees, 2, "asked for, it has the trees of this character's class")
    eq(UpgradeScoutWelcome.Trees[2].Label:GetText(), "Feral", "by their names")
end

-- The button at the minimap (Minimap.lua): our own, or LibDBIcon's where an addon brought it.
function scenarios.minimap()
    local ICON = "Interface\\AddOns\\UpgradeScout\\icon"
    local function about(actual, expected, label)
        checks = checks + 1
        if type(actual) ~= "number" or math.abs(actual - expected) > 0.01 then
            error(string.format("%s: expected about %s, got %s", label, tostring(expected), tostring(actual)), 2)
        end
    end
    -- Where a button is, from the middle of the minimap.
    local function At(button)
        local point = button._points[1]
        eq(point.point, "CENTER", "the button is put by its middle"); eq(point.to, Minimap, "against the minimap")
        eq(point.toPoint, "CENTER", "from the middle of it")
        return point.x, point.y
    end
    -- A new session of the addon for `player`. libraries(), if given, runs when the addon's
    -- files are in and the game has not yet said the character is logged in: the moment by
    -- which other addons have brought their libraries.
    local function Session(player, libraries)
        if player then
            W.Logout()
            W.Login(player, {})
            ns = {}
        end
        UpgradeScoutMinimapButton = nil
        LoadAddon()
        if libraries then libraries() end
        eq(UpgradeScoutMinimapButton, nil, "no button before the character is logged in")
        W.Fire("PLAYER_LOGIN")
        W.Fire("PLAYER_ENTERING_WORLD")
    end

    StandardWorld()
    -- The middle of the minimap on the screen, and the scale the game draws it at.
    Minimap._center, Minimap._scale = { 1000, 600 }, 0.8
    Session()
    local button = UpgradeScoutMinimapButton
    check(button ~= nil, "logged in: a button of our own")
    eq(button:GetParent(), Minimap, "on the minimap"); eq(button:IsShown(), true, "in view")
    eq(button:GetWidth(), 31, "as big as the game's own buttons there")
    eq(button.Icon:GetTexture(), ICON, "with the addon's icon")
    eq(Pictures(button, "MiniMap-TrackingBorder"), 1, "in the game's ring")
    local x, y = At(button)
    about(x, -79.696, "to begin with on the left of the minimap, ten past its edge"); about(y, 6.972, "a little above the middle")
    about(UpgradeScoutDB.minimap.minimapPos, 175, "the place is written down for the account")

    -- Pointed at, it says what it is for.
    button:GetScript("OnEnter")(button)
    eq(GameTooltip:GetOwner(), button, "pointed at: a tooltip"); eq(GameTooltip:IsShown(), true, "in view")
    eq(#GameTooltip._lines, 3, "of three lines"); eq(GameTooltip._lines[1].text, "Upgrade Scout", "the addon's name")
    eq(GameTooltip._lines[2].text, ns.L.MINIMAP_CLICK, "what a click does"); eq(GameTooltip._lines[3].text, ns.L.MINIMAP_DRAG, "and that it can be dragged")
    button:GetScript("OnLeave")(button)
    eq(GameTooltip:IsShown(), false, "the tooltip goes with the cursor")

    -- A click opens the window, another closes it. Before the game has said who the
    -- character is, too: the button is there from the first moment.
    button:Click()
    local window = UpgradeScoutWelcome
    check(window ~= nil and window:IsShown(), "a click opens the addon's window")
    eq(window.Again:GetText(), ns.L.WELCOME_AGAIN, "whose last line points back at the button")
    button:Click()
    eq(window:IsShown(), false, "another click closes it"); eq(UpgradeScoutDB.welcomed, true, "and the window has been seen")
    W.Run(12)
    eq(window:IsShown(), false, "seen by way of the button, it does not come up by itself after")
    button:Click()
    eq(#window.Trees, 2, "opened again: the trees of the character, known by now")
    button:Click()

    -- Dragged, it goes around the minimap after the cursor, and stays where it is let go.
    W.pointer = { 800, 560 }            -- straight above the middle, at the minimap's scale
    button:GetScript("OnEnter")(button)
    button:GetScript("OnDragStart")(button)
    eq(GameTooltip:IsShown(), false, "dragged: the tooltip gets out of the way")
    W.Tick()
    x, y = At(button)
    about(x, 0, "it goes to where the cursor is: the top of the minimap"); about(y, 80, "on its edge")
    about(UpgradeScoutDB.minimap.minimapPos, 90, "and the place is written down")
    W.pointer = { 720, 560 }            -- above and to the left
    W.Tick()
    x, y = At(button)
    about(x, -56.569, "on with the cursor"); about(y, 56.569, "along the edge")
    button:GetScript("OnDragStop")(button)
    W.pointer = { 1100, 500 }
    W.Tick()
    x, y = At(button)
    about(x, -56.569, "let go, it stays"); about(y, 56.569, "where it was left")
    about(UpgradeScoutDB.minimap.minimapPos, 135, "the place it was left at")

    -- An addon makes the minimap bigger and square: the button keeps to its edge.
    GetMinimapShape = function() return "SQUARE" end
    Minimap:SetSize(200, 200)
    Minimap:GetScript("OnSizeChanged")(Minimap)
    x, y = At(button)
    about(x, -102.929, "a bigger, square minimap: out towards its corner"); about(y, 102.929, "at once")
    -- Another gives it one round corner, with no change of size: seen when the world is entered.
    GetMinimapShape = function() return "CORNER-TOPLEFT" end
    W.Fire("PLAYER_ENTERING_WORLD")
    x, y = At(button)
    about(x, -77.782, "a round corner where the button is: on the round of it"); about(y, 77.782, "as on a round minimap")
    GetMinimapShape = function() return "CORNER-BOTTOMRIGHT" end
    W.Run(3.5)
    x, y = At(button)
    about(x, -102.929, "reshaped a moment after: the button follows"); about(y, 102.929, "by itself")
    GetMinimapShape = nil
    Minimap:SetSize(140, 140)

    -- Another character of the account has the button where it was left.
    Session({ name = "Alty", level = 20, class = "DRUID", money = 5000 })
    check(UpgradeScoutMinimapButton ~= nil and UpgradeScoutMinimapButton ~= button, "another character: a button again")
    x, y = At(UpgradeScoutMinimapButton)
    about(x, -56.569, "where the first character left it"); about(y, 56.569, "on a minimap of the usual size")

    -- Another addon has brought LibDBIcon (and LibDataBroker, which it needs): the button is
    -- that library's, which the tools that gather the minimap's buttons know.
    local made, launchers = {}, {}
    local function Libraries()
        local brokers = LibStub:NewLibrary("LibDataBroker-1.1", 4)
        function brokers:NewDataObject(name, object)
            launchers[name] = object
            return object
        end
        local icons = LibStub:NewLibrary("LibDBIcon-1.0", 57)
        function icons:Register(name, object, db)
            local theirs = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
            theirs.dataObject, theirs.db = object, db
            made[name] = theirs
        end
        function icons:GetMinimapButton(name) return made[name] end
    end
    Session({ name = "Tester", level = 10, class = "WARRIOR", money = 5000 }, Libraries)
    W.Run(1.5)
    eq(UpgradeScoutMinimapButton, nil, "LibDBIcon is there: no button of our own")
    local theirs = made.UpgradeScout
    check(theirs ~= nil, "the library makes the button, under the addon's name")
    eq(theirs.db, UpgradeScoutDB.minimap, "it is given the place to keep"); about(theirs.db.minimapPos, 135, "where our own button was")
    eq(theirs.db.hide, nil, "and nothing says to hide it")
    local launcher = theirs.dataObject
    eq(launcher, launchers.UpgradeScout, "from a launcher given to LibDataBroker"); eq(launcher.type, "launcher", "of that kind")
    eq(launcher.icon, ICON, "with the addon's icon"); eq(launcher.label, "Upgrade Scout", "and its name")
    launcher.OnClick(theirs, "LeftButton")
    eq(ns.Welcome.IsShown(), true, "a click on it opens the window")
    launcher.OnClick(theirs, "RightButton")
    eq(ns.Welcome.IsShown(), false, "and closes it, with either button of the mouse")
    GameTooltip:SetOwner(theirs)
    launcher.OnTooltipShow(GameTooltip)
    eq(#GameTooltip._lines, 3, "its tooltip: the same three lines"); eq(GameTooltip._lines[3].text, ns.L.MINIMAP_DRAG, "it can be dragged too")
    GameTooltip:SetOwner(UIParent)
    launcher.OnTooltipShow(GameTooltip)
    eq(#GameTooltip._lines, 2, "the launcher on a bar: nothing about dragging"); eq(GameTooltip._lines[2].text, ns.L.MINIMAP_CLICK, "only what a click does")

    -- A LibDBIcon that will not make the button: our own after all, and the launcher stays.
    made, launchers = {}, {}
    Session({ name = "Tester", level = 10, class = "WARRIOR", money = 5000 }, function()
        Libraries()
        LibStub("LibDBIcon-1.0").Register = function() error("not today") end
    end)
    check(UpgradeScoutMinimapButton ~= nil, "the library fails to make the button: our own")
    eq(next(made), nil, "and none of the library's"); check(launchers.UpgradeScout ~= nil, "the launcher is on the bars all the same")
    UpgradeScoutMinimapButton:GetScript("OnEnter")(UpgradeScoutMinimapButton)
    eq(#GameTooltip._lines, 3, "our own button says it can be dragged")

    -- LibDataBroker alone, brought by a bar of launchers: a launcher there, our own button here.
    made, launchers = {}, {}
    Session({ name = "Tester", level = 10, class = "WARRIOR", money = 5000 }, function()
        local brokers = LibStub:NewLibrary("LibDataBroker-1.1", 4)
        function brokers:NewDataObject(name, object)
            launchers[name] = object
            return object
        end
    end)
    check(UpgradeScoutMinimapButton ~= nil, "LibDataBroker without LibDBIcon: our own button")
    check(launchers.UpgradeScout ~= nil, "and a launcher")
end

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

function scenarios.locale_ko()
    CheckLocale("koKR", "Korean", "스캔")
end

function scenarios.locale_tw()
    CheckLocale("zhTW", "Traditional Chinese", "掃描")
end

---------------------------------------------------------------------------
local fn = scenarios[scenario]
if not fn then
    realPrint("unknown scenario: " .. tostring(scenario))
    os.exit(2)
end
local ok, err = xpcall(fn, debug.traceback)
-- An error in a handler of the addon does not stop the game, or a scenario: it is looked for here.
if ok and W.errors[1] then ok, err = false, "an error in a handler:\n" .. W.errors[1] end
if ok then
    realPrint(string.format("ok    %-20s %d checks", scenario, checks))
    os.exit(0)
else
    realPrint(string.format("FAIL  %-20s after %d checks", scenario, checks))
    realPrint(err)
    os.exit(1)
end
