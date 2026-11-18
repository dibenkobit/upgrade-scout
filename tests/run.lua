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
    "pawn_scan", "pawn_absent", "pawn_tooltips", "pawn_welcome", "pawn_supplies", "pawn_alt", "pawn_unread",
    "talents", "welcome", "minimap",
    "tooltip_settings",
    "wants", "wants_ui", "gain_ui",
    "buy_refused", "prices",
    "pawn_effects",
    "price_max", "price_max_ui",
    "companion_scan", "companion_absent", "companion_tooltips", "companion_welcome", "companion_supplies", "companion_alt",
    "companion_chance",
    "scan_listed",
    "leveling_scan", "leveling_hands", "leveling_absent", "leveling_tooltips", "leveling_welcome", "leveling_supplies", "leveling_alt",
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

-- An offer by its item's name, once its price has been looked up. (An item is in the list
-- before that, from the moment it is known, at the lowest price of its row: see Unsure.)
local function Offer(name)
    for _, offer in pairs(ns.Scanner.offers) do
        if offer.name == name and not offer.unsure then return offer end
    end
end

-- An item that is in the list at the lowest price of its row, which has not been looked up.
local function Unsure(name)
    for _, offer in pairs(ns.Scanner.offers) do
        if offer.name == name and offer.unsure then return offer end
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

-- How many offers have had their price looked up.
local function OfferCount()
    local n = 0
    for _, offer in pairs(ns.Scanner.offers) do
        if not offer.unsure then n = n + 1 end
    end
    return n
end

-- And how many are in the list at a price that has not: all of them, or with `over` those
-- that cost more than that many copper.
local function UnsureCount(over)
    local n = 0
    for _, offer in pairs(ns.Scanner.offers) do
        if offer.unsure and offer.buyout > (over or 0) then n = n + 1 end
    end
    return n
end

local function ScanToEnd()
    check(ns.Scanner.Start(), "scan starts")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 600)
end

-- The two filters of the tab that are on from the start. With both off the list shows every
-- upgrade, so the scan has to look up every price.
local function SetView(affordableOnly, topOnly)
    ns.db.affordableOnly = affordableOnly
    ns.db.topOnly = topOnly
end

-- A tick box of the Filters menu of the tab (Filters.lua), by its label, for a test to handle
-- as the player does. The menu is opened for every look and every click, which has the game
-- describe it anew, and closed again.
local function FilterBox(label)
    local box = {}
    local function Look(what)
        local field = UpgradeScoutFrame.FilterField
        field:Open()
        local at = field:Find(label)
        local seen = what(field, at)
        field:Close()
        return seen
    end
    -- Has the menu of the view in sight such a line?
    function box:IsShown() return Look(function(_, at) return at ~= nil end) end
    function box:GetChecked() return Look(function(field, at) return field.lines[at].Tick:IsShown() end) end
    function box:IsEnabled() return Look(function(field, at) return field.lines[at]:IsEnabled() end) end
    function box:Click() Look(function(field) field:Tick(label) end) end
    -- Its tooltip, written into the game's.
    function box:Tooltip()
        Look(function(field, at)
            GameTooltip:SetOwner(field.lines[at])
            field.checks[at].tooltip(GameTooltip, field.checks[at])
        end)
    end
    return box
end

-- The labels of the Filters menu's tick boxes, top to bottom, with a "/" where a rule is.
local function FilterMenu()
    local field = UpgradeScoutFrame.FilterField
    field:Open()
    local out = {}
    for i, tickBox in ipairs(field.checks) do
        out[#out + 1] = tickBox.text
        for _, rule in ipairs(field.rules) do
            if rule.afterCheck == i then out[#out + 1] = "/" end
        end
    end
    field:Close()
    return table.concat(out, " | ")
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
    check(UnsureCount(GetMoney()) > 0, "rows that cost too much are counted at their lowest price, without a search")
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
    eq(UnsureCount(), 0, "no price in the list that was not looked up")
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
    eq(UnsureCount(), 1, "the sixth item stays in it at the lowest price of its row")
    check(Status():find("6 upgrades in 5 slots.", 1, true) ~= nil, "the status line counts them all: " .. Status())
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
    check(frame.PlanBar.Check.Text._font ~= nil, "a tick box's label has a font")
    check(frame.FilterNames._font ~= nil, "and so have the names beside the Filters field")
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

-- The list has its items from the moment they are known, each at the lowest price of its row,
-- before any price is looked up. The searches that follow put the prices right, and a purchase
-- does not wait for them.
function scenarios.scan_listed()
    StandardWorld()
    LoadAddon()
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    -- The row of an item in the list, as it is drawn.
    local function Row(name)
        for _, w in ipairs(box:GetFrames()) do
            local data = w._shown and w:GetElementData().data
            if data and data.kind == "item" and data.entry.offer.name == name then return w end
        end
    end
    -- What the tooltip of a row says, line by line.
    local function Tooltip(row)
        row:GetScript("OnEnter")(row)
        local out = {}
        for _, line in ipairs(GameTooltip._lines) do out[#out + 1] = line.text end
        return table.concat(out, " | ")
    end
    local NOTE = "Price from the auction list, still being checked"

    check(S.Start(), "scan starts")
    W.RunUntil(function() return UnsureCount() > 0 end, 10)
    eq(S.state, "verify", "the items are in the list as the price checks begin")
    eq(OfferCount(), 0, "before any price has been looked up")
    eq(Unsure("New Ring").buyout, 800, "the ring at the lowest price of its row")
    eq(Unsure("Helm").buyout, 2500, "and the helm")
    eq(Unsure("Good Chest").buyout, 1, "the good chest at the lowest number of its row, which is a bid")
    check(Unsure("Bid Only Chest") ~= nil, "an item that takes bids alone is listed until its search says so")
    check(Unsure("My Own Chest") ~= nil, "a row with an auction of the player's own is listed until its search says whose it is")
    eq(Unsure("Weak Chest"), nil, "what is no upgrade is not listed")
    eq(Unsure("Future Chest"), nil, "nor what asks for a higher level")
    eq(Unsure("Unlearned Mail"), nil, "nor what the character cannot wear")
    eq(S.Unchecked().groups.CHEST, nil, "no row is counted as one that waits: they are all in the list")

    -- As the player sees it: the rows are there, their prices written like any other, and
    -- can be bought from. The status line says that the prices are looked up, and that some
    -- of them may be bids; the tooltip of a row says it of that row.
    W.Run(0.1)
    local ring = Row("New Ring")
    check(ring ~= nil, "the ring has its row")
    eq(ring.Price:GetAlpha(), 1, "its buyout in full ink, though not looked up yet"); eq(ring.Net:GetAlpha(), 1, "and its net cost")
    eq(ring.Buy:IsEnabled(), true, "and it can be bought at once")
    check(Tooltip(ring):find(NOTE, 1, true) ~= nil, "its tooltip says where the price is from: " .. Tooltip(ring))
    check(frame.Status:GetText():find("Checking prices (some may be bids): ", 1, true) ~= nil, "the status line: " .. frame.Status:GetText())

    -- The searches put the list right: the same offers as ever.
    W.RunUntil(function() return S.state == "idle" end, 60)
    W.Run(0.3)
    CheckStandardOffers("listed first")
    eq(UnsureCount(), 0, "no price is left that was not looked up")
    eq(Offer("Good Chest").buyout, 4000, "the good chest at its cheapest buyout")
    eq(Row("Bid Only Chest"), nil, "the item that takes bids alone is out of the list")
    ring = Row("New Ring")
    check(Tooltip(ring):find(NOTE, 1, true) == nil, "and the tooltip has nothing to add")

    -- A purchase during the price checks: they give way to it, the item is looked up as it is
    -- before any purchase, and the box asks at the buyout that found, not at the bid the row
    -- was listed at. The checks pick up again when the purchase is over.
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "second scan starts")
    W.RunUntil(function() return UnsureCount() > 0 end, 10)
    W.Run(0.1)
    eq(S.CanBuy(), true, "a purchase can begin while the prices are looked up")
    -- (For a moment the chest that takes bids alone, listed at a copper, is the one row of its
    -- slot: no chest can stand beside it at that price. Its search comes first, the biggest
    -- upgrade there is, and takes it out.)
    check(Row("Bid Only Chest") ~= nil and Row("Good Chest") == nil, "the chest slot for now: the one listed at a bid")
    local good = Unsure("Good Chest")
    eq(good.buyout, 1, "the good chest is still at the bid")
    S.Buy(good)
    eq(S.mode, "buy", "the price checks give way to the purchase")
    W.RunUntil(Asking, 30)
    eq(Asking().offer.buyout, 4000, "the box asks at the buyout the search found")
    check(UnsureCount() > 0, "with other prices still to be looked up")
    Asking().Buy:Click()
    W.RunUntil(function() return #S.acquired == 1 end, 30)
    W.RunUntil(function() return S.state == "idle" and UnsureCount() == 0 end, 120)
    eq(S.halted, false, "the price checks went on by themselves, to their end")
    eq(Offer("Good Chest").buyout, 5000, "the next good chest is listed at its own price")
    eq(OfferCount(), 6, "and the other offers are all there")
    eq(S.stats.checked - S.stats.exact, 2, "statistics: of the rows searched, two were listed at a bid, the rest at their cheapest buyout")

    -- A row listed at a bid, bought from: there is nothing to buy out. The chat says so, as
    -- of any item that is gone by the time it is asked for, and the row leaves the list.
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "third scan starts")
    W.RunUntil(function() return UnsureCount() > 0 end, 10)
    W.Run(0.1)
    local bids = Row("Bid Only Chest")
    check(bids ~= nil, "the chest that takes bids alone has its row")
    bids.Buy:Click()
    eq(S.mode, "buy", "it is looked up")
    W.RunUntil(function() return Unsure("Bid Only Chest") == nil end, 30)
    eq(Asking(), nil, "nothing is asked: there is none to buy out")
    check(W.printed[#W.printed]:find("Bid Only Chest", 1, true) ~= nil and W.printed[#W.printed]:find("no longer for sale", 1, true) ~= nil,
        "the chat says it is gone: " .. W.printed[#W.printed])
    W.RunUntil(function() return S.state == "idle" and UnsureCount() == 0 end, 120)
    eq(Row("Bid Only Chest"), nil, "its row is gone")
    eq(OfferCount(), 6, "and the price checks went on to their end")
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
            if said and said:find("Checking prices", 1, true) then return said end
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
    -- What it costs in the end is there too, though the list is by buyout: "Net cost" is off.
    eq(ns.db.net and true or false, false, "the list is by buyout")
    eq(box.NetLabel:IsShown(), true, "a line for the net cost all the same"); eq(box.NetLabel:GetText(), "NET COST", "named")
    eq(box.Net:IsShown(), true, "with its coins"); eq(box.Net:GetAmount(), 4000 - good.sell, "the buyout less what a vendor pays")
    check(good.sell > 0, "a vendor pays something for it")
    eq(box:GetHeight(), 194, "the box at the height of its three lines")
    eq(box.Count:IsShown(), false, "nothing to count"); eq(box.Stock:IsShown(), false, "nor a stock")
    eq(box.Buy.Label:GetText(), "BUY", "its button says what it does")
    check(table.concat(UISpecialFrames, " "):find(box:GetName(), 1, true) ~= nil, "Escape closes it")
    -- The item in the box has the tooltip its row in the list has: the item's own, and under
    -- it the addon's lines, written by the tab as a row's are and so only once.
    box.Item:GetScript("OnEnter")(box.Item)
    eq(GameTooltip._link, good.link, "the item's tooltip over its name")
    eq(GameTooltip._owner, box.Item, "hung from the item in the box")
    local gains = 0
    for _, line in ipairs(GameTooltip._lines) do
        if line.text == "Arms" then
            gains = gains + 1
            eq(line.right, "+80%", "how much better it is on the profile, as its row says")
        end
    end
    eq(gains, 1, "the line of the profile, and once")
    eq(box.Item.upgradeScoutRow, true, "the tab writes these lines itself, as on a row")
    box.Item:GetScript("OnLeave")(box.Item)
    eq(GameTooltip:IsShown(), false, "and goes when the mouse leaves")
    -- The box may go from under the mouse (bought, or Escape): the tooltip goes with it.
    box.Item:GetScript("OnEnter")(box.Item)
    box.Item:GetScript("OnHide")(box.Item)
    eq(GameTooltip:IsShown(), false, "the tooltip of an item whose box has gone")

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

    -- The auction house turns the bid down, and the item is still there at its price (what the
    -- bid was turned down for, it does not say). The box stays, looks the item up once more
    -- and asks again. (What a refused bid leads to otherwise: scenarios.buy_refused.)
    W.RunUntil(function() return ns.Scanner.state == "idle" and W.AH.ready end, 30)
    local bids = #W.AH.calls.bids
    W.AH.failBid = true
    ns.Scanner.Buy(Offer("Great Chest"))
    W.RunUntil(Asking, 30)
    searches = W.AH.calls.search
    box.Buy:Click()
    eq(#W.AH.calls.bids, bids + 1, "the bid went out")
    W.RunUntil(function() return box.step == "check" end, 5)
    eq(box:IsShown(), true, "turned down: the box stays"); eq(box.Buy:IsEnabled(), false, "its button greyed while the item is looked up")
    W.RunUntil(function() return box.step == "confirm" end, 30)
    eq(W.AH.calls.search, searches + 1, "one more item search")
    eq(box:IsShown(), true, "and the box asks again"); eq(box.Buy:IsEnabled(), true, "with its button back")
    eq(box.WasLabel:IsShown(), false, "no old price: the price holds"); eq(box.TotalLabel:GetText(), "BUYOUT", "the usual line")
    eq(box.Total:GetAmount(), 90000, "at the price it had"); eq(box:GetHeight(), 194, "the box at its usual height")
    W.AH.failBid = nil
    check(Offer("Great Chest") ~= nil, "and nothing was bought")
    box.Cancel:Click()
    eq(#W.AH.calls.bids, bids + 1, "no second bid without a second press")

    -- Too expensive
    W.player.money = 10
    W.RunUntil(function() return ns.Scanner.state == "idle" and W.AH.ready end, 30)
    ns.Scanner.Buy(Offer("Great Chest"))
    eq(Asking(), nil, "no box when the player cannot pay")
    eq(ns.Scanner.state, "idle", "and no search")
end

-- The player pressed "Buy" in the box and the auction house turned the bid down: someone else
-- was faster. The player is not sent back to the list: the box looks the item up once more
-- and goes on from what it finds.
function scenarios.buy_refused()
    StandardWorld()
    W.AddAuction(200, 6000)             -- a third Good Chest, dearer than the two of the standard world
    LoadAddon()
    W.OpenAuctionHouse()
    ScanToEnd()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local function Idle() return ns.Scanner.state == "idle" and W.AH.ready end
    -- Someone else buys every copy of the item at this price.
    local function Sold(id, buyout)
        for i = #W.AH.auctions, 1, -1 do
            local a = W.AH.auctions[i]
            if a.id == id and a.buyout == buyout then table.remove(W.AH.auctions, i) end
        end
    end
    local function Said(words)
        local n = 0
        for _, line in ipairs(W.printed) do
            if line:find(words, 1, true) then n = n + 1 end
        end
        return n
    end

    -- The next copy costs more. The box shows the price the player agreed to and the price the
    -- item has now, and "Buy" buys at that one.
    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(Asking, 30)
    local box = Asking()
    eq(box.Total:GetAmount(), 4000, "the cheapest copy"); eq(box.WasLabel:IsShown(), false, "at the price the list has")
    Sold(200, 4000)
    W.AH.failBid = true
    box.Buy:Click()
    eq(#W.AH.calls.bids, 1, "the bid went out"); eq(W.AH.calls.bids[1].amount, 4000, "at that price")
    W.RunUntil(function() return box.step == "check" end, 5)
    eq(box:IsShown(), true, "turned down: the box stays")
    eq(box.Buy:IsEnabled(), false, "its button greyed while the item is looked up")
    eq(box.Total:GetAmount(), 4000, "the price the player agreed to still in it")
    W.AH.failBid = nil
    W.RunUntil(function() return box.step == "confirm" end, 30)
    eq(box:IsShown(), true, "the box asks again")
    eq(box.WasLabel:GetText(), "OLD PRICE", "the price the player agreed to"); eq(box.Was:GetAmount(), 4000, "in grey over the new one")
    eq(box.TotalLabel:GetText(), "NEW PRICE", "the price of the next copy"); eq(box.Total:GetAmount(), 5000, "which is what is paid")
    eq(box.Gain:GetText(), "+80%", "the gain as it was"); eq(box:GetHeight(), 226, "the box taller by the line")
    eq(box.Net:GetAmount(), ns.Results.Net(5000, box.offer.sell), "the net cost is of the new price")
    eq(box.Buy:IsEnabled(), true, "and the button is back")
    eq(Offer("Good Chest").buyout, 5000, "the list has the new price too")
    eq(Said("now costs"), 0, "not a word in the chat")

    -- That copy goes as well, while the box is up: the same again, from the price the box had.
    Sold(200, 5000)
    W.AH.failBid = true
    box.Buy:Click()
    eq(#W.AH.calls.bids, 2, "a second bid, from a second press"); eq(W.AH.calls.bids[2].amount, 5000, "at the price the box showed")
    W.RunUntil(function() return box.step == "check" end, 5)
    W.AH.failBid = nil
    W.RunUntil(function() return box.step == "confirm" end, 30)
    eq(box.Was:GetAmount(), 5000, "the old price is the one the player agreed to last"); eq(box.Total:GetAmount(), 6000, "the new one the third copy's")
    box.Buy:Click()
    eq(#W.AH.calls.bids, 3, "the third press"); eq(W.AH.calls.bids[3].amount, 6000, "buys at the price shown")
    W.RunUntil(function() return not box:IsShown() end, 5)
    eq(Said("Bought"), 1, "bought, the chat says"); eq(W.player.money, 100000 - 6000, "for 60 silver")
    W.RunUntil(Idle, 30)

    -- None is left. The box says so in place of its lines and stays until the player closes
    -- it: a box that went away by itself would look like a purchase.
    ns.Scanner.Buy(Offer("Helm"))
    W.RunUntil(Asking, 30)
    eq(box.Note:IsShown(), false, "no note in the usual question")
    Sold(211, Offer("Helm").buyout)
    W.AH.failBid = true
    box.Buy:Click()
    W.RunUntil(function() return box.step == "check" end, 5)
    W.AH.failBid = nil
    W.RunUntil(function() return box.step == "gone" end, 30)
    eq(box:IsShown(), true, "the box stays")
    eq(box.Note:IsShown(), true, "with a note"); eq(box.Note:GetText(), "No longer for sale", "that the item is gone")
    check(box.Name:GetText():find("Helm", 1, true) ~= nil, "under the item's name")
    eq(box.FirstLabel:IsShown(), false, "no gain"); eq(box.Gain:IsShown(), false, "nor its number")
    eq(box.TotalLabel:IsShown(), false, "no price"); eq(box.Total:IsShown(), false, "nor its coins")
    eq(box.WasLabel:IsShown(), false, "no old one"); eq(box.NetLabel:IsShown(), false, "no net cost")
    eq(box:GetHeight(), 162, "the box at its usual height")
    eq(box.Buy:IsEnabled(), false, "nothing to buy"); eq(box.Cancel:IsEnabled(), true, "the box can be closed")
    eq(Offer("Helm"), nil, "the item leaves the list")
    eq(Said("no longer for sale"), 0, "the box said it, not the chat")
    -- The list has no row for it now: the item in the box has the tooltip it has anywhere.
    box.Item:GetScript("OnEnter")(box.Item)
    eq(GameTooltip._link, box.link, "the item's own tooltip"); eq(box.Item.entry, nil, "with nothing of a row's")
    eq(box.Item.upgradeScoutRow, false, "nor written as a row's is")
    box.Item:GetScript("OnLeave")(box.Item)
    -- Gold coming in repaints the box: it stays as it is.
    W.Fire("PLAYER_MONEY")
    W.Run(0.3)
    eq(box.Note:IsShown(), true, "the note holds"); eq(box.Buy:IsEnabled(), false, "and so does the button")
    box.Cancel:Click()
    eq(box:IsShown(), false, "closed")

    -- The next question has its lines back.
    W.RunUntil(Idle, 30)
    ns.Scanner.Buy(Offer("Great Chest"))
    W.RunUntil(Asking, 30)
    eq(box.Note:IsShown(), false, "no note"); eq(box.TotalLabel:IsShown(), true, "the price is back")
    eq(box.TotalLabel:GetText(), "BUYOUT", "under its usual name"); eq(box.Total:GetAmount(), 90000, "the robe's")
    eq(box.Gain:IsShown(), true, "and the gain"); eq(box.Buy:IsEnabled(), true, "and the button")

    -- The player closes the box while the item is being looked up: nothing comes back up.
    local bids = #W.AH.calls.bids
    W.AH.failBid = true
    box.Buy:Click()
    W.RunUntil(function() return box.step == "check" end, 5)
    W.AH.failBid = nil
    box.Cancel:Click()
    W.RunUntil(Idle, 30)
    W.Run(0.5)
    eq(Asking(), nil, "no box after the player closed it")
    eq(#W.AH.calls.bids, bids + 1, "and nothing more was bid")

    -- Closed in the same way, and the item turns out to be gone: the chat says what the box
    -- could not.
    ns.Scanner.Buy(Offer("Great Chest"))
    W.RunUntil(Asking, 30)
    Sold(201, 90000)
    W.AH.failBid = true
    box.Buy:Click()
    W.RunUntil(function() return box.step == "check" end, 5)
    W.AH.failBid = nil
    box.Cancel:Click()
    W.RunUntil(Idle, 30)
    W.Run(0.5)
    eq(Asking(), nil, "no box")
    eq(Offer("Great Chest"), nil, "the item leaves the list"); eq(Said("no longer for sale"), 1, "and the chat says why")

    -- The auction house does not answer the lookup: the box goes, and the chat says so.
    ns.Scanner.Buy(Offer("New Ring"))
    W.RunUntil(Asking, 30)
    W.AH.failBid = true
    W.AH.dropSearches = 5
    box.Buy:Click()
    W.RunUntil(function() return box.step == "check" end, 5)
    W.AH.failBid = nil
    W.RunUntil(function() return not box:IsShown() end, 60)
    W.AH.dropSearches = nil
    eq(Said("did not answer"), 1, "the chat says the auction house did not answer")
    check(Offer("New Ring") ~= nil, "the item stays in the list")
end

-- A row of gear has two prices, and each has 94 to stand in. Whatever the sum, a price takes no
-- more: one too wide gives up its copper, and then its silver. The coins stand close, as in
-- the game's bags, and so do those of the game's own gold display while a tab of ours is up.
function scenarios.prices()
    local function Gear(id, name, slot, value, buyout)
        W.AddItem({ id = id, name = name, equipLoc = slot, subClassID = 3, value = value, level = 5 })
        W.AddAuction(id, buyout)
    end
    Gear(301, "Cheap Helm", "INVTYPE_HEAD", 12, 9999)               -- 99s 99c
    Gear(302, "Poor Helm", "INVTYPE_HEAD", 6, 20000)                -- weaker and dearer: no pick
    Gear(303, "Costly Legs", "INVTYPE_LEGS", 5, 999999)             -- 99g 99s 99c
    Gear(304, "Dear Boots", "INVTYPE_FEET", 5, 9999999)             -- 999g 99s 99c
    Gear(305, "Rich Gloves", "INVTYPE_HAND", 5, 99999999)           -- 9,999g 99s 99c
    Gear(306, "Royal Belt", "INVTYPE_WAIST", 5, 9999999999)         -- 999,999g 99s 99c
    Gear(307, "Crown Bracers", "INVTYPE_WRIST", 5, 99999999999)     -- 9,999,999g 99s 99c: all the gold there can be
    W.player.money = 99999999999
    LoadAddon()
    W.OpenAuctionHouse()
    local lib = LibStub("LibAHTab-1-0")
    local purse = AuctionHouseFrame.MoneyFrameBorder.MoneyFrame

    -- How a coin display is laid out: its parts from the left, each with what it is anchored
    -- to; and how wide the amount is, coins and all.
    local function Laid(money)
        local anchors = { [money] = "frame", [money.CopperDisplay] = "copper", [money.SilverDisplay] = "silver" }
        local out = {}
        for _, key in ipairs({ "GoldDisplay", "SilverDisplay", "CopperDisplay" }) do
            local part = money[key]
            if part:IsShown() then
                local at = part._points[1]
                out[#out + 1] = key:sub(1, 1) .. " " .. at.point .. " to " .. tostring(anchors[at.to]) .. " " .. at.toPoint .. " " .. at.x
            end
        end
        return table.concat(out, ", ")
    end
    local function Width(money)
        local width, parts = 0, 0
        for _, key in ipairs({ "GoldDisplay", "SilverDisplay", "CopperDisplay" }) do
            local part = money[key]
            if part:IsShown() then
                width, parts = width + part:GetWidth(), parts + 1
                eq(part._points[1].point, "RIGHT", "a part is anchored by its right edge")
            end
        end
        return width + 4 * (parts - 1)
    end
    -- Which parts of an amount are shown, and the numbers in them: "9,999g 99s".
    local function Reads(money)
        local out = {}
        for _, key in ipairs({ "GoldDisplay", "SilverDisplay", "CopperDisplay" }) do
            local part = money[key]
            if part:IsShown() then out[#out + 1] = part.Text:GetText() .. (W.colorblind and "" or key:sub(1, 1):lower()) end
        end
        return table.concat(out, " ")
    end

    -- The game's gold display at the foot of the window, as the game lays it out: silver and
    -- gold each in a slot of 36, a number two pixels before its coin.
    eq(Laid(purse), "G RIGHT to silver RIGHT -36, S RIGHT to frame RIGHT -36, C RIGHT to frame RIGHT 0", "the game's own layout before a tab of ours is up")
    eq(purse.SilverDisplay.Text._points[1].x, -14, "and its own air between a number and its coin")

    lib:SetSelected("UpgradeScout")
    SetView(false, false)
    ScanToEnd()
    W.Run(0.3)
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    local function Row(name)
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry and w.entry.offer.name == name then return w end
        end
    end
    local NAMES = { "Cheap Helm", "Poor Helm", "Costly Legs", "Dear Boots", "Rich Gloves", "Royal Belt", "Crown Bracers" }
    -- Every price of every row, in the room it has: it ends where its column ends, and begins
    -- clear of the column before it.
    local function AllFit(label)
        for _, name in ipairs(NAMES) do
            local row = Row(name)
            check(row ~= nil, name .. " is listed")
            local gain, buyout, net = row.Upgrade._points[1].x, row.Price._points[1].x, row.Net._points[1].x
            check(Width(row.Price) <= 94, label .. ": the buyout of " .. name .. " in its room: " .. Width(row.Price))
            check(Width(row.Net) <= 94, label .. ": the net cost of " .. name .. " in its room: " .. Width(row.Net))
            check(buyout - Width(row.Price) >= gain + 8, label .. ": the buyout of " .. name .. " clear of the gain")
            check(net - Width(row.Net) >= buyout + 8, label .. ": the net cost of " .. name .. " clear of the buyout")
        end
    end
    AllFit("coins")

    -- What fits is shown in full. What does not gives up its copper, and then its silver.
    eq(Reads(Row("Cheap Helm").Price), "99s 99c", "silver and copper"); eq(Width(Row("Cheap Helm").Price), 54, "two parts of 25 and the step between them")
    eq(Reads(Row("Cheap Helm").Net), "98s 99c", "its net cost: a silver less")
    eq(Reads(Row("Costly Legs").Price), "99g 99s 99c", "tens of gold: to the copper"); eq(Width(Row("Costly Legs").Price), 83, "three parts")
    eq(Reads(Row("Dear Boots").Price), "999g 99s 99c", "hundreds of gold: to the copper still"); eq(Width(Row("Dear Boots").Price), 89, "in 89 of the 94")
    eq(Reads(Row("Dear Boots").Net), "999g 98s 99c", "and so the net cost")
    eq(Reads(Row("Rich Gloves").Price), "9,999g 99s", "thousands of gold: no copper"); eq(Width(Row("Rich Gloves").Price), 72, "which would have made it 101")
    eq(Reads(Row("Rich Gloves").Net), "9,999g 98s", "nor in the net cost")
    eq(Reads(Row("Royal Belt").Price), "999,999g 99s", "hundreds of thousands: gold and silver"); eq(Width(Row("Royal Belt").Price), 84, "in their room")
    eq(Reads(Row("Crown Bracers").Price), "9,999,999g", "all the gold there can be: gold alone"); eq(Width(Row("Crown Bracers").Price), 67, "with room to spare")
    eq(Reads(Row("Crown Bracers").Net), "9,999,999g", "and its net cost")
    -- A cheaper item in the frame of a dear one has its coins back.
    eq(Row("Cheap Helm").Price.CopperDisplay:IsShown(), true, "copper where it fits"); eq(Row("Cheap Helm").Price.SilverDisplay:IsShown(), true, "and silver")

    -- The coins stand close: a part a small step after the one before it, a number a pixel
    -- before its coin.
    local legs = Row("Costly Legs")
    eq(Laid(legs.Price), "G RIGHT to silver LEFT -4, S RIGHT to copper LEFT -4, C RIGHT to frame RIGHT 0", "the three parts of a buyout")
    eq(Laid(legs.Net), "G RIGHT to silver LEFT -4, S RIGHT to copper LEFT -4, C RIGHT to frame RIGHT 0", "and of a net cost")
    eq(legs.Price.GoldDisplay.Text._points[1].x, -13, "the number before its coin"); eq(legs.Price.GoldDisplay:GetWidth(), 2 * 6 + 13, "the part as wide as the two")

    -- The name has the room up to the pick. A row without a pick has nothing there: its
    -- name may run on to where the gain begins.
    local cheap, poor = Row("Cheap Helm"), Row("Poor Helm")
    eq(cheap.Pick:IsShown(), true, "the better helm has a pick"); eq(poor.Pick:IsShown(), false, "the other has none")
    eq(cheap.Name:GetWidth(), 204, "a name before a pick"); eq(cheap.Name._points[1].x + 204 + 12, cheap.Pick._points[1].x, "ends a step before it")
    eq(poor.Name:GetWidth(), 356, "a name with no pick after it runs on")
    eq(poor.Name._points[1].x + 356 + 8, poor.Upgrade._points[1].x - 72, "to a step before the meter of the gain")

    -- The box that asks before a purchase has the price in full, whatever the row had room for.
    ns.Scanner.Buy(Offer("Rich Gloves"))
    W.RunUntil(Asking, 30)
    local ask = Asking()
    eq(Reads(ask.Total), "9,999g 99s 99c", "the buyout to the copper"); eq(Reads(ask.Net), "9,999g 98s 99c", "and the net cost")
    eq(Laid(ask.Total), "G RIGHT to silver LEFT -4, S RIGHT to copper LEFT -4, C RIGHT to frame RIGHT 0", "its coins as close as a row's")
    ask.Cancel:Click()

    -- A player who has letters in place of the coins: the numbers are wider by a letter and
    -- have no coin after them. The prices keep to their room all the same.
    W.colorblind = true
    ns.UI.Refresh()
    AllFit("letters")
    eq(Reads(Row("Costly Legs").Price), "99g 99s 99c", "tens of gold in letters")
    eq(Row("Costly Legs").Price.GoldDisplay.Text._points[1].x, 0, "a number with no coin ends where its part does")
    eq(Reads(Row("Crown Bracers").Price), "9,999,999g 99s", "and here the silver fits: there are no coins to make room for")
    W.colorblind = nil
    ns.UI.Refresh()
    AllFit("coins again")
    eq(Reads(Row("Crown Bracers").Price), "9,999,999g", "back to gold alone")

    -- The game's gold display, while a tab of ours is up: its coins as close as ours.
    eq(Laid(purse), "G RIGHT to silver LEFT -4, S RIGHT to copper LEFT -4, C RIGHT to frame RIGHT 0", "the gold display on our tab")
    eq(purse.SilverDisplay.Text._points[1].x, -13, "a number a pixel before its coin there too")
    -- The game writes the amount again whenever the gold changes, in its own layout.
    W.player.money = 1234567
    W.Fire("PLAYER_MONEY")
    eq(purse:GetAmount(), 1234567, "the game wrote the new amount")
    eq(Laid(purse), "G RIGHT to silver LEFT -4, S RIGHT to copper LEFT -4, C RIGHT to frame RIGHT 0", "and its coins stand close again")
    -- The Consumables tab is ours as well.
    lib:SetSelected("UpgradeScoutSupplies")
    eq(Laid(purse), "G RIGHT to silver LEFT -4, S RIGHT to copper LEFT -4, C RIGHT to frame RIGHT 0", "the same on the Consumables tab")
    -- On a tab of the game's the display is the game's again.
    AuctionHouseFrame:SetDisplayMode({ "buy" })
    eq(UpgradeScoutFrame:IsShown(), false, "the game's Buy tab is up")
    eq(Laid(purse), "G RIGHT to silver RIGHT -36, S RIGHT to frame RIGHT -36, C RIGHT to frame RIGHT 0", "the game's layout is back")
    eq(purse.SilverDisplay.Text._points[1].x, -14, "with its air"); eq(purse:GetAmount(), 1234567, "and the same amount")
    W.player.money = 7654321
    W.Fire("PLAYER_MONEY")
    eq(Laid(purse), "G RIGHT to silver RIGHT -36, S RIGHT to frame RIGHT -36, C RIGHT to frame RIGHT 0", "left alone while the game's tab is up")
    lib:SetSelected("UpgradeScout")
    eq(Laid(purse), "G RIGHT to silver LEFT -4, S RIGHT to copper LEFT -4, C RIGHT to frame RIGHT 0", "and close again on ours")
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
    -- How far below the top of the box a line stands.
    local function Y(part)
        for _, point in ipairs(part._points) do
            if point.point == "LEFT" or point.point == "RIGHT" then return point.y end
        end
    end
    -- How many lines the chat has about a price that changed.
    local function Told()
        local n = 0
        for _, line in ipairs(W.printed) do
            if line:find("now costs", 1, true) then n = n + 1 end
        end
        return n
    end
    local function Idle() return ns.Scanner.state == "idle" and W.AH.ready end

    -- The price changed, and the player is not looking at the list: nothing pops up, and the
    -- chat says what happened.
    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(Asking(), nil, "no question away from the tab")
    eq(Offer("Good Chest").buyout, 5000, "list shows the new price")
    eq(Told(), 1, "the chat says the price changed")
    check(W.printed[#W.printed]:find("now costs 50s (was 40s)", 1, true) ~= nil, "the new price and the old: " .. W.printed[#W.printed])

    W.RunUntil(Idle, 5)
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ns.Scanner.Buy(Offer("Helm"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    eq(Asking(), nil, "no box for an item that is gone")
    eq(Offer("Helm"), nil, "and it leaves the list")
    check(W.printed[#W.printed]:find("no longer for sale", 1, true) ~= nil, "says it is gone")

    -- The price changed, and the player is looking: the box comes up as for any purchase, with
    -- the price the list had over the one the item has now. Here someone put a cheaper copy up.
    local cheaper = W.AddAuction(200, 4500)
    W.RunUntil(Idle, 5)
    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 30)
    local box = Asking()
    check(box ~= nil, "a box when the price changed")
    eq(Told(), 1, "and not a word in the chat")
    eq(box.offer.buyout, 4500, "about the item at its new price"); eq(Offer("Good Chest").buyout, 4500, "which the list shows too")
    eq(box.Gain:GetText(), "+80%", "the gain, as ever")
    eq(box.WasLabel:IsShown(), true, "a line for the old price"); eq(box.WasLabel:GetText(), "OLD PRICE", "named")
    eq(box.Was:IsShown(), true, "with its coins"); eq(box.Was:GetAmount(), 5000, "what the list had")
    eq(box.Was._font, PriceFontGray, "in grey: it is not the price any more")
    eq(box.TotalLabel:GetText(), "NEW PRICE", "under it the new one"); eq(box.Total:GetAmount(), 4500, "which is what is paid")
    eq(box.Total._font, PriceFontWhite, "in white: the player can pay")
    eq(Y(box.WasLabel), -102, "the old price on the second line"); eq(Y(box.Was), -102, "coins and all")
    eq(Y(box.TotalLabel), -134, "the new one on the third"); eq(Y(box.Total), -134, "coins and all")
    eq(box.NetLabel:IsShown(), true, "under them the net cost"); eq(box.Net:GetAmount(), ns.Results.Net(4500, box.offer.sell), "of the new price")
    eq(Y(box.NetLabel), -166, "on the fourth line"); eq(Y(box.Net), -166, "coins and all")
    eq(box:GetHeight(), 226, "the box is taller by the line")
    eq(box.Buy.Label:GetText(), "BUY", "the button is the usual one"); eq(box.Buy:IsEnabled(), true, "and ready")
    -- The tooltip of the item in the box has the notes of its row, about the price as the box
    -- has it: a purse one silver short of the new price is told so.
    local purse = W.player.money
    W.player.money = 4400
    box.Item:GetScript("OnEnter")(box.Item)
    local noted = {}
    for _, line in ipairs(GameTooltip._lines) do noted[line.text] = true end
    eq(noted["You are 1s short"], true, "short of the price as the box has it, not as the list had it")
    box.Item:GetScript("OnLeave")(box.Item)
    W.player.money = purse
    box.Cancel:Click()
    eq(#W.AH.calls.bids, 0, "nothing bought before the player agrees")

    -- The list has the new price now, so the next question is the usual one.
    W.RunUntil(Idle, 30)
    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(Asking, 30)
    eq(box.WasLabel:IsShown(), false, "no old price when the price holds"); eq(box.Was:IsShown(), false, "nor its coins")
    eq(box.TotalLabel:GetText(), "BUYOUT", "the buyout under its usual name"); eq(box.Total:GetAmount(), 4500, "as listed")
    eq(Y(box.TotalLabel), -102, "back on the second line"); eq(Y(box.Total), -102, "coins and all")
    eq(Y(box.NetLabel), -134, "the net cost on the third"); eq(Y(box.Net), -134, "coins and all")
    eq(box:GetHeight(), 194, "and the box at its usual height")
    box.Cancel:Click()

    -- The cheaper copy is sold meanwhile; "Buy" pays the price the box shows.
    for i = #W.AH.auctions, 1, -1 do
        if W.AH.auctions[i] == cheaper then table.remove(W.AH.auctions, i) end
    end
    W.RunUntil(Idle, 30)
    ns.Scanner.Buy(Offer("Good Chest"))
    W.RunUntil(Asking, 30)
    eq(box.Was:GetAmount(), 4500, "the old price"); eq(box.Total:GetAmount(), 5000, "the new one")
    eq(box.Net:GetAmount(), ns.Results.Net(5000, box.offer.sell), "the net cost of the new price")
    eq(box:GetHeight(), 226, "the box at the height of its four lines")
    box.Buy:Click()
    eq(#W.AH.calls.bids, 1, "bought"); eq(W.AH.calls.bids[1].amount, 5000, "at the new price")
    W.RunUntil(function() return not box:IsShown() end, 5)
    eq(Told(), 1, "the chat was told once, by the purchase away from the tab")

    -- The server never answers the lookup.
    W.RunUntil(Idle, 30)
    W.AH.dropSearches = 5
    ns.Scanner.Buy(Offer("Great Chest"))
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 60)
    eq(Asking(), nil, "no box without an answer")
    W.AH.dropSearches = nil

    -- The new price is more than the player has: the box says so in red, and there is nothing
    -- to press but "Cancel".
    for _, a in ipairs(W.AH.auctions) do
        if a.id == 201 then a.buyout = 99000 end
    end
    W.RunUntil(Idle, 30)
    check(W.player.money >= 90000 and W.player.money < 99000, "enough for the old price only")
    ns.Scanner.Buy(Offer("Great Chest"))
    W.RunUntil(Asking, 30)
    eq(box.Was:GetAmount(), 90000, "the old price"); eq(box.Total:GetAmount(), 99000, "the new one")
    eq(box.Total._font, PriceFontRed, "in red: out of reach"); eq(box.Buy:IsEnabled(), false, "and cannot be paid")
    box.Cancel:Click()
    eq(#W.AH.calls.bids, 1, "nothing more was bought")
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
    eq(list.Titles[3]:GetText(), "UPGRADE", "third"); eq(list.Titles[4]:GetText(), "BUYOUT", "what is paid")
    -- Gear has five columns, the last of them what the item costs in the end. What a point
    -- of the gain costs is not shown: not in a column of its own, nor anywhere else on the tab.
    eq(list.Titles[5]:IsShown(), true, "a title after the buyout"); eq(list.Titles[5]:GetText(), "NET COST", "the net cost")
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
    -- After the buyout, what the item costs in the end: always, and in grey while the best
    -- value is judged by the buyout.
    eq(rows[2].Net._template, "MoneyDisplayFrameTemplate", "the net cost is a coin display too"); eq(rows[2].Net:IsShown(), true, "in view")
    eq(rows[2].Net:GetAmount(), 2500 - Offer("Helm").sell, "the buyout less what a vendor pays"); check(Offer("Helm").sell > 0, "which is something")
    eq(rows[2].Net._font, PriceFontGray, "in grey: the list goes by the buyout")
    eq(rows[2].PerPoint, nil, "two prices on a row, and neither is per point")
    local coins = 0
    for _, w in ipairs(Made("MoneyDisplayFrameTemplate")) do
        if w:GetParent() == rows[2] then coins = coins + 1 end
    end
    eq(coins, 2, "and no other coin display on it")
    -- The coins of a price stand close together: each part of it a small step to the left of
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
    eq(Laid(rows[2].Price), "S25 RIGHT to copper LEFT -4, C0 RIGHT to frame RIGHT 0", "25 silver: the copper at the right edge, the silver close before it")
    -- And a number right before its coin, as in the game's bags: the game leaves more air.
    local silver = rows[2].Price.SilverDisplay
    eq(silver.Text._points[1].x, -13, "the number ends a pixel before the coin, which is 12 wide")
    eq(silver:GetWidth(), 2 * 6 + 13, "and the part is as wide as the two: two digits, the pixel and the coin")
    eq(rows[2].Buy:IsEnabled(), true, "can buy")

    -- The columns of gear. How far along a part is anchored: a row's part from the row's left
    -- edge, a title from that of the plate, which the rows lie INSET inside.
    local INSET = 8
    local function At(part)
        eq(#part._points, 1, "one anchor")
        return part._points[1].x
    end
    local helm = rows[2]
    eq(At(helm.Net), 684, "the net cost ends close before the Buy button, with no column between them")
    eq(At(list.Titles[5]) - INSET, At(helm.Net), "its title ends where the net costs do")
    eq(At(list.Titles[4]) - INSET, At(helm.Price), "the title of the buyout ends where the buyouts do")
    eq(At(list.Titles[3]) - INSET, At(helm.Upgrade), "the title of the gain ends where the gains do")
    eq(At(helm.Trough), At(helm.Upgrade), "and so does the meter under a gain")
    eq(At(list.Titles[2]) - INSET, At(helm.Pick), "the title of the pick begins where the picks do")
    check(At(helm.Pick) >= At(helm.Name) + helm.Name:GetWidth() + 8, "a pick begins clear of the longest name")
    check(At(helm.Upgrade) - 72 >= At(helm.Pick) + 140 + 8, "the meter of a gain begins clear of the longest pick")
    -- A price has 94 to stand in and never takes more (scenarios.prices): the two columns
    -- are that wide, with air between them and before them.
    eq(At(helm.Net) - At(helm.Price), 106, "the net cost a step after the buyout"); eq(At(helm.Price) - At(helm.Upgrade), 106, "the buyout a step after the gain")
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
    -- The name makes room for the label, down to the least a name is given (110). A label
    -- that asks for more than that leaves, as this one does, is cut short itself.
    eq(axe.Name:GetWidth() + 8 + axe.Hand:GetWidth(), nameWidth, "and its name makes room for it: the two share the room")
    eq(axe.Name:GetWidth(), 110, "the name at its least"); eq(axe.Hand:GetWidth(), nameWidth - 110 - 8, "the label in what is left")
    check(axe.Hand:GetWidth() < #"Two-Hand (game)" * 6, "which is less than its words take")
    eq(axe.Hand._points[1].x, axe.Name._points[1].x + nameWidth, "at the end of the name's room")
    -- The labels of a slot stand in one column: a weapon that is no pick has its label where
    -- one that is a pick does, and its name ends before the label. (The name of armor with no
    -- pick runs on: scenarios.prices.)
    do
        local element = axe:GetElementData()
        local _, draw = box._view:_Ask(element)
        local entry = element.data.entry
        local pick = entry.pick
        check(pick ~= nil and axe.Pick:IsShown(), "the axe is a pick of its slot")
        entry.pick = nil
        draw(axe, element)
        eq(axe.Pick:IsShown(), false, "the same row as one that is no pick")
        eq(At(axe.Hand), At(axe.Name) + nameWidth, "has its label in the same place")
        eq(axe.Name:GetWidth() + 8 + axe.Hand:GetWidth(), nameWidth, "and its name still ends before the label")
        entry.pick = pick
        draw(axe, element)
        eq(axe.Pick:IsShown(), true, "the axe as it was")
    end
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

    -- The filters: a field at the right end of the strip, one of the game's dropdowns, whose
    -- menu has a tick box for each of them. No tick box stands in the strip itself.
    local filters = frame.FilterField
    eq(filters._template, "WowStyle1DropdownTemplate", "the filters are in a dropdown of the game's")
    eq(filters:GetText(), "Filters", "which says what it is, whatever is ticked")
    eq(filters.menuMixin, ns.Widgets.MenuStyle, "its menu opens on our plate")
    eq(filters._anchor.point .. " to " .. filters._anchor.relativePoint, "TOPRIGHT to BOTTOMRIGHT",
        "and hangs from the field's right end: the field stands at the window's edge")
    eq(frame.AffordCheck, nil, "no filter's tick box in the strip"); eq(frame.TopCheck, nil, "not one")
    -- A warrior of level 10 wears mail, and plate from 40: the line that is its own names mail.
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top 5 per slot | Best armor type for the class | Upgrade at least | / | Value by net cost",
        "the lines of the menu, the one that is no filter under a rule")
    local checkbox, topBox = FilterBox("Only what I can afford"), FilterBox("Top 5 per slot")
    eq(topBox:GetChecked(), true, "top five on by default")
    eq(rows[3].Count:GetText(), "", "nothing cut, so no count in the header")
    eq(checkbox:GetChecked(), true, "afford filter on by default")
    -- A line of the menu is the game's, dressed as the tab's own tick boxes are.
    filters:Open()
    local ticked, unticked = filters.lines[filters:Find("Top 5 per slot")], filters.lines[filters:Find("Value by net cost")]
    eq(ticked.leftTexture1:GetAlpha(), 0, "the game's square is see-through")
    eq(Pictures(ticked, "Inset"), 9, "under our recess, cut in nine"); eq(Pictures(ticked, "RowGlow"), 1, "with the light of a row under the mouse")
    eq(Pictures(ticked, "Check"), 1, "our gold tick"); eq(ticked.Tick:IsShown(), true, "which shows on a line that is ticked")
    eq(Pictures(unticked, "Check"), 1, "a line that is not has one too"); eq(unticked.Tick:IsShown(), false, "out of sight")
    filters:Close()
    -- What is on is plain without a click: the names of those filters stand beside the field.
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5 per slot", "the filters that are on, by name")
    filters._tooltip(GameTooltip)
    eq(GameTooltip._lines[1].text, "Filters", "the field's tooltip is titled with its name")
    eq(GameTooltip._lines[2].text, "Only what I can afford", "and lists what is on, in full"); eq(GameTooltip._lines[3].text, "Top 5 per slot", "line by line")
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
    filters:Open()
    filters:Tick("Only what I can afford")
    eq(#W.sounds, sounds + 1, "the game sounds the click, once")
    eq(ns.db.affordableOnly, false, "setting saved")
    eq(filters._open, true, "the menu stays open for the next box")
    eq(filters.lines[1].Tick:IsShown(), false, "and the tick is gone from the line")
    filters:Close()
    eq(frame.FilterNames:GetText(), "Top 5 per slot", "the filter is named beside the field no more")
    -- The robe's price was not looked up while it was hidden; now it is.
    eq(ns.Scanner.mode, "more", "the list asks for the missing price")
    W.Run(0.2)
    check(Status():find("Checking prices", 1, true) ~= nil, "and says so")
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
    eq(Laid(rows[4].Price), "G9 RIGHT to silver LEFT -4, S0 RIGHT to copper LEFT -4, C0 RIGHT to frame RIGHT 0",
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
    check(about:find("Choose the profile for your spec.", 1, true) ~= nil, "the tooltip says which profile to take: " .. about)
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
    topBox:Tooltip()
    eq(GameTooltip._lines[1].text, "Top 5 per slot", "the filter's tooltip is titled with its label")
    check(GameTooltip._lines[2].text:find("Up to 5 options", 1, true) ~= nil, "and explains it")

    -- Unticked, everything is listed again.
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
    topBox:Click()
    eq(ns.db.topOnly, true, "top five ticked")
    W.Run(0.3)
    eq(box:GetScrollPercentage(), 0, "at the top")
    topBox:Click()
    eq(ns.db.topOnly, false, "and unticked")
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
    eq(bar.Summary:GetText(), "4 items, +45 points, 9g 40s, net cost 9g 36s", "what it comes to: what is paid, and what it costs in the end")
    local afford, top = FilterBox("Only what I can afford"), FilterBox("Top 5 per slot")
    eq(afford:IsEnabled(), false, "the price filter has no say in a set: its line of the menu is grey")
    eq(top:IsEnabled(), false, "and so is top five's")
    afford:Click()
    eq(ns.db.affordableOnly, true, "a grey line takes no click")
    eq(FilterBox("Value by net cost"):IsEnabled(), true, "the net cost keeps its say")
    eq(frame.FilterNames:GetText(), "", "neither is named beside the field while the list is a set")
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
    eq(bar.Summary:GetText(), "4 items, +28 points, 60s, net cost 56s", "what it comes to")
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
    eq(bar.Summary:GetText(), "3 items, +16 points, 35s, net cost 32s", "and comes to the rest of the sum")
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
    eq(afford:IsEnabled(), true, "the filters are back")
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5 per slot", "and named beside the field again")
    eq(bar.Summary:GetText(), "", "nothing summed")
    check(Listed():find("[CHEST] Great Chest Good Chest", 1, true) ~= nil, "the list as ever: " .. Listed())
    check(box:GetFrames()[1].Toggle:IsShown(), "its headings fold again")

    -- A scan with the box ticked looks up what the set needs from the start.
    bar.Check:SetChecked(true)
    bar.Check:Click()
    -- While the scan finds what there is, nothing is known of the set, and the strip does not
    -- say that the sum buys nothing: an empty set means that only once the scan has had its say.
    check(S.Start(), "scan starts")
    W.Run(0.1)
    eq(S.state, "browse", "the auction list is being read")
    eq(Listed(), "", "with nothing listed yet")
    eq(bar.Summary:GetText(), "", "and the strip does not call the sum too small")
    -- Once the items are known a set is drawn from the lowest prices of their rows, before
    -- any of them is looked up.
    W.RunUntil(function() return UnsureCount() > 0 end, 5)
    W.Run(0.1)
    check(S.state ~= "idle", "the scan is at work: " .. S.state)
    check(Listed() ~= "", "a set is listed at once: " .. Listed())
    check(bar.Summary:GetText() ~= "" and bar.Summary:GetText() ~= ns.L.PLAN_NONE, "and summed: " .. bar.Summary:GetText())
    W.RunUntil(function() return S.state == "idle" end, 600)
    W.Run(0.3)
    check(Offer("Plain Chest") ~= nil, "the plain chest is priced by the scan itself")
    eq(Listed(), "[CHEST] Great Chest [FINGER] New Ring [OFF HAND] Shield", "the set after a new scan: " .. Listed())
    eq(bar.Summary:GetText(), "3 items, +33 points, 9g 15s, net cost 9g 12s", "and the strip sums it")
    -- A scan that ends with nothing for the sum does say so.
    W.Type(bar.Gold, "0")
    W.Run(0.3)
    eq(bar.Summary:GetText(), "No upgrade fits this sum.", "no gold, no scan at work: the strip says so")

    -- The Consumables view has no strip.
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScoutSupplies")
    W.Run(0.3)
    eq(bar:IsShown(), false, "no strip over consumables")
    eq(afford:IsEnabled(), true, "and their price filter works")
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

-- The net cost on the Upgrades tab: a column of its own beside the buyout, always; and the
-- line "Value by net cost" of the Filters menu, which says which of the two the best value
-- is judged by.
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
    local list, filters = frame.List, frame.FilterField
    local net, afford, top = FilterBox("Value by net cost"), FilterBox("Only what I can afford"), FilterBox("Top 5 per slot")
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
    -- Ticks or unticks a box: one of the Filters menu (FilterBox), where a click is all there
    -- is, or the tab's own box of the best set, which is a tick box of the game's.
    local function Tick(tickBox, on)
        if tickBox.SetChecked then
            tickBox:SetChecked(on)
        else
            eq(tickBox:GetChecked(), not on, "the click changes the box")
        end
        tickBox:Click()
        Settle()
    end
    -- The lines of the tooltip that is up, by the words on their left.
    local function Lines()
        local out = {}
        for _, line in ipairs(GameTooltip._lines) do out[line.text] = line end
        return out
    end

    -- The box: the last line of the Filters menu, under a rule, off until it is ticked.
    eq(frame.NetCheck, nil, "no tick box of its own above the list")
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top 5 per slot | Best armor type for the class | Upgrade at least | / | Value by net cost",
        "the last line of the menu, under a rule: what the best value goes by, not a filter")
    eq(net:IsShown(), true, "in the menu of the Upgrades tab")
    eq(net:GetChecked(), false, "not ticked")
    eq(ns.db.net, nil, "off until the player says otherwise")
    net:Tooltip()
    eq(GameTooltip._lines[1].text, "Value by net cost", "its tooltip is titled with its label")
    check(GameTooltip._lines[2].text:find("The best value is judged by", 1, true) ~= nil, "says what the line is for")
    check(GameTooltip._lines[2].text:find("less what a vendor pays for it", 1, true) ~= nil, "and what a net cost is")
    check(GameTooltip._lines[2].text:find("Bought for 4 silver and sold for 3, it cost you 1.", 1, true) ~= nil, "with an example")
    check(GameTooltip._lines[2].text:find("Unticked, it is judged by the buyout.", 1, true) ~= nil, "and what it goes by otherwise")
    GameTooltip:Hide()
    -- Where the parts of the strip stand, in a window 800 wide: the Filters field ends 14 short
    -- of the right edge, the names of the filters that are on end 8 before it, and the profile
    -- field keeps clear of the room those names have.
    local function Right(part)
        eq(#part._points, 1, "one anchor"); eq(part._points[1].point, "RIGHT", "by its right edge")
        return part._points[1].x
    end
    eq(Right(filters), -14, "the Filters field ends at the right end of the bar")
    eq(filters._points[1].toPoint, "TOPRIGHT", "of the tab")
    eq(Right(frame.FilterNames), -8, "the names end a step before the field")
    eq(frame.FilterNames._points[1].to, filters, "to the left of it")
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5 per slot", "the two filters that are on from the start")
    local dropdown, scan = frame.ProfileDropdown, frame.ScanButton
    eq(frame.ProfileLabel:IsShown(), true, "the profile field keeps its caption: its menu has no other characters")
    check(dropdown:GetWidth() >= 110, "and a width that shows a profile's name (" .. dropdown:GetWidth() .. ")")
    local namesLeft = 800 - 14 - filters:GetWidth() - 8 - frame.FilterNames:GetStringWidth()
    check(72 + scan:GetWidth() + dropdown._points[1].x + dropdown:GetWidth() + 16 <= namesLeft,
        "and ends clear of the names beside the Filters field")

    -- By buyout, as ever: the picks go by it. A row has both prices all the same, the buyout
    -- in white and after it, in grey, what the item costs in the end.
    ScanToEnd()
    W.Run(0.3)
    eq(list.Titles[4]:GetText(), "BUYOUT", "the first price column"); eq(list.Titles[5]:GetText(), "NET COST", "and the second")
    local robe = Row("Great Chest")
    eq(robe.Price:GetAmount(), 90000, "the robe at its nine gold"); eq(robe.Pick.Text:GetText(), "Best upgrade", "the best upgrade")
    eq(robe.Net:GetAmount(), 2000, "which is 20 silver in the end: nine gold less the 8 gold 80 a vendor pays")
    eq(robe.Price._font, PriceFontWhite, "the buyout in white: the picks go by it"); eq(robe.Net._font, PriceFontGray, "the net cost in grey")
    eq(Row("Good Chest").Price:GetAmount(), 4000, "the good chest at its 40 silver"); eq(Row("Good Chest").Pick.Text:GetText(), "Best value", "the best value")
    eq(Row("Good Chest").Net:GetAmount(), 3000, "30 silver in the end")
    eq(Row("Slight Chest").Price:GetAmount(), 1800, "the slight chest under them"); eq(Row("Slight Chest").Net:GetAmount(), 1700, "with its own")
    eq(Row("Helm").Net:GetAmount(), 2500, "no vendor buys the helm: its whole buyout")
    eq(Row("New Ring").Net:GetAmount(), 0, "the ring is for sale below its vendor price: it costs nothing in the end")
    eq(Row("Big Axe").Net:GetAmount(), 2900, "the axe less its silver"); eq(Row("Shield").Net:GetAmount(), 600, "and the shield")
    robe:GetScript("OnEnter")(robe)
    eq(Lines().Buyout, nil, "a row's tooltip says nothing of the price: the row does"); eq(Lines()["Net cost"], nil, "nor of the net cost")
    robe:GetScript("OnLeave")(robe)

    -- Ticked: the picks go by what each item costs in the end. The numbers stay where they
    -- are, and change their ink: the net cost is the white one now.
    local searches = W.AH.calls.search
    local sounds = #W.sounds
    Tick(net, true)
    eq(#W.sounds, sounds + 1, "the box clicks")
    eq(ns.db.net, true, "the setting is kept"); eq(UpgradeScoutCharDB.net, true, "with the character's saved ones")
    eq(net:GetChecked(), true, "the tick shows")
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5 per slot", "not named among the filters that are on: the white column says it")
    eq(W.AH.calls.search, searches, "nothing to look up: every price here was known")
    eq(list.Titles[4]:GetText(), "BUYOUT", "the columns are headed as they were"); eq(list.Titles[5]:GetText(), "NET COST", "both of them")
    robe = Row("Great Chest")
    eq(robe.Price:GetAmount(), 90000, "the robe's buyout, where it was"); eq(robe.Net:GetAmount(), 2000, "and its net cost")
    eq(robe.Net._font, PriceFontWhite, "the net cost in white: the picks go by it"); eq(robe.Price._font, PriceFontGray, "the buyout in grey")
    eq(robe.Pick.Text:GetText(), "Best of both", "the strongest chest is the cheapest per point too: 20 silver for +20")
    eq(Row("Good Chest"), nil, "top five has no use for the good chest now: weaker, and 30 silver for +8")
    eq(Row("Slight Chest"), nil, "nor for the slight one: 17 silver for +4")
    eq(Heading("CHEST").Count:GetText(), "1 of 3", "the heading counts them")
    eq(Row("Helm").Price:GetAmount(), 2500, "the helm's buyout"); eq(Row("Helm").Net:GetAmount(), 2500, "and all of it again")
    eq(Row("Helm").Upgrade:GetText(), "New", "the gains are what they were")

    -- A row's tooltip says as little of the prices as before: both stand in the row.
    robe:GetScript("OnEnter")(robe)
    local tip = Lines()
    eq(tip.Buyout, nil, "no line for the buyout"); eq(tip["Net cost"], nil, "nor for the net cost")
    eq(tip.Arms.right, "+200%", "the gains on every profile, which stay")
    robe:GetScript("OnLeave")(robe)

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

    -- The best set for a budget is chosen by buyouts, as ever. Its rows have both prices as
    -- the list's do, and the strip says both sums, with the line ticked or not.
    local bar = frame.PlanBar
    Tick(bar.Check, true)
    eq(bar.Summary:GetText(), "4 items, +45 points, 9g 40s, net cost 51s", "the set for ten gold: what is paid, and what it costs in the end")
    eq(Row("Great Chest").Price:GetAmount(), 90000, "a row of the set: its buyout"); eq(Row("Great Chest").Net:GetAmount(), 2000, "and its net cost")
    eq(net:IsEnabled(), true, "the line keeps its say in a set"); eq(top:IsEnabled(), false, "where the filters have none")
    Tick(net, false)
    eq(bar.Summary:GetText(), "4 items, +45 points, 9g 40s, net cost 51s", "unticked: the same two sums")
    eq(Row("Great Chest").Price:GetAmount(), 90000, "row by row"); eq(Row("Great Chest").Net:GetAmount(), 2000, "the same two prices")
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
    eq(robe.Net:GetAmount(), 2000, "listed again, with its net cost"); eq(robe.Net._font, PriceFontWhite, "in white: the picks go by it")
    eq(robe.Price:GetAmount(), 90000, "and its buyout"); eq(robe.Price._font, PriceFontRed, "in red, not grey: it cannot be paid")
    eq(robe.Buy:IsEnabled(), false, "and it cannot be bought")
    robe:GetScript("OnEnter")(robe)
    check(Lines()["You are 4g short"] ~= nil, "the tooltip counts what is missing from the buyout")
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
    -- The Filters menu is in reach while the box is up. The line is in the box whether the
    -- list is priced by the net cost or not.
    net:Click()
    eq(ask.NetLabel:IsShown(), true, "unticked: the line stays"); eq(ask.Net:GetAmount(), 2000, "with its coins")
    eq(ask.TotalLabel:GetText(), "BUYOUT", "over it the buyout"); eq(ask.Total:GetAmount(), 90000, "as before")
    eq(ask:GetHeight(), 194, "and the box is as it was")
    net:Click()
    eq(ask.Net:IsShown(), true, "ticked: there as well")
    ask.Buy:Click()
    eq(#W.AH.calls.bids, 1, "bought"); eq(W.AH.calls.bids[1].amount, 90000, "for the buyout")
    W.RunUntil(function() return not ask:IsShown() end, 5)
    Settle()

    -- A consumable is used up: no net cost in the other view.
    tabs:SetSelected("UpgradeScoutSupplies")
    W.Run(0.3)
    eq(net:IsShown(), false, "no such line over consumables")
    eq(FilterMenu(), "Only what I can afford | Best for me | Everything I can use", "whose menu has their own filters, and no rule")
    eq(list.Titles[4]:GetText(), "EACH", "whose price column is the price of a piece")
    eq(list.Titles[5]:GetText(), "FOR SALE", "and whose last one counts the pieces")
    eq(Right(filters), -14, "the field stands where it stood")
    tabs:SetSelected("UpgradeScout")
    W.Run(0.3)
    eq(net:IsShown(), true, "back on the Upgrades tab"); eq(net:GetChecked(), true, "still ticked")
    eq(list.Titles[4]:GetText(), "BUYOUT", "and the two price columns as they were"); eq(list.Titles[5]:GetText(), "NET COST", "both")
    eq(Row("Shield").Net._font, PriceFontWhite, "the net cost still the white one")

    -- Ticking the line leaves the list where the player has it: a row or two come or go, and
    -- the ones in view are the ones being read. A filter starts the list from its top.
    Tick(top, false)
    box:SetScrollPercentage(0.5)
    Tick(net, false)
    eq(box:GetScrollPercentage(), 0.5, "unticked: the list stays where it was")
    Tick(net, true)
    eq(box:GetScrollPercentage(), 0.5, "ticked: the same")
    Tick(top, true)
    eq(box:GetScrollPercentage(), 0, "a filter: back to the top")

    -- An auction house that deals in whole silver shows no copper in a buyout. A net cost has
    -- copper all the same: a vendor pays to the copper.
    W.AH.copper = false
    ns.UI.Refresh()
    local shield = Row("Shield")
    eq(shield.Net:GetAmount(), 600, "the shield's net cost"); eq(shield.Net.CopperDisplay:IsShown(), true, "to the copper")
    eq(shield.Price:GetAmount(), 700, "its buyout"); eq(shield.Price.CopperDisplay:IsShown(), false, "in whole silver")
    Tick(net, false)
    shield = Row("Shield")
    eq(shield.Net.CopperDisplay:IsShown(), true, "unticked: the net cost to the copper still"); eq(shield.Price.CopperDisplay:IsShown(), false, "and the buyout in whole silver")
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

    -- The default view: what adds to the character, which is what has a score; the best of
    -- each kind, among what the character can pay for.
    local rows, summary = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 2/3] j*=15 l*=12", "what has a score, the higher first, and nothing else")
    eq(summary.items, 2, "rows counted"); eq(summary.groups, 1, "subcategories counted")
    eq(summary.scoreless, 11, "the rest is left out and counted: what restores, what the tables do not know, what is of no use")
    eq(summary.useless, 0, "under that count alone: not as of no use"); eq(summary.hidden, 0, "nor as what costs too much")
    eq(rows[1].group, "SUB2", "a heading is known by its subcategory")
    -- Every rank of a kind, with "Best for me" off.
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = false, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 3/3] j*=15 i=8 l*=12", "each kind from its best down")
    -- What has a score and costs too much is left out for its price, as before.
    rows, summary = P.Build(list, { money = 600, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 2/2] l*=12 i*=8", "the weaker Agility elixir stands for its kind")
    eq(summary.hidden, 1, "the stronger one costs too much"); eq(summary.scoreless, 11, "and what has no score is not counted with it")

    -- "Everything I can use", for a character without mana: the best of each kind that is of
    -- use, among what the character can pay for.
    rows, summary = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, all = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 3/4] j*=15 l*=12 m* [Potions 2/3] b* n* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "the heading with scores under it first; under a heading by score, the higher first, then what restores, health before health and mana, then what has neither")
    eq(summary.items, 8, "rows counted"); eq(summary.groups, 5, "subcategories counted")
    eq(summary.useless, 2, "mana for a character without it and Intellect on a scale without it are left out")
    eq(summary.hidden, 0, "and are not counted among what costs too much"); eq(summary.scoreless, 0, "nothing is left out for having no score")
    eq(rows[1].group, "SUB2", "the elixirs lead: theirs is the one heading with a score under it"); eq(rows[5].group, "SUB1", "and the potions follow, at the head of the rest")

    -- The same for a character with mana: the mana potion is of use, only too dear.
    _, summary = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, all = true, value = Value, mana = true })
    eq(summary.useless, 1, "with mana, only the Intellect elixir is of no use"); eq(summary.hidden, 1, "and the mana potion costs too much")

    -- With no filter besides: kinds stay together; what is of no use goes last and is marked.
    rows, summary = P.Build(list, { money = 20000, affordableOnly = false, bestOnly = false, all = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 5/5] j*=15 i=8 l*=12 m* k*~ [Potions 4/4] b* a n* c*!~ [Food & Drink 2/2] e* d [Bandages 2/2] g* f [Other 1/1] h*",
        "every consumable, the best of its kind first and marked")
    eq(summary.items, 14, "all listed"); eq(summary.hidden, 0, "nothing left out"); eq(summary.useless, 0, "not even what is of no use")
    local why = {}
    for _, row in ipairs(rows) do
        if row.entry and row.entry.useless then why[row.entry.supply.id] = row.entry.why end
    end
    eq(why.c, "MANA", "the mana potion says why it is of no use"); eq(why.k, "WEIGHT", "and so does the elixir")

    -- What has a score stands at the top of its heading, above what only restores: a potion
    -- that adds Strength, among the healing potions.
    list.r = Make("r", 1, "Increases Strength by 4 for 2 min.", 5, 80, 3, { Strength = 4 })
    rows = P.Build(list, { money = 20000, affordableOnly = false, bestOnly = false, all = true, value = Value, mana = false })
    eq(Text(rows), "[Potions 5/5] r*=6 b* a n* c*!~ [Elixirs 5/5] j*=15 i=8 l*=12 m* k*~ [Food & Drink 2/2] e* d [Bandages 2/2] g* f [Other 1/1] h*",
        "the potion with a score first, then the ones that restore, then the one of no use; and the potions, with a score among them now, lead the list as the tab has them")
    list.r = nil

    -- Other weights turn the elixirs around without another scan.
    weights = { Intellect = 1 }
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, all = true, value = Value, mana = true })
    eq(Text(rows), "[Elixirs 2/2] k*=25 m* [Potions 2/3] b* n* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "on weights for Intellect its elixir is the one worth having")
    weights = { Agility = 1, Strength = 1.5 }

    -- Without a way to score, nothing has a score and nothing is left out, asked for or not:
    -- there is no telling what adds to the character. Kinds keep an order all the same: what
    -- restores, then the rest from the highest level down. And the headings stand as the tab
    -- has them: none has a score under it to come first for.
    rows, summary = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, mana = true })
    eq(Text(rows), "[Potions 2/3] b* n* [Elixirs 4/5] k* j* l* m* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "no scores without a way to score, and no meter to order by: the level decides")
    eq(summary.useless, 0, "what cannot be scored is not called useless"); eq(summary.scoreless, 0, "nor left out for having no score")

    -- A new rank the tables do not know yet: the kind goes by level, as before there were scores.
    list.o = Make("o", 2, "Increases Agility by 35 for 1 hr.", 29, 900, 1)
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, all = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 3/5] l*=12 o* m* [Potions 2/3] b* n* [Food & Drink 1/2] e* [Bandages 1/2] g* [Other 1/1] h*",
        "the unknown stronger elixir stands for its kind, without a score")
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 2/3] j*=15 l*=12", "and is not in the list of what has one, where its kind goes by the ranks that do")
    list.o = nil

    -- Food that restores health and adds a stat without a weight is still food.
    list.p = Make("p", 5, "Restores 874 health over 27 sec. Also increases your Intellect by 5.", 25, 100, 5)
    list.p.stats, list.p.restores = { Intellect = 5 }, "H"
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, all = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 3/4] j*=15 l*=12 m* [Potions 2/3] b* n* [Food & Drink 2/3] e* p* [Bandages 1/2] g* [Other 1/1] h*",
        "it is listed for what it restores")
    -- And all such food is one kind, whatever the bonuses: the one for the higher level stands for it.
    list.q = Make("q", 5, "Restores 1392 health over 30 sec. Also increases your Spirit by 8.", 35, 150, 5)
    list.q.stats, list.q.restores = { Spirit = 8 }, "H"
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, all = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 3/4] j*=15 l*=12 m* [Potions 2/3] b* n* [Food & Drink 2/4] q* e* [Bandages 1/2] g* [Other 1/1] h*",
        "one row for food with a bonus of no use, not one for every bonus")
    -- With a weight for one of the bonuses, that food is scored and stands apart.
    weights = { Agility = 1, Strength = 1.5, Spirit = 0.5 }
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, all = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 3/4] j*=15 l*=12 m* [Food & Drink 3/4] q*=4 e* p* [Potions 2/3] b* n* [Bandages 1/2] g* [Other 1/1] h*",
        "food with a bonus of use has its score, and stands above the food that only restores; its heading moves up to the elixirs', above the potions")
    rows = P.Build(list, { money = 20000, affordableOnly = true, bestOnly = true, value = Value, mana = false })
    eq(Text(rows), "[Elixirs 2/3] j*=15 l*=12 [Food & Drink 1/1] q*=4", "and is the one meal in the list of what adds to the character")
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

    -- The rows the tab would show a character without mana, on the profile "S1": what has a score.
    local rows, summary = ns.Supplies.Build(S.supplies, SupplyOpts("S1", { affordableOnly = true, bestOnly = true, mana = false }))
    eq(#rows, 4, "one heading and three rows"); eq(rows[1].title, "Elixirs", "the elixirs alone")
    eq(rows[2].entry.supply.name, "Elixir of Agility", "the one that scores highest"); eq(rows[4].entry.supply.name, "Silent Elixir", "down to the last of them")
    eq(summary.scoreless, 11, "the rest has no score on this profile"); eq(summary.hidden, 1, "and the best Strength elixir costs too much")
    -- And with everything the character can use.
    rows, summary = ns.Supplies.Build(S.supplies, SupplyOpts("S1", { affordableOnly = true, bestOnly = true, all = true, mana = false }))
    eq(rows[1].title, "Elixirs", "the elixirs first: they have scores")
    eq(rows[2].entry.supply.name, "Elixir of Agility", "the elixir that scores highest"); eq(rows[2].entry.value, 15, "with its score")
    eq(rows[3].entry.supply.name, "Elixir of Ogre Strength", "then the next kind"); eq(rows[3].entry.value, 12, "by its score")
    eq(rows[4].entry.supply.name, "Silent Elixir", "an item without its effect line is scored all the same")
    eq(rows[5].title, "Potions", "nothing for the Intellect elixir on this profile: the potions come next, the first of what has no score")
    eq(rows[6].entry.supply.name, "Greater Healing Potion", "the best healing potion")
    eq(rows[7].title, "Food & Drink", "the mana potion is of no use, so food comes next")
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
    -- A click on a tick box of the Filters menu, which ticks or unticks it.
    local function Tick(tickBox, checked)
        eq(tickBox:GetChecked(), not checked, "the click changes the box")
        tickBox:Click()
        W.Run(0.3)
    end
    local topBox, bestBox, affordBox = FilterBox("Top 5 per slot"), FilterBox("Best for me"), FilterBox("Only what I can afford")
    local allBox = FilterBox("Everything I can use")

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
    eq(list.Titles[5]:IsShown(), true, "five columns"); eq(list.Titles[5]:GetText(), "NET COST", "after the buyout, the net cost")
    local gearPrice, gearLast = At(list.Titles[4]), At(list.Titles[5])
    eq(topBox:IsShown(), true, "its own second filter in the Filters menu"); eq(bestBox:IsShown(), false, "not the other view's")
    eq(frame.ProfileDropdown:IsShown(), true, "and the profile")

    -- The Consumables tab shows the same frame, made over.
    lib:SetSelected("UpgradeScoutSupplies")
    eq(frame:IsShown(), true, "the same frame is up")
    eq(list.Titles[2]:GetText(), "EFFECT", "the second column is what the item does")
    eq(list.Titles[3]:IsShown(), true, "the third column stays"); eq(list.Titles[3]:GetText(), "SCORE", "for what the item is worth")
    eq(list.Titles[4]:GetText(), "EACH", "the price is that of one piece")
    eq(list.Titles[5]:IsShown(), true, "a fifth column here too"); eq(list.Titles[5]:GetText(), "FOR SALE", "how many there are")
    check(At(list.Titles[4]) < gearLast, "the price stands before it")
    eq(At(list.Titles[5]), gearLast, "which ends where the net cost of gear does: close before the Buy button")
    eq(frame.ProfileDropdown:IsShown(), true, "the profile stays: consumables are scored on it")
    eq(frame.FilterField:IsShown(), true, "the Filters field stays, with the menu of this view")
    eq(topBox:IsShown(), false, "the top-N filter is gone"); eq(bestBox:IsShown(), true, "another one is in its place")
    eq(FilterMenu(), "Only what I can afford | Best for me | Everything I can use", "after the price filter, which is shared: two lines of its own, and no rule")
    eq(bestBox:GetChecked(), true, "ticked by default")
    bestBox:Tooltip()
    eq(GameTooltip._lines[1].text, "Best for me", "its tooltip is titled with its label"); eq(GameTooltip._lines[2].text, ns.L.SUP_BEST_TIP, "and says what it does")
    GameTooltip:Hide()
    eq(allBox:GetChecked(), false, "the last one is not ticked: the list is of what has a score")
    allBox:Tooltip()
    eq(GameTooltip._lines[1].text, "Everything I can use", "titled with its label too"); eq(GameTooltip._lines[2].text, ns.L.SUP_ALL_TIP, "and saying what it adds")
    GameTooltip:Hide()
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Best for me", "both are on, and named beside the field")
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
    -- Left to itself the list is of what adds to the character: what has a score.
    eq(Listed(), "[ELIXIRS 2 of 3], Elixir of Agility, Elixir of Ogre Strength",
        "the best of each kind that has a score and that the character can pay for, and no potion, food or bandage")
    check(Said("2 consumables in 1 categories. 1 more cost more than you have.") ~= nil, "the status line counts them: " .. tostring(Said("consumables in")))
    -- "Everything I can use" brings the rest.
    Tick(allBox, true)
    eq(ns.db.allUsable, true, "the setting is saved")
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Best for me \194\183 Everything", "and the box is named beside the field, in a word")
    eq(Listed(), "[ELIXIRS 2 of 3], Elixir of Agility, Elixir of Ogre Strength, [POTIONS 1 of 3], Greater Healing Potion, "
        .. "[FOOD & DRINK 1 of 3], Stormwind Brie, [BANDAGES 1 of 2], Heavy Wool Bandage, [OTHER], Rough Dynamite",
        "the best of each kind that is of use and that the character can pay for, by subcategory: the one with scores first")
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
    check(table.concat(seen, "\n"):find("18 for sale, from 8s each", 1, true) ~= nil, "the tooltip says how much there is: " .. table.concat(seen, " | "))
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
    -- These lines are notes on a row: the box of the score's lines (the welcome window)
    -- leaves them be, and with the box of the notes unticked the tooltip is the item's own
    -- and no more.
    UpgradeScoutDB.rowTooltip = false
    check(Tooltip(agility):find("Score of what it adds: +15", 1, true) ~= nil, "the score's lines switched off for the tabs: a consumable keeps its own")
    UpgradeScoutDB.rowTooltip = nil
    UpgradeScoutDB.rowNotes = false
    local bare = Tooltip(agility)
    check(bare:find("Upgrade Scout", 1, true) == nil and bare:find("Score of what it adds", 1, true) == nil and bare:find("for sale", 1, true) == nil,
        "the notes switched off, a consumable's tooltip has nothing of ours: " .. bare)
    check(bare ~= "", "but it is still the item's own")
    UpgradeScoutDB.rowNotes = nil

    -- Every consumable instead of the best of each kind.
    Tick(bestBox, false)
    eq(ns.db.bestOnly, false, "the setting is saved")
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Everything", "and the filter is named beside the field no more")
    -- The list is now longer than the plate: it is read at its top and at its bottom.
    local top = Listed()
    scrollBox:SetScrollPercentage(1)
    local bottom = Listed()
    scrollBox:SetScrollPercentage(0)
    local first = "[ELIXIRS], Elixir of Agility, Elixir of Lesser Agility, Elixir of Ogre Strength, Elixir of Wisdom, "
        .. "[POTIONS], Greater Healing Potion, Healing Potion, Minor Healing Potion, "
        .. "[FOOD & DRINK], Stormwind Brie, Wild Hog Shank, Mutton Chop"
    local ending = "[BANDAGES], Heavy Wool Bandage, Wool Bandage, [OTHER], Rough Dynamite"
    eq(top:sub(1, #first), first, "each kind from its best down; of two equally strong the cheaper first; what is of no use last")
    eq(bottom:sub(-#ending), ending, "and so to the end of the list")
    local wisdom = Row("Elixir of Wisdom")
    eq(wisdom.Icon._grey, true, "what is of no use is grey"); eq(wisdom.Upgrade:IsShown(), false, "and has no score")
    check(Tooltip(wisdom):find("your profile gives no weight", 1, true) ~= nil, "its tooltip says why: " .. Tooltip(wisdom))
    eq(Row("Elixir of Lesser Agility").Upgrade:GetText(), "+8", "a weaker one of a kind has its own score")

    -- What costs too much comes back in red when the price filter is off.
    Tick(affordBox, false)
    eq(frame.FilterNames:GetText(), "Everything", "one box is left on")
    frame.FilterField._tooltip(GameTooltip)
    eq(GameTooltip._lines[2].text, "Everything I can use", "which the field's tooltip names in full")
    GameTooltip:Hide()
    local mana = Row("Mana Potion")
    check(mana ~= nil, "the mana potion is listed")
    eq(mana.Price._font, PriceFontRed, "its price in red"); eq(mana.Buy:IsEnabled(), false, "and it cannot be bought")
    check(Tooltip(mana):find("you have none", 1, true) ~= nil, "a character without mana is told so: " .. Tooltip(mana))
    eq(Row("Elixir of Giants").Upgrade:GetText(), "+37.5", "the elixir that costs too much has the best score")
    check(math.abs(Row("Elixir of Agility").Meter:GetWidth() - 71 * 15 / 37.5) < 0.01, "and the meters now measure against it")
    -- With no box ticked at all the list is every consumable that has a score.
    Tick(allBox, false)
    eq(ns.db.allUsable, false, "the setting is saved")
    eq(frame.FilterNames:GetText(), "", "no filter is on: nothing stands beside the field")
    frame.FilterField._tooltip(GameTooltip)
    eq(GameTooltip._lines[2].text, "No filter is on.", "and its tooltip says so")
    GameTooltip:Hide()
    eq(Listed(), "[ELIXIRS], Elixir of Giants, Elixir of Ogre Strength, Elixir of Agility, Elixir of Lesser Agility",
        "the kind with the highest score first, each from its best down; nothing without a score")
    Tick(allBox, true)
    Tick(affordBox, true)
    Tick(bestBox, true)

    -- A heading folds its subcategory away, as a slot's heading does.
    local heading = Rows()[1]
    heading.Toggle:Click()
    eq(ns.db.collapsed.SUB2, true, "elixirs folded")
    eq(Listed(), "[ELIXIRS 2 of 3], [POTIONS 1 of 3], Greater Healing Potion, "
        .. "[FOOD & DRINK 1 of 3], Stormwind Brie, [BANDAGES 1 of 2], Heavy Wool Bandage, [OTHER], Rough Dynamite", "its rows are gone, and it keeps its place")
    Rows()[1].Toggle:Click()
    eq(ns.db.collapsed.SUB2, nil, "and unfolded again")

    -- Another profile: the list is scored again as it stands. No scan, of either kind.
    local scannedAt = S.suppliesAt
    frame.ProfileDropdown:Pick(2)
    W.Run(0.3)
    eq(ns.Roster.Me().profile, "S2", "the choice is saved"); eq(S.state, "idle", "nothing is scanned"); eq(S.suppliesAt, scannedAt, "the list is the same scan's")
    eq(Listed(), "[ELIXIRS], Elixir of Wisdom, [POTIONS 1 of 3], Greater Healing Potion, "
        .. "[FOOD & DRINK 1 of 3], Stormwind Brie, [BANDAGES 1 of 2], Heavy Wool Bandage, [OTHER], Rough Dynamite",
        "on a profile for Intellect its elixir is the one of use")
    eq(Row("Elixir of Wisdom").Upgrade:GetText(), "+6", "with its score on that profile")
    check(Said("5 consumables in 5 categories.") ~= nil, "nothing of use costs too much now: " .. tostring(Said("consumables in")))
    -- A character with mana has a use for the mana potion, which costs too much.
    W.player.mana = 400
    ns.UI.Refresh()
    W.Run(0.3)
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
    eq(list.Titles[2]:GetText(), "PICK", "the Upgrades tab has its titles back"); eq(list.Titles[5]:GetText(), "NET COST", "all five of them")
    eq(At(list.Titles[4]), gearPrice, "each where it was"); eq(At(list.Titles[5]), gearLast, "the last one too")
    eq(frame.ProfileDropdown:IsShown(), true, "its profile"); eq(topBox:IsShown(), true, "and its filter")
    eq(Listed(), "", "and its own, empty list")
    eq(list.Intro:IsShown(), true, "with the emblem: gear was never scanned"); eq(list.Intro.Heading:GetText(), "GEAR UPGRADES FOR SALE", "under its own title")
    eq(ns.Scanner.state, "idle", "nothing was started behind the view")

    -- And back: the consumables are still there.
    lib:SetSelected("UpgradeScoutSupplies")
    W.Run(0.3)
    check(Row("Greater Healing Potion") ~= nil, "the Consumables tab still has its list")

    -- Nothing for sale has a score (here: the tables know of no stats), and the box is not
    -- ticked: the list is empty, and says which box lists the rest.
    for _, supply in pairs(S.supplies) do supply.stats = nil end
    Tick(allBox, false)
    eq(Listed(), "", "nothing has a score: nothing is listed")
    eq(frame.Status:GetText(), "Nothing for sale has a score on this profile. Tick \"Everything I can use\" in Filters to see the rest.", "the status line says where the rest is")
    eq(list.Hint:GetText(), frame.Status:GetText(), "and so does the middle of the empty plate")
    Tick(allBox, true)
    check(Row("Greater Healing Potion") ~= nil, "ticked, it lists them")
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
    -- The names of the filters that are on are kept their room beside the Filters field, which
    -- leaves none for that and the field's caption both, so the field stands without its caption.
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
    -- The game's own comparison is on (Shift is held, or the player has the game compare
    -- always): as the tooltip is filled in the game puts up what the warrior wears, and a
    -- second item beside it where it compares with two. Neither stays under a row for the
    -- druid.
    W.comparing = { W.Link(100), W.Link(200) }
    jerkin:GetScript("OnEnter")(jerkin)
    eq(ShoppingTooltip1:IsShown(), true, "the game comparing by itself: there is still one tooltip beside the row")
    eq(ShoppingTooltip1._lines[1].text, "Alt's Jerkin", "with the druid's chest, not the warrior's")
    eq(ShoppingTooltip2:IsShown(), false, "and the game's second item, which would lie under it, is taken down")
    jerkin:GetScript("OnLeave")(jerkin)
    local belt = Row("Hide Belt")
    check(belt ~= nil, "the belt is in the list")
    check(not (belt.entry.replaced and belt.entry.replaced[1]), "the druid has no belt on")
    belt:GetScript("OnEnter")(belt)
    eq(ShoppingTooltip1:IsShown(), false, "a slot the druid has nothing in: nothing beside the row, and not what the warrior wears")
    eq(ShoppingTooltip2:IsShown(), false, "in neither of the game's tooltips")
    belt:GetScript("OnLeave")(belt)
    W.comparing = nil
    -- With "Only my talent tree" ticked the row's tooltip has one line of ours: whose list
    -- it is and the profile it is made on, then the gain.
    UpgradeScoutDB.ownTree = true
    jerkin:GetScript("OnEnter")(jerkin)
    doubles = {}
    for _, line in ipairs(GameTooltip._lines) do
        if line.right then doubles[#doubles + 1] = line end
    end
    eq(#doubles, 1, "one line of ours with 'Only my talent tree' ticked")
    eq(doubles[1].text, "|TInterface\\AddOns\\UpgradeScout\\icon.tga:0|t " .. ALTY .. ": Balance", "the druid and the profile in use, after the addon's icon")
    eq(doubles[1].right, "+67%", "with the gain of the row"); eq(doubles[1].r, RAID_CLASS_COLORS.DRUID.r, "in the colour of the druid's class")
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.ownTree = nil
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

    -- Consumables for the druid: its level, its mana, its profession. (Everything it can use:
    -- a potion that restores has no score, and is not in the list otherwise.)
    ns.db.allUsable = true
    lib:SetSelected("UpgradeScoutSupplies")
    check(list.Hint:GetText():find(ALTY .. " can use", 1, true) ~= nil, "the other view is the druid's too: " .. list.Hint:GetText())
    eq(frame.ProfileLabel:IsShown(), false, "the strip is laid out as on the other tab: no caption here either")
    eq(dropdown:GetWidth(), 200, "and the field at its full width")
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
    eq(Ours(GameTooltip, 201), "Arms +200% | Protection ~ -100% | Has effects the score does not count",
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
    eq(Ours(GameTooltip, 212), "Arms -4% | Protection ~ +0 pts | Takes both hands", "the two-hander against sword and shield, 26 against 27")
end

-- The tooltip's block of the welcome window and its two questions. How our lines are written:
-- for every profile of the class, or one line for the profile in use. Where they show: on the
-- addon's tabs at the auction house, elsewhere in the game, both, or neither.
function scenarios.tooltip_settings()
    StandardWorld()
    W.player.money = 50000
    -- The two rings of the window's pictures.
    W.AddItem({ id = 16999, name = "Royal Seal", equipLoc = "INVTYPE_FINGER", quality = 3, level = 54 })
    W.AddItem({ id = 5000, name = "Coral Band", equipLoc = "INVTYPE_FINGER", level = 21 })
    -- On the second profile the two chests score 9 (for sale) and 12 (worn).
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    LoadAddon()
    W.Run(1)

    local ICON = "|TInterface\\AddOns\\UpgradeScout\\icon.tga:0|t "
    -- What the addon wrote in the tooltip that is up: from its first line on (the one with
    -- its icon, written "*" here), each as "left right", joined by " | "; nil when it wrote
    -- nothing.
    local function Ours(tooltip)
        local first
        for i, line in ipairs(tooltip._lines) do
            if line.text:find(ICON, 1, true) then
                eq(first, nil, "the addon's icon once only")
                first = i
            end
        end
        if not first then return nil end
        eq(tooltip._lines[first - 1].text, " ", "a blank line before our lines")
        local out = {}
        for i = first, #tooltip._lines do
            local line = tooltip._lines[i]
            out[#out + 1] = (line.text:gsub("|T.-|t ", "*", 1)) .. (line.right and " " .. line.right or "")
        end
        return table.concat(out, " | ")
    end
    -- The same for an item shown in a tooltip, as the bags or the chat show one.
    local function Item(tooltip, id)
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetHyperlink(W.Link(id))
        return Ours(tooltip)
    end
    local function Line(tooltip, text)
        for _, line in ipairs(tooltip._lines) do
            if line.text == text then return line end
        end
    end

    -- Until anything is chosen: every profile of the class under the addon's name.
    eq(ns.OwnTree(), false, "every tree to begin with")
    eq(Item(GameTooltip, 200), "*Upgrade Scout | Arms +80% | Protection ~ -25%", "a line for every profile, as before")

    -- The window: two cards side by side, and under them the tooltip's block.
    ns.Welcome.Show()
    local window = UpgradeScoutWelcome
    local block, tip = window.Tips, window.Tips.Picture.Tip
    local all, own, tabs, elsewhere = block.All, block.Own, block.Tabs, block.Elsewhere
    eq(#window.Pair, 2, "two cards: the auction house and the bags")
    near(window.Pair[1]:GetWidth() * 2 + 11, block:GetWidth(), "which together are as wide as the block under them")
    eq(block.Title:GetText(), "TOOLTIP SETTINGS", "the block's name, in capitals as a card's")
    check(block.Body:GetText():find("Point at any item", 1, true) ~= nil, "and its sentence")
    eq(all.Label:GetText(), "All specs", "how: a button for every tree"); eq(own.Label:GetText(), "Only my spec", "and one for the tree in use")
    eq(tabs.Label:GetText(), "Show on the addon's auction tabs", "where: a box for the addon's tabs")
    eq(elsewhere.Label:GetText(), "Show elsewhere: bags, loot, chat", "and one for the rest of the game")
    eq(elsewhere._points[1].x, tabs._points[1].x, "one box under the other: their words do not fit side by side")
    eq(tabs._points[1].y - elsewhere._points[1].y, 15 + 7, "lower by a box and the room between two")
    eq(all.Mark:IsShown(), true, "every tree is lit to begin with"); eq(own.Mark:IsShown(), false, "the other is dark")
    eq(tabs:GetChecked(), true, "both places ticked to begin with"); eq(elsewhere:GetChecked(), true, "the second as well")
    eq(tabs.Tick:IsShown(), true, "with their ticks"); eq(elsewhere.Tick:IsShown(), true, "both")
    eq(tip.Brand:IsShown(), true, "the block's picture: the addon's name over the lines")
    eq(tip.Lines[1].Title:GetText(), "Arms", "a line for each profile"); eq(tip.Lines[2].Title:IsShown(), true, "both of them")
    local tall, high = tip:GetHeight(), window:GetHeight()

    -- How: the tree in use alone.
    local told = 0
    ns.Listen("SETTING_CHANGED", function() told = told + 1 end)
    own:Click()
    eq(UpgradeScoutDB.ownTree, true, "chosen: written down for the account"); eq(ns.OwnTree(), true, "and in force at once")
    eq(own.Mark:IsShown(), true, "its button lights up"); eq(all.Mark:IsShown(), false, "the other goes dark")
    own:Click()
    eq(told, 1, "the answer in force clicked again: nothing changes")
    eq(tip.Brand:IsShown(), false, "the picture has no heading now")
    eq(tip.Lines[1].Title:GetText(), ICON .. "Arms", "but one line: the addon's icon and the profile in use")
    eq(tip.Lines[1].Gain:GetText(), "+31%", "with its gain"); eq(tip.Lines[1].Gain:IsShown(), true, "which shows")
    eq(tip.Lines[2].Title:IsShown(), false, "the other profile is gone"); eq(tip.Lines[2].Gain:IsShown(), false, "with its gain")
    check(tip:GetHeight() < tall, "and the tooltip in the picture is shorter")
    eq(window:GetHeight(), high, "the window stays as tall as it was")

    -- An item's tooltip anywhere in the game: one line, under a blank one.
    eq(Item(GameTooltip, 200), "*Arms +80%", "the chest in the bags: the profile in use and its gain")
    eq(Line(GameTooltip, ICON .. "Arms").r, RAID_CLASS_COLORS.WARRIOR.r, "the profile in the colour of the class")
    eq(Line(GameTooltip, ICON .. "Arms").rightR, GREEN_FONT_COLOR.r, "a gain in green")
    eq(Item(ItemRefTooltip, 200), "*Arms +80%", "the same for a link clicked in the chat")
    eq(Item(GameTooltip, 211), "*Arms +12 pts", "a helm for the empty head: in points")
    eq(Item(GameTooltip, 201), "*Arms +200% | Has effects the score does not count", "what a score leaves out is still said")
    eq(Item(GameTooltip, 100), nil, "nothing for the chest the character has on")
    eq(Item(GameTooltip, 214), nil, "nothing for a potion")

    -- Another tree chosen in the window: the line is that tree's.
    window.Trees[2]:Click()
    eq(Item(GameTooltip, 200), "*Protection ~ -25%", "the line follows the profile in use")
    eq(Line(GameTooltip, ICON .. "Protection ~").rightR, RED_FONT_COLOR.r, "a loss in red")
    eq(tip.Lines[2].Title:GetText(), ICON .. "Protection ~", "and so does the picture"); eq(tip.Lines[2].Gain:GetText(), "+36%", "with that profile's gain")
    eq(tip.Lines[1].Title:IsShown(), false, "the first profile's line is gone from it")
    window.Trees[1]:Click()

    -- The notes of the line in use stay under it.
    W.equipped[17] = W.Link(213)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    eq(Item(GameTooltip, 212), "*Arms -4% | Takes both hands", "the two-hander against sword and shield")
    W.equipped[17] = nil
    W.Fire("PLAYER_EQUIPMENT_CHANGED")

    -- Where: not in the rest of the game. An item's tooltip has nothing of ours; the picture
    -- stays, for the lines still show on the addon's tabs.
    elsewhere:SetChecked(false)
    elsewhere:Click()
    eq(UpgradeScoutDB.tooltip, false, "unticked: written down for the account"); eq(elsewhere.Tick:IsShown(), false, "the tick goes")
    eq(Item(GameTooltip, 200), nil, "no line in an item's tooltip")
    eq(block.Picture:GetAlpha(), 1, "the picture stays as it is"); eq(own:IsEnabled(), true, "and the buttons are there to press")

    -- A row of the list at the auction house has the lines of the answer in force.
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ScanToEnd()
    W.Run(0.3)
    local rows
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then rows = w end
    end
    local function Row(name)
        for _, w in ipairs(rows:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry and w.entry.offer.name == name then return w end
        end
    end
    local chest = Row("Good Chest")
    check(chest ~= nil, "the good chest is in the list")
    chest:GetScript("OnEnter")(chest)
    eq(Ours(GameTooltip), "*Arms +80%", "a row's tooltip: one line, for the profile the list is made on")
    local with = #GameTooltip._lines
    chest:GetScript("OnLeave")(chest)

    -- Where: not on the addon's tabs either. A row's tooltip is the item's own, with the
    -- worn item beside it as ever. Shown nowhere, the lines leave nothing to choose: the
    -- picture fades and the two buttons go dim, keeping what they say.
    tabs:SetChecked(false)
    tabs:Click()
    eq(UpgradeScoutDB.rowTooltip, false, "unticked: written down for the account"); eq(tabs.Tick:IsShown(), false, "the tick goes")
    W.compared = nil
    chest:GetScript("OnEnter")(chest)
    eq(Ours(GameTooltip), nil, "a row's tooltip has nothing of ours")
    eq(GameTooltip._link, chest.entry.offer.link, "it is the item's own")
    eq(#GameTooltip._lines, with - 2, "shorter by our blank line and our line")
    eq(W.compared, GameTooltip, "the worn item is still shown beside it")
    chest:GetScript("OnLeave")(chest)
    eq(block.Picture:GetAlpha(), 1, "the score shown nowhere: the picture stays for the note")
    eq(tip.Note:IsShown(), true, "which it has"); eq(tip.Note:GetText(), "You are 12s short", "in the row's own words")
    eq(tip.Brand:IsShown(), true, "under the addon's name"); eq(tip.Lines[1].Title:IsShown(), false, "and no line of the score")
    local notes = block.Notes
    eq(notes.Label:GetText(), 'Show lines such as "You are 12s short" and "Takes both hands"', "the box of the notes names two of them, word for word")
    eq(notes:GetChecked(), true, "ticked to begin with"); check(notes._points[1].y < elsewhere._points[1].y, "under the two boxes of the score")
    check(block.Rule._points[1].y < elsewhere._points[1].y and block.Rule._points[1].y > notes._points[1].y, "a fine line between them")
    notes:SetChecked(false)
    notes:Click()
    eq(UpgradeScoutDB.rowNotes, false, "unticked: written down for the account"); eq(notes.Tick:IsShown(), false, "the tick goes")
    eq(block.Picture:GetAlpha(), 0.3, "nothing of ours shows anywhere now: the picture fades")
    eq(tip.Note:IsShown(), false, "without the note"); eq(tip.Lines[1].Title:IsShown(), true, "and with the score's line, which would come back")
    notes:SetChecked(true)
    notes:Click()
    eq(UpgradeScoutDB.rowNotes, nil, "ticked again: nothing is left written"); eq(block.Picture:GetAlpha(), 1, "and the picture is back")
    eq(own:IsEnabled(), false, "the buttons cannot be pressed"); eq(all:IsEnabled(), false, "neither of them")
    eq(own:GetAlpha(), 0.35, "and are dim"); eq(own.Mark:IsShown(), true, "but keep what they say")
    eq(UpgradeScoutDB.ownTree, true, "as does the account")

    -- The tabs ticked again: the lines are back on a row, as they were left.
    tabs:SetChecked(true)
    tabs:Click()
    eq(UpgradeScoutDB.rowTooltip, nil, "ticked again: nothing is left written")
    eq(block.Picture:GetAlpha(), 1, "the picture is back"); eq(own:IsEnabled(), true, "and so are the buttons"); eq(own:GetAlpha(), 1, "at full strength")
    chest:GetScript("OnEnter")(chest)
    eq(Ours(GameTooltip), "*Arms +80%", "the row's tooltip has its one line again")
    chest:GetScript("OnLeave")(chest)

    -- How: every tree again, and nothing is left written.
    all:Click()
    eq(UpgradeScoutDB.ownTree, nil, "every tree chosen: nothing is left written")
    eq(all.Mark:IsShown(), true, "its button is lit"); eq(own.Mark:IsShown(), false, "the other is dark")
    eq(tip.Brand:IsShown(), true, "the picture has its heading back"); eq(tip.Lines[2].Title:IsShown(), true, "and both profiles")
    eq(tip.Lines[1].Title:GetText(), "Arms", "by their names alone"); eq(tip:GetHeight(), tall, "as tall as it was")
    chest:GetScript("OnEnter")(chest)
    eq(Ours(GameTooltip), "*Upgrade Scout | Arms +80% | Protection ~ -25%", "the row's tooltip has every profile again")
    chest:GetScript("OnLeave")(chest)
    eq(Item(GameTooltip, 200), nil, "an item's tooltip elsewhere is still without our lines")
    elsewhere:SetChecked(true)
    elsewhere:Click()
    eq(UpgradeScoutDB.tooltip, nil, "the rest of the game ticked again: nothing is left written")
    eq(Item(GameTooltip, 200), "*Upgrade Scout | Arms +80% | Protection ~ -25%", "and an item's tooltip has every profile again")
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
    eq(window.Ask:GetText(), ns.L.WELCOME_TREE:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")), "and stands alone, with nothing after it")

    -- The pictures: the list, an item's tooltip, the bags.
    local list, tip, bag = window.Pair[1].Picture, window.Tips.Picture.Tip, window.Pair[2].Picture
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
    check(window.Pair[1].Body:GetText():find("Scan", 1, true) and window.Pair[1].Body:GetText():find("Consumables", 1, true),
        "the auction house's card names the button and the tabs")
    eq(window.Pair[2].Title:GetText(), "IN YOUR BAGS AND BANK", "a card's name in capitals")

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

    -- Our lines in the tooltip of any item away from the addon's tabs, switched off (the
    -- tooltip's block and its other answers have a scenario of their own, tooltip_settings).
    local function Ours(id)
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink(W.Link(id))
        for _, line in ipairs(GameTooltip._lines) do
            if line.text:find("Upgrade Scout", 1, true) then return true end
        end
        return false
    end
    local tips = window.Tips.Elsewhere
    eq(tips:GetChecked(), true, "the tooltip's box is ticked to begin with"); eq(Ours(200), true, "and an item's tooltip has our lines")
    tips:SetChecked(false)
    tips:Click()
    eq(UpgradeScoutDB.tooltip, false, "unticked: written down for the account"); eq(Ours(200), false, "and the lines are gone")
    eq(tips.Tick:IsShown(), false, "the tick goes"); eq(window.Tips.Picture:GetAlpha(), 1, "the picture stays: the lines still show on the addon's tabs")

    -- The arrows in the bags, the same way: they go and come at once.
    local slot = W.PutInBags(W.Link(200))
    W.OpenBags()
    local function Arrow()
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(Arrow(), true, "an arrow on the better chest")
    local arrows = window.Pair[2].Switch
    arrows:SetChecked(false)
    arrows:Click()
    eq(UpgradeScoutDB.arrows, false, "unticked: written down"); eq(Arrow(), false, "and the arrow is gone at once")
    W.DrawBags()
    eq(Arrow(), false, "it stays away when the bags are drawn again")
    arrows:SetChecked(true)
    arrows:Click()
    eq(UpgradeScoutDB.arrows, nil, "ticked again: nothing is left written"); eq(Arrow(), true, "and the arrow is back")
    eq(window.Pair[1].Switch, nil, "the auction house has no box: its tabs are in nobody's way")
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

---------------------------------------------------------------------------
-- Pawn in place of the addon's own weights (Pawn.lua), for a player who chose it
---------------------------------------------------------------------------
-- Pawn's names for the scales it makes for the talent trees of a warrior and of a druid: two
-- each here, as the tests' classes have two profiles.
local ARMS, PROT, BALANCE, FERAL = '"Classic":WARRIOR1', '"Classic":WARRIOR2', '"Classic":DRUID1', '"Classic":DRUID2'

-- Pawn is installed, with those four scales and one the player made by hand. The character
-- being played (call this while it is the warrior) has its class's two and the hand-made
-- one switched on. Arms weighs an item's first score, as the addon's own first profile does,
-- Protection the second, and "Leveling" the first twice over; the druid's weigh the scores
-- the tests give an item for a druid. Protection is told to show no two-handed weapons.
local function PawnWorld()
    W.InstallPawn()
    W.AddPawnScale({ name = ARMS, title = "Warrior: Arms", class = 1, spec = 1, shown = true,
        values = { TEST_S1 = 1, Strength = 1.5, Agility = 1, Stamina = 0.5, Ap = 0.4, CritRating = 8 } })
    W.AddPawnScale({ name = PROT, title = "Warrior: Protection", class = 1, spec = 2, shown = true, no2H = true,
        values = { TEST_S2 = 1, Stamina = 1 } })
    W.AddPawnScale({ name = "Leveling", shown = true, values = { TEST_S1 = 2 } })
    W.AddPawnScale({ name = BALANCE, title = "Druid: Balance", class = 11, spec = 1,
        values = { TEST_D1 = 1, Intellect = 1, SpellDamage = 1, CritRating = 6 } })
    W.AddPawnScale({ name = FERAL, title = "Druid: Feral", class = 11, spec = 2, values = { TEST_D2 = 1, Agility = 1 } })
end

-- Pawn was asked nothing it answers with an error line in the chat, and about no item with
-- its enchantment on.
local function CheckPawnAsked(label)
    eq(#W.pawn.fails, 0, label .. ": Pawn is asked about no scale it has not" .. (W.pawn.fails[1] and (": " .. W.pawn.fails[1]) or ""))
    for _, link in ipairs(W.pawn.asked) do
        check(not link:match("item:%d+:%d"), label .. ": Pawn is asked about an item without its enchantment")
    end
end

-- The road of a player who has Pawn: the addon scores by itself until Pawn is chosen, then
-- on the Pawn scale in use, and the lists are made the same way from Pawn's numbers.
function scenarios.pawn_scan()
    StandardWorld()
    -- The worn chest is enchanted. On the second score: the two chests 9 (for sale) and 12
    -- (worn), a helm, a two-hander and a shield.
    W.equipped[5] = (W.Link(100):gsub("item:100:", "item:100:66", 1))
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["211:0"].value2, W.items["212:0"].value2, W.items["213:0"].value2 = 5, 40, 8
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    PawnWorld()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score, S, me = ns.Score, ns.Scanner, ns.Roster.Me()

    -- Pawn is there and not chosen: the addon scores by itself and asks Pawn nothing.
    eq(ns.Pawn.Usable(), true, "Pawn is there to be asked"); eq(Score.Engine(), nil, "and is not, until chosen")
    eq(Score.Current().name, "S1", "the profiles are the addon's own")
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    ScanToEnd()
    CheckStandardOffers("the addon's own weights, with Pawn installed")
    eq(#W.pawn.asked, 0, "Pawn is asked about no item")
    eq(#dropdown.radios, 2, "the field lists the addon's profiles"); eq(dropdown:GetText(), "Arms", "the one in use")

    -- Pawn chosen, as the welcome window does it: for the whole account, and at once.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    Score.SetEngine("pawn")
    eq(UpgradeScoutDB.engine, "pawn", "the choice is written down for the account"); eq(Score.Engine(), "pawn", "and Pawn scores")
    eq(told, 1, "what keeps scores is told")
    local current, list = Score.Current()
    eq(#list, 3, "the profiles are the Pawn scales the character has switched on")
    eq(list[1].name, "Leveling", "in Pawn's order: one made by hand first"); eq(list[1].title, "Leveling", "by its name")
    eq(list[2].name, ARMS, "then Pawn's own, by Pawn's name for it"); eq(list[2].title, "Arms", "shown without the class it begins with")
    eq(list[3].title, "Protection", "each of them")
    eq(current.name, ARMS, "the one in use: Pawn's scale for the tree the talents are in")
    eq(Score.Title(ARMS), "Arms", "a scale's title by its name"); eq(Score.IsApprox(ARMS), false, "no scale is marked as an estimate")
    eq(#Score.Trees(), 2, "the addon's own profiles are still there to be asked for")

    -- The list that was there is made again, on the scale.
    check(S.state ~= "idle", "a list that was made on the addon's weights is made again")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(S.ctx.profile, ARMS, "on the scale in use")
    CheckStandardOffers("Pawn's scale for Arms")
    near(S.ctx.equipped[5].value, 10, "what is worn is scored by Pawn, without its enchantment")
    near(S.ctx.equipped[16].value, 20, "every piece of it")
    eq(S.ctx.show1H, true, "the scale shows one-handed weapons"); eq(S.ctx.show2H, true, "and two-handed ones")
    CheckPawnAsked("a scan")
    eq(#dropdown.radios, 3, "the field lists the scales"); eq(dropdown.radios[1].text, "Leveling", "by their names")
    eq(dropdown:GetText(), "Arms", "and shows the one in use")
    dropdown._tooltip(GameTooltip)
    local tip = {}
    for _, line in ipairs(GameTooltip._lines) do tip[#tip + 1] = line.text end
    check(table.concat(tip, " | "):find(ns.L.PROFILE_TIP_PAWN, 1, true) ~= nil, "its tooltip is about Pawn's scales")

    -- Another scale chosen in the field: kept apart from the addon's own profile, and the
    -- list is made again. This one is told to show no two-handers.
    dropdown:Pick(3)
    eq(me.scale, PROT, "the scale chosen is written on the character's card"); eq(me.profile, nil, "the addon's own profile is left alone")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(S.ctx.profile, PROT, "the list is on the scale chosen"); eq(S.ctx.show2H, false, "which shows no two-handed weapons")
    check(Offer("Helm") ~= nil, "a helm for the empty head, by its score on that scale")
    check(Offer("Shield") ~= nil, "a shield for the empty off hand")
    eq(Offer("Big Axe"), nil, "no two-hander, though it scores 40 against the sword's nothing")
    eq(Offer("Good Chest"), nil, "the chest is no upgrade on it: 9 against 12")
    eq(OfferCount(), 2, "and nothing else")

    -- The scale made by hand weighs the first score twice.
    dropdown:Pick(1)
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(me.scale, "Leveling", "a scale made by hand chosen"); near(Offer("Good Chest").value, 36, "its own weights: 18 twice over")
    near(S.ctx.equipped[5].value, 20, "for what is worn as well")

    -- /upscout stats: Pawn's stats of the item and the scale's weights, with Pawn's total.
    W.items["200:0"].pawn = { Strength = 5, IsMail = 1 }
    local at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats " .. W.Link(200))
    local said = Said(at)
    check(said:find('on the profile "Leveling": score 36', 1, true) ~= nil, "the scale in use and Pawn's score: " .. said)
    check(said:find("TEST_S1: 18 × 2 = 36", 1, true) ~= nil, "a stat by Pawn's name for it, with the scale's weight")
    check(said:find("Strength", 1, true) == nil, "a stat the scale does not weigh is left out")
    W.items["200:0"].pawn = nil

    -- The scale's weights are changed in Pawn's own window: the addon hears of it, and the
    -- list is made again.
    PawnCommon.Scales["Leveling"].Values.TEST_S1 = 3
    W.PawnChanged()
    W.Run(0.5)
    eq(told, 2, "Pawn's scales changed: what keeps scores is told")
    W.RunUntil(function() return S.state == "idle" end, 600)
    near(Offer("Good Chest").value, 54, "the list is on the new weights")
    -- Pawn resets its tooltips for other reasons too (how they look): no scale changed.
    W.PawnChanged()
    W.Run(0.5)
    eq(told, 2, "Pawn's tooltips reset with its scales as they were: nothing is told"); eq(S.state, "idle", "and the list stays")
    PawnCommon.Scales["Leveling"].Values.TEST_S1 = 4
    W.PawnChanged()
    PawnCommon.Scales["Leveling"].Values.TEST_S1 = 3
    PawnCommon.Scales[PROT].DoNotShow1HUpgrades = true
    W.PawnChanged()
    W.Run(0.5)
    eq(told, 3, "a burst of changes is one telling")
    W.RunUntil(function() return S.state == "idle" end, 600)
    PawnCommon.Scales[PROT].DoNotShow1HUpgrades = false
    W.PawnChanged()
    W.Run(0.5)
    eq(told, 4, "a scale's say on weapons is a change as well")
    W.RunUntil(function() return S.state == "idle" end, 600)

    -- The scale in use is switched off in Pawn: the one for the talents takes its place.
    PawnCommon.Scales["Leveling"].PerCharacterOptions[W.PawnName()].Visible = false
    W.PawnChanged()
    W.Run(0.5)
    eq(Score.Current().name, ARMS, "a scale that is gone gives way to the one for the talents")
    eq(#dropdown.radios, 2, "and is no longer in the field"); eq(dropdown:GetText(), "Arms", "which shows the one in use")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(S.ctx.profile, ARMS, "the list follows")

    -- No scale switched on: no scan, and the reason.
    PawnCommon.Scales[ARMS].PerCharacterOptions[W.PawnName()].Visible = false
    PawnCommon.Scales[PROT].PerCharacterOptions[W.PawnName()].Visible = false
    W.PawnChanged()
    W.Run(0.5)
    eq(Score.Current(), nil, "no scale switched on: none in use")
    eq(S.Start(), false, "and no scan"); eq(S.message, ns.L.ERR_NO_SCALE, "which says why")
    PawnCommon.Scales[ARMS].PerCharacterOptions[W.PawnName()].Visible = true
    W.PawnChanged()
    W.Run(0.5)
    CheckPawnAsked("scales coming and going")

    -- Back to the addon's own weights: its profile is where it was left, and so is the scale.
    Score.SetEngine(nil)
    eq(UpgradeScoutDB.engine, nil, "the addon's own weights chosen again: nothing is left written")
    eq(Score.Current().name, "S1", "the addon's profile as it was"); eq(me.scale, "Leveling", "the scale chosen is kept for another time")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(#dropdown.radios, 2, "the field lists the addon's profiles again")
    local asked = #W.pawn.asked
    ScanToEnd()
    CheckStandardOffers("the addon's own weights again")
    eq(#W.pawn.asked, asked, "and Pawn is asked nothing")

    -- Which scale is for a character's talents: the place of the tree among its class's, as
    -- Pawn numbers them. A priest has three trees there and two profiles here.
    ns.Weights.classes.PRIEST = { "PRIEST_HEALER", "PRIEST_SHADOW" }
    for spec, title in ipairs({ "Discipline", "Holy", "Shadow" }) do
        W.AddPawnScale({ name = '"Classic":PRIEST' .. spec, title = "Priest: " .. title, class = 5, spec = spec })
    end
    Score.SetEngine("pawn")
    eq(Score.Current({ key = "P", class = "PRIEST", talents = "PRIEST_SHADOW" }).title, "Shadow", "a priest's Shadow is Pawn's third")
    eq(Score.Current({ key = "P", class = "PRIEST", talents = "PRIEST_HEALER" }).title, "Holy", "its healer is Pawn's Holy")
    eq(Score.Current({ key = "P", class = "PRIEST" }).title, "Discipline", "without talents known: the first")
    eq(Score.Current({ key = "P", class = "DRUID", talents = "D2" }).title, "Feral", "another class by the place of its tree")
    eq(Score.Current({ key = "P", class = "DRUID", talents = "D2", scale = BALANCE }).title, "Balance", "under the scale chosen for it")
    CheckPawnAsked("another character's scales")
end

-- Pawn chosen and not there: the addon scores by itself, and the choice stands.
function scenarios.pawn_absent()
    StandardWorld()
    UpgradeScoutDB = { engine = "pawn" }
    LoadAddon()
    local Score = ns.Score
    eq(ns.Pawn.Usable(), false, "Pawn is not installed"); eq(Score.Engine(), nil, "so the addon scores, though Pawn was chosen")
    eq(Score.Current().name, "S1", "on its own profiles")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("Pawn chosen and not installed")
    eq(UpgradeScoutDB.engine, "pawn", "the choice stands for when Pawn is back")

    -- Pawn is there but still reading its scales, as in the first moments of logging in.
    PawnWorld()
    W.pawn.ready = false
    eq(ns.Pawn.Usable(), false, "Pawn that has not read its scales yet cannot be asked"); eq(Score.Engine(), nil, "and is not")
    eq(Score.Current().name, "S1", "the addon's profiles meanwhile")
    eq(#W.pawn.fails, 0, "nothing is asked of it")
    W.pawn.ready = true
    eq(Score.Engine(), "pawn", "once it has, it scores, as chosen")
    eq(Score.Current().name, "Leveling", "on the first of its scales, with no talents to go by")

    -- A Pawn without one of the functions the addon calls is a Pawn that cannot be asked.
    local kept = PawnGetItemValue
    PawnGetItemValue = nil
    eq(ns.Pawn.Usable(), false, "a Pawn that lacks a function the addon calls"); eq(Score.Engine(), nil, "leaves the scoring to the addon")
    PawnGetItemValue = kept
    local scales = PawnCommon
    PawnCommon = nil
    eq(ns.Pawn.Usable(), false, "and so does one without its scales")
    PawnCommon = scales
    eq(Score.Engine(), "pawn", "with everything in place it scores")

    -- Switched off for the next session: the addon's weights again, without a word.
    Relog(W.player, W.equipped)
    W.RemovePawn()
    eq(ns.Score.Engine(), nil, "Pawn switched off: the addon scores")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("Pawn switched off")
    eq(UpgradeScoutDB.engine, "pawn", "and the choice still stands")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- With Pawn scoring: no lines of ours in a tooltip, the arrows in the bags by the scale in
-- use, and under a row of the list only what there is to say about buying the item.
function scenarios.pawn_tooltips()
    StandardWorld()
    W.AddItem({ id = 220, name = "Oak Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subClassID = 19, value = 9, level = 5 })
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["212:0"].value2 = 40
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    -- A shirt and a trinket that is only used, as most characters wear: Pawn keeps nothing
    -- of either, and that is not to be taken for gear still to be read.
    W.AddItem({ id = 230, name = "Lucky Charm", equipLoc = "INVTYPE_TRINKET", value = 0, level = 1, noStats = true })
    W.equipped[4] = W.Link(207)
    W.equipped[13] = W.Link(230)
    PawnWorld()
    -- Pawn was chosen in an earlier session.
    UpgradeScoutDB = { engine = "pawn" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(ns.Pawn.Item(W.Link(207)).pawn, false, "a shirt: Pawn has nothing, and that is its answer")
    eq(ns.Pawn.Item(W.Link(230)).pawn, false, "the same for a trinket that adds nothing")
    eq(ns.Score.Context(ARMS).unread, nil, "wearing them, the gear is whole")
    eq(ns.Score.Engine(), "pawn", "Pawn scores, as chosen before"); eq(ns.Score.Current().name, ARMS, "on the scale for the talents")

    -- Does the tooltip have lines of ours? Our header, then what is under it, joined by " | ".
    local function Ours(tooltip)
        local header
        for i, line in ipairs(tooltip._lines) do
            if line.text:find("Upgrade Scout", 1, true) then header = i end
        end
        if not header then return nil end
        local out = {}
        for i = header + 1, #tooltip._lines do
            local line = tooltip._lines[i]
            out[#out + 1] = line.text .. (line.right and " " .. line.right or "")
        end
        return table.concat(out, " | ")
    end
    local function Shown(tooltip, id)
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetHyperlink(W.Link(id))
        return Ours(tooltip)
    end
    eq(Shown(GameTooltip, 200), nil, "no lines of ours for an item in the bags: Pawn writes its own")
    eq(Shown(ItemRefTooltip, 200), nil, "nor for a link in the chat")

    -- The arrows stay, and go by the scale in use.
    local function Bag(slot)
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local function Grey(slot) return ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow._grey end
    local slot = {}
    for _, id in ipairs({ 200, 202, 203, 204, 208, 212, 214, 220 }) do slot[id] = W.PutInBags(W.Link(id)) end
    W.OpenBags()
    eq(Bag(slot[200]), true, "a better chest: 18 against 10 on Pawn's scale"); eq(Grey(slot[200]), false, "green: it can be put on now")
    eq(Bag(slot[203]), true, "a better chest of a higher level"); eq(Grey(slot[203]), true, "grey")
    eq(Bag(slot[212]), true, "a two-hander against the sword")
    eq(Bag(slot[202]), false, "not a weaker chest"); eq(Bag(slot[204]), false, "not mail the character has not learned")
    eq(Bag(slot[208]), false, "not a chest Pawn has nothing for"); eq(Bag(slot[220]), false, "not a wand: a warrior never uses one")
    eq(Bag(slot[214]), false, "not a potion")
    W.Run(12)
    local asked = #W.pawn.asked
    W.DrawBags()
    eq(#W.pawn.asked, asked, "what was worked out is kept: Pawn is not asked again when the bags are drawn")

    -- Another scale chosen, as in the welcome window: the arrows follow.
    ns.UI.ChooseProfile(PROT)
    W.Run(1)
    eq(Bag(slot[200]), false, "on Protection the chest is no upgrade: 9 against 12")
    eq(Bag(slot[212]), false, "and that scale shows no two-handers")
    ns.UI.ChooseProfile(ARMS)
    W.Run(1)
    eq(Bag(slot[200]), true, "back on Arms the chest has its arrow"); eq(Bag(slot[212]), true, "and so has the two-hander")

    -- The scale's weights change in Pawn's own window.
    PawnCommon.Scales[ARMS].Values.TEST_S1 = 0
    W.PawnChanged()
    W.Run(1)
    eq(Bag(slot[200]), false, "a scale that weighs nothing: no arrows")
    PawnCommon.Scales[ARMS].Values.TEST_S1 = 1
    W.PawnChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "the weights back, the arrow back")

    -- They can be switched off and on as ever.
    UpgradeScoutDB.arrows = false
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(Bag(slot[200]), false, "the arrows switched off with Pawn scoring")
    UpgradeScoutDB.arrows = nil
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(Bag(slot[200]), true, "and on again")

    -- A row of the list at the auction house.
    W.player.money = 50000
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    SetView(false, false)
    ScanToEnd()
    W.Run(1)
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    local function Row(name)
        for _, w in ipairs(scrollBox:GetFrames()) do
            local entry = w._shown and w._kind == "Button" and w.entry or nil
            if entry and entry.offer and entry.offer.name == name then return w end
        end
    end
    local function Under(name)
        local row = Row(name)
        check(row ~= nil, name .. " is in the list")
        W.compared = nil
        row:GetScript("OnEnter")(row)
        local ours = Ours(GameTooltip)
        row:GetScript("OnLeave")(row)
        return ours
    end
    eq(Under("Good Chest"), nil, "a row with nothing to add: no lines of ours, not even the addon's name")
    eq(W.compared, GameTooltip, "the worn item is shown beside it as ever")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short",
        "a row with something to say about buying: that, under the addon's name, and no gains")
    local noted = Row("Great Chest")
    noted:GetScript("OnEnter")(noted)
    local named = false
    for _, line in ipairs(GameTooltip._lines) do
        if line.text:find("Pawn score", 1, true) then named = true end
    end
    eq(named, false, "notes are nobody's score: the heading is the addon's name alone")
    noted:GetScript("OnLeave")(noted)
    ns.db.net = true
    eq(Under("Good Chest"), nil, "with Value by net cost ticked: still nothing, the prices are in the row")
    ns.db.net = nil
    -- The notes have a box of their own in the welcome window; the one of the score's lines
    -- on the tabs has nothing to say here.
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short", "the score's box unticked: the notes stay")
    UpgradeScoutDB.rowTooltip = nil
    UpgradeScoutDB.rowNotes = false
    ns.Fire("SETTING_CHANGED", "rowNotes")
    eq(Under("Great Chest"), nil, "the notes' box unticked: no notes")
    eq(W.compared, GameTooltip, "the worn item still beside it")
    UpgradeScoutDB.rowNotes = nil
    ns.Fire("SETTING_CHANGED", "rowNotes")
    check(Under("Great Chest") ~= nil, "ticked again, they are back")
    -- One line for the tree in use, chosen before Pawn was: nothing changes with Pawn scoring.
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    eq(Shown(GameTooltip, 200), nil, "\"Only my spec\" chosen: still no lines of ours in the bags")
    eq(Under("Good Chest"), nil, "nor under a row with nothing to add")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short", "and the notes as they were")
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")
    CheckPawnAsked("tooltips and arrows")

    -- The addon's own weights chosen again: its lines are back.
    ns.Score.SetEngine(nil)
    W.Run(1)
    eq(Shown(GameTooltip, 200), "Arms +80% | Protection ~ -25%", "the addon scores again: its lines in the tooltip")
    eq(Bag(slot[200]), true, "and the arrows by its own profile")
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 600)
    check(Under("Good Chest"):find("Arms +80%", 1, true) ~= nil, "a row's tooltip has the gains again")

    -- With the addon scoring, the two kinds of lines under a row each go by their own box.
    W.Run(1)
    local both = Under("Great Chest")
    check(both:find("Arms +200%", 1, true) ~= nil and both:find("Has effects the score does not count | You are 4g short", 1, true) ~= nil,
        "the score and the notes: " .. both)
    UpgradeScoutDB.rowNotes = false
    local scoreOnly = Under("Great Chest")
    check(scoreOnly:find("Arms +200%", 1, true) ~= nil, "the notes unticked: the score stays")
    check(scoreOnly:find("Has effects", 1, true) == nil and scoreOnly:find("short", 1, true) == nil, "without the notes: " .. scoreOnly)
    UpgradeScoutDB.rowNotes = nil
    UpgradeScoutDB.rowTooltip = false
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short", "the score unticked: the notes alone, under the addon's name")
    eq(Under("Good Chest"), nil, "and nothing where there is nothing to note")
    UpgradeScoutDB.rowNotes = false
    eq(Under("Great Chest"), nil, "both unticked: nothing of ours")
    UpgradeScoutDB.rowTooltip, UpgradeScoutDB.rowNotes = nil, nil
end

-- The welcome window with Pawn: who scores, the scales in place of the trees, the tooltip's
-- block out of use, and the window coming up once for a player who has Pawn.
function scenarios.pawn_welcome()
    StandardWorld()
    W.AddItem({ id = 16999, name = "Royal Seal", equipLoc = "INVTYPE_FINGER", quality = 3, level = 54 })
    W.AddItem({ id = 5000, name = "Coral Band", equipLoc = "INVTYPE_FINGER", level = 21 })
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    local L

    -- Without Pawn: the choice is there, and Pawn's answer is out of reach.
    LoadAddon()
    L = ns.L
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome ~= nil end, 10)
    local window = UpgradeScoutWelcome
    eq(window.About:GetText(), L.WELCOME_FIRST, "the first time: a welcome")
    local own, pawn = window.Engines[1], window.Engines[2]
    eq(own.Label:GetText(), "Upgrade Scout", "who scores: the addon"); eq(pawn.Label:GetText(), "Pawn", "or Pawn, each by its name")
    eq(own.Mark:IsShown(), true, "the addon is the one that does"); eq(pawn.Mark:IsShown(), false, "Pawn is not")
    eq(pawn:GetAlpha(), 0.45, "Pawn cannot be chosen while it is not there: its button is grey")
    eq(pawn.Glow.parts[1]:IsShown(), false, "and does not light up under the mouse"); eq(own.Glow.parts[1]:IsShown(), true, "as the other does")
    eq(window.Who:GetText(), L.WELCOME_ENGINE, "the question stands alone")
    -- Why it is grey is said in a tooltip of the button.
    local function Hint(button)
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        button:GetScript("OnEnter")(button)
        local said = GameTooltip._lines[1] and GameTooltip._lines[1].text or nil
        local owner = GameTooltip:GetOwner()
        button:GetScript("OnLeave")(button)
        return said, owner
    end
    local said, owner = Hint(pawn)
    eq(said, L.WELCOME_NO_PAWN, "the mouse on the grey button: a tooltip says why"); eq(owner, pawn, "at the button")
    eq(Hint(own), nil, "the addon's own button has nothing to explain")
    pawn:Click()
    eq(UpgradeScoutDB.engine, nil, "a click on the grey button does nothing")
    check(own._points[1].x < pawn._points[1].x and own._points[1].y == pawn._points[1].y, "the two side by side")
    check(window.Trees[1]._points[1].y < own._points[1].y, "above the trees")
    eq(#window.Trees, 2, "the trees as ever"); eq(window.Trees[1].Label:GetText(), "Arms", "by their names")
    local height = window:GetHeight()
    window.Done:Click()
    eq(UpgradeScoutDB.welcomed, true, "seen"); eq(UpgradeScoutDB.pawnOffered, nil, "but not with Pawn there to choose")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "no Pawn: the window does not come up by itself again")

    -- The player installs Pawn. The window comes up once more by itself, and says why.
    PawnWorld()
    Relog(W.player, W.equipped)
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome:IsShown() end, 10)
    L = ns.L
    window = UpgradeScoutWelcome
    eq(window.About:GetText(), L.WELCOME_PAWN_NEW, "Pawn is there now: the window comes up to say that it can be chosen")
    own, pawn = window.Engines[1], window.Engines[2]
    eq(pawn:GetAlpha(), 1, "Pawn can be chosen: its button is no longer grey"); eq(pawn.Glow.parts[1]:IsShown(), true, "and lights up under the mouse")
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    pawn:GetScript("OnEnter")(pawn)
    eq(#GameTooltip._lines, 0, "with nothing left to explain in a tooltip")
    eq(window.Who:GetText(), L.WELCOME_ENGINE, "the question stands alone: nothing more to say of a button that can be clicked")
    eq(own.Mark:IsShown(), true, "the addon scores until Pawn is chosen")
    eq(window:GetHeight(), height, "the window is as tall as without Pawn")

    -- Pawn chosen.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    pawn:Click()
    eq(UpgradeScoutDB.engine, "pawn", "a click chooses Pawn, for the account"); eq(told, 1, "and what keeps scores is told")
    eq(pawn.Mark:IsShown(), true, "Pawn's button is lit"); eq(own.Mark:IsShown(), false, "the addon's goes dark")
    local trees = window.Trees
    eq(trees[1].Label:GetText(), "Leveling", "the buttons are the character's Pawn scales now")
    eq(trees[2].Label:GetText(), "Arms", "by their names, without the class"); eq(trees[3].Label:GetText(), "Protection", "each of them")
    eq(trees[3]:IsShown(), true, "three of them"); eq(trees[2].Mark:IsShown(), true, "the one in use is lit")
    check(window.Ask:GetText():find(L.WELCOME_SCALE:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")), 1, true) ~= nil,
        "the question is about the scale, and names the character")
    eq(window.Ask:GetText(), L.WELCOME_SCALE:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")), "and stands alone, with nothing after it")
    pawn:Click()
    eq(told, 1, "the one that scores clicked again: nothing changes")

    -- The score in a tooltip is Pawn's to write now: the block says so, and what it asks of
    -- the score is out of use, the two buttons dim, the two boxes empty and dim. The notes
    -- are still ours: their box is as it was, and so is the arrows' card.
    local block, arrows = window.Tips, window.Pair[2]
    local tip, tabs, elsewhere, notes = block.Picture.Tip, block.Tabs, block.Elsewhere, block.Notes
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_PAWN, "the tooltip's block says that Pawn writes there")
    for name, box in pairs({ ["the addon's tabs"] = tabs, ["the rest of the game"] = elsewhere }) do
        eq(box:IsEnabled(), false, "the score's box for " .. name .. " is out of use"); eq(box:GetChecked(), false, "and empty: " .. name)
        eq(box.Tick:IsShown(), false, "without its tick: " .. name); eq(box:GetAlpha(), 0.4, "and dim: " .. name)
        eq(box.Label:GetAlpha(), 0.5, "as its words are: " .. name)
        box:SetChecked(false)
        box:Click()
    end
    eq(UpgradeScoutDB.tooltip, nil, "a click on such a box changes nothing"); eq(UpgradeScoutDB.rowTooltip, nil, "on either")
    eq(block.All:IsEnabled(), false, "the two buttons are out of use"); eq(block.Own:IsEnabled(), false, "both")
    eq(block.All:GetAlpha(), 0.35, "and dim"); eq(block.All.Mark:IsShown(), true, "the one in force still lit")
    block.Own:Click()
    eq(UpgradeScoutDB.ownTree, nil, "a click on a dim button changes nothing")
    -- The notes: the one box in use, and the picture shows what it is for.
    eq(notes:IsEnabled(), true, "the box of the notes is in use"); eq(notes:GetChecked(), true, "and ticked")
    eq(notes.Tick:IsShown(), true, "with its tick"); eq(notes:GetAlpha(), 1, "at full strength")
    eq(block.Picture:GetAlpha(), 1, "the picture is whole: it has the note")
    eq(tip.Note:IsShown(), true, "what the player is short of"); eq(tip.Brand:IsShown(), true, "under the addon's name")
    eq(tip.Lines[1].Title:IsShown(), false, "and no line of the score: that is Pawn's"); eq(tip.Lines[2].Title:IsShown(), false, "none")
    notes:SetChecked(false)
    notes:Click()
    eq(UpgradeScoutDB.rowNotes, false, "unticked: written down, with Pawn scoring as without")
    eq(block.Picture:GetAlpha(), 0.3, "nothing of ours in a tooltip now: the picture fades")
    eq(tip.Note:IsShown(), false, "without the note")
    eq(tip.Lines[1].Title:GetText(), "Arms", "it has the addon's own lines: what would come back")
    eq(tip.Lines[2].Title:GetText(), "Protection ~", "its profiles, not Pawn's scales")
    eq(tip.Lines[3], nil, "and no more of them")
    notes:SetChecked(true)
    notes:Click()
    eq(UpgradeScoutDB.rowNotes, nil, "and ticked again"); eq(block.Picture:GetAlpha(), 1, "the picture is back")
    eq(arrows.Switch:IsEnabled(), true, "the arrows' box is in use"); eq(arrows.Switch:GetChecked(), true, "and ticked")
    eq(arrows.Body:GetText(), L.WELCOME_ARROWS_TEXT, "with its own sentence"); eq(arrows.Picture:GetAlpha(), 1, "and its picture whole")
    local slot = W.PutInBags(W.Link(200))
    W.OpenBags()
    local function Arrow()
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(Arrow(), true, "an arrow on the better chest, by Pawn's scale")
    arrows.Switch:SetChecked(false)
    arrows.Switch:Click()
    eq(UpgradeScoutDB.arrows, false, "the arrows switched off with Pawn scoring"); eq(Arrow(), false, "go at once")
    arrows.Switch:SetChecked(true)
    arrows.Switch:Click()
    eq(Arrow(), true, "and come back")

    -- Another character of the account. Pawn writes of the one being played alone, so the
    -- lists for the other have our lines, always: the box of the tabs is held ticked, the
    -- one of the rest of the game empty. How the lines are written is the player's to choose.
    UpgradeScoutDB.chars["Alty-Testrealm"] = { key = "Alty-Testrealm", name = "Alty", realm = "Testrealm", class = "DRUID", level = 20 }
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_PAWN_OTHERS, "with another character the block says where our lines are left")
    eq(tabs:IsEnabled(), false, "the box of the tabs is not the player's to change"); eq(tabs:GetChecked(), true, "it is held ticked")
    eq(tabs.Tick:IsShown(), true, "with its tick"); eq(tabs:GetAlpha(), 0.4, "dim"); eq(tabs.Label:GetAlpha(), 0.5, "as its words are")
    tabs:Click()
    eq(UpgradeScoutDB.rowTooltip, nil, "a click on it changes nothing")
    eq(elsewhere:IsEnabled(), false, "the box of the rest of the game stays out of use"); eq(elsewhere:GetChecked(), false, "empty")
    eq(elsewhere:GetAlpha(), 0.4, "and dim")
    eq(block.All:IsEnabled(), true, "the two buttons are in use"); eq(block.Own:IsEnabled(), true, "both")
    eq(block.All:GetAlpha(), 1, "and whole")
    eq(tip.Lines[1].Title:IsShown(), true, "the picture has the score's lines"); eq(tip.Note:IsShown(), true, "and the note under them")
    block.Own:Click()
    eq(UpgradeScoutDB.ownTree, true, "a click on a button counts")
    eq(tip.Lines[2].Title:IsShown(), false, "and the picture follows: one line")
    block.All:Click()
    eq(UpgradeScoutDB.ownTree, nil, "both ways")
    -- Left unticked while the addon scored: with Pawn scoring that has no say.
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(tabs:GetChecked(), true, "the box of the tabs left unticked before: held ticked all the same"); eq(tabs.Tick:IsShown(), true, "with its tick")
    eq(block.All:IsEnabled(), true, "and the two buttons in use"); eq(tip.Lines[1].Title:IsShown(), true, "the picture with the score's lines")
    eq(UpgradeScoutDB.rowTooltip, false, "what the box was left at is kept")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    UpgradeScoutDB.chars["Alty-Testrealm"] = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_PAWN, "without the other character the block is as it was")
    eq(tabs:IsEnabled(), false, "the box of the tabs out of use"); eq(tabs:GetChecked(), false, "and empty")
    eq(block.All:IsEnabled(), false, "and the two buttons out of use")

    -- A scale chosen in the window: written on the character's card, apart from the profile.
    trees[3]:Click()
    eq(ns.Roster.Me().scale, PROT, "a click on a scale chooses it"); eq(ns.Roster.Me().profile, nil, "the addon's own profile is left alone")
    eq(trees[3].Mark:IsShown(), true, "its button lights up"); eq(trees[2].Mark:IsShown(), false, "the other goes dark")
    W.Run(0.5)
    eq(Arrow(), false, "and the arrows go by it: on Protection the chest is no upgrade")

    -- Many scales stand in rows; a long name is cut short on its button.
    for i = 1, 4 do
        W.AddPawnScale({ name = "Extra " .. i, shown = true, values = { TEST_S1 = 1 } })
    end
    W.AddPawnScale({ name = "A scale with a name far too long for any button to hold in one piece", shown = true })
    W.PawnChanged()
    W.Run(0.5)
    eq(trees[8]:IsShown(), true, "eight scales: a button for each")
    eq(trees[1]._points[1].y, trees[4]._points[1].y, "four in the first row"); check(trees[5]._points[1].y < trees[4]._points[1].y, "the rest in a second")
    eq(trees[5]._points[1].x, trees[1]._points[1].x, "which starts at the left again")
    check(trees[1].Label:GetWidth() <= trees[1]:GetWidth() - 40, "a name too long for its button is cut short")
    check(window:GetHeight() > height, "and the window is taller for the second row")
    for name in pairs(PawnCommon.Scales) do
        if name:find("Extra", 1, true) or name:find("far too long", 1, true) then PawnCommon.Scales[name] = nil end
    end

    -- No scale switched on in Pawn: the window says so where the buttons were.
    for _, name in ipairs({ ARMS, PROT, "Leveling" }) do PawnCommon.Scales[name].PerCharacterOptions[W.PawnName()].Visible = false end
    W.PawnChanged()
    W.Run(0.5)
    eq(trees[1]:IsShown(), false, "no scale switched on: no buttons")
    eq(window.Ask:IsShown(), true, "and a sentence in their place")
    check(window.Ask:GetText():find("Pawn shows no scale for", 1, true) ~= nil, "that says what to do: " .. window.Ask:GetText())
    for _, name in ipairs({ ARMS, PROT, "Leveling" }) do PawnCommon.Scales[name].PerCharacterOptions[W.PawnName()].Visible = true end
    W.PawnChanged()
    W.Run(0.5)
    eq(trees[3]:IsShown(), true, "switched on again, they are back")

    -- Closed: seen with Pawn there, so it does not come up by itself again.
    window.Done:Click()
    eq(UpgradeScoutDB.pawnOffered, true, "the choice has been seen")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "it does not come up by itself again")
    ns.Welcome.Show()
    eq(window.About:GetText(), L.WELCOME_ABOUT, "asked for, it has its usual first words")

    -- The addon chosen again: the trees, and the tooltip's block in use, as they were.
    own:Click()
    eq(UpgradeScoutDB.engine, nil, "a click on the addon's button: nothing is left written"); eq(told, 5, "what keeps scores is told")
    eq(own.Mark:IsShown(), true, "the addon's button is lit")
    eq(trees[1].Label:GetText(), "Arms", "the trees are back"); eq(trees[3]:IsShown(), false, "two of them")
    eq(trees[1].Mark:IsShown(), true, "the one for the talents in use")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_TEXT, "the tooltip's block has its sentence")
    for name, box in pairs({ ["the addon's tabs"] = tabs, ["the rest of the game"] = elsewhere }) do
        eq(box:IsEnabled(), true, "the score's box for " .. name .. " is in use"); eq(box:GetChecked(), true, "and ticked, as it was left: " .. name)
        eq(box.Tick:IsShown(), true, "with its tick: " .. name); eq(box:GetAlpha(), 1, "and whole: " .. name)
        eq(box.Label:GetAlpha(), 1, "as its words are: " .. name)
    end
    eq(block.All:IsEnabled(), true, "the two buttons in use"); eq(block.All:GetAlpha(), 1, "and whole")
    eq(block.Picture:GetAlpha(), 1, "the picture whole")
    eq(tip.Lines[1].Title:IsShown(), true, "with the score's lines"); eq(tip.Note:IsShown(), true, "and the note under them")
    block.Own:Click()
    eq(UpgradeScoutDB.ownTree, true, "and a click on a button counts again")
    block.All:Click()
    eq(UpgradeScoutDB.ownTree, nil, "both ways")
    CheckPawnAsked("the welcome window")

    -- A new player who has Pawn: one window, with the welcome, and it counts for both.
    window.Done:Click()
    UpgradeScoutDB = nil
    Relog(W.player, W.equipped)
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome ~= window and UpgradeScoutWelcome:IsShown() end, 10)
    eq(UpgradeScoutWelcome.About:GetText(), ns.L.WELCOME_FIRST, "a new player with Pawn: the welcome")
    eq(UpgradeScoutWelcome.Engines[2]:IsEnabled(), true, "with Pawn there to choose")
    UpgradeScoutWelcome.Done:Click()
    eq(UpgradeScoutDB.welcomed, true, "seen"); eq(UpgradeScoutDB.pawnOffered, true, "and seen with Pawn")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(UpgradeScoutWelcome:IsShown(), false, "it comes up once, not twice")
end

-- A worn item that Pawn cannot read, though the game says it adds something: waited for a
-- few seconds, then the arrows are drawn without it.
function scenarios.pawn_unread()
    StandardWorld()
    PawnWorld()
    W.items["101:0"].pawnBlind = true
    UpgradeScoutDB = { engine = "pawn" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(ns.Pawn.Item(W.Link(101)), nil, "a ring with stats that Pawn gave nothing for: no answer yet")
    eq(ns.Score.Context(ARMS).unread, 1, "worn, it is gear still to be read")
    local slot = W.PutInBags(W.Link(200))
    W.OpenBags()
    local function Arrow()
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(Arrow(), false, "no arrow on the better chest while the ring is waited for")
    W.Run(2)
    eq(Arrow(), false, "nor two seconds later")
    W.Run(5)
    eq(Arrow(), true, "the wait is over: the arrows are drawn without the ring")
    -- Read at last (the gear is looked at again when it changes): nothing to wait for.
    W.items["101:0"].pawnBlind = nil
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    eq(ns.Score.Context(ARMS).unread, nil, "the ring read, the gear is whole")
    eq(Arrow(), true, "and the arrow stays")
    -- An item in the bags that Pawn cannot read gets no arrow, and keeps none from the rest.
    W.items["203:0"].pawnBlind = true
    local blind = W.PutInBags(W.Link(203))
    W.DrawBags()
    W.Run(12)
    local arrow = ContainerFrameCombinedBags.Items[blind].UpgradeScoutArrow
    eq(arrow ~= nil and arrow:IsShown(), false, "no arrow on an item Pawn cannot read")
    eq(Arrow(), true, "the others keep theirs")
    CheckPawnAsked("gear that Pawn cannot read")
end

-- With Pawn scoring, an effect the score leaves out is a line the game gives the item for a
-- spell of its own which Pawn could not turn into a number. A line another addon wrote into
-- the tooltip Pawn reads is none, though Pawn could not read it either.
function scenarios.pawn_effects()
    StandardWorld()
    PawnWorld()
    UpgradeScoutDB = { engine = "pawn" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score = ns.Score
    local good = W.items["200:0"]
    local function Effects(id) return Score.HasUnscoredEffects(Score.Item(W.Link(id))) end
    eq(Score.Engine(), "pawn", "Pawn scores")
    eq(Effects(201), true, "a use Pawn could not read"); eq(Effects(200), false, "an item of plain stats")

    -- Another addon puts the item's number under every item, in Pawn's tooltip as well.
    W.pawn.foreign = { "ItemID", "IconID" }
    check(Score.Item(W.Link(200)).pawn.UnknownLines.ItemID ~= nil, "(Pawn could not read the other addon's line)")
    eq(Effects(200), false, "a line of another addon's is no effect of the item")
    eq(Effects(201), true, "the item's own use still is one")

    -- What the item does while worn: counted where Pawn read the line.
    good.equipLine, good.pawnCounts = true, true
    eq(Effects(200), false, "a line of what it does while worn, read by Pawn")
    good.pawnCounts = nil
    eq(Effects(200), true, "the same line, not read by Pawn")
    good.equipLine, good.procLine = nil, true
    eq(Effects(200), true, "a chance on hit")
    good.procLine = nil

    -- Pawn keeps the piece it stumbled on where it took a line apart, and has taken the
    -- colour off the line it read.
    local great = W.items["201:0"]
    great.pawnUnknown = { "Does something." }
    eq(Effects(201), true, "a piece of the item's line")
    great.pawnUnknown = { "|cffffffffUse: Does something.|r" }
    eq(Effects(201), true, "the line in a colour")
    great.pawnUnknown = { "Use: Does nothing." }
    eq(Effects(201), false, "a line the item does not have")
    -- In French the game writes a space that does not break, and Pawn a plain one.
    local use = ITEM_SPELL_TRIGGER_ONUSE
    ITEM_SPELL_TRIGGER_ONUSE = "Utiliser\194\160:"
    great.pawnUnknown = { "Utiliser : Does something." }
    eq(Effects(201), true, "the line with Pawn's plain space")
    ITEM_SPELL_TRIGGER_ONUSE = use
    great.pawnUnknown = nil

    -- Without a tooltip to read, the game's tables, as for the addon's own weights.
    local tooltip = C_TooltipInfo.GetHyperlink
    C_TooltipInfo.GetHyperlink = function() return nil end
    eq(Effects(201), false, "no tooltip, and the item is not in the tables")
    ns.GearData.newest, ns.GearData.effects[201] = 1000, true
    eq(Effects(201), true, "no tooltip: the tables' list")
    ns.GearData.newest, ns.GearData.effects[201] = 0, nil
    C_TooltipInfo.GetHyperlink = tooltip

    -- The list: the mark stands on the robe and on nothing else.
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    ScanToEnd()
    eq(Offer("Great Chest").effects, true, "the robe is marked")
    for _, name in ipairs({ "Good Chest", "New Ring", "Helm", "Big Axe", "Shield" }) do
        eq(Offer(name).effects, false, name .. " is not, with the other addon's lines under it")
    end
    CheckPawnAsked("effects with another addon's lines")
end

-- What a consumable adds, scored on a Pawn scale: the game's names for stats put into
-- Pawn's, and a chance into the percentage Pawn reads.
function scenarios.pawn_supplies()
    StandardWorld()
    SuppliesWorld()
    PawnWorld()
    UpgradeScoutDB = { engine = "pawn" }
    LoadAddon()
    SupplyFacts()
    local Score = ns.Score
    eq(Score.Engine(), "pawn", "Pawn scores")

    near(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_AGILITY_SHORT = 4 }, ARMS), 8 * 1.5 + 4, "stats under Pawn's names, by the scale's weights")
    local call = W.pawn.calls[#W.pawn.calls]
    eq(call.scale, ARMS, "Pawn makes the sum itself, on the scale"); eq(call.stats.Strength, 8, "of the stats by its own names")
    eq(call.level, nil, "for no item level"); eq(call.socketBonus, nil, "and no sockets")
    eq(call.debug, false, "without its debug lines"); eq(call.noNormalization, false, "as it sums an item")
    eq(call.noReforging, true, "and nothing to reforge")

    near(Score.StatsValue({ ITEM_MOD_CRIT_RATING_SHORT = 28 }, ARMS), 2 * 8, "a chance: 28 points of rating are the 2% Pawn reads")
    near(Score.StatsValue({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, ARMS), 2 * 8, "a chance with weapons counts on a fighter's scale")
    near(Score.StatsValue({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, BALANCE), 0, "and not on a caster's")
    near(Score.StatsValue({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, BALANCE), 6, "a chance with spells counts on a caster's scale")
    near(Score.StatsValue({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, ARMS), 0, "and not on a fighter's")
    near(Score.StatsValue({ ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, BALANCE), 12, "both kinds add up for the one who uses both")
    near(Score.StatsValue({ ITEM_MOD_ATTACK_POWER_SHORT = 10 }, ARMS), 4, "attack power under the name gear's has in Pawn")
    near(Score.StatsValue({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 36 }, BALANCE), 36, "spell damage")
    near(Score.StatsValue({ ITEM_MOD_HEALTH_SHORT = 25 }, ARMS), 2 * 0.5, "health as the Stamina that gives it: Pawn has no weight for it")
    near(Score.StatsValue({ ITEM_MOD_MANA_SHORT = 30 }, BALANCE), 2, "mana as Intellect")
    near(Score.StatsValue({ ITEM_MOD_UNHEARD_OF_SHORT = 99 }, ARMS), 0, "a stat Pawn has no name for counts for nothing")
    near(Score.StatsValue({ ITEM_MOD_SPIRIT_SHORT = 8 }, ARMS), 0, "nor does one the scale does not weigh")
    eq(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8 }, "Gone"), nil, "no answer for a scale there is not")
    eq(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8 }, "S1"), nil, "nor for one of the addon's own profiles")

    -- The list of consumables is scored on the scale.
    W.OpenAuctionHouse()
    ScanSupplies()
    local rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(ARMS, { mana = false }))
    local function Value(name)
        for _, row in ipairs(rows) do
            if row.kind == "supply" and row.entry.supply.name == name then return row.entry.value end
        end
    end
    near(Value("Elixir of Giants"), 25 * 1.5, "an elixir of Strength on Arms"); near(Value("Elixir of Agility"), 15, "one of Agility")
    eq(Value("Elixir of Wisdom"), nil, "Intellect is of no use on that scale")
    rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(BALANCE, { mana = true }))
    near(Value("Elixir of Wisdom"), 6, "and worth its weight on a caster's")
    -- The heading over a consumable's score says whose score it is.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    ns.Tooltip.AddHeader(GameTooltip, "Arms", true)
    local heading = GameTooltip._lines[#GameTooltip._lines]
    check(heading.text:find("Upgrade Scout (Pawn score)", 1, true) ~= nil, "a heading over a score, with Pawn scoring: " .. heading.text)
    eq(heading.right, "Arms", "with what stands on its right")
    ns.Tooltip.AddHeader(GameTooltip)
    heading = GameTooltip._lines[#GameTooltip._lines]
    eq(heading.text:find("Pawn", 1, true), nil, "a heading over notes alone names no Pawn")
    CheckPawnAsked("consumables")
end

-- Another character of the account: the Pawn scales it has switched on, as Pawn's own notes
-- say, or those of its class where Pawn has no notes about it.
function scenarios.pawn_alt()
    StandardWorld()
    local warrior, warriorGear = W.player, W.equipped
    W.AddItem({ id = 300, name = "Alt's Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 12, D2 = 3 }, level = 15 })
    W.AddItem({ id = 310, name = "Druid Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 20, D2 = 2 }, level = 18 })
    W.AddAuction(310, 2000)
    PawnWorld()
    UpgradeScoutDB = { engine = "pawn" }

    -- The druid is played once.
    W.Login(Druid())
    W.equipped = { [5] = W.Link(300) }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(ns.Score.Current(), nil, "the druid has no scale switched on in Pawn: none in use")
    Relog(warrior, warriorGear)
    local Score, S = ns.Score, ns.Scanner
    local card = UpgradeScoutDB.chars["Alty-Testrealm"]
    check(card ~= nil, "the druid is remembered")

    -- Pawn has no notes about the druid: the scales of its class.
    local _, theirs = Score.Current(card)
    eq(#theirs, 2, "a character Pawn has no notes about: the scales of its class")
    eq(theirs[1].name, BALANCE, "by Pawn's names"); eq(theirs[1].title, "Balance", "shown without the class")
    eq(theirs[2].title, "Feral", "each of them")
    -- Pawn has notes: what the druid has switched on.
    PawnCommon.Scales[FERAL].PerCharacterOptions["Alty-Testrealm"] = { Visible = true }
    PawnCommon.Scales["Leveling"].PerCharacterOptions["Alty-Testrealm"] = { Visible = true }
    PawnCommon.Scales[BALANCE].PerCharacterOptions["Alty-Testrealm"] = { Visible = false }
    _, theirs = Score.Current(card)
    eq(#theirs, 2, "a character Pawn has notes about: the scales it has switched on")
    eq(theirs[1].name, "Leveling", "one made by hand among them"); eq(theirs[2].name, FERAL, "and not the ones it has switched off")
    PawnCommon.Scales[BALANCE].PerCharacterOptions["Alty-Testrealm"] = { Visible = true }
    PawnCommon.Scales["Leveling"].PerCharacterOptions["Alty-Testrealm"] = nil
    eq(#Score.Profiles(ns.Roster.Me()), 3, "the card of the character being played is that character")

    -- At the auction house the field lists them under the warrior's own.
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    local ALTY = "|cffff7c0aAlty|r"
    eq(#dropdown.radios, 5, "three scales of the warrior and two of the druid")
    eq(dropdown.radios[4].text, ALTY .. ": Balance", "the druid's by its name and the scale's")
    eq(dropdown.radios[5].text, ALTY .. ": Feral", "each of them")
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(4)
    eq(ns.Roster.Target(), card, "the lists are for the druid"); eq(card.scale, BALANCE, "on the scale chosen, written on its card")
    eq(card.profile, nil, "apart from the addon's own profile")
    frame.ScanButton:Click()
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(1)
    eq(S.ctx.who, card, "the scan was for the druid"); eq(S.ctx.profile, BALANCE, "on its scale")
    near(S.ctx.equipped[5].value, 12, "its chest by Pawn's number on that scale")
    check(Offer("Druid Jerkin") ~= nil, "a jerkin better than the druid's"); near(Offer("Druid Jerkin").value, 20, "by Pawn's number")
    eq(Offer("Good Chest"), nil, "the warrior's upgrades are not the druid's")

    -- A row's tooltip keeps our lines here: Pawn's are about the character being played.
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    local jerkin
    for _, w in ipairs(scrollBox:GetFrames()) do
        local entry = w._shown and w._kind == "Button" and w.entry or nil
        if entry and entry.offer and entry.offer.name == "Druid Jerkin" then jerkin = w end
    end
    check(jerkin ~= nil, "the jerkin is in the list")
    jerkin:GetScript("OnEnter")(jerkin)
    local doubles = {}
    for _, line in ipairs(GameTooltip._lines) do
        if line.right then doubles[#doubles + 1] = line end
    end
    eq(doubles[1].right, ALTY, "a list for another character: our header, which says whose")
    check(doubles[1].text:find("Upgrade Scout (Pawn score)", 1, true) ~= nil, "and that the score in our lines is Pawn's: " .. doubles[1].text)
    eq(doubles[2].text, "Balance", "then the druid's scales"); eq(doubles[2].right, "+67%", "with the gain on each: 20 against 12")
    eq(doubles[3].text, "Feral", "on the other one"); eq(doubles[3].right, "-33%", "2 against 3")
    eq(ShoppingTooltip1:IsShown(), true, "and the druid's chest beside it")
    jerkin:GetScript("OnLeave")(jerkin)

    -- One line for the scale in use: it says whose score it is after the scale's name.
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    jerkin:GetScript("OnEnter")(jerkin)
    local single = GameTooltip._lines[#GameTooltip._lines]
    check(single.text:find(ALTY .. ": Balance (Pawn score)", 1, true) ~= nil, "\"Only my spec\": one line, with whose score it is: " .. single.text)
    eq(single.right, "+67%", "and the gain")
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")

    -- Pawn writes into the game's tooltips what an item is to the character being played. In
    -- a list for another character that is kept out, of the row's tooltip and of the one
    -- beside it, and Pawn's options are afterwards as the player has them.
    W.pawn.writes = true
    local function PawnLine(tooltip)
        for _, line in ipairs(tooltip._lines) do
            if line.text:find("Pawn:", 1, true) then return line.text end
        end
    end
    local function Row(name)
        for _, w in ipairs(scrollBox:GetFrames()) do
            local entry = w._shown and w._kind == "Button" and w.entry or nil
            if entry and entry.offer and entry.offer.name == name then return w end
        end
    end
    local function ListFor(index)
        dropdown:Pick(index)
        W.Run(0.5)
        if S.state == "idle" then frame.ScanButton:Click() end
        W.RunUntil(function() return S.state == "idle" end, 300)
        W.Run(1)
    end
    local function Elsewhere()
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink(W.Link(310))
        return PawnLine(GameTooltip)
    end
    eq(Elsewhere(), "Pawn: upgrade", "anywhere else Pawn writes its line"); eq(GameTooltip._border, "green", "and colours the border")
    ShoppingTooltip1._border = "green"
    jerkin:GetScript("OnEnter")(jerkin)
    eq(PawnLine(GameTooltip), nil, "a row for another character: Pawn's line is kept out")
    eq(PawnLine(ShoppingTooltip1), nil, "and out of the tooltip of what that character wears")
    eq(GameTooltip._lines[#GameTooltip._lines].right, "-33%", "our lines are there as before")
    -- They are all that says the score there, so they do not go by the box of our lines on
    -- the tabs: a player who unticked it while the addon scored is not left with nothing.
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    jerkin:GetScript("OnEnter")(jerkin)
    eq(GameTooltip._lines[#GameTooltip._lines].right, "-33%", "our lines unticked for the tabs: they still stand in a list for another character")
    eq(PawnLine(GameTooltip), nil, "with none of Pawn's")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(GameTooltip._border, "white", "Pawn takes back a border it had coloured"); eq(ShoppingTooltip1._border, "white", "on both")
    eq(PawnCommon.ShowUpgradesOnTooltips, true, "Pawn's options are as they were"); eq(PawnCommon.ShowValuesForUpgradesOnly, true, "both")
    jerkin:GetScript("OnLeave")(jerkin)
    -- A player who has Pawn show an item's values, and no upgrades.
    PawnCommon.ShowUpgradesOnTooltips, PawnCommon.ShowValuesForUpgradesOnly = false, false
    eq(Elsewhere(), "Pawn: value", "values shown beside every item")
    jerkin:GetScript("OnEnter")(jerkin)
    eq(PawnLine(GameTooltip), nil, "they are kept out as well"); eq(PawnLine(ShoppingTooltip1), nil, "of both tooltips")
    eq(PawnCommon.ShowUpgradesOnTooltips, false, "and the options are as that player has them"); eq(PawnCommon.ShowValuesForUpgradesOnly, false, "both")
    jerkin:GetScript("OnLeave")(jerkin)
    PawnCommon.ShowUpgradesOnTooltips, PawnCommon.ShowValuesForUpgradesOnly = true, true
    -- Something goes wrong while the tooltip is filled in: the error passes on, with Pawn's
    -- options put back.
    local passed
    local ok, problem = pcall(ns.Pawn.Hushed, function(what) passed = what error("no such item", 0) end, "a link")
    eq(ok, false, "an error in filling the tooltip in passes on"); eq(problem, "no such item", "as it was")
    eq(passed, "a link", "what fills it in is called with what it was given")
    eq(PawnCommon.ShowUpgradesOnTooltips, true, "and Pawn's options are put back all the same"); eq(PawnCommon.ShowValuesForUpgradesOnly, true, "both")

    -- The warrior's own list: Pawn writes there as everywhere.
    ListFor(2)
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own again")
    local chest = Row("Good Chest")
    check(chest ~= nil, "a better chest for the warrior is in the list")
    chest:GetScript("OnEnter")(chest)
    eq(PawnLine(GameTooltip), "Pawn: upgrade", "a row of the player's own list: Pawn's line, as anywhere")
    chest:GetScript("OnLeave")(chest)
    CheckPawnAsked("another character")

    -- The addon's own weights chosen, with Pawn still installed: Pawn writes into tooltips
    -- as before, and is kept out of a list for another character the same way.
    ns.Score.SetEngine(nil)
    W.Run(1)
    W.RunUntil(function() return S.state == "idle" end, 300)
    ListFor(3)
    eq(ns.Roster.Target(), card, "the addon scores, and the lists are for the druid")
    jerkin = Row("Druid Jerkin")
    check(jerkin ~= nil, "the jerkin is in the druid's list by the addon's own weights")
    jerkin:GetScript("OnEnter")(jerkin)
    eq(PawnLine(GameTooltip), nil, "the addon scoring: Pawn's line is kept out of a row for another character")
    eq(PawnLine(ShoppingTooltip1), nil, "and of what that character wears")
    local ours, marked = false, false
    for _, line in ipairs(GameTooltip._lines) do
        if line.right == ALTY then ours = true end
        if line.text:find("Pawn score", 1, true) then marked = true end
    end
    eq(ours, true, "under our header, which says whose list it is")
    eq(marked, false, "and names no Pawn: the score is the addon's own")
    jerkin:GetScript("OnLeave")(jerkin)
    -- With the addon scoring its lines go by their box, in a list for another character too.
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    jerkin:GetScript("OnEnter")(jerkin)
    ours = false
    for _, line in ipairs(GameTooltip._lines) do
        if line.right == ALTY then ours = true end
    end
    eq(ours, false, "the addon scoring, its lines unticked for the tabs: none under the row")
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Elsewhere(), "Pawn: upgrade", "and Pawn writes on everywhere else")

    -- Without Pawn there is nobody to keep out: the tooltip is filled in and no more.
    W.RemovePawn()
    local filled
    ns.Pawn.Hushed(function(what) filled = what end, "a link")
    eq(filled, "a link", "no Pawn: what fills the tooltip in is called")
end

---------------------------------------------------------------------------
-- Forever Companion in place of the addon's own weights (Companion.lua), for a player who
-- chose it
---------------------------------------------------------------------------
-- The keys of the scales it comes with here: a warrior's two and a druid's two, one for each
-- of the two talent trees the tests' classes have profiles for.
local FURY, TANK, MOON, CAT = "wh:1", "wh:2", "wh:3", "wh:4"

-- Forever Companion is installed, with those four scales. The warrior's first weighs an
-- item's first score, as the addon's own first profile does, and its second the second; the
-- druid's weigh the scores the tests give an item for a druid.
local function CompanionWorld()
    W.InstallCompanion()
    W.AddCompanionScale("WARRIOR", { id = 1, label = "Fury DPS", tab = 1,
        w = { TEST_S1 = 1, Strength = 1.5, Agility = 1, Stamina = 0.5, Ap = 0.4, CritRating = 8 } })
    W.AddCompanionScale("WARRIOR", { id = 2, label = "Mitigation Tank", tab = 2, w = { TEST_S2 = 1, Stamina = 1 } })
    W.AddCompanionScale("DRUID", { id = 3, label = "Balance DPS", tab = 1,
        w = { TEST_D1 = 1, Intellect = 1, SpellPower = 1, CritRating = 6 } })
    W.AddCompanionScale("DRUID", { id = 4, label = "Feral DPS", tab = 2, w = { TEST_D2 = 1, Agility = 1 } })
end

-- Forever Companion was asked about no item with its enchantment on.
local function CheckCompanionAsked(label)
    for _, link in ipairs(W.companion.asked) do
        check(not link:match("item:%d+:%d"), label .. ": Forever Companion is asked about an item without its enchantment")
    end
end

-- Has the tooltip Forever Companion's own line?
local function CompanionLine(tooltip)
    for _, line in ipairs(tooltip._lines) do
        if line.text:find("Companion:", 1, true) then return true end
    end
    return false
end

-- Has it Forever Companion's lists of the best gear?
local function CompanionList(tooltip)
    for _, line in ipairs(tooltip._lines) do
        if line.text:find("Companion best:", 1, true) then return true end
    end
    return false
end

-- The road of a player who has Forever Companion: the addon scores by itself until it is
-- chosen, then on the scale it has in use, and the lists are made the same way from its
-- numbers.
function scenarios.companion_scan()
    StandardWorld()
    -- The worn chest is enchanted. On the second score: the two chests 9 (for sale) and 12
    -- (worn), a helm, a two-hander and a shield.
    W.equipped[5] = (W.Link(100):gsub("item:100:", "item:100:66", 1))
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["211:0"].value2, W.items["212:0"].value2, W.items["213:0"].value2 = 5, 40, 8
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    CompanionWorld()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score, S, me = ns.Score, ns.Scanner, ns.Roster.Me()
    local companion = ForeverCompanion
    local function Idle() return S.state == "idle" end

    -- It is there and not chosen: the addon scores by itself and asks it nothing.
    eq(ns.Companion.Usable(), true, "Forever Companion is there to be asked"); eq(Score.Engine(), nil, "and is not, until chosen")
    eq(Score.Current().name, "S1", "the profiles are the addon's own")
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    ScanToEnd()
    CheckStandardOffers("the addon's own weights, with Forever Companion installed")
    eq(#W.companion.asked, 0, "Forever Companion is asked about no item")
    eq(#dropdown.radios, 2, "the field lists the addon's profiles"); eq(dropdown:GetText(), "Arms", "the one in use")

    -- Chosen, as the welcome window does it: for the whole account, and at once.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    Score.SetEngine("companion")
    eq(UpgradeScoutDB.engine, "companion", "the choice is written down for the account"); eq(Score.Engine(), "companion", "and Forever Companion scores")
    eq(told, 1, "what keeps scores is told")
    local current, list = Score.Current()
    eq(#list, 2, "the profiles are the scales Forever Companion has for the class")
    eq(list[1].name, FURY, "by its keys, in its order"); eq(list[1].title, "Fury DPS", "each by the name it shows it by")
    eq(list[2].name, TANK, "the second"); eq(list[2].title, "Mitigation Tank", "by its name")
    eq(current.name, FURY, "the one in use: the one Forever Companion has for the talents")
    eq(Score.Title(TANK), "Mitigation Tank", "a scale's title by its key"); eq(Score.IsApprox(FURY), false, "no scale is marked as an estimate")
    eq(#Score.Trees(), 2, "the addon's own profiles are still there to be asked for")

    -- The list that was there is made again, on the scale.
    check(S.state ~= "idle", "a list that was made on the addon's weights is made again")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, FURY, "on the scale in use")
    CheckStandardOffers("Forever Companion's scale for the first tree")
    near(S.ctx.equipped[5].value, 10, "what is worn is scored on it, without its enchantment")
    near(S.ctx.equipped[16].value, 20, "every piece of it")
    eq(S.ctx.show1H, true, "the scale is offered one-handed weapons"); eq(S.ctx.show2H, true, "and two-handed ones")
    CheckCompanionAsked("a scan")
    eq(#dropdown.radios, 2, "the field lists the scales"); eq(dropdown.radios[1].text, "Fury DPS", "by their names")
    eq(dropdown:GetText(), "Fury DPS", "and shows the one in use")
    dropdown._tooltip(GameTooltip)
    local tip = {}
    for _, line in ipairs(GameTooltip._lines) do tip[#tip + 1] = line.text end
    check(table.concat(tip, " | "):find(ns.L.PROFILE_TIP_COMPANION, 1, true) ~= nil, "its tooltip is about Forever Companion's scales")

    -- Another scale chosen in the field: it is chosen in Forever Companion, whose own line
    -- in a tooltip and whose own arrows go by the scale it has in use.
    local refreshes = W.companion.refreshes
    dropdown:Pick(2)
    eq(companion.db.char.scale, TANK, "the scale chosen in the field is chosen in Forever Companion")
    eq(W.companion.refreshes, refreshes + 1, "which is told to draw its marks again")
    eq(me.companion, nil, "nothing of it is written on the card of the character being played")
    eq(me.profile, nil, "the addon's own profile is left alone"); eq(me.scale, nil, "and so is the Pawn scale")
    W.RunUntil(Idle, 600)
    W.Run(0.5)
    eq(told, 1, "a choice made here is no news from Forever Companion: the list is made once")
    eq(S.ctx.profile, TANK, "the list is on the scale chosen")
    check(Offer("Helm") ~= nil, "a helm for the empty head, by its score on that scale")
    check(Offer("Shield") ~= nil, "a shield for the empty off hand")
    check(Offer("Big Axe") ~= nil, "and a two-hander: a scale of Forever Companion's rules no weapon out")
    eq(Offer("Good Chest"), nil, "the chest is no upgrade on it: 9 against 12")
    eq(OfferCount(), 3, "and nothing else")

    -- /upscout stats: the stats as Forever Companion reads them and the scale's weights.
    W.items["200:0"].companion = { Strength = 5 }
    local at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats " .. W.Link(200))
    local said = Said(at)
    check(said:find('on the profile "Mitigation Tank": score 9', 1, true) ~= nil, "the scale in use and the score on it: " .. said)
    check(said:find("TEST_S2: 9 × 1 = 9", 1, true) ~= nil, "a stat by Forever Companion's name for it, with the scale's weight")
    check(said:find("Strength", 1, true) == nil, "a stat the scale does not weigh is left out")
    W.items["200:0"].companion = nil

    -- The scale's weights are changed in Forever Companion's own window: the addon hears of
    -- it, and the list is made again.
    local tank = W.companion.data.WARRIOR[2].w
    tank.TEST_S2 = 3
    W.CompanionChanged()
    W.Run(0.5)
    eq(told, 2, "its scales changed: what keeps scores is told")
    W.RunUntil(Idle, 600)
    near(Offer("Helm").value, 15, "the list is on the new weights")
    -- It draws its marks again for other reasons too (the gear changed): no scale changed.
    W.CompanionChanged()
    W.Run(0.5)
    eq(told, 2, "its marks drawn again with its scales as they were: nothing is told"); eq(S.state, "idle", "and the list stays")
    tank.TEST_S2 = 4
    W.CompanionChanged()
    tank.TEST_S2, tank.Stamina = 1, 2
    W.CompanionChanged()
    W.Run(0.5)
    eq(told, 3, "a burst of changes is one telling")
    W.RunUntil(Idle, 600)

    -- Another scale chosen in Forever Companion's own options: the list follows.
    companion.db.char.scale = FURY
    W.CompanionChanged()
    W.Run(0.5)
    eq(told, 4, "another scale chosen there: what keeps scores is told")
    eq(Score.Current().name, FURY, "the scale in use is the one it has in use")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, FURY, "the list follows"); eq(dropdown:GetText(), "Fury DPS", "and so does the field")

    -- A scale the player made there, for the account.
    W.AddCompanionCustom({ name = "Leveling", class = "WARRIOR", w = { TEST_S1 = 2 } })
    W.CompanionChanged()
    W.Run(0.5)
    eq(told, 5, "a scale made: the scales changed")
    W.RunUntil(Idle, 600)
    eq(#dropdown.radios, 3, "the field lists it"); eq(dropdown.radios[3].text, "Leveling", "after the ones that come with the addon")
    dropdown:Pick(3)
    eq(companion.db.char.scale, "my:1", "chosen, by its own key")
    W.RunUntil(Idle, 600)
    near(Offer("Good Chest").value, 36, "its own weights: 18 twice over"); near(S.ctx.equipped[5].value, 20, "for what is worn as well")
    -- Taken away while in use: the one for the talents takes its place.
    table.remove(companion.db.global.custom_scales, 1)
    W.CompanionChanged()
    W.Run(0.5)
    eq(told, 6, "a scale taken away")
    eq(Score.Current().name, FURY, "a scale that is gone gives way to the one for the talents")
    eq(#dropdown.radios, 2, "and is no longer in the field"); eq(dropdown:GetText(), "Fury DPS", "which shows the one in use")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, FURY, "the list follows")

    -- With no scale chosen there, Forever Companion picks the one for the talents: other
    -- talents, another scale.
    W.player.talents = { { name = "Arms", points = 1 }, { name = "Fury", points = 9 }, { name = "Protection", points = 0 } }
    W.Fire("TRAIT_CONFIG_UPDATED")
    W.Run(1.5)
    eq(Score.Current().name, TANK, "other talents: the scale Forever Companion picks for them"); eq(told, 7, "and what keeps scores is told")
    W.RunUntil(Idle, 600)
    -- The same found out with nobody saying so: its answer is asked for again after a moment.
    W.player.talents = { { name = "Arms", points = 9 }, { name = "Fury", points = 1 }, { name = "Protection", points = 0 } }
    local counted = W.companion.counted
    for _ = 1, 20 do Score.Current() end
    eq(W.companion.counted, counted, "asked many times in a moment, the talents are not counted each time")
    W.Run(3)
    eq(Score.Current().name, FURY, "an answer grown old is asked for again")
    W.Run(0.5)
    eq(told, 8, "and, being new, told")
    W.RunUntil(Idle, 600)

    -- No scale for the class: no scan, and the reason.
    local kept = W.companion.data.WARRIOR
    W.companion.data.WARRIOR = {}
    W.CompanionChanged()
    W.Run(0.5)
    eq(Score.Current(), nil, "no scale for the class: none in use")
    eq(S.Start(), false, "and no scan"); eq(S.message, ns.L.ERR_NO_SCALE_COMPANION, "which says why")
    W.companion.data.WARRIOR = kept
    W.CompanionChanged()
    W.Run(0.5)
    W.RunUntil(Idle, 600)
    CheckCompanionAsked("scales coming and going")

    -- Back to the addon's own weights: its profile is where it was left.
    Score.SetEngine(nil)
    eq(UpgradeScoutDB.engine, nil, "the addon's own weights chosen again: nothing is left written")
    eq(Score.Current().name, "S1", "the addon's profile as it was")
    W.RunUntil(Idle, 600)
    eq(#dropdown.radios, 2, "the field lists the addon's profiles again")
    local asked = #W.companion.asked
    ScanToEnd()
    CheckStandardOffers("the addon's own weights again")
    eq(#W.companion.asked, asked, "and Forever Companion is asked nothing")

    -- Another character of the account: the scale chosen for it in the addon's field, then
    -- the one chosen for it in Forever Companion, then the one for its talents.
    Score.SetEngine("companion")
    eq(Score.Current({ key = "P", class = "DRUID", talents = "D2" }).title, "Feral DPS", "another character: the scale for the tree its talents are in")
    eq(Score.Current({ key = "P", class = "DRUID" }).title, "Balance DPS", "without talents known: the first for dealing damage")
    eq(Score.Current({ key = "P", class = "DRUID", talents = "D2", companion = MOON }).title, "Balance DPS", "under the scale chosen for it in the addon's field")
    companion.db.sv.char["Alty - PvE"] = { scale = CAT }
    local alt = { key = "Alty-Testrealm", name = "Alty", realm = "Testrealm", class = "DRUID", talents = "D1" }
    eq(Score.Current(alt).title, "Feral DPS", "the scale chosen for it in Forever Companion's own options comes before its talents")
    alt.realm = "Elsewhere"
    eq(Score.Current(alt).title, "Balance DPS", "which cannot be told of a character of another realm")
    -- A priest has three trees and two profiles here, and Forever Companion no scale for the first.
    ns.Weights.classes.PRIEST = { "PRIEST_HEALER", "PRIEST_SHADOW" }
    W.AddCompanionScale("PRIEST", { id = 5, label = "Healer", tab = 2, w = { Healing = 1 } })
    W.AddCompanionScale("PRIEST", { id = 6, label = "Shadow DPS", tab = 3, w = { SpellPower = 1 } })
    W.CompanionChanged()
    W.Run(0.5)
    eq(Score.Current({ key = "P", class = "PRIEST", talents = "PRIEST_SHADOW" }).title, "Shadow DPS", "a priest's Shadow is the third tree")
    eq(Score.Current({ key = "P", class = "PRIEST", talents = "PRIEST_HEALER" }).title, "Healer", "its healer the second")
    eq(Score.Current({ key = "P", class = "PRIEST" }).title, "Shadow DPS", "without talents known: the first for dealing damage")
    eq(Score.Current({ key = "P", class = "MAGE" }), nil, "a class it has no scale for: none")
    CheckCompanionAsked("another character's scales")
end

-- Forever Companion chosen and not there: the addon scores by itself, and the choice stands.
function scenarios.companion_absent()
    StandardWorld()
    UpgradeScoutDB = { engine = "companion" }
    LoadAddon()
    local Score = ns.Score
    eq(ns.Companion.Usable(), false, "Forever Companion is not installed"); eq(Score.Engine(), nil, "so the addon scores, though it was chosen")
    eq(Score.Current().name, "S1", "on its own profiles")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("Forever Companion chosen and not installed")
    eq(UpgradeScoutDB.engine, "companion", "the choice stands for when it is back")

    -- It is there but has not opened what it keeps yet, as while it loads.
    CompanionWorld()
    local db = ForeverCompanion.db
    ForeverCompanion.db = nil
    eq(ns.Companion.Usable(), false, "before it has opened what it keeps it cannot be asked"); eq(Score.Engine(), nil, "and is not")
    eq(Score.Current().name, "S1", "the addon's profiles meanwhile")
    ForeverCompanion.db = db
    eq(Score.Engine(), "companion", "once it has, it scores, as chosen")
    eq(Score.Current().name, FURY, "on the first of its scales for dealing damage, with no talents to go by")

    -- One without a function the addon calls is one that cannot be asked.
    local kept = ForeverCompanion.Scales.ReadItem
    ForeverCompanion.Scales.ReadItem = nil
    eq(ns.Companion.Usable(), false, "a Forever Companion that lacks a function the addon calls"); eq(Score.Engine(), nil, "leaves the scoring to the addon")
    ForeverCompanion.Scales.ReadItem = kept
    local scales = ForeverCompanion.Scales
    ForeverCompanion.Scales = nil
    eq(ns.Companion.Usable(), false, "and so does one without its scales")
    ForeverCompanion.Scales = scales
    eq(Score.Engine(), "companion", "with everything in place it scores")

    -- Switched off for the next session: the addon's weights again, without a word.
    Relog(W.player, W.equipped)
    W.RemoveCompanion()
    eq(ns.Score.Engine(), nil, "Forever Companion switched off: the addon scores")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("Forever Companion switched off")
    eq(UpgradeScoutDB.engine, "companion", "and the choice still stands")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- With Forever Companion scoring: while it writes its own line and draws its own arrows, none
-- of ours beside them; with either switched off in its options, ours in its place, on its scales.
function scenarios.companion_tooltips()
    StandardWorld()
    W.AddItem({ id = 220, name = "Oak Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subClassID = 19, value = 9, level = 5 })
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["212:0"].value2 = 40
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    -- A shirt and a trinket that is only used, as most characters wear.
    W.AddItem({ id = 230, name = "Lucky Charm", equipLoc = "INVTYPE_TRINKET", value = 0, level = 1, noStats = true })
    W.equipped[4] = W.Link(207)
    W.equipped[13] = W.Link(230)
    CompanionWorld()
    W.companion.writes = true
    -- It was chosen in an earlier session.
    UpgradeScoutDB = { engine = "companion" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score = ns.Score
    local options = ForeverCompanion.db.global
    eq(ns.Companion.Item(W.Link(207)).companion, false, "a shirt is not gear: there is nothing to read, and that is an answer")
    eq(Score.Context(FURY).unread, nil, "wearing one, the gear is whole")
    eq(Score.Engine(), "companion", "Forever Companion scores, as chosen before"); eq(Score.Current().name, FURY, "on the scale for the talents")

    -- What an item does beyond its stats: a use and a chance on hit it reads none of; what
    -- the item does while worn it reads where it knows the words.
    local function Effects(id) return Score.HasUnscoredEffects(Score.Item(W.Link(id))) end
    local good = W.items["200:0"]
    eq(Effects(201), true, "a use: not counted"); eq(Effects(200), false, "an item of plain stats")
    good.equipLine = true
    eq(Effects(200), true, "what it does while worn, in words Forever Companion does not know")
    good.equipText = "+14 Attack Power."
    eq(Effects(200), false, "the same in words it knows: counted")
    good.equipLine, good.equipText, good.procLine = nil, nil, true
    eq(Effects(200), true, "a chance on hit")
    good.procLine = nil

    -- Does the tooltip have lines of ours? Our header, then what is under it, joined by " | ".
    local function Ours(tooltip)
        local header
        for i, line in ipairs(tooltip._lines) do
            if line.text:find("Upgrade Scout", 1, true) then header = i end
        end
        if not header then return nil end
        local out = {}
        for i = header + 1, #tooltip._lines do
            local line = tooltip._lines[i]
            out[#out + 1] = line.text .. (line.right and " " .. line.right or "")
        end
        return table.concat(out, " | ")
    end
    local function Shown(tooltip, id)
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetHyperlink(W.Link(id))
        return Ours(tooltip)
    end
    eq(Shown(GameTooltip, 200), nil, "no lines of ours for an item in the bags: Forever Companion writes its own")
    eq(CompanionLine(GameTooltip), true, "which is there")
    eq(Shown(ItemRefTooltip, 200), nil, "nor for a link in the chat")

    -- The arrows in the bags are Forever Companion's own: none of ours beside them.
    local function Bag(slot)
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local function Grey(slot) return ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow._grey end
    local slot = {}
    for _, id in ipairs({ 200, 202, 203, 204, 208, 212, 214, 220 }) do slot[id] = W.PutInBags(W.Link(id)) end
    W.OpenBags()
    W.Run(1)
    eq(Bag(slot[200]), false, "a better chest: no arrow of ours, Forever Companion draws its own")
    eq(Bag(slot[203]), false, "nor on one of a higher level"); eq(Bag(slot[212]), false, "nor on a two-hander")

    -- Its arrows in the bags switched off in its options: ours are drawn, by its scale.
    options.scale_badges_more = false
    W.CompanionChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "its own arrows in the bags switched off: ours, on a better chest, 18 against 10 on its scale")
    eq(Grey(slot[200]), false, "green: it can be put on now")
    eq(Bag(slot[203]), true, "a better chest of a higher level"); eq(Grey(slot[203]), true, "grey")
    eq(Bag(slot[212]), true, "a two-hander against the sword")
    eq(Bag(slot[202]), false, "not a weaker chest"); eq(Bag(slot[204]), false, "not mail the character has not learned")
    eq(Bag(slot[208]), false, "not a chest with nothing to read"); eq(Bag(slot[220]), false, "not a wand: a warrior never uses one")
    eq(Bag(slot[214]), false, "not a potion")
    -- They can be switched off and on as ever.
    UpgradeScoutDB.arrows = false
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(Bag(slot[200]), false, "ours switched off in the welcome window")
    UpgradeScoutDB.arrows = nil
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(Bag(slot[200]), true, "and on again")

    -- Another scale chosen, as in the welcome window: it is chosen in Forever Companion, and
    -- the arrows follow.
    ns.UI.ChooseProfile(TANK)
    W.Run(1)
    eq(ForeverCompanion.db.char.scale, TANK, "a scale chosen in the welcome window is chosen in Forever Companion")
    eq(Bag(slot[200]), false, "on the tank's scale the chest is no upgrade: 9 against 12")
    eq(Bag(slot[212]), true, "and the two-hander is one: 40 against nothing")
    ns.UI.ChooseProfile(FURY)
    W.Run(1)
    eq(Bag(slot[200]), true, "back on the first scale the chest has its arrow")

    -- The scale's weights change in Forever Companion's own window.
    local fury = W.companion.data.WARRIOR[1].w
    fury.TEST_S1 = 0
    W.CompanionChanged()
    W.Run(1)
    eq(Bag(slot[200]), false, "a scale that weighs nothing: no arrows")
    fury.TEST_S1 = 1
    W.CompanionChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "the weights back, the arrow back")

    -- Its own arrows switched on again, by any of its three options for them: ours go.
    options.scale_badges_more = nil
    W.CompanionChanged()
    W.Run(1)
    eq(Bag(slot[200]), false, "its arrows in the bags switched on again: ours go")
    options.scale_arrows = false
    W.CompanionChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "its arrows switched off altogether: ours are back")
    options.scale_arrows = nil
    W.CompanionChanged()
    W.Run(1)
    eq(Bag(slot[200]), false, "and on: ours go")

    -- Its gear scales switched off altogether in its options: it writes no line and draws
    -- no arrow, and ours stand in for both, on its scales.
    options.scales_enabled = false
    W.CompanionChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "its gear scales switched off: our arrows")
    eq(Shown(GameTooltip, 200), "Fury DPS +80% | Mitigation Tank -25%", "and our lines in a tooltip, a line for each of its scales")
    eq(CompanionLine(GameTooltip), false, "with none of its own")
    local heading
    for _, line in ipairs(GameTooltip._lines) do
        if line.text:find("Upgrade Scout", 1, true) then heading = line.text end
    end
    check(heading:find("Upgrade Scout (Forever Companion score)", 1, true) ~= nil, "under a heading that says whose score it is: " .. heading)
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    Shown(GameTooltip, 200)
    local single = GameTooltip._lines[#GameTooltip._lines]
    check(single.text:find("Fury DPS (Forever Companion score)", 1, true) ~= nil, "\"Only my spec\": one line, with whose score it is: " .. single.text)
    eq(single.right, "+80%", "and the gain")
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")
    UpgradeScoutDB.tooltip = false
    ns.Fire("SETTING_CHANGED", "tooltip")
    eq(Shown(GameTooltip, 200), nil, "they go by their box in the welcome window, as with the addon scoring")
    UpgradeScoutDB.tooltip = nil
    ns.Fire("SETTING_CHANGED", "tooltip")
    options.scales_enabled = nil
    W.CompanionChanged()
    W.Run(1)
    eq(Shown(GameTooltip, 200), nil, "its gear scales switched on again: its line, and none of ours")
    eq(CompanionLine(GameTooltip), true, "its own is back"); eq(Bag(slot[200]), false, "and so are its arrows, for ours")

    -- A row of the list at the auction house.
    W.player.money = 50000
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    SetView(false, false)
    ScanToEnd()
    W.Run(1)
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    local function Row(name)
        for _, w in ipairs(scrollBox:GetFrames()) do
            local entry = w._shown and w._kind == "Button" and w.entry or nil
            if entry and entry.offer and entry.offer.name == name then return w end
        end
    end
    local function Under(name)
        local row = Row(name)
        check(row ~= nil, name .. " is in the list")
        W.compared = nil
        row:GetScript("OnEnter")(row)
        local ours, theirs = Ours(GameTooltip), CompanionLine(GameTooltip)
        row:GetScript("OnLeave")(row)
        return ours, theirs
    end
    local ours, theirs = Under("Good Chest")
    eq(ours, nil, "a row with nothing to add: no lines of ours, not even the addon's name")
    eq(theirs, true, "Forever Companion's line stands there, as anywhere"); eq(W.compared, GameTooltip, "and the worn item beside it as ever")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short",
        "a row with something to say about buying: that, under the addon's name, and no gains")
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short", "the score's box unticked: the notes stay")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    -- Its line switched off in its options: the gains under a row are ours to write, by their box.
    options.scale_tooltip = false
    W.CompanionChanged()
    W.Run(1)
    ours, theirs = Under("Good Chest")
    check(ours ~= nil and ours:find("Fury DPS +80%", 1, true) ~= nil, "its line switched off: the gains are ours to write under a row")
    eq(theirs, false, "with none of its own")
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Under("Good Chest"), nil, "and they go by their box")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    options.scale_tooltip = nil
    W.CompanionChanged()
    W.Run(1)
    CheckCompanionAsked("tooltips and arrows")

    -- The addon's own weights chosen again: its lines are back, and its arrows, which then
    -- stand beside Forever Companion's own: they are by other weights.
    Score.SetEngine(nil)
    W.Run(1)
    eq(Shown(GameTooltip, 200), "Arms +80% | Protection ~ -25% | Companion: value",
        "the addon scores again: its lines in the tooltip, and Forever Companion's own after them")
    eq(Bag(slot[200]), true, "and its arrows, by its own profile")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- The welcome window with Forever Companion: the third answer to who scores, its scales in
-- place of the trees, the tooltip's block and the arrows' card out of use while it writes
-- and draws its own, and the window coming up once for a player who has it.
function scenarios.companion_welcome()
    StandardWorld()
    W.AddItem({ id = 16999, name = "Royal Seal", equipLoc = "INVTYPE_FINGER", quality = 3, level = 54 })
    W.AddItem({ id = 5000, name = "Coral Band", equipLoc = "INVTYPE_FINGER", level = 21 })
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    local L

    -- Without it: the answer is there, and out of reach.
    LoadAddon()
    L = ns.L
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome ~= nil end, 10)
    local window = UpgradeScoutWelcome
    eq(#window.Engines, 4, "who scores: four answers, Forever Companion's the third")
    local own, pawn, theirs = window.Engines[1], window.Engines[2], window.Engines[3]
    eq(own.Label:GetText(), "Upgrade Scout", "the addon"); eq(pawn.Label:GetText(), "Pawn", "Pawn")
    eq(theirs.Label:GetText(), "Forever Companion", "and Forever Companion, each by its name")
    eq(own.Mark:IsShown(), true, "the addon is the one that does"); eq(theirs.Mark:IsShown(), false, "Forever Companion is not")
    eq(theirs:GetAlpha(), 0.45, "it cannot be chosen while it is not there: its button is grey")
    eq(theirs.Glow.parts[1]:IsShown(), false, "and does not light up under the mouse")
    local function Hint(button)
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        button:GetScript("OnEnter")(button)
        local said = GameTooltip._lines[1] and GameTooltip._lines[1].text or nil
        button:GetScript("OnLeave")(button)
        return said
    end
    eq(Hint(theirs), L.WELCOME_NO_COMPANION, "the mouse on its grey button: a tooltip says why")
    eq(Hint(pawn), L.WELCOME_NO_PAWN, "each grey button with its own reason"); eq(Hint(own), nil, "the addon's own has nothing to explain")
    theirs:Click()
    eq(UpgradeScoutDB.engine, nil, "a click on the grey button does nothing")
    check(own._points[1].x < pawn._points[1].x and pawn._points[1].x < theirs._points[1].x, "the three side by side")
    eq(own._points[1].y, theirs._points[1].y, "in one row"); near(own:GetWidth(), theirs:GetWidth(), "each as wide as the others")
    check(theirs._points[1].x + theirs:GetWidth() <= window:GetWidth() - 20 + 0.01, "and all of them inside the window")
    local height = window:GetHeight()
    window.Done:Click()
    eq(UpgradeScoutDB.welcomed, true, "seen"); eq(UpgradeScoutDB.companionOffered, nil, "but not with Forever Companion there to choose")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "without it the window does not come up by itself again")

    -- The player installs Forever Companion. The window comes up once more, and says why.
    CompanionWorld()
    Relog(W.player, W.equipped)
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome:IsShown() end, 10)
    L = ns.L
    window = UpgradeScoutWelcome
    eq(window.About:GetText(), L.WELCOME_COMPANION_NEW, "it is there now: the window comes up to say that it can be chosen")
    own, pawn, theirs = window.Engines[1], window.Engines[2], window.Engines[3]
    eq(theirs:GetAlpha(), 1, "its button is no longer grey"); eq(theirs.Glow.parts[1]:IsShown(), true, "and lights up under the mouse")
    eq(Hint(theirs), nil, "with nothing left to explain in a tooltip")
    eq(pawn:GetAlpha(), 0.45, "Pawn's is still grey: Pawn is not there")
    eq(own.Mark:IsShown(), true, "the addon scores until another is chosen")
    eq(window:GetHeight(), height, "the window is as tall as without it")

    -- Chosen.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    theirs:Click()
    eq(UpgradeScoutDB.engine, "companion", "a click chooses Forever Companion, for the account"); eq(told, 1, "and what keeps scores is told")
    eq(theirs.Mark:IsShown(), true, "its button is lit"); eq(own.Mark:IsShown(), false, "the addon's goes dark")
    eq(pawn.Mark:IsShown(), false, "and Pawn's stays so")
    local trees = window.Trees
    eq(trees[1].Label:GetText(), "Fury DPS", "the buttons are Forever Companion's scales for the class now")
    eq(trees[2].Label:GetText(), "Mitigation Tank", "by their names"); eq(trees[2]:IsShown(), true, "two of them")
    eq(trees[1].Mark:IsShown(), true, "the one in use is lit")
    eq(window.Ask:GetText(), L.WELCOME_SCALE_COMPANION:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")),
        "the question is about its scale, names the character, and stands alone")
    theirs:Click()
    eq(told, 1, "the one that scores clicked again: nothing changes")

    -- The score in a tooltip is Forever Companion's to write: the block says so, and what
    -- it asks of the score is out of use. The notes are still ours.
    local block, arrows = window.Tips, window.Pair[2]
    local tip, tabs, elsewhere, notes = block.Picture.Tip, block.Tabs, block.Elsewhere, block.Notes
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_COMPANION, "the tooltip's block says that Forever Companion writes there")
    for name, box in pairs({ ["the addon's tabs"] = tabs, ["the rest of the game"] = elsewhere }) do
        eq(box:IsEnabled(), false, "the score's box for " .. name .. " is out of use"); eq(box:GetChecked(), false, "and empty: " .. name)
        eq(box:GetAlpha(), 0.4, "and dim: " .. name)
    end
    eq(block.All:IsEnabled(), false, "the two buttons are out of use"); eq(block.All:GetAlpha(), 0.35, "and dim")
    eq(notes:IsEnabled(), true, "the box of the notes is in use"); eq(notes:GetChecked(), true, "and ticked")
    eq(tip.Note:IsShown(), true, "the picture has the note"); eq(tip.Lines[1].Title:IsShown(), false, "and no line of the score")

    -- The arrows in the bags are Forever Companion's own too: the card says so, and its box
    -- is empty, dim and out of use.
    local options = ForeverCompanion.db.global
    local slot = W.PutInBags(W.Link(200))
    W.OpenBags()
    W.Run(1)
    local function Arrow()
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(arrows.Body:GetText(), L.WELCOME_ARROWS_COMPANION, "the arrows' card says that Forever Companion draws them")
    eq(arrows.Switch:IsEnabled(), false, "its box is out of use"); eq(arrows.Switch:GetChecked(), false, "and empty")
    eq(arrows.Switch.Tick:IsShown(), false, "without its tick"); eq(arrows.Switch:GetAlpha(), 0.4, "and dim")
    eq(arrows.Title:GetAlpha(), 0.5, "as its name is"); eq(arrows.Picture:GetAlpha(), 0.3, "and the picture is faded")
    arrows.Switch:Click()
    eq(UpgradeScoutDB.arrows, nil, "a click on it changes nothing"); eq(Arrow(), false, "no arrow of ours in the bags")
    -- Its own arrows switched off in its options: the card is ours again.
    options.scale_arrows = false
    W.CompanionChanged()
    W.Run(0.5)
    eq(arrows.Body:GetText(), L.WELCOME_ARROWS_TEXT, "its own arrows switched off: the card has its own sentence")
    eq(arrows.Switch:IsEnabled(), true, "its box is in use"); eq(arrows.Switch:GetChecked(), true, "and ticked, as it was left")
    eq(arrows.Switch:GetAlpha(), 1, "at full strength"); eq(arrows.Title:GetAlpha(), 1, "as its name is")
    eq(arrows.Picture:GetAlpha(), 1, "and the picture whole"); eq(Arrow(), true, "with an arrow of ours on the better chest, by its scale")
    arrows.Switch:SetChecked(false)
    arrows.Switch:Click()
    eq(UpgradeScoutDB.arrows, false, "the arrows switched off"); eq(Arrow(), false, "go at once")
    arrows.Switch:SetChecked(true)
    arrows.Switch:Click()
    eq(Arrow(), true, "and come back")
    options.scale_arrows = nil
    W.CompanionChanged()
    W.Run(0.5)
    eq(arrows.Switch:IsEnabled(), false, "its own switched on again: the card is out of use"); eq(Arrow(), false, "and ours are gone")
    eq(UpgradeScoutDB.arrows, nil, "what the box was left at is kept")

    -- Its line in a tooltip switched off in its options: the block is ours again.
    options.scale_tooltip = false
    W.CompanionChanged()
    W.Run(0.5)
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_TEXT, "its line switched off: the tooltip's block has its own sentence")
    for name, box in pairs({ ["the addon's tabs"] = tabs, ["the rest of the game"] = elsewhere }) do
        eq(box:IsEnabled(), true, "the score's box for " .. name .. " is in use"); eq(box:GetChecked(), true, "and ticked: " .. name)
        eq(box:GetAlpha(), 1, "and whole: " .. name)
    end
    eq(block.All:IsEnabled(), true, "the two buttons in use"); eq(tip.Lines[1].Title:IsShown(), true, "the picture with the score's lines")
    eq(tip.Lines[1].Title:GetText(), "Arms", "which are the addon's own profiles, as in every picture")
    options.scale_tooltip = nil
    W.CompanionChanged()
    W.Run(0.5)
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_COMPANION, "switched on again: Forever Companion writes there")
    eq(told, 1, "none of that is news about the scores")

    -- Another character of the account: the lists for it have our lines, always.
    UpgradeScoutDB.chars["Alty-Testrealm"] = { key = "Alty-Testrealm", name = "Alty", realm = "Testrealm", class = "DRUID", level = 20 }
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_COMPANION_OTHERS, "with another character the block says where our lines are left")
    eq(tabs:IsEnabled(), false, "the box of the tabs is not the player's to change"); eq(tabs:GetChecked(), true, "it is held ticked")
    eq(block.All:IsEnabled(), true, "and the two buttons are in use")
    UpgradeScoutDB.chars["Alty-Testrealm"] = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_COMPANION, "without the other character the block is as it was")

    -- A scale chosen in the window is chosen in Forever Companion.
    trees[2]:Click()
    eq(ForeverCompanion.db.char.scale, TANK, "a click on a scale chooses it in Forever Companion")
    eq(trees[2].Mark:IsShown(), true, "its button lights up"); eq(trees[1].Mark:IsShown(), false, "the other goes dark")
    eq(ns.Roster.Me().companion, nil, "nothing is written on the card"); eq(ns.Roster.Me().profile, nil, "the addon's own profile is left alone")
    W.Run(0.5)
    eq(told, 1, "which is no news from it")
    -- And one chosen in its own options shows here.
    ForeverCompanion.db.char.scale = FURY
    W.CompanionChanged()
    W.Run(0.5)
    eq(trees[1].Mark:IsShown(), true, "a scale chosen in Forever Companion's options is the one lit here"); eq(told, 2, "and what keeps scores is told")

    -- Closed: seen with Forever Companion there, so it does not come up by itself again.
    window.Done:Click()
    eq(UpgradeScoutDB.companionOffered, true, "the choice has been seen with it"); eq(UpgradeScoutDB.pawnOffered, nil, "and not with Pawn, which was not there")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "it does not come up by itself again")
    ns.Welcome.Show()
    eq(window.About:GetText(), L.WELCOME_ABOUT, "asked for, it has its usual first words")

    -- The addon chosen again: the trees, the block and the card as they were.
    own:Click()
    eq(UpgradeScoutDB.engine, nil, "a click on the addon's button: nothing is left written"); eq(own.Mark:IsShown(), true, "its button is lit")
    eq(trees[1].Label:GetText(), "Arms", "the trees are back"); eq(trees[1].Mark:IsShown(), true, "the one for the talents in use")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_TEXT, "the tooltip's block has its sentence"); eq(tabs:IsEnabled(), true, "and its boxes in use")
    eq(arrows.Body:GetText(), L.WELCOME_ARROWS_TEXT, "the arrows' card has its sentence"); eq(arrows.Switch:IsEnabled(), true, "and its box in use")
    eq(arrows.Switch:GetChecked(), true, "ticked"); eq(arrows.Picture:GetAlpha(), 1, "with its picture whole")
    W.Run(0.5)
    eq(Arrow(), true, "and the arrows in the bags are ours, by the addon's own profile")
    CheckCompanionAsked("the welcome window")

    -- A new player who has both Pawn and Forever Companion: one window, with the welcome,
    -- and it counts for both.
    window.Done:Click()
    UpgradeScoutDB = nil
    PawnWorld()
    Relog(W.player, W.equipped)
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome ~= window and UpgradeScoutWelcome:IsShown() end, 10)
    eq(UpgradeScoutWelcome.About:GetText(), ns.L.WELCOME_FIRST, "a new player with both: the welcome")
    eq(UpgradeScoutWelcome.Engines[2]:GetAlpha(), 1, "with Pawn there to choose"); eq(UpgradeScoutWelcome.Engines[3]:GetAlpha(), 1, "and Forever Companion")
    UpgradeScoutWelcome.Done:Click()
    eq(UpgradeScoutDB.welcomed, true, "seen"); eq(UpgradeScoutDB.pawnOffered, true, "with Pawn")
    eq(UpgradeScoutDB.companionOffered, true, "and with Forever Companion")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(UpgradeScoutWelcome:IsShown(), false, "it comes up once, not three times")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- What a consumable adds, scored on a scale of Forever Companion's: the game's names for
-- stats put into its own, and a chance into the percentage it reads.
function scenarios.companion_supplies()
    StandardWorld()
    SuppliesWorld()
    CompanionWorld()
    UpgradeScoutDB = { engine = "companion" }
    LoadAddon()
    SupplyFacts()
    local Score = ns.Score
    eq(Score.Engine(), "companion", "Forever Companion scores")

    near(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_AGILITY_SHORT = 4 }, FURY), 8 * 1.5 + 4, "stats under its names, by the scale's weights")
    near(Score.StatsValue({ ITEM_MOD_CRIT_RATING_SHORT = 28 }, FURY), 2 * 8, "a chance: 28 points of rating are the 2% it reads")
    near(Score.StatsValue({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, FURY), 2 * 8, "a chance with weapons counts on a fighter's scale")
    near(Score.StatsValue({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, MOON), 0, "and not on a caster's")
    near(Score.StatsValue({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, MOON), 6, "a chance with spells counts on a caster's scale")
    near(Score.StatsValue({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, FURY), 0, "and not on a fighter's")
    near(Score.StatsValue({ ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, MOON), 12, "both kinds add up for the one who uses both")
    near(Score.StatsValue({ ITEM_MOD_ATTACK_POWER_SHORT = 10 }, FURY), 4, "attack power")
    -- What adds to spells: to damage and healing alike it is spell power; damage alone counts
    -- as spell power on a scale that weighs that for its damage, and for nothing on a healer's.
    near(Score.StatsValue({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 36 }, MOON), 36, "spell damage alone, on a scale that weighs spell power for its damage")
    near(Score.StatsValue({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 20, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 20 }, MOON), 20, "damage and healing alike are spell power, counted once")
    near(Score.StatsValue({ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 20 }, MOON), 0, "healing alone is nothing to a scale without a weight for it")
    W.AddCompanionScale("DRUID", { id = 7, label = "Healer", tab = 3, w = { Healing = 2, SpellPower = 2, Intellect = 1 } })
    local mine = W.AddCompanionCustom({ name = "Mine", class = "WARRIOR", w = { Strength = 1, SpellCritRating = 5 } })
    W.CompanionChanged()
    W.Run(0.5)
    near(Score.StatsValue({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 36 }, "wh:7"), 0, "damage alone is nothing to a healer's scale")
    near(Score.StatsValue({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 20, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 20 }, "wh:7"), 40, "damage and healing alike: spell power")
    near(Score.StatsValue({ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 10 }, "wh:7"), 20, "healing alone: healing")
    near(Score.StatsValue({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 30, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 40 }, "wh:7"), 30 * 2 + 10 * 2, "more of the one than of the other: each part under its name")
    near(Score.StatsValue({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, "my:" .. mine.id), 5, "a chance with spells under its own name, on a scale that weighs that")
    near(Score.StatsValue({ ITEM_MOD_HEALTH_SHORT = 25 }, FURY), 2.5 * 0.5, "health as the Stamina that gives it: Forever Companion has no stat for it")
    near(Score.StatsValue({ ITEM_MOD_MANA_SHORT = 30 }, MOON), 2, "mana as Intellect")
    near(Score.StatsValue({ ITEM_MOD_UNHEARD_OF_SHORT = 99 }, FURY), 0, "a stat it has no name for counts for nothing")
    near(Score.StatsValue({ ITEM_MOD_SPIRIT_SHORT = 8 }, FURY), 0, "nor does one the scale does not weigh")
    eq(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8 }, "wh:99"), nil, "no answer for a scale there is not")
    eq(Score.StatsValue({ ITEM_MOD_STRENGTH_SHORT = 8 }, "S1"), nil, "nor for one of the addon's own profiles")

    -- The list of consumables is scored on the scale.
    W.OpenAuctionHouse()
    ScanSupplies()
    local rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(FURY, { mana = false }))
    local function Value(name)
        for _, row in ipairs(rows) do
            if row.kind == "supply" and row.entry.supply.name == name then return row.entry.value end
        end
    end
    near(Value("Elixir of Giants"), 25 * 1.5, "an elixir of Strength on a fighter's scale"); near(Value("Elixir of Agility"), 15, "one of Agility")
    eq(Value("Elixir of Wisdom"), nil, "Intellect is of no use on that scale")
    rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(MOON, { mana = true }))
    near(Value("Elixir of Wisdom"), 6, "and worth its weight on a caster's")
    -- The heading over a consumable's score says whose score it is.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    ns.Tooltip.AddHeader(GameTooltip, "Fury DPS", true)
    local heading = GameTooltip._lines[#GameTooltip._lines]
    check(heading.text:find("Upgrade Scout (Forever Companion score)", 1, true) ~= nil, "a heading over a score, with Forever Companion scoring: " .. heading.text)
    eq(heading.right, "Fury DPS", "with what stands on its right")
    ns.Tooltip.AddHeader(GameTooltip)
    heading = GameTooltip._lines[#GameTooltip._lines]
    eq(heading.text:find("Forever Companion", 1, true), nil, "a heading over notes alone names no other addon")
    CheckCompanionAsked("consumables")
end

-- Another character of the account: the scales of its class, its own choice among them
-- written on its card, and Forever Companion's line, which is about the character being
-- played, kept out of the rows of its list.
function scenarios.companion_alt()
    StandardWorld()
    local warrior, warriorGear = W.player, W.equipped
    W.AddItem({ id = 300, name = "Alt's Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 12, D2 = 3 }, level = 15 })
    W.AddItem({ id = 310, name = "Druid Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 20, D2 = 2 }, level = 18 })
    W.AddAuction(310, 2000)
    CompanionWorld()
    W.companion.writes = true
    UpgradeScoutDB = { engine = "companion" }

    -- The druid is played once.
    W.Login(Druid())
    W.equipped = { [5] = W.Link(300) }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(ns.Score.Current().name, MOON, "the druid, played: the scale Forever Companion has in use for it")
    Relog(warrior, warriorGear)
    local Score, S = ns.Score, ns.Scanner
    local options = ForeverCompanion.db.global
    local card = UpgradeScoutDB.chars["Alty-Testrealm"]
    check(card ~= nil, "the druid is remembered")

    local _, theirs = Score.Current(card)
    eq(#theirs, 2, "another character: the scales Forever Companion has for its class")
    eq(theirs[1].name, MOON, "by their keys"); eq(theirs[1].title, "Balance DPS", "and their names")
    eq(theirs[2].title, "Feral DPS", "each of them")
    eq(#Score.Profiles(ns.Roster.Me()), 2, "the card of the character being played is that character")

    -- At the auction house the field lists them under the warrior's own.
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    local ALTY = "|cffff7c0aAlty|r"
    eq(#dropdown.radios, 4, "two scales of the warrior and two of the druid")
    eq(dropdown.radios[3].text, ALTY .. ": Balance DPS", "the druid's by its name and the scale's")
    eq(dropdown.radios[4].text, ALTY .. ": Feral DPS", "each of them")
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(4)
    eq(ns.Roster.Target(), card, "the lists are for the druid"); eq(card.companion, CAT, "on the scale chosen, written on its card")
    eq(ForeverCompanion.db.char.scale, nil, "and not chosen in Forever Companion, where the choice is the warrior's")
    eq(card.profile, nil, "apart from the addon's own profile"); eq(card.scale, nil, "and from the Pawn scale")
    dropdown:Pick(3)
    eq(card.companion, MOON, "another of its scales chosen")
    frame.ScanButton:Click()
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(1)
    eq(S.ctx.who, card, "the scan was for the druid"); eq(S.ctx.profile, MOON, "on its scale")
    near(S.ctx.equipped[5].value, 12, "its chest by Forever Companion's reading, on that scale")
    check(Offer("Druid Jerkin") ~= nil, "a jerkin better than the druid's"); near(Offer("Druid Jerkin").value, 20, "by the same reading")
    eq(Offer("Good Chest"), nil, "the warrior's upgrades are not the druid's")

    -- A row's tooltip has our lines here: Forever Companion's is about the character being
    -- played, and is kept out.
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    local function Row(name)
        for _, w in ipairs(scrollBox:GetFrames()) do
            local entry = w._shown and w._kind == "Button" and w.entry or nil
            if entry and entry.offer and entry.offer.name == name then return w end
        end
    end
    local function ListFor(index)
        dropdown:Pick(index)
        W.Run(0.5)
        if S.state == "idle" then frame.ScanButton:Click() end
        W.RunUntil(function() return S.state == "idle" end, 300)
        W.Run(1)
    end
    local function Elsewhere()
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink(W.Link(310))
        return CompanionLine(GameTooltip)
    end
    local jerkin = Row("Druid Jerkin")
    check(jerkin ~= nil, "the jerkin is in the list")
    jerkin:GetScript("OnEnter")(jerkin)
    local doubles = {}
    for _, line in ipairs(GameTooltip._lines) do
        if line.right then doubles[#doubles + 1] = line end
    end
    eq(doubles[1].right, ALTY, "a list for another character: our header, which says whose")
    check(doubles[1].text:find("Upgrade Scout (Forever Companion score)", 1, true) ~= nil, "and that the score in our lines is Forever Companion's: " .. doubles[1].text)
    eq(doubles[2].text, "Balance DPS", "then the druid's scales"); eq(doubles[2].right, "+67%", "with the gain on each: 20 against 12")
    eq(doubles[3].text, "Feral DPS", "on the other one"); eq(doubles[3].right, "-33%", "2 against 3")
    eq(ShoppingTooltip1:IsShown(), true, "and the druid's chest beside it")
    eq(CompanionLine(GameTooltip), false, "Forever Companion's line is kept out of a row for another character")
    eq(rawget(options, "scale_tooltip"), nil, "and its option for the line is afterwards as it was: never set")
    jerkin:GetScript("OnLeave")(jerkin)
    eq(Elsewhere(), true, "anywhere else it writes its line")
    -- Its lists of the best gear, for the talent trees the player follows in it, are about
    -- the character being played as well, and are kept out the same way.
    W.companion.lists = true
    jerkin:GetScript("OnEnter")(jerkin)
    eq(CompanionList(GameTooltip), false, "Forever Companion's lists of the best gear are kept out of a row for another character")
    eq(CompanionLine(GameTooltip), false, "with its line")
    eq(rawget(options, "bis_tooltip"), nil, "and its option for the lists is afterwards as it was: never set")
    jerkin:GetScript("OnLeave")(jerkin)
    Elsewhere()
    eq(CompanionList(GameTooltip), true, "anywhere else it writes its lists")
    options.bis_tooltip = true
    jerkin:GetScript("OnEnter")(jerkin)
    eq(CompanionList(GameTooltip), false, "kept out the same for a player who has set that option")
    eq(rawget(options, "bis_tooltip"), true, "which is as they have it")
    jerkin:GetScript("OnLeave")(jerkin)
    options.bis_tooltip = nil
    -- A player who has set that option: it is put back as they have it.
    options.scale_tooltip = true
    jerkin:GetScript("OnEnter")(jerkin)
    eq(CompanionLine(GameTooltip), false, "kept out the same way"); eq(rawget(options, "scale_tooltip"), true, "and the option is as that player has it")
    jerkin:GetScript("OnLeave")(jerkin)
    options.scale_tooltip = nil
    -- Something goes wrong while the tooltip is filled in: the error passes on, with the
    -- option put back.
    local passed
    local ok, problem = pcall(ns.Companion.Hushed, function(what) passed = what error("no such item", 0) end, "a link")
    eq(ok, false, "an error in filling the tooltip in passes on"); eq(problem, "no such item", "as it was")
    eq(passed, "a link", "what fills it in is called with what it was given"); eq(rawget(options, "scale_tooltip"), nil, "and the option is put back all the same")
    eq(rawget(options, "bis_tooltip"), nil, "the one for its lists too")
    -- Our lines are all that says the score there, so they do not go by their box.
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    jerkin:GetScript("OnEnter")(jerkin)
    eq(GameTooltip._lines[#GameTooltip._lines].right, "-33%", "our lines unticked for the tabs: they still stand in a list for another character")
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    -- One line for the scale in use says whose score it is after the scale's name.
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    jerkin:GetScript("OnEnter")(jerkin)
    local single = GameTooltip._lines[#GameTooltip._lines]
    check(single.text:find(ALTY .. ": Balance DPS (Forever Companion score)", 1, true) ~= nil, "\"Only my spec\": one line, with whose score it is: " .. single.text)
    eq(single.right, "+67%", "and the gain")
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")

    -- The warrior's own list: Forever Companion writes there as everywhere.
    ListFor(1)
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own again")
    local chest = Row("Good Chest")
    check(chest ~= nil, "a better chest for the warrior is in the list")
    chest:GetScript("OnEnter")(chest)
    eq(CompanionLine(GameTooltip), true, "a row of the player's own list: its line, as anywhere")
    eq(CompanionList(GameTooltip), true, "and its lists of the best gear")
    chest:GetScript("OnLeave")(chest)
    CheckCompanionAsked("another character")

    -- The addon's own weights chosen, with Forever Companion still installed: it writes into
    -- tooltips as before, and is kept out of a list for another character the same way.
    Score.SetEngine(nil)
    W.Run(1)
    W.RunUntil(function() return S.state == "idle" end, 300)
    ListFor(3)
    eq(ns.Roster.Target(), card, "the addon scores, and the lists are for the druid")
    jerkin = Row("Druid Jerkin")
    check(jerkin ~= nil, "the jerkin is in the druid's list by the addon's own weights")
    jerkin:GetScript("OnEnter")(jerkin)
    eq(CompanionLine(GameTooltip), false, "the addon scoring: its line is kept out of a row for another character")
    eq(CompanionList(GameTooltip), false, "and so are its lists of the best gear")
    local ours, marked = false, false
    for _, line in ipairs(GameTooltip._lines) do
        if line.right == ALTY then ours = true end
        if line.text:find("Forever Companion score", 1, true) then marked = true end
    end
    eq(ours, true, "under our header, which says whose list it is")
    eq(marked, false, "and names no other addon: the score is the addon's own")
    jerkin:GetScript("OnLeave")(jerkin)
    eq(Elsewhere(), true, "and it writes on everywhere else")

    -- Without Forever Companion there is nobody to keep out: the tooltip is filled in and no more.
    W.RemoveCompanion()
    local filled
    ns.Companion.Hushed(function(what) filled = what end, "a link")
    eq(filled, "a link", "no Forever Companion: what fills the tooltip in is called")
end

-- A chance on an item. Forever Companion's scales weigh one percent of it, and in most
-- languages of the game it takes the game's points of rating for percent: such an item
-- scores many times what it does in English. The addon scores by that reading all the same.
-- The player chose Forever Companion to score and sees its number in its own line of a
-- tooltip: a list that said another would contradict it.
function scenarios.companion_chance()
    StandardWorld()
    -- Two chests with 2% to crit, which the game counts as 28 points of rating, and 4
    -- Strength. Forever Companion took the first's crit from the game's count, as it does in
    -- Russian, and read the second's from the words of its tooltip, as it does in English.
    local game = { ITEM_MOD_CRIT_RATING_SHORT = 28, ITEM_MOD_STRENGTH_SHORT = 4 }
    W.AddItem({ id = 330, name = "Counted Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 0, level = 10,
        game = game, companion = { CritRating = 28, Strength = 4 } })
    W.AddItem({ id = 331, name = "Read Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 0, level = 10,
        game = game, companion = { CritRating = 2, Strength = 4 } })
    CompanionWorld()
    local scale = W.AddCompanionCustom({ name = "Chances", class = "WARRIOR", w = { Strength = 1, CritRating = 30 } })
    local key = "my:" .. scale.id
    ForeverCompanion.db.char.scale = key
    UpgradeScoutDB = { engine = "companion" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score = ns.Score
    eq(Score.Engine(), "companion", "Forever Companion scores"); eq(Score.Current().name, key, "on the scale chosen in it")

    local handed = {}
    local read = ForeverCompanion.Scales.ReadItem
    ForeverCompanion.Scales.ReadItem = function(link)
        local got, wait = read(link)
        handed[tonumber(link:match("item:(%d+)"))] = got
        return got, wait
    end
    local counted = Score.Item(W.Link(330))
    eq(counted.companion, handed[330], "Forever Companion's reading of an item is used as it stands")
    near(Score.Value(counted, key), 28 * 30 + 4, "a chance it took from the game's count of rating is scored as it scores it")
    local worded = Score.Item(W.Link(331))
    eq(worded.companion, handed[331], "the same for one it read as percent")
    near(Score.Value(worded, key), 2 * 30 + 4, "which scores what it reads")
    eq(#W.errors, 0, "nothing of it is an error")
end

---------------------------------------------------------------------------
-- Forever Leveling BiS as the one who scores (Leveling.lua)
---------------------------------------------------------------------------
-- The warrior's three specs and the druid's four, as that addon has them, each with weights
-- under its own names for the stats. Of the warrior's, Arms scores an item of the tests as
-- their first profile does and Fury as the second (see W.InstallLeveling), so the standard
-- world reads by Arms as it does by the addon itself.
local MAIN_ARMS, MAIN_FURY = "@WARRIOR:arms:twohand", "@WARRIOR:fury:twohand"

local function LevelingWorld()
    W.InstallLeveling()
    W.AddLevelingSpecs("WARRIOR", { "arms", "fury", "protection" })
    W.AddLevelingSpecs("DRUID", { "balance", "feral", "bear", "restoration" })
    W.SetLevelingWeights("WARRIOR", "arms", { str = 1.5, agi = 1, sta = 0.5, atkpwr = 0.4, critPct = 8, dps = 2, ohDps = 1 })
    W.SetLevelingWeights("WARRIOR", "fury", { str = 1, sta = 1, dps = 1 })
    W.SetLevelingWeights("WARRIOR", "protection", { sta = 2, armor = 0.1, block = 0.5 })
    W.SetLevelingWeights("DRUID", "balance", { int = 1, splpwr = 1, spldmg = 1, critPct = 6 })
    W.SetLevelingWeights("DRUID", "feral", { agi = 1, str = 1, feratkpwr = 0.5, dps = 3 })
    W.SetLevelingWeights("DRUID", "bear", { sta = 1.5, agi = 1, armor = 0.1 })
    W.SetLevelingWeights("DRUID", "restoration", { splheal = 1, splpwr = 1, int = 0.5 })
end

-- The talent trees by the names the game has for them, as the addon's own table of them has
-- in the game (the tests' own profiles are named otherwise: see TestWeights).
local function TreeNames()
    local trees = ns.Weights.titles.enUS
    trees.DRUID_BALANCE, trees.DRUID_FERAL_CAT, trees.DRUID_FERAL_BEAR = "Balance", "Feral Combat", "Feral Combat"
    trees.DRUID_RESTORATION, trees.HUNTER_SURVIVAL, trees.PALADIN_HOLY = "Restoration", "Survival", "Holy"
end

-- Forever Leveling BiS was asked about no item with its enchantment on.
local function CheckLevelingAsked(label)
    for _, ask in ipairs(W.leveling.asked) do
        check(not ask.link:match("item:%d+:%d"), label .. ": Forever Leveling BiS is asked for the score of an item without its enchantment")
    end
    for _, link in ipairs(W.leveling.gains) do
        check(not link:match("item:%d+:%d"), label .. ": and whether it is for the character the same way")
    end
end

-- Has the tooltip Forever Leveling BiS's own block?
local function LevelingBlock(tooltip)
    for _, line in ipairs(tooltip._lines) do
        if line.text:find("Forever Leveling BiS:", 1, true) then return true end
    end
    return false
end

-- The road of a player who has Forever Leveling BiS: the addon scores by itself until it is
-- chosen, then by its score for the main spec chosen in it, and the lists are made the same
-- way from its numbers.
function scenarios.leveling_scan()
    StandardWorld()
    -- The worn chest is enchanted. On the second score: the two chests 9 (for sale) and 12
    -- (worn), a helm, a two-hander and a shield.
    W.equipped[5] = (W.Link(100):gsub("item:100:", "item:100:66", 1))
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["211:0"].value2, W.items["212:0"].value2, W.items["213:0"].value2 = 5, 40, 8
    LevelingWorld()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score, S, me = ns.Score, ns.Scanner, ns.Roster.Me()
    local function Idle() return S.state == "idle" end

    -- It is there and not chosen: the addon scores by itself and asks it about no item.
    eq(ns.Leveling.Usable(), true, "Forever Leveling BiS is there to be asked"); eq(Score.Engine(), nil, "and is not, until chosen")
    eq(Score.Current().name, "S1", "the profiles are the addon's own")
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    ScanToEnd()
    CheckStandardOffers("the addon's own weights, with Forever Leveling BiS installed")
    eq(#W.leveling.asked, 0, "Forever Leveling BiS is asked about no item"); eq(#W.leveling.gains, 0, "in no way")
    eq(#dropdown.radios, 2, "the field lists the addon's profiles"); eq(dropdown:GetText(), "Arms", "the one in use")

    -- Chosen, as the welcome window does it: for the whole account, and at once.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    Score.SetEngine("leveling")
    eq(UpgradeScoutDB.engine, "leveling", "the choice is written down for the account"); eq(Score.Engine(), "leveling", "and Forever Leveling BiS scores")
    eq(told, 1, "what keeps scores is told")
    local current, list = Score.Current()
    eq(#list, 1, "the character being played has one profile: its main spec in Forever Leveling BiS")
    eq(current.name, MAIN_ARMS, "with none chosen there, the first of its class, and the way it fills its hands")
    eq(current.title, "Arms", "by the name of its talent tree")
    eq(Score.Title(MAIN_ARMS), "Arms", "a spec's title by its profile"); eq(Score.IsApprox(MAIN_ARMS), false, "no spec is marked as an estimate")
    eq(#Score.Trees(), 2, "the addon's own profiles are still there to be asked for")

    -- The list that was there is made again, by its score.
    check(S.state ~= "idle", "a list that was made on the addon's weights is made again")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MAIN_ARMS, "on the main spec")
    CheckStandardOffers("Forever Leveling BiS, on the first spec")
    near(S.ctx.equipped[5].value, 10, "what is worn is scored by it, without its enchantment")
    near(S.ctx.equipped[16].value, 20, "every piece of it")
    eq(S.ctx.show1H, true, "a spec is offered one-handed weapons"); eq(S.ctx.show2H, true, "and two-handed ones")
    CheckLevelingAsked("a scan")
    eq(#dropdown.radios, 1, "the field has the one line"); eq(dropdown.radios[1].text, "Arms", "the main spec")
    eq(dropdown:GetText(), "Arms", "which it shows")
    dropdown._tooltip(GameTooltip)
    local tip = {}
    for _, line in ipairs(GameTooltip._lines) do tip[#tip + 1] = line.text end
    check(table.concat(tip, " | "):find(ns.L.PROFILE_TIP_LEVELING, 1, true) ~= nil, "its tooltip says where the main spec is chosen")
    dropdown:Pick(1)
    W.Run(0.5)
    eq(told, 1, "the one line clicked: nothing changes"); eq(S.state, "idle", "and the list stays")
    eq(me.leveling, nil, "nothing is written on the card of the character being played")
    eq(me.profile, nil, "the addon's own profile is left alone")

    -- Another main spec chosen in Forever Leveling BiS: the addon hears of it, and the list
    -- follows.
    Score.Current()
    W.LevelingChar().spec = "fury"
    W.LevelingChanged()
    W.Run(0.5)
    eq(told, 2, "another main spec chosen there: what keeps scores is told")
    eq(Score.Current().name, MAIN_FURY, "the profile is the main spec it has now")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MAIN_FURY, "the list follows"); eq(dropdown:GetText(), "Fury", "and so does the field")
    check(Offer("Helm") ~= nil, "a helm for the empty head, by its score for that spec")
    check(Offer("Shield") ~= nil, "a shield for the empty off hand")
    check(Offer("Big Axe") ~= nil, "and a two-hander")
    eq(Offer("Good Chest"), nil, "the chest is no upgrade for it: 9 against 12")
    eq(OfferCount(), 3, "and nothing else")

    -- It calls for other reasons too (the gear changed, an item was loaded): nothing of
    -- what the scores rest on changed.
    W.LevelingChanged()
    W.Run(0.5)
    eq(told, 2, "it says something changed, with its answers as they were: nothing is told"); eq(S.state, "idle", "and the list stays")
    -- The spec's weights are changed in its own window.
    W.SetLevelingWeights("WARRIOR", "fury", { str = 1, sta = 2, dps = 1 })
    W.LevelingChanged()
    W.Run(0.5)
    eq(told, 3, "the weights of the main spec changed: what keeps scores is told")
    W.RunUntil(Idle, 600)
    W.SetLevelingWeights("WARRIOR", "fury", { str = 1, sta = 3, dps = 1 })
    W.LevelingChanged()
    W.SetLevelingWeights("WARRIOR", "fury", { str = 1, sta = 1, dps = 1 })
    W.LevelingChanged()
    W.Run(0.5)
    eq(told, 4, "a burst of changes is one telling")
    W.RunUntil(Idle, 600)
    -- Another way to fill the hands chosen there for the spec.
    W.LevelingChar().weapons = { ["WARRIOR:fury"] = "dualwield" }
    W.LevelingChanged()
    W.Run(0.5)
    eq(told, 5, "another weapon setup: what keeps scores is told")
    eq(Score.Current().name, "@WARRIOR:fury:dualwield", "and the profile names it")
    W.RunUntil(Idle, 600)

    -- A main spec found changed with nobody saying so: its answer is asked for again after
    -- a moment, and not each time.
    Score.Current()
    W.LevelingChar().spec = "arms"
    local asked = W.leveling.specAsked
    for _ = 1, 20 do Score.Current() end
    eq(W.leveling.specAsked, asked, "asked many times in a moment, the main spec is not asked for each time")
    W.Run(3)
    eq(Score.Current().name, MAIN_ARMS, "an answer grown old is asked for again")
    W.Run(0.5)
    eq(told, 6, "and, being new, told")
    W.RunUntil(Idle, 600)
    CheckStandardOffers("Forever Leveling BiS, back on the first spec")

    -- /upscout stats: the stats as the game counts them on the spec's weights, by Forever
    -- Leveling BiS's words for them, and its own score, which counts more than those.
    local good = W.items["200:0"]
    good.game, good.leveling, good.bonus = { ITEM_MOD_STRENGTH_SHORT = 4 }, { str = 4 }, 3
    local at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats " .. W.Link(200))
    local said = Said(at)
    check(said:find('on the profile "Arms": score 27', 1, true) ~= nil, "the main spec and Forever Leveling BiS's own score for it: " .. said)
    check(said:find("Strength: 4 × 1.5 = 6", 1, true) ~= nil, "a stat by its word for it, with the spec's weight")
    check(said:find("TEST_S1", 1, true) == nil, "a stat it has no weight for is left out")
    good.game, good.leveling, good.bonus = nil, nil, nil

    -- It has no answer about the character: no main spec, no scan, and the reason.
    W.leveling.ready = false
    W.LevelingChanged()
    W.Run(0.5)
    eq(told, 7, "its answers gone: what keeps scores is told")
    eq(Score.Current(), nil, "no main spec to be had: none in use")
    eq(S.Start(), false, "and no scan"); eq(S.message, ns.L.ERR_NO_SCALE_LEVELING, "which says why")
    W.leveling.ready = true
    W.LevelingChanged()
    W.Run(0.5)
    W.RunUntil(Idle, 600)
    eq(Score.Current().name, MAIN_ARMS, "its answers back, the main spec back")
    CheckLevelingAsked("answers coming and going")

    -- Back to the addon's own weights: its profile is where it was left.
    Score.SetEngine(nil)
    eq(UpgradeScoutDB.engine, nil, "the addon's own weights chosen again: nothing is left written")
    eq(Score.Current().name, "S1", "the addon's profile as it was")
    W.RunUntil(Idle, 600)
    eq(#dropdown.radios, 2, "the field lists the addon's profiles again")
    local before = #W.leveling.asked
    ScanToEnd()
    CheckStandardOffers("the addon's own weights again")
    eq(#W.leveling.asked, before, "and Forever Leveling BiS is asked about no item")

    -- Another character of the account can be scored on any spec of its class: the one
    -- chosen for it in the addon's field, then its main spec as Forever Leveling BiS last
    -- saved it, then the one for its talents, then the first.
    Score.SetEngine("leveling")
    TreeNames()
    local saved = ForeverLevelingBiSDB.chars
    local function Other(card)
        card.key, card.name, card.realm = card.key or "P", card.name or "P", card.realm or "Testrealm"
        return card
    end
    local picked, all = Score.Current(Other({ class = "DRUID", talents = "DRUID_FERAL_BEAR" }))
    eq(#all, 4, "another character: every spec Forever Leveling BiS has for its class")
    eq(all[1].name, "DRUID:balance", "each by its class and its key there"); eq(all[1].title, "Balance", "and the name of its talent tree")
    eq(all[2].title, "Feral Combat (Cat)", "a druid's two of one tree are told apart by the shape")
    eq(all[3].title, "Feral Combat (Bear)", "each of them"); eq(all[4].title, "Restoration", "the last")
    eq(picked.name, "DRUID:bear", "the one in use: the spec for the tree its talents are in")
    eq(Score.Current(Other({ class = "DRUID" })).name, "DRUID:balance", "with nothing to go by: the first")
    eq(Score.Current(Other({ class = "DRUID", talents = "DRUID_FERAL_BEAR", leveling = "restoration" })).name, "DRUID:restoration",
        "under the spec chosen for it in the addon's field")
    eq(Score.Current(Other({ class = "DRUID", talents = "DRUID_FERAL_CAT", leveling = "gone" })).name, "DRUID:feral",
        "a choice that is no spec any more gives way to the talents")
    saved["Alty-Testrealm"] = { spec = "bear", weapons = { ["DRUID:bear"] = "held" } }
    local alt = Other({ key = "Alty-Testrealm", name = "Alty", class = "DRUID", talents = "DRUID_BALANCE" })
    eq(Score.Current(alt).name, "DRUID:bear:held", "its main spec as saved there comes before its talents, with the way it fills its hands")
    alt.leveling = "feral"
    eq(Score.Current(alt).name, "DRUID:feral", "and after the choice made in the addon's field")
    alt.leveling, alt.realm = nil, "Elsewhere"
    eq(Score.Current(alt).name, "DRUID:balance", "a character of another realm is another character there")
    -- Forever Leveling BiS keeps a character by its full name: the first name and the surname.
    saved["Bob Hopes-Testrealm"] = { spec = "feral" }
    eq(Score.Current(Other({ key = "Bob Hopes", name = "Bob", last = "Hopes", class = "DRUID" })).name, "DRUID:feral",
        "a character with a surname is found by both names")
    saved["Alty-Testrealm"].spec = "nonsense"
    alt.realm = "Testrealm"
    eq(Score.Current(alt).name, "DRUID:balance", "a saved spec that is none of the class's is passed over")
    -- A priest has three specs there and two profiles here; a hunter four specs for three trees.
    W.AddLevelingSpecs("PRIEST", { "discipline", "holy", "shadow" })
    W.AddLevelingSpecs("HUNTER", { "beastmastery", "marksmanship", "survival", "survivalmelee" })
    picked, all = Score.Current(Other({ class = "PRIEST", talents = "PRIEST_HEALER" }))
    eq(picked.name, "PRIEST:holy", "a priest that heals: Holy stands for either of its healing trees")
    eq(all[1].title, ns.L.TREE_DISCIPLINE, "Discipline by the game's name for the tree"); eq(all[2].title, "Holy", "Holy by the word a paladin's is")
    eq(Score.Current(Other({ class = "PRIEST", talents = "PRIEST_SHADOW" })).name, "PRIEST:shadow", "its Shadow by the tree")
    picked, all = Score.Current(Other({ class = "HUNTER", talents = "HUNTER_SURVIVAL" }))
    eq(picked.name, "HUNTER:survival", "a hunter of the Survival tree: the first of the two specs for it")
    eq(all[3].title, "Survival (Ranged)", "which are told apart by the way of fighting"); eq(all[4].title, "Survival (Melee)", "in the game's words")
    eq(Score.Current(Other({ class = "HUNTER", talents = "HUNTER_BEAST_MASTERY" })).name, "HUNTER:beastmastery", "a tree named in two words")
    eq(Score.Current(Other({ class = "MAGE" })), nil, "a class it has no specs for: none")
    eq(Score.Title("DRUID:bear:held"), "Feral Combat (Bear)", "a profile's title leaves the weapon setup out")
    eq(Score.Title("no such thing"), "no such thing", "what is no profile is its own title")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- A weapon is worth one thing in the main hand and another in the off hand to Forever
-- Leveling BiS, and the lists keep the two apart; and a weapon it says is not for the spec
-- is not offered.
function scenarios.leveling_hands()
    W.player.dualWield = true
    local function Blade(id, name, dps, level, more)
        local def = { id = id, name = name, equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, value = 0, dps = dps, level = level }
        for key, value in pairs(more or {}) do def[key] = value end
        return W.AddItem(def)
    end
    Blade(400, "Main Blade", 10, 5)
    Blade(401, "Off Blade", 8, 5)
    Blade(402, "New Blade", 12, 8)
    Blade(403, "Odd Blade", 30, 8, { notFor = true })
    Blade(404, "Left Blade", 11, 8, { equipLoc = "INVTYPE_WEAPONOFFHAND" })
    Blade(405, "Great Axe", 16, 8, { equipLoc = "INVTYPE_2HWEAPON", subClassID = 1 })
    W.AddItem({ id = 406, name = "Buckler", equipLoc = "INVTYPE_SHIELD", subClassID = 6, value = 7, level = 6 })
    W.equipped[16], W.equipped[17] = W.Link(400), W.Link(401)
    for id = 402, 406 do W.AddAuction(id, 1000) end
    LevelingWorld()
    UpgradeScoutDB = { engine = "leveling" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score, S = ns.Score, ns.Scanner
    eq(Score.Engine(), "leveling", "Forever Leveling BiS scores"); eq(Score.Current().name, MAIN_ARMS, "on the main spec")

    -- The spec weighs a point of damage per second 2 in the main hand and 1 in the off hand.
    local ctx = Score.Context(MAIN_ARMS)
    near(ctx.equipped[16].value, 20, "the weapon in the main hand, at what it is worth there")
    near(ctx.equipped[17].value, 8, "the one in the off hand, at what it is worth in the off hand")
    local blade = Score.Item(W.Link(402))
    near(Score.Value(blade, MAIN_ARMS, 10), 24, "a weapon for one hand: its score is the main hand's")
    near(Score.OffValue(blade, MAIN_ARMS, 10), 12, "with another for the off hand")
    local left = Score.Item(W.Link(404))
    near(Score.Value(left, MAIN_ARMS, 10), 11, "a weapon made for the off hand has the one score, the off hand's")
    eq(Score.OffValue(left, MAIN_ARMS, 10), nil, "and no second one")
    eq(Score.OffValue(Score.Item(W.Link(405)), MAIN_ARMS, 10), nil, "nor has a two-hander")
    eq(Score.OffValue(Score.Item(W.Link(406)), MAIN_ARMS, 10), nil, "nor a shield")
    eq(Score.ClassCanUse(Score.Item(W.Link(403)), nil), false, "a weapon Forever Leveling BiS says the character cannot use now is not for it")
    eq(Score.ClassCanUse(blade, nil), true, "one it has a gain for is")
    eq(Score.ClassCanUse(Score.Item(W.Link(403)), { class = "WARRIOR", level = 10 }), true, "and it is not asked about another character")
    W.items["402:0"].cached = false
    eq(Score.Item(W.Link(402)), nil, "an item the client has not loaded has no answer yet")
    W.items["402:0"].cached = true

    W.OpenAuctionHouse()
    -- (Every price is to be looked up, also of what a better weapon for the same gold leaves out.)
    SetView(false, false)
    ScanToEnd()
    local offer = Offer("New Blade")
    check(offer ~= nil, "a better blade is in the list")
    near(offer.value, 24, "at its score for the main hand"); near(offer.offValue, 12, "with the one for the off hand beside it")
    local gains = ns.Compare.Gains(offer, S.ctx)
    eq(#gains, 2, "it can go in either hand")
    eq(gains[1].group, "MAINHAND", "in the main hand"); near(gains[1].delta, 4, "24 against 20")
    eq(gains[2].group, "OFFHAND", "in the off hand"); near(gains[2].delta, 4, "12 against 8: both at what they are worth there")
    near(gains[2].base, 8, "against the worn one's worth there")
    local worn = {}
    ns.Compare.Wear(worn, offer, gains[2])
    near(worn[17].value, 12, "put on in the off hand, it counts for what it is worth there")
    ns.Compare.Wear(worn, offer, gains[1])
    near(worn[16].value, 24, "and in the main hand for its score")
    check(Offer("Left Blade") ~= nil, "a weapon for the off hand: 11 against 8"); eq(Offer("Left Blade").offValue, nil, "with its one score")
    check(Offer("Great Axe") ~= nil, "a two-hander against both hands, the off hand at what it is worth there: 32 against 28")
    eq(Offer("Buckler"), nil, "a shield is no upgrade on the blade in the off hand: 7 against 8")
    eq(Offer("Odd Blade"), nil, "the weapon that is not for the spec is not offered, for all its score")
    -- What Forever Leveling BiS was asked: the worn off-hand weapon as one in the off hand.
    local asMain, asOff = false, false
    for _, ask in ipairs(W.leveling.asked) do
        if ask.link:find("item:401:", 1, true) then
            if ask.offHand then asOff = true else asMain = true end
        end
    end
    eq(asOff, true, "the weapon worn in the off hand is asked about as one held there"); eq(asMain, false, "and not as one in the main hand")
    local refused = 0
    for _, link in ipairs(W.leveling.gains) do
        local id = tonumber(link:match("item:(%d+)"))
        check(id >= 402 and id <= 406, "whether an item is for the character is asked of what is for sale, not of what is worn")
        if id == 403 then refused = refused + 1 end
    end
    check(refused >= 1, "the odd blade among them")
    CheckLevelingAsked("weapons")

    -- With anyone else scoring a weapon has the one score, for either hand.
    Score.SetEngine(nil)
    eq(Score.OffValue(Score.Item(W.Link(402)), "S1", 10), nil, "the addon's own weights: no second score for the off hand")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- Forever Leveling BiS chosen and not there: the addon scores by itself, and the choice stands.
function scenarios.leveling_absent()
    StandardWorld()
    UpgradeScoutDB = { engine = "leveling" }
    LoadAddon()
    local Score = ns.Score
    eq(ns.Leveling.Usable(), false, "Forever Leveling BiS is not installed"); eq(Score.Engine(), nil, "so the addon scores, though it was chosen")
    eq(Score.Current().name, "S1", "on its own profiles")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("Forever Leveling BiS chosen and not installed")
    eq(UpgradeScoutDB.engine, "leveling", "the choice stands for when it is back")

    -- It is there but does not know the character yet, as in the moments of logging in:
    -- its API has no answers then.
    LevelingWorld()
    W.leveling.ready = false
    eq(ns.Leveling.Usable(), false, "before it knows the character it cannot be asked"); eq(Score.Engine(), nil, "and is not")
    eq(Score.Current().name, "S1", "the addon's profiles meanwhile")
    W.leveling.ready = true
    eq(Score.Engine(), "leveling", "once it does, it scores, as chosen")
    eq(Score.Current().name, MAIN_ARMS, "on its main spec")
    local asked = W.leveling.specAsked
    for _ = 1, 50 do Score.Engine() end
    eq(W.leveling.specAsked, asked, "that it is there is not found out anew each time")

    -- An API older than the one that scores, or without a function the addon calls, is one
    -- that cannot be asked.
    ForeverLevelingBiS_API.version = 1
    eq(ns.Leveling.Usable(), false, "its first API had no scores"); eq(Score.Engine(), nil, "and leaves the scoring to the addon")
    ForeverLevelingBiS_API.version = 2
    local kept = ForeverLevelingBiS_API.ScoreItem
    ForeverLevelingBiS_API.ScoreItem = nil
    eq(ns.Leveling.Usable(), false, "one that lacks a function the addon calls"); eq(Score.Engine(), nil, "leaves it to the addon too")
    ForeverLevelingBiS_API.ScoreItem = kept
    eq(Score.Engine(), "leveling", "with everything in place it scores")
    -- What it is asked only where it is there can be missing.
    local gain, keys = ForeverLevelingBiS_API.GetGain, ForeverLevelingBiS_API.GetStatKeys
    ForeverLevelingBiS_API.GetGain, ForeverLevelingBiS_API.GetStatKeys = nil, nil
    eq(ns.Leveling.Usable(), true, "without its word on what a character can wear it still scores")
    eq(Score.ClassCanUse(Score.Item(W.Link(212)), nil), true, "and no weapon is refused for it")
    local parts = Score.Parts(Score.Item(W.Link(200)), MAIN_ARMS, 10)
    eq(#parts, 0, "nor is it an error to ask for a sum without its words for the stats")
    ForeverLevelingBiS_API.GetGain, ForeverLevelingBiS_API.GetStatKeys = gain, keys

    -- Switched off for the next session: the addon's weights again, without a word.
    Relog(W.player, W.equipped)
    W.RemoveLeveling()
    eq(ns.Score.Engine(), nil, "Forever Leveling BiS switched off: the addon scores")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("Forever Leveling BiS switched off")
    eq(UpgradeScoutDB.engine, "leveling", "and the choice still stands")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- With Forever Leveling BiS scoring: while it writes its own block and draws its own arrows,
-- none of ours beside them; with either switched off in its settings, ours in its place, by
-- its score.
function scenarios.leveling_tooltips()
    StandardWorld()
    W.AddItem({ id = 220, name = "Oak Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subClassID = 19, value = 9, level = 5 })
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["212:0"].value2 = 40
    -- A shirt and a trinket that is only used, as most characters wear.
    W.AddItem({ id = 230, name = "Lucky Charm", equipLoc = "INVTYPE_TRINKET", value = 0, level = 1, noStats = true })
    W.equipped[4] = W.Link(207)
    W.equipped[13] = W.Link(230)
    LevelingWorld()
    -- It was chosen in an earlier session.
    UpgradeScoutDB = { engine = "leveling" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score = ns.Score
    local kept = ForeverLevelingBiSDB
    eq(ns.Leveling.Item(W.Link(207)).leveling, false, "a shirt is not gear: there is nothing to read, and that is an answer")
    eq(Score.Context(MAIN_ARMS).unread, nil, "wearing one, the gear is whole")
    eq(Score.Engine(), "leveling", "Forever Leveling BiS scores, as chosen before"); eq(Score.Current().name, MAIN_ARMS, "on the main spec")

    -- What an item does beyond its stats: a use and a chance on hit count as not scored;
    -- what it does while worn is a stat where the game's tables say so.
    local function Effects(id) return Score.HasUnscoredEffects(Score.Item(W.Link(id))) end
    local good = W.items["200:0"]
    eq(Effects(201), true, "a use: not counted"); eq(Effects(200), false, "an item of plain stats")
    good.equipLine = true
    eq(Effects(200), true, "what it does while worn, which the game's tables know no stat for")
    ns.GearData.extra[200] = { ITEM_MOD_ATTACK_POWER_SHORT = 14 }
    eq(Effects(200), false, "the same where they do: counted")
    ns.GearData.extra[200] = nil
    good.equipLine, good.procLine = nil, true
    eq(Effects(200), true, "a chance on hit")
    good.procLine = nil

    -- Does the tooltip have lines of ours? Our header, then what is under it, joined by " | ".
    local function Ours(tooltip)
        local header
        for i, line in ipairs(tooltip._lines) do
            if line.text:find("Upgrade Scout", 1, true) then header = i end
        end
        if not header then return nil end
        local out = {}
        for i = header + 1, #tooltip._lines do
            local line = tooltip._lines[i]
            out[#out + 1] = line.text .. (line.right and " " .. line.right or "")
        end
        return table.concat(out, " | ")
    end
    local function Shown(tooltip, id)
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetHyperlink(W.Link(id))
        return Ours(tooltip)
    end
    eq(Shown(GameTooltip, 200), nil, "no lines of ours for an item in the bags: Forever Leveling BiS writes its own")
    eq(LevelingBlock(GameTooltip), true, "which are there")
    eq(Shown(ItemRefTooltip, 200), nil, "nor for a link in the chat")

    -- The arrows in the bags are its own: none of ours beside them.
    local function Arrow(button)
        local arrow = button.UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local function Bag(slot) return Arrow(ContainerFrameCombinedBags.Items[slot]) end
    local function Grey(slot) return ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow._grey end
    local slot = {}
    for _, id in ipairs({ 200, 202, 203, 204, 208, 212, 214, 220 }) do slot[id] = W.PutInBags(W.Link(id)) end
    W.OpenBags()
    W.Run(1)
    eq(Bag(slot[200]), false, "a better chest: no arrow of ours, Forever Leveling BiS draws its own")
    eq(Bag(slot[203]), false, "nor on one of a higher level"); eq(Bag(slot[212]), false, "nor on a two-hander")
    -- It draws none in the bank: there ours stay, by its score.
    W.bags[6] = { [3] = { link = W.Link(211) }, [4] = { link = W.Link(202) } }
    W.OpenBank(6)
    local bank = {}
    for button in BankPanel:EnumerateValidItems() do bank[button._slot] = button end
    eq(Arrow(bank[3]), true, "the helm in the bank: an arrow of ours, where it draws none")
    eq(Arrow(bank[4]), false, "not the weaker chest in the bank")

    -- Its arrows switched off in its settings: ours are drawn in the bags, by its score.
    kept.bagMarks = false
    W.LevelingChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "its own arrows switched off: ours, on a better chest, 18 against 10 by its score")
    eq(Grey(slot[200]), false, "green: it can be put on now")
    eq(Bag(slot[203]), true, "a better chest of a higher level"); eq(Grey(slot[203]), true, "grey")
    eq(Bag(slot[212]), true, "a two-hander against the sword")
    eq(Bag(slot[202]), false, "not a weaker chest"); eq(Bag(slot[204]), false, "not mail the character has not learned")
    eq(Bag(slot[208]), false, "not a chest with nothing to read"); eq(Bag(slot[220]), false, "not a wand: a warrior never uses one")
    eq(Bag(slot[214]), false, "not a potion")
    -- They can be switched off and on as ever.
    UpgradeScoutDB.arrows = false
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(Bag(slot[200]), false, "ours switched off in the welcome window")
    UpgradeScoutDB.arrows = nil
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(Bag(slot[200]), true, "and on again")
    -- Another main spec chosen in Forever Leveling BiS: the arrows follow.
    W.LevelingChar().spec = "fury"
    W.LevelingChanged()
    W.Run(1)
    eq(Bag(slot[200]), false, "for the other spec the chest is no upgrade: 9 against 12")
    eq(Bag(slot[212]), true, "and the two-hander is one: 40 against nothing")
    W.LevelingChar().spec = nil
    W.LevelingChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "back on the first spec the chest has its arrow")
    -- Its arrows switched on again: ours go from the bags.
    kept.bagMarks = nil
    W.LevelingChanged()
    W.Run(1)
    eq(Bag(slot[200]), false, "its arrows switched on again: ours go")
    eq(Arrow(bank[3]), true, "and stay in the bank")

    -- Its block in a tooltip switched off in its settings. It tells nobody of that: it is
    -- found out the next time a tooltip is up. Then our lines stand in, by its score.
    kept.tooltip = false
    eq(Shown(GameTooltip, 200), "Arms +80%", "its block switched off: our line in a tooltip, for the main spec")
    eq(LevelingBlock(GameTooltip), false, "with nothing of its own")
    local heading
    for _, line in ipairs(GameTooltip._lines) do
        if line.text:find("Upgrade Scout", 1, true) then heading = line.text end
    end
    check(heading:find("Upgrade Scout (Forever Leveling BiS score)", 1, true) ~= nil, "under a heading that says whose score it is: " .. heading)
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    Shown(GameTooltip, 200)
    local single = GameTooltip._lines[#GameTooltip._lines]
    check(single.text:find("Arms (Forever Leveling BiS score)", 1, true) ~= nil, "\"Only my spec\": one line, with whose score it is: " .. single.text)
    eq(single.right, "+80%", "and the gain")
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")
    UpgradeScoutDB.tooltip = false
    ns.Fire("SETTING_CHANGED", "tooltip")
    eq(Shown(GameTooltip, 200), nil, "they go by their box in the welcome window, as with the addon scoring")
    UpgradeScoutDB.tooltip = nil
    ns.Fire("SETTING_CHANGED", "tooltip")
    W.Run(0.5)

    -- A row of the list at the auction house.
    W.player.money = 50000
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    SetView(false, false)
    ScanToEnd()
    W.Run(1)
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    local function Row(name)
        for _, w in ipairs(scrollBox:GetFrames()) do
            local entry = w._shown and w._kind == "Button" and w.entry or nil
            if entry and entry.offer and entry.offer.name == name then return w end
        end
    end
    local function Under(name)
        local row = Row(name)
        check(row ~= nil, name .. " is in the list")
        W.compared = nil
        row:GetScript("OnEnter")(row)
        local ours, theirs = Ours(GameTooltip), LevelingBlock(GameTooltip)
        row:GetScript("OnLeave")(row)
        return ours, theirs
    end
    -- (Its block is still switched off: the gains under a row are ours to write, by their box.)
    local ours, theirs = Under("Good Chest")
    check(ours ~= nil and ours:find("Arms +80%", 1, true) ~= nil, "its block switched off: the gains are ours to write under a row")
    eq(theirs, false, "with nothing of its own")
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Under("Good Chest"), nil, "and they go by their box")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    -- Switched on again: its block, and none of our lines about the score.
    kept.tooltip = nil
    eq(Shown(GameTooltip, 200), nil, "its block switched on again: its lines, and none of ours")
    eq(LevelingBlock(GameTooltip), true, "its own are back")
    W.Run(0.5)
    ours, theirs = Under("Good Chest")
    eq(ours, nil, "a row with nothing to add: no lines of ours, not even the addon's name")
    eq(theirs, true, "Forever Leveling BiS's block stands there, as anywhere"); eq(W.compared, GameTooltip, "and the worn item beside it as ever")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short",
        "a row with something to say about buying: that, under the addon's name, and no gains")
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short", "the score's box unticked: the notes stay")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    CheckLevelingAsked("tooltips and arrows")

    -- The addon's own weights chosen again: its lines are back, and its arrows, which then
    -- stand beside Forever Leveling BiS's own: they are by other weights.
    Score.SetEngine(nil)
    W.Run(1)
    eq(Shown(GameTooltip, 200), "Arms +80% | Protection ~ -25% | Forever Leveling BiS: block",
        "the addon scores again: its lines in the tooltip, and Forever Leveling BiS's own after them")
    eq(Bag(slot[200]), true, "and its arrows, by its own profile")
    eq(#W.errors, 0, "nothing of it is an error")
end
-- The welcome window with Forever Leveling BiS: the fourth answer to who scores, the one
-- button of its main spec in place of the trees, the tooltip's block and the arrows' card out
-- of use while it writes and draws its own, and the window coming up once for a player who
-- has it.
function scenarios.leveling_welcome()
    StandardWorld()
    W.AddItem({ id = 16999, name = "Royal Seal", equipLoc = "INVTYPE_FINGER", quality = 3, level = 54 })
    W.AddItem({ id = 5000, name = "Coral Band", equipLoc = "INVTYPE_FINGER", level = 21 })
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    local L

    -- Without it: the answer is there, and out of reach.
    LoadAddon()
    L = ns.L
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome ~= nil end, 10)
    local window = UpgradeScoutWelcome
    eq(#window.Engines, 4, "who scores: four answers")
    local own, pawn, companion, theirs = unpack(window.Engines)
    eq(theirs.Label:GetText(), "Forever Leveling BiS", "the fourth is Forever Leveling BiS, by its name")
    eq(own.Mark:IsShown(), true, "the addon is the one that does"); eq(theirs.Mark:IsShown(), false, "Forever Leveling BiS is not")
    eq(theirs:GetAlpha(), 0.45, "it cannot be chosen while it is not there: its button is grey")
    eq(theirs.Glow.parts[1]:IsShown(), false, "and does not light up under the mouse")
    local function Hint(button)
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        button:GetScript("OnEnter")(button)
        local said = GameTooltip._lines[1] and GameTooltip._lines[1].text or nil
        button:GetScript("OnLeave")(button)
        return said
    end
    eq(Hint(theirs), L.WELCOME_NO_LEVELING, "the mouse on its grey button: a tooltip says why")
    theirs:Click()
    eq(UpgradeScoutDB.engine, nil, "a click on the grey button does nothing")
    -- The four in one row, each as wide as the others, every name with room on its button.
    check(own._points[1].x < pawn._points[1].x and pawn._points[1].x < companion._points[1].x
        and companion._points[1].x < theirs._points[1].x, "the four side by side")
    eq(own._points[1].y, theirs._points[1].y, "in one row"); near(own:GetWidth(), theirs:GetWidth(), "each as wide as the others")
    check(theirs._points[1].x + theirs:GetWidth() <= window:GetWidth() - 20 + 0.01, "and all of them inside the window")
    check(theirs.Label:GetUnboundedStringWidth() + 17 <= theirs:GetWidth(), "the longest name has room on its button, with the diamond of the one that is lit")
    -- In a wider font a name may not have that room: the buttons then share the row by the
    -- length of their names.
    theirs.Label:SetText("Forever Leveling BiS in a wider font")
    ns.Welcome.Show()
    check(theirs:GetWidth() > own:GetWidth() and own:GetWidth() > pawn:GetWidth(), "a name too long for an equal share: the buttons go by their names")
    check(theirs.Label:GetUnboundedStringWidth() + 17 <= theirs:GetWidth(), "and the long one has its room")
    near(pawn._points[1].x, own._points[1].x + own:GetWidth() + 11, "one after another, with the same gap")
    near(theirs._points[1].x + theirs:GetWidth(), window:GetWidth() - 20, "the row as wide as before")
    theirs.Label:SetText("Forever Leveling BiS")
    ns.Welcome.Show()
    near(own:GetWidth(), theirs:GetWidth(), "the name as it is: each as wide as the others again")
    local height = window:GetHeight()
    window.Done:Click()
    eq(UpgradeScoutDB.welcomed, true, "seen"); eq(UpgradeScoutDB.levelingOffered, nil, "but not with Forever Leveling BiS there to choose")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "without it the window does not come up by itself again")

    -- The player installs Forever Leveling BiS. The window comes up once more, and says why.
    LevelingWorld()
    Relog(W.player, W.equipped)
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome:IsShown() end, 10)
    L = ns.L
    window = UpgradeScoutWelcome
    eq(window.About:GetText(), L.WELCOME_LEVELING_NEW, "it is there now: the window comes up to say that it can be chosen")
    own, pawn, companion, theirs = unpack(window.Engines)
    eq(theirs:GetAlpha(), 1, "its button is no longer grey"); eq(theirs.Glow.parts[1]:IsShown(), true, "and lights up under the mouse")
    eq(Hint(theirs), nil, "with nothing left to explain in a tooltip")
    eq(pawn:GetAlpha(), 0.45, "Pawn's is still grey: Pawn is not there"); eq(companion:GetAlpha(), 0.45, "and so is Forever Companion's")
    eq(own.Mark:IsShown(), true, "the addon scores until another is chosen")
    eq(window:GetHeight(), height, "the window is as tall as without it")

    -- Chosen.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    theirs:Click()
    eq(UpgradeScoutDB.engine, "leveling", "a click chooses Forever Leveling BiS, for the account"); eq(told, 1, "and what keeps scores is told")
    eq(theirs.Mark:IsShown(), true, "its button is lit"); eq(own.Mark:IsShown(), false, "the addon's goes dark")
    local trees = window.Trees
    eq(trees[1].Label:GetText(), "Arms", "one button in place of the trees: the main spec in Forever Leveling BiS")
    eq(trees[1]:IsShown(), true, "it is there"); eq(trees[2]:IsShown(), false, "and no other")
    eq(trees[1].Mark:IsShown(), true, "lit")
    eq(window.Ask:GetText(), L.WELCOME_SCALE_LEVELING:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")),
        "over it, whose main spec it is and where it is chosen")
    trees[1]:Click()
    eq(told, 1, "a click on it changes nothing"); eq(ns.Roster.Me().leveling, nil, "and writes nothing")
    theirs:Click()
    eq(told, 1, "the one that scores clicked again: nothing changes")

    -- The score in a tooltip is Forever Leveling BiS's to write: the block says so, and what
    -- it asks of the score is out of use. The notes are still ours.
    local block, arrows = window.Tips, window.Pair[2]
    local tip, tabs, elsewhere, notes = block.Picture.Tip, block.Tabs, block.Elsewhere, block.Notes
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_LEVELING, "the tooltip's block says that Forever Leveling BiS writes there")
    for name, box in pairs({ ["the addon's tabs"] = tabs, ["the rest of the game"] = elsewhere }) do
        eq(box:IsEnabled(), false, "the score's box for " .. name .. " is out of use"); eq(box:GetChecked(), false, "and empty: " .. name)
        eq(box:GetAlpha(), 0.4, "and dim: " .. name)
    end
    eq(block.All:IsEnabled(), false, "the two buttons are out of use"); eq(block.All:GetAlpha(), 0.35, "and dim")
    eq(notes:IsEnabled(), true, "the box of the notes is in use"); eq(notes:GetChecked(), true, "and ticked")
    eq(tip.Note:IsShown(), true, "the picture has the note"); eq(tip.Lines[1].Title:IsShown(), false, "and no line of the score")

    -- The arrows in the bags are its own too: the card says so, and its box is empty, dim
    -- and out of use.
    local kept = ForeverLevelingBiSDB
    local slot = W.PutInBags(W.Link(200))
    W.OpenBags()
    W.Run(1)
    local function Arrow()
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(arrows.Body:GetText(), L.WELCOME_ARROWS_LEVELING, "the arrows' card says that Forever Leveling BiS draws them")
    eq(arrows.Switch:IsEnabled(), false, "its box is out of use"); eq(arrows.Switch:GetChecked(), false, "and empty")
    eq(arrows.Switch.Tick:IsShown(), false, "without its tick"); eq(arrows.Switch:GetAlpha(), 0.4, "and dim")
    eq(arrows.Title:GetAlpha(), 0.5, "as its name is"); eq(arrows.Picture:GetAlpha(), 0.3, "and the picture is faded")
    arrows.Switch:Click()
    eq(UpgradeScoutDB.arrows, nil, "a click on it changes nothing"); eq(Arrow(), false, "no arrow of ours in the bags")
    -- Its own arrows switched off in its settings: the card is ours again.
    kept.bagMarks = false
    W.LevelingChanged()
    W.Run(0.5)
    eq(arrows.Body:GetText(), L.WELCOME_ARROWS_TEXT, "its own arrows switched off: the card has its own sentence")
    eq(arrows.Switch:IsEnabled(), true, "its box is in use"); eq(arrows.Switch:GetChecked(), true, "and ticked, as it was left")
    eq(arrows.Switch:GetAlpha(), 1, "at full strength"); eq(arrows.Picture:GetAlpha(), 1, "and the picture whole")
    eq(Arrow(), true, "with an arrow of ours on the better chest, by its score")
    kept.bagMarks = nil
    W.LevelingChanged()
    W.Run(0.5)
    eq(arrows.Switch:IsEnabled(), false, "its own switched on again: the card is out of use"); eq(Arrow(), false, "and ours are gone")
    eq(UpgradeScoutDB.arrows, nil, "what the box was left at is kept")

    -- Its block in a tooltip switched off in its settings, of which it tells nobody: the
    -- window finds out when it is next drawn, and the block is ours again.
    kept.tooltip = false
    ns.Welcome.Show()
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_TEXT, "its block switched off: the tooltip's block has its own sentence")
    for name, box in pairs({ ["the addon's tabs"] = tabs, ["the rest of the game"] = elsewhere }) do
        eq(box:IsEnabled(), true, "the score's box for " .. name .. " is in use"); eq(box:GetChecked(), true, "and ticked: " .. name)
        eq(box:GetAlpha(), 1, "and whole: " .. name)
    end
    eq(block.All:IsEnabled(), true, "the two buttons in use"); eq(tip.Lines[1].Title:IsShown(), true, "the picture with the score's lines")
    W.Run(0.5)
    kept.tooltip = nil
    ns.Welcome.Show()
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_LEVELING, "switched on again: Forever Leveling BiS writes there")
    W.Run(0.5)
    eq(told, 1, "none of that is news about the scores")

    -- Another character of the account: the lists for it have our lines, always.
    UpgradeScoutDB.chars["Alty-Testrealm"] = { key = "Alty-Testrealm", name = "Alty", realm = "Testrealm", class = "DRUID", level = 20 }
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_LEVELING_OTHERS, "with another character the block says where our lines are left")
    eq(tabs:IsEnabled(), false, "the box of the tabs is not the player's to change"); eq(tabs:GetChecked(), true, "it is held ticked")
    eq(block.All:IsEnabled(), true, "and the two buttons are in use")
    UpgradeScoutDB.chars["Alty-Testrealm"] = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_LEVELING, "without the other character the block is as it was")

    -- A main spec chosen in Forever Leveling BiS shows here.
    W.LevelingChar().spec = "fury"
    W.LevelingChanged()
    W.Run(0.5)
    eq(trees[1].Label:GetText(), "Fury", "another main spec chosen there is the one on the button"); eq(told, 2, "and what keeps scores is told")
    eq(trees[2]:IsShown(), false, "still the one button")

    -- Closed: seen with Forever Leveling BiS there, so it does not come up by itself again.
    window.Done:Click()
    eq(UpgradeScoutDB.levelingOffered, true, "the choice has been seen with it")
    eq(UpgradeScoutDB.pawnOffered, nil, "and not with Pawn, which was not there"); eq(UpgradeScoutDB.companionOffered, nil, "nor with Forever Companion")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "it does not come up by itself again")
    ns.Welcome.Show()
    eq(window.About:GetText(), L.WELCOME_ABOUT, "asked for, it has its usual first words")

    -- The addon chosen again: the trees, the block and the card as they were.
    own:Click()
    eq(UpgradeScoutDB.engine, nil, "a click on the addon's button: nothing is left written"); eq(own.Mark:IsShown(), true, "its button is lit")
    eq(trees[1].Label:GetText(), "Arms", "the trees are back"); eq(trees[2]:IsShown(), true, "both of them")
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_TEXT, "the tooltip's block has its sentence"); eq(tabs:IsEnabled(), true, "and its boxes in use")
    eq(arrows.Body:GetText(), L.WELCOME_ARROWS_TEXT, "the arrows' card has its sentence"); eq(arrows.Switch:IsEnabled(), true, "and its box in use")
    W.Run(0.5)
    eq(Arrow(), true, "and the arrows in the bags are ours, by the addon's own profile")
    CheckLevelingAsked("the welcome window")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- What a consumable adds, scored on the weights of a spec of Forever Leveling BiS: the game's
-- names for stats put into its own, and a chance into the percent it weighs.
function scenarios.leveling_supplies()
    StandardWorld()
    SuppliesWorld()
    LevelingWorld()
    UpgradeScoutDB = { engine = "leveling" }
    LoadAddon()
    SupplyFacts()
    local Score = ns.Score
    eq(Score.Engine(), "leveling", "Forever Leveling BiS scores")
    local CASTS, HEALS = "DRUID:balance", "DRUID:restoration"
    local DAMAGE, HEALING = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
    local function Value(stats, id, level) return Score.StatsValue(stats, id, level) end

    near(Value({ ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_AGILITY_SHORT = 4 }, MAIN_ARMS), 8 * 1.5 + 4, "stats under its names, by the spec's weights")
    near(Value({ ITEM_MOD_CRIT_RATING_SHORT = 28 }, MAIN_ARMS), 2 * 8, "a chance: 28 points of rating are the 2% it weighs")
    near(Value({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, MAIN_ARMS), 2 * 8, "a chance with weapons counts on a fighter's weights")
    near(Value({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, CASTS, 20), 0, "and not on a caster's")
    near(Value({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, CASTS, 20), 6, "a chance with spells counts on a caster's weights")
    near(Value({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, MAIN_ARMS), 0, "and not on a fighter's")
    near(Value({ ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, CASTS, 20), 12, "both kinds add up for the one who uses both")
    near(Value({ ITEM_MOD_ATTACK_POWER_SHORT = 10 }, MAIN_ARMS), 4, "attack power")
    near(Value({ ITEM_MOD_MELEE_ATTACK_POWER_SHORT = 10 }, MAIN_ARMS), 4, "attack power with weapons in hand is plain attack power, of a consumable")
    -- What adds to spells is three stats there: to damage and healing alike, to the one, to
    -- the other.
    near(Value({ [DAMAGE] = 36 }, CASTS, 20), 36, "spell damage alone, under its own name")
    near(Value({ [DAMAGE] = 20, [HEALING] = 20 }, CASTS, 20), 20, "damage and healing alike are spell power, counted once")
    near(Value({ [HEALING] = 20 }, CASTS, 20), 0, "healing alone is nothing to weights without one for it")
    near(Value({ [DAMAGE] = 36 }, HEALS, 20), 0, "damage alone is nothing to a healer's")
    near(Value({ [DAMAGE] = 20, [HEALING] = 20 }, HEALS, 20), 20, "damage and healing alike: spell power")
    near(Value({ [HEALING] = 10 }, HEALS, 20), 10, "healing alone: healing")
    near(Value({ [DAMAGE] = 30, [HEALING] = 40 }, HEALS, 20), 30 + 10, "more of the one than of the other: each part under its name")
    near(Value({ ITEM_MOD_HEALTH_SHORT = 25 }, MAIN_ARMS), 2.5 * 0.5, "health as the Stamina that gives it: Forever Leveling BiS has no stat for it")
    near(Value({ ITEM_MOD_MANA_SHORT = 30 }, CASTS, 20), 2, "mana as Intellect")
    near(Value({ ITEM_MOD_UNHEARD_OF_SHORT = 99 }, MAIN_ARMS), 0, "a stat it has no name for counts for nothing")
    near(Value({ ITEM_MOD_SPIRIT_SHORT = 8 }, MAIN_ARMS), 0, "nor does one the spec does not weigh")
    eq(Value({ ITEM_MOD_STRENGTH_SHORT = 8 }, "MAGE:frost", 20), nil, "no answer for a spec it has no weights for")
    eq(Value({ ITEM_MOD_STRENGTH_SHORT = 8 }, "S1"), nil, "nor for one of the addon's own profiles")

    -- Its weights change with the level, and are asked for by the character's.
    W.SetLevelingWeights("DRUID", "bear", function(level) return { sta = level >= 40 and 2 or 1 } end)
    near(Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 20), 10, "a druid of 20: the weights of that level")
    near(Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 45), 20, "one of 45: another level's")
    local last = W.leveling.weighed[#W.leveling.weighed]
    eq(last.class, "DRUID", "asked for by the class"); eq(last.spec, "bear", "the spec"); eq(last.level, 45, "and the level")
    local times = #W.leveling.weighed
    Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 45)
    Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 20)
    eq(#W.leveling.weighed, times, "the same weights are not asked for twice")
    -- A spec with weights for each way of filling the hands is asked about with the one named.
    W.SetLevelingWeights("DRUID", "feral", function(_, setup) return { agi = setup == "held" and 3 or 1 } end)
    W.LevelingChanged()
    W.Run(0.5)
    near(Value({ ITEM_MOD_AGILITY_SHORT = 10 }, "DRUID:feral:held", 20), 30, "a weapon setup named in the profile is the one asked about")
    near(Value({ ITEM_MOD_AGILITY_SHORT = 10 }, "DRUID:feral", 20), 10, "none named: the spec's usual one")

    -- The list of consumables is scored on the spec.
    W.OpenAuctionHouse()
    ScanSupplies()
    local rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(MAIN_ARMS, { mana = false }))
    local function Worth(name)
        for _, row in ipairs(rows) do
            if row.kind == "supply" and row.entry.supply.name == name then return row.entry.value end
        end
    end
    near(Worth("Elixir of Giants"), 25 * 1.5, "an elixir of Strength on a fighter's weights"); near(Worth("Elixir of Agility"), 15, "one of Agility")
    eq(Worth("Elixir of Wisdom"), nil, "Intellect is of no use to that spec")
    rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(CASTS, { mana = true }))
    near(Worth("Elixir of Wisdom"), 6, "and worth its weight to a caster's")
    -- The heading over a consumable's score says whose score it is.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    ns.Tooltip.AddHeader(GameTooltip, "Arms", true)
    local heading = GameTooltip._lines[#GameTooltip._lines]
    check(heading.text:find("Upgrade Scout (Forever Leveling BiS score)", 1, true) ~= nil, "a heading over a score, with Forever Leveling BiS scoring: " .. heading.text)
    eq(heading.right, "Arms", "with what stands on its right")
    ns.Tooltip.AddHeader(GameTooltip)
    heading = GameTooltip._lines[#GameTooltip._lines]
    eq(heading.text:find("Forever Leveling BiS", 1, true), nil, "a heading over notes alone names no other addon")
    eq(#W.leveling.asked, 0, "no item was asked about for any of it")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- Another character of the account: the specs of its class, its items scored from the
-- weights of its spec at its level, its own choice written on its card, and Forever Leveling
-- BiS's block, which is about the character being played, kept out of the rows of its list.
function scenarios.leveling_alt()
    StandardWorld()
    local warrior, warriorGear = W.player, W.equipped
    -- The druid's chests, by the game's own count of their stats: Intellect, Agility, and on
    -- the one for sale 1% to crit, which the game counts as 14 points of rating.
    W.AddItem({ id = 300, name = "Alt's Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, level = 15,
        values = { D1 = 0 }, game = { ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_AGILITY_SHORT = 3 } })
    W.AddItem({ id = 310, name = "Druid Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, level = 18,
        values = { D1 = 0 }, game = { ITEM_MOD_INTELLECT_SHORT = 14, ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_CRIT_RATING_SHORT = 14 } })
    W.AddAuction(310, 2000)
    LevelingWorld()
    UpgradeScoutDB = { engine = "leveling" }

    -- The druid is played once, and its main spec chosen in Forever Leveling BiS.
    W.Login(Druid())
    W.equipped = { [5] = W.Link(300) }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(ns.Score.Current().name, "@DRUID:balance:twohand", "the druid, played: its main spec in Forever Leveling BiS")
    W.LevelingChar().spec = "feral"
    Relog(warrior, warriorGear)
    TreeNames()
    local Score, S = ns.Score, ns.Scanner
    local kept = ForeverLevelingBiSDB
    local card = UpgradeScoutDB.chars["Alty-Testrealm"]
    check(card ~= nil, "the druid is remembered")

    local current, theirs = Score.Current(card)
    eq(#theirs, 4, "another character: every spec Forever Leveling BiS has for its class")
    eq(theirs[1].name, "DRUID:balance", "by its class and its key there"); eq(theirs[1].title, "Balance", "and the name of its tree")
    eq(current.name, "DRUID:feral", "the one in use: its main spec as Forever Leveling BiS last saved it")
    eq(#Score.Profiles(ns.Roster.Me()), 1, "the card of the character being played is that character")

    -- At the auction house the field lists them under the warrior's one line.
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    local ALTY = "|cffff7c0aAlty|r"
    eq(#dropdown.radios, 5, "the warrior's main spec and the druid's four specs")
    eq(dropdown.radios[1].text, "Arms", "the warrior's own")
    eq(dropdown.radios[2].text, ALTY .. ": Balance", "the druid's by its name and the spec's")
    eq(dropdown.radios[3].text, ALTY .. ": Feral Combat (Cat)", "each of them")
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(4)
    eq(ns.Roster.Target(), card, "the lists are for the druid"); eq(card.leveling, "bear", "on the spec chosen, written on its card by its key")
    dropdown:Pick(2)
    eq(card.leveling, "balance", "another of its specs chosen")
    eq(kept.chars["Alty-Testrealm"].spec, "feral", "and nothing is written into what Forever Leveling BiS keeps")
    eq(card.profile, nil, "apart from the addon's own profile"); eq(card.scale, nil, "from the Pawn scale")
    eq(card.companion, nil, "and from Forever Companion's")
    local scored = #W.leveling.asked
    frame.ScanButton:Click()
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(1)
    eq(S.ctx.who, card, "the scan was for the druid"); eq(S.ctx.profile, "DRUID:balance", "on its spec")
    near(S.ctx.equipped[5].value, 12, "its chest: 12 Intellect, by the weights of that spec")
    check(Offer("Druid Jerkin") ~= nil, "a jerkin better than the druid's")
    near(Offer("Druid Jerkin").value, 20, "14 Intellect and the 1% to crit: the game's 14 points of rating, weighed by the percent")
    eq(Offer("Good Chest"), nil, "the warrior's upgrades are not the druid's")
    eq(#W.leveling.asked, scored, "Forever Leveling BiS is asked for the score of no item: that is for the character being played")
    local levels = {}
    for _, weighed in ipairs(W.leveling.weighed) do
        if weighed.class == "DRUID" and weighed.spec == "balance" then levels[weighed.level] = true end
    end
    eq(levels[20], true, "its weights are asked for by the druid's class, spec and level"); eq(levels[10], nil, "not by the warrior's")

    -- A row's tooltip has our lines here: Forever Leveling BiS's block is about the character
    -- being played, and is kept out.
    local scrollBox
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then scrollBox = w end
    end
    local function Row(name)
        for _, w in ipairs(scrollBox:GetFrames()) do
            local entry = w._shown and w._kind == "Button" and w.entry or nil
            if entry and entry.offer and entry.offer.name == name then return w end
        end
    end
    local function ListFor(index)
        dropdown:Pick(index)
        W.Run(0.5)
        if S.state == "idle" then frame.ScanButton:Click() end
        W.RunUntil(function() return S.state == "idle" end, 300)
        W.Run(1)
    end
    local function Elsewhere()
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink(W.Link(310))
        return LevelingBlock(GameTooltip)
    end
    local jerkin = Row("Druid Jerkin")
    check(jerkin ~= nil, "the jerkin is in the list")
    jerkin:GetScript("OnEnter")(jerkin)
    local doubles = {}
    for _, line in ipairs(GameTooltip._lines) do
        if line.right then doubles[#doubles + 1] = line end
    end
    eq(doubles[1].right, ALTY, "a list for another character: our header, which says whose")
    check(doubles[1].text:find("Upgrade Scout (Forever Leveling BiS score)", 1, true) ~= nil, "and that the score in our lines is Forever Leveling BiS's: " .. doubles[1].text)
    eq(doubles[2].text, "Balance", "then the druid's specs"); eq(doubles[2].right, "+67%", "with the gain on each: 20 against 12")
    eq(doubles[3].text, "Feral Combat (Cat)", "on the next"); eq(doubles[3].right, "-33%", "2 Agility against 3")
    eq(doubles[4].text, "Feral Combat (Bear)", "on the third"); eq(doubles[5].text, "Restoration", "and the fourth")
    eq(doubles[5].right, "+17%", "half of 14 Intellect against half of 12")
    eq(ShoppingTooltip1:IsShown(), true, "and the druid's chest beside it")
    eq(LevelingBlock(GameTooltip), false, "Forever Leveling BiS's block is kept out of a row for another character")
    eq(rawget(kept, "tooltip"), nil, "and its switch for the block is afterwards as it was: never touched")
    jerkin:GetScript("OnLeave")(jerkin)
    eq(Elsewhere(), true, "anywhere else it writes its block")
    -- A player who has touched that switch: it is put back as they have it.
    kept.tooltip = true
    jerkin:GetScript("OnEnter")(jerkin)
    eq(LevelingBlock(GameTooltip), false, "kept out the same way"); eq(rawget(kept, "tooltip"), true, "and the switch is as that player has it")
    jerkin:GetScript("OnLeave")(jerkin)
    kept.tooltip = nil
    -- Something goes wrong while the tooltip is filled in: the error passes on, with the
    -- switch put back.
    local passed
    local ok, problem = pcall(ns.Leveling.Hushed, function(what) passed = what error("no such item", 0) end, "a link")
    eq(ok, false, "an error in filling the tooltip in passes on"); eq(problem, "no such item", "as it was")
    eq(passed, "a link", "what fills it in is called with what it was given"); eq(rawget(kept, "tooltip"), nil, "and the switch is put back all the same")
    -- While its block is kept out, the addon does not take it for switched off.
    local during
    ns.Leveling.Hushed(function() during = ns.Leveling.WritesTooltip() end)
    eq(during, true, "kept out for a moment, it is still the one that writes the score")
    -- Our lines are all that says the score there, so they do not go by their box.
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    jerkin:GetScript("OnEnter")(jerkin)
    eq(GameTooltip._lines[#GameTooltip._lines].right, "+17%", "our lines unticked for the tabs: they still stand in a list for another character")
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    -- One line for the spec in use says whose score it is after the spec's name.
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    jerkin:GetScript("OnEnter")(jerkin)
    local single = GameTooltip._lines[#GameTooltip._lines]
    check(single.text:find(ALTY .. ": Balance (Forever Leveling BiS score)", 1, true) ~= nil, "\"Only my spec\": one line, with whose score it is: " .. single.text)
    eq(single.right, "+67%", "and the gain")
    jerkin:GetScript("OnLeave")(jerkin)
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")

    -- A weapon for that character: its damage per second by the weight of the hand it is in,
    -- and its speed, which the game keeps in the words of the tooltip.
    local CLAWS = "DRUID:feral"
    W.AddItem({ id = 320, name = "Cat Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10, value = 0, level = 10, speed = 3.6,
        game = { ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20, ITEM_MOD_MELEE_ATTACK_POWER_SHORT = 40 } })
    W.AddItem({ id = 321, name = "Claw", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 13, value = 0, level = 10, speed = 2.0,
        game = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } })
    W.AddItem({ id = 322, name = "Sling", equipLoc = "INVTYPE_RANGED", classID = 2, subClassID = 2, value = 0, level = 10, speed = 2.8,
        game = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 1 } })
    local function Worth(id, offHand) return Score.Value(Score.Item(W.Link(id)), CLAWS, 20, offHand) end
    local function Feral(weights)
        W.SetLevelingWeights("DRUID", "feral", weights)
        W.LevelingChanged()
        W.Run(0.5)
    end
    near(Worth(320), 5 + 40 * 0.5 + 20 * 3, "a staff: its stats, the attack power it gives a druid's shapes, and its damage per second")
    near(Worth(321), 30, "a weapon for one hand, in the main hand"); near(Worth(321, true), 15, "in the off hand: half, where the spec names no weight for it")
    near(Score.OffValue(Score.Item(W.Link(321)), CLAWS, 20), 15, "which is its second score")
    near(Worth(322), 1, "a ranged weapon by the weight for those, which this spec has none of")
    Feral({ agi = 1, feratkpwr = 0.5, dps = 3, ohDps = 1, rangedDps = 2, speed = 2 })
    near(Worth(320), 85 + (3.6 - 3.3) * 10 * 2, "a weight for speed: for each tenth of a second slower than a two-hander's usual 3.3")
    near(Worth(321), 30 + (2.0 - 2.4) * 10 * 2, "a one-hander against the usual 2.4: faster counts against it")
    near(Worth(321, true), 10, "the off hand by its own weight, with none for its speed"); near(Worth(322), 1 + 20, "a ranged weapon by its own")
    Feral({ agi = 1, feratkpwr = 0.5, dps = 3, speed = 2, speedRef = 3.0 })
    near(Worth(320), 85 + (3.6 - 3.0) * 10 * 2, "the speed the weights were measured at, where they name it")
    Feral({ agi = 1, feratkpwr = 0.5, dps = 3, speed = -100 })
    near(Worth(320), 5 + 40 * 0.5, "speed can cancel a weapon's damage, and take it no lower than nothing")
    W.items["320:0"].speedText = "Tempo 3,60"
    Feral({ agi = 1, feratkpwr = 0.5, dps = 3, speed = 2 })
    near(Worth(320), 85 + (3.6 - 3.3) * 10 * 2, "a speed written with a comma, as some languages do")
    Feral({ agi = 1, str = 1, feratkpwr = 0.5, dps = 3 })

    -- The warrior's own list: Forever Leveling BiS writes there as everywhere.
    ListFor(1)
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own again")
    local chest = Row("Good Chest")
    check(chest ~= nil, "a better chest for the warrior is in the list")
    chest:GetScript("OnEnter")(chest)
    eq(LevelingBlock(GameTooltip), true, "a row of the player's own list: its block, as anywhere")
    chest:GetScript("OnLeave")(chest)
    CheckLevelingAsked("another character")

    -- The addon's own weights chosen, with Forever Leveling BiS still installed: it writes
    -- into tooltips as before, and is kept out of a list for another character the same way.
    W.items["300:0"].values, W.items["310:0"].values = { D1 = 12, D2 = 3 }, { D1 = 20, D2 = 2 }
    W.items["300:0"].game, W.items["310:0"].game = nil, nil
    Score.SetEngine(nil)
    W.Run(1)
    W.RunUntil(function() return S.state == "idle" end, 300)
    ListFor(3)
    eq(ns.Roster.Target(), card, "the addon scores, and the lists are for the druid")
    jerkin = Row("Druid Jerkin")
    check(jerkin ~= nil, "the jerkin is in the druid's list by the addon's own weights")
    jerkin:GetScript("OnEnter")(jerkin)
    eq(LevelingBlock(GameTooltip), false, "the addon scoring: its block is kept out of a row for another character")
    local ours, marked = false, false
    for _, line in ipairs(GameTooltip._lines) do
        if line.right == ALTY then ours = true end
        if line.text:find("Forever Leveling BiS score", 1, true) then marked = true end
    end
    eq(ours, true, "under our header, which says whose list it is")
    eq(marked, false, "and names no other addon: the score is the addon's own")
    jerkin:GetScript("OnLeave")(jerkin)
    eq(Elsewhere(), true, "and it writes on everywhere else")

    -- Without Forever Leveling BiS there is nobody to keep out: the tooltip is filled in and no more.
    W.RemoveLeveling()
    local filled
    ns.Leveling.Hushed(function(what) filled = what end, "a link")
    eq(filled, "a link", "no Forever Leveling BiS: what fills the tooltip in is called")
    eq(#W.errors, 0, "nothing of it is an error")
end

---------------------------------------------------------------------------
-- What a character wants of its gear (Wants.lua), and the menu its two filters are in
---------------------------------------------------------------------------
-- The standard world with more for sale. For the empty head a leather cap and a cloth hood
-- beside the mail helm; a cloak; and two more chests of mail, which add a half and a fifth to
-- the worn one's 10. With those, a warrior's upgrades are:
--   head        Hide Cap (leather), Silk Hood (cloth), Helm (mail): all new
--   chest       Great Chest (a cloth robe, +200%), Good Chest (+80%), Fine Chest (+50%),
--               Fair Chest (+20%): the last three mail
--   the rest    Wool Cloak, New Ring and Shield, all new, and Big Axe (+30%)
local function WantsWorld()
    StandardWorld()
    local function Sell(def, price)
        W.AddItem(def)
        W.AddAuction(def.id, price)
    end
    Sell({ id = 240, name = "Hide Cap", equipLoc = "INVTYPE_HEAD", subClassID = 2, value = 15, level = 9 }, 300)
    Sell({ id = 241, name = "Silk Hood", equipLoc = "INVTYPE_HEAD", subClassID = 1, value = 14, level = 9 }, 200)
    Sell({ id = 242, name = "Wool Cloak", equipLoc = "INVTYPE_CLOAK", subClassID = 1, value = 5, level = 8 }, 150)
    Sell({ id = 243, name = "Fine Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 15, level = 9 }, 1500)
    Sell({ id = 244, name = "Fair Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 12, level = 9 }, 300)
end

-- The two filters themselves, and what they do to a scan, to the list and to a set.
function scenarios.wants()
    WantsWorld()
    LoadAddon()
    local Wants, S = ns.Wants, ns.Scanner

    -- Which items a choice of armor is about: what covers the body.
    eq(Wants.ArmorOf("INVTYPE_CHEST", 4, 2), 2, "a leather chest is leather")
    eq(Wants.ArmorOf("INVTYPE_ROBE", 4, 1), 1, "a robe is cloth")
    eq(Wants.ArmorOf("INVTYPE_FEET", 4, 4), 4, "plate boots are plate")
    eq(Wants.ArmorOf("INVTYPE_CLOAK", 4, 1), nil, "a cloak is cloth for everyone: no choice there")
    eq(Wants.ArmorOf("INVTYPE_SHIELD", 4, 6), nil, "nor with a shield")
    eq(Wants.ArmorOf("INVTYPE_FINGER", 4, 0), nil, "a ring"); eq(Wants.ArmorOf("INVTYPE_HOLDABLE", 4, 0), nil, "or what is held in the hand")
    eq(Wants.ArmorOf("INVTYPE_2HWEAPON", 2, 1), nil, "a two-handed axe is a weapon, whatever the number of its kind")
    eq(Wants.ArmorOf(nil, 4, 2), nil, "nothing for what is not worn")

    -- The heaviest armor a character wears now.
    local function Armor(class, level, learned)
        return Wants.Armor({ class = class, level = level, armor = learned })
    end
    eq(Armor("HUNTER", 10), 2, "a hunter: leather"); eq(Armor("HUNTER", 40), 3, "and mail from level 40")
    eq(Armor("SHAMAN", 39), 2, "a shaman the same"); eq(Armor("SHAMAN", 40), 3, "at the same level")
    eq(Armor("WARRIOR", 10), 3, "a warrior: mail"); eq(Armor("WARRIOR", 40), 4, "and plate from 40")
    eq(Armor("PALADIN", 39), 3, "a paladin the same"); eq(Armor("PALADIN", 60), 4, "then plate")
    eq(Armor("ROGUE", 60), 2, "a rogue: leather for good"); eq(Armor("DRUID", 60), 2, "a druid too")
    eq(Armor("MAGE", 60), nil, "a mage wears cloth alone: nothing to leave out")
    eq(Armor("PRIEST", 60), nil, "nor has a priest"); eq(Armor("WARLOCK", 60), nil, "or a warlock")
    -- Where the game has said what the character learned, that decides, not its level: mail
    -- and plate are taught by a trainer.
    eq(Armor("HUNTER", 45, { [1] = true, [2] = true }), 2, "a hunter of 45 who never went to the trainer: leather still")
    eq(Armor("HUNTER", 40, { [1] = true, [2] = true, [3] = true }), 3, "mail once it is learned")
    eq(Wants.Armor(nil), nil, "no character, no armor")

    -- What a card asks for.
    local hunter = { class = "HUNTER", level = 20 }
    eq(Wants.Of(hunter), nil, "nothing ticked: nothing is asked")
    hunter.armorOnly = true
    eq(Wants.Of(hunter).armor, 2, "only leather"); eq(Wants.Of(hunter).gain, nil, "and any gain")
    check(Wants.Of(hunter) == Wants.Of({ class = "ROGUE", level = 5, armorOnly = true }), "the same wants are one table")
    hunter.level = 40
    eq(Wants.Of(hunter).armor, 3, "the tick goes with the character to mail")
    eq(Wants.Of({ class = "MAGE", level = 30, armorOnly = true }), nil, "a tick on the card of one who wears cloth alone asks for nothing")
    hunter.armorOnly = nil
    eq(Wants.Gain(hunter), 10, "the number before one is typed")
    hunter.minGain = 50
    eq(Wants.Of(hunter), nil, "a number alone asks for nothing")
    hunter.minGainOn = true
    eq(Wants.Of(hunter).gain, 50, "ticked: at least that"); eq(Wants.Of(hunter).armor, nil, "of any armor")
    local told = 0
    ns.Listen("WANTS_CHANGED", function(card) if card == hunter then told = told + 1 end end)
    Wants.SetGain(hunter, true, 12345)
    eq(hunter.minGain, 9999, "no more than four digits")
    Wants.SetGain(hunter, true, 0.4)
    eq(hunter.minGain, 1, "and no less than one")
    Wants.SetGain(hunter, false)
    eq(hunter.minGainOn, nil, "unticked"); eq(hunter.minGain, 1, "the number stays"); eq(told, 3, "the addon is told each time")
    Wants.SetArmorOnly(hunter, true)
    eq(hunter.armorOnly, true, "the other box"); eq(told, 4, "of which it is told as well")
    hunter.minGain = "many"
    eq(Wants.Gain(hunter), 10, "a card with no number for a number has the first one")

    -- The percent is held against the number as the list writes it, rounded.
    local half = { gain = 50 }
    eq(Wants.Enough(half, { percent = 0.5 }), true, "+50% is at least 50")
    eq(Wants.Enough(half, { percent = 0.4951 }), true, "and so is what the list writes as +50%")
    eq(Wants.Enough(half, { percent = 0.4949 }), false, "what it writes as +49% is not")
    eq(Wants.Enough(half, { delta = 12 }), true, "a gain with no percent to it, in an empty slot, is more than any")
    eq(Wants.Enough(nil, { percent = 0.01 }), true, "nothing asked: anything will do")

    -- A scan.
    W.OpenAuctionHouse()
    local me = ns.Roster.Me()
    local function Scan()
        W.RunUntil(function() return W.AH.ready end, 5)
        local before = W.AH.calls.search
        ScanToEnd()
        return W.AH.calls.search - before
    end
    local function More()
        local before = W.AH.calls.search
        if not S.Demand() then return 0 end
        W.RunUntil(function() return S.state == "idle" end, 600)
        return W.AH.calls.search - before
    end
    -- The upgrades the list shows with the tab's own two filters off, by name; and how many
    -- the character's filters leave out.
    local function Shown()
        local rows, summary = ns.Results.Build(S.offers, S.ctx, { money = GetMoney(), wants = Wants.Of(me), unchecked = S.Unchecked() })
        local out, seen = {}, {}
        for _, row in ipairs(rows) do
            local name = row.kind == "item" and row.entry.offer.name
            if name and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
        table.sort(out)
        return table.concat(out, ", "), summary.unwanted
    end
    local EVERYTHING = "Big Axe, Fair Chest, Fine Chest, Good Chest, Great Chest, Helm, Hide Cap, New Ring, Shield, Silk Hood, Wool Cloak"
    local MAIL = "Big Axe, Fair Chest, Fine Chest, Good Chest, Helm, New Ring, Shield, Wool Cloak"
    local HALF = "Fine Chest, Good Chest, Great Chest, Helm, Hide Cap, New Ring, Shield, Silk Hood, Wool Cloak"

    -- Reference: nothing asked, and the tab's own filters off, so every price is looked up.
    SetView(false, false)
    local all = Scan()
    local list, unwanted = Shown()
    eq(OfferCount(), 11, "eleven upgrades for sale"); eq(list, EVERYTHING, "all of them listed"); eq(unwanted, 0, "none left out")

    -- The best armor type, mail for a warrior of level 10, ticked with every price known: the
    -- list is without the lighter armor.
    Wants.SetArmorOnly(me, true)
    list, unwanted = Shown()
    eq(list, MAIL, "no leather cap, no cloth hood, no robe; the cloak, the ring and the weapons as before")
    eq(unwanted, 3, "three upgrades left out")
    -- A scan with it ticked looks up no price for those three.
    eq(Scan(), all - 3, "three item searches fewer")
    eq(Offer("Hide Cap"), nil, "no price for the cap"); eq(Offer("Silk Hood"), nil, "the hood"); eq(Offer("Great Chest"), nil, "or the robe")
    check(Unsure("Hide Cap") ~= nil and Unsure("Silk Hood") ~= nil and Unsure("Great Chest") ~= nil, "which are counted at the lowest price of their rows")
    list, unwanted = Shown()
    eq(list, MAIL, "the same list"); eq(unwanted, 3, "and the same count")
    eq(S.Demand(), false, "nothing more is needed for the list as it is")
    -- Unticked: their prices are asked for, and no others.
    Wants.SetArmorOnly(me, false)
    eq(More(), 3, "unticked: three searches")
    eq(OfferCount(), 11, "and every upgrade has its price"); eq(Shown(), EVERYTHING, "and is listed")

    -- "Upgrade at least 50%": the fair chest (+20%) and the axe (+30%) add too little. The fine
    -- chest adds exactly a half; what goes into an empty slot stays whatever the number.
    Wants.SetGain(me, true, 50)
    list, unwanted = Shown()
    eq(list, HALF, "the list of what adds a half or more"); eq(unwanted, 2, "two left out")
    eq(Scan(), all - 2, "a scan looks up no price for those two")
    eq(Offer("Fair Chest"), nil, "the fair chest"); eq(Offer("Big Axe"), nil, "and the axe")
    check(Unsure("Fair Chest") ~= nil and Unsure("Big Axe") ~= nil, "counted without a search")
    -- A smaller number asks for the prices it lets in.
    Wants.SetGain(me, true, 25)
    eq(More(), 1, "at least 25: one search, for the axe")
    check(Offer("Big Axe") ~= nil, "which has its price now"); eq(Offer("Fair Chest"), nil, "the fair chest still adds too little")
    Wants.SetGain(me, true, 51)
    eq(Shown(), "Good Chest, Great Chest, Helm, Hide Cap, New Ring, Shield, Silk Hood, Wool Cloak", "at least 51: the fine chest's +50% falls short")
    eq(More(), 0, "a bigger number asks for nothing")
    -- Both.
    Wants.SetArmorOnly(me, true)
    list, unwanted = Shown()
    eq(list, "Good Chest, Helm, New Ring, Shield, Wool Cloak", "both: mail that adds over a half, and what is no matter of armor")
    eq(unwanted, 6, "six left out, each counted once: three for their armor, three for their gain")
    Wants.SetArmorOnly(me, false)
    Wants.SetGain(me, false)
    eq(More(), 1, "nothing asked any more: the fair chest's price is looked up")

    -- "Top 5 per slot" is judged among what the character would have. The leather cap is
    -- stronger than the mail helm and cheaper per point, so top five has no use for the helm;
    -- with mail alone the helm is the best there is for the head.
    SetView(false, true)
    Scan()
    eq(Offer("Helm"), nil, "top five: no price for the helm"); check(Offer("Hide Cap") ~= nil, "the cap outdoes it")
    Wants.SetArmorOnly(me, true)
    check(More() >= 1, "only mail: the helm's price is asked for")
    check(Offer("Helm") ~= nil, "and found")
    Scan()
    check(Offer("Helm") ~= nil, "a scan with both ticked looks it up as well"); eq(Offer("Hide Cap"), nil, "and not the cap")
    Wants.SetArmorOnly(me, false)
    SetView(false, false)

    -- The best set for a budget is made of what the character would have. Worn: a chest and
    -- boots worth 10 each. For sale: a cloth chest (+100%), a mail one (+60%) and mail boots (+20%).
    local Plan = ns.Plan
    local GOLD = 10000
    local function Worn(id, invType, value)
        return { link = "worn" .. id, itemID = id, invType = invType, value = value }
    end
    local function For(id, invType, value, buyout, armor)
        return { id = "o" .. id, itemID = id, invType = invType, value = value, buyout = buyout, link = "link" .. id, name = "Item " .. id, count = 1, armor = armor }
    end
    local ctx = { equipped = { [5] = Worn(1, "INVTYPE_CHEST", 10), [8] = Worn(2, "INVTYPE_FEET", 10) }, dualWield = false }
    local offers = {}
    for _, offer in ipairs({ For(11, "INVTYPE_CHEST", 20, 4 * GOLD, 1), For(12, "INVTYPE_CHEST", 16, 3 * GOLD, 3), For(13, "INVTYPE_FEET", 12, 2 * GOLD, 3) }) do
        offers[offer.id] = offer
    end
    local function Best(wants)
        local rows = Plan.Rows(Plan.Choose(Plan.Ladder(offers, ctx, 10 * GOLD, wants), 10 * GOLD))
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.itemID .. ":+" .. ns.Num(row.entry.delta) end
        end
        return table.concat(out, " ")
    end
    eq(Best(nil), "11:+10 13:+2", "nothing asked: the strong chest and the boots")
    eq(Best({ armor = 3 }), "12:+6 13:+2", "only mail: the mail chest in the cloth one's place")
    eq(Best({ gain = 50 }), "11:+10", "at least 50%: no boots")
    eq(Best({ armor = 3, gain = 50 }), "12:+6", "both: the mail chest alone")
    eq(Best({ armor = 3, gain = 70 }), "", "and nothing where nothing passes")

    -- For an hour while 2.6.0 was made the two were the account's, and that build wiped what
    -- the cards held. What it left ticked goes back onto the cards, onto every one of them.
    local saved = UpgradeScoutDB
    saved.bestArmor, saved.minGain, saved.minGainOn = true, 40, true
    me.armorOnly, me.minGain, me.minGainOn = nil, nil, nil
    saved.chars["Alty-Testrealm"] = { key = "Alty-Testrealm", name = "Alty", realm = "Testrealm", faction = "Alliance",
        class = "DRUID", level = 20, gear = {} }
    Relog(W.player, W.equipped)
    eq(saved.bestArmor, nil, "nothing of it is left with the account"); eq(saved.minGain, nil, "nor the number"); eq(saved.minGainOn, nil, "nor its tick")
    for key, card in pairs(saved.chars) do
        check(card.armorOnly == true and card.minGain == 40 and card.minGainOn == true, "the card of " .. key .. " has all of it")
    end
    local wants = ns.Wants.Of(ns.Roster.Me())
    eq(wants.armor, 3, "and it is asked of the character being played"); eq(wants.gain, 40, "with that number")
end

-- "Best armor type for the class" in the Filters menu of the Upgrades tab: the same words for
-- every class, and for every character a tick of its own, kept with the character the list
-- is for, whoever shops for it.
function scenarios.wants_ui()
    WantsWorld()
    local warrior, warriorGear = W.player, W.equipped
    -- A druid of the account, in a leather jerkin. For sale for it: a better jerkin, and a
    -- cloth robe that is better still.
    W.AddItem({ id = 300, name = "Alt's Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 12 }, level = 15 })
    W.AddItem({ id = 310, name = "Druid Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, values = { D1 = 20 }, level = 18 })
    W.AddItem({ id = 311, name = "Druid Robe", equipLoc = "INVTYPE_ROBE", subClassID = 1, value = 0, values = { D1 = 25 }, level = 18 })
    W.AddAuction(310, 2000)
    W.AddAuction(311, 1000)
    local LABEL, SHORT = "Best armor type for the class", "Best armor"
    local MENU = "Only what I can afford | Buyout up to | Top 5 per slot | " .. LABEL .. " | Upgrade at least | / | Value by net cost"
    -- The box of the menu in view, and the last line of its tooltip: which type it keeps for
    -- the character the list is for.
    local best = FilterBox(LABEL)
    local function Kept()
        best:Tooltip()
        local lines = GameTooltip._lines
        local title, tip, last = lines[1].text, lines[2].text, lines[#lines].text
        GameTooltip:Hide()
        eq(title, LABEL, "the tooltip is titled with the label"); eq(tip, ns.L.ARMOR_BEST_TIP, "and says what the box leaves out")
        return last
    end
    local function Named(card, armor)
        return ns.Roster.Colored(card, card.name) .. ": " .. armor
    end

    -- The druid is played, and ticks its box.
    W.Login(Druid())
    W.equipped = { [5] = W.Link(300) }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    eq(FilterMenu(), MENU, "the line is in a druid's menu")
    eq(best:GetChecked(), false, "not ticked until the player ticks it")
    eq(Kept(), Named(ns.Roster.Me(), "Leather"), "its tooltip names leather, the heaviest armor a druid wears")
    best:Click()
    eq(ns.Roster.Me().armorOnly, true, "ticked: written on the druid's card"); eq(best:GetChecked(), true, "and the tick shows")
    W.CloseAuctionHouse()

    -- The warrior at the auction house. A mage of the account is known as well.
    Relog(warrior, warriorGear)
    UpgradeScoutDB.chars["Magey-Testrealm"] = { key = "Magey-Testrealm", name = "Magey", realm = "Testrealm",
        faction = "Alliance", class = "MAGE", level = 30, gear = {} }
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local me, druid = ns.Roster.Me(), UpgradeScoutDB.chars["Alty-Testrealm"]
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    -- The row of an upgrade, wherever in the list it is: the list may be longer than what is
    -- in view, so it is looked for at the top and then at the bottom.
    local function Row(name)
        for _, at in ipairs({ 0, 1 }) do
            box:SetScrollPercentage(at)
            for _, w in ipairs(box:GetFrames()) do
                if w._shown and w._kind == "Button" and w.entry and w.entry.offer.name == name then return w end
            end
        end
    end
    local function Settle()
        W.RunUntil(function() return S.state == "idle" end, 300)
        W.Run(0.5)
    end
    local function Status() return frame.Status:GetText() or "" end

    -- The same line, and the box is the warrior's own: the druid's tick is the druid's.
    eq(FilterMenu(), MENU, "a warrior's menu has the same line")
    eq(best:GetChecked(), false, "not ticked: the tick the druid set is the druid's")
    eq(Kept(), Named(me, "Mail"), "its tooltip names mail, the heaviest armor of a warrior of level 10")

    -- Everything, with the tab's own two filters off.
    SetView(false, false)
    ScanToEnd()
    W.Run(0.5)
    eq(frame.FilterNames:GetText(), "", "no filter is on: nothing beside the field")
    check(Row("Hide Cap") ~= nil and Row("Silk Hood") ~= nil and Row("Great Chest") ~= nil, "leather and cloth are in the list")
    check(Status():find("11 upgrades in 6 slots.", 1, true) ~= nil, "eleven upgrades: " .. Status())

    -- Ticked: the list keeps mail, and what is no matter of armor. Nothing is looked up.
    local searches = W.AH.calls.search
    best:Click()
    Settle()
    eq(me.armorOnly, true, "written on the warrior's card"); eq(UpgradeScoutDB.chars[me.key].armorOnly, true, "which is saved with the account")
    eq(Row("Hide Cap"), nil, "the leather cap is out"); eq(Row("Silk Hood"), nil, "the cloth hood"); eq(Row("Great Chest"), nil, "and the robe")
    check(Row("Helm") ~= nil and Row("Good Chest") ~= nil, "mail stays")
    check(Row("Wool Cloak") ~= nil, "a cloak stays: it is cloth for everyone")
    check(Row("New Ring") ~= nil and Row("Big Axe") ~= nil and Row("Shield") ~= nil, "and a ring, a weapon, a shield")
    eq(Row("Helm").Pick.Text:GetText(), "Best of both", "the picks are chosen among what is left")
    eq(W.AH.calls.search, searches, "no item search: every price was known")
    eq(frame.FilterNames:GetText(), SHORT, "the filter is named beside the field")
    check(Status():find("8 upgrades in 6 slots.", 1, true) ~= nil, "the status line counts what is listed: " .. Status())
    frame.FilterField._tooltip(GameTooltip)
    eq(GameTooltip._lines[2].text, LABEL, "and the field's tooltip names it in full")
    GameTooltip:Hide()

    -- The best set for a budget is made of the same.
    local bar = frame.PlanBar
    bar.Check:SetChecked(true)
    bar.Check:Click()
    Settle()
    check(Row("Good Chest") ~= nil and Row("Helm") ~= nil, "the set for ten gold: the best mail")
    eq(Row("Great Chest"), nil, "not the robe, which the money would buy"); eq(Row("Hide Cap"), nil, "nor the leather cap")
    eq(best:IsEnabled(), true, "the box keeps its say in a set"); eq(frame.FilterNames:GetText(), SHORT, "and its name beside the field")
    bar.Check:SetChecked(false)
    bar.Check:Click()
    Settle()

    -- The arrows in the bags are the same character's: lighter armor gets none.
    local function Arrow(slot)
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local cap, helm, cloak = W.PutInBags(W.Link(240)), W.PutInBags(W.Link(211)), W.PutInBags(W.Link(242))
    W.OpenBags()
    eq(Arrow(helm), true, "a mail helm for the empty head has its arrow"); eq(Arrow(cloak), true, "and a cloak")
    eq(Arrow(cap), false, "the leather cap has none")
    best:Click()
    W.Run(1.5)
    eq(Arrow(cap), true, "unticked: the cap has its arrow")
    check(Row("Hide Cap") ~= nil, "and its row")
    best:Click()
    W.Run(1.5)
    eq(Arrow(cap), false, "ticked again: gone"); eq(Row("Hide Cap"), nil, "from the list too")

    -- The lists for the druid: the same line, and the box is the druid's, ticked as the druid
    -- left it.
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ProfileDropdown:Pick(3)
    W.Run(0.5)
    eq(ns.Roster.Target(), druid, "the lists are for the druid")
    eq(FilterMenu(), MENU, "the menu is what it was")
    eq(best:GetChecked(), true, "ticked, as the druid left it")
    eq(frame.FilterNames:GetText(), SHORT, "and named beside the field")
    eq(Kept(), Named(druid, "Leather"), "its tooltip names the druid's armor")
    frame.ScanButton:Click()
    Settle()
    check(Row("Druid Jerkin") ~= nil, "the leather jerkin is listed")
    eq(Row("Druid Robe"), nil, "the cloth robe is not"); eq(Offer("Druid Robe"), nil, "and its price was not looked up")
    eq(Arrow(cap), false, "the arrows stay the warrior's")
    -- Unticked by whoever shops for the druid: on the druid's card, and on no other.
    searches = W.AH.calls.search
    best:Click()
    Settle()
    eq(druid.armorOnly, nil, "unticked on the druid's card"); eq(me.armorOnly, true, "the warrior's own tick is where it was")
    eq(W.AH.calls.search, searches + 1, "one item search, for the robe")
    check(Row("Druid Robe") ~= nil, "which is listed now")
    -- Both of the druid's filters on, and between them they leave every upgrade out: the
    -- robe for its cloth, the jerkin (+67%) for its gain.
    best:Click()
    ns.Wants.SetGain(druid, true, 90)
    ns.UI.Refresh()
    eq(Row("Druid Jerkin"), nil, "nothing is listed")
    check(Status():find("No upgrade passes your filters. They leave out 2.", 1, true) ~= nil, "and the status line says why: " .. Status())
    eq(frame.FilterNames:GetText(), SHORT .. " \194\183 From +90%", "beside the names of the two")
    ns.Wants.SetGain(druid, false)
    ns.UI.Refresh()
    check(Row("Druid Jerkin") ~= nil, "the jerkin is back without the second")
    eq(me.minGainOn, nil, "the warrior's own second filter was never on")

    -- A mage wears cloth alone: there is nothing lighter to leave out, and no such line.
    frame.ProfileDropdown:Pick(5)
    W.Run(0.5)
    eq(ns.Roster.Target(), UpgradeScoutDB.chars["Magey-Testrealm"], "the lists are for the mage")
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top 5 per slot | Upgrade at least | / | Value by net cost", "a mage's menu has no line about armor")

    -- Back to the warrior: its box is as it was.
    frame.ProfileDropdown:Pick(1)
    W.Run(0.5)
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own again")
    eq(best:GetChecked(), true, "and its box is ticked, as it was")
    eq(frame.FilterNames:GetText(), SHORT, "named beside the field")
    -- At level 40 a warrior wears plate, and the same tick keeps plate.
    W.player.level = 40
    W.Fire("PLAYER_LEVEL_UP", 40)
    W.Run(2)
    eq(FilterMenu(), MENU, "level 40: the same line")
    eq(best:GetChecked(), true, "still ticked")
    eq(ns.Wants.Of(me).armor, 4, "and it asks for plate now"); eq(Kept(), Named(me, "Plate"), "as its tooltip says")

    -- What the warrior set while it shopped for the druid is the druid's. Played itself, the
    -- druid finds its two boxes so.
    ns.Wants.SetGain(druid, true, 90)
    W.CloseAuctionHouse()
    local grown = W.player
    Relog(Druid(), { [5] = W.Link(300) })
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local gain = FilterBox("Upgrade at least")
    local own = ns.Roster.Me()
    eq(best:GetChecked(), true, "the druid is played: its box is ticked, as the warrior left it for the druid")
    eq(gain:GetChecked(), true, "and so is the other"); eq(ns.Wants.Gain(own), 90, "with the number the warrior typed for it")
    -- And what the druid sets for itself is what the warrior finds the next time it shops
    -- for the druid, beside its own, which is as it was.
    best:Click()
    gain:Click()
    eq(own.armorOnly, nil, "unticked by the druid"); eq(own.minGainOn, nil, "both of them")
    W.CloseAuctionHouse()
    Relog(grown, warriorGear)
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    eq(best:GetChecked(), true, "the warrior again: its own box is ticked, as it left it"); eq(gain:GetChecked(), false, "its other one never was")
    UpgradeScoutFrame.ProfileDropdown:Pick(3)
    W.Run(0.5)
    eq(ns.Roster.Target().name, "Alty", "the lists are for the druid")
    eq(best:GetChecked(), false, "the druid's box is as the druid left it: unticked"); eq(gain:GetChecked(), false, "and so is its other one")
    eq(ns.Wants.Gain(ns.Roster.Target()), 90, "its number is still the druid's")
end

-- "Upgrade at least N %" in the Filters menu: a tick box with a field for the number.
function scenarios.gain_ui()
    WantsWorld()
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local filters, me = frame.FilterField, ns.Roster.Me()
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    -- The row of an upgrade, wherever in the list it is: the list may be longer than what is
    -- in view, so it is looked for at the top and then at the bottom.
    local function Row(name)
        for _, at in ipairs({ 0, 1 }) do
            box:SetScrollPercentage(at)
            for _, w in ipairs(box:GetFrames()) do
                if w._shown and w._kind == "Button" and w.entry and w.entry.offer.name == name then return w end
            end
        end
    end
    local function Settle()
        W.RunUntil(function() return S.state == "idle" end, 300)
        W.Run(0.5)
    end
    -- The line of the open menu, and its field.
    local function Line()
        local line = filters.lines[filters:Find("Upgrade at least")]
        return line, line.Number
    end
    SetView(false, false)
    ScanToEnd()
    W.Run(0.5)
    eq(Row("Fair Chest").Upgrade:GetText(), "+20%", "the fair chest adds a fifth"); eq(Row("Big Axe").Upgrade:GetText(), "+30%", "the axe three tenths")
    eq(Row("Fine Chest").Upgrade:GetText(), "+50%", "the fine chest a half"); eq(Row("Helm").Upgrade:GetText(), "New", "the helm goes on an empty head")

    -- The line: a tick box, its words, a field for the number and a percent sign.
    filters:Open()
    local line, number = Line()
    check(number ~= nil and number._kind == "EditBox", "the line has a field for the number")
    eq(number:GetText(), "10", "with ten in it before a number is typed"); eq(line.Tick:IsShown(), false, "and no tick")
    eq(number:GetWidth(), 46, "wide enough for four digits")
    -- The game hands an attached frame over in a layer under the menu, out of view and deaf to
    -- the mouse: the field is put where it can be seen and typed into.
    eq(number:IsVisible(), true, "the field is in view")
    eq(number:GetFrameStrata(), "FULLSCREEN_DIALOG", "in the menu's layer, not under its plate")
    check(number:GetFrameLevel() > line:GetFrameLevel(), "above its line")
    eq(number._mouse, true, "and in reach of the mouse")
    eq(Pictures(number, "Inset"), 9, "a recess of ours, like the tick box's")
    check(line._size ~= nil, "the line says how big it is with its field")
    eq(line._size[1], 16 + 7 + line.fontString:GetStringWidth() + 6 + 46 + 4 + 6, "the box, the words, the field and the sign in a row")
    eq(line._size[2], 20, "as tall as the other lines")

    -- A number typed is asked for at once, and ticks the box. The menu is not drawn again:
    -- that would take the field from under the keys.
    local sounds = #W.sounds
    W.Type(number, "50")
    eq(me.minGain, 50, "the number is written on the character's card"); eq(me.minGainOn, true, "and asked for")
    eq(line.Tick:IsShown(), true, "the typing ticked the box"); eq(#W.sounds, sounds, "without a click")
    eq(filters._open, true, "the menu stays up"); check(Line() == line, "and its line is the one that was typed into")
    W.Run(0.5)
    eq(Row("Fair Chest"), nil, "the fair chest's +20% is out"); eq(Row("Big Axe"), nil, "and the axe's +30%")
    check(Row("Fine Chest") ~= nil, "+50% is at least 50"); check(Row("Good Chest") ~= nil and Row("Great Chest") ~= nil, "as is more")
    check(Row("Helm") ~= nil and Row("New Ring") ~= nil and Row("Shield") ~= nil, "what goes into an empty slot stays")
    eq(frame.FilterNames:GetText(), "From +50%", "the filter is named beside the field, with its number")
    filters:Close()
    filters._tooltip(GameTooltip)
    eq(GameTooltip._lines[2].text, "Upgrade at least 50%", "and in the field's tooltip in full")
    GameTooltip:Hide()

    -- The menu opened again has the number and the tick. Typed digit by digit.
    filters:Open()
    line, number = Line()
    eq(number:GetText(), "50", "the number is in the field"); eq(line.Tick:IsShown(), true, "and the box is ticked")
    W.Type(number, "5")
    W.Run(0.5)
    check(Row("Fair Chest") ~= nil and Row("Big Axe") ~= nil, "at least 5: everything again")
    W.Type(number, "51")
    W.Run(0.5)
    eq(Row("Fine Chest"), nil, "at least 51: +50% falls short")
    -- An empty field asks for nothing while the player types. Left empty, it unticks the box
    -- and shows the last number again.
    W.Type(number, "")
    eq(me.minGain, 51, "an empty field changes nothing yet"); eq(me.minGainOn, true, "the box stays ticked")
    W.PressEnter(number)
    eq(me.minGainOn, nil, "left empty: unticked"); eq(line.Tick:IsShown(), false, "the tick goes")
    eq(number:GetText(), "51", "and the last number is back in the field"); eq(me.minGain, 51, "kept for the next time")
    W.Run(0.5)
    check(Row("Fine Chest") ~= nil and Row("Fair Chest") ~= nil, "everything is listed again")
    eq(frame.FilterNames:GetText(), "", "and nothing stands beside the field")
    W.Type(number, "0")
    eq(me.minGainOn, nil, "nought is no number to ask for")
    W.PressEnter(number)
    eq(number:GetText(), "51", "and gives way to the last one")
    filters:Close()

    -- The tick box itself: a click asks for the number that is in the field.
    local gain = FilterBox("Upgrade at least")
    gain:Tooltip()
    eq(GameTooltip._lines[1].text, "Upgrade at least", "its tooltip is titled with its words"); eq(GameTooltip._lines[2].text, ns.L.GAIN_MIN_TIP, "and says what it leaves out")
    GameTooltip:Hide()
    gain:Click()
    eq(me.minGainOn, true, "ticked"); eq(me.minGain, 51, "with the number that was there")
    W.Run(0.5)
    eq(Row("Fine Chest"), nil, "the list is cut at once")
    gain:Click()
    eq(me.minGainOn, nil, "unticked"); eq(me.minGain, 51, "the number stays")

    -- A scan with the filter on looks up no price for what adds too little; a smaller number
    -- sends for the prices it lets in.
    filters:Open()
    W.Type(select(2, Line()), "50")
    filters:Close()
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.5)
    eq(Offer("Big Axe"), nil, "no price for the axe"); eq(Offer("Fair Chest"), nil, "or for the fair chest")
    check(frame.Status:GetText():find("9 upgrades in 5 slots.", 1, true) ~= nil, "the status line counts what is listed: " .. frame.Status:GetText())
    local searches = W.AH.calls.search
    filters:Open()
    W.Type(select(2, Line()), "25")
    filters:Close()
    eq(S.mode, "more", "a smaller number: the missing price is asked for")
    Settle()
    eq(W.AH.calls.search, searches + 1, "one item search, for the axe")
    check(Row("Big Axe") ~= nil, "which is listed"); eq(Row("Fair Chest"), nil, "the fair chest still adds too little")

    -- The best set for a budget holds nothing that adds less. Eight silver buy the leather cap,
    -- the cloak and the fair chest; with the filter on, not the chest.
    gain:Click()
    Settle()
    local bar = frame.PlanBar
    bar.Check:SetChecked(true)
    bar.Check:Click()
    W.Type(bar.Gold, "0")
    W.Type(bar.Silver, "8")
    Settle()
    -- The items of the set, top to bottom.
    local function Set()
        local out = {}
        box:SetScrollPercentage(0)
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry then out[#out + 1] = w.entry.offer.name end
        end
        return table.concat(out, ", ")
    end
    eq(Set(), "Hide Cap, Wool Cloak, Fair Chest", "eight silver: the cap, the cloak and the fair chest")
    gain:Click()
    Settle()
    eq(Set(), "Hide Cap, Wool Cloak", "at least 25: no chest that adds a fifth")
    eq(gain:IsEnabled(), true, "the box keeps its say in a set"); eq(frame.FilterNames:GetText(), "From +25%", "and its name beside the field")
    bar.Check:SetChecked(false)
    bar.Check:Click()
    Settle()

    -- Three names have room beside the field. Four have not: their number stands there, and
    -- the field's tooltip has the names.
    FilterBox("Only what I can afford"):Click()
    FilterBox("Top 5 per slot"):Click()
    Settle()
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5 per slot \194\183 From +25%", "three filters by name")
    FilterBox("Best armor type for the class"):Click()
    Settle()
    eq(frame.FilterNames:GetText(), "Filters on: 4", "four: how many are on")
    filters._tooltip(GameTooltip)
    local named = {}
    for i = 2, #GameTooltip._lines do named[#named + 1] = GameTooltip._lines[i].text end
    eq(table.concat(named, " | "), "Only what I can afford | Top 5 per slot | Best armor type for the class | Upgrade at least 25%", "the tooltip names them in full")
    GameTooltip:Hide()

    -- The number is the character's own, kept with the account.
    eq(UpgradeScoutDB.chars[me.key].minGain, 25, "the number is saved on the character's card"); eq(UpgradeScoutDB.chars[me.key].minGainOn, true, "with its tick")
end

---------------------------------------------------------------------------
-- "Buyout up to": the most to pay for one item, a price filter with a sum of its own that is
-- kept with the character the list is for (Wants.lua)
---------------------------------------------------------------------------
-- The world of the wants, and one chest more: weaker than the good chest (+60% against +80%)
-- and dearer per point, so "top five" has no use for it while the good chest is in the list.
--   chest   Great Chest 9g, Good Chest 40s, Plain Chest 35s, Fine Chest 15s, Fair Chest 3s
--   head    Helm 25s, Hide Cap 3s, Silk Hood 2s
--   others  Big Axe 30s, New Ring 8s, Shield 7s, Wool Cloak 1s 50c
local function PriceWorld()
    WantsWorld()
    W.AddItem({ id = 245, name = "Plain Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 16, level = 9 })
    W.AddAuction(245, 3500)
end

-- The sum itself, and what it does to the list, to its picks and to a scan.
function scenarios.price_max()
    PriceWorld()
    LoadAddon()
    local Wants, S = ns.Wants, ns.Scanner
    local SILVER, GOLD = 100, 10000

    -- The sum on a card.
    local card = { class = "WARRIOR", level = 10 }
    eq(Wants.Price(card), nil, "nothing typed and nothing ticked: no sum is asked for")
    eq(Wants.PriceTyped(card), GOLD, "one gold stands in the fields before a sum is typed")
    card.maxPrice = 5 * GOLD
    eq(Wants.Price(card), nil, "a sum alone asks for nothing")
    card.maxPriceOn = true
    eq(Wants.Price(card), 5 * GOLD, "ticked: no more than that")
    local told = 0
    ns.Listen("WANTS_CHANGED", function() told = told + 1 end)
    Wants.SetPrice(card, true, 2 * GOLD + 50 * SILVER + 99)
    eq(card.maxPrice, 2 * GOLD + 50 * SILVER, "a sum is in whole silver")
    Wants.SetPrice(card, true, 12)
    eq(card.maxPrice, SILVER, "and no less than one")
    Wants.SetPrice(card, true, 1e12)
    eq(card.maxPrice, 99999 * GOLD + 99 * SILVER, "nor more than its two fields hold")
    Wants.SetPrice(card, false)
    eq(card.maxPriceOn, nil, "unticked"); eq(card.maxPrice, 99999 * GOLD + 99 * SILVER, "the sum stays")
    eq(Wants.Price(card), nil, "and is not asked for")
    eq(told, 0, "the arrows in the bags are not told: a price is no matter of theirs")
    card.maxPriceOn = true
    eq(Wants.Of(card), nil, "nor is the sum one of the wants: a set for a budget goes without it")
    card.maxPrice = "much"
    eq(Wants.Price(card), GOLD, "a card with no number for a sum has the first one")
    eq(Wants.Price(nil), nil, "no character, no sum")

    -- A scan.
    W.OpenAuctionHouse()
    local me = ns.Roster.Me()
    local function Scan()
        W.RunUntil(function() return W.AH.ready end, 5)
        local before = W.AH.calls.search
        ScanToEnd()
        return W.AH.calls.search - before
    end
    local function More()
        local before = W.AH.calls.search
        if not S.Demand() then return 0 end
        W.RunUntil(function() return S.state == "idle" end, 600)
        return W.AH.calls.search - before
    end
    -- The list as the tab makes it.
    local function Rows()
        return ns.Results.Build(S.offers, S.ctx, {
            money = GetMoney(), affordableOnly = ns.db.affordableOnly, cap = Wants.Price(me),
            limit = ns.db.topOnly and ns.Results.TOP_COUNT or nil, unchecked = S.Unchecked(),
        })
    end
    -- The upgrades it shows, by name, and how many it leaves out for their price.
    local function Shown()
        local rows, summary = Rows()
        local out, seen = {}, {}
        for _, row in ipairs(rows) do
            local name = row.kind == "item" and row.entry.offer.name
            if name and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
        table.sort(out)
        return table.concat(out, ", "), summary.hidden
    end
    -- The rows under a heading, top to bottom, each with its pick.
    local function Under(group)
        local out, inside = {}, false
        for _, row in ipairs((Rows())) do
            if row.kind == "header" then
                inside = row.group == group
            elseif inside then
                out[#out + 1] = row.entry.offer.name .. (row.entry.pick and " (" .. row.entry.pick .. ")" or "")
            end
        end
        return table.concat(out, ", ")
    end
    local EVERYTHING = "Big Axe, Fair Chest, Fine Chest, Good Chest, Great Chest, Helm, Hide Cap, New Ring, Plain Chest, Shield, Silk Hood, Wool Cloak"
    local CHEAP = "Fair Chest, Fine Chest, Hide Cap, New Ring, Shield, Silk Hood, Wool Cloak"

    -- Reference: no sum, and the tab's own filters off, so every price is looked up.
    SetView(false, false)
    local all = Scan()
    local list, hidden = Shown()
    eq(OfferCount(), 12, "twelve upgrades for sale"); eq(list, EVERYTHING, "all of them listed"); eq(hidden, 0, "none left out")
    eq(S.Ceiling(), nil, "no price filter is on: a row may cost anything")
    eq(Under("CHEST"), "Great Chest (UPGRADE), Good Chest, Plain Chest, Fine Chest (VALUE), Fair Chest", "the chests, the dearest the best")

    -- No more than 20 silver, with every price known: what costs more is out, and the picks
    -- are chosen among what is left. The best upgrade of a slot is the best one for that sum.
    Wants.SetPrice(me, true, 20 * SILVER)
    list, hidden = Shown()
    eq(list, CHEAP, "seven upgrades for 20 silver or less"); eq(hidden, 5, "five left out for their price")
    eq(Under("CHEST"), "Fine Chest (UPGRADE), Fair Chest (VALUE)", "the best chest for that sum is the best upgrade")
    eq(Under("HEAD"), "Hide Cap (UPGRADE), Silk Hood (VALUE)", "and the helm, at 25 silver, is not among the head's")
    local ceiling, typed = S.Ceiling()
    eq(ceiling, 20 * SILVER, "a row may cost the sum typed"); eq(typed, true, "which is said to be that sum, and not the purse")
    -- What the buyer can pay for is a matter of the purse, with the sum or without it.
    W.player.money = 10 * SILVER
    local fine
    for _, row in ipairs((Rows())) do
        if row.kind == "item" and row.entry.offer.name == "Fine Chest" then fine = row.entry end
    end
    check(fine ~= nil, "ten silver in the purse: the fine chest, at 15, is still under the sum")
    eq(fine.affordable, false, "and its row says that it cannot be paid for")
    -- Both price filters: the less of the two is what a row may cost.
    ns.db.affordableOnly = true
    ceiling, typed = S.Ceiling()
    eq(ceiling, 10 * SILVER, "the purse is the less"); eq(typed, false, "and is named as such")
    list, hidden = Shown()
    eq(list, "Fair Chest, Hide Cap, New Ring, Shield, Silk Hood, Wool Cloak", "nothing over ten silver"); eq(hidden, 6, "the fine chest is out as well")
    W.player.money = 10 * GOLD
    ceiling, typed = S.Ceiling()
    eq(ceiling, 20 * SILVER, "ten gold in the purse: the sum is the less"); eq(typed, true, "and is named")
    ns.db.affordableOnly = false

    -- A scan with the sum on looks up no price for what costs more. That is known of a row
    -- whose lowest price is over the sum. The good chest's row starts with an auction that
    -- only takes bids, under the sum, so its buyout is looked up: it is out of the list all
    -- the same.
    eq(Scan(), all - 4, "four item searches fewer")
    eq(Offer("Great Chest"), nil, "no price for the robe"); eq(Offer("Plain Chest"), nil, "the plain chest")
    eq(Offer("Helm"), nil, "the helm"); eq(Offer("Big Axe"), nil, "or the axe")
    check(Unsure("Great Chest") ~= nil and Unsure("Plain Chest") ~= nil and Unsure("Helm") ~= nil and Unsure("Big Axe") ~= nil,
        "which are counted at the lowest price of their rows")
    eq(Offer("Good Chest").buyout, 40 * SILVER, "the good chest's buyout is known, and over the sum")
    list, hidden = Shown()
    eq(list, CHEAP, "the same list"); eq(hidden, 5, "and the same count")
    eq(S.Demand(), false, "nothing more is needed for the list as it is")
    -- A bigger sum asks for the prices it lets in, and for no others.
    Wants.SetPrice(me, true, 30 * SILVER)
    eq(More(), 2, "30 silver: two searches, for the helm and the axe")
    check(Offer("Helm") ~= nil and Offer("Big Axe") ~= nil, "which have their prices now"); eq(Offer("Plain Chest"), nil, "the plain chest still costs more")
    Wants.SetPrice(me, true, 10 * SILVER)
    eq(More(), 0, "a smaller sum asks for nothing")
    eq(Shown(), "Fair Chest, Hide Cap, New Ring, Shield, Silk Hood, Wool Cloak", "and leaves out more")
    Wants.SetPrice(me, false)
    eq(More(), 2, "unticked: the two prices still missing are looked up, the robe's and the plain chest's")
    eq(OfferCount(), 12, "and every upgrade has its price"); eq(Shown(), EVERYTHING, "and is listed")

    -- "Top 5 per slot" is judged among what the sum lets through. The good chest outdoes the
    -- plain one; with no more than 36 silver to pay the good chest is out, and the plain one
    -- is the best chest there is.
    SetView(false, true)
    Scan()
    eq(Offer("Plain Chest"), nil, "top five: no price for the plain chest"); check(Offer("Good Chest") ~= nil, "the good chest outdoes it")
    Wants.SetPrice(me, true, 36 * SILVER)
    check(More() >= 1, "no more than 36 silver: the plain chest's price is asked for")
    check(Offer("Plain Chest") ~= nil, "and found")
    eq(Under("CHEST"), "Plain Chest (UPGRADE), Fine Chest, Fair Chest (VALUE)", "it is the best upgrade for that sum")
    Scan()
    check(Offer("Plain Chest") ~= nil, "a scan with both on looks it up as well"); eq(Offer("Great Chest"), nil, "and not the robe")
    SetView(false, false)

    -- The best set for a budget goes by its budget, and the sum has no say in it: the robe,
    -- at nine gold, is looked up for a set of ten.
    ns.db.plan = true
    check(More() >= 1, "a set: prices over the sum are asked for")
    check(Offer("Great Chest") ~= nil, "the robe's among them")
    ns.db.plan = nil

    -- The sum is kept with the character, in the account's file.
    eq(UpgradeScoutDB.chars[me.key].maxPrice, 36 * SILVER, "the sum is saved on the character's card"); eq(UpgradeScoutDB.chars[me.key].maxPriceOn, true, "with its tick")
end

-- "Buyout up to" in the Filters menu: a tick box with a field for the gold and one for the
-- silver, a coin after each.
function scenarios.price_max_ui()
    PriceWorld()
    LoadAddon()
    -- A druid of the account, to shop for.
    UpgradeScoutDB.chars["Alty-Testrealm"] = { key = "Alty-Testrealm", name = "Alty", realm = "Testrealm",
        faction = "Alliance", class = "DRUID", level = 20, gear = {} }
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local filters, me = frame.FilterField, ns.Roster.Me()
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    local function Row(name)
        for _, at in ipairs({ 0, 1 }) do
            box:SetScrollPercentage(at)
            for _, w in ipairs(box:GetFrames()) do
                if w._shown and w._kind == "Button" and w.entry and w.entry.offer.name == name then return w end
            end
        end
    end
    local function Settle()
        W.RunUntil(function() return S.state == "idle" end, 300)
        W.Run(0.5)
    end
    local function Status() return frame.Status:GetText() or "" end
    -- The line of the open menu, and its two fields.
    local function Line()
        local line = filters.lines[filters:Find("Buyout up to")]
        return line, line.Gold, line.Silver
    end
    SetView(false, false)
    ScanToEnd()
    W.Run(0.5)
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top 5 per slot | Best armor type for the class | Upgrade at least | / | Value by net cost",
        "the line stands under the other price filter")
    eq(Row("Great Chest").Pick.Text:GetText(), "Best upgrade", "the robe, at nine gold, is the best chest there is")
    check(Status():find("12 upgrades in 6 slots.", 1, true) ~= nil, "twelve upgrades: " .. Status())

    -- The line: a tick box, its words, a field for the gold and one for the silver, a coin
    -- after each.
    filters:Open()
    local line, gold, silver = Line()
    check(gold ~= nil and gold._kind == "EditBox", "the line has a field for the gold"); check(silver ~= nil and silver._kind == "EditBox", "and one for the silver")
    eq(gold:GetText(), "1", "one gold in them before a sum is typed"); eq(silver:GetText(), "00", "and no silver"); eq(line.Tick:IsShown(), false, "and no tick")
    eq(gold:GetWidth(), 46, "wide enough for five digits"); eq(silver:GetWidth(), 30, "and for two")
    for _, field in ipairs({ gold, silver }) do
        eq(field:IsVisible(), true, "a field is in view")
        eq(field:GetFrameStrata(), "FULLSCREEN_DIALOG", "in the menu's layer, not under its plate")
        check(field:GetFrameLevel() > line:GetFrameLevel(), "above its line")
        eq(field._mouse, true, "and in reach of the mouse")
        eq(Pictures(field, "Inset"), 9, "in a recess of ours")
    end
    eq(gold.Coin:GetTexture(), "Interface\\MoneyFrame\\UI-GoldIcon", "the game's gold coin after the one")
    eq(silver.Coin:GetTexture(), "Interface\\MoneyFrame\\UI-SilverIcon", "its silver coin after the other")
    check(line._size ~= nil, "the line says how big it is with its fields")
    eq(line._size[1], 16 + 7 + line.fontString:GetStringWidth() + 6 + 46 + 3 + 13 + 6 + 30 + 3 + 13, "the box, the words, and two fields with their coins in a row")
    eq(line._size[2], 20, "as tall as the other lines")

    -- A sum typed is asked for at once, and ticks the box. On the way to a sum in silver alone
    -- the gold is emptied: nothing is asked for a sum of nothing.
    local sounds = #W.sounds
    W.Type(gold, "")
    eq(me.maxPriceOn, nil, "no sum yet: nothing is asked"); eq(line.Tick:IsShown(), false, "and nothing ticked")
    W.Type(silver, "20")
    eq(me.maxPrice, 2000, "20 silver is written on the character's card"); eq(me.maxPriceOn, true, "and asked for")
    eq(line.Tick:IsShown(), true, "the typing ticked the box"); eq(#W.sounds, sounds, "without a click")
    eq(filters._open, true, "the menu stays up"); check(Line() == line, "and its line is the one that was typed into")
    W.Run(0.5)
    eq(Row("Great Chest"), nil, "the robe's nine gold are out"); eq(Row("Good Chest"), nil, "the good chest's 40 silver"); eq(Row("Plain Chest"), nil, "the plain one's 35")
    eq(Row("Helm"), nil, "the helm's 25"); eq(Row("Big Axe"), nil, "and the axe's 30")
    check(Row("Fair Chest") ~= nil and Row("Hide Cap") ~= nil and Row("New Ring") ~= nil, "what costs less stays")
    eq(Row("Fine Chest").Pick.Text:GetText(), "Best upgrade", "the best chest for 20 silver is the best upgrade now")
    eq(Row("Fair Chest").Pick.Text:GetText(), "Best value", "and the best value is chosen beside it")
    eq(frame.FilterNames:GetText(), "Up to 20s", "the filter is named beside the field, with its sum")
    check(Status():find("7 upgrades in 5 slots. 5 more cost more than 20s.", 1, true) ~= nil, "the status line says what the sum leaves out: " .. Status())
    filters:Close()
    filters._tooltip(GameTooltip)
    eq(GameTooltip._lines[2].text, "Buyout up to 20s", "and the field's tooltip names it in full")
    GameTooltip:Hide()

    -- The menu opened again has the sum and the tick. A bigger sum lets more in.
    filters:Open()
    line, gold, silver = Line()
    eq(gold:GetText(), "0", "no gold in the sum"); eq(silver:GetText(), "20", "and 20 silver"); eq(line.Tick:IsShown(), true, "and the box is ticked")
    W.Type(gold, "1")
    eq(me.maxPrice, 12000, "one gold and 20 silver")
    W.Run(0.5)
    check(Row("Good Chest") ~= nil and Row("Helm") ~= nil and Row("Big Axe") ~= nil, "everything but the robe again")
    eq(Row("Great Chest"), nil, "which costs nine")
    eq(Row("Good Chest").Pick.Text:GetText(), "Best upgrade", "the best chest for that sum")
    check(Status():find("11 upgrades in 6 slots. 1 more cost more than 1g 20s.", 1, true) ~= nil, "and the one left out: " .. Status())
    -- A field emptied leaves what the other holds: the silver gone, the sum is one gold.
    W.Type(silver, "")
    eq(me.maxPrice, 10000, "no silver: one gold")
    -- No sum asks for nothing while the player types. Enter on it unticks the box and shows
    -- the last sum again.
    W.Type(gold, "")
    eq(me.maxPrice, 10000, "two empty fields change nothing yet"); eq(me.maxPriceOn, true, "the box stays ticked")
    W.PressEnter(gold)
    eq(me.maxPriceOn, nil, "Enter on no sum: unticked"); eq(line.Tick:IsShown(), false, "the tick goes")
    eq(gold:GetText(), "1", "and the last sum is back in the fields"); eq(silver:GetText(), "00", "both of them"); eq(me.maxPrice, 10000, "kept for the next time")
    W.Run(0.5)
    check(Row("Great Chest") ~= nil, "everything is listed again")
    eq(frame.FilterNames:GetText(), "", "and nothing stands beside the field")
    W.Type(gold, "0")
    eq(me.maxPriceOn, nil, "nought is no sum to ask for")
    W.PressEnter(gold)
    eq(gold:GetText(), "1", "and gives way to the last one"); eq(silver:GetText(), "00", "in both fields")
    filters:Close()

    -- The tick box itself: a click asks for the sum that is in the fields.
    local price = FilterBox("Buyout up to")
    price:Tooltip()
    eq(GameTooltip._lines[1].text, "Buyout up to", "its tooltip is titled with its words"); eq(GameTooltip._lines[2].text, ns.L.PRICE_MAX_TIP, "and says what it leaves out")
    GameTooltip:Hide()
    price:Click()
    eq(me.maxPriceOn, true, "ticked"); eq(me.maxPrice, 10000, "with the sum that was there")
    W.Run(0.5)
    eq(Row("Great Chest"), nil, "the list is cut at once")
    price:Click()
    eq(me.maxPriceOn, nil, "unticked"); eq(me.maxPrice, 10000, "the sum stays")

    -- A scan with the sum on looks up no price for what costs more; a bigger sum sends for
    -- the prices it lets in.
    filters:Open()
    gold, silver = select(2, Line())
    W.Type(silver, "20")
    W.Type(gold, "0")
    filters:Close()
    eq(me.maxPrice, 2000, "20 silver again"); eq(me.maxPriceOn, true, "and on")
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.5)
    eq(Offer("Helm"), nil, "no price for the helm"); eq(Offer("Plain Chest"), nil, "or for the plain chest")
    check(Status():find("7 upgrades in 5 slots. 5 more cost more than 20s.", 1, true) ~= nil, "the status line counts them all the same: " .. Status())
    local searches = W.AH.calls.search
    filters:Open()
    W.Type(select(3, Line()), "30")
    filters:Close()
    eq(S.mode, "more", "a bigger sum: the missing prices are asked for")
    Settle()
    eq(W.AH.calls.search, searches + 2, "two item searches, for the helm and the axe")
    check(Row("Helm") ~= nil and Row("Big Axe") ~= nil, "which are listed"); eq(Row("Plain Chest"), nil, "the plain chest still costs more")

    -- Beside the other price filter the less of the two decides, and the status line names
    -- the one that did.
    FilterBox("Only what I can afford"):Click()
    Settle()
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Up to 30s", "both are named beside the field")
    check(Status():find("more cost more than 30s.", 1, true) ~= nil, "ten gold in the purse: the sum is the less: " .. Status())
    W.player.money = 1000
    ns.UI.Refresh()
    eq(Row("Helm"), nil, "ten silver in the purse: the helm is out again")
    check(Status():find("more cost more than you have.", 1, true) ~= nil, "and it is the purse that leaves it out: " .. Status())
    W.player.money = 100000
    FilterBox("Only what I can afford"):Click()
    Settle()

    -- The best set for a budget goes by its budget: the sum has no say in it, and its line
    -- of the menu is grey, as the other price filter's is.
    local bar = frame.PlanBar
    bar.Check:SetChecked(true)
    bar.Check:Click()
    Settle()
    check(Row("Great Chest") ~= nil, "the set for ten gold has the robe, for nine")
    eq(price:IsEnabled(), false, "the line is grey"); eq(price:GetChecked(), true, "with its tick")
    price:Click()
    eq(me.maxPriceOn, true, "a grey line takes no click")
    eq(frame.FilterNames:GetText(), "", "and is not named beside the field while the list is a set")
    filters:Open()
    gold, silver = select(2, Line())
    eq(gold._mouse, false, "its fields are only read: out of reach of the mouse"); eq(silver._mouse, false, "both of them")
    eq(silver:GetText(), "30", "with the sum in them")
    filters:Close()
    bar.Check:SetChecked(false)
    bar.Check:Click()
    Settle()
    eq(Row("Great Chest"), nil, "the list again: the sum has its say"); eq(frame.FilterNames:GetText(), "Up to 30s", "and its name")

    -- The sum is the character's own, kept with the account. Another character of the
    -- account has its own: shopping for the druid, the fields are the druid's.
    eq(UpgradeScoutDB.chars[me.key].maxPrice, 3000, "the sum is saved on the character's card"); eq(UpgradeScoutDB.chars[me.key].maxPriceOn, true, "with its tick")
    local druid = UpgradeScoutDB.chars["Alty-Testrealm"]
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ProfileDropdown:Pick(3)
    W.Run(0.5)
    eq(ns.Roster.Target(), druid, "the lists are for the druid")
    eq(price:GetChecked(), false, "its box is not ticked: the warrior's sum is the warrior's")
    eq(frame.FilterNames:GetText(), "", "and nothing is named beside the field")
    filters:Open()
    gold, silver = select(2, Line())
    eq(gold:GetText(), "1", "one gold in its fields, as before any sum is typed"); eq(silver:GetText(), "00", "and no silver")
    W.Type(gold, "5")
    filters:Close()
    eq(druid.maxPrice, 50000, "five gold, typed while shopping for the druid, is the druid's"); eq(druid.maxPriceOn, true, "and asked for it")
    eq(me.maxPrice, 3000, "the warrior's own sum is where it was")
    eq(frame.FilterNames:GetText(), "Up to 5g", "the druid's is named beside the field")
    frame.ProfileDropdown:Pick(1)
    W.Run(0.5)
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own again")
    eq(price:GetChecked(), true, "and its box is ticked, as it was"); eq(frame.FilterNames:GetText(), "Up to 30s", "with its own sum")
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
    -- Beside the Filters field the names stand apart by a bullet: the game's Russian font has
    -- no middle dot, and draws a square for one.
    ns.Filters.SetRoom(1000)
    eq(UpgradeScoutFrame.FilterNames:GetText(), "По карману \226\128\162 Топ-5 в слоте", "the filters that are on, a bullet between them")
    -- The welcome window: words too long for a line of the tooltip's block go on to a second
    -- one, and the box under them stands lower by it. (The stand-in client measures a text by
    -- its bytes, and a Cyrillic letter is two.)
    ns.Welcome.Show()
    local block = UpgradeScoutWelcome.Tips
    eq(block.All.Label:GetText(), "Все спеки", "how, in Russian"); eq(block.Own.Label:GetText(), "Только мой спек", "both buttons")
    eq(block.Tabs.Label:GetText(), "Показывать на вкладках аддона на аукционе", "where: the addon's tabs")
    eq(block.Elsewhere.Label:GetText(), "Показывать в остальной игре: сумки, добыча, чат", "and the rest of the game")
    eq(block.Tabs.Label:GetWidth(), 378, "words too long for the line are given its width")
    eq(block.Tabs._points[1].y - block.Elsewhere._points[1].y, 2 + 24 + 7, "and the next box is lower by their two lines")
end

function scenarios.locale_de()
    CheckLocale("deDE", "German", "Scannen")
end

function scenarios.locale_fr()
    CheckLocale("frFR", "French", "Scanner")
end

function scenarios.locale_zh()
    CheckLocale("zhCN", "Simplified Chinese", "扫描")
    -- Beside the Filters field the middle dot stays: for a bullet, which the Russian client
    -- gets, the game's Chinese font has an empty place.
    ns.Filters.SetRoom(1000)
    check(UpgradeScoutFrame.FilterNames:GetText():find(" \194\183 ", 1, true) ~= nil, "a middle dot between the filters that are on")
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
