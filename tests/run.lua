-- Runs Upgrade Scout against the stand-in client in tests/wow.lua.
--   lua5.1 tests/run.lua            every scenario, each in its own process
--   lua5.1 tests/run.lua <name>     one scenario
-- Run from the project folder (the one that contains UpgradeScout/ and tests/).
local realPrint = print
local scenario = arg[1]
local ADDON_DIR = "UpgradeScout/"

local names = {
    "events", "compare", "picks", "scan_sorted", "scan_order", "scan_unsorted", "scan_async", "scan_late", "scan_no_sample",
    "scan_cold", "scan_unloaded", "scan_late_slow", "scan_stats_late", "scan_warm_tail", "pawn_blind_scan", "roster_names",
    "leveling_no_realm", "supplies_unloaded", "scan_junk",
    "scan_suffix_rows", "scan_varying_rows", "scan_no_answer", "scan_interrupted",
    "scan_lazy", "scan_top_five", "top_ui", "scan_bad_floor", "scan_pages", "scan_halt", "scan_unanswered", "scan_slow_answer", "scan_pieces", "scan_eta",
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
    "levels", "levels_ui", "scan_levels", "scan_no_level",
    "ellesmere", "ellesmere_absent", "ellesmere_late", "ellesmere_leveling", "ellesmere_companion",
    "hands", "weapons", "weapons_scan", "weapons_spare", "weapons_ui", "weapons_rogue", "weapons_hunter", "weapons_untrained", "weapons_warlock", "weapons_paladin",
    "weapons_others", "weapons_leveling",
    "gearquest_scan", "gearquest_absent", "gearquest_tooltips", "gearquest_welcome", "gearquest_supplies", "gearquest_alt",
    "tab_row",
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

-- More of them for a scenario that has a use for other classes, or for profiles by the names
-- the addon's own go by: a function that is given the tests' weights each time the addon is
-- loaded, to add to. See MoreProfiles.
local moreWeights

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
    if moreWeights then moreWeights(ns.Weights) end
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

-- The two filters of the tab that are on from the start, and with `hideWorse` the one under
-- them that is not ("Hide worse deals"). With all three off the list shows every upgrade, so
-- the scan has to look up every price.
local function SetView(affordableOnly, topOnly, hideWorse)
    ns.db.affordableOnly = affordableOnly
    ns.db.topOnly = topOnly
    ns.db.hideWorse = hideWorse or nil
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

-- The lines of a menu, top to bottom: the label of each, a "/" where a rule is, and a ">"
-- after a line that opens a menu of its own. With `marks`, a line of which one is chosen is
-- "(x)" before its label when it is that one and "( )" when not, and a tick box "[x]" or "[ ]".
local function MenuLines(elements, marks)
    local out = {}
    for _, line in ipairs(elements) do
        local text = line.kind == "rule" and "/" or line.text
        if line.kind ~= "rule" and #line.elements > 0 then text = text .. " >" end
        if marks and (line.kind == "radio" or line.kind == "check") then
            local mark = line.isSelected(line.data) and "x" or " "
            text = (line.kind == "radio" and "(" .. mark .. ") " or "[" .. mark .. "] ") .. text
        end
        out[#out + 1] = text
    end
    return table.concat(out, " | ")
end

-- The lines of the Filters menu.
local function FilterMenu()
    local field = UpgradeScoutFrame.FilterField
    field:Open()
    local out = MenuLines(field.elements)
    field:Close()
    return out
end

-- The menu that the line "Weapons" of the Filters menu opens (Filters.lua), for a test to
-- handle as the player does. Each look and each click opens the two menus anew, as FilterBox
-- does, and closes what is still open after it. A click may come with `keep`: a function
-- that is told the Filters field and that menu right after the click, before anything is
-- closed, to see what the click left open.
local function WeaponsMenu()
    local menu = {}
    local function Look(what)
        local field = UpgradeScoutFrame.FilterField
        field:Open()
        local seen = what(field, field:OpenSub("Weapons"))
        if field._open then field:Close() end
        return seen
    end
    -- Its lines, with their marks: those under the line that heads it.
    function menu:Lines()
        return Look(function(_, sub)
            local lines = {}
            for _, line in ipairs(sub.elements) do
                if line.kind ~= "title" then lines[#lines + 1] = line end
            end
            return MenuLines(lines, true)
        end)
    end
    -- The line that heads it, which says whose choice the menu shows; nil where it has none.
    function menu:Head()
        return Look(function(_, sub) return sub.elements[1].kind == "title" and sub.elements[1].text or nil end)
    end
    -- A click on a line, by its label.
    function menu:Click(label, keep)
        Look(function(field, sub)
            field:ClickSub(label)
            if keep then keep(field, sub) end
        end)
    end
    -- The frame of a line, as the game drew it and the addon dressed it, told to `what`.
    function menu:Line(label, what)
        return Look(function(_, sub)
            for i, line in ipairs(sub.elements) do
                if line.text == label then return what(sub.lines[i], line) end
            end
            error("no line labelled " .. label)
        end)
    end
    -- The tooltip of a line: its lines of text, joined.
    function menu:Tooltip(label)
        return self:Line(label, function(frame, line)
            GameTooltip:SetOwner(frame)
            line.tooltip(GameTooltip, line)
            local seen = {}
            for _, said in ipairs(GameTooltip._lines) do seen[#seen + 1] = said.text end
            GameTooltip:Hide()
            return table.concat(seen, " | ")
        end)
    end
    return menu
end

-- What a card keeps of its weapons for the profile it is scored on (Wants.lua): { hands,
-- kinds }, and an empty table where it keeps nothing.
local function Chosen(card)
    return ns.Wants.Kept(card) or {}
end

-- Writes that on a card as a saved file would have it: `hands`, and the kinds of `out`
-- unticked. Returns the card.
local function Keep(card, hands, out)
    local kinds
    for _, kind in ipairs(out or {}) do
        kinds = kinds or {}
        kinds[kind] = false
    end
    card.byProfile = { [ns.Wants.ProfileKey(card)] = { hands = hands, kinds = kinds } }
    return card
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
    eq(MAINHANDSLOT, "Main Hand", "the game has a word for the main hand")
    eq(ns.Compare.GroupLabel("MAINHAND"), "Weapon", "and its rows are headed by the addon's own: two-hand weapons are among them")
    eq(ns.Compare.GroupLabel("OFFHAND"), "Off Hand", "the off hand keeps the game's")
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

    -- Top N per slot: N rows and never one more. The best upgrade and the best value are
    -- always among them, and the other places go to the next biggest upgrades, whatever they
    -- cost: the best value has the place of the N-th when it is not one of the N biggest.
    -- u1..u8 each cost less per point than the one before; x1 and x2 are poor buys, and are
    -- listed for what they add.
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
    eq(rows[3].group, "CHEST", "chest block"); eq(rows[3].shown, 5, "five rows kept, as the number says"); eq(rows[3].total, 10, "of ten")
    eq(Ids(4), "u1 u2 x1 u3 u7", "the four biggest upgrades, poor buys or not, and the best value in the place of the fifth")
    eq(rows[4].entry.pick, "UPGRADE", "best upgrade marked"); eq(rows[8].entry.pick, "VALUE", "best value marked")
    -- (u8 costs the least per point of them all, and has no row: it is neither.)

    -- Of two offers that gain the same the cheaper stands first, and so has the last of the
    -- rows that go by size: the fifth of six, the best value having the sixth.
    many.e = offer("e", 45, 600000)
    rows = ns.Results.Build(many, ctx, { money = 1e9, limit = 6 })
    eq(Ids(4), "u1 u2 x1 u3 x2 u7", "x2 and not e, which gains as much for more")
    eq(rows[3].shown, 6, "six rows"); eq(rows[3].total, 11, "of eleven")
    many.e = nil

    -- The best value is one of the five: they are all there is to show.
    many.u2.buyout = 100            -- +38 for a silver: no cheaper point in the slot
    rows = ns.Results.Build(many, ctx, { money = 1e9, limit = 5 })
    eq(Ids(4), "u1 u2 x1 u3 x2", "five rows, the best value among them")
    eq(rows[3].shown, 5, "five rows"); eq(rows[3].total, 10, "of ten"); eq(rows[5].entry.pick, "VALUE", "u2 is the best value")

    rows = ns.Results.Build(many, ctx, { money = 1e9 })
    eq(rows[3].shown, 10, "no limit: everything listed"); eq(#rows, 2 + 1 + 10, "row count without the limit")
    eq(Ids(4), "u1 u2 x1 u3 x2 u4 u5 u6 u7 u8", "in order of size")
    eq(rows[5].entry.pick, "VALUE", "with the same pick: the limit has no say in the picks")

    -- No more offers than rows: all of them, and nothing for the header to count.
    rows = ns.Results.Build(offers, ctx, { money = 1e9, limit = 5 })
    eq(Ids(4), "a b c", "three chests, three rows"); eq(rows[3].shown, 3, "all three"); eq(rows[3].total, 3, "of three")

    -- What a player wrote of the list: "it shows like top 2, then 2 middle of the pack, then
    -- the best value". Ten chests, of which g2, g6, g8 and g9 each cost less per point than
    -- everything stronger. By the rule the list had then only those had rows beside the best
    -- upgrade: g1 g2 g6 g8 g9. The five biggest upgrades are g1 to g5, and the best value has
    -- the place of the fifth.
    local GOLD = 10000
    local wrote = {
        g1 = offer("g1", 50, 40 * GOLD),    -- +40, a gold a point
        g2 = offer("g2", 48, 30 * GOLD),    -- +38, 79 silver a point
        g3 = offer("g3", 46, 35 * GOLD),    -- +36, 97 silver
        g4 = offer("g4", 44, 32 * GOLD),    -- +34, 94 silver
        g5 = offer("g5", 42, 28 * GOLD),    -- +32, 88 silver
        g6 = offer("g6", 35, 15 * GOLD),    -- +25, 60 silver
        g7 = offer("g7", 32, 16 * GOLD),    -- +22, 73 silver
        g8 = offer("g8", 28, 9 * GOLD),     -- +18, 50 silver
        g9 = offer("g9", 22, 1 * GOLD),     -- +12, 8 silver: the best value
        g10 = offer("g10", 13, 50 * 100),   -- +3, 17 silver
    }
    rows = ns.Results.Build(wrote, ctx, { money = 1e9, limit = 5 })
    eq(Ids(2), "g1 g2 g3 g4 g9", "the real top four, and the best value: five rows for top five")
    eq(rows[1].shown, 5, "five rows"); eq(rows[1].total, 10, "of ten")
    eq(rows[2].entry.pick, "UPGRADE", "the best upgrade first"); eq(rows[6].entry.pick, "VALUE", "the best value last")
    for i = 3, 5 do eq(rows[i].entry.pick, nil, "no pick between them: " .. rows[i].entry.offer.id) end

    -- The number is the player's. A slot with a number shows that many rows, the best upgrade
    -- and the best value among them.
    local function Listed(opts)
        opts.money = 1e9
        rows = ns.Results.Build(wrote, ctx, opts)
        return Ids(2)
    end
    eq(Listed({ limit = 3 }), "g1 g2 g9", "top three: the best, the second biggest and the best value"); eq(rows[1].shown, 3, "three rows"); eq(rows[1].total, 10, "of ten")
    eq(Listed({ limit = 2 }), "g1 g9", "top two: the best upgrade and the best value"); eq(rows[1].shown, 2, "two rows")
    eq(rows[2].entry.pick, "UPGRADE", "each with its mark"); eq(rows[3].entry.pick, "VALUE", "whatever the number")
    eq(Listed({ limit = 1 }), "g1", "top one: the best upgrade alone"); eq(rows[1].shown, 1, "one row"); eq(rows[2].entry.pick, "UPGRADE", "with its mark")
    eq(Listed({ limit = 8 }), "g1 g2 g3 g4 g5 g6 g7 g9", "top eight: the best value is the ninth by size, and has the place of the eighth")
    eq(Listed({ limit = 9 }), "g1 g2 g3 g4 g5 g6 g7 g8 g9", "top nine: it is one of them, and they are the nine biggest")
    eq(Listed({ limit = 99 }), "g1 g2 g3 g4 g5 g6 g7 g8 g9 g10", "fewer offers than the number: all of them"); eq(rows[1].shown, 10, "ten of ten")
    -- The best upgrade is the best value too: one item has both places, and the rest go by size.
    wrote.g1.buyout = 100                   -- +40 for a silver: no cheaper point in the slot
    eq(Listed({ limit = 2 }), "g1 g2", "top two when the picks are one item: the two biggest"); eq(rows[2].entry.pick, "BOTH", "which has both marks")
    eq(Listed({ limit = 1 }), "g1", "top one: that item alone")
    eq(Listed({ limit = 3 }), "g1 g2 g3", "top three: the three biggest"); eq(rows[1].shown, 3, "three rows")
    wrote.g1.buyout = 40 * GOLD

    -- "Hide worse deals": an offer is left out when a stronger one costs the same or less per
    -- point. That is the rule the player wrote of, under its own name, and no number cuts it.
    -- g11 is too small to be the best value and costs less per point than it: the steps go on
    -- below the best value.
    wrote.g11 = offer("g11", 12, 100)       -- +2, half a silver a point
    eq(Listed({ frontier = true }), "g1 g2 g6 g8 g9 g11", "each row costs less per point than everything stronger")
    eq(rows[1].shown, 6, "six rows"); eq(rows[1].total, 11, "of eleven")
    eq(rows[2].entry.pick, "UPGRADE", "the best upgrade is the first of them"); eq(rows[6].entry.pick, "VALUE", "and the best value is among them")
    eq(rows[7].entry.pick, nil, "the picks are chosen among all eleven, as without it")
    -- The same price per point as a stronger offer is no reason to stay; a copper less is.
    wrote.t = offer("t", 30, 20 * GOLD)     -- +20 for a gold a point, as g1
    eq(Listed({ frontier = true }), "g1 g2 g6 g8 g9 g11", "as dear per point as a stronger one: left out")
    wrote.t.buyout = 12 * GOLD - 20         -- a copper a point under g6, which stands above it
    eq(Listed({ frontier = true }), "g1 g2 g6 t g8 g9 g11", "a copper less per point than everything stronger: listed")
    -- And of two that gain the same, the dearer is left out.
    wrote.t2 = offer("t2", 30, 12 * GOLD)
    eq(Listed({ frontier = true }), "g1 g2 g6 t g8 g9 g11", "the same gain for more: left out")
    wrote.t, wrote.t2 = nil, nil

    -- Both: what a stronger offer beats for its price is left out first, and the number
    -- counts among the rest. The best value is always one of those, and has its row.
    eq(Listed({ frontier = true, limit = 5 }), "g1 g2 g6 g8 g9", "top five of the six that are left: the best value is the fifth")
    eq(rows[1].shown, 5, "five rows"); eq(rows[1].total, 11, "of eleven")
    eq(Listed({ frontier = true, limit = 3 }), "g1 g2 g9", "top three of them: the two biggest that are left, and the best value")
    eq(rows[1].shown, 3, "three rows"); eq(rows[1].total, 11, "of eleven")
    eq(rows[2].entry.pick, "UPGRADE", "the same picks"); eq(rows[4].entry.pick, "VALUE", "as in every other list of the slot")
    eq(Listed({ frontier = true, limit = 2 }), "g1 g9", "top two of them: the best upgrade and the best value")
    eq(Listed({ frontier = true, limit = 1 }), "g1", "top one of them: the best upgrade alone")
    eq(Listed({ frontier = true, limit = 99 }), "g1 g2 g6 g8 g9 g11", "fewer left than the number: all that are left")
    eq(Listed({ limit = 5 }), "g1 g2 g3 g4 g9", "and without it the top five are the four biggest and the best value again")

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

-- The list does not wait for the rows the client is slow to tell about: it is shown, and its
-- prices are looked up, while those are read on. A real scan stood four seconds near the end
-- of its scoring for 13 rows of 10,000 that the client never told of.
function scenarios.scan_late()
    StandardWorld()
    W.AddItem({ id = 300, name = "Ghost", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 70, level = 9, uncached = true })
    W.AddAuction(300, 100)
    W.neverLoad = { [300] = true }       -- the client never loads this one,
    W.AddItem({ id = 301, name = "Late Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 40, level = 9, uncached = true })
    W.AddAuction(301, 600)
    W.loadAfter = { [301] = 2.5 }        -- and this one after two and a half seconds
    LoadAddon()
    SetView(false, false)                -- every upgrade is listed, so every price is looked up
    W.OpenAuctionHouse()
    local S = ns.Scanner
    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "score" end, 60)
    local began = W.now
    W.RunUntil(function() return S.state ~= "score" end, 60)
    eq(S.state, "verify", "the prices are looked up")
    check(W.now - began < 1.5, "a second after the last row was read, not four: " .. (W.now - began))
    check(Unsure("Good Chest") ~= nil or Offer("Good Chest") ~= nil, "the rows that were read are in the list")
    eq(Unsure("Late Helm"), nil, "a row the client has not told of is not in the list yet")
    eq(S.stats.late, 2, "two rows the list did not wait for")
    eq(S.stats.lateWhy.data, 2, "both for want of their items")

    W.RunUntil(function() return Unsure("Late Helm") ~= nil or Offer("Late Helm") ~= nil end, 5)
    check(W.now - began < 3.2, "the helm is in the list as soon as the client has it: " .. (W.now - began))
    eq(S.state, "verify", "while the prices are looked up")
    eq(S.stats.lateRead, 1, "one late row read")

    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(Offer("Late Helm").buyout, 600, "and its price is looked up like any other")
    eq(Offer("Ghost"), nil, "the row never read went to its item search, which left it out")
    eq(S.stats.unread.data, 1, "one row never read, for want of its item")
    eq(S.stats.unreadItems[1], "300:0 data", "and it is named")
    eq(ns.db.lastScan.unread.data, 1, "the numbers are kept with the last scan's")
    eq(S.unanswered, 0, "nothing was left unanswered")
    check(Offer("Good Chest") ~= nil and Offer("Helm") ~= nil and Offer("Shield") ~= nil, "the rest of the list is whole")

    -- A scan stopped while a row is still being read: the row is a candidate from then on,
    -- and its search is among the prices looked up when the list asks for them again.
    check(S.Start(), "a second scan starts")
    W.RunUntil(function() return S.state == "verify" end, 60)
    eq(S.stats.late, 1, "the second scan: the one row that never loads is late")
    local searches = W.AH.calls.search
    S.Stop()
    eq(S.stats.unread.data, 1, "stopped: the late row is given to its search")
    S.Resume()
    check(S.Demand(), "the prices are picked up again")
    W.RunUntil(function() return S.state == "idle" end, 600)
    check(W.AH.calls.search > searches, "and looked up")
    eq(Offer("Ghost"), nil, "the row never read is left out again")
    check(Offer("Late Helm") ~= nil, "the helm, loaded by now, is found at once")
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
    local function Shown(affordableOnly, topOnly, hideWorse)
        local rows = ns.Results.Build(S.offers, S.ctx, {
            money = GetMoney(), affordableOnly = affordableOnly, limit = topOnly and ns.Results.TopCount() or nil, frontier = hideWorse,
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
    local function Name(view) return "afford=" .. tostring(view[1]) .. " top=" .. tostring(view[2]) .. (view[3] and " hide" or "") end
    local function Scan(view)
        SetView(view[1], view[2], view[3])
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
    -- (The third of a view: "Hide worse deals", by itself and with "top five".)
    local views = { { true, true }, { true, false }, { false, true }, { true, false, true }, { true, true, true }, { false, false } }
    local want = {}
    for _, view in ipairs(views) do want[Name(view)] = Shown(view[1], view[2], view[3]) end
    check(want["afford=true top=true"] ~= want["afford=true top=false"], "'top five' hides something in this world")
    check(want["afford=true top=true"] ~= want["afford=false top=true"], "so does the price filter")
    check(want["afford=true top=false hide"] ~= want["afford=true top=false"], "and so does 'hide worse deals'")
    check(want["afford=true top=false hide"] ~= want["afford=true top=true"], "which is another list than 'top five'")

    -- Scanned with a filter on, the list is the same and the searches are fewer.
    local used = {}
    for i = 1, #views - 1 do
        local view = views[i]
        used[i] = Scan(view)
        eq(Shown(view[1], view[2], view[3]), want[Name(view)], "same list as the full scan with " .. Name(view))
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
    eq(W.AH.calls.browse, 7, "seven scans, seven browse queries")
    check(used[4] <= used[1] and used[5] == used[4], "worse deals hidden: no more searches than for top five, and as many with top five as without ("
        .. used[4] .. ", " .. used[5] .. " and " .. used[1] .. ")")
    realPrint(string.format("      item searches: %d with both filters off, %d by default, %d with only the price filter, %d with only top five",
        all, used[1], used[2], used[3]))
    realPrint(string.format("      item searches with the price filter and worse deals hidden: %d, and %d with top five as well", used[4], used[5]))
end

-- "Top 5 per slot" as a player asked for it, "real top 5 + best value", in the five rows its
-- number says: the best value has the place of the fifth when it is not one of the five.
-- Eleven chests against a worn one worth 10, in the order of what they add:
--   Top Chest 1..5   +40 to +32, from 79 silver to a gold a point: the five biggest upgrades
--   Mid Chest A      +25 for 15 gold, 60 silver a point: less than any of those five
--   Mid Chest B      +22 for 16 gold, 73 silver a point: more than A
--   Resale Chest     +20 for 14 gold, 70 silver a point: more than A as well. A vendor pays
--                    13 gold 50 for it, and so it costs 2 silver 50 a point in the end
--   Mid Chest C      +18 for 9 gold, 50 silver a point
--   Value Chest      +12 for a gold, 8 silver a point: the best value by buyout
--   Tiny Chest       +3 for 10 copper: the cheapest point of all, and under a quarter of +40
local function TopFiveWorld()
    local GOLD = 10000
    W.AddItem({ id = 100, name = "Worn Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 10, level = 5 })
    W.equipped[5] = W.Link(100)
    local chests = {
        { "Top Chest 1", 50, 40 * GOLD }, { "Top Chest 2", 48, 30 * GOLD }, { "Top Chest 3", 46, 35 * GOLD },
        { "Top Chest 4", 44, 32 * GOLD }, { "Top Chest 5", 42, 28 * GOLD },
        { "Mid Chest A", 35, 15 * GOLD }, { "Mid Chest B", 32, 16 * GOLD },
        { "Resale Chest", 30, 14 * GOLD, 13 * GOLD + 5000 },
        { "Mid Chest C", 28, 9 * GOLD }, { "Value Chest", 22, 1 * GOLD }, { "Tiny Chest", 13, 10 },
    }
    for i, def in ipairs(chests) do
        W.AddItem({ id = 300 + i, name = def[1], equipLoc = "INVTYPE_CHEST", subClassID = 3, value = def[2], level = 8, sell = def[4] })
        W.AddAuction(300 + i, def[3])
    end
end

-- The list under "Top 5 per slot" is five rows of a slot: its biggest upgrades, with its best
-- value in the place of the fifth when it is not one of them. And the scan looks up no price
-- of what is neither one of the five biggest nor the best value, which such a list cannot show.
function scenarios.scan_top_five()
    TopFiveWorld()
    local GOLD = 10000
    W.player.money = 100 * GOLD
    LoadAddon()
    local R, S = ns.Results, ns.Scanner

    -- The question the scan asks of a slot before an item search (Results.LeftOut): has the
    -- list no row for an item that gives so much and costs so much at the least, whatever
    -- it turns out to cost? Asked of five chests known to be for sale, +40 to +32, each for a
    -- gold a point.
    local ctx = { equipped = { [5] = { link = "WORN", value = 10, invType = "INVTYPE_CHEST", itemID = 1 } } }
    local function offer(id, value, buyout)
        return { id = id, name = id, value = value, buyout = buyout, invType = "INVTYPE_CHEST", itemID = 100, count = 1 }
    end
    local known = {}
    for i = 1, 5 do known["v" .. i] = offer("v" .. i, 52 - 2 * i, (42 - 2 * i) * GOLD) end
    local five = R.Collect(known, ctx, { money = 1e12 }).CHEST
    eq(#five, 5, "five chests known")
    eq(R.LeftOut(five, 33, 1e12, false, 5), false, "+33 is one of the five biggest upgrades whatever it costs")
    eq(R.LeftOut(five, 30, 30 * GOLD, false, 5), true, "+30 for a gold a point at the least: sixth by its gain, and no cheaper a point than the five")
    eq(R.LeftOut(five, 30, 30 * GOLD - 1, false, 5), false, "a copper less and it may be the best value, which has a row")
    eq(R.LeftOut(five, 9, 1, false, 5), true, "+9 is under a quarter of +40: no best value, were it for a copper")
    eq(R.LeftOut(five, 10, 1, false, 5), false, "+10 is a quarter of it: for a copper it would be the best value")
    -- As much as the fifth of them gives, +32 for 32 gold: which of the two stands first is a
    -- matter of the price, and at the same price of neither.
    eq(R.LeftOut(five, 32, 32 * GOLD + 1, false, 5), true, "the fifth one's gain for a copper more: after it, and dearer a point")
    eq(R.LeftOut(five, 32, 32 * GOLD, false, 5), false, "for the same price nothing says that it stands after the fifth")
    eq(R.LeftOut(five, 32, 32 * GOLD - 1, false, 5), false, "and for less it stands before it")
    -- Four known: the fifth row is still to be had.
    known.v5 = nil
    eq(R.LeftOut(R.Collect(known, ctx, { money = 1e12 }).CHEST, 9, 1e12, false, 5), false, "four chests known: any fifth has a row")
    -- A cheaper point in a weaker chest proves nothing. w gives +12 for a copper a point, u
    -- +20 for 50 silver a point, less than the five: w is the best value, and u has no row.
    -- But u may not be passed over: a chest of +60 found later asks +15 of a best value,
    -- w falls short of that, and the row goes to u.
    known.v5 = offer("v5", 42, 32 * GOLD)
    known.w = offer("w", 22, 12)
    local six = R.Collect(known, ctx, { money = 1e12 }).CHEST
    eq(R.LeftOut(six, 20, 10 * GOLD, false, 5), false, "a weaker chest that costs less a point does not rule u out")
    local function Ids(offers)
        local out = {}
        for _, row in ipairs(R.Build(offers, ctx, { money = 1e12, limit = 5 })) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.id .. (row.entry.pick and "!" .. row.entry.pick or "") end
        end
        return table.concat(out, " ")
    end
    known.u = offer("u", 30, 10 * GOLD)
    eq(Ids(known), "v1!UPGRADE v2 v3 v4 w!VALUE", "as things stand the weak chest is the best value, in the place of the fifth, and u has no row")
    known.z = offer("z", 70, 90 * GOLD)
    eq(Ids(known), "z!UPGRADE v1 v2 v3 u!VALUE", "with a chest of +60 in the slot the row is u's")

    -- "Hide worse deals" asks another question of the slot (Results.Dominated): does a chest
    -- known to be for sale give more for no more a point than this one costs at the least,
    -- or as much for less? Asked of the five again, each for a gold a point.
    eq(R.Dominated(five, 30, 30 * GOLD, false), true, "+30 for a gold a point at the least: a stronger chest costs no more a point")
    eq(R.Dominated(five, 30, 30 * GOLD - 1, false), false, "a copper less and its point is the cheapest of all: it has a row")
    eq(R.Dominated(five, 33, 33 * GOLD, false), true, "one of the five biggest upgrades is left out for its price all the same")
    eq(R.Dominated(five, 9, 1, false), false, "and +9 for a copper is not, too small as it is to be the best value")
    eq(R.Dominated(five, 41, 1e12, false), false, "nothing known gives as much as +41: the best upgrade has a row at any price")
    -- Of two that give the same the dearer is left out. At the same price which of them
    -- stands first is not a matter of the price, and nothing is proven.
    local one = R.Collect({ s = offer("s", 42, 32 * GOLD) }, ctx, { money = 1e12 }).CHEST
    eq(R.Dominated(one, 32, 32 * GOLD + 1, false), true, "the gain of a chest that is known for a copper more: after it, and dearer a point")
    eq(R.Dominated(one, 32, 32 * GOLD, false), false, "for the same price nothing says which of the two stands first")
    eq(R.Dominated(one, 31, 31 * GOLD, false), true, "a point less for the same price a point: left out")
    -- With both boxes ticked the first question is no proof. Two chests known, +100 for 10
    -- copper a point and +90 for 20, and a list with rows for two: +10 for a copper a point
    -- is the third by its gain and too small to be the best value, so "top two" by itself
    -- has no row for it. With worse deals hidden the +90 is out for its price, and the
    -- second row is the small chest's.
    local pair = { p1 = offer("p1", 110, 1000), p2 = offer("p2", 100, 1800) }
    local two = R.Collect(pair, ctx, { money = 1e12 }).CHEST
    eq(R.LeftOut(two, 10, 10, false, 2), true, "top two: no row for +10, whatever it costs")
    eq(R.Dominated(two, 10, 10, false), false, "worse deals hidden: no stronger chest is as cheap a point")
    pair.p3 = offer("p3", 20, 10)
    local function Two(frontier)
        local out = {}
        for _, row in ipairs(R.Build(pair, ctx, { money = 1e12, limit = 2, frontier = frontier })) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.id end
        end
        return table.concat(out, " ")
    end
    eq(Two(false), "p1 p2", "the two biggest upgrades"); eq(Two(true), "p1 p3", "and the two biggest of what is left with worse deals hidden")

    -- The scan. Reference: "top five" off, so every price is looked up.
    W.OpenAuctionHouse()
    -- The rows of the chest slot under "top five", top to bottom, by buyout or by net cost;
    -- of the offers the scan has, or of a list of the test's own.
    local function Shown(net, offers)
        local rows = R.Build(offers or S.offers, S.ctx, { money = GetMoney(), affordableOnly = true, net = net, limit = R.TopCount() })
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.name .. (row.entry.pick and " (" .. row.entry.pick .. ")" or "") end
        end
        return table.concat(out, ", "), rows[1]
    end
    local function Scan(topOnly)
        SetView(true, topOnly)
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
    local all = Scan(false)
    eq(all, 11, "eleven chests, eleven item searches"); eq(OfferCount(), 11, "and eleven offers")
    local full = {}
    for id, found in pairs(S.offers) do full[id] = found end
    -- Five rows for top five. The best value is the tenth by its gain, or the eighth by net
    -- cost: it has the place of the fifth, and Top Chest 5 has no row.
    local FOUR = "Top Chest 1 (UPGRADE), Top Chest 2, Top Chest 3, Top Chest 4"
    local want = { buyout = FOUR .. ", Value Chest (VALUE)", net = FOUR .. ", Resale Chest (VALUE)" }
    local list, header = Shown(false)
    eq(list, want.buyout, "the four biggest upgrades, whatever a point of them costs, and the best value")
    eq(header.shown, 5, "five rows"); eq(header.total, 11, "of eleven")
    eq(Shown(true), want.net, "by net cost the same four, and the best value by that")

    -- Scanned with "top five" on: the same two lists for fewer searches. Two chests are not
    -- looked up. Mid Chest B is the seventh by its gain and at the least dearer a point than
    -- Mid Chest A, by buyout and by net cost. Tiny Chest is the last by its gain and adds too
    -- little to be the best value. Mid Chest A and C are looked up: each might have been the
    -- best value. So is Resale Chest, though A costs less a point by buyout: by net cost it
    -- may be the best value, and it is. (The scan passes over what is neither one of the five
    -- biggest nor the best value. The rows are all taken from those, so that is still a
    -- proof; Top Chest 5, one of the five, is looked up though the best value has its row.)
    local used = Scan(true)
    eq(used, 9, "nine item searches of eleven"); eq(S.stats.skipped, 2, "statistics: two candidates skipped")
    eq(Offer("Mid Chest B"), nil, "no price for a chest that is neither among the five nor the best value")
    eq(Offer("Tiny Chest"), nil, "nor for one that adds too little to be the best value, cheap as its point is")
    check(Unsure("Mid Chest B") ~= nil and Unsure("Tiny Chest") ~= nil, "both are counted at the lowest price of their rows")
    check(Offer("Mid Chest A") ~= nil and Offer("Mid Chest C") ~= nil and Offer("Resale Chest") ~= nil, "what might have been the best value has its price")
    list, header = Shown(false)
    eq(list, want.buyout, "the same list by buyout as the full scan")
    eq(header.shown, 5, "five rows"); eq(header.total, 11, "of eleven: the two not looked up are counted")
    eq(Shown(true), want.net, "and the same list by net cost")
    eq(S.Demand(), false, "nothing more is needed for the list as it is")

    -- The two that were passed over could not have had a row, whatever a search had found:
    -- at the lowest price of its row or at any price above it each leaves both lists as they
    -- are, rows and picks.
    local function With(name, buyout)
        local offers = {}
        for id, found in pairs(S.offers) do offers[id] = found end
        local priced = {}
        for key, value in pairs(Unsure(name)) do priced[key] = value end
        priced.buyout, priced.unsure = buyout, nil
        offers[priced.id] = priced
        return offers
    end
    for _, name in ipairs({ "Mid Chest B", "Tiny Chest" }) do
        local least = Unsure(name).buyout
        for _, buyout in ipairs({ least, least + 1, least * 2, 99 * GOLD }) do
            eq(Shown(false, With(name, buyout)), want.buyout, name .. " for " .. buyout .. ": no row by buyout")
            eq(Shown(true, With(name, buyout)), want.net, name .. " for " .. buyout .. ": no row by net cost")
        end
        -- (Said of the rows themselves, as the list now counts them: five, and none its own.)
        local with, head = Shown(false, With(name, least))
        check(head.shown == 5 and not with:find(name, 1, true), name .. ", passed over by the scan: the slot has its five rows, and none of them is that chest's")
    end
    -- That rests on the lowest price of the row. For a gold, which its row rules out, Mid
    -- Chest B would have been the best value. Tiny Chest has no row at any price.
    eq(Shown(false, With("Mid Chest B", 1 * GOLD)), FOUR .. ", Mid Chest B (VALUE)", "under its row's lowest price the chest would have had a row")
    eq(Shown(false, With("Tiny Chest", 1)), want.buyout, "the tiny chest for a copper: no row")

    -- The list starts to need a price it did not have. With 29 gold four of the five biggest
    -- upgrades cost too much, and Mid Chest B is one of the five that are left: its price is
    -- asked for, and no other. Tiny Chest still has six before it.
    W.player.money = 29 * GOLD
    eq(More(), 1, "29 gold: one item search"); eq(W.AH.calls.browse, 2, "sent as a follow-up, not by a new scan")
    check(Offer("Mid Chest B") ~= nil, "for Mid Chest B"); eq(Offer("Tiny Chest"), nil, "and not for Tiny Chest")
    eq(Shown(false), "Top Chest 5 (UPGRADE), Mid Chest A, Mid Chest B, Resale Chest, Value Chest (VALUE)",
        "the four biggest upgrades for 29 gold, and the best value")
    eq(Shown(false), Shown(false, full), "as the scan that looked everything up has it")
    eq(Shown(true), "Top Chest 5 (UPGRADE), Mid Chest A, Mid Chest B, Resale Chest (VALUE), Mid Chest C", "by net cost the best value is one of the five")
    eq(Shown(true), Shown(true, full), "the same there")
    W.player.money = 100 * GOLD
    eq(More(), 0, "a hundred gold again: every price that list needs is known")
    eq(Shown(false), want.buyout, "and it is the list it was")

    -- "Top five" off: the one price still missing is looked up.
    SetView(true, false)
    eq(More(), 1, "'top five' off: one search, for Tiny Chest")
    eq(used + 2, all, "in all each chest was searched once")
    eq(UnsureCount(), 0, "no price in the list that was not looked up")

    -- The other lists the two lines of the menu make, each scanned for anew: worse deals
    -- hidden, top five of those, and a top three of the player's own. Each is the list of
    -- the scan that looked everything up, by buyout and by net cost, for seven searches.
    --   * Worse deals hidden, with a number or without: a chest is passed over when one
    --     already priced gives more for no more a point. Top Chest 3, 4 and 5 cost more a
    --     point than Top Chest 2, and Mid Chest B more than Mid Chest A. So does Resale
    --     Chest by buyout: it is looked up for what it costs in the end. Tiny Chest has the
    --     cheapest point of all, and is looked up too.
    --   * Top three: the three biggest are looked up, and what might be the best value. Top
    --     Chest 4 and 5 and Mid Chest B are neither, and Tiny Chest adds too little. The rows
    --     are three: the two biggest, and the best value in the place of Top Chest 3.
    -- And no chest that was passed over would have had a row, at the lowest price of its row
    -- or at any above it.
    local function List(case, net, offers)
        local rows = R.Build(offers or S.offers, S.ctx, { money = GetMoney(), affordableOnly = true, net = net, limit = case.top, frontier = case.hide })
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.name .. (row.entry.pick and " (" .. row.entry.pick .. ")" or "") end
        end
        return table.concat(out, ", ")
    end
    local STEPS = "Top Chest 1 (UPGRADE), Top Chest 2, Mid Chest A, "
    local TWO = "Top Chest 1 (UPGRADE), Top Chest 2, "
    local cases = {
        { name = "worse deals hidden", hide = true,
          buyout = STEPS .. "Mid Chest C, Value Chest (VALUE), Tiny Chest", net = STEPS .. "Resale Chest (VALUE), Tiny Chest",
          passed = { "Top Chest 3", "Top Chest 4", "Top Chest 5", "Mid Chest B" } },
        { name = "top five of those", top = 5, hide = true,
          buyout = STEPS .. "Mid Chest C, Value Chest (VALUE)", net = STEPS .. "Resale Chest (VALUE), Tiny Chest",
          passed = { "Top Chest 3", "Top Chest 4", "Top Chest 5", "Mid Chest B" } },
        { name = "top three", top = 3,
          buyout = TWO .. "Value Chest (VALUE)", net = TWO .. "Resale Chest (VALUE)",
          passed = { "Top Chest 4", "Top Chest 5", "Mid Chest B", "Tiny Chest" } },
    }
    for _, case in ipairs(cases) do
        ns.db.topCount = case.top
        SetView(true, case.top ~= nil, case.hide)
        W.RunUntil(function() return W.AH.ready end, 5)
        local before = W.AH.calls.search
        ScanToEnd()
        eq(W.AH.calls.search - before, 7, case.name .. ": seven item searches of eleven"); eq(S.stats.skipped, 4, case.name .. ": four chests passed over")
        eq(List(case, false), case.buyout, case.name .. ": the list by buyout"); eq(List(case, false, full), case.buyout, case.name .. ": which the full scan has too")
        eq(List(case, true), case.net, case.name .. ": the list by net cost"); eq(List(case, true, full), case.net, case.name .. ": which the full scan has too")
        eq(S.Demand(), false, case.name .. ": nothing more is needed for the list as it is")
        for _, name in ipairs(case.passed) do
            eq(Offer(name), nil, case.name .. ": no price for " .. name)
            local least = Unsure(name).buyout
            for _, buyout in ipairs({ least, least + 1, least * 2, 99 * GOLD }) do
                eq(List(case, false, With(name, buyout)), case.buyout, case.name .. ", " .. name .. " for " .. buyout .. ": no row by buyout")
                eq(List(case, true, With(name, buyout)), case.net, case.name .. ", " .. name .. " for " .. buyout .. ": no row by net cost")
            end
        end
    end

    -- The number or a box changed after a scan: the prices the list then needs are sent for,
    -- and no others. Five for three: Top Chest 4 and 5 are among the five.
    ns.db.topCount = 5
    eq(More(), 2, "top five after top three: two searches"); check(Offer("Top Chest 4") ~= nil and Offer("Top Chest 5") ~= nil, "for the fourth and the fifth")
    eq(Shown(false), want.buyout, "the list of the top five by buyout"); eq(Shown(true), want.net, "and by net cost")
    -- Worse deals hidden as well: Tiny Chest, which top five has no row for, is the fifth of
    -- the chests that no stronger one undersells by net cost.
    SetView(true, true, true)
    eq(More(), 1, "worse deals hidden as well: one search"); check(Offer("Tiny Chest") ~= nil, "for Tiny Chest"); eq(Offer("Mid Chest B"), nil, "and not for Mid Chest B")
    eq(List(cases[2], false), cases[2].buyout, "the list of both by buyout"); eq(List(cases[2], true), cases[2].net, "and by net cost")
    SetView(true, false)
    eq(More(), 1, "neither ticked: the one price still missing"); eq(UnsureCount(), 0, "Mid Chest B's")
    ns.db.topCount = nil
end

-- "Top [ 5 ] per slot" and "Hide worse deals" in the Filters menu (Filters.lua). The first has
-- a field for its number, typed as the numbers of the character's own lines are; the second
-- is a tick box under it. Both are the player's (ns.db). Either changes the list at once and
-- sends for the prices the list then needs. The chests are those of "scan_top_five".
function scenarios.top_ui()
    TopFiveWorld()
    W.player.money = 100 * 10000
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local filters = frame.FilterField
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    -- The chests the list shows, top to bottom: "Top 1, Top 2, Mid A, Value".
    local function Listed()
        local out = {}
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w._kind == "Button" and w.entry then out[#out + 1] = (w.entry.offer.name:gsub(" Chest", "")) end
        end
        return table.concat(out, ", ")
    end
    -- The item searches sent since the last look, once the list is at rest.
    local seen = 0
    local function Searches()
        W.RunUntil(function() return S.state == "idle" end, 300)
        W.Run(0.5)
        local sent = W.AH.calls.search - seen
        seen = W.AH.calls.search
        return sent
    end
    local function Names() return frame.FilterNames:GetText() end
    local LABEL, HIDE = "Top", "Hide worse deals"
    local ALL = "Top 1, Top 2, Top 3, Top 4, Top 5, Mid A, Mid B, Resale, Mid C, Value, Tiny"
    local top, hide = FilterBox(LABEL), FilterBox(HIDE)
    -- The line of the open menu, and its field.
    local function Line()
        local line = filters.lines[filters:Find(LABEL)]
        return line, line.Number
    end
    local function Title(tickBox)
        tickBox:Tooltip()
        local title, tip = GameTooltip._lines[1].text, GameTooltip._lines[2].text
        GameTooltip:Hide()
        return title, tip
    end

    -- The two lines stand together, under the price filters. Top five is on from the start.
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top | Hide worse deals | Best armor type for the class | Upgrade at least | Gear at most | Weapons > | / | Value by net cost",
        "the line with the number, and the line under it")
    eq(top:GetChecked(), true, "top five is ticked from the start"); eq(hide:GetChecked(), false, "worse deals are hidden once that is ticked")
    eq(ns.db.topCount, nil, "no number is written down until one is typed"); eq(ns.Results.TopCount(), 5, "five stands for it")
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ScanButton:Click()
    eq(Searches(), 9, "a scan for the top five: nine item searches of eleven")
    eq(Listed(), "Top 1, Top 2, Top 3, Top 4, Value", "five rows: the four biggest upgrades, and the best value in the place of the fifth")
    eq(Names(), "Affordable \194\183 Top 5", "named beside the field with its number")

    -- The line: a tick box, its word, a field for the number, and the words it goes on with.
    filters:Open()
    local line, number = Line()
    check(number ~= nil and number._kind == "EditBox", "the line has a field for the number")
    eq(number:GetText(), "5", "with five in it until a number is typed"); eq(line.Tick:IsShown(), true, "and its tick")
    eq(number:GetWidth(), 30, "wide enough for two digits"); eq(number._mouse, true, "and in reach of the mouse")
    eq(line._size[1], 16 + 7 + line.fontString:GetStringWidth() + 6 + 30 + 4 + #"per slot" * 6, "the box, the word, the field and the words after it in a row")
    filters:Close()
    local title, tip = Title(top)
    eq(title, "Top 5 per slot", "the tooltip is titled with the line in full"); eq(tip, ns.L.TOP_TIP, "and says what the number is")
    check(tip:find("as many items as the number says", 1, true) ~= nil and not tip:find("%d", 1, true), "in words that hold for any number")

    -- A number typed is asked for at once. Seven: Mid Chest B is the seventh by its gain,
    -- which top five had no row for, and its price is sent for: the scan passes over nothing
    -- that is one of the seven biggest. The seventh row is the best value's all the same.
    -- Tiny Chest is still out.
    filters:Open()
    line, number = Line()
    W.Type(number, "7")
    eq(ns.db.topCount, 7, "the number is the player's setting"); eq(ns.db.topOnly, true, "and the box stays ticked")
    eq(filters._open, true, "the menu stays up"); check(Line() == line, "and its line is the one that was typed into")
    eq(Searches(), 1, "one item search"); check(Offer("Mid Chest B") ~= nil, "for the seventh chest"); eq(Offer("Tiny Chest"), nil, "and for no other")
    eq(Listed(), "Top 1, Top 2, Top 3, Top 4, Top 5, Mid A, Value", "seven rows: the six biggest upgrades and the best value")
    eq(Names(), "Affordable \194\183 Top 7", "the name beside the field has the number")
    filters:Close()
    eq((Title(top)), "Top 7 per slot", "and so has the tooltip of the line")
    -- A smaller number is a shorter list, and nothing to look up.
    filters:Open()
    number = select(2, Line())
    eq(number:GetText(), "7", "the menu opened again has the number")
    W.Type(number, "3")
    eq(Searches(), 0, "three: no item search")
    eq(Listed(), "Top 1, Top 2, Value", "three rows: the best upgrade, the second biggest and the best value"); eq(Names(), "Affordable \194\183 Top 3", "by name")
    filters:Close()

    -- "Hide worse deals": a chest is left out when a stronger one costs the same or less per
    -- point. Ticked with top three, the three are counted among the chests that are left.
    -- Top Chest 3 costs more a point than Top Chest 2 and is out, but it had no row: the
    -- two biggest of those that are left are Top Chest 1 and 2 still, and the third row is
    -- the best value's as before. Tiny Chest, too small to have a row under any number, is
    -- one of those that are left: its price is sent for.
    title, tip = Title(hide)
    eq(title, HIDE, "its tooltip is titled with its label"); eq(tip, ns.L.DEALS_TIP, "and says what is left out")
    check(tip:find("Leaves out an item when the same slot has another that is both stronger and a better deal. Example: +30% for 5 gold and +20% for 4 gold.", 1, true) ~= nil, "in plain words, with an example in numbers")
    hide:Click()
    eq(ns.db.hideWorse, true, "the setting is the player's"); eq(hide:GetChecked(), true, "ticked")
    eq(Searches(), 1, "one item search"); check(Offer("Tiny Chest") ~= nil, "for Tiny Chest")
    eq(Listed(), "Top 1, Top 2, Value", "three of the chests that no stronger one undersells: the two biggest and the best value")
    eq(Names(), "Affordable \194\183 Top 3 \194\183 No worse deals", "both are named beside the field")
    filters._tooltip(GameTooltip)
    eq(GameTooltip._lines[3].text, "Top 3 per slot", "the field's tooltip has both lines in full"); eq(GameTooltip._lines[4].text, HIDE, "one under the other")
    GameTooltip:Hide()

    -- The field left empty unticks its box, and the number is back in it. Worse deals hidden
    -- and no number: every chest that no stronger one undersells.
    filters:Open()
    line, number = Line()
    W.Type(number, "")
    eq(ns.db.topOnly, true, "an empty field asks for nothing")
    W.PressEnter(number)
    eq(ns.db.topOnly, false, "left empty: unticked"); eq(line.Tick:IsShown(), false, "the tick goes")
    eq(number:GetText(), "3", "and the last number is back in the field"); eq(ns.db.topCount, 3, "kept for the next time")
    eq(Searches(), 0, "no item search")
    eq(Listed(), "Top 1, Top 2, Mid A, Mid C, Value, Tiny", "each costs less per point than everything stronger")
    eq(Names(), "Affordable \194\183 No worse deals", "named by itself")
    filters:Close()
    -- Neither ticked: everything, and every price has been looked up by now.
    hide:Click()
    eq(ns.db.hideWorse, false, "unticked"); eq(Searches(), 0, "no item search"); eq(UnsureCount(), 0, "no price in the list that was not looked up")
    eq(Listed(), ALL, "all eleven chests"); eq(Names(), "Affordable", "and neither is named")

    -- The tick box itself asks for the number that is in the field. 99 is the most there is.
    top:Click()
    eq(ns.db.topOnly, true, "ticked"); eq(ns.db.topCount, 3, "with the number that was there")
    W.Run(0.5)
    eq(Listed(), "Top 1, Top 2, Value", "the list is cut at once, to three rows")
    filters:Open()
    number = select(2, Line())
    W.Type(number, "99")
    eq(ns.db.topCount, 99, "99 typed")
    W.Run(0.5)
    eq(Listed(), ALL, "more than the slot has: all of them"); eq(Names(), "Affordable \194\183 Top 99", "by name")
    filters:Close()
    -- The number comes out of a saved file: what is no number from 1 to 99 there is read as one.
    for _, saved in ipairs({ { "x", 5 }, { 0, 1 }, { -3, 1 }, { 2.7, 2 }, { 250, 99 }, { 0 / 0, 5 } }) do
        ns.db.topCount = saved[1]
        eq(ns.Results.TopCount(), saved[2], "a saved " .. tostring(saved[1]) .. " is read as " .. saved[2])
    end
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
        local rows = ns.Results.Build(S.offers, S.ctx, { money = GetMoney(), affordableOnly = true, limit = ns.Results.TopCount() })
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
    eq(S.stats.resent, 0, "statistics: no search sent twice"); eq(#S.stats.slow, 0, "and none that took long")
    check(S.stats.slowest > 0 and S.stats.slowest < 1, "an answer comes in well under a second: " .. S.stats.slowest)
    eq(S.stats.foreign, 0, "nobody else searched meanwhile"); eq(S.stats.dropped, 0, "and no request was thrown away")

    -- A search left without an answer once is sent again after a second, not eight (four
    -- times as long as an answer has taken in this scan, and no less than a second): the
    -- second sending is answered, and the scan loses that second and no price. The statistics
    -- say where the time went.
    W.RunUntil(function() return W.AH.ready end, 5)
    check(S.Start(), "fourth scan starts")
    W.RunUntil(function() return S.state == "verify" and OfferCount() >= 1 end, 60)
    local searches, began = W.AH.calls.search, GetTime()
    W.AH.dropSearches = 1
    W.RunUntil(function() return W.AH.calls.search == searches + 1 end, 60)
    -- Somebody else searches while it waits for that answer: it is counted.
    W.RunUntil(function() return W.AH.ready end, 5)
    C_AuctionHouse.SendBrowseQuery({ searchString = "x", sorts = {}, itemClassFilters = {} })
    W.RunUntil(function() return W.AH.calls.search == searches + 2 end, 60)
    local waited = GetTime() - began
    check(waited >= 1 and waited < 2, "the search without an answer is sent again after a second: " .. waited)
    W.RunUntil(function() return S.state == "idle" end, 120)
    W.Run(0.3)
    eq(S.unanswered, 0, "it got its answer the second time"); eq(S.stats.timeouts, 0, "statistics: no search without an answer")
    eq(OfferCount(), 6, "all six prices are in the list"); eq(UnsureCount(), 0, "none left at its row's lowest price")
    eq(S.stats.resent, 1, "statistics: one search sent twice"); eq(S.stats.foreign, 1, "one search of somebody else's")
    eq(#S.stats.slow, 1, "one search took long")
    local slow = S.stats.slow[1]
    eq(slow.tries, 2, "sent twice"); check(slow.sec >= 1 and slow.sec < 2, "over a second: " .. slow.sec)
    check(slow.item:find("%d+:%d+$") ~= nil and slow.auctions >= 1, "with the item it was for and its auctions: " .. slow.item)
    eq(ns.db.lastScan.resent, 1, "kept with the last scan's numbers"); eq(#ns.db.lastScan.slow, 1, "the slow search too")
end

-- An answer that is slow to come, while the client lets no other request out: the search is
-- not sent again over it. A second sending put in line behind the first would go out after
-- the answer and take it away again, and the row with it.
function scenarios.scan_slow_answer()
    StandardWorld()
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local function Begin(label)
        W.RunUntil(function() return W.AH.ready end, 15)
        local searches = W.AH.calls.search
        check(S.Start(), label .. ": scan starts")
        W.RunUntil(function() return S.state == "verify" and OfferCount() >= 1 end, 60)
        return searches
    end
    local function End(label)
        W.RunUntil(function() return S.state == "idle" end, 120)
        W.Run(0.5)
        eq(OfferCount(), 6, label .. ": all six prices are in the list"); eq(UnsureCount(), 0, label .. ": none left unchecked")
        eq(S.unanswered, 0, label .. ": nothing unanswered"); eq(S.stats.timeouts, 0, label .. ": no search given up")
    end

    -- How many searches a scan with every answer in time sends.
    local searches = Begin("plain")
    End("plain")
    local plain = W.AH.calls.search - searches

    -- The answer comes after 3.4 seconds, and the client is busy until then.
    searches = Begin("slow")
    W.AH.slowSearch = { answer = 3.41, ready = 3.44 }
    End("slow")
    eq(W.AH.calls.search - searches, plain, "slow: every search went out once")
    eq(S.stats.resent, 0, "slow: none a second time")
    eq(#S.stats.slow, 1, "slow: the slow one is written down")
    local slow = S.stats.slow[1]
    eq(slow.tries, 1, "slow: sent once"); check(slow.sec >= 3.3 and slow.sec < 4, "slow: over three seconds: " .. slow.sec)
    check(slow.after >= 3.3 and slow.after < 4, "slow: the answer came that long after its one sending: " .. slow.after)
    check(S.stats.slowest >= 3.3 and S.stats.slowest < 4, "slow: the longest answer of the scan: " .. S.stats.slowest)

    -- No answer at all, and the client lets nothing out for twelve seconds: the search is
    -- sent again when it does, as it was before the first sending was given up early.
    searches = Begin("busy")
    W.AH.slowSearch = { answer = false, ready = 12 }
    End("busy")
    eq(W.AH.calls.search - searches, plain + 1, "busy: one search went out twice")
    eq(S.stats.resent, 1, "busy: counted")
    slow = S.stats.slow[1]
    eq(slow.tries, 2, "busy: sent twice"); check(slow.sec >= 12 and slow.sec < 13, "busy: twelve seconds: " .. slow.sec)
    check(slow.after < 1, "busy: the second sending was answered at once: " .. slow.after)

    -- No answer, and the client free again at once: sent again after a second. Answers have
    -- come in a fifth of a second here, and four times that is under the least it waits.
    searches = Begin("free")
    W.AH.slowSearch = { answer = false, ready = 0.15 }
    End("free")
    eq(W.AH.calls.search - searches, plain + 1, "free: one search went out twice")
    slow = S.stats.slow[1]
    check(slow.sec >= 1 and slow.sec < 2, "free: a second lost, not eight: " .. slow.sec)

    -- Where answers are slower to come the wait is longer: one that took 0.6 seconds, and the
    -- next search left without an answer is sent again after four times that.
    searches = Begin("lagging")
    W.AH.slowSearch = { answer = 0.6, ready = 0.15 }
    W.RunUntil(function() return W.AH.slowSearch == nil end, 30)
    W.Run(0.9)
    W.AH.slowSearch = { answer = false, ready = 0.15 }
    End("lagging")
    eq(W.AH.calls.search - searches, plain + 1, "lagging: one search went out twice")
    eq(#S.stats.slow, 1, "lagging: and is written down")
    slow = S.stats.slow[1]
    check(slow.sec >= 2.4 and slow.sec < 3.2, "lagging: after four times the slowest answer, 2.4 seconds: " .. slow.sec)

    -- An answer that is late and not lost, with the client free: the search goes out again
    -- after a second, the first answer comes right after, and the next searches are waited
    -- for as long as that one took. Nothing is lost by the second sending.
    searches = Begin("late")
    W.AH.slowSearch = { answer = 1.3, ready = 0.15 }
    W.RunUntil(function() return W.AH.slowSearch == nil end, 30)
    W.RunUntil(function() return #S.stats.slow == 1 end, 30)
    W.AH.slowSearch = { answer = false, ready = 0.15 }
    End("late")
    eq(W.AH.calls.search - searches, plain + 2, "late: two searches went out twice")
    eq(#S.stats.slow, 2, "late: both are written down")
    check(S.stats.slow[1].sec >= 1 and S.stats.slow[1].sec < 2, "late: the late answer came after 1.3 seconds: " .. S.stats.slow[1].sec)
    check(S.stats.slow[2].sec >= 3, "late: the next search without an answer was waited for longer, 3 seconds: " .. S.stats.slow[2].sec)
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
    -- then. Like any row whose item it never loads, it is left out: no search is sent.
    W.items["230:0"].cached = false
    W.neverLoad = { [230] = true }
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    eq(S.stats.searches, searches, "no search for the row nothing was known of")
    eq(S.stats.left, 1, "it is left out")
    eq(S.stats.timeouts, 0, "nothing goes unanswered"); eq(S.unanswered, 0, "and no price is missing")
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
    -- (For a moment the chest that takes bids alone is in the list at a copper, and the good
    -- chest beside it at its bid: the slot has no more than five chests, and a row for each.)
    check(Row("Bid Only Chest") ~= nil and Row("Good Chest") ~= nil, "the chest slot for now: the ones listed at a bid among its rows")
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
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top | Hide worse deals | Best armor type for the class | Upgrade at least | Gear at most | Weapons > | / | Value by net cost",
        "the lines of the menu, the one that is no filter under a rule")
    local checkbox, topBox = FilterBox("Only what I can afford"), FilterBox("Top")
    eq(topBox:GetChecked(), true, "top five on by default")
    eq(rows[3].Count:GetText(), "", "nothing cut, so no count in the header")
    eq(checkbox:GetChecked(), true, "afford filter on by default")
    -- A line of the menu is the game's, dressed as the tab's own tick boxes are.
    filters:Open()
    local ticked, unticked = filters.lines[filters:Find("Top")], filters.lines[filters:Find("Value by net cost")]
    eq(ticked.leftTexture1:GetAlpha(), 0, "the game's square is see-through")
    eq(Pictures(ticked, "Inset"), 9, "under our recess, cut in nine"); eq(Pictures(ticked, "RowGlow"), 1, "with the light of a row under the mouse")
    eq(Pictures(ticked, "Check"), 1, "our gold tick"); eq(ticked.Tick:IsShown(), true, "which shows on a line that is ticked")
    eq(Pictures(unticked, "Check"), 1, "a line that is not has one too"); eq(unticked.Tick:IsShown(), false, "out of sight")
    filters:Close()
    -- What is on is plain without a click: the names of those filters stand beside the field.
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5", "the filters that are on, by name")
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
    eq(frame.FilterNames:GetText(), "Top 5", "the filter is named beside the field no more")
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
    -- Weaker than twenty of them and far dearer per point than Legs 40: neither one of the
    -- five biggest upgrades nor the best value, so "top five" never shows it.
    W.AddItem({ id = 990, name = "Poor Deal Legs", equipLoc = "INVTYPE_LEGS", subClassID = 3, value = 20, level = 5 })
    W.AddAuction(990, 5000)
    ns.Scanner.offers, ns.Scanner.ctx, ns.Scanner.finishedAt = {}, nil, nil
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.3)
    eq(dropdown:GetText(), "Arms", "the dropdown follows a scale changed elsewhere")

    -- Top five: the forty legs shrink to five, and the header says how many there are. The
    -- four biggest upgrades (40 down to 37), and under them the best value (10: the cheapest
    -- per point that gives at least a quarter of +40), which is not one of the five biggest
    -- and has the place of the fifth.
    local legs
    rows = Rows()
    for i, row in ipairs(rows) do
        if Data(row).kind == "header" and Data(row).group == "LEGS" then legs = i end
    end
    eq(rows[legs].Title:GetText(), "LEGS", "the legs block")
    eq(rows[legs].Count:GetText(), "5 of about 41", "its header counts the cut and the ones not looked up")
    eq(Offer("Poor Deal Legs"), nil, "no item search for an offer the list would hide")
    -- (Nor for the nine weakest: cheaper per point than anything, and too small a gain to be
    -- the best value. The legs from 35 down to 10 each might have been it, and were looked up.)
    eq(Offer("Legs 9"), nil, "nor for legs that add too little to be the best value"); check(Unsure("Legs 9") ~= nil, "which are counted at their row's price")
    check(Offer("Legs 35") ~= nil and Offer("Legs 10") ~= nil, "the legs that might have been the best value have their prices")
    eq(rows[legs + 1].Name:GetText(), "|cff1eff00Legs 40|r", "best legs first")
    eq(rows[legs + 4].Name:GetText(), "|cff1eff00Legs 37|r", "the fourth of them three steps below the best")
    eq(rows[legs + 5].Name:GetText(), "|cff1eff00Legs 10|r", "then the best value, in the fifth row and not in a sixth")
    eq(rows[legs + 5].Pick.Text:GetText(), "Best value", "marked as best value")
    eq(rows[legs + 4].Pick:IsShown(), false, "no plate on a row that is neither pick")
    eq(rows[legs + 5].Price:GetAmount(), 100, "for a silver: ten copper a point, the least of those that add enough")
    check(rows[legs + 6] == nil or Data(rows[legs + 6]).kind == "header", "no sixth legs row")
    topBox:Tooltip()
    eq(GameTooltip._lines[1].text, "Top 5 per slot", "the filter's tooltip is titled with its line in full")
    check(GameTooltip._lines[2].text:find("Each slot keeps as many items as the number says: the best upgrade, the best value and the next biggest ones.", 1, true) ~= nil, "and explains it")
    check(GameTooltip._lines[2].text:find("Example: with 3, the best, the second biggest and the best value.", 1, true) ~= nil, "with an example")

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
    -- A chest that "top five" has no row for: the weakest of six, and dearer per point than the
    -- Good Chest. Three of the five before it are weaker than the Good Chest and dearer, so
    -- no set has a use for them, and dearer than the plain one, which a set can need for all
    -- of them.
    W.AddItem({ id = 220, name = "Plain Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 13, level = 8 })
    W.AddAuction(220, 2000)
    for i = 1, 3 do
        W.AddItem({ id = 220 + i, name = "Dear Chest " .. i, equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 13 + i, level = 8 })
        W.AddAuction(220 + i, 5000 + 500 * i)
    end
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
    local afford, top = FilterBox("Only what I can afford"), FilterBox("Top")
    eq(afford:IsEnabled(), false, "the price filter has no say in a set: its line of the menu is grey")
    eq(top:IsEnabled(), false, "and so is top five's"); eq(FilterBox("Hide worse deals"):IsEnabled(), false, "and the line under it")
    frame.FilterField:Open()
    eq(frame.FilterField.lines[frame.FilterField:Find("Top")].Number._mouse, false, "the number of top five is only read meanwhile")
    frame.FilterField:Close()
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
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5", "and named beside the field again")
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
    -- "Top N per slot" has a row for each of three chests, whichever price the picks go by.
    rows = R.Build(offers, ctx, { money = 1e9, net = true, limit = 5 })
    eq(Read(), "a@4000!BOTH b@18000 c@6000", "top five by net cost: the three of them")
    eq(rows[1].shown, 3, "three rows"); eq(rows[1].total, 3, "of three")
    rows = R.Build(offers, ctx, { money = 1e9, limit = 5 })
    eq(Read(), "a@100000!UPGRADE b@20000 c@6000!VALUE", "top five by buyout: the same three")
    -- With more than five the row it keeps for the best value goes by the same price as the
    -- pick. Five chests stronger than those, which no vendor buys: the four biggest of them
    -- have rows either way, and the fifth row is the best value's.
    local seven = { a = offers.a, c = offers.c }
    for i = 1, 5 do seven["s" .. i] = offer("s" .. i, 56 - i, 510000 - 10000 * i, 0) end   -- +45 to +41
    rows = R.Build(seven, ctx, { money = 1e9, limit = 5 })
    eq(Read(), "s1@500000!UPGRADE s2@490000 s3@480000 s4@470000 c@6000!VALUE", "by buyout the fifth row is the cheap chest's")
    eq(rows[1].shown, 5, "five rows"); eq(rows[1].total, 7, "of seven")
    rows = R.Build(seven, ctx, { money = 1e9, net = true, limit = 5 })
    eq(Read(), "s1@500000!UPGRADE s2@490000 s3@480000 s4@470000 a@4000!VALUE", "by net cost it is the dear chest's")
    eq(rows[1].shown, 5, "five rows there too")
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
    eq(Read(), "a@4000!UPGRADE f@0!VALUE g@0", "free in the end: the best value, and of two that are free the stronger")

    -- What the scanner asks before an item search: would "top N" leave an item out whatever
    -- its price turns out to be? It asks that of the list by net cost and of the one by buyout,
    -- and the least the item can cost is a cost of the same kind. Asked here with the number
    -- one, where one stronger chest stands before the item: what is left to prove is that it
    -- cannot be the best value. (The question is the same for every number: is the item
    -- neither one of the N biggest nor the best value? A list of one row has none for the
    -- best value, so of that list it asks more than is needed, and never less.)
    local entries = R.Collect({ a = offer("a", 50, 100000, 96000) }, ctx, { money = 1e9 }).CHEST
    eq(R.LeftOut(entries, 20, 2000, true, 1), true, "by net cost, +20 for a silver a point at the least: no cheaper than the dear chest")
    eq(R.LeftOut(entries, 20, 1999, true, 1), false, "a copper less and it may be the best value")
    eq(R.LeftOut(entries, 40, 4001, true, 1), true, "the same gain for more")
    eq(R.LeftOut(entries, 40, 4000, true, 1), false, "but not for the same")
    eq(R.LeftOut(entries, 20, 2000, false, 1), false, "by buyout the dear chest rules that item out no more")
    eq(R.LeftOut(entries, 20, 50000, false, 1), true, "+20 for 25 silver a point at the least: by buyout no cheaper than it")
    eq(R.LeftOut(entries, 20, 49999, false, 1), false, "a copper less and it may be the best value there too")
    entries = R.Collect({ a = offer("a", 50, 100000, 96000) }, ctx, { money = 1e9, net = true }).CHEST
    eq(R.LeftOut(entries, 20, 2000, false, 1), false, "the answer is the same for entries that were priced at their net cost")
    eq(R.LeftOut(entries, 20, 2000, true, 1), true, "either way")
    eq(R.LeftOut(entries, 20, 2000, true, 2), false, "a list with two rows may have one for it, whatever it costs: one chest alone is known to stand before it")

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
        local list = R.Build(S.offers, S.ctx, { money = GetMoney(), affordableOnly = true, net = net, limit = topOnly and R.TopCount() or nil })
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
    -- A chest that adds little, +4 for 18 silver: too small a gain to be the best value by
    -- either price. One of three chests, it has its row under "top five" all the same.
    W.AddItem({ id = 221, name = "Slight Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 14, level = 8 })
    W.AddAuction(221, 1800)
    LoadAddon()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    local tabs = LibStub("LibAHTab-1-0")
    tabs:SetSelected("UpgradeScout")
    local list, filters = frame.List, frame.FilterField
    local net, afford, top = FilterBox("Value by net cost"), FilterBox("Only what I can afford"), FilterBox("Top")
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
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top | Hide worse deals | Best armor type for the class | Upgrade at least | Gear at most | Weapons > | / | Value by net cost",
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
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5", "the two filters that are on from the start")
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
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5", "not named among the filters that are on: the white column says it")
    eq(W.AH.calls.search, searches, "nothing to look up: every price here was known")
    eq(list.Titles[4]:GetText(), "BUYOUT", "the columns are headed as they were"); eq(list.Titles[5]:GetText(), "NET COST", "both of them")
    robe = Row("Great Chest")
    eq(robe.Price:GetAmount(), 90000, "the robe's buyout, where it was"); eq(robe.Net:GetAmount(), 2000, "and its net cost")
    eq(robe.Net._font, PriceFontWhite, "the net cost in white: the picks go by it"); eq(robe.Price._font, PriceFontGray, "the buyout in grey")
    eq(robe.Pick.Text:GetText(), "Best of both", "the strongest chest is the cheapest per point too: 20 silver for +20")
    eq(Row("Good Chest").Pick:IsShown(), false, "the good chest is no pick now, at 30 silver for +8, and keeps its row: three chests are no more than five")
    check(Row("Slight Chest") ~= nil, "as the slight one does, 17 silver for +4")
    eq(Heading("CHEST").Count:GetText(), "", "three chests, three rows: nothing for the heading to count")
    eq(Row("Helm").Price:GetAmount(), 2500, "the helm's buyout"); eq(Row("Helm").Net:GetAmount(), 2500, "and all of it again")
    eq(Row("Helm").Upgrade:GetText(), "New", "the gains are what they were")

    -- A row's tooltip says as little of the prices as before: both stand in the row.
    robe:GetScript("OnEnter")(robe)
    local tip = Lines()
    eq(tip.Buyout, nil, "no line for the buyout"); eq(tip["Net cost"], nil, "nor for the net cost")
    eq(tip.Arms.right, "+200%", "the gains on every profile, which stay")
    robe:GetScript("OnLeave")(robe)

    -- A scan with the box ticked sends the searches a scan without it sends: it looks up what
    -- the list needs either way, so that the box can be ticked and unticked without one. (In
    -- a bigger world the two lists differ by a row, the best value's: see the scenario "net".)
    eq(searches, 9, "the scan by buyout: nine item searches")
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.3)
    eq(W.AH.calls.search - searches, 9, "the scan by net cost: the same nine")
    check(Offer("Slight Chest") ~= nil, "the slight chest's price is known")
    check(Row("Slight Chest") ~= nil, "and the list by net cost has its row")
    eq(Row("Great Chest").Pick.Text:GetText(), "Best of both", "over it the robe, both picks by net cost")
    Tick(net, false)
    eq(W.AH.calls.search - searches, 9, "unticked: no search")
    check(Row("Slight Chest") ~= nil, "and the slight chest is in the list by buyout")
    eq(Row("Good Chest").Pick.Text:GetText(), "Best value", "under the best value")
    Tick(net, true)
    eq(W.AH.calls.search - searches, 9, "ticked again: no search")
    eq(Row("Good Chest").Pick:IsShown(), false, "and the good chest is no pick once more")

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
    local topBox, bestBox, affordBox = FilterBox("Top"), FilterBox("Best for me"), FilterBox("Only what I can afford")
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
    eq(#window.Engines, 5, "who scores: five answers, Forever Companion's the third")
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
    eq(own._points[1].y, theirs._points[1].y, "in one row")
    check(theirs.Label:GetUnboundedStringWidth() + 17 <= theirs:GetWidth(), "its name has room on its button")
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
    -- Under the one line, the way to where another spec is chosen: a line that is no choice
    -- of the menu, and opens Forever Leveling BiS on its settings.
    eq(#dropdown.buttons, 1, "under the one line, a line that is no choice")
    eq(dropdown.buttons[1].text, ns.L.CHOOSE_LEVELING, "no main spec is chosen there yet: it says where one is chosen")
    eq(dropdown.buttons[1].after, 1, "right under the spec")
    eq(#dropdown.buttons[1].initializers, 1, "dressed as the menu's other lines")
    eq(#W.leveling.typed, 0, "Forever Leveling BiS has been asked to open nothing yet")
    dropdown.buttons[1].callback()
    eq(#W.leveling.typed, 1, "the line clicked: Forever Leveling BiS is asked for one thing"); eq(W.leveling.typed[1], "settings", "its settings")
    W.Run(0.5)
    eq(told, 1, "which is no news about the scores"); eq(S.state, "idle", "and the list stays")

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
    eq(#dropdown.radios, 2, "the field lists the addon's profiles again"); eq(#dropdown.buttons, 0, "and has no line for Forever Leveling BiS's settings")
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

    -- Its say on the hands. It has rules this addon has not (a hand that takes only one kind
    -- of weapon, a weapon judged by another weapon setup's weights), and tells what comes of
    -- them: the most an item gains. No row says more than that.
    Blade(407, "Rule Blade", 14, 8, { noMain = true })      -- its rules keep this one out of the main hand
    Blade(408, "Setup Blade", 15, 8, { gain = 3 })          -- judged by other weights: it gains 3, whatever the hand
    Blade(409, "Flat Blade", 13, 8, { gain = 0 })           -- and this one nothing at all
    local now = Score.Context(MAIN_ARMS)
    eq(type(now.hands), "function", "the comparison for the character being played has its say on the hands")
    eq(Score.Context("WARRIOR:arms", { class = "WARRIOR", level = 10, gear = {} }).hands, nil, "the one for another character has not")
    local function Sale(id)
        local item = Score.Item(W.Link(id))
        return { link = W.Link(id), itemID = id, invType = item.invType, value = Score.Value(item, MAIN_ARMS, 10),
            offValue = Score.OffValue(item, MAIN_ARMS, 10) }
    end
    gains = ns.Compare.Gains(Sale(402), now)
    eq(#gains, 2, "a blade that gains what the rows say keeps both hands"); near(gains[1].delta, 4, "at its gain")
    gains = ns.Compare.Gains(Sale(407), now)
    eq(#gains, 1, "a blade it keeps out of the main hand has one place, for all its score there (28 against 20)")
    eq(gains[1].group, "OFFHAND", "the off hand"); near(gains[1].delta, 6, "14 against 8, which is its own gain")
    gains = ns.Compare.Gains(Sale(408), now)
    eq(#gains, 2, "a blade that would gain more in either hand than it says: both places stay")
    near(gains[1].delta, 3, "at what it says the blade gains, in the main hand (not 30 against 20)")
    near(gains[2].delta, 3, "and in the off hand (not 15 against 8)")
    near(gains[1].percent, 3 / 28, "the share is of the gain that is said")
    eq(#ns.Compare.Place(Sale(408), now), 2, "an upgrade still, in both")
    eq(#ns.Compare.Gains(Sale(409), now), 0, "a blade it says gains nothing has no place, whatever the scores (26 against 20)")
    -- The answer is kept for a moment, and asked for again when it says something changed.
    local asked = #W.leveling.gains
    ns.Compare.Gains(Sale(407), now)
    eq(#W.leveling.gains, asked, "asked once for an item, not at every comparison")
    W.LevelingChanged()
    ns.Compare.Gains(Sale(407), now)
    eq(#W.leveling.gains, asked + 1, "and again after it said that something changed")
    W.Run(0.5)

    -- Another character's shield: its own block, which this addon reads from the tooltip, is
    -- no stat to Forever Leveling BiS. A bonus to the block value, which the game counts
    -- among an item's stats, is.
    W.AddItem({ id = 410, name = "Wall", equipLoc = "INVTYPE_SHIELD", subClassID = 6, value = 0, level = 6, block = 40,
        game = { ITEM_MOD_STAMINA_SHORT = 5 } })
    W.AddItem({ id = 411, name = "Bonus Wall", equipLoc = "INVTYPE_SHIELD", subClassID = 6, value = 0, level = 6, block = 40,
        game = { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_BLOCK_VALUE_SHORT = 10 } })
    near(Score.Value(Score.Item(W.Link(410)), "WARRIOR:protection", 10), 10, "a shield for another character: 5 Stamina by 2, its 40 block by nothing")
    near(Score.Value(Score.Item(W.Link(411)), "WARRIOR:protection", 10), 15, "a bonus to the block value counts: 10 by 0.5 more")

    -- Weights of a spec that is not the main one change without a word from it: they are
    -- asked for again when they are ten seconds old, and what keeps scores is told.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    near(Score.Value(Score.Item(W.Link(410)), "WARRIOR:protection", 10), 10, "before the change")
    W.SetLevelingWeights("WARRIOR", "protection", { sta = 3, armor = 0.1, block = 0.5 })
    W.Run(5)
    near(Score.Value(Score.Item(W.Link(410)), "WARRIOR:protection", 10), 10, "weights changed there for another spec: the old answer holds for a while")
    eq(told, 0, "and nothing is told")
    W.Run(6)
    near(Score.Value(Score.Item(W.Link(410)), "WARRIOR:protection", 10), 15, "ten seconds on they are asked for again: 5 Stamina by 3")
    W.Run(0.5)
    eq(told, 1, "and what keeps scores is told that they changed")

    -- The best set for a budget: an offer stands in for another only where it is as strong in
    -- either hand. Three blades at one price, gold for two: the one that is weakest in the
    -- main hand is by far the best in the off hand, and belongs in the set.
    local function Held(id, value)
        return { link = "worn" .. id, itemID = id, invType = "INVTYPE_WEAPON", value = value }
    end
    local function ForSale(id, value, offValue)
        return { id = "o" .. id, itemID = id, invType = "INVTYPE_WEAPON", value = value, offValue = offValue, buyout = 1000,
            link = "link" .. id, name = "Item " .. id, count = 1 }
    end
    local wearing = { equipped = { [16] = Held(1, 20), [17] = Held(2, 8) }, dualWield = true }
    local first, second, third = ForSale(11, 30, 15), ForSale(12, 29, 14.5), ForSale(13, 28, 27)
    local sale = { [first.id] = first, [second.id] = second, [third.id] = third }
    local _, summary = ns.Plan.Rows(ns.Plan.Choose(ns.Plan.Ladder(sale, wearing, 2000), 2000))
    near(summary.gain, 29, "the set: 30 against 20 in the main hand, 27 against 8 in the off hand")

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
    eq(#window.Engines, 5, "who scores: five answers")
    local own, pawn, companion, theirs, last = unpack(window.Engines)
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
    -- The five in one row. The longest names have no room on a fifth of it, so the buttons
    -- share the row by the length of their names, each with the same room around its name.
    check(own._points[1].x < pawn._points[1].x and pawn._points[1].x < companion._points[1].x
        and companion._points[1].x < theirs._points[1].x and theirs._points[1].x < last._points[1].x, "the five side by side")
    eq(own._points[1].y, last._points[1].y, "in one row")
    check(theirs:GetWidth() > own:GetWidth() and own:GetWidth() > pawn:GetWidth(), "a name too long for an equal share: the buttons go by their names")
    check(theirs.Label:GetUnboundedStringWidth() + 17 <= theirs:GetWidth(), "the longest name has room on its button, with the diamond of the one that is lit")
    near(pawn._points[1].x, own._points[1].x + own:GetWidth() + 11, "one after another, with the same gap")
    near(last._points[1].x + last:GetWidth(), window:GetWidth() - 20, "the row as wide as the window has room")
    -- Names that all have room on an equal share: each button is as wide as the others.
    companion.Label:SetText("Companion")
    theirs.Label:SetText("Leveling BiS")
    ns.Welcome.Show()
    near(own:GetWidth(), theirs:GetWidth(), "shorter names: each as wide as the others"); near(pawn:GetWidth(), last:GetWidth(), "all five")
    near(last._points[1].x + last:GetWidth(), window:GetWidth() - 20, "the row as wide as before")
    companion.Label:SetText("Forever Companion")
    theirs.Label:SetText("Forever Leveling BiS")
    ns.Welcome.Show()
    check(theirs:GetWidth() > own:GetWidth(), "the names as they are: by their length again")
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
    -- No main spec is chosen in Forever Leveling BiS yet: it goes by the class's first, and
    -- the line over the button says that this one is no choice.
    eq(window.Ask:GetText(), L.WELCOME_SCALE_LEVELING_UNCHOSEN:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")),
        "over it: no main spec is chosen there yet, and it goes by this one")
    eq(window.There.Label:GetText(), L.CHOOSE_LEVELING, "the button beside it says where to choose one")
    -- Chosen there, the same spec or another: the line says where it is chosen, the button
    -- where it is changed.
    W.LevelingChar().spec = "arms"
    W.LevelingChanged()
    W.Run(0.5)
    window:Hide()
    ns.Welcome.Show()
    eq(window.Ask:GetText(), L.WELCOME_SCALE_LEVELING:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")),
        "a main spec chosen there: over the button, whose main spec it is and where it is chosen")
    trees[1]:Click()
    eq(told, 1, "a click on it changes nothing"); eq(ns.Roster.Me().leveling, nil, "and writes nothing")
    theirs:Click()
    eq(told, 1, "the one that scores clicked again: nothing changes")
    -- Beside the one button, the way to where another spec is chosen: the two share the row.
    local there = window.There
    eq(there:IsShown(), true, "beside it, a button for the place where the spec is chosen")
    eq(there.Label:GetText(), L.CHANGE_LEVELING, "which says so"); eq(there.Mark:IsShown(), false, "it is no answer of several: not lit")
    eq(there._points[1].y, trees[1]._points[1].y, "in the spec's row"); near(there:GetWidth(), trees[1]:GetWidth(), "as wide as the spec's button")
    near(there._points[1].x, trees[1]._points[1].x + trees[1]:GetWidth() + 11, "right after it")
    near(there._points[1].x + there:GetWidth(), window:GetWidth() - 20, "up to the window's edge")
    check(there.Label:GetUnboundedStringWidth() + 2 <= there:GetWidth() - 40, "its words have room on it")
    eq(#W.leveling.typed, 0, "Forever Leveling BiS has been asked to open nothing yet")

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

    -- The button beside it clicked: Forever Leveling BiS opens on its settings, where the
    -- main spec is chosen, and this window, which would cover it, closes. Closed that way it
    -- has been seen with Forever Leveling BiS there, and does not come up by itself again.
    there:Click()
    eq(#W.leveling.typed, 1, "the way there clicked: Forever Leveling BiS is asked for one thing"); eq(W.leveling.typed[1], "settings", "its settings")
    eq(window:IsShown(), false, "and the window is out of its way"); eq(told, 2, "which is no news about the scores")
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
    eq(there:IsShown(), false, "and the button for Forever Leveling BiS's settings is gone")
    near(trees[2]._points[1].x + trees[2]:GetWidth(), window:GetWidth() - 20, "the trees have the whole row again")
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
    eq(#dropdown.buttons, 1, "the way to the warrior's main spec in Forever Leveling BiS"); eq(dropdown.buttons[1].after, 1, "under the warrior's line, above the druid's")
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
-- GearQuest as the one who scores (GearQuest.lua)
---------------------------------------------------------------------------
-- The warrior's three specs and the druid's four, as the tests have that addon name them,
-- each with weights under its own names for the stats. Of the warrior's, Arms has a row for
-- an item of the tests with the score their first profile gives it and Fury with the
-- second's (see W.InstallGearQuest), so the standard world reads by Arms as it does by the
-- addon itself.
local MINE_ARMS, MINE_FURY = "@WARRIOR:arms", "@WARRIOR:fury"

local function GearQuestWorld()
    W.InstallGearQuest()
    W.AddGearQuestSpecs("WARRIOR", { { id = "arms", label = "Arms" }, { id = "fury", label = "Fury" },
        { id = "protection", label = "Protection" } })
    W.AddGearQuestSpecs("DRUID", { { id = "feral", label = "Feral" }, { id = "bear", label = "Bear" },
        { id = "balance", label = "Balance" }, { id = "restoration", label = "Restoration" } })
    W.SetGearQuestWeights("WARRIOR", "arms", { weights = { str = 1.5, agi = 1, sta = 0.5, ap = 0.4, crit = 8, health = 0.05 }, dps = 2 })
    W.SetGearQuestWeights("WARRIOR", "fury", { weights = { str = 1, sta = 1 }, dps = 1 })
    W.SetGearQuestWeights("WARRIOR", "protection", { weights = { sta = 2, armor = 0.1, blockValue = 0.5, resist = 1 }, dps = 1, speed = 3 })
    W.SetGearQuestWeights("DRUID", "feral", { weights = { agi = 1, str = 1, feralAp = 0.5 }, dps = 3 })
    W.SetGearQuestWeights("DRUID", "bear", { weights = { sta = 1.5, agi = 1, armor = 0.1 } })
    W.SetGearQuestWeights("DRUID", "balance", { weights = { int = 1, sp = 1, crit = 6, mana = 0.1 }, ranged = 4 })
    W.SetGearQuestWeights("DRUID", "restoration", { weights = { heal = 1, sp_from_heal = 0.6, int = 0.5 } })
    -- (A kind of armor a spec would rather not wear counts for a share of its worth.)
    W.gearquest.kinds.DRUID = { balance = { Leather = 0.5 }, default = { Leather = 1 } }
end

-- GearQuest was asked about no item with its enchantment on.
local function CheckGearQuestAsked(label)
    for _, link in ipairs(W.gearquest.asked) do
        check(not link:match("item:%d+:%d"), label .. ": GearQuest is asked about an item without its enchantment")
    end
end

-- What GearQuest wrote into the tooltip: "rank" for its line of a score, "miss" for its
-- word that it is not scoring the item, nil for nothing.
local function GearQuestLine(tooltip)
    for _, line in ipairs(tooltip._lines) do
        if line.text:find("GearQuest: Rank", 1, true) then return "rank" end
        if line.text:find("GearQuest is not scoring", 1, true) then return "miss" end
    end
    return nil
end

-- The road of a player who has GearQuest: the addon scores by itself until it is chosen,
-- then by GearQuest's rows for the spec in use in it, and by its weights for what it has no
-- row for. A spec chosen in the addon's field is the addon's own choice: GearQuest is not
-- told of it, and nothing of it is changed.
function scenarios.gearquest_scan()
    StandardWorld()
    -- The worn chest is enchanted. On the second score: the two chests 9 (for sale) and 12
    -- (worn), a helm, a two-hander and a shield.
    W.equipped[5] = (W.Link(100):gsub("item:100:", "item:100:66", 1))
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["211:0"].value2, W.items["212:0"].value2, W.items["213:0"].value2 = 5, 40, 8
    GearQuestWorld()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score, S, me = ns.Score, ns.Scanner, ns.Roster.Me()
    local function Idle() return S.state == "idle" end

    -- It is there and not chosen: the addon scores by itself and asks it about no item.
    eq(ns.GearQuest.Usable(), true, "GearQuest is there to be asked"); eq(Score.Engine(), nil, "and is not, until chosen")
    eq(Score.Current().name, "S1", "the profiles are the addon's own")
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    ScanToEnd()
    CheckStandardOffers("the addon's own weights, with GearQuest installed")
    eq(#W.gearquest.asked, 0, "GearQuest is asked about no item"); eq(#W.gearquest.weighed, 0, "and for no weights")
    eq(#dropdown.radios, 2, "the field lists the addon's profiles"); eq(dropdown:GetText(), "Arms", "the one in use")

    -- Chosen, as the welcome window does it: for the whole account, and at once.
    local told, expected = 0, 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    local function Told(label)
        expected = expected + 1
        eq(told, expected, label)
    end
    Score.SetEngine("gearquest")
    eq(UpgradeScoutDB.engine, "gearquest", "the choice is written down for the account"); eq(Score.Engine(), "gearquest", "and GearQuest scores")
    Told("what keeps scores is told")
    local current, list = Score.Current()
    eq(#list, 3, "the character being played can go by every spec GearQuest has for its class")
    eq(current.name, MINE_ARMS, "the one in use is the one in use there: with none picked, the first of its class")
    eq(current.title, "Arms", "by GearQuest's own name for it")
    eq(list[2].name, MINE_FURY, "each by its class and its name there, marked as the character's own"); eq(list[3].title, "Protection", "the last")
    eq(Score.Title(MINE_ARMS), "Arms", "a spec's title by its profile"); eq(Score.IsApprox(MINE_ARMS), false, "no spec is marked as an estimate")
    eq(#Score.Trees(), 2, "the addon's own profiles are still there to be asked for")

    -- The list that was there is made again, by its rows.
    check(S.state ~= "idle", "a list that was made on the addon's weights is made again")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MINE_ARMS, "on the spec in use")
    CheckStandardOffers("GearQuest, on the first spec")
    near(S.ctx.equipped[5].value, 10, "what is worn is scored by its row, without its enchantment")
    near(S.ctx.equipped[16].value, 20, "every piece of it")
    eq(S.ctx.show1H, true, "a spec is offered one-handed weapons"); eq(S.ctx.show2H, true, "and two-handed ones")
    eq(#W.gearquest.stored, 1, "an item with a row at the character's level is asked about once")
    eq(W.gearquest.stored[1].itemId, 208, "a row of another level is looked for where there is none: for the chest with nothing to read")
    CheckGearQuestAsked("a scan")
    eq(#dropdown.radios, 3, "the field lists its specs"); eq(dropdown.radios[2].text, "Fury", "by its names for them")
    eq(dropdown:GetText(), "Arms", "and shows the one in use"); eq(#dropdown.buttons, 0, "with no line that leads elsewhere: a spec is chosen here")
    dropdown._tooltip(GameTooltip)
    local tip = {}
    for _, line in ipairs(GameTooltip._lines) do tip[#tip + 1] = line.text end
    check(table.concat(tip, " | "):find(ns.L.PROFILE_TIP_GEARQUEST, 1, true) ~= nil, "its tooltip says that a choice here changes nothing in GearQuest")
    -- Finding an item's rows is slow there: what it answered is remembered.
    local before = #W.gearquest.asked
    ScanToEnd()
    CheckStandardOffers("GearQuest, the list made again")
    eq(#W.gearquest.asked, before, "a list made again: it is asked about no item twice")

    -- Another spec chosen in the addon's field: the choice is the addon's own. GearQuest is
    -- not told of it and stays on its spec. The list is made again on the spec chosen, by
    -- the sum on that spec's weights (Fury: Strength and Stamina at 1, a weapon's damage per
    -- second at 1) and not by GearQuest's rows, which are for the spec in use there: by the
    -- game's count the worn chest has 6 Strength, the one for sale 10, the helm 3 Stamina
    -- and the two-hander 30 damage per second; the shield has nothing those weights count.
    W.items["100:0"].game, W.items["200:0"].game = { ITEM_MOD_STRENGTH_SHORT = 6 }, { ITEM_MOD_STRENGTH_SHORT = 10 }
    W.items["211:0"].game, W.items["212:0"].game = { ITEM_MOD_STAMINA_SHORT = 3 }, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 }
    local drawn = W.gearquest.refreshed
    dropdown:Pick(2)
    W.Run(0.5)
    eq(#W.gearquest.picked, 0, "another spec chosen in the field: GearQuest is not asked to pick it")
    eq(GearQuestForeverCharDB.specPick, nil, "nothing is written to what it saves for the character")
    eq(next(GearQuestForeverDB.settings), nil, "nor for the account")
    eq(GearQuest:GetEffectiveSpec(), "arms", "its spec in use is what it was"); eq(W.gearquest.refreshed, drawn, "and its windows are not drawn anew")
    eq(me.gearquest, "fury", "the choice is written on the character's card, by the spec's name there")
    eq(me.profile, nil, "the addon's own profile is left alone")
    eq(Score.Current().name, MINE_FURY, "the profile here is the spec chosen here")
    eq(told, expected, "nothing GearQuest answers has changed: no change of what the scores rest on is told")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MINE_FURY, "the list is made again on the spec chosen"); eq(dropdown:GetText(), "Fury", "which the field shows")
    near(S.ctx.equipped[5].value, 6, "what is worn is scored by the sum on that spec's weights, without its enchantment")
    local chest = Offer("Good Chest")
    check(chest ~= nil, "a chest by the sum, 10 against 6: by its row for that spec it would be none, 9 against 12")
    near(chest and chest.value or 0, 10, "at what its stats add up to")
    check(Offer("Helm") ~= nil, "a helm for the empty head"); check(Offer("Big Axe") ~= nil, "and a two-hander, by its damage")
    eq(Offer("Shield"), nil, "no shield: the weights count nothing of it, whatever its row for that spec says")
    eq(OfferCount(), 3, "and nothing else")
    eq(S.ctx.show1H, true, "a spec chosen here is offered one-handed weapons"); eq(S.ctx.show2H, true, "and two-handed ones")
    for _, id in ipairs({ 100, 200, 211, 212 }) do W.items[id .. ":0"].game = nil end

    -- The spec in use in GearQuest chosen here: that is no choice to remember. The addon goes
    -- by whatever is in use there, and the list is by its rows again.
    dropdown:Pick(1)
    W.Run(0.5)
    eq(me.gearquest, nil, "the spec in use there chosen here: nothing stays written on the card")
    eq(#W.gearquest.picked, 0, "nothing is picked there"); eq(told, expected, "and nothing told")
    eq(Score.Current().name, MINE_ARMS, "the profile is the spec in use there")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MINE_ARMS, "the list is made again on it")
    CheckStandardOffers("GearQuest, back on the spec in use")

    -- A spec picked in GearQuest's own window: it draws its windows anew, which is heard.
    -- With none chosen here the addon follows, by GearQuest's rows for that spec.
    GearQuestForeverCharDB.specPick = { WARRIOR = "fury" }
    W.GearQuestChanged()
    W.Run(0.5)
    Told("another spec picked there: what keeps scores is told")
    eq(Score.Current().name, MINE_FURY, "none chosen here: the profile is the spec it has in use now"); eq(me.gearquest, nil, "with nothing written down")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MINE_FURY, "the list follows"); eq(dropdown:GetText(), "Fury", "and so does the field")
    check(Offer("Helm") ~= nil, "a helm for the empty head, by its row for that spec")
    check(Offer("Shield") ~= nil, "a shield for the empty off hand")
    check(Offer("Big Axe") ~= nil, "and a two-hander")
    eq(Offer("Good Chest"), nil, "the chest is no upgrade for it: 9 against 12")
    eq(OfferCount(), 3, "and nothing else")
    dropdown:Pick(2)
    W.Run(0.5)
    eq(me.gearquest, nil, "the spec in use clicked: nothing is written"); eq(told, expected, "and nothing told")

    -- A spec chosen here stays the profile when another is picked in GearQuest; the one in
    -- use there chosen here, and the addon follows again.
    dropdown:Pick(3)
    W.Run(0.5)
    eq(me.gearquest, "protection", "a third spec chosen here")
    W.RunUntil(Idle, 600)
    GearQuestForeverCharDB.specPick.WARRIOR = "arms"
    W.GearQuestChanged()
    W.Run(0.5)
    Told("another spec picked there meanwhile: its rows are another spec's, which is told")
    eq(Score.Current().name, "@WARRIOR:protection", "the spec chosen here stays the profile"); eq(me.gearquest, "protection", "as written")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, "@WARRIOR:protection", "and the list is on it")
    dropdown:Pick(1)
    W.Run(0.5)
    eq(me.gearquest, nil, "the spec now in use there chosen here: nothing written, the addon follows again")
    eq(Score.Current().name, MINE_ARMS, "the profile is the spec it has in use now")
    W.RunUntil(Idle, 600)
    CheckStandardOffers("GearQuest, back on the first spec")
    eq(#W.gearquest.picked, 0, "through all of it nothing was picked in GearQuest")
    -- It draws them anew for other reasons too: nothing of what the scores rest on changed.
    W.GearQuestChanged()
    W.Run(0.5)
    eq(told, expected, "its windows drawn anew, with its answers as they were: nothing is told"); eq(S.state, "idle", "and the list stays")
    -- The spec's weights are other ones.
    W.SetGearQuestWeights("WARRIOR", "arms", { weights = { str = 1.5, agi = 1, sta = 2, crit = 8 }, dps = 2 })
    W.GearQuestChanged()
    W.Run(0.5)
    Told("the weights of the spec in use changed: what keeps scores is told")
    W.RunUntil(Idle, 600)
    W.SetGearQuestWeights("WARRIOR", "arms", { weights = { str = 1.5, agi = 1, sta = 3, crit = 8 }, dps = 2 })
    W.GearQuestChanged()
    W.SetGearQuestWeights("WARRIOR", "arms", { weights = { str = 1.5, agi = 1, sta = 0.5, ap = 0.4, crit = 8, health = 0.05 }, dps = 2 })
    W.GearQuestChanged()
    W.Run(0.5)
    Told("a burst of changes is one telling")
    W.RunUntil(Idle, 600)

    -- A spec found changed with nothing drawn anew: its answer is asked for again after a
    -- moment, and not each time.
    Score.Current()
    GearQuestForeverCharDB.specPick.WARRIOR = "fury"
    local asked = W.gearquest.specAsked
    for _ = 1, 20 do Score.Current() end
    eq(W.gearquest.specAsked, asked, "asked many times in a moment, the spec in use is not asked for each time")
    W.Run(3)
    eq(Score.Current().name, MINE_FURY, "an answer grown old is asked for again")
    W.Run(0.5)
    Told("and, being new, told")
    W.RunUntil(Idle, 600)
    GearQuestForeverCharDB.specPick.WARRIOR = nil
    W.GearQuestChanged()
    W.Run(0.5)
    Told("no spec picked there any more: the class's first again")
    W.RunUntil(Idle, 600)
    CheckStandardOffers("GearQuest, on the first spec again")

    -- An item it has no row for is scored here, on the spec's weights: each stat times its
    -- weight, a chance by the percent.
    local function Value(link, id) return Score.Value(Score.Item(link), id or MINE_ARMS, 10) end
    W.AddItem({ id = 240, name = "Odd Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, level = 9, unranked = true, value = 99,
        game = { ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_SPIRIT_SHORT = 7 } })
    near(Value(W.Link(240)), 4 * 1.5 + 8, "an item it has no row for: its stats on the spec's weights, 14 points of rating the 1% it weighs")
    near(Value(W.Link(240), MINE_FURY), 4, "another spec of the character's: the sum on that one's weights")
    -- One it lists at another level than the character's: the score of that row, as it takes
    -- one for a piece that is worn.
    W.AddItem({ id = 241, name = "Old Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, level = 5, elsewhere = true, value = 7,
        game = { ITEM_MOD_STRENGTH_SHORT = 1 } })
    near(Value(W.Link(241)), 7, "an item it lists at another level: the score it has there")
    local last = W.gearquest.stored[#W.gearquest.stored]
    eq(last.itemId, 241, "asked for by the item"); eq(last.slot, "Head", "and the slot of its lists")
    near(Value(W.Link(241), MINE_FURY), 1, "its rows are for the spec in use: another spec is the sum")
    near(Value(W.Link(200), "WARRIOR:arms"), 0, "and so is the same spec of another warrior of the account, of whom it knows nothing")
    -- A random enchantment has a row with the score of its best roll. The one at hand is
    -- one roll: it scores what it adds up to, and never more than the row says.
    W.AddItem({ id = 242, name = "Scout Band", equipLoc = "INVTYPE_FINGER", level = 8, unranked = true })
    W.AddItem({ id = 242, suffix = 1, name = "Scout Band of the Tiger", equipLoc = "INVTYPE_FINGER", level = 8, best = true, value = 12,
        game = { ITEM_MOD_STRENGTH_SHORT = 4 } })
    W.AddItem({ id = 242, suffix = 2, name = "Scout Band of the Bear", equipLoc = "INVTYPE_FINGER", level = 8, best = true, value = 12,
        game = { ITEM_MOD_STRENGTH_SHORT = 20 } })
    W.AddItem({ id = 242, suffix = 3, name = "Scout Band of the Whale", equipLoc = "INVTYPE_FINGER", level = 8, unranked = true,
        game = { ITEM_MOD_STRENGTH_SHORT = 2 } })
    near(Value(W.Link(242, 1)), 6, "a random enchantment, a lesser roll than the best its row is scored by: what it adds up to")
    near(Value(W.Link(242, 2)), 12, "one that adds up to more: no more than its row says")
    local stored = #W.gearquest.stored
    near(Value(W.Link(242, 3)), 3, "an enchantment it has no row for: the sum")
    eq(#W.gearquest.stored, stored, "its item's row of another level is not asked for: that may be another enchantment's")
    CheckGearQuestAsked("items of every kind")

    -- Its say on weapons, for the spec in use: one of its specs holds a two-hander and
    -- nothing else, one never a two-hander, one daggers alone.
    W.gearquest.twoOnly = true
    local ctx = Score.Context(MINE_ARMS)
    eq(ctx.show1H, false, "a spec of two-handers alone: no one-handed weapon is offered"); eq(ctx.show2H, true, "two-handed ones are")
    eq(Score.Context(MINE_FURY).show1H, true, "a spec that is not the one in use is offered every weapon")
    W.gearquest.twoOnly, W.gearquest.noTwo = false, true
    ctx = Score.Context(MINE_ARMS)
    eq(ctx.show1H, true, "a spec of a weapon and a shield: one-handed weapons"); eq(ctx.show2H, false, "and no two-handed ones")
    W.gearquest.noTwo, W.gearquest.daggers = false, true
    W.AddItem({ id = 243, name = "Keen Dagger", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 15, value = 30, level = 9 })
    eq(Score.ClassCanUse(Score.Item(W.Link(243)), nil), true, "a spec of daggers alone: a dagger is for it")
    eq(Score.ClassCanUse(Score.Item(W.Link(212)), nil), false, "an axe is not"); eq(Score.ClassCanUse(Score.Item(W.Link(213)), nil), true, "a shield is no weapon")
    -- (Its say is about the spec in use there: with another chosen here it has none.)
    Score.Choose(me, MINE_FURY)
    eq(Score.ClassCanUse(Score.Item(W.Link(212)), nil), true, "another spec chosen here: the axe is for it")
    Score.Choose(me, MINE_ARMS)
    eq(me.gearquest, nil, "the spec in use chosen again"); eq(Score.ClassCanUse(Score.Item(W.Link(212)), nil), false, "its say is back")
    eq(Score.ClassCanUse(Score.Item(W.Link(212)), { class = "WARRIOR", level = 10, key = "P", name = "P" }), true,
        "of another character it has no say")
    W.gearquest.daggers = false

    -- /upscout stats: the stats as the game counts them on the spec's weights, by GearQuest's
    -- words for them, and its own score for the item, which counts more than those.
    local good = W.items["200:0"]
    good.game = { ITEM_MOD_STRENGTH_SHORT = 4 }
    local at = #W.printed + 1
    SlashCmdList.UPGRADESCOUT("stats " .. W.Link(200))
    local said = Said(at)
    check(said:find('on the profile "Arms": score 18', 1, true) ~= nil, "the spec in use and GearQuest's own score for the item: " .. said)
    check(said:find("Strength: 4 × 1.5 = 6", 1, true) ~= nil, "a stat by its word for it, with the spec's weight")
    check(said:find("TEST_S1", 1, true) == nil, "a stat it has no weight for is left out")
    good.game = nil

    -- A spec of the player's own making there: listed after the ones that come with it, by
    -- the name the player gave it, with the weights of the spec it was made from and what
    -- was changed. A weight changed later is found out when the answer has grown old.
    GearQuestForeverDB.customSpecs = { WARRIOR = { { id = "c:1", name = "My Tank", base = "protection", overrides = { sta = 3 } } } }
    list = select(2, Score.Current())
    eq(#list, 4, "a spec the player made there is listed"); eq(list[4].name, "@WARRIOR:c:1", "by its own name there")
    eq(list[4].title, "My Tank", "and shown by the name the player gave it")
    W.AddItem({ id = 244, name = "Stout Belt", equipLoc = "INVTYPE_WAIST", subClassID = 3, level = 9, unranked = true,
        game = { ITEM_MOD_STAMINA_SHORT = 5, RESISTANCE2_NAME = 4, RESISTANCE5_NAME = 6 } })
    near(Value(W.Link(244), "@WARRIOR:protection"), 5 * 2 + 6, "the spec it was made from; of an item's resistances the greatest counts")
    near(Value(W.Link(244), "@WARRIOR:c:1"), 5 * 3 + 6, "the player's own: the same, with what was changed")
    GearQuestForeverDB.customSpecs.WARRIOR[1].overrides.sta = 4
    W.Run(11)
    near(Value(W.Link(244), "@WARRIOR:c:1"), 5 * 4 + 6, "a weight changed there with no word: an answer grown old is asked for again")
    W.Run(0.5)
    Told("and, found changed, told")
    W.RunUntil(Idle, 600)
    -- That spec chosen here, and then deleted there: a choice of a spec that is no more is
    -- none, and the addon goes by the spec in use there.
    dropdown:Pick(4)
    W.Run(0.5)
    eq(me.gearquest, "c:1", "the player's own spec chosen here"); eq(Score.Current().name, "@WARRIOR:c:1", "is the profile")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, "@WARRIOR:c:1", "and the list is on it")
    GearQuestForeverDB.customSpecs.WARRIOR = {}
    W.GearQuestChanged()
    W.Run(0.5)
    Told("the spec deleted there: what keeps scores is told")
    eq(#select(2, Score.Current()), 3, "it is listed no more"); eq(Score.Current().name, MINE_ARMS, "and the profile is the spec in use there")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MINE_ARMS, "the list is made again on that"); eq(dropdown:GetText(), "Arms", "which the field shows")
    eq(#W.gearquest.picked, 0, "nothing was picked there")
    me.gearquest = nil

    -- It has no spec for the class: none in use, no scan, and the reason.
    local specs = W.gearquest.specs.WARRIOR
    W.gearquest.specs.WARRIOR = nil
    W.GearQuestChanged()
    W.Run(0.5)
    Told("its specs gone: what keeps scores is told")
    eq(Score.Current(), nil, "no spec to be had: none in use")
    eq(S.Start(), false, "and no scan"); eq(S.message, ns.L.ERR_NO_SCALE_GEARQUEST, "which says why")
    W.gearquest.specs.WARRIOR = specs
    W.GearQuestChanged()
    W.Run(0.5)
    Told("its specs back")
    W.RunUntil(Idle, 600)
    eq(Score.Current().name, MINE_ARMS, "the spec in use back")
    ScanToEnd()
    CheckStandardOffers("GearQuest, with its specs back")

    -- GearQuest can show another character's lists (its "simulation"). All it says is then
    -- about that one: it cannot be asked, and the addon scores by itself meanwhile.
    GearQuestForeverDB.settings.preview = { enabled = true }
    W.GearQuestChanged()
    W.Run(0.5)
    Told("its simulation switched on: who scores is another, and what keeps scores is told")
    eq(ns.GearQuest.Usable(), false, "it cannot be asked while it simulates another character"); eq(Score.Engine(), nil, "the addon scores")
    eq(Score.Current().name, "S1", "on its own profiles"); eq(UpgradeScoutDB.engine, "gearquest", "and the choice stands")
    W.RunUntil(Idle, 600)
    CheckStandardOffers("GearQuest simulating: the addon's own weights")
    -- Switched off again with nothing drawn anew: found out after a moment.
    GearQuestForeverDB.settings.preview.enabled = false
    W.Run(3)
    eq(Score.Engine(), "gearquest", "its simulation switched off: it scores again")
    W.Run(0.5)
    Told("which is told")
    W.RunUntil(Idle, 600)
    eq(S.ctx.profile, MINE_ARMS, "the list is by its spec again")
    CheckStandardOffers("GearQuest, after its simulation")

    -- A level gained: its lists are another level's.
    W.player.level = 11
    W.Fire("PLAYER_LEVEL_UP", 11)
    W.Run(2.5)
    Told("a level gained: what keeps scores is told")
    W.RunUntil(Idle, 600)

    -- Back to the addon's own weights: its profile is where it was left.
    Score.SetEngine(nil)
    Told("the addon's own weights chosen again")
    eq(UpgradeScoutDB.engine, nil, "nothing is left written"); eq(Score.Current().name, "S1", "the addon's profile as it was")
    W.RunUntil(Idle, 600)
    eq(#dropdown.radios, 2, "the field lists the addon's profiles again")
    before = #W.gearquest.asked
    ScanToEnd()
    eq(#W.gearquest.asked, before, "and GearQuest is asked about no item")

    -- Another character of the account can be scored on any spec of its class: the one
    -- chosen for it in the addon's field, then the one for its talents, then the one
    -- GearQuest starts the class on.
    Score.SetEngine("gearquest")
    local function Other(card)
        card.key, card.name, card.realm = card.key or "P", card.name or "P", card.realm or "Testrealm"
        return card
    end
    local picked, all = Score.Current(Other({ class = "DRUID", talents = "DRUID_FERAL_BEAR" }))
    eq(#all, 4, "another character: every spec GearQuest has for its class")
    eq(all[1].name, "DRUID:feral", "each by its class and its name there, without the mark"); eq(all[2].title, "Bear", "and GearQuest's name for it")
    eq(picked.name, "DRUID:bear", "the one in use: the spec for the tree its talents are in")
    eq(Score.Current(Other({ class = "DRUID", talents = "DRUID_FERAL_CAT" })).name, "DRUID:feral", "a druid's other shape")
    eq(Score.Current(Other({ class = "DRUID", talents = "DRUID_RESTORATION" })).name, "DRUID:restoration", "a tree by its name")
    eq(Score.Current(Other({ class = "DRUID" })).name, "DRUID:feral", "with nothing to go by: the one it starts the class on")
    eq(Score.Current(Other({ class = "DRUID", talents = "DRUID_BALANCE", gearquest = "restoration" })).name, "DRUID:restoration",
        "under the spec chosen for it in the addon's field")
    eq(Score.Current(Other({ class = "DRUID", talents = "DRUID_BALANCE", gearquest = "gone" })).name, "DRUID:balance",
        "a choice that is no spec any more gives way to the talents")
    eq(Score.Current(Other({ class = "WARRIOR", talents = "S2" })).name, "WARRIOR:arms", "talents that name no spec of its: the first")
    eq(Score.Current(Other({ class = "MAGE" })), nil, "a class it has no specs for: none")
    eq(Score.Title("DRUID:bear"), "Bear", "a profile's title"); eq(Score.Title("no such thing"), "no such thing", "what is no profile is its own title")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- GearQuest chosen and not there, there and not ready, in a version without what is asked of
-- it, and without what is asked only where it is there.
function scenarios.gearquest_absent()
    StandardWorld()
    UpgradeScoutDB = { engine = "gearquest" }
    LoadAddon()
    local Score = ns.Score
    eq(ns.GearQuest.Usable(), false, "GearQuest is not installed"); eq(Score.Engine(), nil, "so the addon scores, though it was chosen")
    eq(Score.Current().name, "S1", "on its own profiles")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("GearQuest chosen and not installed")
    eq(UpgradeScoutDB.engine, "gearquest", "the choice stands for when it is back")

    -- It is there but has not made its lists yet, as in the moments of logging in.
    GearQuestWorld()
    GearQuest.Data.byItemId = nil
    eq(ns.GearQuest.Usable(), false, "before its lists are made it cannot be asked"); eq(Score.Engine(), nil, "and is not")
    eq(Score.Current().name, "S1", "the addon's profiles meanwhile")
    -- A version without a function the addon calls, or without a part of it, is one that
    -- cannot be asked.
    GearQuest.Data.byItemId = {}
    local weights, spec = GearQuest.Custom.Weights, GearQuest.Spec
    GearQuest.Custom.Weights = nil
    eq(ns.GearQuest.Usable(), false, "one that lacks a function the addon calls"); eq(Score.Engine(), nil, "leaves the scoring to the addon")
    GearQuest.Custom.Weights, GearQuest.Spec = weights, nil
    eq(ns.GearQuest.Usable(), false, "one that lacks a part of it"); eq(Score.Engine(), nil, "does too")
    GearQuest.Spec = spec
    eq(Score.Engine(), "gearquest", "with everything in place it scores, as chosen")
    eq(Score.Current().name, MINE_ARMS, "on the spec in use in it")
    local asked = W.gearquest.specAsked
    for _ = 1, 50 do Score.Engine() end
    eq(W.gearquest.specAsked, asked, "whom it scores for is not found out anew each time")

    -- What it is asked only where it is there can be missing.
    local data = GearQuest.Data
    data.EquippedPipelineScore, data.UsesTwoHandOnlyWeapons, data.UsesOneHandAndShield, data.AssassinationDaggerOnly = nil, nil, nil, nil
    GearQuest.Spec.GetDefaultSpec, GearQuest.Custom.SpecIsIndexed = nil, nil
    GearQuest.ScoringWeightLabels, GearQuest.L, GearQuest.StatWeightsArmorClass, GearQuest.RefreshUI = nil, nil, nil, nil
    eq(ns.GearQuest.Usable(), true, "without those it still scores")
    W.AddItem({ id = 241, name = "Old Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, level = 5, elsewhere = true, value = 7,
        game = { ITEM_MOD_STRENGTH_SHORT = 2 } })
    near(Score.Value(Score.Item(W.Link(241)), MINE_ARMS, 10), 3, "an item it lists at another level, with no way to ask for that row: the sum")
    eq(Score.ClassCanUse(Score.Item(W.Link(212)), nil), true, "no weapon is refused for it")
    local ctx = Score.Context(MINE_ARMS)
    eq(ctx.show1H, true, "a spec is offered every weapon"); eq(ctx.show2H, true, "of either kind")
    W.items["200:0"].game = { ITEM_MOD_STRENGTH_SHORT = 4 }
    local parts, total = Score.Parts(Score.Item(W.Link(200)), MINE_ARMS, 10)
    eq(#parts, 1, "a sum without its words for the stats is no error"); eq(parts[1].label, "str", "a stat then goes by its name there")
    near(total, 18, "and the total is its row's as ever")
    W.items["200:0"].game = nil
    -- A spec chosen in the field asks nothing of it: the choice is kept here.
    Score.Choose(ns.Roster.Me(), MINE_FURY)
    W.Run(0.5)
    eq(Score.Current().name, MINE_FURY, "a spec chosen in the field is the profile here"); eq(#W.gearquest.picked, 0, "and nothing is picked there")
    eq(GearQuest:GetEffectiveSpec(), "arms", "its spec in use is what it was")
    Score.Choose(ns.Roster.Me(), MINE_ARMS)
    eq(ns.Roster.Me().gearquest, nil, "the one in use there chosen again: nothing is kept")
    eq(Score.Current({ class = "DRUID", key = "P", name = "P", realm = "Testrealm" }).name, "DRUID:feral",
        "another character with nothing to go by: the first of its class")
    -- With nothing drawn anew to listen for, a spec picked there is found out by asking.
    GearQuestForeverCharDB.specPick = { WARRIOR = "fury" }
    W.Run(3)
    eq(Score.Current().name, MINE_FURY, "a spec picked there: found out after a moment")
    GearQuestForeverCharDB.specPick = nil

    -- Switched off for the next session: the addon's weights again, without a word.
    Relog(W.player, W.equipped)
    W.RemoveGearQuest()
    eq(ns.Score.Engine(), nil, "GearQuest switched off: the addon scores")
    W.OpenAuctionHouse()
    ScanToEnd()
    CheckStandardOffers("GearQuest switched off")
    eq(UpgradeScoutDB.engine, "gearquest", "and the choice still stands")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- With GearQuest scoring: under an item it has a row for it writes its own line, and none of
-- ours stand beside it; under any other the lines are ours, on its weights. The arrows in
-- the bags are ours whatever the item: it draws none there.
function scenarios.gearquest_tooltips()
    StandardWorld()
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["212:0"].value2 = 40
    -- A chest GearQuest has no row for: 10 Strength, which Arms weighs at 15 against the
    -- worn chest's 10.
    W.AddItem({ id = 245, name = "Odd Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, level = 8, unranked = true,
        game = { ITEM_MOD_STRENGTH_SHORT = 10 } })
    W.AddAuction(245, 3000)
    -- A shirt and a trinket that is only used, as most characters wear.
    W.AddItem({ id = 230, name = "Lucky Charm", equipLoc = "INVTYPE_TRINKET", value = 0, level = 1, noStats = true })
    W.equipped[4] = W.Link(207)
    W.equipped[13] = W.Link(230)
    GearQuestWorld()
    -- It was chosen in an earlier session.
    UpgradeScoutDB = { engine = "gearquest" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score = ns.Score
    local settings = GearQuestForeverDB.settings
    eq(ns.GearQuest.Item(W.Link(207)).gearquest, false, "a shirt is not gear: there is nothing to read, and that is an answer")
    eq(Score.Context(MINE_ARMS).unread, nil, "wearing one, the gear is whole")
    eq(Score.Engine(), "gearquest", "GearQuest scores, as chosen before"); eq(Score.Current().name, MINE_ARMS, "on the spec in use in it")

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
    local function Has(text, part) return text ~= nil and text:find(part, 1, true) ~= nil end
    eq(Shown(GameTooltip, 200), nil, "an item GearQuest has a row for: no lines of ours, it writes its own")
    eq(GearQuestLine(GameTooltip), "rank", "which is there")
    local ours = Shown(GameTooltip, 245)
    check(Has(ours, "Arms +50%"), "an item it has no row for: our lines, on its weights: " .. tostring(ours))
    check(Has(ours, "Fury +10 pts"), "a line for every spec it has for the class")
    eq(GearQuestLine(GameTooltip), "miss", "beside its own word that it is not scoring the item")
    local heading
    for _, line in ipairs(GameTooltip._lines) do
        if line.text:find("Upgrade Scout", 1, true) then heading = line.text end
    end
    check(heading:find("Upgrade Scout (scored like GearQuest)", 1, true) ~= nil, "under a heading that says whose weights they are: " .. heading)
    eq(Shown(ItemRefTooltip, 200), nil, "the same for a link in the chat: none of ours where it has a row")
    check(Has(Shown(ItemRefTooltip, 245), "Arms +50%"), "and ours where it has none")
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    Shown(GameTooltip, 245)
    local single
    for _, line in ipairs(GameTooltip._lines) do
        if line.text:find("(scored like GearQuest)", 1, true) then single = line end
    end
    check(single ~= nil and single.text:find("Arms (scored like GearQuest)", 1, true) ~= nil, "\"Only my spec\": one line, with whose weights they are")
    eq(single.right, "+50%", "and the gain")
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")
    UpgradeScoutDB.tooltip = false
    ns.Fire("SETTING_CHANGED", "tooltip")
    eq(Shown(GameTooltip, 245), nil, "they go by their box in the welcome window, as with the addon scoring")
    UpgradeScoutDB.tooltip = nil
    ns.Fire("SETTING_CHANGED", "tooltip")
    -- Its line switched off in its settings. It tells nobody of that: it is found out the
    -- next time a tooltip is up. Then our lines stand under every item, by its score.
    settings.showGearScore = false
    check(Has(Shown(GameTooltip, 200), "Arms +80%"), "its line switched off: ours under an item it has a row for, by that row")
    eq(GearQuestLine(GameTooltip), nil, "with nothing of its own")
    settings.showGearScore = nil
    eq(Shown(GameTooltip, 200), nil, "switched on again: its line, and none of ours")
    eq(GearQuestLine(GameTooltip), "rank", "its own is back")
    W.Run(0.5)

    -- The arrows in the bags are ours: GearQuest draws none there. By its row where it has
    -- one, by its weights where it has none.
    local function Arrow(button)
        local arrow = button.UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local function Bag(slot) return Arrow(ContainerFrameCombinedBags.Items[slot]) end
    local function Grey(slot) return ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow._grey end
    local slot = {}
    for _, id in ipairs({ 200, 202, 203, 204, 208, 212, 214, 245 }) do slot[id] = W.PutInBags(W.Link(id)) end
    W.OpenBags()
    W.Run(1)
    eq(Bag(slot[200]), true, "a better chest: an arrow of ours, 18 against 10 by its rows"); eq(Grey(slot[200]), false, "green: it can be put on now")
    eq(Bag(slot[245]), true, "a chest it has no row for: an arrow by its weights, 15 against 10")
    eq(Bag(slot[203]), true, "a better chest of a higher level"); eq(Grey(slot[203]), true, "grey")
    eq(Bag(slot[212]), true, "a two-hander against the sword")
    eq(Bag(slot[202]), false, "not a weaker chest"); eq(Bag(slot[204]), false, "not mail the character has not learned")
    eq(Bag(slot[208]), false, "not a chest with nothing to read"); eq(Bag(slot[214]), false, "not a potion")
    -- Another spec picked in GearQuest: the arrows follow.
    GearQuestForeverCharDB.specPick = { WARRIOR = "fury" }
    W.GearQuestChanged()
    W.Run(1)
    eq(Bag(slot[200]), false, "for the other spec the chest is no upgrade: 9 against 12")
    eq(Bag(slot[212]), true, "and the two-hander is one: 40 against nothing")
    GearQuestForeverCharDB.specPick = nil
    W.GearQuestChanged()
    W.Run(1)
    eq(Bag(slot[200]), true, "back on the first spec the chest has its arrow")

    -- Another spec chosen in the addon's field (as the welcome window does it, with the tab
    -- not open): the choice is the addon's own, and GearQuest stays on its spec. Its line in
    -- a tooltip is about that spec, so ours stand under every item, one it has a row for
    -- too, and say what the item is on the spec chosen here; the arrows go by that spec.
    -- The leather chest has 3 Strength by the game's count: to Arms it is what its row says,
    -- 9 against the worn chest's 10, and to Fury the sum on its weights, 3 against a worn
    -- chest that adds up to nothing.
    W.items["202:0"].game = { ITEM_MOD_STRENGTH_SHORT = 3 }
    ns.UI.ChooseProfile(MINE_FURY)
    W.Run(1)
    eq(Score.Current().name, MINE_FURY, "another spec chosen here: it is the profile"); eq(ns.Roster.Me().gearquest, "fury", "written on the character's card")
    eq(#W.gearquest.picked, 0, "nothing is picked in GearQuest"); eq(GearQuest:GetEffectiveSpec(), "arms", "whose spec in use is what it was")
    eq(Score.Writes(W.Link(202)), false, "its line is not about the profile here: the score is ours to write, for an item it has a row for too")
    ours = Shown(GameTooltip, 202)
    check(Has(ours, "Fury +3 pts"), "an item it has a row for: our lines stand, with the spec chosen here by its weights: " .. tostring(ours))
    check(Has(ours, "Arms -10%"), "and a line for every spec as ever, the one in use there by its row")
    eq(GearQuestLine(GameTooltip), "rank", "GearQuest's own line stands as before, about its own spec")
    check(Has(Shown(GameTooltip, 245), "Fury +10 pts"), "an item it has no row for: our lines as before")
    check(Has(Shown(ItemRefTooltip, 202), "Fury +3 pts"), "the same for a link in the chat")
    UpgradeScoutDB.ownTree = true
    ns.Fire("SETTING_CHANGED", "ownTree")
    Shown(GameTooltip, 202)
    single = nil
    local arms = false
    for _, line in ipairs(GameTooltip._lines) do
        if line.text:find("(scored like GearQuest)", 1, true) then single = line end
        if line.text:find("Arms", 1, true) then arms = true end
    end
    check(single ~= nil and single.text:find("Fury (scored like GearQuest)", 1, true) ~= nil, "\"Only my spec\": the one line is the spec chosen here, with whose weights they are")
    eq(single and single.right, "+3 pts", "and the gain on it"); eq(arms, false, "the spec in use there has no line of ours")
    UpgradeScoutDB.ownTree = nil
    ns.Fire("SETTING_CHANGED", "ownTree")
    UpgradeScoutDB.tooltip = false
    ns.Fire("SETTING_CHANGED", "tooltip")
    eq(Shown(GameTooltip, 202), nil, "they go by their box in the welcome window as ever"); eq(GearQuestLine(GameTooltip), "rank", "which is nothing to GearQuest's own line")
    UpgradeScoutDB.tooltip = nil
    ns.Fire("SETTING_CHANGED", "tooltip")
    eq(Bag(slot[202]), true, "the arrows go by the spec chosen here: the leather chest is an upgrade on it")
    eq(Bag(slot[200]), false, "and the chest that is one on the spec in use there is none: nothing of it counts")
    -- The spec chosen here picked in GearQuest as well: its line is about the profile here
    -- again, and ours give way to it. Another picked there, and they stand again.
    GearQuestForeverCharDB.specPick = { WARRIOR = "fury" }
    W.GearQuestChanged()
    W.Run(1)
    eq(Shown(GameTooltip, 200), nil, "the same spec in use there: its own line, and none of ours"); eq(GearQuestLine(GameTooltip), "rank", "which is there")
    GearQuestForeverCharDB.specPick = nil
    W.GearQuestChanged()
    W.Run(1)
    eq(Score.Current().name, MINE_FURY, "another picked there: the spec chosen here stays the profile")
    check(Has(Shown(GameTooltip, 202), "Fury +3 pts"), "and our lines stand again")
    -- The spec in use there chosen here: the addon follows it again, as before.
    ns.UI.ChooseProfile(MINE_ARMS)
    W.Run(1)
    eq(ns.Roster.Me().gearquest, nil, "the spec in use there chosen here: nothing is kept")
    eq(Shown(GameTooltip, 202), nil, "its line, and none of ours"); eq(GearQuestLine(GameTooltip), "rank", "its own is there")
    eq(Bag(slot[200]), true, "the arrows are by its rows again"); eq(Bag(slot[202]), false, "for the one as for the other")
    eq(#W.gearquest.picked, 0, "through all of it nothing was picked in GearQuest")

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
        local lines, theirs = Ours(GameTooltip), GearQuestLine(GameTooltip)
        row:GetScript("OnLeave")(row)
        return lines, theirs
    end
    near(Offer("Odd Chest").value, 15, "an item it has no row for is in the list, by its weights")
    local theirs
    ours, theirs = Under("Good Chest")
    eq(ours, nil, "a row of an item it has a row for, with nothing to add: no lines of ours, not even the addon's name")
    eq(theirs, "rank", "GearQuest's line stands there, as anywhere"); eq(W.compared, GameTooltip, "and the worn item beside it as ever")
    ours, theirs = Under("Odd Chest")
    check(Has(ours, "Arms +50%"), "a row of an item it has none for: the gains are ours to write: " .. tostring(ours))
    eq(theirs, "miss", "under its word that it is not scoring the item")
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Under("Odd Chest"), nil, "and they go by their box")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    eq(Under("Great Chest"), "Has effects the score does not count | You are 4g short",
        "a row with something to say about buying: that, under the addon's name, and no gains")
    -- The list on another spec than the one in use there: under a row of an item GearQuest
    -- has a row for our gains stand too, by their box, beside its own line.
    local dropdown = UpgradeScoutFrame.ProfileDropdown
    dropdown:Pick(2)
    W.Run(0.5)
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 600)
    W.Run(1)
    eq(ns.Scanner.ctx.profile, MINE_FURY, "another spec chosen in the field: the list is on it")
    ours, theirs = Under("Weak Chest")
    check(Has(ours, "Fury +3 pts"), "a row of an item it has a row for: the gains are ours to write: " .. tostring(ours))
    eq(theirs, "rank", "beside its own line, which is about its own spec")
    UpgradeScoutDB.rowTooltip = false
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    ours, theirs = Under("Weak Chest")
    eq(ours, nil, "and they go by their box"); eq(theirs, "rank", "its own stays")
    UpgradeScoutDB.rowTooltip = nil
    ns.Fire("SETTING_CHANGED", "rowTooltip")
    W.items["202:0"].game = nil
    dropdown:Pick(1)
    W.Run(0.5)
    W.RunUntil(function() return ns.Scanner.state == "idle" end, 600)
    W.Run(1)
    eq(ns.Roster.Me().gearquest, nil, "the spec in use there chosen in the field: the addon follows it again")
    eq(Under("Good Chest"), nil, "and under a row of an item it has a row for there are no lines of ours")
    eq(#W.gearquest.picked, 0, "nothing was picked in GearQuest")
    CheckGearQuestAsked("tooltips and arrows")

    -- The addon's own weights chosen again: its lines are back under every item, and
    -- GearQuest's own after them.
    Score.SetEngine(nil)
    W.Run(1)
    eq(Shown(GameTooltip, 200), "Arms +80% | Protection ~ -25% | GearQuest: Rank #1 for your level",
        "the addon scores again: its lines in the tooltip, and GearQuest's own after them")
    eq(Bag(slot[200]), true, "and its arrows, by its own profile")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- The welcome window with GearQuest: the fifth answer to who scores, its specs in place of
-- the trees, the tooltip's block in use with a sentence on whose lines are whose, and the
-- window coming up once for a player who has it.
function scenarios.gearquest_welcome()
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
    eq(#window.Engines, 5, "who scores: five answers")
    local own, theirs = window.Engines[1], window.Engines[5]
    eq(theirs.Label:GetText(), "GearQuest", "the fifth is GearQuest, by the name it goes by in the game")
    eq(own.Mark:IsShown(), true, "the addon is the one that does"); eq(theirs.Mark:IsShown(), false, "GearQuest is not")
    eq(theirs:GetAlpha(), 0.45, "it cannot be chosen while it is not there: its button is grey")
    local function Hint(button)
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        button:GetScript("OnEnter")(button)
        local said = GameTooltip._lines[1] and GameTooltip._lines[1].text or nil
        button:GetScript("OnLeave")(button)
        return said
    end
    eq(Hint(theirs), L.WELCOME_NO_GEARQUEST, "the mouse on its grey button: a tooltip says why")
    theirs:Click()
    eq(UpgradeScoutDB.engine, nil, "a click on the grey button does nothing")
    check(theirs._points[1].x + theirs:GetWidth() <= window:GetWidth() - 20 + 0.01, "the five inside the window")
    check(theirs.Label:GetUnboundedStringWidth() + 17 <= theirs:GetWidth(), "its name has room on its button")
    local height = window:GetHeight()
    window.Done:Click()
    eq(UpgradeScoutDB.welcomed, true, "seen"); eq(UpgradeScoutDB.gearquestOffered, nil, "but not with GearQuest there to choose")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "without it the window does not come up by itself again")

    -- The player installs GearQuest. The window comes up once more, and says why.
    GearQuestWorld()
    Relog(W.player, W.equipped)
    W.Fire("PLAYER_ENTERING_WORLD")
    W.RunUntil(function() return UpgradeScoutWelcome:IsShown() end, 10)
    L = ns.L
    window = UpgradeScoutWelcome
    eq(window.About:GetText(), L.WELCOME_GEARQUEST_NEW, "it is there now: the window comes up to say that it can be chosen")
    own, theirs = window.Engines[1], window.Engines[5]
    eq(theirs:GetAlpha(), 1, "its button is no longer grey"); eq(theirs.Glow.parts[1]:IsShown(), true, "and lights up under the mouse")
    eq(Hint(theirs), nil, "with nothing left to explain in a tooltip")
    eq(window.Engines[2]:GetAlpha(), 0.45, "Pawn's is still grey: Pawn is not there")
    eq(own.Mark:IsShown(), true, "the addon scores until another is chosen")
    eq(window:GetHeight(), height, "the window is as tall as without it")

    -- Chosen.
    local told = 0
    ns.Listen("SCORING_CHANGED", function() told = told + 1 end)
    theirs:Click()
    eq(UpgradeScoutDB.engine, "gearquest", "a click chooses GearQuest, for the account"); eq(told, 1, "and what keeps scores is told")
    eq(theirs.Mark:IsShown(), true, "its button is lit"); eq(own.Mark:IsShown(), false, "the addon's goes dark")
    local trees = window.Trees
    eq(trees[1].Label:GetText(), "Arms", "its specs in place of the trees"); eq(trees[2].Label:GetText(), "Fury", "by its names for them")
    eq(trees[3]:IsShown(), true, "every one it has for the class"); check(trees[4] == nil or not trees[4]:IsShown(), "and no more")
    eq(trees[1].Mark:IsShown(), true, "the one in use in it is lit"); eq(trees[2].Mark:IsShown(), false, "the others are not")
    eq(window.Ask:GetText(), L.WELCOME_SCALE_GEARQUEST:format(ns.Roster.Colored(ns.Roster.Me(), "Tester")), "over them: which of them the character goes by")
    eq(window.There:IsShown(), false, "no button that leads elsewhere: a spec is chosen here")
    -- A click on another: the choice is the addon's own, and GearQuest stays as it is. Its
    -- line in a tooltip is about its own spec then, the lines under every item are ours,
    -- and the tooltip's block says what it always says.
    trees[2]:Click()
    W.Run(0.5)
    eq(#W.gearquest.picked, 0, "a click on another: nothing is picked in GearQuest"); eq(GearQuest:GetEffectiveSpec(), "arms", "whose spec in use is what it was")
    eq(ns.Score.Current().name, MINE_FURY, "it is the profile here")
    eq(trees[2].Mark:IsShown(), true, "lit"); eq(trees[1].Mark:IsShown(), false, "the first no more")
    eq(ns.Roster.Me().gearquest, "fury", "and written on the character's card")
    eq(told, 1, "nothing GearQuest answers has changed: no change of what the scores rest on is told")
    eq(window.Tips.Body:GetText(), L.WELCOME_TOOLTIP_TEXT, "the tooltip's block, with another spec here than there: its own sentence")
    -- A click on the one in use there: nothing is kept, and the addon follows GearQuest.
    trees[1]:Click()
    W.Run(0.5)
    eq(ns.Roster.Me().gearquest, nil, "a click on the one in use in it: nothing stays written"); eq(ns.Score.Current().name, MINE_ARMS, "the profile is that one")
    eq(trees[1].Mark:IsShown(), true, "lit again"); eq(#W.gearquest.picked, 0, "and still nothing picked there")
    theirs:Click()
    W.Run(0.5)
    eq(told, 1, "the one that scores clicked again: nothing changes")

    -- The tooltip's block is in use as ever: GearQuest writes its own line for the items it
    -- has a row for and leaves the rest to us, and the block's sentence says so. The arrows
    -- in the bags are ours.
    local block, arrows = window.Tips, window.Pair[2]
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_GEARQUEST, "the tooltip's block says whose lines are whose")
    for name, box in pairs({ ["the addon's tabs"] = block.Tabs, ["the rest of the game"] = block.Elsewhere }) do
        eq(box:IsEnabled(), true, "the score's box for " .. name .. " is in use"); eq(box:GetChecked(), true, "and ticked: " .. name)
    end
    eq(block.All:IsEnabled(), true, "the two buttons are in use"); eq(block.Notes:IsEnabled(), true, "and the box of the notes")
    eq(arrows.Switch:IsEnabled(), true, "the arrows' box is in use"); eq(arrows.Body:GetText(), L.WELCOME_ARROWS_TEXT, "with its sentence as ever")
    -- Its line switched off in its settings: the lines are all ours, and the block says
    -- what it always says.
    GearQuestForeverDB.settings.showGearScore = false
    window:Hide()
    ns.Welcome.Show()
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_TEXT, "its line switched off: the block's own sentence")
    GearQuestForeverDB.settings.showGearScore = nil
    window:Hide()
    ns.Welcome.Show()
    eq(block.Body:GetText(), L.WELCOME_TOOLTIP_GEARQUEST, "switched on again: whose lines are whose")
    window.Done:Click()
    eq(UpgradeScoutDB.gearquestOffered, true, "the choice has been seen with GearQuest there")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(12)
    eq(window:IsShown(), false, "and the window does not come up for it again")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- What a consumable adds, scored on a spec's weights as GearQuest names the stats.
function scenarios.gearquest_supplies()
    StandardWorld()
    SuppliesWorld()
    GearQuestWorld()
    UpgradeScoutDB = { engine = "gearquest" }
    LoadAddon()
    SupplyFacts()
    local Score = ns.Score
    eq(Score.Engine(), "gearquest", "GearQuest scores")
    local CASTS, HEALS = "DRUID:balance", "DRUID:restoration"
    local DAMAGE, HEALING, BOTH = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_POWER_SHORT"
    local function Value(stats, id, level) return Score.StatsValue(stats, id, level) end

    near(Value({ ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_AGILITY_SHORT = 4 }, MINE_ARMS), 8 * 1.5 + 4, "stats under its names, by the spec's weights")
    near(Value({ ITEM_MOD_CRIT_RATING_SHORT = 28 }, MINE_ARMS), 2 * 8, "a chance: 28 points of rating are the 2% it weighs")
    near(Value({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, MINE_ARMS), 2 * 8, "a chance with weapons counts on a fighter's weights")
    near(Value({ ITEM_MOD_CRIT_MELEE_RATING_SHORT = 28 }, CASTS, 20), 0, "and not on a caster's")
    near(Value({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, CASTS, 20), 6, "a chance with spells counts on a caster's weights")
    near(Value({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, MINE_ARMS), 0, "and not on a fighter's")
    near(Value({ ITEM_MOD_ATTACK_POWER_SHORT = 10 }, MINE_ARMS), 4, "attack power")
    near(Value({ ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 10 }, MINE_ARMS), 4, "attack power with a ranged weapon is attack power there")
    near(Value({ ITEM_MOD_MELEE_ATTACK_POWER_SHORT = 10 }, MINE_ARMS), 4, "and so is attack power with weapons in hand, of a consumable")
    -- What adds to spells is two stats there: to their damage and to their healing.
    near(Value({ [DAMAGE] = 36 }, CASTS, 20), 36, "spell damage: its spell power")
    near(Value({ [BOTH] = 20 }, CASTS, 20), 20, "damage and healing alike: spell power, to weights without one for healing")
    near(Value({ [DAMAGE] = 20, [HEALING] = 20 }, CASTS, 20), 20, "the same under the game's two other names")
    near(Value({ [HEALING] = 30 }, CASTS, 20), 0, "healing alone is nothing to those")
    near(Value({ [HEALING] = 30 }, HEALS, 20), 30 + 10 * 0.6, "to a healer's it is healing, and a third of it spell power under a weight of its own")
    near(Value({ [DAMAGE] = 30, [HEALING] = 40 }, HEALS, 20), 40, "with something for damage beside it: healing alone")
    near(Value({ ITEM_MOD_HEALTH_SHORT = 20 }, MINE_ARMS), 1, "health under its own weight")
    near(Value({ ITEM_MOD_MANA_SHORT = 30 }, CASTS, 20), 3, "and mana")
    near(Value({ ITEM_MOD_UNHEARD_OF_SHORT = 99 }, MINE_ARMS), 0, "a stat it has no name for counts for nothing")
    near(Value({ ITEM_MOD_SPIRIT_SHORT = 8 }, MINE_ARMS), 0, "nor does one the spec does not weigh")
    eq(Value({ ITEM_MOD_STRENGTH_SHORT = 8 }, "MAGE:frost", 20), nil, "no answer for a spec it has no weights for")
    eq(Value({ ITEM_MOD_STRENGTH_SHORT = 8 }, "S1"), nil, "nor for one of the addon's own profiles")

    -- Its weights are asked for by the class, the spec and the level, and not twice.
    W.SetGearQuestWeights("DRUID", "bear", function(level) return { weights = { sta = level >= 40 and 2 or 1 } } end)
    near(Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 20), 10, "a druid of 20: the weights it has for that level")
    near(Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 45), 20, "one of 45: another level's")
    local last = W.gearquest.weighed[#W.gearquest.weighed]
    eq(last.class, "DRUID", "asked for by the class"); eq(last.base, "bear", "the spec"); eq(last.level, 45, "and the level")
    local times = #W.gearquest.weighed
    Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 45)
    Value({ ITEM_MOD_STAMINA_SHORT = 10 }, "DRUID:bear", 20)
    eq(#W.gearquest.weighed, times, "the same weights are not asked for twice")

    -- The list of consumables is scored on the spec.
    W.OpenAuctionHouse()
    ScanSupplies()
    local rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(MINE_ARMS, { mana = false }))
    local function Worth(name)
        for _, row in ipairs(rows) do
            if row.kind == "supply" and row.entry.supply.name == name then return row.entry.value end
        end
    end
    near(Worth("Elixir of Giants"), 25 * 1.5, "an elixir of Strength on a fighter's weights"); near(Worth("Elixir of Agility"), 15, "one of Agility")
    eq(Worth("Elixir of Wisdom"), nil, "Intellect is of no use to that spec")
    rows = ns.Supplies.Build(ns.Scanner.supplies, SupplyOpts(CASTS, { mana = true }))
    near(Worth("Elixir of Wisdom"), 6, "and worth its weight to a caster's")
    -- The heading over a consumable's score says whose weights they are.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    ns.Tooltip.AddHeader(GameTooltip, "Arms", true)
    local heading = GameTooltip._lines[#GameTooltip._lines]
    check(heading.text:find("Upgrade Scout (scored like GearQuest)", 1, true) ~= nil, "a heading over a score, with GearQuest scoring: " .. heading.text)
    eq(heading.right, "Arms", "with what stands on its right")
    ns.Tooltip.AddHeader(GameTooltip)
    heading = GameTooltip._lines[#GameTooltip._lines]
    eq(heading.text:find("GearQuest", 1, true), nil, "a heading over notes alone names no other addon")
    eq(#W.gearquest.asked, 0, "no item was asked about for any of it")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- Another character of the account: the specs of its class, its items scored from the
-- weights of its spec, its own choice written on its card, and GearQuest's line, which is
-- about the character being played, kept out of the rows of its list.
function scenarios.gearquest_alt()
    StandardWorld()
    local warrior, warriorGear = W.player, W.equipped
    -- The druid's chests, by the game's own count of their stats: Intellect, Agility, and on
    -- the one for sale 1% to crit, which the game counts as 14 points of rating. Both are
    -- leather, which GearQuest's Balance counts for half.
    W.AddItem({ id = 300, name = "Alt's Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, level = 15,
        values = { D1 = 0 }, game = { ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_AGILITY_SHORT = 3 } })
    W.AddItem({ id = 310, name = "Druid Jerkin", equipLoc = "INVTYPE_CHEST", subClassID = 2, value = 0, level = 18,
        values = { D1 = 0 }, game = { ITEM_MOD_INTELLECT_SHORT = 14, ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_CRIT_RATING_SHORT = 14 } })
    W.AddAuction(310, 2000)
    GearQuestWorld()
    UpgradeScoutDB = { engine = "gearquest" }

    -- The druid is played once, and a spec picked for it in GearQuest, which keeps that with
    -- what it saves for the druid alone.
    W.Login(Druid())
    W.equipped = { [5] = W.Link(300) }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    eq(ns.Score.Current().name, "@DRUID:feral", "the druid, played: the spec in use in GearQuest, the first of its class")
    GearQuestForeverCharDB.specPick = { DRUID = "bear" }
    W.ResetBags()
    Relog(warrior, warriorGear)
    local Score, S = ns.Score, ns.Scanner
    local card = UpgradeScoutDB.chars["Alty-Testrealm"]
    check(card ~= nil, "the druid is remembered")
    eq(GearQuestForeverCharDB.specPick, nil, "what was picked for the druid in GearQuest is not there to be read while the warrior plays")

    local current, theirs = Score.Current(card)
    eq(#theirs, 4, "another character: every spec GearQuest has for its class")
    eq(theirs[1].name, "DRUID:feral", "by its class and its name there"); eq(theirs[3].title, "Balance", "and GearQuest's name for it")
    eq(current.name, "DRUID:feral", "the one in use, with no talents known and none chosen here: the one it starts the class on")
    eq(#Score.Profiles(ns.Roster.Me()), 3, "the card of the character being played is that character")

    -- At the auction house the field lists them under the warrior's own.
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame = UpgradeScoutFrame
    local dropdown = frame.ProfileDropdown
    local ALTY = "|cffff7c0aAlty|r"
    eq(#dropdown.radios, 7, "the warrior's three specs and the druid's four")
    eq(dropdown.radios[1].text, "Arms", "the warrior's own"); eq(dropdown.radios[4].text, ALTY .. ": Feral", "the druid's by its name and the spec's")
    eq(dropdown.radios[6].text, ALTY .. ": Balance", "each of them")
    W.RunUntil(function() return W.AH.ready end, 5)
    dropdown:Pick(5)
    eq(ns.Roster.Target(), card, "the lists are for the druid"); eq(card.gearquest, "bear", "on the spec chosen, written on its card by its name there")
    dropdown:Pick(6)
    eq(card.gearquest, "balance", "another of its specs chosen")
    eq(#W.gearquest.picked, 0, "and nothing is picked in GearQuest")
    eq(card.profile, nil, "apart from the addon's own profile"); eq(card.scale, nil, "from the Pawn scale")
    eq(card.companion, nil, "from Forever Companion's"); eq(card.leveling, nil, "and from Forever Leveling BiS's")
    local asked = #W.gearquest.asked
    frame.ScanButton:Click()
    W.RunUntil(function() return S.state == "idle" end, 300)
    W.Run(1)
    eq(S.ctx.who, card, "the scan was for the druid"); eq(S.ctx.profile, "DRUID:balance", "on its spec")
    near(S.ctx.equipped[5].value, 12 * 0.5, "its chest: 12 Intellect by the weights of that spec, for the half its leather counts")
    check(Offer("Druid Jerkin") ~= nil, "a jerkin better than the druid's")
    near(Offer("Druid Jerkin").value, 20 * 0.5, "14 Intellect and the 1% to crit: the game's 14 points of rating, weighed by the percent")
    eq(Offer("Good Chest"), nil, "the warrior's upgrades are not the druid's")
    eq(#W.gearquest.asked, asked, "GearQuest is asked for the row of no item: its rows are for the character being played")
    local levels = {}
    for _, weighed in ipairs(W.gearquest.weighed) do
        if weighed.class == "DRUID" and weighed.base == "balance" then levels[weighed.level] = true end
    end
    eq(levels[20], true, "its weights are asked for by the druid's class, spec and level"); eq(levels[10], nil, "not by the warrior's")

    -- A row's tooltip has our lines here: GearQuest's line is about the character being
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
    local row = Row("Druid Jerkin")
    check(row ~= nil, "the jerkin is in the druid's list")
    row:GetScript("OnEnter")(row)
    local ours = Ours(GameTooltip)
    check(ours ~= nil and ours:find("Balance +67%", 1, true) ~= nil, "a row of the druid's list: our lines, on its spec: " .. tostring(ours))
    eq(GearQuestLine(GameTooltip), nil, "GearQuest's own line, which is about the warrior, is kept out")
    eq(rawget(GameTooltip, "gqSkipScoreHook"), nil, "and the tooltip is left as it was found")
    row:GetScript("OnLeave")(row)
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetHyperlink(W.Link(310))
    eq(GearQuestLine(GameTooltip), "rank", "elsewhere in the game it writes about the character being played, as ever")
    -- Whatever happens while such a tooltip is filled in, its mark is taken off again.
    local ok = pcall(Score.Hushed, function() error("the game fails to fill a tooltip in") end, GameTooltip)
    eq(ok, false, "an error while a tooltip is filled in is passed on"); eq(rawget(GameTooltip, "gqSkipScoreHook"), nil, "and the mark does not stay")
    Score.Hushed(function(tooltip, link)
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetHyperlink(link)
    end, GameTooltip, W.Link(200))
    eq(GearQuestLine(GameTooltip), nil, "filled in for another character: none of its lines")

    -- The warrior's own list is by GearQuest's rows again.
    dropdown:Pick(1)
    W.Run(0.5)
    if S.state == "idle" then frame.ScanButton:Click() end
    W.RunUntil(function() return S.state == "idle" end, 300)
    eq(S.ctx.who, nil, "back to the warrior's own list"); eq(S.ctx.profile, MINE_ARMS, "on the spec in use in GearQuest")
    CheckStandardOffers("the warrior's list, after the druid's")
    CheckGearQuestAsked("lists for two characters")

    -- The druid is played again. What was chosen for it here stands, on its card: the
    -- profile is that spec, with GearQuest on the one picked in it for the druid.
    W.ResetBags()
    Relog(Druid(), { [5] = W.Link(300) })
    eq(GearQuest:GetEffectiveSpec(), "bear", "the druid, played again: GearQuest has the spec picked in it")
    eq(ns.Score.Current().name, "@DRUID:balance", "and the profile here is the one chosen for it here")
    eq(GearQuest:GetEffectiveSpec(), "bear", "which is nothing to GearQuest"); eq(#W.gearquest.picked, 0, "where nothing is picked")
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
    local shaman = { class = "SHAMAN", level = 20 }
    eq(Wants.Of(shaman), nil, "nothing ticked: nothing is asked")
    shaman.armorOnly = true
    eq(Wants.Of(shaman).armor, 2, "only leather"); eq(Wants.Of(shaman).gain, nil, "and any gain")
    check(Wants.Of(shaman) == Wants.Of({ class = "ROGUE", level = 5, armorOnly = true }), "the same wants are one table")
    shaman.level = 40
    eq(Wants.Of(shaman).armor, 3, "the tick goes with the character to mail")
    eq(Wants.Of({ class = "MAGE", level = 30, armorOnly = true }), nil, "a tick on the card of one who wears cloth alone asks for nothing")
    shaman.armorOnly = nil
    eq(Wants.Gain(shaman), 10, "the number before one is typed")
    shaman.minGain = 50
    eq(Wants.Of(shaman), nil, "a number alone asks for nothing")
    shaman.minGainOn = true
    eq(Wants.Of(shaman).gain, 50, "ticked: at least that"); eq(Wants.Of(shaman).armor, nil, "of any armor")
    local told = 0
    ns.Listen("WANTS_CHANGED", function(card) if card == shaman then told = told + 1 end end)
    Wants.SetGain(shaman, true, 12345)
    eq(shaman.minGain, 9999, "no more than four digits")
    Wants.SetGain(shaman, true, 0.4)
    eq(shaman.minGain, 1, "and no less than one")
    Wants.SetGain(shaman, false)
    eq(shaman.minGainOn, nil, "unticked"); eq(shaman.minGain, 1, "the number stays"); eq(told, 3, "the addon is told each time")
    Wants.SetArmorOnly(shaman, true)
    eq(shaman.armorOnly, true, "the other box"); eq(told, 4, "of which it is told as well")
    shaman.minGain = "many"
    eq(Wants.Gain(shaman), 10, "a card with no number for a number has the first one")

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

    -- "Top 5 per slot" is judged among what the character would have. With three more for the
    -- head, of leather and of cloth, the mail helm is the weakest of six and the dearest per
    -- point: five stand before it, the leather cap among them, and top five has no row for
    -- it. With mail alone the helm is the best there is for the head.
    for i, def in ipairs({ { "Bear Cap", 2, 17, 500 }, { "Wolf Cap", 2, 16, 400 }, { "Linen Hood", 1, 13, 250 } }) do
        W.AddItem({ id = 250 + i, name = def[1], equipLoc = "INVTYPE_HEAD", subClassID = def[2], value = def[3], level = 9 })
        W.AddAuction(250 + i, def[4])
    end
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
    local MENU = "Only what I can afford | Buyout up to | Top | Hide worse deals | " .. LABEL .. " | Upgrade at least | Gear at most | Weapons > | / | Value by net cost"
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
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top | Hide worse deals | Upgrade at least | Gear at most | Weapons > | / | Value by net cost", "a mage's menu has no line about armor")

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
    FilterBox("Top"):Click()
    Settle()
    eq(frame.FilterNames:GetText(), "Affordable \194\183 Top 5 \194\183 From +25%", "three filters by name")
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
-- and dearer per point, so it is not the best value while the good chest is in the list.
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
            limit = ns.db.topOnly and ns.Results.TopCount() or nil, unchecked = S.Unchecked(),
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

    -- "Top 5 per slot" is judged among what the sum lets through. With three more chests, each
    -- stronger than the plain one and dearer, five stand before it, and the good chest costs
    -- less per point: top five has no row for it. With no more than 36 silver to pay those
    -- five are out, and the plain one is the best chest there is.
    for i = 1, 3 do
        W.AddItem({ id = 250 + i, name = "Dear Chest " .. i, equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 18 + i, level = 9 })
        W.AddAuction(250 + i, (40 + 5 * i) * SILVER)
    end
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
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top | Hide worse deals | Best armor type for the class | Upgrade at least | Gear at most | Weapons > | / | Value by net cost",
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
    eq(UpgradeScoutFrame.FilterNames:GetText(), "По карману \226\128\162 Топ-5", "the filters that are on, a bullet between them")
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
-- A client that has loaded none of its items yet, as a game that has just been updated: it
-- tells of the rows over many seconds, a batch at a time, with more than a second between
-- the batches. A few rows that were read are not the list: it waits for the rest as long as
-- the client goes on telling of them, the status line counts them down, and when the list
-- comes it is whole. No row goes to an item search unread.
function scenarios.scan_cold()
    StandardWorld()
    local slow = {}
    for i = 1, 60 do
        local id = 3000 + i
        W.AddItem({ id = id, name = "Cold Helm " .. i, equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 20 + i, level = 9, uncached = true })
        W.AddAuction(id, 1000 + i)
        slow[id] = 2.5 + math.floor((i - 1) / 10) * 2.5     -- ten at a time, two and a half seconds apart
    end
    W.loadAfter = slow
    LoadAddon()
    SetView(false, false)                -- every upgrade is listed, so every price is looked up
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    local function Status() return frame.Status:GetText() or "" end
    local function Listed(name) return Unsure(name) ~= nil or Offer(name) ~= nil end

    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "score" and S.stats.waiting > 0 end, 60)
    eq(S.stats.waiting, 60, "every row has had its turn, and the client has yet to tell of sixty")
    W.Run(1.3)
    eq(S.state, "score", "over a second with no row read: the list waits on, for there are many")
    eq(Listed("Good Chest"), false, "and is not shown as a few rows of what is for sale")
    check(Status():find("Scoring items: ", 1, true) ~= nil, "the status line counts the rows scored still: " .. Status())
    W.RunUntil(function() return (S.info.waiting or 0) > 0 end, 10)
    W.Run(0.1)
    eq(Status(), "Waiting for the game to load items: 60 left", "two seconds of nothing: the status line says what the scan waits for")
    W.RunUntil(function() return S.info.waiting < 60 end, 10)
    W.Run(0.1)
    eq(Status(), "Waiting for the game to load items: " .. S.info.waiting .. " left", "counted down as the client tells of them")
    eq(S.stats.stalled, true, "the scan's numbers say that it stood still for the client")
    W.RunUntil(function() return S.state ~= "score" end, 60)
    eq(S.state, "verify", "nearly all told of: the prices are looked up")
    -- (The last few, when the client stops for a moment, are read on meanwhile like any
    -- few rows, and join the list as they come.)
    check(S.stats.late <= 30, "a few rows at most are left to be read meanwhile: " .. S.stats.late)
    eq(S.unread, 0, "and none is left out")
    eq(S.stats.waiting, 60, "the scan's numbers say how many the client was slow with")
    eq(S.stats.waitingWhy.data, 60, "and for want of what")
    local listed = 0
    for i = 1, 60 do
        if Listed("Cold Helm " .. i) then listed = listed + 1 end
    end
    check(listed >= 30, "the list has most of the rows when it comes: " .. listed)
    W.RunUntil(function() return S.state == "idle" end, 600)
    for i = 1, 60 do check(Offer("Cold Helm " .. i) ~= nil, "and is whole in the end: helm " .. i) end
    eq(Offer("Cold Helm 60").buyout, 1060, "each at its price")
    check(not Status():find("has not loaded", 1, true), "the list is short of nothing: " .. Status())
    eq(#ns.db.scans, 1, "the scan's numbers are kept among the last few")
end

-- Many rows the client never tells of. An item search for each would take minutes, most of
-- them for nothing, with the list standing at the few rows that were read: none is sent. The
-- scan goes on with what was read, ends, and the list says how many rows it is short of. A
-- scan a little later, with the items loaded, has them.
function scenarios.scan_unloaded()
    StandardWorld()
    W.neverLoad = {}
    for i = 1, 40 do
        local id = 3100 + i
        W.AddItem({ id = id, name = "Ghost Helm " .. i, equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 20 + i, level = 9, uncached = true })
        W.AddAuction(id, 1000 + i)
        W.neverLoad[id] = true
    end
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    local function Status() return frame.Status:GetText() or "" end
    -- The items the scan sends an item search for.
    local searched = {}
    local Send = C_AuctionHouse.SendSearchQuery
    C_AuctionHouse.SendSearchQuery = function(key, ...)
        searched[#searched + 1] = key.itemID
        return Send(key, ...)
    end
    local function Ghosts()
        local n = 0
        for i = 1, #searched do
            if searched[i] > 3100 then n = n + 1 end
        end
        return n
    end

    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "score" and S.stats.waiting > 0 end, 60)
    local began = W.now
    -- (The game loads other items meanwhile, as it does all the time for everybody: those
    -- say nothing of the rows that wait, and do not keep the scan waiting.)
    while S.state == "score" and W.now - began < 20 do
        W.Fire("ITEM_DATA_LOAD_RESULT", 999999, true)
        W.Run(0.25)
    end
    check(W.now - began > 3.5 and W.now - began < 5, "they are waited for four seconds, as ever: " .. (W.now - began))
    eq(S.state, "verify", "then the prices of what was read are looked up")
    eq(S.unread, 40, "forty rows the client told nothing of")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(Ghosts(), 0, "and no item search is sent for any of them")
    check(Offer("Good Chest") ~= nil and Offer("Helm") ~= nil and Offer("Shield") ~= nil, "the rows that were read are all in the list")
    eq(S.stats.left, 40, "the scan's numbers say how many were left out"); eq(S.stats.unread.data, 40, "and for want of what")
    eq(#S.stats.unreadItems, 12, "the first of them are named")
    W.Run(0.3)
    check(Status():find("The game has not loaded 40 rows yet. Scan again in a moment.", 1, true) ~= nil,
        "the list says what it is short of: " .. Status())
    eq(S.Demand(), false, "nothing more is looked up when the list is drawn again")

    -- A purchase, and out of its box again: nothing is sent for the rows left out.
    S.Buy(Offer("Helm"))
    W.RunUntil(Asking, 30)
    Asking().Cancel:Click()
    W.Run(2)
    eq(S.state, "idle", "after a purchase called off the scanner is idle"); eq(Ghosts(), 0, "and has asked about none of them")

    -- The client has its items now.
    W.neverLoad = nil
    check(S.Start(), "a second scan starts")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(S.unread, 0, "a scan a little later: nothing is left out")
    eq(Offer("Ghost Helm 40").buyout, 1040, "and the rows are in the list, at their prices")
    W.Run(0.3)
    check(not Status():find("has not loaded", 1, true), "the list is short of nothing: " .. Status())
    eq(#ns.db.scans, 2, "the numbers of both scans are kept")
    eq(ns.db.scans[1].left, 40, "the first's among them")
end

-- A few rows that are read on while the prices are looked up, in a game so slow that a frame
-- has time for one of them: they are given up when their time is over all the same, and the
-- scan ends. (It waited on for ever: a frame that had no time for every row never looked at
-- the time.)
function scenarios.scan_late_slow()
    StandardWorld()
    W.neverLoad = {}
    for i = 1, 3 do
        local id = 3200 + i
        W.AddItem({ id = id, name = "Ghost Ring " .. i, equipLoc = "INVTYPE_FINGER", value = 30 + i, level = 9, uncached = true })
        W.AddAuction(id, 500 + i)
        W.neverLoad[id] = true
    end
    -- The clock the addon times a frame by (it takes the function when it loads).
    local slowFrames, ticks = false, 0
    local clock = debugprofilestop
    debugprofilestop = function()
        if not slowFrames then return clock() end
        ticks = ticks + 1
        return ticks * 7
    end
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    local S = ns.Scanner
    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "verify" end, 60)
    eq(S.stats.late, 3, "three rows the list did not wait for")
    -- From here on the clock of a frame runs out after one row.
    slowFrames = true
    local began = W.now
    W.RunUntil(function() return S.state == "idle" end, 60)
    check(W.now - began < 30, "the scan ends: " .. (W.now - began))
    eq(S.stats.unread.data, 3, "the three rows were given up")
    check(Offer("Good Chest") ~= nil and Offer("Helm") ~= nil, "and the list is whole")
end

-- The menu of the profile field names another character by its whole name, surname and all,
-- and by nothing else: no realm. And a realm the game has no name for at login (an empty
-- one, now and then) does not unmake what the cards knew.
function scenarios.roster_names()
    StandardWorld()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Roster = ns.Roster
    local me = Roster.Me()
    eq(me.realm, "Testrealm", "the character's realm, as the game names it")
    UpgradeScoutDB.chars["Alty Moon"] = { key = "Alty Moon", name = "Alty", last = "Moon", realm = "Elsewhere", class = "DRUID",
        level = 20, talents = "D1" }
    UpgradeScoutDB.chars["Alty Sun"] = { key = "Alty Sun", name = "Alty", last = "Sun", realm = "Testrealm", class = "DRUID",
        level = 20, talents = "D2" }
    local moon, sun = UpgradeScoutDB.chars["Alty Moon"], UpgradeScoutDB.chars["Alty Sun"]
    eq(Roster.FullName(moon), "Alty Moon", "a whole name: the first name and the surname")
    eq(Roster.FullName(me), "Tester", "the first name alone where there is no surname")

    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local dropdown = UpgradeScoutFrame.ProfileDropdown
    local lines = {}
    for i = 1, #dropdown.radios do lines[#lines + 1] = dropdown.radios[i].text end
    local all = table.concat(lines, " / ")
    check(all:find("Alty Sun|r: ", 1, true) ~= nil, "a character is listed by its whole name: " .. all)
    check(all:find("Alty Moon|r: ", 1, true) ~= nil, "one of another realm too: " .. all)
    check(not all:find("Elsewhere", 1, true) and not all:find("Testrealm", 1, true), "and no realm is written: " .. all)
    check(all:find("Alty Sun", 1, true) < all:find("Alty Moon", 1, true), "those of this realm come first")

    -- The game has no name for the realm: an empty one.
    W.realm = ""
    Roster.Update()
    eq(me.realm, "Testrealm", "the card keeps the realm it knew")
    me.realm = ""                        -- as a version that took the empty name wrote it
    Roster.Update()
    eq(me.realm, nil, "an empty name is no realm")
    eq(Roster.SameRealm(me, sun), true, "a character whose realm is not known is taken to be of the same one")
    eq(Roster.SameRealm(me, moon), true, "whichever that is")
    W.realm = nil
    Roster.Update()
    eq(me.realm, "Testrealm", "named again, it is written down")
    eq(Roster.SameRealm(me, sun), true, "of the same realm"); eq(Roster.SameRealm(me, moon), false, "and of another")
end

-- Forever Leveling BiS names the character's entry by the realm as the game gave it at
-- login. With no name for the realm then, it keeps the character under a name without one
-- for the session, with nothing chosen in it: the addon reads that entry, and says that no
-- main spec is chosen, whatever was saved under the real name.
function scenarios.leveling_no_realm()
    StandardWorld()
    LevelingWorld()
    ForeverLevelingBiSDB.chars["Tester-Testrealm"].spec = "fury"    -- chosen in a session before
    W.realm = ""
    ForeverLevelingBiSDB.chars[W.LevelingKey()] = {}                 -- what it makes at this login
    LoadAddon()
    W.Fire("PLAYER_LOGIN")
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    ns.Score.SetEngine("leveling")
    eq(ns.Roster.Me().realm, nil, "the card has no realm to go by")
    eq(ns.Score.Text("CHANGE"), ns.L.CHOOSE_LEVELING, "no main spec is chosen in the entry it goes by: the button says where to choose one")
    W.LevelingChar().spec = "arms"
    eq(ns.Score.Text("CHANGE"), ns.L.CHANGE_LEVELING, "chosen there, the button says where it is changed")
end

-- An item whose name the game has a moment before what it gives. It is asked again, and is
-- in the list when the game tells the rest. (It was taken to give nothing, for the whole
-- scan.) One the game never tells more of is taken to give nothing after a while, and the
-- scan does not wait for it or look it up.
function scenarios.scan_stats_late()
    StandardWorld()
    W.AddItem({ id = 3300, name = "Slow Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 40, level = 9 })
    W.AddAuction(3300, 900)
    W.AddItem({ id = 3301, name = "Blank Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 50, level = 9 })
    W.AddAuction(3301, 950)
    W.items["3300:0"].statsHeld, W.items["3301:0"].statsHeld = true, true
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    local S = ns.Scanner
    local blank = 0
    local Send = C_AuctionHouse.SendSearchQuery
    C_AuctionHouse.SendSearchQuery = function(key, ...)
        if key.itemID == 3301 then blank = blank + 1 end
        return Send(key, ...)
    end
    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "score" end, 60)
    local began = W.now
    W.Run(0.8)
    W.items["3300:0"].statsHeld = nil     -- the game tells what the helm gives
    W.RunUntil(function() return S.state == "idle" end, 600)
    check(Offer("Slow Helm") ~= nil, "the helm the game was slow to tell of is in the list")
    eq(Offer("Slow Helm").buyout, 900, "at its price")
    eq(Offer("Blank Helm"), nil, "the one it never told more of is not")
    eq(blank, 0, "and was not looked up")
    eq(next(S.stats.unread), nil, "no row went to an item search unread")
    check(Offer("Good Chest") ~= nil and Offer("Helm") ~= nil and Offer("Shield") ~= nil, "the rest of the list is whole")
    check(W.now - began < 30, "and the scan did not stand still for it: " .. (W.now - began))
end

-- Most of the rows a first look left unread come a moment later, and one never does: the
-- list does not stand four seconds for that one because they were many at first.
function scenarios.scan_warm_tail()
    StandardWorld()
    for i = 1, 31 do
        local id = 3400 + i
        W.AddItem({ id = id, name = "Fresh Helm " .. i, equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 20 + i, level = 9, uncached = true })
        W.AddAuction(id, 1000 + i)
    end
    W.AddItem({ id = 3499, name = "Ghost Ring", equipLoc = "INVTYPE_FINGER", value = 30, level = 9, uncached = true })
    W.AddAuction(3499, 500)
    W.neverLoad = { [3499] = true }
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    local S = ns.Scanner
    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "score" and S.stats.waiting > 0 end, 60)
    local began = W.now
    eq(S.stats.waiting, 32, "thirty-two rows unread at the first look")
    W.RunUntil(function() return S.state ~= "score" end, 60)
    check(W.now - began < 2.5, "the list comes a second after the last row was read, not four: " .. (W.now - began))
    eq(S.stats.late, 1, "the one row is read on meanwhile")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(Offer("Fresh Helm 31").buyout, 1031, "the rows that came are in the list")
end

-- An item Pawn has nothing for, though the game says what it gives: that is an answer, and
-- the scan does not wait for another.
function scenarios.pawn_blind_scan()
    StandardWorld()
    PawnWorld()
    for i = 1, 3 do
        W.AddItem({ id = 3500 + i, name = "Blind Helm " .. i, equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 40 + i, level = 9, pawnBlind = true })
        W.AddAuction(3500 + i, 900 + i)
    end
    UpgradeScoutDB = { engine = "pawn" }
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    SetView(false, false)
    W.OpenAuctionHouse()
    local S = ns.Scanner
    check(S.Start(), "scan starts")
    W.RunUntil(function() return S.state == "idle" end, 600)
    check(S.stats.score < 0.3, "the scoring is not held up by what Pawn cannot read: " .. S.stats.score)
    eq(S.stats.waiting, 0, "no row waited"); eq(S.stats.late, 0, "none was read late")
    eq(Offer("Blind Helm 1"), nil, "and such an item is not in the list")
end

-- A scan for consumables in a client that has not loaded its items: the rows it never told
-- of are left out, as ever, and when they are many the scan's numbers say so.
function scenarios.supplies_unloaded()
    SuppliesWorld()
    W.neverLoad = {}
    for i = 1, 40 do
        local id = 4000 + i
        W.AddItem({ id = id, name = "Ghost Brew " .. i, classID = 0, quality = 1, subClassID = 2, level = 10, stack = 5,
            use = "Increases Strength by " .. i .. " for 1 hr.", uncached = true })
        W.AddAuction(id, 20 + i, { quantity = 3 })
        W.neverLoad[id] = true
    end
    LoadAddon()
    SupplyFacts()
    W.OpenAuctionHouse()
    local S = ns.Scanner
    check(S.StartSupplies(), "the scan for consumables starts")
    W.RunUntil(function() return S.state == "score" and (S.info.waiting or 0) > 0 end, 60)
    eq(S.info.waiting, 40, "forty rows the client has yet to tell of")
    W.RunUntil(function() return S.state == "idle" end, 60)
    eq(S.suppliesUnread, 40, "left out, and counted: the list says that it is short of them")
    local listed = 0
    for _ in pairs(S.supplies) do listed = listed + 1 end
    check(listed > 0, "what the client told of is listed")
    W.neverLoad = nil
    check(S.StartSupplies(), "a second scan starts")
    W.RunUntil(function() return S.state == "idle" end, 60)
    eq(S.suppliesUnread, 0, "a scan a little later is short of nothing")
end

-- A real scan, as the game is: most rows are not loaded at the first look and come a moment
-- after they are asked for, and of a few dozen the client never says that it has loaded
-- them. Some of those can be read all the same, by the row's own link: they are, and are
-- in the list. The rest are left out: no wait, no item search, no word about them. The
-- status line counts the rows scored from the first to the last, and never says that the
-- scan waits for the game.
function scenarios.scan_junk()
    StandardWorld()
    for i = 1, 30 do
        W.AddItem({ id = 3600 + i, name = "Plain Cap " .. i, equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 1, level = 5, uncached = true })
        W.AddAuction(3600 + i, 100 + i)
    end
    W.AddItem({ id = 3701, name = "Odd Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 45, level = 9, neverCached = true })
    W.AddAuction(3701, 1200)
    W.AddItem({ id = 3702, name = "Odd Cap", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 2, level = 9, neverCached = true })
    W.AddAuction(3702, 300)
    W.neverLoad = {}
    for i = 1, 3 do
        W.AddItem({ id = 3710 + i, name = "Ghost Ring " .. i, equipLoc = "INVTYPE_FINGER", value = 30 + i, level = 9, uncached = true })
        W.AddAuction(3710 + i, 500 + i)
        W.neverLoad[3710 + i] = true
    end
    LoadAddon()
    SetView(false, false)
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local S = ns.Scanner
    local frame = UpgradeScoutFrame
    local function Status() return frame.Status:GetText() or "" end
    local ghosts = 0
    local Send = C_AuctionHouse.SendSearchQuery
    C_AuctionHouse.SendSearchQuery = function(key, ...)
        if key.itemID > 3710 then ghosts = ghosts + 1 end
        return Send(key, ...)
    end

    check(S.Start(), "scan starts")
    local began, last = W.now, 0
    while S.state ~= "idle" do
        W.Tick(0.05)
        local text = Status()
        if S.state == "score" then
            check(not text:find("Waiting for the game", 1, true), "the status line never says that the scan waits: " .. text)
            local n = tonumber(text:match("Scoring items: (%d+) of"))
            if n then
                check(n >= last, "and counts the rows scored, never back: " .. text)
                last = n
            end
        end
        check(W.now - began < 600, "the scan ends")
    end
    check(S.stats.score < 3, "the scoring did not stand still for the rows that never load: " .. S.stats.score)
    eq(S.stats.waiting, 35, "at the first look thirty-five rows were not loaded")
    eq(S.stats.stalled, false, "the scan never stood still for the client")
    eq(S.stats.forced, 2, "two rows were read though the client never said it had their items")
    eq(Offer("Odd Helm").buyout, 1200, "one of them an upgrade, in the list at its price")
    eq(S.stats.late, 3, "three rows were left to be read meanwhile")
    eq(S.stats.unread.data, 3, "and never were"); eq(S.stats.left, 3, "they are left out")
    eq(ghosts, 0, "with no item search sent for them")
    eq(S.unread, 0, "and the list says nothing of them")
    W.Run(0.3)
    check(not Status():find("has not loaded", 1, true), "its status line neither: " .. Status())
    check(Offer("Good Chest") ~= nil and Offer("Helm") ~= nil and Offer("Shield") ~= nil, "the rest of the list is whole")
end

---------------------------------------------------------------------------
-- "Gear at most N levels below": a character is offered nothing made for levels far below
-- its own, and its scan reads no such gear (Wants.lua, Scanner.lua, Filters.lua). Gear that
-- asks for no level is not made for a low one: the filter leaves it alone.
---------------------------------------------------------------------------
-- A warrior of level 30 in a chest that scores 10, at an auction house with gear for every
-- level. With ten levels asked for, gear from level 20 up is all it is offered.
--   below 20    400 chests no better than the worn one, and two upgrades: Old Helm (level
--               12) and Edge Belt (19)
--   20 to 30    20 chests no better, and four upgrades: Rim Belt and Rim Boots (20), Fine
--               Helm (25), Top Chest (30)
--   above 30    250 rows the warrior cannot wear yet
--   no level    Bare Ring asks for none (0). Of two cloaks the rows do not say what they ask
--               for, and the items do: Dim Cloak 26, Dull Cloak 12. All three are upgrades.
local function LevelsWorld()
    W.player.level = 30
    W.AddItem({ id = 100, name = "Worn Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 10, level = 25 })
    W.equipped[5] = W.Link(100)
    local function Sell(def, price)
        W.AddItem(def)
        W.AddAuction(def.id, price)
    end
    for i = 1, 400 do
        Sell({ id = 1000 + i, name = "Low Chest " .. i, equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 1 + i % 9, level = 1 + i % 19 }, 100 + i)
    end
    for i = 1, 20 do
        Sell({ id = 2000 + i, name = "Mid Chest " .. i, equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 1 + i % 9, level = 20 + i % 11 }, 500 + i)
    end
    for i = 1, 250 do
        Sell({ id = 3000 + i, name = "High Chest " .. i, equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 50 + i, level = 31 + i % 15 }, 900 + i)
    end
    Sell({ id = 500, name = "Old Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 20, level = 12 }, 400)
    Sell({ id = 501, name = "Edge Belt", equipLoc = "INVTYPE_WAIST", subClassID = 3, value = 6, level = 19 }, 300)
    Sell({ id = 502, name = "Rim Belt", equipLoc = "INVTYPE_WAIST", subClassID = 3, value = 7, level = 20 }, 350)
    Sell({ id = 503, name = "Rim Boots", equipLoc = "INVTYPE_FEET", subClassID = 3, value = 8, level = 20 }, 450)
    Sell({ id = 504, name = "Fine Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 30, level = 25 }, 2000)
    Sell({ id = 505, name = "Top Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 25, level = 30 }, 3000)
    Sell({ id = 506, name = "Bare Ring", equipLoc = "INVTYPE_FINGER", value = 5, level = 0 }, 250)
    Sell({ id = 507, name = "Dim Cloak", equipLoc = "INVTYPE_CLOAK", subClassID = 1, value = 8, level = 26, levelUntold = true }, 600)
    Sell({ id = 508, name = "Dull Cloak", equipLoc = "INVTYPE_CLOAK", subClassID = 1, value = 9, level = 12, levelUntold = true }, 200)
end

-- Every upgrade of that world for the warrior, and those made for level 20 and up. The
-- filter's list is those and the ring, which asks for no level. The stand-in's auction
-- house, asked for gear from level 20, sends no row that says less, and so not the ring's,
-- which says 0: as the Forever server does. A scan with the box ticked reads the ring from
-- the search it sends first, which names no level (ReadFirst in Scanner.lua).
-- (`noLevelPasses` is an auction house that sends such rows whatever level is named.)
local EVERY_LEVEL = "Bare Ring, Dim Cloak, Dull Cloak, Edge Belt, Fine Helm, Old Helm, Rim Belt, Rim Boots, Top Chest"
local FROM_TWENTY = "Dim Cloak, Fine Helm, Rim Belt, Rim Boots, Top Chest"
local WITH_RING = "Bare Ring, " .. FROM_TWENTY

-- The filter itself, and what it does to the list after a scan, to the price checks of a
-- scan and to a set for a budget.
function scenarios.levels()
    LevelsWorld()
    LoadAddon()
    local Wants, S = ns.Wants, ns.Scanner

    -- The number on a card, and the level it comes to.
    local card = { class = "SHAMAN", level = 30 }
    eq(Wants.Below(card), 10, "ten levels stand in the field before a number is typed")
    eq(Wants.FromLevel(card), nil, "nothing ticked: gear of every level"); eq(Wants.Of(card), nil, "and nothing is asked")
    card.maxBelow = 12
    eq(Wants.Of(card), nil, "a number alone asks for nothing")
    eq(Wants.LevelTyped(card), 18, "though it is known what it comes to")
    card.maxBelowOn = true
    eq(Wants.FromLevel(card), 18, "ticked, at level 30: nothing made for less than level 18")
    eq(Wants.Of(card).level, 18, "which is one of the wants"); eq(Wants.Of(card).armor, nil, "of any armor"); eq(Wants.Of(card).gain, nil, "and any gain")
    check(Wants.Of(card) == Wants.Of({ class = "MAGE", level = 20, maxBelow = 2, maxBelowOn = true }), "the same wants are one table")
    card.level = 31
    eq(Wants.Of(card).level, 19, "a level gained takes it up by one")
    card.level = 14
    eq(Wants.FromLevel(card), 2, "at level 14: from the second level")
    card.level = 13
    eq(Wants.FromLevel(card), nil, "at level 13 the number reaches the first level: nothing is left out"); eq(Wants.Of(card), nil, "and nothing is asked")
    card.level = 5
    eq(Wants.FromLevel(card), nil, "nor of a character of fewer levels than the number")
    eq(Wants.FromLevel(nil), nil, "no character, no level"); eq(Wants.LevelTyped(nil), nil, "typed or asked")
    card.armorOnly, card.minGainOn, card.minGain, card.level = true, true, 40, 30
    local all = Wants.Of(card)
    eq(all.armor, 2, "beside the other two wants: leather"); eq(all.gain, 40, "at least 40%"); eq(all.level, 18, "from level 18")

    -- What is set, and who is told.
    local told = 0
    ns.Listen("WANTS_CHANGED", function() told = told + 1 end)
    Wants.SetBelow(card, true, 75)
    eq(card.maxBelow, 59, "no more than 59 levels, which is all there are below the last")
    Wants.SetBelow(card, true, 0.4)
    eq(card.maxBelow, 1, "and no less than one")
    Wants.SetBelow(card, true, 7.9)
    eq(card.maxBelow, 7, "in whole levels")
    Wants.SetBelow(card, false)
    eq(card.maxBelowOn, nil, "unticked"); eq(card.maxBelow, 7, "the number stays")
    eq(told, 0, "the arrows in the bags are not told: an item in the bags is judged whatever level it is made for")

    -- A card comes out of a saved file: what is no number, or no tick, is taken for none.
    for _, wrong in ipairs({ "ten", 0, -4, 0 / 0, true, {} }) do
        eq(Wants.Below({ maxBelow = wrong }), 10, "a card with " .. tostring(wrong) .. " for a number has the first one")
    end
    eq(Wants.Below({ maxBelow = 1e9 }), 59, "a number beyond all levels is the most there is"); eq(Wants.Below({ maxBelow = math.huge }), 59, "however far beyond")
    eq(Wants.Below({ maxBelow = 3.7 }), 3, "a number between two levels is the lower")
    for _, wrong in ipairs({ "yes", 1, {} }) do
        eq(Wants.FromLevel({ level = 30, maxBelow = 10, maxBelowOn = wrong }), nil, "a tick of " .. tostring(wrong) .. " is no tick")
    end
    for _, wrong in ipairs({ "30", true, {}, 0 / 0, -5 }) do
        eq(Wants.FromLevel({ level = wrong, maxBelow = 10, maxBelowOn = true }), nil, "a card with " .. tostring(wrong) .. " for a level leaves nothing out")
    end
    eq(Wants.FromLevel({ maxBelow = 10, maxBelowOn = true }), nil, "nor does one without a level")
    eq(Wants.FromLevel({ level = 30.9, maxBelow = 10, maxBelowOn = true }), 20, "a level between two is the lower")

    -- Which items the character would have.
    local twenty = { level = 20 }
    eq(Wants.Fits(twenty, { reqLevel = 20 }), true, "gear for level 20 is offered from level 20")
    eq(Wants.Fits(twenty, { reqLevel = 19 }), false, "gear for level 19 is not")
    eq(Wants.Fits(twenty, { reqLevel = 0 }), true, "gear that asks for no level is not made for a low one: the filter leaves it alone")
    eq(Wants.Fits(twenty, { reqLevel = 1 }), false, "gear made for the first level is")
    eq(Wants.Fits(twenty, {}), true, "what says nothing of its level is not left out for it")
    eq(Wants.Fits(nil, { reqLevel = 1 }), true, "nothing asked: anything will do")
    eq(Wants.Fits({ level = 20, armor = 3 }, { reqLevel = 25, armor = 2 }), false, "the armor is asked as before")
    eq(#Wants.Keep(twenty, { reqLevel = 19 }, { {}, {} }), 0, "no slot is kept for what is not offered")
    eq(#Wants.Keep(twenty, { reqLevel = 20 }, { {}, {} }), 2, "and every slot for what is")

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

    -- Reference: nothing asked, and the tab's own filters off, so every price is looked up.
    SetView(false, false)
    eq(Scan(), 9, "nine upgrades, nine item searches")
    local list, unwanted = Shown()
    eq(list, EVERY_LEVEL, "all of them listed"); eq(unwanted, 0, "none left out")
    eq(S.ReadFrom(), nil, "the scan read gear of every level")

    -- Ticked after the scan: what is made for less than level 20 is out at once. Nothing is
    -- looked up, and no new scan is needed: the rows that stay were all read.
    Wants.SetBelow(me, true, 10)
    list, unwanted = Shown()
    eq(list, WITH_RING, "no helm of level 12, no belt of 19, no cloak of 12; the ring that asks for no level stays")
    eq(unwanted, 3, "three upgrades left out")
    eq(S.ReadFrom(), nil, "the list has all it is to show"); eq(S.Demand(), false, "and needs no price")
    -- The best set for a budget is made of the same. Eight silver buy the old helm and the
    -- dull cloak; of what is made for level 20 and up, the belt and the boots.
    local function Set(wants)
        local rows = ns.Plan.Rows(ns.Plan.Choose(ns.Plan.Ladder(S.offers, S.ctx, 800, wants), 800))
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.name end
        end
        table.sort(out)
        return table.concat(out, ", ")
    end
    eq(Set(nil), "Dull Cloak, Old Helm", "a set for eight silver, of any level")
    eq(Set(Wants.Of(me)), "Rim Belt, Rim Boots", "and of gear from level 20")
    -- Unticked again: they were read, and are back.
    Wants.SetBelow(me, false)
    eq(Shown(), EVERY_LEVEL, "unticked: everything again")

    -- A scan with it ticked keeps nothing made for less, and looks up no such price. The
    -- ring that asks for no level is in its list like any other upgrade.
    Wants.SetBelow(me, true, 10)
    eq(Scan(), 6, "six item searches")
    eq(OfferCount(), 6, "six upgrades"); eq(UnsureCount(), 0, "and none waiting")
    list, unwanted = Shown()
    eq(list, WITH_RING, "the same list"); eq(unwanted, 0, "what the scan did not keep is not counted as left out: it was never scored")
    eq(S.ReadFrom(), nil, "the list has all it is to show")
    -- Narrower after the scan: out at once.
    Wants.SetBelow(me, true, 5)
    list, unwanted = Shown()
    eq(list, "Bare Ring, Dim Cloak, Fine Helm, Top Chest", "from level 25: no belt and no boots of level 20"); eq(unwanted, 2, "two left out")
    eq(S.ReadFrom(), nil, "which takes no new scan")
    -- Wider than the scan read: there is nothing to show of what it did not read, no lookup
    -- brings it, and the scanner says from which level it read.
    Wants.SetBelow(me, true, 15)
    eq(Shown(), WITH_RING, "from level 15: the list is what the scan read, from level 20")
    eq(S.ReadFrom(), 20, "and the scanner says that it read from there"); eq(S.Demand(), false, "no price is asked for: the rows are not there")
    Wants.SetBelow(me, true, 10)
    eq(S.ReadFrom(), nil, "the number the scan was made with: nothing is missing")
    W.RunUntil(function() return W.AH.ready end, 5)
    local browses = W.AH.calls.browse
    eq(S.Reread(), false, "and there is nothing to scan again for"); eq(S.state, "idle", "nothing is under way")
    Wants.SetBelow(me, false)
    eq(S.ReadFrom(), 20, "switched off: missing again"); eq(Shown(), WITH_RING, "with the same list")
    -- A level gained since the scan makes the filter narrower by one.
    Wants.SetBelow(me, true, 10)
    W.player.level = 31
    eq(Wants.Of(me).level, 21, "level 31: from level 21"); eq(Shown(), "Bare Ring, Dim Cloak, Fine Helm, Top Chest", "what is made for level 20 is out")
    eq(S.ReadFrom(), nil, "and no scan is needed for that")
    W.player.level = 30
    -- The scan made again for a list that is short (S.Reread: the tab calls it a moment after
    -- the filter was made wider) has what the last one left unread.
    Wants.SetBelow(me, false)
    local searches = W.AH.calls.search
    eq(S.Reread(), true, "the box unticked: the list is short, and is scanned again")
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(W.AH.calls.browse - browses, 1, "one scan"); eq(W.AH.lastQuery.minLevel, nil, "which asks for every level")
    eq(W.AH.calls.search - searches, 9, "nine searches again")
    eq(Shown(), EVERY_LEVEL, "and every upgrade"); eq(S.ReadFrom(), nil, "nothing missing")
    eq(S.Reread(), false, "nor anything to scan again for")

    -- Ticked while the prices of a scan are looked up: what it leaves out is not looked up
    -- (the first search, for the strongest upgrade, is out by then: a helm of level 25).
    W.RunUntil(function() return W.AH.ready end, 5)
    searches = W.AH.calls.search
    check(S.Start(), "a scan starts")
    W.RunUntil(function() return S.state == "verify" end, 120)
    Wants.SetBelow(me, true, 10)
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(W.AH.calls.search - searches, 6, "six searches, not nine")
    eq(S.stats.skipped, 3, "three candidates whose price the list did not need")
    eq(Offer("Old Helm"), nil, "no price for the old helm"); check(Unsure("Old Helm") ~= nil, "which is counted at the lowest price of its row")
    check(Offer("Bare Ring") ~= nil, "the ring that asks for no level has its price like any other")
    list, unwanted = Shown()
    eq(list, WITH_RING, "the list is of gear from level 20, and the ring"); eq(unwanted, 3, "with three left out")
    eq(S.ReadFrom(), nil, "the scan itself read every level")
    -- Unticked: their prices are asked for, and no others.
    Wants.SetBelow(me, false)
    eq(More(), 3, "unticked: three searches")
    eq(OfferCount(), 9, "and every upgrade has its price"); eq(Shown(), EVERY_LEVEL, "and is listed")

    -- The number is the character's own, kept with the account.
    Wants.SetBelow(me, true, 12)
    eq(UpgradeScoutDB.chars[me.key].maxBelow, 12, "the number is saved on the character's card"); eq(UpgradeScoutDB.chars[me.key].maxBelowOn, true, "with its tick")
end

-- A browse query as one text, its fields in the order of their names: two queries are the
-- same when their texts are.
local function QueryText(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, key in ipairs(keys) do out[#out + 1] = tostring(key) .. "=" .. QueryText(value[key]) end
    return "{" .. table.concat(out, ",") .. "}"
end

-- What the scan asks of the auction house with the filter on, how much less it reads and
-- scores, and that of gear that asks for a level the list is the same whatever the auction
-- house makes of being asked. The ring that asks for none is in the list wherever its row
-- comes, and missing where the auction house leaves it out.
function scenarios.scan_levels()
    LevelsWorld()
    W.AddItem({ id = 600, name = "Weak Potion", classID = 0, quality = 1, subClassID = 1, level = 1, stack = 5, use = "Restores 70 to 90 health." })
    W.AddAuction(600, 30, { quantity = 10 })
    LoadAddon()
    local Wants, S, AH = ns.Wants, ns.Scanner, W.AH
    W.OpenAuctionHouse()
    local me = ns.Roster.Me()
    SetView(false, false)
    -- A scan, and what it took: browse queries, further pages, item searches, the rows read
    -- and the rows that went on to be scored.
    local function Scan()
        W.RunUntil(function() return AH.ready end, 5)
        local queries, pages, searches = AH.calls.browse, AH.calls.more, AH.calls.search
        ScanToEnd()
        return { queries = AH.calls.browse - queries, pages = AH.calls.more - pages, searches = AH.calls.search - searches,
            rows = S.stats.rows, scored = S.info.toScore }
    end
    -- The upgrades whose price was looked up, by name.
    local function Found()
        local out = {}
        for _, offer in pairs(S.offers) do
            if not offer.unsure then out[#out + 1] = offer.name end
        end
        table.sort(out)
        return table.concat(out, ", ")
    end
    -- The search every scan has sent so far: weapons and armor of every quality, by level
    -- and then by price, and not a word of levels.
    local PLAIN = "{filters={1=6,2=7,3=8,4=9,5=10,6=11,7=12},itemClassFilters={1={classID=2},2={classID=4}},"
        .. "searchString=,sorts={1={reverseSort=false,sortOrder=2},2={reverseSort=false,sortOrder=0}}}"
    local LEVELLED = PLAIN:gsub(",searchString=", ",maxLevel=0,minLevel=20,searchString=")

    -- The box not ticked: the search is what it always was, to the letter. The browse reads
    -- on to the hundredth row above the character's level, and every row up to that level
    -- is scored: 429 of them.
    local took = Scan()
    eq(QueryText(AH.lastQuery), PLAIN, "not ticked: the search is the one every scan sent before")
    eq(AH.lastQuery.minLevel, nil, "no lower level in it"); eq(AH.lastQuery.maxLevel, nil, "and no upper")
    eq(took.queries, 1, "one search"); eq(took.pages, 10, "ten further pages")
    eq(took.rows, 550, "550 rows read"); eq(took.scored, 429, "429 of them scored")
    eq(took.searches, 9, "nine item searches"); eq(Found(), EVERY_LEVEL, "for the nine upgrades")
    eq(S.stats.fromLevel, 0, "the scan's numbers: no level was asked for"); eq(S.stats.levelAsked, false, "of anybody")
    check(not S.StatsText():find("level", 1, true), "and its line says nothing of levels: " .. S.StatsText())
    -- A number typed and not ticked asks for nothing either.
    me.maxBelow = 10
    Scan()
    eq(QueryText(AH.lastQuery), PLAIN, "a number alone: the same search")

    -- Ticked, ten levels: the search names level 20, and nothing else in it is other than it
    -- was. The upper level is left at nought, which is no bound, as the game's own window
    -- sends it. An auction house that goes by the level sends 275 rows in all; the browse
    -- stops at the 200th, and 25 rows are scored.
    -- That auction house leaves the ring out too, which asks for no level, and the filter
    -- does not: so the scan begins with the plain search, which brings the gear that asks
    -- for no level before any other, and reads it to the first row that asks for one. That
    -- is one page here, of 50 rows: the ring's, and 49 for the first levels, which are
    -- dropped as they come. The ring is the 26th row scored, and the sixth upgrade.
    Wants.SetBelow(me, true, 10)
    took = Scan()
    eq(QueryText(AH.lastQuery), LEVELLED, "ticked: the same search with the two levels in it")
    eq(AH.lastQuery.minLevel, 20, "level 30 less ten"); eq(AH.lastQuery.maxLevel, 0, "and no upper level")
    eq(took.queries, 2, "two searches"); eq(QueryText(AH.queries[#AH.queries - 1]), PLAIN, "the first of them the plain one, for the gear that asks for no level")
    eq(took.pages, 3, "three further pages, not ten: none of the first search, three of the second")
    eq(took.rows, 250, "250 rows read, not 550"); eq(took.scored, 26, "and 26 scored, not 429")
    eq(took.searches, 6, "six item searches"); eq(Found(), WITH_RING, "for the five upgrades made for level 20 and up, and the ring")
    eq(S.stats.early, true, "the browse still stops before the last page"); eq(S.partial, false, "which is a complete scan")
    eq(S.stats.requests, 5, "five requests in all: two searches and three further pages")
    -- The cloak whose row does not say its level came, was kept, and its item said 26. The
    -- ring that asks for no level did not come with it: this auction house leaves it out
    -- with what is made for less than level 20. It was read before, and the scan's numbers
    -- tell the two apart.
    eq(S.stats.fromLevel, 20, "the scan's numbers: gear from level 20"); eq(S.stats.levelAsked, true, "asked of the auction house")
    eq(S.stats.belowLevel, 0, "which sent no row below it"); eq(S.stats.noLevel, 1, "and one without a level")
    eq(S.stats.noLevelFirst, 1, "after one read by the search that named none: the ring")
    check(S.StatsText():find("The search asked for gear from level 20 up: 0 rows below it came back all the same and were dropped "
        .. "(none means the auction house goes by the level), 1 rows had no level.", 1, true) ~= nil, "as the line of /upscout stats says: " .. S.StatsText())
    eq(UpgradeScoutCharDB.lastScan.fromLevel, 20, "and as is kept with the character's settings"); eq(UpgradeScoutCharDB.lastScan.noLevelFirst, 1, "with the ring's row")
    check(Offer("Bare Ring") ~= nil, "the ring that asks for no level has its price")
    eq(Offer("Edge Belt"), nil, "the belt of level 19 on the first search's page has none"); eq(Unsure("Edge Belt"), nil, "not even its row's")

    -- An auction house that sends what asks for no level whatever level is asked for: the
    -- ring comes twice, and is one row: its item says that it asks for no level, and it is
    -- judged like any other, an upgrade with a price and a place in the list.
    AH.noLevelPasses = true
    took = Scan()
    eq(took.queries, 2, "the same two searches"); eq(took.rows, 250, "the same 250 rows read"); eq(took.scored, 26, "and the same 26 scored")
    eq(took.searches, 6, "six item searches"); eq(Found(), WITH_RING, "the same list")
    eq(S.stats.noLevel, 2, "two rows without a level from the search that named one"); eq(S.stats.noLevelFirst, 1, "and the ring's before it")
    AH.noLevelPasses = nil

    -- An auction house that pays no heed to the levels sends every row, as before. The rows
    -- below level 20 are dropped as they come, so the list is the same and the scoring as
    -- short: the 24 rows that say a level from 20 to 30, and the three that say none, of
    -- which the item of one says 26, of one 12, and the ring's none at all. The cloak of
    -- level 12 is out, and the ring is in.
    AH.levelBounds = "ignore"
    took = Scan()
    eq(QueryText(AH.lastQuery), LEVELLED, "the search still names the level")
    eq(took.rows, 600, "550 rows read, as without the filter, after the 50 of the first search"); eq(took.pages, 10, "ten further pages")
    eq(took.scored, 27, "but 27 scored, not 429")
    eq(took.searches, 6, "six item searches"); eq(Found(), WITH_RING, "and the list is the same, with the ring")
    eq(S.stats.early, true, "the browse stops early as it did"); eq(S.partial, false, "a complete scan")
    eq(S.stats.levelAsked, true, "the scan's numbers: asked for"); eq(S.stats.belowLevel, 402, "402 rows below level 20 came all the same")
    eq(S.stats.noLevel, 3, "and three without a level")
    check(S.StatsText():find("402 rows below it came back all the same and were dropped", 1, true) ~= nil, "which the line of /upscout stats tells: " .. S.StatsText())
    check(Offer("Bare Ring") ~= nil, "the ring that asks for no level has its price")
    eq(Offer("Dull Cloak"), nil, "the cloak whose item says level 12 has none"); eq(Unsure("Dull Cloak"), nil, "not even its row's")
    -- Rows in no order of level, from an auction house that goes by the level: every one of
    -- its 275 rows is read, and of gear that asks for a level the list is the same as from
    -- that auction house in order. The first search is read for one page and no further:
    -- its rows ask for a level from the first on, and the ring is not among those fifty.
    -- (No order of level is no way to find the gear that asks for none short of reading
    -- every row there is, which is what the filter is there to spare.)
    AH.levelBounds, AH.honorLevelSort = "honor", false
    took = Scan()
    eq(took.queries, 2, "unsorted: two searches"); eq(took.rows, 325, "50 rows of the first, and 275 of the second, all there are from level 20")
    eq(S.stats.early, false, "read to the last")
    eq(took.scored, 25, "25 scored"); eq(Found(), FROM_TWENTY, "the list of gear from level 20")
    eq(S.stats.noLevelFirst, 0, "the first search brought no row without a level")
    AH.honorLevelSort = true

    -- An auction house that takes the upper level of nought at its word has nothing between
    -- level 20 and level 0. A scan answered with nothing at all sends its search again
    -- without the levels, and is the scan it was before there was a filter, but for the
    -- rows it drops.
    AH.levelBounds = "literal"
    took = Scan()
    eq(took.queries, 3, "three searches"); eq(QueryText(AH.lastQuery), PLAIN, "the last the plain one")
    eq(QueryText(AH.queries[#AH.queries - 1]), LEVELLED, "after the one that named the level")
    eq(QueryText(AH.queries[#AH.queries - 2]), PLAIN, "and that after the one for the gear that asks for no level")
    eq(took.rows, 600, "550 rows read, after the 50 of the first search"); eq(took.scored, 27, "27 scored")
    eq(took.searches, 6, "six item searches"); eq(Found(), WITH_RING, "the same list, with the ring")
    eq(S.stats.fromLevel, 20, "the scan's numbers: gear from level 20"); eq(S.stats.levelAsked, false, "not asked of the auction house in the end")
    eq(S.stats.belowLevel, 402, "402 rows dropped here"); eq(S.stats.requests, 13, "and two requests more than the eleven")
    check(S.StatsText():find("Gear from level 20 up was wanted, but the search that asked for it brought nothing back: "
        .. "402 rows below it were dropped here, 3 rows had no level.", 1, true) ~= nil, "as the line of /upscout stats says: " .. S.StatsText())
    -- And one that does not answer a search with a level in it: the same, after the wait.
    AH.levelBounds = "silent"
    W.RunUntil(function() return AH.ready end, 5)
    local began = W.now
    took = Scan()
    check(W.now - began > 15, "the search with the level is waited for as long as any")
    eq(took.queries, 3, "then sent without it, the third search of the scan"); eq(QueryText(AH.lastQuery), PLAIN, "as the plain one")
    eq(took.scored, 27, "27 rows scored"); eq(Found(), WITH_RING, "the same list, with the ring")
    eq(S.stats.levelAsked, false, "and the scan's numbers say that the level went unasked"); eq(S.message, nil, "the scan has nothing to complain of")
    AH.levelBounds = "honor"
    -- An auction house that answers nothing at all is given up as before: after the search
    -- for the gear that asks for no level and the search with the level, the two that every
    -- scan sent, by level and then by price alone.
    AH.answerBrowse = false
    W.RunUntil(function() return AH.ready end, 5)
    local sent = AH.calls.browse
    check(S.Start(), "a scan starts")
    W.RunUntil(function() return S.state == "idle" end, 120)
    eq(AH.calls.browse - sent, 4, "four searches"); eq(QueryText(AH.queries[#AH.queries - 3]), PLAIN, "the first for the gear that asks for no level")
    eq(QueryText(AH.queries[#AH.queries - 2]), LEVELLED, "with the level"); eq(QueryText(AH.queries[#AH.queries - 1]), PLAIN, "without it")
    eq(AH.lastQuery.minLevel, nil, "and without it again"); eq(AH.lastQuery.sorts[1].sortOrder, Enum.AuctionHouseSortOrder.Price, "by price alone")
    eq(S.message, ns.L.ERR_BROWSE, "then the scan says that the auction house did not answer")
    AH.answerBrowse = true

    -- The scan for consumables is not the filter's business: its search names no level, and
    -- a potion for the first level is in its list.
    W.RunUntil(function() return AH.ready end, 5)
    ScanSupplies()
    eq(#AH.lastQuery.itemClassFilters, 1, "the search for consumables"); eq(AH.lastQuery.minLevel, nil, "names no level")
    eq(AH.lastQuery.maxLevel, nil, "neither of the two")
    check(Supply("Weak Potion") ~= nil, "and a potion anybody can drink is listed")

    -- The numbers of a scan made before there was a filter, or spoiled in the saved file,
    -- are read without them.
    S.stats = nil
    UpgradeScoutCharDB.lastScan = { requests = 3, rows = 120, fromLevel = "twenty", belowLevel = {} }
    check(not S.StatsText():find("level", 1, true), "numbers that are none: no word of levels: " .. S.StatsText())
    UpgradeScoutCharDB.lastScan = { requests = 3, rows = 120, fromLevel = 20 }
    check(S.StatsText():find("0 rows below it were dropped here, 0 rows had no level.", 1, true) ~= nil, "a level alone: nought for the rest: " .. S.StatsText())
end

-- The search a scan with the filter on begins with, for the gear that asks for no level
-- (ReadFirst in Scanner.lua): read on while its pages hold nothing else, given up when the
-- auction house does not answer it, and not sent at all by a scan with the box unticked.
function scenarios.scan_no_level()
    LevelsWorld()
    -- Seventy chests that ask for no level and are no better than the worn one: with the
    -- ring, 71 rows before the first that asks for a level, which is a page and a half.
    for i = 1, 70 do
        W.AddItem({ id = 4000 + i, name = "Bare Chest " .. i, equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 1 + i % 9, level = 0 })
        W.AddAuction(4000 + i, 700 + i)
    end
    LoadAddon()
    local Wants, S, AH = ns.Wants, ns.Scanner, W.AH
    W.OpenAuctionHouse()
    local me = ns.Roster.Me()
    SetView(false, false)
    local function Scan()
        W.RunUntil(function() return AH.ready end, 5)
        local queries, pages, searches = AH.calls.browse, AH.calls.more, AH.calls.search
        ScanToEnd()
        return { queries = AH.calls.browse - queries, pages = AH.calls.more - pages, searches = AH.calls.search - searches,
            rows = S.stats.rows, scored = S.info.toScore }
    end
    local function Found()
        local out = {}
        for _, offer in pairs(S.offers) do
            if not offer.unsure then out[#out + 1] = offer.name end
        end
        table.sort(out)
        return table.concat(out, ", ")
    end

    -- The box not ticked: one search, as ever, and nothing counted of levels.
    local took = Scan()
    eq(took.queries, 1, "not ticked: one search"); eq(took.rows, 600, "600 rows read"); eq(took.scored, 499, "499 scored")
    eq(Found(), EVERY_LEVEL, "the nine upgrades"); eq(S.stats.noLevelFirst, 0, "no row counted as read first")

    -- Ticked: the first search is read to the first row that asks for a level, which is on
    -- its second page. The 71 rows without a level are scored, and the 29 of the first
    -- level that came with them are dropped. Then the search that names the level: 200
    -- rows, of which 25 are scored.
    Wants.SetBelow(me, true, 10)
    took = Scan()
    eq(took.queries, 2, "ticked: two searches"); eq(took.pages, 4, "one further page of the first, three of the second")
    eq(took.rows, 300, "100 rows and 200"); eq(took.scored, 96, "71 and 25 scored")
    eq(took.searches, 6, "six item searches"); eq(Found(), WITH_RING, "the upgrades from level 20, and the ring")
    eq(S.stats.noLevelFirst, 71, "71 rows without a level read first"); eq(S.stats.noLevel, 1, "one from the search that named the level")
    eq(S.stats.belowLevel, 0, "which sent nothing below it"); eq(S.stats.requests, 6, "six requests")
    eq(S.partial, false, "a complete scan"); eq(S.message, nil, "with nothing to say")

    -- The second page of the first search never comes. After the wait the scan goes on
    -- with the search that names the level, and its list is marked as one that may be
    -- short: the ring was on the page that came, but more such gear may not have been.
    AH.answerMore = false
    W.RunUntil(function() return AH.ready end, 5)
    local began, queries = W.now, AH.calls.browse
    check(S.Start(), "a scan starts")
    W.RunUntil(function() return AH.calls.browse - queries == 2 end, 60)
    check(W.now - began > 15, "the page is waited for as long as any answer")
    AH.answerMore = true
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(Found(), WITH_RING, "the list is the same here: the ring was on the first page")
    eq(S.stats.noLevelFirst, 50, "of 50 rows without a level"); eq(S.partial, true, "and the scan is marked as cut short")
    eq(S.stats.levelAsked, true, "the level was asked for all the same")

    -- The auction house says that the first search failed: the same, without the wait.
    AH.answerBrowse = false
    W.RunUntil(function() return AH.ready end, 5)
    began, queries = W.now, AH.calls.browse
    check(S.Start(), "a scan starts")
    W.RunUntil(function() return AH.calls.browse - queries == 1 end, 5)
    AH.answerBrowse = true
    W.Fire("AUCTION_HOUSE_BROWSE_FAILURE")
    W.RunUntil(function() return S.state == "idle" end, 600)
    check(W.now - began < 15, "no wait for an answer that was refused")
    eq(AH.calls.browse - queries, 2, "the search that names the level goes out"); eq(AH.lastQuery.minLevel, 20, "from level 20")
    eq(Found(), FROM_TWENTY, "the list is of gear from level 20, without the ring")
    eq(S.stats.noLevelFirst, 0, "no row without a level was read first"); eq(S.partial, true, "and the scan is marked as cut short")

    -- A scan after it is whole again.
    took = Scan()
    eq(took.queries, 2, "the next scan: two searches"); eq(Found(), WITH_RING, "with the ring"); eq(S.partial, false, "and complete")

    -- Cut short, and read whole after all. The second page of the first search never comes;
    -- then the auction house has nothing for the search that names the level, which goes out
    -- again without it and reads the gear that asks for no level with the rest. Such a scan
    -- is complete.
    AH.levelBounds, AH.answerMore = "literal", false
    W.RunUntil(function() return AH.ready end, 5)
    queries = AH.calls.browse
    check(S.Start(), "a scan starts")
    W.RunUntil(function() return AH.calls.browse - queries == 2 end, 60)
    AH.answerMore = true
    W.RunUntil(function() return S.state == "idle" end, 600)
    eq(AH.calls.browse - queries, 3, "three searches: the first, the one with the level, the one without")
    eq(S.stats.levelAsked, false, "the level went unasked in the end"); eq(Found(), WITH_RING, "the list is whole")
    eq(S.partial, false, "and the scan is not marked as cut short: the last search read what the first did not")
    AH.levelBounds = "honor"

    -- One row that asks for a level among those that ask for none, out of its place, does
    -- not end the first search: a ring on its second page is read all the same. (The chest
    -- of level 22 is the first row of all here, before the 72 that ask for no level.)
    W.AddItem({ id = 4100, name = "Stray Chest", equipLoc = "INVTYPE_CHEST", subClassID = 3, value = 1, level = 22, sortsAs = -1 })
    W.AddAuction(4100, 800)
    W.AddItem({ id = 4101, name = "Far Ring", equipLoc = "INVTYPE_FINGER", value = 4, level = 0 })
    W.AddAuction(4101, 260)
    took = Scan()
    eq(took.queries, 2, "a stray row: two searches"); eq(took.pages, 4, "the first read to its second page, as before")
    eq(S.stats.noLevelFirst, 72, "72 rows without a level read first")
    eq(Found(), "Bare Ring, Dim Cloak, Far Ring, Fine Helm, Rim Belt, Rim Boots, Top Chest", "the ring of the second page is in the list")
    eq(S.partial, false, "a complete scan")

    -- Somebody else's search while the first one is read stops the scan, as it stops any.
    W.RunUntil(function() return AH.ready end, 5)
    check(S.Start(), "a scan starts")
    W.RunUntil(function() return AH.calls.more > 0 and S.state == "browse" and AH.ready end, 5)
    C_AuctionHouse.SendBrowseQuery({ searchString = "x", sorts = {}, itemClassFilters = {} })
    eq(S.state, "idle", "a search that is not ours stops the scan"); eq(S.message, ns.L.ST_INTERRUPTED, "which says why")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- "Gear at most N levels below" in the Filters menu: a tick box with a field for the number,
-- and words after it. The scan the tab makes by itself when the list is short of rows the
-- last one did not read, and when it makes none; a character of the account with a number
-- and a level of its own.
function scenarios.levels_ui()
    LevelsWorld()
    -- For a druid of the account: two leather caps, of no worth to a warrior.
    W.AddItem({ id = 510, name = "Grove Cap", equipLoc = "INVTYPE_HEAD", subClassID = 2, value = 0, values = { D1 = 12 }, level = 18 })
    W.AddItem({ id = 511, name = "Sprout Cap", equipLoc = "INVTYPE_HEAD", subClassID = 2, value = 0, values = { D1 = 9 }, level = 12 })
    W.AddAuction(510, 700)
    W.AddAuction(511, 300)
    LoadAddon()
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
    local LABEL = "Gear at most"
    -- How many scans were started. (A scan with the box unticked sends one search for the
    -- rows of the auction house, and a scan with it ticked two: see scan_levels.)
    local scans, Start = 0, S.Start
    S.Start = function(...)
        local started = Start(...)
        if started then scans = scans + 1 end
        return started
    end
    local function Browses() return scans end
    -- The line of the open menu, and its field.
    local function Line()
        local line = filters.lines[filters:Find(LABEL)]
        return line, line.Number
    end
    -- A number typed into the field of the menu, as the player does it.
    local function TypeLevels(text)
        filters:Open()
        W.Type(select(2, Line()), text)
        filters:Close()
        W.Run(0.5)
    end
    -- The tick box, and the last line of its tooltip: the level the number comes to for the
    -- character the list is for.
    local below = FilterBox(LABEL)
    local function Comes()
        below:Tooltip()
        local lines = GameTooltip._lines
        local title, tip, last = lines[1].text, lines[2].text, lines[#lines].text
        GameTooltip:Hide()
        eq(title, LABEL, "the tooltip is titled with the label"); eq(tip, ns.L.LEVEL_MIN_TIP, "and says what the box leaves out")
        return last
    end
    local function Scanned()
        W.RunUntil(function() return W.AH.ready end, 5)
        frame.ScanButton:Click()
        Settle()
    end

    -- The line stands with the character's other two, above the menu of its weapons and the
    -- rule. Its tooltip says that the scan is the shorter for it, and which level the number
    -- comes to for the warrior.
    SetView(false, false)
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top | Hide worse deals | Best armor type for the class | Upgrade at least | " .. LABEL .. " | Weapons > | / | Value by net cost",
        "the line stands after the other number, and before the menu of weapons")
    eq(below:GetChecked(), false, "not ticked until the player ticks it")
    eq(Comes(), ns.Roster.Colored(me, me.name) .. ": From level 20", "its tooltip names the level: 30 less the ten that stand in the field")
    check(ns.L.LEVEL_MIN_TIP:find("Scans get faster too", 1, true) ~= nil, "and says that a scan is faster with it")
    -- No list yet: the box ticked and unticked starts no scan. The first one is the player's.
    below:Click()
    W.Run(1.5)
    below:Click()
    W.Run(1.5)
    eq(Browses(), 0, "nothing scanned yet: the filter starts no scan"); eq(S.state, "idle", "and nothing is under way")
    eq(me.maxBelowOn, nil, "the box is unticked again")
    Scanned()
    eq(Browses(), 1, "the player's scan"); eq(W.AH.calls.browse, 1, "is one search for the rows")
    eq(W.AH.lastQuery.minLevel, nil, "a scan with the box unticked asks for every level")
    check(Row("Old Helm") ~= nil and Row("Edge Belt") ~= nil and Row("Bare Ring") ~= nil and Row("Dull Cloak") ~= nil, "gear of every level is in the list")
    check(Status():find("9 upgrades in 6 slots.", 1, true) ~= nil, "nine upgrades: " .. Status())
    eq(frame.FilterNames:GetText(), "", "no filter is on: nothing beside the field")

    -- The line: a tick box, its words, a field for the number, and the words it goes on with.
    filters:Open()
    local line, number = Line()
    check(number ~= nil and number._kind == "EditBox", "the line has a field for the number")
    eq(number:GetText(), "10", "with ten in it before a number is typed"); eq(line.Tick:IsShown(), false, "and no tick")
    eq(number:GetWidth(), 30, "wide enough for two digits")
    eq(number:IsVisible(), true, "the field is in view")
    eq(number:GetFrameStrata(), "FULLSCREEN_DIALOG", "in the menu's layer, not under its plate")
    check(number:GetFrameLevel() > line:GetFrameLevel(), "above its line")
    eq(number._mouse, true, "and in reach of the mouse")
    eq(Pictures(number, "Inset"), 9, "a recess of ours, like the tick box's")
    check(line._size ~= nil, "the line says how big it is with its field")
    eq(line._size[1], 16 + 7 + line.fontString:GetStringWidth() + 6 + 30 + 4 + #"levels below the character" * 6,"the box, the words, the field and the words after it in a row")
    eq(line._size[2], 20, "as tall as the other lines")

    -- A number typed is asked for at once, and ticks the box. What is made for less than
    -- level 20 leaves the list at once: nothing is looked up, and no scan is asked for.
    local sounds, searches = #W.sounds, W.AH.calls.search
    W.Type(number, "10")
    eq(me.maxBelow, 10, "the number is written on the character's card"); eq(me.maxBelowOn, true, "and asked for")
    eq(line.Tick:IsShown(), true, "the typing ticked the box"); eq(#W.sounds, sounds, "without a click")
    eq(filters._open, true, "the menu stays up"); check(Line() == line, "and its line is the one that was typed into")
    W.Run(0.5)
    eq(Row("Old Helm"), nil, "the helm of level 12 is out"); eq(Row("Edge Belt"), nil, "the belt of level 19")
    eq(Row("Dull Cloak"), nil, "and the cloak whose item says level 12")
    check(Row("Rim Belt") ~= nil and Row("Rim Boots") ~= nil, "what is made for level 20 stays")
    check(Row("Fine Helm") ~= nil and Row("Top Chest") ~= nil and Row("Dim Cloak") ~= nil, "and what is made for more")
    check(Row("Bare Ring") ~= nil, "and the ring that asks for no level: it is not made for a low one")
    eq(frame.FilterNames:GetText(), "From level 20", "the filter is named beside the field, by the level it comes to")
    eq(Status(), "6 upgrades in 6 slots.", "the status line counts what is listed, and says no more")
    eq(W.AH.calls.search, searches, "no item search: every price was known"); eq(S.state, "idle", "and nothing is under way")
    W.Run(1)
    eq(Browses(), 1, "nor is a scan made a moment later: every row that is to be shown was read"); eq(S.state, "idle", "nothing is under way then either")
    filters:Close()
    filters._tooltip(GameTooltip)
    eq(GameTooltip._lines[2].text, "Gear at most 10 levels below the character", "the field's tooltip has the line in full")
    GameTooltip:Hide()

    -- The menu opened again has the number and the tick. A smaller number is narrower.
    filters:Open()
    line, number = Line()
    eq(number:GetText(), "10", "the number is in the field"); eq(line.Tick:IsShown(), true, "and the box is ticked")
    W.Type(number, "5")
    W.Run(0.5)
    eq(Row("Rim Belt"), nil, "five levels: what is made for level 20 is out"); check(Row("Fine Helm") ~= nil, "what is made for 25 stays")
    eq(frame.FilterNames:GetText(), "From level 25", "and the name beside the field says so")
    -- More levels than there are is all of them: gear of every level is offered, the ring
    -- that asks for none as well, and the box is named by the first level. The field shows
    -- what was taken when it is left.
    W.Type(number, "99")
    eq(me.maxBelow, 59, "99 levels typed: 59 are asked for")
    W.Run(0.5)
    check(Row("Old Helm") ~= nil and Row("Bare Ring") ~= nil, "which is every level there is: all nine again")
    eq(ns.Wants.Of(me), nil, "nothing is asked of the gear"); eq(frame.FilterNames:GetText(), "From level 1", "and the ticked box is named by where it reaches")
    W.PressEnter(number)
    eq(number:GetText(), "59", "the field has the number that is kept")
    -- An empty field asks for nothing while the player types. Left empty, it unticks the box
    -- and shows the last number again.
    W.Type(number, "")
    eq(me.maxBelow, 59, "an empty field changes nothing yet"); eq(me.maxBelowOn, true, "the box stays ticked")
    W.PressEnter(number)
    eq(me.maxBelowOn, nil, "left empty: unticked"); eq(line.Tick:IsShown(), false, "the tick goes")
    eq(number:GetText(), "59", "and the last number is back in the field"); eq(me.maxBelow, 59, "kept for the next time")
    W.Type(number, "0")
    eq(me.maxBelowOn, nil, "nought is no number to ask for")
    W.PressEnter(number)
    eq(number:GetText(), "59", "and gives way to the last one")
    filters:Close()
    eq(Comes(), ns.Roster.Colored(me, me.name) .. ": From level 1", "the line's tooltip says where 59 levels reach")
    filters:Open()
    W.Type(select(2, Line()), "10")
    filters:Close()

    -- The tick box itself: a click asks for the number that is in the field.
    eq(below:GetChecked(), true, "ten typed: ticked")
    below:Click()
    eq(me.maxBelowOn, nil, "a click: unticked"); eq(me.maxBelow, 10, "the number stays")
    W.Run(0.5)
    check(Row("Old Helm") ~= nil, "and the list is whole again")
    below:Click()
    eq(me.maxBelowOn, true, "ticked"); eq(me.maxBelow, 10, "with the number that was there")
    W.Run(0.5)
    eq(Row("Old Helm"), nil, "the list is cut at once")

    -- The best set for a budget holds nothing made for less. Eight silver buy the old helm
    -- and the dull cloak; with the filter on, the belt and the boots of level 20.
    local bar = frame.PlanBar
    bar.Check:SetChecked(true)
    bar.Check:Click()
    W.Type(bar.Gold, "0")
    W.Type(bar.Silver, "8")
    Settle()
    check(Row("Rim Belt") ~= nil and Row("Rim Boots") ~= nil, "a set for eight silver: the belt and the boots")
    eq(Row("Old Helm"), nil, "not the helm of level 12, which the money would buy")
    eq(below:IsEnabled(), true, "the box keeps its say in a set"); eq(frame.FilterNames:GetText(), "From level 20", "and its name beside the field")
    below:Click()
    Settle()
    check(Row("Old Helm") ~= nil and Row("Dull Cloak") ~= nil, "unticked: the helm and the cloak of level 12")
    below:Click()
    bar.Check:SetChecked(false)
    bar.Check:Click()
    Settle()

    -- The arrows in the bags do not go by it: an old helm that beats an empty head has its
    -- arrow, whatever level it was made for.
    local old = W.PutInBags(W.Link(500))
    W.OpenBags()
    local arrow = ContainerFrameCombinedBags.Items[old].UpgradeScoutArrow
    check(arrow ~= nil and arrow:IsShown(), "a helm of level 12 in the bags has its arrow with the box ticked")

    -- A scan with the box ticked asks the auction house for level 20 and up. (This one
    -- sends no row that says less, the ring's among them: the scan has read the ring before,
    -- from a search that names no level, and it is in the list.)
    local queries = W.AH.calls.browse
    Scanned()
    eq(W.AH.lastQuery.minLevel, 20, "the scan asks for gear from level 20"); eq(W.AH.lastQuery.maxLevel, 0, "and names no upper level")
    eq(W.AH.calls.browse - queries, 2, "after a search that names no level, for the gear that asks for none")
    eq(Row("Old Helm"), nil, "no helm of level 12"); check(Row("Rim Belt") ~= nil and Row("Dim Cloak") ~= nil, "the gear from level 20 is there")
    check(Row("Bare Ring") ~= nil, "and the ring that asks for no level")
    eq(Status(), "6 upgrades in 6 slots.", "six upgrades, and no more to say")
    local whole = Status()

    -- Made narrower after that scan, or set back to the number it was made with: rows go and
    -- come at once, and nothing is read.
    W.RunUntil(function() return W.AH.ready end, 5)
    browses, searches = Browses(), W.AH.calls.search
    TypeLevels("5")
    W.Run(1)
    eq(Row("Rim Belt"), nil, "five levels: what is made for level 20 is out at once")
    TypeLevels("10")
    W.Run(1)
    check(Row("Rim Belt") ~= nil, "ten levels again: it is back")
    eq(Browses(), browses, "no scan for either: all that is to be shown was read"); eq(S.state, "idle", "and nothing is under way")
    -- Made wider than the scan read, and set back before a second is over: no scan. Nor for
    -- a tick taken off and put back.
    TypeLevels("15")
    eq(frame.FilterNames:GetText(), "From level 15", "fifteen levels: from level 15")
    eq(Row("Edge Belt"), nil, "the belt of level 19 was not read, and is not there")
    TypeLevels("10")
    W.Run(1)
    below:Click()
    W.Run(0.5)
    eq(frame.FilterNames:GetText(), "", "unticked: no filter is on")
    below:Click()
    W.Run(1.5)
    eq(Browses(), browses, "wider, and back within the second: no scan"); eq(S.state, "idle", "nothing is under way")
    eq(W.AH.calls.search, searches, "and nothing was looked up"); eq(Status(), whole, "the status line is as it was")

    -- Made wider and left so: the rows that were not read cannot be shown and no lookup
    -- brings them, so the list is scanned again by itself, a second after the last key.
    -- Nothing is said of it meanwhile. ("15" is two keys: the first, one level, is narrower.)
    filters:Open()
    W.Type(select(2, Line()), "1")
    W.Run(0.3)
    W.Type(select(2, Line()), "15")
    filters:Close()
    W.Run(0.9)
    eq(Browses(), browses, "nothing is read while the player may still be typing"); eq(S.state, "idle", "or under way")
    eq(Row("Edge Belt"), nil, "the belt of level 19 is not there yet"); eq(Status(), whole, "and the status line has no word about it")
    W.Run(0.2)
    eq(Browses(), browses + 1, "a second after the last key the list is scanned again"); check(S.state ~= "idle", "the scan is under way")
    Settle()
    eq(Browses(), browses + 1, "one scan for the two keys"); eq(W.AH.lastQuery.minLevel, 15, "which asks for gear from level 15")
    check(Row("Edge Belt") ~= nil, "the belt of level 19 is listed"); eq(Row("Old Helm"), nil, "the helm of level 12 is not")
    eq(Status(), "7 upgrades in 6 slots.", "seven upgrades")
    -- Unticked: the same, and the scan asks for every level.
    W.RunUntil(function() return W.AH.ready end, 5)
    below:Click()
    W.Run(0.5)
    eq(frame.FilterNames:GetText(), "", "unticked: no filter is on"); eq(Browses(), browses + 1, "no scan at once")
    W.Run(1)
    check(S.state ~= "idle", "a second later a scan is under way")
    Settle()
    eq(Browses(), browses + 2, "one scan"); eq(W.AH.lastQuery.minLevel, nil, "which asks for every level")
    check(Row("Old Helm") ~= nil and Row("Bare Ring") ~= nil, "gear of every level is in the list again")
    eq(Status(), "9 upgrades in 6 slots.", "nine upgrades")
    -- Ticked again: narrower, at once, with nothing read.
    below:Click()
    W.Run(1.5)
    eq(Row("Old Helm"), nil, "ticked again: the helm of level 12 is out at once"); check(Row("Edge Belt") ~= nil, "the belt of level 19 stays: fifteen levels")
    eq(Browses(), browses + 2, "and nothing is read"); eq(S.state, "idle", "or under way")

    -- Two keys that both make it wider are one scan, a second after the last of them. After
    -- a scan made with one level (from level 29), "2" is from level 28 and "20" from level 10.
    TypeLevels("1")
    Scanned()
    eq(W.AH.lastQuery.minLevel, 29, "one level: the scan asks for gear from level 29")
    eq(Status(), "2 upgrades in 2 slots.", "the chest of level 30 is all there is, with the ring that asks for no level")
    W.RunUntil(function() return W.AH.ready end, 5)
    browses = Browses()
    filters:Open()
    W.Type(select(2, Line()), "2")
    W.Run(0.6)
    W.Type(select(2, Line()), "20")
    filters:Close()
    W.Run(0.6)
    eq(Browses(), browses, "more than a second after the first key and less after the last: no scan yet"); eq(S.state, "idle", "nothing is under way")
    W.Run(0.6)
    check(S.state ~= "idle", "a second after the last key a scan is under way")
    Settle()
    eq(Browses(), browses + 1, "one scan, not two"); eq(W.AH.lastQuery.minLevel, 10, "for what stands in the field in the end: from level 10")
    check(Row("Old Helm") ~= nil and Row("Edge Belt") ~= nil, "the helm of level 12 and the belt of level 19 are listed")

    -- A scan keeps the bound it started with. Made wider while one is under way, the filter
    -- has it started over, after the same second: here a scan from level 25, and fifteen
    -- levels typed while it reads.
    TypeLevels("5")
    W.Run(1)
    eq(Browses(), browses + 1, "five levels are narrower: nothing is read")
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ScanButton:Click()
    eq(Browses(), browses + 2, "the player's scan"); eq(S.stats.fromLevel, 25, "reads gear from level 25")
    TypeLevels("15")
    W.Run(0.4)
    check(S.state ~= "idle", "that scan is still under way"); eq(Browses(), browses + 2, "and is the one that is")
    W.Run(0.2)
    eq(Browses(), browses + 3, "a second after the key it is started over"); eq(S.stats.fromLevel, 15, "from level 15")
    check(S.state ~= "idle", "and under way")
    Settle()
    eq(Browses(), browses + 3, "to its end, once"); eq(W.AH.lastQuery.minLevel, 15, "its search asked for gear from level 15")
    check(Row("Edge Belt") ~= nil and Row("Rim Belt") ~= nil, "the belts of level 19 and 20 are listed"); eq(Row("Old Helm"), nil, "the helm of level 12 is not")
    eq(Status(), "7 upgrades in 6 slots.", "seven upgrades, and nothing about a scan that was stopped")

    -- The druid of the account has a box, a number and a level of its own: level 20, and
    -- ten in the field as before any number is typed.
    local druid = UpgradeScoutDB.chars["Alty-Testrealm"]
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ProfileDropdown:Pick(3)
    Settle()
    eq(ns.Roster.Target(), druid, "the lists are for the druid")
    eq(W.AH.lastQuery.minLevel, nil, "the list made for it asks for every level: the warrior's tick is the warrior's")
    eq(below:GetChecked(), false, "its box is not ticked")
    eq(frame.FilterNames:GetText(), "", "and nothing is named beside the field")
    check(Row("Grove Cap") ~= nil and Row("Sprout Cap") ~= nil, "both caps are in its list")
    eq(Comes(), ns.Roster.Colored(druid, "Alty") .. ": From level 10", "its tooltip counts from the druid's level: 20 less ten")
    filters:Open()
    eq(select(2, Line()):GetText(), "10", "ten in its field")
    W.Type(select(2, Line()), "5")
    filters:Close()
    W.Run(0.5)
    eq(druid.maxBelow, 5, "five levels, typed while shopping for the druid, are the druid's"); eq(druid.maxBelowOn, true, "and asked for it")
    eq(me.maxBelow, 15, "the warrior's own number is where it was"); eq(me.maxBelowOn, true, "with its tick")
    eq(frame.FilterNames:GetText(), "From level 15", "the druid's is named beside the field: 20 less five")
    eq(Row("Sprout Cap"), nil, "the cap of level 12 is out at once"); check(Row("Grove Cap") ~= nil, "the cap of level 18 stays")
    Scanned()
    eq(W.AH.lastQuery.minLevel, 15, "the scan for the druid asks for gear from level 15")
    check(Row("Grove Cap") ~= nil, "the cap of level 18 is listed"); eq(Row("Sprout Cap"), nil, "the cap of level 12 is not")
    -- Unticked by whoever shops for the druid: the list made for the druid is short, and is
    -- scanned again by itself as the warrior's own is.
    W.RunUntil(function() return W.AH.ready end, 5)
    browses = Browses()
    below:Click()
    W.Run(0.5)
    eq(druid.maxBelowOn, nil, "unticked on the druid's card"); eq(me.maxBelowOn, true, "the warrior's own tick is where it was")
    eq(Row("Sprout Cap"), nil, "the cap of level 12 was not read, and is not there yet"); eq(Browses(), browses, "nothing is read at once")
    W.Run(1)
    check(S.state ~= "idle", "a second later a scan is under way")
    Settle()
    eq(Browses(), browses + 1, "one scan"); eq(W.AH.lastQuery.minLevel, nil, "which asks for every level")
    eq(ns.Roster.Target(), druid, "for the druid")
    check(Row("Sprout Cap") ~= nil and Row("Grove Cap") ~= nil, "and has the cap of level 12 beside the other")
    -- Back to the warrior: its box is as it was, and the list made for it goes by it.
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ProfileDropdown:Pick(1)
    Settle()
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own again")
    eq(below:GetChecked(), true, "and its box is ticked, as it was"); eq(frame.FilterNames:GetText(), "From level 15", "with its own number")
    eq(W.AH.lastQuery.minLevel, 15, "the scan for the warrior asks for gear from level 15: 30 less its fifteen")

    -- A card out of a saved file with something else where the number and the tick belong:
    -- no tick, the first number, and a scan that asks for every level.
    me.maxBelow, me.maxBelowOn = "ten", "yes"
    ns.UI.Refresh()
    eq(below:GetChecked(), false, "a tick that is none is not shown as one"); eq(frame.FilterNames:GetText(), "", "nor named")
    filters:Open()
    eq(select(2, Line()):GetText(), "10", "the field has the first number")
    filters:Close()
    Scanned()
    eq(W.AH.lastQuery.minLevel, nil, "and the scan asks for every level")
    below:Click()
    eq(me.maxBelowOn, true, "a click ticks it for good")

    -- Where no scan can start when the second is over, nothing is done and nothing said: the
    -- list stays as it is until the player scans. With the question about a purchase up:
    Scanned()
    eq(W.AH.lastQuery.minLevel, 20, "a scan from level 20"); eq(Status(), "6 upgrades in 6 slots.", "with its six upgrades")
    W.RunUntil(function() return W.AH.ready end, 5)
    browses = Browses()
    below:Click()
    eq(me.maxBelowOn, nil, "unticked: the list is short")
    S.Buy(Offer("Rim Belt"))
    eq(S.mode, "buy", "a belt is looked up to be bought"); eq(S.Reread(), false, "which is no time to scan again")
    W.RunUntil(Asking, 30)
    W.Run(1.5)
    eq(Browses(), browses, "nor does a scan take the list from under the question"); check(Asking() ~= nil, "which stands")
    Asking().Cancel:Click()
    W.Run(1.5)
    eq(Browses(), browses, "nor is one made when the question is gone"); eq(S.state, "idle", "nothing is under way")
    eq(Row("Old Helm"), nil, "the list is as it was"); eq(Status(), "6 upgrades in 6 slots.", "and the status line has no word about it")
    -- With the Consumables tab chosen within the second: a scan for gear is not started from
    -- there. (That tab has no such line.)
    below:Click()
    below:Click()
    eq(me.maxBelowOn, nil, "ticked and unticked again: the list is short")
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScoutSupplies")
    W.Run(1.5)
    eq(Browses(), browses, "the other tab in view: no scan for gear"); eq(S.state, "idle", "nothing is under way")
    eq(below:IsShown(), false, "no such line in the menu of the consumables")
    frame.ScanButton:Click()
    eq(S.mode, "supplies", "a scan for consumables is under way"); eq(S.Reread(), false, "and is not stopped for one for gear")
    Settle()
    browses = Browses()
    -- With the auction house closed within the second.
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    W.Run(0.5)
    below:Click()
    below:Click()
    W.CloseAuctionHouse()
    W.Run(1.5)
    eq(Browses(), browses, "the auction house closed: no scan"); eq(S.message, nil, "and no word that it is closed")
    eq(Status(), "6 upgrades in 6 slots.", "the status line is as it was")
end

---------------------------------------------------------------------------
-- The arrows in EllesmereUI's bag windows (Ellesmere.lua)
---------------------------------------------------------------------------
-- The arrow of ours on the button EllesmereUI shows a slot of a bag on, and that button: the
-- one texture there is on the frame it keeps over the icon. No arrow where the slot never
-- had one; neither where the slot is not shown.
local function EllesmereMark(bag, slot)
    local button = W.EllesmereButton(bag, slot)
    local textures = button and button._textOverlay._textures
    return textures and textures[1] or nil, button
end

-- Whether that slot shows the arrow, and whether its arrow is the grey one.
local function EllesmereArrow(bag, slot)
    local arrow = EllesmereMark(bag, slot)
    return arrow ~= nil and arrow:IsShown()
end
local function EllesmereGrey(bag, slot) return (EllesmereMark(bag, slot))._grey end

-- EllesmereUI's windows in place of the game's: its slots have the arrows the game's would
-- have, and it is never asked to draw a window for their sake.
function scenarios.ellesmere()
    StandardWorld()
    -- On the second profile nothing but the two chests has a score.
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.AddItem({ id = 240, name = "Hide Cap", equipLoc = "INVTYPE_HEAD", subClassID = 2, value = 15, level = 9 })
    W.AddItem({ id = 250, name = "Tinker's Bracers", equipLoc = "INVTYPE_WRIST", subClassID = 3, value = 5, level = 5,
        skill = { "Engineering", 150 } })
    W.InstallEllesmere()
    LoadAddon()
    W.Run(1)
    local E = W.ellesmere
    eq(type(EUI_Bags.itemOverlayIcons.UpgradeScout), "function", "EllesmereUI has a function of ours, under the addon's name")
    local listed = 0
    for _ in pairs(EUI_Bags.itemOverlayIcons) do listed = listed + 1 end
    eq(listed, 1, "and that one alone")

    -- What Bags.Arrow is asked about the slots of EllesmereUI's windows.
    local asked = {}
    local Judge = ns.Bags.Arrow
    ns.Bags.Arrow = function(link, where, addon)
        if addon == "ellesmere" then asked[#asked + 1] = { link = link, where = where } end
        return Judge(link, where, addon)
    end
    local function Forget()
        for i = #asked, 1, -1 do asked[i] = nil end
    end

    local slot = {}
    for _, id in ipairs({ 200, 203, 202, 204, 214, 240, 250 }) do slot[id] = W.PutInBags(W.Link(id)) end
    W.bags[5] = { [2] = { link = W.Link(210) } }
    eq(E.refreshes, 0, "its window is closed: it draws nothing"); eq(#asked, 0, "and nothing is judged")
    W.OpenEllesmereBags()
    eq(E.refreshes, 1, "opened, it draws its slots")
    local arrow, button = EllesmereMark(0, slot[200])
    eq(EllesmereArrow(0, slot[200]), true, "a better chest: 18 against 10 on the profile in use")
    eq(arrow._atlas, "bags-greenarrow", "the game's own green arrow"); eq(arrow._grey, false, "green: the character can put it on now")
    eq(arrow:GetParent(), button._textOverlay, "drawn on the frame EllesmereUI keeps over the icon")
    eq(#arrow._points, 2, "held by two of its corners")
    local corner, middle = arrow._points[1], arrow._points[2]
    eq(corner.point .. ">" .. corner.toPoint, "TOPRIGHT>TOPRIGHT", "the top right one in that frame's top right corner")
    eq(corner.to, button._textOverlay, "of that frame"); eq(corner.x .. "," .. corner.y, "-1,-1", "a pixel inside it")
    eq(middle.point .. ">" .. middle.toPoint, "BOTTOMLEFT>CENTER", "the bottom left one in the middle: a quarter of the icon")
    eq(middle.to, button._textOverlay, "of the same frame")
    eq(W.EllesmereWrittenOn(button), "", "nothing is written on EllesmereUI's button")
    eq(EllesmereArrow(0, slot[203]), true, "a better chest above the character's level")
    eq(EllesmereGrey(0, slot[203]), true, "grey: its tooltip says in red that it asks for level 14")
    eq(EllesmereArrow(0, slot[240]), true, "a cap for the empty head")
    eq(EllesmereArrow(0, slot[202]), false, "not a weaker chest"); eq(EllesmereArrow(0, slot[204]), false, "not mail the character has not learned")
    eq(EllesmereArrow(0, slot[250]), false, "not bracers that ask for a profession it has not")
    eq(EllesmereArrow(0, slot[214]), false, "not a potion")
    local _, potion = EllesmereMark(0, slot[214])
    eq(potion._textOverlay._textures, nil, "a slot that never had an arrow gets no texture")
    eq(EllesmereArrow(5, 2), true, "a ring in the reagent bag, for the empty second finger")
    eq(#asked, 8, "every item it drew was judged, once")
    for _, ask in ipairs(asked) do eq(ask.where, nil, "each as an item of the bags") end
    eq(ContainerFrameCombinedBags.Items[slot[200]].UpgradeScoutArrow, nil, "the game's own bag window is closed: nothing is drawn there")

    -- An item leaves the bags. EllesmereUI draws its window again a moment later, and every
    -- item after that one on the button before the one it had.
    local first = button
    local frames = #W.frames
    W.bags[0][slot[200]] = nil
    W.Fire("BAG_UPDATE", 0)
    W.Run(0.2)
    eq(E.refreshes, 2, "the bags changed: EllesmereUI draws its window again")
    eq(W.EllesmereButton(0, slot[203]), first, "the button that had the good chest has the future chest now")
    eq(EllesmereArrow(0, slot[203]), true, "with its arrow"); eq(EllesmereGrey(0, slot[203]), true, "the grey one")
    eq(#first._textOverlay._textures, 1, "which is the texture that was there: none is made for a button that has one")
    eq(EllesmereArrow(0, slot[202]), false, "the next button had the future chest and has the weak one: no arrow")
    eq(#W.frames, frames, "and no frame is made for any of it")

    -- An item the game is still loading gets its arrow once the game has it, with EllesmereUI
    -- drawing nothing for that.
    W.items["201:0"].cached = false
    local robe = W.PutInBags(W.Link(201))
    W.Run(0.2)
    eq(E.refreshes, 3, "a robe comes into the bags: EllesmereUI draws")
    eq(EllesmereArrow(0, robe), false, "no arrow while the game loads the robe")
    W.items["201:0"].cached = true
    W.Run(1.5)
    eq(EllesmereArrow(0, robe), true, "then its arrow"); eq(E.refreshes, 3, "which EllesmereUI was not asked to draw its window for")

    -- Whatever changes the answers puts the arrows right on the slots as EllesmereUI last
    -- drew them. A level up: the chest that asked for level 14.
    local drawn = E.refreshes
    W.player.level = 14
    W.Fire("PLAYER_LEVEL_UP", 14)
    W.Run(2)
    eq(EllesmereArrow(0, slot[203]), true, "a level up: the chest of level 14 keeps its arrow"); eq(EllesmereGrey(0, slot[203]), false, "green now")
    -- A profession learned.
    W.player.professions = { { "Engineering", 150 } }
    W.Fire("SKILL_LINES_CHANGED")
    W.Run(1)
    eq(EllesmereArrow(0, slot[250]), true, "the skills changed: the bracers that asked for the profession")
    -- Mail learned: the game no longer says so in red.
    W.items["204:0"].red = nil
    W.Fire("SPELLS_CHANGED")
    W.Run(1)
    eq(EllesmereArrow(0, slot[204]), true, "the spells changed: the mail, now that it is learned")
    -- Another profile chosen: on the second nothing in the bags has a score.
    W.OpenAuctionHouse()
    UpgradeScoutFrame.ProfileDropdown:Pick(2)
    W.Run(1)
    eq(ns.Roster.Me().profile, "S2", "the second profile chosen")
    eq(EllesmereArrow(0, slot[240]), false, "another profile: the cap loses its arrow"); eq(EllesmereArrow(0, robe), false, "and the robe")
    UpgradeScoutFrame.ProfileDropdown:Pick(1)
    W.Run(1)
    eq(EllesmereArrow(0, slot[240]), true, "and has it again on the first"); eq(EllesmereArrow(0, robe), true, "as the robe has")
    -- The character asks for the best armor of its class alone: mail.
    ns.Wants.SetArmorOnly(ns.Roster.Me(), true)
    W.Run(1)
    eq(EllesmereArrow(0, slot[240]), false, "only the best armor wanted: the leather cap loses its arrow")
    eq(EllesmereArrow(0, slot[204]), true, "the mail keeps its own")
    ns.Wants.SetArmorOnly(ns.Roster.Me(), false)
    W.Run(1)
    eq(EllesmereArrow(0, slot[240]), true, "any armor again: the cap has it back")
    -- New gear: the future chest goes on.
    W.equipped[5] = W.Link(203)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    eq(EllesmereArrow(0, robe), false, "new gear: the robe against the chest now worn, 30 against 60")
    eq(EllesmereArrow(0, slot[204]), false, "and the mail, 40 against 60"); eq(EllesmereArrow(0, slot[240]), true, "the cap still")
    -- The arrows switched off in the welcome window, and on.
    UpgradeScoutDB.arrows = false
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(EllesmereArrow(0, slot[240]), false, "switched off in the welcome window: gone at once")
    eq(E.refreshes, drawn, "and through all of that EllesmereUI was never asked to draw its window")
    EUI_Bags:RefreshInventory()
    eq(EllesmereArrow(0, slot[240]), false, "they stay away when it draws its window again")
    UpgradeScoutDB.arrows = nil
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(EllesmereArrow(0, slot[240]), true, "switched on: back at once")
    eq(E.refreshes, drawn + 1, "with no drawing of EllesmereUI's but its own")

    -- Its window closed: nothing of it is judged, whatever changes. It draws every slot when
    -- it opens, and the arrows are right then.
    W.CloseEllesmereBags()
    Forget()
    W.equipped[5] = W.Link(100)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    eq(#asked, 0, "its window closed: nothing of it is judged for new gear"); eq(E.refreshes, drawn + 1, "and it draws nothing")
    W.OpenEllesmereBags()
    eq(EllesmereArrow(0, robe), true, "opened again: the robe against the old chest worn again, 30 against 10")
    check(#asked > 0, "judged as EllesmereUI drew it")
    -- The whole screen hidden, as the player's key for it does, with the window open: nothing
    -- opens when the screen comes back, so the arrows are put right while it is away.
    UIParent:Hide()
    W.equipped[5] = W.Link(203)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    UIParent:Show()
    eq(EllesmereArrow(0, robe), false, "new gear with the screen hidden: the robe has no arrow when the screen is back")
    UIParent:Hide()
    W.equipped[5] = W.Link(100)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    UIParent:Show()
    eq(EllesmereArrow(0, robe), true, "and has it again after the old chest went on behind the hidden screen")
    eq(E.refreshes, drawn + 2, "EllesmereUI drew nothing for either: it has drawn its window twice by itself, and no more")

    -- Its bank: every slot of the tab is drawn, the empty ones too, and handed over in one
    -- table that is filled anew for each.
    W.bags[6] = { [3] = { link = W.Link(211) }, [4] = { link = W.Link(202) } }
    Forget()
    W.OpenEllesmereBank(6)
    eq(E.bankRefreshes, 1, "the bank opens: EllesmereUI draws it")
    eq(EllesmereArrow(6, 3), true, "the helm in the bank"); eq(EllesmereArrow(6, 4), false, "not the weaker chest in the bank")
    eq(#asked, 2, "the two items in it were judged")
    for _, ask in ipairs(asked) do eq(ask.where, "bank", "each as an item of the bank") end
    local _, empty = EllesmereMark(6, 1)
    check(empty ~= nil and empty._textOverlay._textures == nil, "an empty slot of the bank has a button, and nothing of ours on it")
    local _, helm = EllesmereMark(6, 3)
    eq(W.EllesmereWrittenOn(helm), "", "nothing is written on a button of the bank either")
    -- EllesmereUI's table has gone on to the last slot, an empty one. What the arrows are
    -- put right from is not that table.
    UpgradeScoutDB.arrows = false
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(EllesmereArrow(6, 3), false, "switched off: gone from the bank too")
    UpgradeScoutDB.arrows = nil
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(EllesmereArrow(6, 3), true, "switched on: the helm has its arrow, from what was kept of its slot")
    eq(EllesmereArrow(6, 4), false, "and the weaker chest none"); eq(E.bankRefreshes, 1, "with the bank not drawn again")
    -- The helm is taken out.
    W.bags[6][3] = nil
    EUI_BankFrame:RefreshBank()
    eq(EllesmereArrow(6, 3), false, "the helm taken out: its slot is empty, and has no arrow")
    eq(#helm._textOverlay._textures, 1, "the texture stays for what the slot holds next")
    W.CloseEllesmereBank()
end

-- No EllesmereUI: nothing is looked for twice, nothing fails, and the game's own windows have
-- their arrows. Nor does an EllesmereUI that has no place for other addons get anything.
function scenarios.ellesmere_absent()
    StandardWorld()
    LoadAddon()
    W.Run(1)
    eq(EUI_Bags, nil, "there is no EllesmereUI")
    W.AddOnLoaded("SomeOtherAddon")
    local chest = W.PutInBags(W.Link(200))
    W.OpenBags()
    local arrow = ContainerFrameCombinedBags.Items[chest].UpgradeScoutArrow
    check(arrow ~= nil and arrow:IsShown(), "the game's own bag window has its arrow on the better chest")
    eq(arrow._points[1].point, "TOPLEFT", "in the top left corner, where the game has it")
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1)
    UpgradeScoutDB.arrows = false
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(arrow:IsShown(), false, "switched off, it goes")
    UpgradeScoutDB.arrows = nil
    ns.Fire("SETTING_CHANGED", "arrows")
    eq(arrow:IsShown(), true, "and comes back: the arrows are put right with no window of another addon to look at")

    -- An EllesmereUI from before it kept a place for other addons: its bag window, with no
    -- function to give ours to.
    EUI_Bags = W.Widget("Frame", "EUI_MainBagFrame", UIParent)
    W.AddOnLoaded("EllesmereUIBags")
    eq(EUI_Bags.itemOverlayIcons, nil, "an EllesmereUI too old to take a function is given none")
    eq(#W.errors, 0, "and nothing of this is an error")
end

-- EllesmereUI's Bags module loaded after the addon: it is given our function when it has
-- loaded, once.
function scenarios.ellesmere_late()
    StandardWorld()
    LoadAddon()
    W.Run(1)
    local chest = W.PutInBags(W.Link(200))
    W.AddOnLoaded("SomeOtherAddon")
    eq(EUI_Bags, nil, "EllesmereUI has not loaded yet")
    W.InstallEllesmere()
    eq(type(EUI_Bags.itemOverlayIcons.UpgradeScout), "function", "loaded after the addon: it is given our function then")
    W.OpenEllesmereBags()
    eq(EllesmereArrow(0, chest), true, "and its slots have their arrows")
    -- What loads after that is nothing to it.
    local given = 0
    local Register = EUI_Bags.RegisterItemOverlayIcon
    EUI_Bags.RegisterItemOverlayIcon = function(name, func)
        given = given + 1
        Register(name, func)
    end
    W.AddOnLoaded("YetAnotherAddon")
    eq(given, 0, "the function is given once: an addon loaded later changes nothing")
    W.bags[0][chest] = nil
    W.Fire("BAG_UPDATE", 0)
    W.Run(0.2)
    eq(EllesmereArrow(0, chest), false, "the chest gone from the bags: so is its slot")
end

-- Forever Leveling BiS scores and draws its own arrows. On EllesmereUI's slots it draws on
-- every one, those of the bank too: none of ours beside them, in the bags or in the bank.
function scenarios.ellesmere_leveling()
    StandardWorld()
    W.items["200:0"].value2, W.items["100:0"].value2 = 9, 12
    W.items["212:0"].value2 = 40
    LevelingWorld()
    -- It was chosen in an earlier session.
    UpgradeScoutDB = { engine = "leveling" }
    W.InstallEllesmere()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local E, kept = W.ellesmere, ForeverLevelingBiSDB
    eq(ns.Score.Engine(), "leveling", "Forever Leveling BiS scores, as chosen before")

    local asked = {}
    local Judge = ns.Bags.Arrow
    ns.Bags.Arrow = function(link, where, addon)
        if addon == "ellesmere" then asked[#asked + 1] = where or "bags" end
        return Judge(link, where, addon)
    end
    local slot = {}
    for _, id in ipairs({ 200, 203, 212, 202 }) do slot[id] = W.PutInBags(W.Link(id)) end
    W.bags[6] = { [3] = { link = W.Link(211) }, [4] = { link = W.Link(202) } }
    W.OpenEllesmereBags()
    W.OpenEllesmereBank(6)
    W.Run(1)
    eq(table.concat(asked, " "), "bags bags bags bags bank bank", "every slot is asked about as what it is: of the bags, or of the bank")
    eq(EllesmereArrow(0, slot[200]), false, "a better chest: no arrow of ours, Forever Leveling BiS draws its own")
    eq(EllesmereArrow(0, slot[203]), false, "nor on one of a higher level"); eq(EllesmereArrow(0, slot[212]), false, "nor on a two-hander")
    eq(EllesmereArrow(6, 3), false, "nor on the helm in EllesmereUI's bank: there it draws as well")
    eq(Judge(W.Link(211), "bank"), "now", "in the game's own bank, where it draws none, ours stay")
    eq(Judge(W.Link(211), "bank", "ellesmere"), false, "and in EllesmereUI's they do not")

    -- Its arrows switched off in its settings: ours are drawn, by its score, in both windows.
    local drawn, bankDrawn = E.refreshes, E.bankRefreshes
    kept.bagMarks = false
    W.LevelingChanged()
    W.Run(1)
    eq(EllesmereArrow(0, slot[200]), true, "its own arrows switched off: ours, on a better chest, 18 against 10 by its score")
    eq(EllesmereGrey(0, slot[200]), false, "green: it can be put on now")
    eq(EllesmereArrow(0, slot[203]), true, "a better chest of a higher level"); eq(EllesmereGrey(0, slot[203]), true, "grey")
    eq(EllesmereArrow(0, slot[212]), true, "a two-hander against the sword"); eq(EllesmereArrow(0, slot[202]), false, "not a weaker chest")
    eq(EllesmereArrow(6, 3), true, "the helm in the bank"); eq(EllesmereArrow(6, 4), false, "not the weaker chest in the bank")
    -- Another main spec chosen in Forever Leveling BiS: the arrows follow.
    W.LevelingChar().spec = "fury"
    W.LevelingChanged()
    W.Run(1)
    eq(EllesmereArrow(0, slot[200]), false, "for the other spec the chest is no upgrade: 9 against 12")
    eq(EllesmereArrow(0, slot[212]), true, "and the two-hander is one: 40 against nothing")
    W.LevelingChar().spec = nil
    W.LevelingChanged()
    W.Run(1)
    eq(EllesmereArrow(0, slot[200]), true, "back on the first spec the chest has its arrow")
    -- Its arrows switched on again: ours go, from the bank too.
    kept.bagMarks = nil
    W.LevelingChanged()
    W.Run(1)
    eq(EllesmereArrow(0, slot[200]), false, "its arrows switched on again: ours go from the bags")
    eq(EllesmereArrow(6, 3), false, "and from the bank")
    eq(E.refreshes, drawn, "with EllesmereUI never asked to draw its bag window"); eq(E.bankRefreshes, bankDrawn, "or its bank")
end

-- Forever Companion scores and draws its own arrows: none of ours on EllesmereUI's slots
-- while it does, as on the game's.
function scenarios.ellesmere_companion()
    StandardWorld()
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    CompanionWorld()
    -- It was chosen in an earlier session.
    UpgradeScoutDB = { engine = "companion" }
    W.InstallEllesmere()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local E, options = W.ellesmere, ForeverCompanion.db.global
    eq(ns.Score.Engine(), "companion", "Forever Companion scores, as chosen before")

    local chest = W.PutInBags(W.Link(200))
    W.bags[6] = { [3] = { link = W.Link(211) } }
    W.OpenEllesmereBags()
    W.OpenEllesmereBank(6)
    W.Run(1)
    eq(EllesmereArrow(0, chest), false, "a better chest: no arrow of ours while Forever Companion draws its own")
    eq(EllesmereArrow(6, 3), false, "nor on the helm in the bank")
    local drawn, bankDrawn = E.refreshes, E.bankRefreshes
    options.scale_arrows = false
    W.CompanionChanged()
    W.Run(1)
    eq(EllesmereArrow(0, chest), true, "its arrows switched off in its options: ours, on its scale")
    eq(EllesmereArrow(6, 3), true, "in the bank too")
    options.scale_arrows = nil
    W.CompanionChanged()
    W.Run(1)
    eq(EllesmereArrow(0, chest), false, "and on again: ours go"); eq(EllesmereArrow(6, 3), false, "from the bank too")
    eq(E.refreshes, drawn, "with EllesmereUI never asked to draw its bag window"); eq(E.bankRefreshes, bankDrawn, "or its bank")
end

---------------------------------------------------------------------------
-- Weapons: how a character fills its hands, and the kinds of weapon it is offered
---------------------------------------------------------------------------
-- Profiles by the names the addon's own have for a warrior's and a paladin's Protection, on
-- which a character that has not chosen is offered a weapon for one hand and a shield
-- (Wants.Hands), and profiles for a paladin, a rogue and a warlock, which the tests' weights
-- have none for. A warrior's Protection scores as the tests' second profile does (`value2`);
-- the others each by a stat of their own (an item's `values`: PP, PR, R1, L1).
local function MoreProfiles()
    moreWeights = function(data)
        data.classes.WARRIOR = { "S1", "WARRIOR_PROTECTION" }
        data.classes.PALADIN = { "PALADIN_HOLY", "PALADIN_PROTECTION", "PALADIN_RETRIBUTION" }
        data.classes.ROGUE = { "R1" }
        data.classes.WARLOCK = { "L1" }
        data.start.PALADIN, data.start.ROGUE, data.start.WARLOCK = "PALADIN_RETRIBUTION", "R1", "L1"
        local titles = data.titles.enUS
        titles.WARRIOR_PROTECTION, titles.PALADIN_HOLY, titles.PALADIN_PROTECTION = "Protection", "Holy", "Protection"
        titles.PALADIN_RETRIBUTION, titles.R1, titles.L1 = "Retribution", "Combat", "Affliction"
        data.profiles.WARRIOR_PROTECTION = { class = "WARRIOR", weights = { TEST_S2 = 1 } }
        data.profiles.PALADIN_HOLY = { class = "PALADIN", weights = { TEST_PH = 1 } }
        data.profiles.PALADIN_PROTECTION = { class = "PALADIN", weights = { TEST_PP = 1 } }
        data.profiles.PALADIN_RETRIBUTION = { class = "PALADIN", weights = { TEST_PR = 1 } }
        data.profiles.R1 = { class = "ROGUE", weights = { TEST_R1 = 1 } }
        data.profiles.L1 = { class = "WARLOCK", weights = { TEST_L1 = 1 } }
    end
end

-- An item put up for sale.
local function Sell(def, price)
    W.AddItem(def)
    W.AddAuction(def.id, price)
    return def
end

-- Where an item for the hands is offered, for every way the hands are held and every way the
-- character says it fills them (Compare.Place by the choice, and what Wants.Keep leaves of
-- it): the table of the whole matter.
function scenarios.hands()
    LoadAddon()
    local Compare, Wants = ns.Compare, ns.Wants
    local function Worn(id, invType, value)
        return { link = "worn" .. id, itemID = id, invType = invType, value = value }
    end
    -- What is held: a two-hander (30); a sword (20) and a shield (7); two swords (20 and 8);
    -- nothing.
    local HELD = {
        two = { [16] = Worn(1, "INVTYPE_2HWEAPON", 30) },
        shield = { [16] = Worn(1, "INVTYPE_WEAPON", 20), [17] = Worn(2, "INVTYPE_SHIELD", 7) },
        pair = { [16] = Worn(1, "INVTYPE_WEAPON", 20), [17] = Worn(2, "INVTYPE_WEAPON", 8) },
        none = {},
    }
    local function Ctx(held, dualWield, more)
        local ctx = { equipped = HELD[held], dualWield = dualWield }
        for key, value in pairs(more or {}) do ctx[key] = value end
        return ctx
    end
    -- An item for sale: a two-hander is worth 60, anything else 40, unless said.
    local function Item(kind, value)
        return { link = "sale" .. kind, itemID = 9, invType = "INVTYPE_" .. kind, value = value or (kind == "2HWEAPON" and 60 or 40) }
    end
    -- What the list has of it: each place as "hand +gain note"; "unwanted" where it is an
    -- upgrade that the choice leaves out, which the list counts; "" where it has no place.
    local function Listed(ctx, hands, item)
        local wants = hands ~= "ANY" and { hands = hands } or nil
        local placements = Compare.Place(item, ctx, wants and wants.hands)
        local kept = Wants.Keep(wants, item, placements)
        if #placements > 0 and #kept == 0 then return "unwanted" end
        local out = {}
        for _, placement in ipairs(kept) do
            out[#out + 1] = (placement.group == "MAINHAND" and "main" or "off") .. " +" .. ("%g"):format(placement.delta)
                .. (placement.note and " " .. placement.note or "")
        end
        return table.concat(out, ", ")
    end
    local EMPTY, NEEDS = "main +10 OFFHAND_EMPTY", "off +40 NEEDS_ONE_HAND"
    -- (For one that holds a two-hander and goes over to one hand: a weapon for one hand at
    -- its own worth, 40, and not at the 10 it has over the two-hander.)
    local REPLACES = "main +40 REPLACES_TWO_HAND"
    -- For each way of holding, and one who can hold two weapons or cannot: what "Any",
    -- "Two-hand" and "One-hand, shield and off-hand" make of each kind of item.
    local TABLE = {
        { "two", false, {
            ["2HWEAPON"] = { "main +30", "main +30", "unwanted" },
            WEAPON = { EMPTY, "unwanted", REPLACES },
            WEAPONMAINHAND = { EMPTY, "unwanted", REPLACES },
            WEAPONOFFHAND = { "", "", "" },
            SHIELD = { "", "", NEEDS },
            HOLDABLE = { "", "", NEEDS },
        } },
        { "two", true, {
            ["2HWEAPON"] = { "main +30", "main +30", "unwanted" },
            WEAPON = { EMPTY, "unwanted", REPLACES .. ", " .. NEEDS },
            WEAPONMAINHAND = { EMPTY, "unwanted", REPLACES },
            WEAPONOFFHAND = { "", "", NEEDS },
            SHIELD = { "", "", NEEDS },
            HOLDABLE = { "", "", NEEDS },
        } },
        { "shield", false, {
            ["2HWEAPON"] = { "main +33 BOTH_HANDS", "main +33 BOTH_HANDS", "unwanted" },
            WEAPON = { "main +20", "unwanted", "main +20" },
            WEAPONMAINHAND = { "main +20", "unwanted", "main +20" },
            WEAPONOFFHAND = { "", "", "" },
            SHIELD = { "off +33", "unwanted", "off +33" },
            HOLDABLE = { "off +33", "unwanted", "off +33" },
        } },
        { "shield", true, {
            ["2HWEAPON"] = { "main +33 BOTH_HANDS", "main +33 BOTH_HANDS", "unwanted" },
            WEAPON = { "main +20, off +33", "unwanted", "main +20, off +33" },
            WEAPONMAINHAND = { "main +20", "unwanted", "main +20" },
            WEAPONOFFHAND = { "off +33", "unwanted", "off +33" },
            SHIELD = { "off +33", "unwanted", "off +33" },
            HOLDABLE = { "off +33", "unwanted", "off +33" },
        } },
        { "pair", true, {
            ["2HWEAPON"] = { "main +32 BOTH_HANDS", "main +32 BOTH_HANDS", "unwanted" },
            WEAPON = { "main +20, off +32", "unwanted", "main +20, off +32" },
            WEAPONMAINHAND = { "main +20", "unwanted", "main +20" },
            WEAPONOFFHAND = { "off +32", "unwanted", "off +32" },
            SHIELD = { "off +32", "unwanted", "off +32" },
            HOLDABLE = { "off +32", "unwanted", "off +32" },
        } },
        { "none", false, {
            ["2HWEAPON"] = { "main +60", "main +60", "unwanted" },
            WEAPON = { "main +40", "unwanted", "main +40" },
            WEAPONMAINHAND = { "main +40", "unwanted", "main +40" },
            WEAPONOFFHAND = { "", "", "" },
            SHIELD = { "off +40", "unwanted", "off +40" },
            HOLDABLE = { "off +40", "unwanted", "off +40" },
        } },
        { "none", true, {
            ["2HWEAPON"] = { "main +60", "main +60", "unwanted" },
            WEAPON = { "main +40, off +40", "unwanted", "main +40, off +40" },
            WEAPONMAINHAND = { "main +40", "unwanted", "main +40" },
            WEAPONOFFHAND = { "off +40", "unwanted", "off +40" },
            SHIELD = { "off +40", "unwanted", "off +40" },
            HOLDABLE = { "off +40", "unwanted", "off +40" },
        } },
    }
    local cases = 0
    for _, row in ipairs(TABLE) do
        local held, dualWield, expected = row[1], row[2], row[3]
        for kind, byChoice in pairs(expected) do
            for i, hands in ipairs(Wants.HANDS) do
                cases = cases + 1
                eq(Listed(Ctx(held, dualWield), hands, Item(kind)), byChoice[i],
                    ("holding %s%s, %s, the list set to %s"):format(held, dualWield and " (can hold two weapons)" or "", kind, hands))
            end
        end
    end
    eq(cases, 7 * 6 * 3, "every case of the table was asked"); eq(table.concat(Wants.HANDS, " "), "ANY TWO ONE", "the three choices, in the menu's order")

    -- The off hand beside a two-hander, for one going over to a weapon for one hand: the item
    -- goes into it as into an empty slot. Its gain is its own worth, with no percent to it,
    -- and nothing comes off: what the hands gain in all is for the weapon to come to decide.
    local two = Ctx("two", false)
    local place = Compare.Place(Item("SHIELD", 9), two, "ONE")[1]
    eq(place.group, "OFFHAND", "a shield beside a two-hander goes to the off hand"); eq(place.slot, 17, "its slot")
    near(place.delta, 9, "for what it is worth"); near(place.base, 0, "against nothing")
    eq(place.percent, nil, "no percent is claimed"); eq(place.replaced, nil, "and the two-hander is not said to come off for it")
    eq(place.note, "NEEDS_ONE_HAND", "the row says what it takes")
    eq(#Compare.Place(Item("SHIELD", 9), two), 0, "without the choice it has no place, as ever")
    eq(#Compare.Place(Item("SHIELD", 9), two, "TWO"), 0, "nor for one who keeps to two-handers")
    eq(#Compare.Place(Item("SHIELD", 9), two, "ANY"), 0, "nor by any name that is not that choice")
    eq(#Compare.Place(Item("SHIELD", 0), two, "ONE"), 0, "a shield worth nothing is no upgrade there either")
    -- The main hand of the same character, the mirror of that: a weapon for one hand goes
    -- into it as into a hand without the two-hander, which the choice leaves out. Its gain
    -- is its own worth, with no percent, whether it beats the two-hander (30) or not, and
    -- the two-hander is said to come off.
    place = Compare.Place(Item("WEAPON", 25), two, "ONE")[1]
    eq(place.group, "MAINHAND", "a sword weaker than the two-hander goes to the main hand"); eq(place.slot, 16, "its slot")
    near(place.delta, 25, "for what it is worth"); near(place.base, 0, "against no weapon"); eq(place.percent, nil, "no percent is claimed")
    eq(#place.replaced, 1, "one item comes off"); eq(place.replaced[1], "worn1", "the two-hander")
    eq(place.note, "REPLACES_TWO_HAND", "and the row says so")
    eq(#Compare.Place(Item("WEAPON", 25), two, "ONE"), 1, "one who cannot hold two is offered it for that hand alone")
    place = Compare.Place(Item("WEAPONMAINHAND", 33), two, "ONE")[1]
    near(place.delta, 33, "a stronger one the same: its worth, and not the 3 it has over the two-hander"); eq(place.percent, nil, "nor a share of it")
    eq(place.note, "REPLACES_TWO_HAND", "with the same note")
    eq(#Compare.Place(Item("WEAPON", 0), two, "ONE"), 0, "a sword worth nothing is no upgrade there either")
    -- Without that choice it is measured against the two-hander as it always was: the gain a
    -- share of what the hands hold now, and a weaker one no upgrade.
    place = Compare.Place(Item("WEAPON", 33), two)[1]
    near(place.delta, 3, "no choice: a sword against the two-hander"); near(place.percent, 0.1, "a share of it"); eq(place.replaced[1], "worn1", "which comes off")
    eq(place.note, "OFFHAND_EMPTY", "with the note it always had")
    eq(#Compare.Place(Item("WEAPON", 25), two), 0, "and a weaker sword is not offered"); eq(#Compare.Place(Item("WEAPON", 25), two, "ANY"), 0, "nor by any way chosen")
    eq(#Compare.Place(Item("WEAPON", 25), two, "TWO"), 0, "nor for one who keeps to two-handers")
    -- One who can hold two is offered a sword for either hand, each as it will be.
    local both = Compare.Place(Item("WEAPON", 25), Ctx("two", true), "ONE")
    eq(#both, 2, "one who can hold two is offered it for both hands")
    eq(both[1].group, "MAINHAND", "the main hand"); eq(both[1].note, "REPLACES_TWO_HAND", "in the two-hander's place"); near(both[1].delta, 25, "at its worth")
    eq(both[2].group, "OFFHAND", "and the off hand"); eq(both[2].note, "NEEDS_ONE_HAND", "with its note"); eq(both[2].replaced, nil, "where nothing comes off")
    -- With a sword and a shield held, the choice changes no place and no number.
    place = Compare.Place(Item("WEAPON", 24), Ctx("shield", false), "ONE")[1]
    near(place.percent, 4 / 27, "a sword against a sword: still a share of both hands"); eq(place.note, nil, "and no note")
    eq(#Compare.Place(Item("WEAPON", 15), Ctx("shield", false), "ONE"), 0, "and a sword weaker than the one held is no upgrade")

    -- A second copy of a unique item has no place, in the freed off hand as anywhere.
    local unique = Item("SHIELD")
    unique.unique, unique.itemID = true, 1
    eq(#Compare.Place(unique, two, "ONE"), 0, "the unique rule holds there")
    unique.itemID = 9
    eq(#Compare.Place(unique, two, "ONE"), 1, "a unique shield that is not worn is offered")

    -- Every place, upgrade or not, and the one place asked about (the lines of a row's
    -- tooltip for the other profiles).
    eq(#Compare.Gains(Item("SHIELD", 0), two, "ONE"), 1, "every place, upgrade or not: the off hand by the choice")
    eq(#Compare.Gains(Item("SHIELD", 0), two), 0, "and none without it")
    near(Compare.Gain(Item("HOLDABLE", 6), two, "OFFHAND", "ONE").delta, 6, "the gain in the off hand, asked for by the choice")
    eq(Compare.Gain(Item("HOLDABLE", 6), two, "OFFHAND"), nil, "which is no place without it")
    near(Compare.Gain(Item("WEAPON", 25), two, "MAINHAND", "ONE").delta, 25, "the gain in the main hand by the choice: the sword's worth")
    near(Compare.Gain(Item("WEAPON", 25), two, "MAINHAND").delta, -5, "and without it what it loses to the two-hander")

    -- What a scan keeps: whatever some choice has a place for.
    eq(Compare.Possible(Item("SHIELD"), two), true, "a shield beside a two-hander is kept: one choice has a place for it")
    eq(Compare.Possible(Item("2HWEAPON"), two), true, "a better two-hander is kept")
    eq(Compare.Possible(Item("WEAPON", 25), two), true, "a sword weaker than the two-hander is kept: one hand has a place for it")
    eq(Compare.Possible(Item("WEAPONMAINHAND", 25), two), true, "a main-hand weapon the same")
    eq(Compare.Possible(Item("WEAPON", 0), two), false, "a sword worth nothing is not")
    eq(Compare.Possible(Item("WEAPONOFFHAND"), two), false, "an off-hand weapon is not for one who cannot hold two")
    eq(Compare.Possible(Item("SHIELD", 5), Ctx("shield", false)), false, "a weaker shield than the one held is not kept")
    eq(Compare.Possible(Item("WEAPON", 15), Ctx("shield", false)), false, "nor a weaker sword than the one held: there is no two-hander to take the place of")

    -- Another addon's say stands beside the choice, and the stricter of the two holds.
    eq(Listed(Ctx("two", false, { show1H = false }), "ONE", Item("SHIELD")), "", "a scale that shows nothing for one hand: no shield, whatever the choice")
    eq(Listed(Ctx("two", false, { show1H = false }), "ONE", Item("WEAPON")), "", "and no sword in the two-hander's place")
    eq(Listed(Ctx("two", false, { show1H = false }), "ONE", Item("2HWEAPON")), "unwanted", "and the choice leaves the two-handers out")
    eq(Listed(Ctx("shield", false, { show2H = false }), "ANY", Item("2HWEAPON")), "", "a scale that shows no two-handers")
    eq(Listed(Ctx("shield", false, { show2H = false }), "TWO", Item("SHIELD")), "unwanted", "with a choice of two-handers: nothing for the hands at all")
    -- The addon that scores is told when the off hand is asked about as free of a
    -- two-hander, and what it says of that hand holds.
    local asked = {}
    local function Says(main, off)
        return function(item, offFree)
            asked[#asked + 1] = offFree
            return main, off
        end
    end
    eq(Listed(Ctx("two", false, { hands = Says(nil, false) }), "ONE", Item("SHIELD")), "", "it says the item has no place in that hand")
    eq(asked[#asked], true, "asked about the off hand as free")
    eq(Listed(Ctx("two", false, { hands = Says(nil, 5) }), "ONE", Item("SHIELD")), "off +5 NEEDS_ONE_HAND", "or the most it gains there")
    eq(Listed(Ctx("two", false, { hands = Says(nil, nil) }), "ANY", Item("2HWEAPON")), "main +30", "without the choice")
    eq(asked[#asked], false, "it is asked as before")
    eq(Listed(Ctx("shield", false, { hands = Says(nil, nil) }), "ONE", Item("SHIELD")), "off +33", "and with a shield held")
    eq(asked[#asked], false, "the off hand is what it is")
    -- What such an addon says a weapon gains, it says against the two-hander held: where it
    -- has a say, the main hand is measured against that as ever, and no row says more.
    eq(Listed(Ctx("two", false, { hands = Says(nil, nil) }), "ONE", Item("WEAPON")), EMPTY, "with its say on the hands, a sword is measured against the two-hander")
    eq(Listed(Ctx("two", false, { hands = Says(nil, nil) }), "ONE", Item("WEAPON", 25)), "", "and a weaker one has no place")
    eq(Listed(Ctx("two", false, { hands = Says(4, nil) }), "ONE", Item("WEAPON")), "main +4 OFFHAND_EMPTY", "the most it says the sword gains holds")
    eq(Listed(Ctx("two", false, { hands = Says(false, nil) }), "ONE", Item("WEAPON")), "", "and so does its no")

    -- What the choice leaves out, item by item (Wants.Fits): what is held in the hands, and
    -- nothing else.
    local ONE, TWO = { hands = "ONE" }, { hands = "TWO" }
    eq(Wants.Fits(ONE, { invType = "INVTYPE_2HWEAPON" }), false, "one hand: no two-hander")
    eq(Wants.Fits(TWO, { invType = "INVTYPE_2HWEAPON" }), true, "two hands: a two-hander")
    for _, kind in ipairs({ "WEAPON", "WEAPONMAINHAND", "WEAPONOFFHAND", "SHIELD", "HOLDABLE" }) do
        eq(Wants.Fits(ONE, { invType = "INVTYPE_" .. kind }), true, "one hand: " .. kind)
        eq(Wants.Fits(TWO, { invType = "INVTYPE_" .. kind }), false, "two hands: no " .. kind)
    end
    for _, kind in ipairs({ "RANGED", "RANGEDRIGHT", "THROWN", "RELIC", "HEAD", "FINGER", "TRINKET" }) do
        check(Wants.Fits(ONE, { invType = "INVTYPE_" .. kind }) and Wants.Fits(TWO, { invType = "INVTYPE_" .. kind }),
            "what is not held in the hands is no matter of the choice: " .. kind)
    end
    eq(Wants.Fits(ONE, {}), true, "nor is an item that does not say how it is worn")

    -- The best set for a budget fills the hands as they can be held, and as the list fills
    -- them. For one that holds a two-hander (30) and goes over to one hand: a sword is in
    -- a set at its own worth, as its row has it, whether it beats the two-hander (36) or not
    -- (25), with a shield (12) beside it or by itself; a shield alone is no set, whatever it
    -- is worth and whatever the money, as it cannot be held beside the two-hander. Without
    -- the choice the two-hander (45) is the set.
    local Plan = ns.Plan
    local function For(id, kind, value, buyout)
        return { id = "o" .. id, itemID = id, invType = "INVTYPE_" .. kind, value = value, buyout = buyout, link = "link" .. id,
            name = "Item " .. id, count = 1 }
    end
    local function Best(offers, ctx, wants, budget)
        budget = budget or 100000
        local rows = Plan.Rows(Plan.Choose(Plan.Ladder(offers, ctx, budget, wants), budget))
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then
                out[#out + 1] = row.entry.offer.itemID .. ":+" .. ("%g"):format(row.entry.delta) .. (row.entry.note and " " .. row.entry.note or "")
            end
        end
        return table.concat(out, " ")
    end
    local offers = {}
    for _, offer in ipairs({ For(31, "2HWEAPON", 45, 3000), For(32, "WEAPON", 36, 2000), For(33, "SHIELD", 12, 800), For(34, "HOLDABLE", 5, 300) }) do
        offers[offer.id] = offer
    end
    eq(Best(offers, two, nil), "31:+15", "no choice: the two-hander, and no shield, which the list has no row for")
    eq(Best(offers, two, ONE), "32:+36 REPLACES_TWO_HAND 33:+12", "one hand: the sword in the two-hander's place, at its own worth, and the shield beside it")
    eq(Best(offers, two, TWO), "31:+15", "two hands: the two-hander")
    eq(Best(offers, two, ONE, 1000), "", "one hand, and money for the shield alone: a shield by itself is no set")
    offers.o32 = nil
    eq(Best(offers, two, ONE), "", "one hand, and no sword for sale: a shield alone is no set, for all the money")
    offers.o35 = For(35, "WEAPON", 25, 1500)
    eq(Best(offers, two, nil), "31:+15", "a sword weaker than the two-hander: no choice, and it is in no set")
    eq(Best(offers, two, ONE), "35:+25 REPLACES_TWO_HAND 33:+12", "one hand: it is in the set as it is in the list, and the shield beside it")
    eq(Best(offers, two, ONE, 1700), "35:+25 REPLACES_TWO_HAND", "with money for nothing beside it, the sword is a set by itself")
    eq(Best(offers, Ctx("two", true), ONE, 1700), "35:+25 REPLACES_TWO_HAND", "one who can hold two: by itself it goes into the main hand, which can be held so")
    offers.o35 = nil
    -- A shield bought and not yet held counts as held by one who goes over to one hand: a
    -- sword is then measured as it will be worn, and a second shield against the first.
    local bought = { { link = "bought", itemID = 33, invType = "INVTYPE_SHIELD", value = 12 } }
    local wearing = Plan.Wearing(two, bought, "ONE")
    eq(wearing.equipped[17].link, "bought", "the shield bought counts as held")
    eq(two.equipped[17], nil, "in a copy of the gear")
    eq(Plan.Wearing(two, bought).equipped[17], nil, "and not for one who has not said it goes that way")
    place = Compare.Place(Item("SHIELD", 15), wearing, "ONE")[1]
    near(place.delta, 3, "another shield is worth what it adds to that one"); eq(place.replaced[1], "bought", "which it would replace")
    eq(place.note, "NEEDS_ONE_HAND", "and still asks for a weapon for one hand")
    unique.itemID = 33
    eq(#Compare.Place(unique, wearing, "ONE"), 0, "a second copy of a unique shield that was bought is not offered")
    -- So does a sword bought, in the two-hander's place, though it does not beat it: the
    -- next sword is measured against that one.
    local blade = { { link = "blade", itemID = 35, invType = "INVTYPE_WEAPON", value = 25 } }
    eq(Plan.Wearing(two, blade, "ONE").equipped[16].link, "blade", "a sword bought by one going over to one hand counts as held")
    eq(Plan.Wearing(two, blade).equipped[16].link, "worn1", "and not for one who has not said so: the two-hander is the better")
    place = Compare.Place(Item("WEAPON", 28), Plan.Wearing(two, blade, "ONE"), "ONE")[1]
    near(place.delta, 3, "another sword is worth what it adds to that one"); eq(place.note, nil, "with no two-hander to note")
end

-- What a test of a scan asks of it, as the scenario of the wants does. Each for the scan
-- that stands, and for the character it was made for.
--   Scan()    a scan to its end; returns how many item searches it sent
--   More()    the prices the list has come to need and lacks; returns how many searches
--   Shown()   the upgrades the list shows with the tab's own filters off, by name; how many
--             the character's filters leave out; and the list's entries by the item's name
--   Set()     the best set for all the gold there is, as "name +gain" in the list's order
local function ScanTools()
    local S = ns.Scanner
    local tools = {}
    local function Owner()
        return S.ctx and S.ctx.who or ns.Roster.Me()
    end
    function tools.Scan()
        W.RunUntil(function() return W.AH.ready end, 5)
        local before = W.AH.calls.search
        ScanToEnd()
        return W.AH.calls.search - before
    end
    function tools.More()
        local before = W.AH.calls.search
        if not S.Demand() then return 0 end
        W.RunUntil(function() return S.state == "idle" end, 600)
        return W.AH.calls.search - before
    end
    function tools.Shown()
        local rows, summary = ns.Results.Build(S.offers, S.ctx, { money = GetMoney(), wants = ns.Wants.Of(Owner()), unchecked = S.Unchecked() })
        local out, entries = {}, {}
        for _, row in ipairs(rows) do
            local name = row.kind == "item" and row.entry.offer.name
            if name and not entries[name] then out[#out + 1] = name end
            if name then entries[name] = entries[name] or row.entry end
        end
        table.sort(out)
        return table.concat(out, ", "), summary.unwanted, entries
    end
    function tools.Set()
        local wants = ns.Wants.Of(Owner())
        local rows = ns.Plan.Rows(ns.Plan.Choose(ns.Plan.Ladder(S.offers, S.ctx, GetMoney(), wants), GetMoney()))
        local out = {}
        for _, row in ipairs(rows) do
            if row.kind == "item" then out[#out + 1] = row.entry.offer.name .. " +" .. ("%g"):format(row.entry.delta) end
        end
        return table.concat(out, ", ")
    end
    return tools
end

-- What a card says of a character's weapons, and what is asked of its gear by that
-- (Wants.lua): the kinds of weapon a class has, the way the hands are filled where the
-- player chose and where the profile says, and a card that came out of a saved file with
-- anything at all written where those are kept.
function scenarios.weapons()
    MoreProfiles()
    StandardWorld()
    LoadAddon()
    local Wants, Roster = ns.Wants, ns.Roster

    -- The kinds of weapon a class can ever wield, by the game's names, in the order of the
    -- menu: those for one hand, for both, for the ranged slot, a "/" between the three.
    local function Kinds(class)
        local out, held = {}, nil
        for _, weapon in ipairs(Roster.WeaponKinds(class)) do
            if held and weapon.held ~= held then out[#out + 1] = "/" end
            held = weapon.held
            out[#out + 1] = C_Item.GetItemSubClassInfo(2, weapon.kind)
        end
        return table.concat(out, " | ")
    end
    eq(Kinds("WARRIOR"), "One-Handed Axes | One-Handed Maces | One-Handed Swords | Daggers | Fist Weapons | / | "
        .. "Two-Handed Axes | Two-Handed Maces | Two-Handed Swords | Polearms | Staves | / | Bows | Crossbows | Guns | Thrown",
        "a warrior: every kind but a wand")
    eq(Kinds("ROGUE"), "One-Handed Axes | One-Handed Maces | One-Handed Swords | Daggers | Fist Weapons | / | Bows | Crossbows | Guns | Thrown",
        "a rogue: nothing for both hands")
    eq(Kinds("WARLOCK"), "One-Handed Swords | Daggers | / | Staves | / | Wands", "a warlock")
    eq(Kinds("MAGE"), Kinds("WARLOCK"), "a mage the same")
    eq(Kinds("PRIEST"), "One-Handed Maces | Daggers | / | Staves | / | Wands", "a priest")
    eq(Kinds("PALADIN"), "One-Handed Axes | One-Handed Maces | One-Handed Swords | / | Two-Handed Axes | Two-Handed Maces | Two-Handed Swords | Polearms",
        "a paladin: nothing for the ranged slot")
    eq(Kinds("DRUID"), "One-Handed Maces | Daggers | Fist Weapons | / | Two-Handed Maces | Polearms | Staves", "a druid")
    eq(#Roster.WeaponKinds("HUNTER"), 12, "a hunter: twelve kinds"); eq(#Roster.WeaponKinds("SHAMAN"), 7, "a shaman: seven")
    eq(#Roster.WeaponKinds(nil), 0, "no class, no kinds"); eq(#Roster.WeaponKinds("BARD"), 0, "nor for a class that is not one")
    -- The kind of weapon an item is.
    eq(Wants.WeaponOf(2, 7), 7, "a one-handed sword"); eq(Wants.WeaponOf(2, 0), 0, "a one-handed axe, whose number is nought")
    eq(Wants.WeaponOf(4, 6), nil, "a shield is no weapon"); eq(Wants.WeaponOf(2, nil), nil, "nor is what has no kind"); eq(Wants.WeaponOf(nil, 7), nil, "or no class")

    -- How the hands are filled. Nothing chosen: any way, and nothing is asked.
    local told = {}
    ns.Listen("WANTS_CHANGED", function(card) told[#told + 1] = card end)
    local function Hands(card)
        local hands, own = Wants.Hands(card)
        return hands .. (own and " (chosen)" or "")
    end
    local warrior = { class = "WARRIOR", level = 30 }
    eq(Hands(warrior), "ANY", "a warrior on Arms, nothing chosen: any way"); eq(Wants.Of(warrior), nil, "which asks for nothing")
    eq(Hands(nil), "ANY", "no character: any way")
    -- On a profile of a shield tank a character that has not chosen is offered one hand.
    warrior.profile = "WARRIOR_PROTECTION"
    eq(Hands(warrior), "ONE", "a warrior on Protection: a weapon for one hand and a shield, by the profile")
    eq(Wants.Of(warrior).hands, "ONE", "which is asked of its gear"); eq(warrior.byProfile, nil, "and not written down as its choice")
    warrior.profile, warrior.talents = nil, "WARRIOR_PROTECTION"
    eq(Hands(warrior), "ONE", "the same where the profile is the one its talents are in")
    local paladin = { class = "PALADIN", level = 17 }
    eq(Hands(paladin), "ANY", "a paladin starts on Retribution: any way")
    paladin.talents = "PALADIN_PROTECTION"
    eq(Hands(paladin), "ONE", "with its talents in Protection: one hand")
    paladin.profile = "PALADIN_HOLY"
    eq(Hands(paladin), "ANY", "and with Holy chosen, any way again")
    paladin.profile = nil
    eq(Hands({ class = "DRUID", level = 30, profile = "D2" }), "ANY", "no other profile has a say: a druid's Feral")
    -- The weights the addon comes with have those two profiles by those names, and of all
    -- its profiles they alone say so.
    local real, tests = {}, ns.Weights
    assert(loadfile(ADDON_DIR .. "Weights.lua"))("UpgradeScout", real)
    ns.Weights = real.Weights
    local tanks = {}
    for class, ids in pairs(real.Weights.classes) do
        for _, id in ipairs(ids) do
            if Wants.Hands({ class = class, level = 60, profile = id }) == "ONE" then tanks[#tanks + 1] = id end
        end
    end
    ns.Weights = tests
    table.sort(tanks)
    eq(table.concat(tanks, " "), "PALADIN_PROTECTION WARRIOR_PROTECTION", "of the addon's own profiles, a warrior's and a paladin's Protection, and no other")
    -- A choice stands whatever the profile, "Any" among them.
    Wants.SetHands(paladin, "ANY")
    eq(Chosen(paladin).hands, "ANY", "any way, chosen: written on the card"); eq(Hands(paladin), "ANY (chosen)", "and it holds on Protection")
    eq(Wants.ProfileKey(paladin), "own:PALADIN_PROTECTION", "it is kept for the profile it was made on: the addon's own Protection")
    eq(paladin.byProfile["own:PALADIN_PROTECTION"].hands, "ANY", "under that name on the card")
    eq(Wants.Of(paladin), nil, "nothing is asked")
    Wants.SetHands(paladin, "TWO")
    eq(Hands(paladin), "TWO (chosen)", "a two-hander, chosen"); eq(Wants.Of(paladin).hands, "TWO", "is asked for")
    Wants.SetHands(paladin, "ONE")
    eq(Hands(paladin), "ONE (chosen)", "one hand, chosen: the same as the profile says, and now the character's own")
    eq(#told, 3, "the addon is told of each choice"); eq(told[3], paladin, "and whose it is")
    Wants.SetHands(paladin, "BOTH")
    eq(Chosen(paladin).hands, "ONE", "what is none of the three is no choice"); eq(#told, 3, "and nothing is told")
    check(Wants.Of(paladin) == Wants.Of(Keep({ class = "WARRIOR", level = 60 }, "ONE")), "the same wants are one table")
    check(Wants.Of(paladin) == Wants.Of(warrior), "whether the player chose them or the profile did")
    check(Wants.Of(paladin) ~= Wants.Of(Keep({ class = "WARRIOR", level = 60 }, "TWO")), "and other wants another")
    -- The choice is the profile's it was made on. With its talents elsewhere the paladin is
    -- on another profile, which has none; one made there is that profile's, and Protection
    -- has its own when the paladin is back on it.
    paladin.talents = "PALADIN_RETRIBUTION"
    eq(Hands(paladin), "ANY", "on Retribution nothing is chosen: one hand was Protection's choice"); eq(Wants.Of(paladin), nil, "and nothing is asked")
    Wants.SetHands(paladin, "TWO")
    Wants.SetKind(paladin, 7, false)
    eq(Hands(paladin), "TWO (chosen)", "a two-hander, chosen on Retribution"); eq(Wants.KindOut(paladin, 7), true, "and no swords")
    paladin.talents = "PALADIN_PROTECTION"
    eq(Hands(paladin), "ONE (chosen)", "on Protection again: one hand, as chosen there"); eq(Wants.KindOut(paladin, 7), false, "and swords, which were unticked on Retribution alone")
    paladin.profile = "PALADIN_RETRIBUTION"
    eq(Hands(paladin), "TWO (chosen)", "Retribution chosen in the profile field, and not by the talents: its own choice all the same")
    eq(Wants.Of(paladin).kinds[7], true, "with its kinds")
    paladin.profile = nil
    Wants.SetKind(paladin, 7, true)
    eq(Wants.KindOut(paladin, 7), false, "a kind ticked on Protection, where it was ticked already, changes nothing")
    paladin.talents = "PALADIN_RETRIBUTION"
    eq(Wants.KindOut(paladin, 7), true, "nor on Retribution, where it is unticked still")
    paladin.talents = "PALADIN_PROTECTION"
    told = { 1, 2, 3 }

    -- The kinds of weapon: all are offered until one is unticked.
    local rogue = { class = "ROGUE", level = 20 }
    eq(Wants.Of(rogue), nil, "a rogue with every kind ticked asks for nothing"); eq(Wants.KindOut(rogue, 15), false, "daggers are offered")
    Wants.SetKind(rogue, 15, false)
    eq(Chosen(rogue).kinds[15], false, "daggers unticked: written on the card"); eq(Wants.KindOut(rogue, 15), true, "and left out")
    eq(Wants.Of(rogue).kinds[15], true, "which is asked of its gear"); eq(Wants.Of(rogue).kinds[7], nil, "swords are not left out")
    eq(Wants.Of(rogue).hands, nil, "and the hands are filled any way")
    eq(#told, 4, "the addon is told")
    Wants.SetKind(rogue, 0, false)
    Wants.SetKind(rogue, 4, false)
    local _, out = Wants.KindsOut(rogue)
    eq(out, 3, "three kinds left out")
    check(Wants.Of(rogue) == Wants.Of(Keep({ class = "ROGUE", level = 5 }, nil, { 4, 0, 15 })),
        "the same kinds left out are the same wants, in whatever order they were unticked")
    check(Wants.Of(rogue) ~= Wants.Of(Keep({ class = "ROGUE", level = 5 }, nil, { 4, 0 })), "and others are not")
    local wants = Wants.Of(rogue)
    eq(Wants.Fits(wants, { invType = "INVTYPE_WEAPON", weapon = 15 }), false, "a dagger does not fit")
    eq(Wants.Fits(wants, { invType = "INVTYPE_WEAPON", weapon = 7 }), true, "a sword does")
    eq(Wants.Fits(wants, { invType = "INVTYPE_RANGED", weapon = 2 }), true, "and a bow")
    eq(Wants.Fits(wants, { invType = "INVTYPE_HEAD", armor = 2 }), true, "what is no weapon is no matter of it")
    eq(Wants.Fits(wants, { invType = "INVTYPE_SHIELD" }), true, "a shield neither")
    eq(Wants.FitsLink(wants, W.Link(102)), true, "by its link: the worn sword fits"); eq(Wants.FitsLink(nil, W.Link(212)), true, "and anything fits no wants")
    eq(Wants.FitsLink({ kinds = { [7] = true } }, W.Link(102)), false, "a sword does not fit wants without swords")
    eq(Wants.FitsLink({ hands = "ONE" }, W.Link(212)), false, "nor a two-handed axe a character that goes by one hand")
    eq(Wants.FitsLink({ hands = "TWO" }, W.Link(213)), false, "nor a shield one that goes by two")
    eq(Wants.FitsLink({ armor = 3 }, W.Link(202)), false, "and leather not one that keeps mail, as before")
    Wants.SetKind(rogue, 15, true)
    Wants.SetKind(rogue, 0, true)
    Wants.SetKind(rogue, 4, true)
    eq(Chosen(rogue).kinds[15], true, "all ticked again: written on the card as ticked, which is the player's own as well"); eq(Wants.Of(rogue), nil, "and nothing is asked")
    -- A kind that is none of the class's own has no say, whatever a card says of it.
    Keep(rogue, nil, { 10, 19 })
    eq(Wants.Of(rogue), nil, "a rogue's card with staves and wands left out asks for nothing")
    Keep(rogue, nil, { 10, 7 })
    _, out = Wants.KindsOut(rogue)
    eq(out, 1, "of staves and swords, the swords count"); eq(Wants.Of(rogue).kinds[10], nil, "alone")
    -- Everything at once: the armor, the gain, the hands and the kinds.
    local all = Keep({ class = "WARRIOR", level = 10, armorOnly = true, minGainOn = true, minGain = 25 }, "ONE", { 15 })
    wants = Wants.Of(all)
    eq(wants.armor, 3, "all four at once: mail"); eq(wants.gain, 25, "a quarter"); eq(wants.hands, "ONE", "one hand"); eq(wants.kinds[15], true, "no daggers")
    eq(Wants.Fits(wants, { invType = "INVTYPE_CHEST", armor = 2 }), false, "each leaves out its own: leather")
    eq(Wants.Fits(wants, { invType = "INVTYPE_2HWEAPON", weapon = 1 }), false, "a two-hander")
    eq(Wants.Fits(wants, { invType = "INVTYPE_WEAPON", weapon = 15 }), false, "a dagger")
    eq(Wants.Fits(wants, { invType = "INVTYPE_WEAPON", weapon = 7 }), true, "and a sword stays")

    -- A card comes out of a saved file: whatever is written there, nothing breaks, and what
    -- is no choice is none.
    local junk = { 5, 0, true, false, "one", "any", "", {}, { "ONE" }, function() end }
    -- The nonsense in each place a choice is kept in: for the whole of what the card keeps
    -- by profile, for what it keeps for the one profile, and for the two things kept there.
    local places = { "all it keeps by profile", "what it keeps for the profile", "a choice" }
    for i = 1, #junk do
        for place = 1, #places do
            local card = { class = "WARRIOR", level = 10, talents = "WARRIOR_PROTECTION" }
            local key = Wants.ProfileKey(card)
            if place == 1 then
                card.byProfile = junk[i]
            elseif place == 2 then
                card.byProfile = { [key] = junk[i], [junk[i]] = junk[i] }
            else
                card.byProfile = { [key] = { hands = junk[i], kinds = junk[i] } }
            end
            local what = "a card with a " .. type(junk[i]) .. " for " .. places[place]
            eq(Hands(card), "ONE", what .. ": the profile has its say, as with no choice")
            eq(Wants.Of(card).kinds, nil, "no kind is left out"); eq(Wants.KindOut(card, 7), false, "asked of one or of all")
            Wants.SetKind(card, 7, false)
            eq(Wants.KindOut(card, 7), true, "a kind unticked on such a card is left out")
            Wants.SetKind(card, 7, true)
            eq(Wants.KindOut(card, 7), false, "and ticked again is not")
            Wants.SetHands(card, "TWO")
            eq(Hands(card), "TWO (chosen)", "and a choice of hands is written over the nonsense")
        end
    end
    local odd = { class = "WARRIOR", level = 10 }
    odd.byProfile = { [Wants.ProfileKey(odd)] = { kinds = { [7] = "no", [15] = 0, [0] = true, [1] = false, [99] = false, swords = false, [1.5] = false } } }
    _, out = Wants.KindsOut(odd)
    eq(out, 1, "only a kind of the class that is plainly left out counts"); eq(Wants.Of(odd).kinds[1], true, "the two-handed axes")
    eq(Wants.Of(Keep({ level = 10 }, "TWO", { 7 })).hands, "TWO", "a card without a class: its choice of hands holds")
    eq(Wants.Of(Keep({ level = 10 }, nil, { 7 })), nil, "and no kind is its class's to leave out")
    -- What a build that was never given out wrote beside the card's other filters is no choice.
    eq(Wants.Of({ class = "WARRIOR", level = 10, hands = "TWO", weaponsOut = { [7] = true } }), nil, "a choice written on the card itself, and under no profile, says nothing")

    -- The same from the file itself: the character being played logs in to a card with
    -- nonsense on it, and scans.
    local me = Roster.Me()
    me.byProfile = { [Wants.ProfileKey(me)] = { hands = { 1, 2 }, kinds = "none" }, other = 5, [7] = "ONE" }
    Relog(W.player, W.equipped)
    me = ns.Roster.Me()
    eq(type(Chosen(me).hands), "table", "the nonsense is on the card still"); eq(me.byProfile.other, 5, "all of it")
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    SetView(false, false)
    ScanToEnd()
    CheckStandardOffers("a card with nonsense about its weapons")
    W.Run(0.5)
    eq(UpgradeScoutFrame.FilterNames:GetText(), "", "no filter is on")
    local menu = WeaponsMenu()
    check(menu:Lines():find("(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | [x] One-Handed Axes", 1, true) ~= nil,
        "the menu opens, with nothing chosen and every kind ticked: " .. menu:Lines())
    menu:Click("Daggers")
    eq(type(Chosen(me).kinds), "table", "a kind unticked there is written over the nonsense"); eq(Chosen(me).kinds[15], false, "as it should be")
    menu:Click("Two-hand")
    eq(Chosen(me).hands, "TWO", "and so is a choice of hands")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- A level 10 warrior that holds a two-handed mace (30; 20 on its second profile) and wears
-- nothing else. For sale, with the score on the second profile after the first:
--   Long Axe         two-handed axe, 45 / 40    +15 on the maul
--   Sharp Sword      one-handed sword, 36 / 24  +6 on the maul, and the off hand empty
--   Blunt Mace       one-handed mace, 20 / 15   weaker than the maul
--   Oak Shield       12 / 12                    for the off hand, which a two-hander leaves no place in
--   Lantern          held in the off hand, 5 / 2
--   Parrying Dagger  off-hand weapon, 9         for one who can hold two weapons, which a warrior of 10 cannot
--   Helm             12 / 5                     for the empty head
--   Short Bow        4 / 1                      for the empty ranged slot
local function TwoHandWorld()
    W.AddItem({ id = 590, name = "Worn Maul", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 5, value = 30, value2 = 20, level = 5 })
    W.equipped[16] = W.Link(590)
    Sell({ id = 600, name = "Long Axe", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 1, value = 45, value2 = 40, level = 9 }, 3000)
    Sell({ id = 601, name = "Sharp Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, value = 36, value2 = 24, level = 9 }, 2000)
    Sell({ id = 602, name = "Blunt Mace", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 4, value = 20, value2 = 15, level = 9 }, 500)
    Sell({ id = 603, name = "Oak Shield", equipLoc = "INVTYPE_SHIELD", subClassID = 6, value = 12, value2 = 12, level = 8 }, 800)
    Sell({ id = 604, name = "Lantern", equipLoc = "INVTYPE_HOLDABLE", subClassID = 0, value = 5, value2 = 2, level = 8 }, 300)
    Sell({ id = 605, name = "Parrying Dagger", equipLoc = "INVTYPE_WEAPONOFFHAND", classID = 2, subClassID = 15, value = 9, value2 = 9, level = 8 }, 400)
    Sell({ id = 606, name = "Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 12, value2 = 5, level = 9 }, 500)
    Sell({ id = 607, name = "Short Bow", equipLoc = "INVTYPE_RANGED", classID = 2, subClassID = 2, value = 4, value2 = 1, level = 6 }, 200)
end

-- A scan, and the choice of weapons changed with its list on view: the list follows at once,
-- no price is looked up for what the choice leaves out, and the prices it comes to need are
-- looked up when it does. The character holds a two-hander, where the choice has most to say.
function scenarios.weapons_scan()
    TwoHandWorld()
    LoadAddon()
    local Wants, S = ns.Wants, ns.Scanner
    W.OpenAuctionHouse()
    local me = ns.Roster.Me()
    local tools = ScanTools()
    local Scan, More, Shown, Set = tools.Scan, tools.More, tools.Shown, tools.Set
    local ANY = "Helm, Long Axe, Sharp Sword, Short Bow"
    local ONE = "Blunt Mace, Helm, Lantern, Oak Shield, Sharp Sword, Short Bow"
    local TWO = "Helm, Long Axe, Short Bow"

    -- Nothing chosen, the tab's own filters off: the list is what it always was for one that
    -- holds a two-hander. The shield, the lantern and the mace, which is weaker than the
    -- maul, are kept without a search: another choice of the hands has a place for them.
    SetView(false, false)
    eq(Scan(), 4, "four item searches: the axe, the sword, the helm and the bow")
    local list, unwanted, entries = Shown()
    eq(list, ANY, "no choice: no shield and no lantern beside the two-hander"); eq(unwanted, 0, "and nothing is counted as left out")
    eq(entries["Sharp Sword"].note, "OFFHAND_EMPTY", "the sword against the maul, with its note")
    near(entries["Sharp Sword"].percent, 0.2, "+20%: its gain is a share of the maul")
    eq(Offer("Oak Shield"), nil, "the shield's price was not looked up"); eq(Unsure("Oak Shield"), nil, "and it is no offer: the scan keeps it aside")
    eq(Offer("Blunt Mace"), nil, "nor the price of the mace"); eq(Unsure("Blunt Mace"), nil, "which is kept aside as well")
    eq(S.stats.candidates, 4, "four upgrades by score: what is kept aside is none"); eq(S.stats.skipped, 0, "and the list did without no price")
    eq(S.Demand(), false, "nothing more is needed for the list as it is")
    eq(Set(), "Helm +12, Long Axe +15, Short Bow +4", "the best set: the axe, and no shield, which the list has no row for")

    -- One hand, a shield and the off hand: the two-hander is out, and what goes into the off
    -- hand is in, at once, as into an empty slot. So are the weapons for one hand, the mace
    -- that does not beat the maul among them: each for the main hand without the maul, at
    -- its own worth. Their prices are asked for.
    Wants.SetHands(me, "ONE")
    list, unwanted, entries = Shown()
    eq(list, ONE, "one hand: the shield, the lantern and the mace are listed, the axe is not"); eq(unwanted, 1, "which is counted as left out")
    local shield = entries["Oak Shield"]
    eq(shield.group, "OFFHAND", "the shield is for the off hand"); eq(shield.note, "NEEDS_ONE_HAND", "with the note that it takes a weapon for one hand")
    near(shield.delta, 12, "at its own worth"); eq(shield.percent, nil, "and no percent"); eq(shield.replaced, nil, "of nothing that comes off")
    eq(entries["Lantern"].note, "NEEDS_ONE_HAND", "the lantern the same")
    local sword, mace = entries["Sharp Sword"], entries["Blunt Mace"]
    eq(sword.group, "MAINHAND", "the sword is for the main hand"); eq(sword.note, "REPLACES_TWO_HAND", "in the place of the maul, which the choice leaves out")
    near(sword.delta, 36, "at its own worth, and not at what it has over the maul"); eq(sword.percent, nil, "with no percent")
    eq(sword.replaced[1], S.ctx.equipped[16].link, "the maul comes off for it"); eq(sword.pick, "UPGRADE", "and it is the best upgrade the main hand is offered")
    eq(mace.group, "MAINHAND", "the mace the same"); near(mace.delta, 20, "at its worth, which is less than the maul's 30"); eq(mace.note, "REPLACES_TWO_HAND", "with the note")
    eq(mace.pick, "VALUE", "and the best value there, at a quarter of the sword's price")
    check(Unsure("Oak Shield") ~= nil and Unsure("Lantern") ~= nil and Unsure("Blunt Mace") ~= nil,
        "the three are in the list at the lowest prices of their rows, as a scan lists what it finds")
    eq(Unsure("Parrying Dagger"), nil, "an off-hand weapon has no place by any choice, for one who cannot hold two: it was not kept")
    eq(More(), 3, "three searches: the shield, the lantern and the mace")
    eq(Offer("Oak Shield").buyout, 800, "the shield has its price"); eq(Offer("Lantern").buyout, 300, "and the lantern"); eq(Offer("Blunt Mace").buyout, 500, "and the mace")
    eq(Shown(), ONE, "the same list")
    eq(Set(), "Helm +12, Sharp Sword +36, Oak Shield +12, Short Bow +4", "the best set: the sword in the maul's place, and the shield beside it")

    -- A two-hander: nothing for one hand.
    Wants.SetHands(me, "TWO")
    list, unwanted = Shown()
    eq(list, TWO, "two hands: the axe, and no sword"); eq(unwanted, 1, "the sword is counted as left out; the mace, the shield and the lantern are no upgrades")
    eq(More(), 0, "nothing to look up")
    eq(Set(), "Helm +12, Long Axe +15, Short Bow +4", "the best set is of the same")
    -- Any way, chosen: as with no choice. The sword is measured against the maul again, and
    -- the mace, which does not beat it, is gone from the list as the shield is. Their
    -- prices are known by now, and they are still no rows, nor in a set.
    Wants.SetHands(me, "ANY")
    list, unwanted, entries = Shown()
    eq(list, ANY, "any way: the list of the start, without the mace"); eq(unwanted, 0, "nothing left out"); eq(More(), 0, "nothing to look up")
    eq(entries["Sharp Sword"].note, "OFFHAND_EMPTY", "the sword against the maul again"); near(entries["Sharp Sword"].percent, 0.2, "at +20%")
    check(Offer("Oak Shield") ~= nil and Offer("Blunt Mace") ~= nil, "the prices of the shield and the mace are still known")
    eq(Set(), "Helm +12, Long Axe +15, Short Bow +4", "and the best set does not pair it with the sword: that takes saying one hand")

    -- A scan with one hand chosen looks up no price for the two-hander.
    Wants.SetHands(me, "ONE")
    eq(Scan(), 6, "six searches: the sword, the mace, the shield, the lantern, the helm and the bow")
    eq(Offer("Long Axe"), nil, "none for the axe"); check(Unsure("Long Axe") ~= nil, "which is kept at its row's lowest price")
    list, unwanted = Shown()
    eq(list, ONE, "the list for one hand"); eq(unwanted, 1, "the axe counted")
    eq(S.Demand(), false, "and nothing more is needed")
    Wants.SetHands(me, "ANY")
    eq(More(), 1, "any way again: one search, for the axe"); eq(Offer("Long Axe").buyout, 3000, "which has its price")
    -- And one with a two-hander chosen none for the sword, the mace, the shield or the lantern.
    Wants.SetHands(me, "TWO")
    eq(Scan(), 3, "three searches: the axe, the helm and the bow")
    eq(Offer("Sharp Sword"), nil, "none for the sword"); eq(Offer("Oak Shield"), nil, "or the shield")
    Wants.SetHands(me, "ONE")
    eq(More(), 4, "one hand: four searches, for the sword, the mace, the shield and the lantern")
    Wants.SetHands(me, "ANY")

    -- The kinds of weapon. One-handed swords unticked: the sword is out; then the bows, then
    -- the two-handed axes.
    Wants.SetKind(me, 7, false)
    list, unwanted = Shown()
    eq(list, "Helm, Long Axe, Short Bow", "no one-handed swords: no sword"); eq(unwanted, 1, "counted")
    Wants.SetKind(me, 2, false)
    Wants.SetKind(me, 1, false)
    list, unwanted = Shown()
    eq(list, "Helm", "nor bows, nor two-handed axes: the helm alone"); eq(unwanted, 3, "three left out")
    eq(Set(), "Helm +12", "and the best set is the helm")
    eq(Scan(), 1, "a scan looks up the helm's price and no other")
    check(Unsure("Sharp Sword") ~= nil and Unsure("Long Axe") ~= nil and Unsure("Short Bow") ~= nil, "the three are kept without a search")
    Wants.SetKind(me, 7, true)
    eq(More(), 1, "swords ticked again: one search"); check(Offer("Sharp Sword") ~= nil, "for the sword")
    -- A kind of weapon is no matter of the hands: with one hand chosen and maces unticked,
    -- the mace is out and the shield stays. (It is armor, of no kind there is a box for.)
    Wants.SetHands(me, "ONE")
    Wants.SetKind(me, 4, false)
    list, unwanted = Shown()
    eq(list, "Helm, Lantern, Oak Shield, Sharp Sword", "one hand, without maces, bows and two-handed axes")
    eq(unwanted, 3, "the mace, the bow and the axe left out: the axe once, for both reasons")
    eq(More(), 2, "the shield's price and the lantern's are asked for")
    Wants.SetKind(me, 2, true)
    Wants.SetKind(me, 1, true)
    Wants.SetKind(me, 4, true)
    Wants.SetHands(me, "ANY")
    eq(select(2, Wants.KindsOut(me)), 0, "every kind ticked again")
    eq(More(), 2, "the bow's price and the axe's are asked for")
    eq(Shown(), ANY, "and the list is whole")

    -- "Upgrade at least" with one hand chosen: what goes into the hands as they will be
    -- without the maul has no percent, as what goes into an empty slot has none, and stays
    -- whatever the number: the shield, and the sword and the mace as well. Any way, where
    -- the sword is +20% on the maul, it falls short.
    Wants.SetHands(me, "ONE")
    Wants.SetGain(me, true, 50)
    list, unwanted = Shown()
    eq(list, ONE, "at least 50% with one hand: every row for the hands stays, none of them has a percent")
    eq(unwanted, 1, "the axe alone is left out")
    Wants.SetHands(me, "ANY")
    list, unwanted = Shown()
    eq(list, "Helm, Long Axe, Short Bow", "at least 50%, any way: the sword's +20% falls short"); eq(unwanted, 1, "and it is counted")
    Wants.SetGain(me, false)

    -- "Top 5 per slot" judges among what the character would have, for the hands as for
    -- armor: with the axe out the sword is the best there is for the main hand.
    SetView(false, true)
    Wants.SetHands(me, "ONE")
    eq(Scan(), 6, "top five with one hand chosen: the sword, the mace, the shield, the lantern, the helm and the bow")
    eq(Offer("Long Axe"), nil, "and no price for the axe")
    SetView(false, false)
    Wants.SetHands(me, "ANY")

    -- Gear changed with the list on view. A scan made with the maul held kept the shield and
    -- the lantern aside. A sword goes on in the maul's place: the off hand is free, the two
    -- are in the list at once, any way, and their prices are asked for.
    eq(Scan(), 4, "a scan with the maul held, any way: four searches")
    eq(Unsure("Oak Shield"), nil, "the shield is kept aside")
    W.AddItem({ id = 591, name = "Worn Blade", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, value = 25, level = 5 })
    W.equipped[16] = W.Link(591)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1.5)
    eq(S.ctx.equipped[16].itemID, 591, "the list is measured against the sword now held")
    list, unwanted, entries = Shown()
    eq(list, "Helm, Lantern, Long Axe, Oak Shield, Sharp Sword, Short Bow", "with a sword held: the shield and the lantern are listed")
    eq(unwanted, 0, "nothing left out"); eq(entries["Oak Shield"].note, nil, "for an off hand that is empty: nothing to note")
    check(Unsure("Oak Shield") ~= nil and Unsure("Lantern") ~= nil, "at the lowest prices of their rows")
    eq(More(), 2, "which are looked up")
    -- The shield goes on beside the sword, and the list is measured against that, whatever
    -- the choice. The lantern (5) is weaker than the shield.
    W.equipped[17] = W.Link(603)
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1.5)
    eq(S.ctx.equipped[17].itemID, 603, "the list is measured against the shield now held")
    list, unwanted, entries = Shown()
    eq(list, "Helm, Long Axe, Sharp Sword, Short Bow", "any way: the axe, 45 against 37, and the sword, 36 against 25")
    eq(unwanted, 0, "nothing left out"); eq(entries["Long Axe"].note, "BOTH_HANDS", "the axe takes both hands")
    Wants.SetHands(me, "ONE")
    list, unwanted, entries = Shown()
    eq(list, "Helm, Sharp Sword, Short Bow", "one hand: no axe"); eq(unwanted, 1, "which is left out")
    eq(entries["Sharp Sword"].note, nil, "and no note on the sword: the off hand stays as it is")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- What a scan keeps aside for another way of filling the hands is counted by itself. One
-- that holds a two-hander has every shield for sale kept so, and they are many: they do not
-- take the place of what the list is for, and their number is no reason to call a scan
-- incomplete, until the character goes over to one hand and the list is to have them.
function scenarios.weapons_spare()
    TwoHandWorld()
    for i = 1, 2010 do
        Sell({ id = 20000 + i, name = "Plain Shield " .. i, equipLoc = "INVTYPE_SHIELD", subClassID = 6, value = 1, level = 1 }, 10 + i)
    end
    -- Read after all of those: an upgrade as things stand.
    Sell({ id = 30000, name = "Late Helm", equipLoc = "INVTYPE_HEAD", subClassID = 3, value = 20, level = 10 }, 600)
    W.AH.honorLevelSort = false
    LoadAddon()
    local Wants, S = ns.Wants, ns.Scanner
    W.OpenAuctionHouse()
    local me = ns.Roster.Me()
    SetView(false, false)
    ScanToEnd()
    eq(S.partial, false, "more shields than are kept aside: the scan is whole all the same")
    check(Offer("Late Helm") ~= nil, "a helm read after them is in the list"); check(Offer("Long Axe") ~= nil, "and the axe")
    eq(S.stats.candidates, 5, "five upgrades by score: the shields kept aside are none")
    eq(UnsureCount(), 0, "and none of them is an offer")
    -- One hand chosen: the shields are in the list, as many as were kept, and the list says
    -- that it has not every one of them.
    Wants.SetHands(me, "ONE")
    eq(UnsureCount(), 2000, "one hand: two thousand of the 2013 things for sale that only one hand has a place for (the shields, the lantern, the mace), as many as are kept")
    eq(S.partial, true, "and the scan says that it has not everything")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- The line "Weapons" of the Filters menu and the menu it opens: what it shows, what a click
-- in it does to the card, to the list on view, to the names beside the Filters field and to
-- the arrows in the bags; whose it is when the list is for another character; and the line
-- the profile chose, until the player chooses.
function scenarios.weapons_ui()
    MoreProfiles()
    TwoHandWorld()
    -- For a druid of the account, and of no worth to a warrior: a staff, a mace, a dagger and
    -- something to hold in the off hand.
    Sell({ id = 620, name = "Elder Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10, value = 0, values = { D1 = 40 }, level = 15 }, 1000)
    Sell({ id = 621, name = "Stone Mace", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 4, value = 0, values = { D1 = 30 }, level = 15 }, 900)
    Sell({ id = 622, name = "Moon Dagger", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 15, value = 0, values = { D1 = 20 }, level = 15 }, 700)
    Sell({ id = 623, name = "Grove Orb", equipLoc = "INVTYPE_HOLDABLE", subClassID = 0, value = 0, values = { D1 = 8 }, level = 15 }, 600)
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    -- The druid as it left things when it was last played: two-handers, and no daggers.
    UpgradeScoutDB.chars["Alty-Testrealm"] = Keep({ key = "Alty-Testrealm", name = "Alty", realm = "Testrealm", faction = "Alliance",
        class = "DRUID", level = 20, gear = {} }, "TWO", { 15 })
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local frame, S, L = UpgradeScoutFrame, ns.Scanner, ns.L
    local me, druid = ns.Roster.Me(), UpgradeScoutDB.chars["Alty-Testrealm"]
    local field = frame.FilterField
    local weapons = WeaponsMenu()
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
    local function Names() return frame.FilterNames:GetText() end
    -- The lines of the Filters field's own tooltip, after its title.
    local function Named()
        field._tooltip(GameTooltip)
        local out = {}
        for i = 2, #GameTooltip._lines do out[#out + 1] = GameTooltip._lines[i].text end
        GameTooltip:Hide()
        return table.concat(out, " | ")
    end
    -- The lines of a row's tooltip that are no part of the game's own: "left right", joined.
    local function RowTip(row)
        row:GetScript("OnEnter")(row)
        local out, ours = {}, false
        for _, line in ipairs(GameTooltip._lines) do
            if ours then out[#out + 1] = line.text .. (line.right and " " .. line.right or "") end
            if line.text:find("Upgrade Scout", 1, true) then ours = true end
        end
        row:GetScript("OnLeave")(row)
        return table.concat(out, " | ")
    end
    local HANDS = "Any | Two-hand | One-hand, shield and off-hand"
    local WARRIOR_KINDS = "[x] One-Handed Axes | [x] One-Handed Maces | [x] One-Handed Swords | [x] Daggers | [x] Fist Weapons | / | "
        .. "[x] Two-Handed Axes | [x] Two-Handed Maces | [x] Two-Handed Swords | [x] Polearms | [x] Staves | / | [x] Bows | [x] Crossbows | [x] Guns | [x] Thrown"

    -- The line stands with the character's other filters, over the rule, and opens a menu:
    -- three lines of which one is chosen, then under a rule a tick box for every kind of
    -- weapon a warrior can ever wield, by the game's names, in three blocks.
    eq(FilterMenu(), "Only what I can afford | Buyout up to | Top | Hide worse deals | Best armor type for the class | Upgrade at least | Gear at most | Weapons > | / | Value by net cost",
        "the line is in the menu, and opens one of its own")
    eq(weapons:Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | " .. WARRIOR_KINDS,
        "which has the three ways to fill the hands, any way chosen, and every kind ticked")
    -- Over them stands whose choice it is: the profile the list is made on, by its name.
    eq(weapons:Head(), "Profile: Arms", "the menu is headed by the profile it is for"); eq(L.WEAPONS_FOR, "Profile: %s", "in the addon's own words")
    field:Open()
    local head = field:OpenSub("Weapons")
    eq(head.elements[1].kind, "title", "a line that only says so: nothing to click"); eq(head.lines[1].fontString:GetText(), "Profile: Arms", "drawn as the game draws one")
    field:Close()
    eq(L.HANDS_ANY .. " | " .. L.HANDS_TWO .. " | " .. L.HANDS_ONE, HANDS, "in the addon's own words")
    -- The lines are the game's, dressed as those of the addon's other menus: the line that
    -- opens the menu in our colours, with the game's arrow at its end; a diamond on a line
    -- of which one is chosen; our tick box on a kind; our rule.
    field:Open()
    local opener
    for i, line in ipairs(field.elements) do
        if line.text == "Weapons" then opener = field.all[i] end
    end
    check(opener.arrow ~= nil, "the line has the game's arrow: it opens a menu"); eq(Pictures(opener, "RowGlow"), 1, "and the light of our rows under the mouse")
    eq(opener:IsEnabled(), true, "it can be opened")
    eq(#opener.fontString._points, 1, "its word is anchored once"); eq(opener.fontString._points[1].x, 16 + 7, "after the room of a tick box, where the words of the other lines stand")
    field:Close()
    eq(weapons:Line("Any", function(line) return Pictures(line, "Diamond") end), 2, "the way chosen: a gold diamond over the grey one")
    eq(weapons:Line("Two-hand", function(line) return Pictures(line, "Diamond") end), 1, "the others: a grey one")
    eq(weapons:Line("Daggers", function(line) return Pictures(line, "Check") == 1 and line.Tick:IsShown() end), true, "a kind: our tick box, ticked")
    local ruled = 0
    field:Open()
    for i, line in ipairs(field:OpenSub("Weapons").elements) do
        if line.kind == "rule" then ruled = ruled + Pictures(field.sub.lines[i], "Line") end
    end
    field:Close()
    eq(ruled, 3, "three rules of ours: over the kinds for one hand, for both and for the ranged slot")
    eq(weapons:Tooltip("Any"), "Any | " .. L.HANDS_ANY_TIP, "a way has a tooltip that says what it shows")
    eq(weapons:Tooltip("Two-hand"), "Two-hand | " .. L.HANDS_TWO_TIP, "each of them")
    eq(weapons:Tooltip("One-hand, shield and off-hand"), "One-hand, shield and off-hand | " .. L.HANDS_ONE_TIP, "what it leaves out, and what it lets in")
    eq(weapons:Tooltip("Staves"), "Staves | " .. L.KINDS_TIP, "and so has a kind")

    -- The list of a warrior that holds a two-handed mace, nothing chosen.
    SetView(false, false)
    ScanToEnd()
    W.Run(0.5)
    check(Row("Long Axe") ~= nil and Row("Sharp Sword") ~= nil and Row("Helm") ~= nil and Row("Short Bow") ~= nil, "the axe, the sword, the helm and the bow")
    eq(Row("Oak Shield"), nil, "no shield beside a two-hander"); eq(Row("Lantern"), nil, "and nothing to hold in the off hand")
    check(Status():find("4 upgrades in 3 slots.", 1, true) ~= nil, "four upgrades: " .. Status())
    eq(Names(), "", "no filter is on: nothing beside the field")
    -- The axe for both hands and the sword for one stand under one heading, "Weapon".
    local heads = {}
    for _, at in ipairs({ 0, 1 }) do
        box:SetScrollPercentage(at)
        for _, w in ipairs(box:GetFrames()) do
            if w._shown and w.Title and not w.entry then heads[w.Title:GetText()] = true end
        end
    end
    eq(heads["WEAPON"], true, "the rows of the main hand are headed \"Weapon\""); eq(heads["MAIN HAND"], nil, "and not by the game's word for the slot")
    eq(heads["HEAD"], true, "the other slots keep the game's words")
    -- The arrows in the bags, by the same gear.
    local function Arrow(slot)
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local axe, sword, shield, helm = W.PutInBags(W.Link(600)), W.PutInBags(W.Link(601)), W.PutInBags(W.Link(603)), W.PutInBags(W.Link(606))
    local mace = W.PutInBags(W.Link(602))
    W.OpenBags()
    eq(Arrow(axe), true, "the axe in the bags has its arrow"); eq(Arrow(sword), true, "and the sword"); eq(Arrow(helm), true, "and the helm")
    eq(Arrow(shield), false, "the shield has none: it has no place beside the maul"); eq(Arrow(mace), false, "nor the mace, which is weaker than the maul")
    -- The lines of ours in the tooltip of an item away from the addon's tabs, after the heading.
    local function ItemTip(id)
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink(W.Link(id))
        local out, ours = {}, false
        for _, line in ipairs(GameTooltip._lines) do
            if ours then out[#out + 1] = line.text .. (line.right and " " .. line.right or "") end
            if line.text:find("Upgrade Scout", 1, true) then ours = true end
        end
        GameTooltip:Hide()
        return table.concat(out, " | ")
    end
    eq(ItemTip(603), "", "the shield's tooltip has no line of ours: nowhere to put it")
    eq(ItemTip(602), "Arms -33% | Protection -25% | Your off hand will be empty", "the mace's says what it loses to the maul")

    -- One hand, a shield and the off hand. The click leaves both menus open, with the mark
    -- on the line clicked; the card has the choice, and the list follows at once.
    local searches, sounds = W.AH.calls.search, #W.sounds
    weapons:Click("One-hand, shield and off-hand", function(open, sub)
        eq(open._open, true, "the menu stays open after the click"); eq(open.sub, sub, "and so does the one beside it")
        check(sub.lines[4].leftTexture2 ~= nil, "whose lines are drawn again: the mark is on the line clicked")
        eq(sub.lines[2].leftTexture2, nil, "and off the one that had it")
        eq(#open.lines, 8, "the lines of the first menu are drawn again as well")
    end)
    eq(#W.sounds, sounds + 1, "the game sounds the click, once")
    eq(Chosen(me).hands, "ONE", "the choice is written on the warrior's card")
    eq(UpgradeScoutDB.chars[me.key].byProfile["own:S1"].hands, "ONE", "which is saved with the account: for its profile, Arms")
    eq(weapons:Lines(), "( ) Any | ( ) Two-hand | (x) One-hand, shield and off-hand | / | " .. WARRIOR_KINDS, "the menu shows it the next time it opens")
    eq(Row("Long Axe"), nil, "the axe is out of the list at once"); check(Row("Oak Shield") ~= nil and Row("Lantern") ~= nil, "and the shield and the lantern are in")
    check(Row("Blunt Mace") ~= nil, "and so is the mace, which is weaker than the maul: one hand has a place for it")
    Settle()
    eq(W.AH.calls.search, searches + 3, "three item searches, for the prices of the three")
    local row = Row("Oak Shield")
    eq(row.Upgrade:GetText(), "New", "the shield is for a slot that is empty: no percent")
    eq(row.Hand:GetText(), "Off Hand", "the row says how it is held")
    eq(Row("Lantern").Hand:GetText(), "Held In Off-hand", "as the lantern's does")
    eq(RowTip(row), "Arms +12 pts | Protection +12 pts | Needs a one-hand weapon in your main hand",
        "its tooltip: what it adds on each profile, in that place, and what it takes")
    -- The sword, which was +20% on the maul, and the mace: each for a main hand without the
    -- maul. The column says "New", and no gain over a weapon the choice leaves out.
    eq(Row("Sharp Sword").Upgrade:GetText(), "New", "the sword's row claims no gain over the maul")
    eq(Row("Blunt Mace").Upgrade:GetText(), "New", "nor does the mace's"); eq(Row("Sharp Sword").Hand:GetText(), "One-Hand", "the row says how it is held")
    eq(RowTip(Row("Sharp Sword")), 'Arms +36 pts | Protection +24 pts | Replaces your two-hand weapon and is not compared with it: one-hand is chosen in the "Weapons" filter.',
        "its tooltip: what it is worth on each profile, and whose place it takes")
    check(Status():find("6 upgrades in 4 slots.", 1, true) ~= nil, "six upgrades now: " .. Status())
    eq(Names(), "One-hand", "the choice is named beside the field"); eq(Named(), "One-hand, shield and off-hand", "and in full in the field's tooltip")
    W.Run(1.5)
    -- The arrows in the bags and the tooltips of the items there follow the list: what it
    -- leaves out has no arrow, and what it offers in the place of the maul has one.
    eq(Arrow(axe), false, "in the bags the axe has lost its arrow"); eq(Arrow(sword), true, "the sword keeps its own")
    eq(Arrow(shield), true, "the shield has one now, as the list has a row for it"); eq(Arrow(mace), true, "and so has the mace")
    eq(Arrow(helm), true, "the helm's is as it was")
    eq(ItemTip(603), "Arms +12 pts | Protection +12 pts | Needs a one-hand weapon in your main hand", "the shield's tooltip reads as its row's does")
    eq(ItemTip(602), 'Arms +20 pts | Protection +15 pts | Replaces your two-hand weapon and is not compared with it: one-hand is chosen in the "Weapons" filter.',
        "and the mace's: its own worth, and whose place it takes")
    eq(ItemTip(600), "Arms +50% | Protection +100%", "the axe's still says what it has over the maul: the choice takes its arrow, not its line")
    -- The best set for a budget is made of the same.
    local bar = frame.PlanBar
    bar.Check:SetChecked(true)
    bar.Check:Click()
    Settle()
    check(Row("Sharp Sword") ~= nil and Row("Oak Shield") ~= nil and Row("Helm") ~= nil, "the set: the sword, the shield beside it, the helm")
    eq(Row("Long Axe"), nil, "and not the axe"); eq(Row("Oak Shield").entry.note, nil, "in a set the shield goes beside the sword: nothing more to note")
    eq(Names(), "One-hand", "the choice keeps its name beside the field")
    -- A shield that was bought and is not yet held counts as held, for one going over to one
    -- hand: a set has no second one.
    S.acquired[#S.acquired + 1] = { link = W.Link(603), itemID = 603, invType = "INVTYPE_SHIELD", value = 12 }
    ns.UI.Refresh()
    check(Row("Sharp Sword") ~= nil, "with the shield bought, the set still has the sword"); eq(Row("Oak Shield"), nil, "and no shield: the one bought is as good")
    table.remove(S.acquired)
    ns.UI.Refresh()
    check(Row("Oak Shield") ~= nil, "without the purchase the shield is in the set again")
    bar.Check:SetChecked(false)
    bar.Check:Click()
    Settle()

    -- A kind of weapon unticked: the menu stays open here too, and the list is without it.
    weapons:Click("One-Handed Swords", function(open, sub)
        eq(open._open, true, "the menu stays open after a tick box"); eq(sub.lines[8].Tick:IsShown(), false, "and the tick is gone from the line")
    end)
    eq(Chosen(me).kinds[7], false, "written on the card"); eq(Row("Sharp Sword"), nil, "no sword in the list")
    eq(Names(), "One-hand \194\183 Weapons 13/14", "beside the field: how many kinds are still offered")
    eq(Named(), "One-hand, shield and off-hand | Weapon types: 13 of 14", "and in its tooltip")
    W.Run(1.5)
    eq(Arrow(sword), false, "the sword in the bags has lost its arrow")
    weapons:Click("One-Handed Swords")
    eq(Chosen(me).kinds[7], true, "ticked again: written on the card as ticked"); check(Row("Sharp Sword") ~= nil, "and the sword is back")
    eq(Names(), "One-hand", "with every kind as the menu first had it, the kinds are not named beside the field")
    W.Run(1.5)
    eq(Arrow(sword), true, "with its arrow")
    -- A two-hander.
    weapons:Click("Two-hand")
    eq(Chosen(me).hands, "TWO", "two hands, chosen"); eq(Names(), "Two-hand", "named beside the field")
    check(Row("Long Axe") ~= nil, "the axe is back"); eq(Row("Sharp Sword"), nil, "the sword is out"); eq(Row("Oak Shield"), nil, "and the shield")
    W.Run(1.5)
    eq(Arrow(axe), true, "in the bags the axe has its arrow"); eq(Arrow(sword), false, "and the sword none")
    weapons:Click("Any")
    eq(Chosen(me).hands, "ANY", "any way, chosen: written down like the others"); eq(Names(), "", "and no filter")
    Settle()

    -- The list for the druid: the menu is the druid's, with a druid's kinds and what the
    -- druid left chosen, and what is clicked there is written on the druid's card alone.
    W.RunUntil(function() return W.AH.ready end, 5)
    frame.ProfileDropdown:Pick(3)
    W.Run(0.5)
    eq(ns.Roster.Target(), druid, "the lists are for the druid")
    eq(weapons:Lines(), "( ) Any | (x) Two-hand | ( ) One-hand, shield and off-hand | / | [x] One-Handed Maces | [ ] Daggers | [x] Fist Weapons | / | "
        .. "[x] Two-Handed Maces | [x] Polearms | [x] Staves", "the druid's menu: its kinds, and its choices as it left them")
    eq(weapons:Head(), "Profile: " .. ns.Score.Current(druid).title, "headed by the druid's profile")
    eq(Names(), "Two-hand \194\183 Weapons 5/6", "named beside the field")
    frame.ScanButton:Click()
    Settle()
    check(Row("Elder Staff") ~= nil, "the staff is listed for the druid")
    eq(Row("Stone Mace"), nil, "the mace is not"); eq(Row("Grove Orb"), nil, "nor the orb"); eq(Row("Moon Dagger"), nil, "nor the dagger")
    eq(Offer("Stone Mace"), nil, "and no price was looked up for what the druid does not want")
    weapons:Click("Any")
    eq(Chosen(druid).hands, "ANY", "any way, on the druid's card"); eq(Chosen(me).hands, "ANY", "the warrior's own is its own")
    check(Row("Stone Mace") ~= nil and Row("Grove Orb") ~= nil, "the mace and the orb are listed at once"); eq(Row("Moon Dagger"), nil, "the dagger still is not")
    weapons:Click("Daggers")
    eq(Chosen(druid).kinds[15], true, "daggers ticked for the druid"); eq(Chosen(me).kinds[15], nil, "and nothing of it on the warrior's card")
    check(Row("Moon Dagger") ~= nil, "the dagger is listed")
    Settle()
    check(Offer("Stone Mace") ~= nil and Offer("Grove Orb") ~= nil and Offer("Moon Dagger") ~= nil, "and the three have their prices")
    weapons:Click("One-hand, shield and off-hand")
    eq(Chosen(druid).hands, "ONE", "one hand for the druid")
    eq(Arrow(axe), true, "the arrows stay the warrior's: its own choice is any way")

    -- Back to the warrior, on Protection now: the profile of a shield tank. Any way was what
    -- it chose on Arms, and is Arms's: on Protection it has not chosen. A character that has
    -- not is offered one hand there, the line the profile chose is the one marked, and its
    -- tooltip says who chose.
    frame.ProfileDropdown:Pick(2)
    Settle()
    eq(ns.Roster.Target(), nil, "the lists are the warrior's own"); eq(me.profile, "WARRIOR_PROTECTION", "on Protection")
    eq(Chosen(me).hands, nil, "the card has no choice for that profile"); eq(me.byProfile["own:S1"].hands, "ANY", "what it chose on Arms is kept for Arms")
    eq(weapons:Head(), "Profile: Protection", "the menu is headed by the profile it is now for")
    eq(weapons:Lines(), "( ) Any | ( ) Two-hand | (x) One-hand, shield and off-hand | / | " .. WARRIOR_KINDS, "and the menu marks the line the profile chose")
    eq(weapons:Tooltip("One-hand, shield and off-hand"),
        "One-hand, shield and off-hand | " .. L.HANDS_ONE_TIP .. ' | The addon picked this for the profile "Protection". You can pick another.', "whose tooltip says so")
    eq(weapons:Tooltip("Two-hand"), "Two-hand | " .. L.HANDS_TWO_TIP, "the other lines' say nothing of it")
    eq(Names(), "One-hand", "it is named beside the field, as a choice of the player's is")
    check(Row("Oak Shield") ~= nil and Row("Sharp Sword") ~= nil, "the list: the shield, and the sword that beats the maul on this profile")
    eq(Row("Long Axe"), nil, "and no two-hander")
    W.Run(1.5)
    eq(Arrow(axe), false, "nor an arrow on the one in the bags")
    -- "Any" chosen: it is written down, and holds on that profile.
    weapons:Click("Any")
    eq(Chosen(me).hands, "ANY", "any way, chosen")
    eq(weapons:Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | " .. WARRIOR_KINDS, "the menu marks it")
    eq(weapons:Tooltip("One-hand, shield and off-hand"), "One-hand, shield and off-hand | " .. L.HANDS_ONE_TIP, "and the profile's line says no more of the profile")
    eq(Names(), "", "no filter is on")
    Settle()
    check(Row("Long Axe") ~= nil, "the axe is listed"); eq(Row("Oak Shield"), nil, "the shield is not")
    -- Each profile of the warrior has a choice of its own. On Arms again the menu is as Arms
    -- left it; two hands and no daggers, chosen now, are Arms's alone. Another profile chosen
    -- in the profile field makes the list anew by itself, as it always did (its scores were
    -- another profile's): that list, the names beside the field and the arrows in the bags
    -- go by the choice of the profile chosen, with no click in the Filters menu.
    frame.ProfileDropdown:Pick(1)
    Settle()
    eq(ns.Score.Current(me).name, "S1", "on Arms again"); eq(weapons:Head(), "Profile: Arms", "whose menu it is")
    eq(weapons:Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | " .. WARRIOR_KINDS, "as Arms left it")
    weapons:Click("Two-hand")
    weapons:Click("Daggers")
    Settle()
    eq(Names(), "Two-hand \194\183 Weapons 13/14", "two hands and no daggers, on Arms")
    check(Row("Long Axe") ~= nil, "Arms's list: the axe"); eq(Row("Sharp Sword"), nil, "and no sword")
    W.Run(1.5)
    eq(Arrow(sword), false, "nor an arrow on the one in the bags")
    local scans = S.finishedAt
    frame.ProfileDropdown:Pick(2)
    Settle()
    eq(weapons:Head(), "Profile: Protection", "Protection chosen: the menu is Protection's")
    eq(weapons:Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | " .. WARRIOR_KINDS, "as Protection left it: any way, and every kind")
    eq(Names(), "", "nothing beside the field")
    check(S.finishedAt ~= nil and S.state == "idle" and scans ~= nil, "the list was made anew for the profile, by itself")
    check(Row("Long Axe") ~= nil and Row("Sharp Sword") ~= nil, "and has the sword again, beside the axe")
    eq(S.Unchecked().unwanted, 0, "nothing of it is left out for the choice Arms made")
    W.Run(1.5)
    eq(Arrow(sword), true, "the sword in the bags has its arrow again")
    eq(me.byProfile["own:S1"].hands, "TWO", "the card has both: two hands for Arms"); eq(me.byProfile["own:S1"].kinds[15], false, "without daggers")
    eq(me.byProfile["own:WARRIOR_PROTECTION"].hands, "ANY", "and any way for Protection"); eq(me.byProfile["own:WARRIOR_PROTECTION"].kinds, nil, "with every kind")
    -- It is there the next time the character is played, still on Protection.
    W.CloseAuctionHouse()
    Relog(W.player, W.equipped)
    me = ns.Roster.Me()
    eq(me.profile, "WARRIOR_PROTECTION", "played again: on Protection"); eq(Chosen(me).hands, "ANY", "with its choice")
    eq(me.byProfile["own:S1"].hands, "TWO", "and with what Arms chose, for when it is on Arms")
    eq(ns.Wants.Of(me), nil, "which asks for nothing")
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    eq(WeaponsMenu():Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | " .. WARRIOR_KINDS, "as the menu shows")
    eq(Chosen(UpgradeScoutDB.chars["Alty-Testrealm"]).hands, "ONE", "and the druid's card has what was chosen for the druid")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- The tab with a list on it, for the three scenarios below: each is what a player wrote of
-- the addon, as it was and as it is with the "Weapons" line.
--   Row(name)   the row of an upgrade, wherever in the list it is
--   Rows()      the names of the upgrades listed, in order of the alphabet
--   Settle()    waits for the scanner, and for the list to be drawn
--   Names()     what stands beside the Filters field
local function Tab()
    W.OpenAuctionHouse()
    LibStub("LibAHTab-1-0"):SetSelected("UpgradeScout")
    local tab = { frame = UpgradeScoutFrame, menu = WeaponsMenu() }
    local box
    for _, w in ipairs(W.frames) do
        if w._template == "WowScrollBoxList" then box = w end
    end
    local function Seen(found)
        for _, at in ipairs({ 0, 1 }) do
            box:SetScrollPercentage(at)
            for _, w in ipairs(box:GetFrames()) do
                if w._shown and w._kind == "Button" and w.entry and w.entry.offer then found(w) end
            end
        end
    end
    function tab.Row(name)
        local row
        Seen(function(w) if w.entry.offer.name == name then row = row or w end end)
        return row
    end
    function tab.Rows()
        local out, seen = {}, {}
        Seen(function(w)
            local name = w.entry.offer.name
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end)
        table.sort(out)
        return table.concat(out, ", ")
    end
    function tab.Settle()
        W.RunUntil(function() return ns.Scanner.state == "idle" end, 300)
        W.Run(0.5)
    end
    function tab.Names() return tab.frame.FilterNames:GetText() end
    function tab.Status() return tab.frame.Status:GetText() or "" end
    -- The lines of a row's tooltip, the game's own and ours, joined.
    function tab.Tip(row)
        row:GetScript("OnEnter")(row)
        local out = {}
        for _, line in ipairs(GameTooltip._lines) do out[#out + 1] = line.text .. (line.right and " " .. line.right or "") end
        row:GetScript("OnLeave")(row)
        return table.concat(out, " | ")
    end
    return tab
end

-- "Is there a way to set a weapon type to search for? I want to look for 1h swords but it
-- keeps showing just daggers and axes. This is using the rogue combat settings."
-- In Forever a weapon skill is trained, and the rogue who wrote that had not trained swords:
-- the list left every sword out and said nothing of it. Here, a rogue with a dagger in each
-- hand (10 and 6) that has trained daggers, one-handed axes and thrown weapons. For sale: two
-- axes, two daggers, two swords and a mace; a sword that asks for a profession the rogue has
-- not, and one made for a higher level; a ring and a knife to throw.
function scenarios.weapons_rogue()
    MoreProfiles()
    W.player = { name = "Slicey", level = 20, class = "ROGUE", money = 100000, dualWield = true,
        spells = { [9078] = true, [9077] = true, [1180] = true, [196] = true, [2567] = true } }
    local function Blade(id, name, kind, score, price, more)
        local def = { id = id, name = name, equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = kind, value = 0, values = { R1 = score }, level = 15 }
        for key, value in pairs(more or {}) do def[key] = value end
        if price then return Sell(def, price) end
        return W.AddItem(def)
    end
    Blade(700, "Worn Dirk", 15, 10)
    Blade(701, "Worn Shiv", 15, 6)
    W.equipped = { [16] = W.Link(700), [17] = W.Link(701) }
    Blade(710, "Hand Axe", 0, 18, 4000)
    Blade(711, "War Hatchet", 0, 17, 2800)
    Blade(712, "Fine Dirk", 15, 16, 1800)
    Blade(713, "Keen Kris", 15, 15, 1000)
    Blade(714, "Cutlass", 7, 14, 2000)
    Blade(715, "Rapier", 7, 13, 900)
    Blade(716, "Cudgel", 4, 12, 1800)
    Blade(719, "Smith's Blade", 7, 30, 1500, { skill = { "Blacksmithing", 100 } })
    Blade(720, "Future Blade", 7, 40, 1500, { level = 25 })
    Sell({ id = 717, name = "Throwing Knife", equipLoc = "INVTYPE_THROWN", classID = 2, subClassID = 16, value = 0, values = { R1 = 3 }, level = 10 }, 100)
    Sell({ id = 718, name = "Band", equipLoc = "INVTYPE_FINGER", value = 0, values = { R1 = 5 }, level = 10 }, 300)
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local me = ns.Roster.Me()
    local S, L, Wants = ns.Scanner, ns.L, ns.Wants
    eq(ns.Score.Current().title, "Combat", "a rogue on Combat")
    eq(me.weapons[15], true, "its card has the daggers it has trained"); eq(me.weapons[7], nil, "and no swords")
    -- A mace in the bags, better than the dagger in the main hand: no arrow while maces are
    -- not trained.
    local cudgel = W.PutInBags(W.Link(716))
    W.OpenBags()
    W.Run(0.5)
    local function Arrow(slot)
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(Arrow(cudgel), false, "a mace in the bags has no arrow: the rogue has not trained maces")
    local tab = Tab()
    local Row, Rows, Settle, menu = tab.Row, tab.Rows, tab.Settle, tab.menu
    local SWORDS, FISTS = "One-Handed Swords (not trained)", "Fist Weapons (not trained)"
    local NOTE = "Train One-Handed Swords to use this weapon."
    local PLAIN = "Band, Fine Dirk, Hand Axe, Keen Kris, Throwing Knife, War Hatchet"
    local WITH_SWORDS = "Band, Cutlass, Fine Dirk, Hand Axe, Keen Kris, Rapier, Throwing Knife, War Hatchet"
    -- The menu of a rogue's kinds, with these three as given.
    local function Kinds(maces, swords, fists)
        return "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | [x] One-Handed Axes | " .. maces .. " | " .. swords
            .. " | [x] Daggers | " .. fists .. " | / | [ ] Bows (not trained) | [ ] Crossbows (not trained) | [ ] Guns (not trained) | [x] Thrown"
    end
    -- The best set for all its gold that can be made of these offers.
    local function Set(offers)
        local set = {}
        for _, row in ipairs(ns.Plan.Rows(ns.Plan.Choose(ns.Plan.Ladder(offers, S.ctx, GetMoney(), Wants.Of(me)), GetMoney()))) do
            if row.kind == "item" then set[#set + 1] = row.entry.offer.name end
        end
        table.sort(set)
        return table.concat(set, ", ")
    end
    -- How many upgrades the list counts as left out by a filter, seen and unseen.
    local function LeftOut()
        local _, _, unwanted = ns.Results.Collect(S.offers, S.ctx, { money = GetMoney(), wants = Wants.Of(me) })
        return unwanted + S.Unchecked().unwanted
    end

    -- As the player found it: daggers and axes, and no sword. Nothing is named beside the
    -- Filters field, for nobody set a filter, and nothing is counted as left out.
    SetView(false, false)
    ScanToEnd()
    W.Run(0.5)
    eq(Rows(), PLAIN, "the list: daggers and axes, a ring and a knife to throw, and no sword")
    eq(Offer("Cutlass"), nil, "no price was looked up for a sword"); eq(Unsure("Cutlass"), nil, "and none is in the list unseen")
    eq(tab.Names(), "", "no filter is named beside the field"); eq(LeftOut(), 0, "and nothing is counted as left out by one")
    -- The menu says why, and is where it is put right: the kinds the rogue has not trained
    -- say so after their names, and are not ticked.
    eq(menu:Lines(), Kinds("[ ] One-Handed Maces (not trained)", "[ ] " .. SWORDS, "[ ] " .. FISTS),
        "the menu: a rogue's nine kinds, those it has trained ticked, the others marked and unticked")
    eq(L.KINDS_UNTRAINED:format("One-Handed Swords"), SWORDS, "in the addon's own words, about the game's own name")
    eq(menu:Tooltip(SWORDS), SWORDS .. " | " .. L.KINDS_TIP .. " | " .. L.KINDS_UNTRAINED_TIP, "its tooltip says what a tick on it does")
    eq(menu:Tooltip("Daggers"), "Daggers | " .. L.KINDS_TIP, "a kind that is trained has the tooltip it had")
    eq(menu:Line(SWORDS, function(line) return line.Tick:IsShown() end), false, "the box as the game drew it: not ticked")

    -- Swords ticked: "offer me these, I will train". The list has them at once, with no
    -- other scan, and their prices are looked up.
    local searches, browses = W.AH.calls.search, W.AH.calls.browse
    menu:Click(SWORDS)
    eq(Chosen(me).kinds[7], true, "the tick is written on the card, for the profile")
    check(Row("Cutlass") ~= nil and Row("Rapier") ~= nil, "both swords are in the list at once")
    check(Unsure("Cutlass") ~= nil, "at the lowest price of their rows, until it is looked up")
    Settle()
    eq(W.AH.calls.search, searches + 2, "two item searches, for the prices of the two"); eq(W.AH.calls.browse, browses, "and no other scan")
    check(Offer("Cutlass") ~= nil and Offer("Rapier") ~= nil, "which are known now")
    eq(Rows(), WITH_SWORDS, "the list with the swords")
    eq(Row("Cutlass").Upgrade:GetText(), "+25%", "14 against the dagger's 10: a share of the 16 the two hands hold")
    eq(Row("Smith's Blade"), nil, "a sword that asks for a profession as well stays out: more than its kind is red")
    eq(Row("Future Blade"), nil, "and so does one made for a higher level"); eq(Row("Cudgel"), nil, "and the mace: another kind not trained, and not ticked")
    check(tab.Tip(Row("Cutlass")):find(NOTE, 1, true) ~= nil, "the row's tooltip says what the sword takes: " .. tab.Tip(Row("Cutlass")))
    eq(L.TT_UNTRAINED:format("One-Handed Swords"), NOTE, "in the addon's own words")
    eq(tab.Tip(Row("Fine Dirk")):find("trained", 1, true), nil, "a dagger's says nothing of it")
    eq(menu:Lines(), Kinds("[ ] One-Handed Maces (not trained)", "[x] " .. SWORDS, "[ ] " .. FISTS), "the menu: swords ticked, and not trained still")
    eq(tab.Names(), "Weapons 4/9", "beside the field: four of a rogue's nine kinds are ticked, which is not how the menu first had them")
    eq(LeftOut(), 0, "nothing is left out by that")
    -- The best set for a budget has no sword: a set is to be worn as it is bought.
    local cutlass, trained = Offer("Cutlass"), {}
    for key, value in pairs(cutlass) do trained[key] = value end
    trained.untrained = nil
    eq(cutlass.untrained, true, "the offer of a sword says that its kind is not trained")
    eq(Set({ cutlass, Offer("Band") }), "Band", "of the sword and the ring, the best set is the ring alone")
    eq(Set({ trained, Offer("Band") }), "Band, Cutlass", "which the sword would be in, were swords trained")
    eq(Set(S.offers):find("Cutlass", 1, true), nil, "and the best set of all that is for sale has none")

    -- Unticked again: the swords are gone as if never asked for. Ticked once more: they are
    -- back with the prices they had.
    searches = W.AH.calls.search
    menu:Click(SWORDS)
    eq(Chosen(me).kinds[7], false, "unticked: written on the card as the player's own, like the tick")
    eq(Rows(), PLAIN, "the list is without swords at once"); eq(Offer("Cutlass"), nil, "no offer of one is in it")
    eq(LeftOut(), 0, "and none is counted as left out"); eq(tab.Names(), "", "the menu is as it first was: nothing beside the field")
    menu:Click(SWORDS)
    Settle()
    eq(Rows(), WITH_SWORDS, "ticked again: the swords are back"); eq(W.AH.calls.search, searches, "at the prices they had, with no item search")
    -- A scan with swords ticked has them from the start.
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.5)
    eq(Rows(), WITH_SWORDS, "a scan with swords ticked lists them")
    check(tab.Tip(Row("Rapier")):find(NOTE, 1, true) ~= nil, "each with the note")

    -- The rogue trains swords, maces and fist weapons. A kind trained is ticked like the
    -- others, with no mark: the swords by the player's tick, the maces because nobody
    -- touched their box. What the player unticked stays unticked: fist weapons, ticked and
    -- unticked again before they were trained.
    menu:Click(FISTS)
    menu:Click(FISTS)
    eq(Chosen(me).kinds[13], false, "fist weapons ticked and unticked again: unticked, by the player"); eq(tab.Names(), "Weapons 4/9", "which is no news while they are not trained")
    W.player.spells[201], W.player.spells[198], W.player.spells[15590] = true, true, true
    W.Fire("SPELLS_CHANGED")
    W.Run(1.5)
    eq(me.weapons[7], true, "trained: the card has the swords"); eq(ns.Roster.Untrained(me, 4), false, "and the maces")
    eq(Arrow(cudgel), true, "the mace in the bags has its arrow, with the bags left open: the arrows are drawn again when the card has the new skill")
    eq(menu:Lines(), Kinds("[x] One-Handed Maces", "[x] One-Handed Swords", "[ ] Fist Weapons"),
        "the menu: swords and maces ticked and no longer marked, fist weapons unticked as the player left them")
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.5)
    eq(tab.Names(), "Weapons 5/9", "beside the field, five of nine: the fist weapons, trained and unticked, are a filter the player set")
    eq(Rows(), "Band, Cudgel, Cutlass, Fine Dirk, Hand Axe, Keen Kris, Rapier, Throwing Knife, War Hatchet", "a scan: the swords, and the mace as well")
    eq(tab.Tip(Row("Cutlass")):find("trained", 1, true), nil, "the sword's row has no note any more"); eq(Offer("Cutlass").untrained, nil, "its offer is like any other")
    eq(Set({ Offer("Cutlass"), Offer("Band") }), "Band, Cutlass", "and a set can have it")
    eq(Row("Smith's Blade"), nil, "the sword that asks for a profession is as far out of reach as it was")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- A hunter's thrown weapons. Its shots take a bow, a gun or a crossbow, and a thrown weapon
-- goes where that is held: whatever its stats add up to, it is no upgrade to a hunter. So
-- that box of the Weapons menu is unticked for a hunter until the player ticks it, trained
-- or not, and nothing is said of a filter: nobody set one. Any other class has the box
-- ticked once it has trained the skill. Here, a hunter with a bow that has trained bows,
-- thrown weapons, daggers and one-handed axes. For sale: a better bow, a throwing knife
-- that scores more than either bow, and a ring.
function scenarios.weapons_hunter()
    moreWeights = function(data)
        data.classes.HUNTER = { "H1" }
        data.start.HUNTER = "H1"
        data.titles.enUS.H1 = "Beast Mastery"
        data.profiles.H1 = { class = "HUNTER", weights = { TEST_H1 = 1 } }
    end
    W.player = { name = "Aimy", level = 20, class = "HUNTER", money = 100000, dualWield = true,
        spells = { [9078] = true, [9077] = true, [264] = true, [2567] = true, [1180] = true, [196] = true } }
    W.AddItem({ id = 800, name = "Worn Bow", equipLoc = "INVTYPE_RANGED", classID = 2, subClassID = 2, value = 0, values = { H1 = 10 }, level = 10 })
    W.equipped = { [18] = W.Link(800) }
    Sell({ id = 810, name = "Fine Bow", equipLoc = "INVTYPE_RANGED", classID = 2, subClassID = 2, value = 0, values = { H1 = 14 }, level = 15 }, 2000)
    Sell({ id = 811, name = "Keen Knife", equipLoc = "INVTYPE_THROWN", classID = 2, subClassID = 16, value = 0, values = { H1 = 20 }, level = 15 }, 500)
    Sell({ id = 812, name = "Band", equipLoc = "INVTYPE_FINGER", value = 0, values = { H1 = 5 }, level = 10 }, 300)
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local me = ns.Roster.Me()
    local Wants = ns.Wants
    eq(ns.Score.Current().title, "Beast Mastery", "a hunter on Beast Mastery")
    eq(me.weapons[16], true, "its card has the thrown weapons it has trained"); eq(me.weapons[2], true, "and the bows")

    -- What is asked of its gear before anything is touched.
    eq(Wants.KindOut(me, 16), true, "thrown weapons are left out, trained though they are"); eq(Wants.KindOut(me, 2), false, "bows are not")
    local out, gone, changed = Wants.KindsOut(me)
    eq(gone, 9, "nine of a hunter's twelve kinds are out: eight not trained, and the thrown weapons"); eq(changed, 0, "none of them by the player's doing")
    eq(out[16], true, "the thrown weapons among them"); eq(Wants.Of(me).kinds[16], true, "which is asked of its gear")
    -- Another class has them as soon as it has trained them; a hunter that has not trained
    -- them is as any character with a kind not trained; a card that does not say what was
    -- learned has every other kind for trained, and a hunter's thrown weapons out all the same.
    eq(Wants.KindOut({ class = "ROGUE", level = 20, weapons = { [15] = true, [16] = true } }, 16), false, "a rogue that has trained thrown weapons is offered them")
    eq(Wants.KindOut({ class = "WARRIOR", level = 20, weapons = { [7] = true, [16] = true } }, 16), false, "and so is a warrior")
    eq(Wants.KindOut({ class = "ROGUE", level = 20, weapons = { [15] = true } }, 16), true, "one that has not is not, as with any kind")
    eq(Wants.KindOut({ class = "HUNTER", level = 20, weapons = { [2] = true } }, 16), true, "a hunter that has not trained them: out")
    local bare = { class = "HUNTER", level = 20 }
    eq(Wants.KindOut(bare, 16), true, "a hunter's card that does not say what was learned: out"); eq(Wants.KindOut(bare, 2), false, "and its bows in")
    _, gone, changed = Wants.KindsOut(bare)
    eq(gone, 1, "one kind out of twelve"); eq(changed, 0, "which is how the menu first has it")

    local tab = Tab()
    local Row, Rows, Settle, menu = tab.Row, tab.Rows, tab.Settle, tab.menu
    local function Kinds(thrown)
        return "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | [x] One-Handed Axes | [ ] One-Handed Swords (not trained) | [x] Daggers | "
            .. "[ ] Fist Weapons (not trained) | / | [ ] Two-Handed Axes (not trained) | [ ] Two-Handed Swords (not trained) | [ ] Polearms (not trained) | "
            .. "[ ] Staves (not trained) | / | [x] Bows | [ ] Crossbows (not trained) | [ ] Guns (not trained) | " .. thrown
    end
    eq(menu:Lines(), Kinds("[ ] Thrown"), "the menu: thrown weapons unticked, and not marked as a kind not trained")
    -- In the bags: the better bow has its arrow, the knife has none.
    local bow, knife = W.PutInBags(W.Link(810)), W.PutInBags(W.Link(811))
    W.OpenBags()
    W.Run(0.5)
    local function Arrow(slot)
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    eq(Arrow(bow), true, "the better bow in the bags has its arrow"); eq(Arrow(knife), false, "the throwing knife has none")

    -- A scan: the bow and the ring, and no knife, though it scores twice the worn bow.
    SetView(false, false)
    local searches = W.AH.calls.search
    ScanToEnd()
    W.Run(0.5)
    eq(Rows(), "Band, Fine Bow", "the list: the bow and the ring, and no throwing knife")
    eq(W.AH.calls.search - searches, 2, "two item searches: no price is looked up for the knife"); eq(Offer("Keen Knife"), nil, "which has none")
    eq(tab.Names(), "", "no filter is named beside the field: nobody set one")
    check(tab.Status():find("2 upgrades in 2 slots.", 1, true) ~= nil, "two upgrades: " .. tab.Status())

    -- Ticked: the knife is in the list at once, for the ranged slot, and has its arrow.
    menu:Click("Thrown")
    eq(Chosen(me).kinds[16], true, "the tick is written on the card, for the profile")
    check(Row("Keen Knife") ~= nil, "the knife is in the list at once")
    Settle()
    eq(W.AH.calls.search - searches, 3, "one more item search, for its price"); check(Offer("Keen Knife") ~= nil, "which is known")
    eq(Rows(), "Band, Fine Bow, Keen Knife", "the list with the knife"); eq(Row("Keen Knife").Upgrade:GetText(), "+100%", "20 against the bow's 10")
    eq(menu:Lines(), Kinds("[x] Thrown"), "the menu: ticked")
    eq(tab.Names(), "Weapons 4/12", "named beside the field: four of twelve, which is not how the menu first had them")
    W.Run(0.5)
    eq(Arrow(knife), true, "the knife in the bags has its arrow now")
    -- Unticked again: as it first was.
    menu:Click("Thrown")
    eq(Chosen(me).kinds[16], false, "unticked: written on the card")
    eq(Rows(), "Band, Fine Bow", "the knife is out of the list"); eq(tab.Names(), "", "and nothing is named beside the field")
    _, gone, changed = Wants.KindsOut(me)
    eq(gone, 9, "nine kinds out again"); eq(changed, 0, "as an untouched menu has them")
    W.Run(0.5)
    eq(Arrow(knife), false, "and the knife's arrow is gone"); eq(Arrow(bow), true, "the bow keeps its own")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- A kind of weapon not trained, for another character of the account: by what its card says
-- it had learned when it was last played, and by what else the item asks of it. Then the
-- best set, a card that does not say what was learned, and nonsense on a card.
function scenarios.weapons_untrained()
    MoreProfiles()
    local function ForDruid(id, name, equipLoc, kind, score, price, more)
        local def = { id = id, name = name, equipLoc = equipLoc, classID = 2, subClassID = kind, value = 0, values = { D1 = score }, level = 15 }
        for key, value in pairs(more or {}) do def[key] = value end
        return Sell(def, price)
    end
    ForDruid(780, "Elder Staff", "INVTYPE_2HWEAPON", 10, 40, 1000)
    ForDruid(781, "Stone Mace", "INVTYPE_WEAPON", 4, 30, 900)
    ForDruid(782, "Moon Dagger", "INVTYPE_WEAPON", 15, 20, 700)
    ForDruid(783, "Smith's Mace", "INVTYPE_WEAPON", 4, 35, 800, { skill = { "Blacksmithing", 100 } })
    ForDruid(784, "Bear Claw", "INVTYPE_WEAPON", 13, 25, 600)
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local S, Wants, Roster = ns.Scanner, ns.Wants, ns.Roster
    -- The druid as it was when it was last played: it had trained staves and daggers.
    UpgradeScoutDB.chars["Alty-Testrealm"] = { key = "Alty-Testrealm", name = "Alty", realm = "Testrealm", faction = "Alliance",
        class = "DRUID", level = 20, gear = {}, weapons = { [10] = true, [15] = true } }
    local druid = UpgradeScoutDB.chars["Alty-Testrealm"]
    eq(Roster.Untrained(druid, 4), true, "maces: a kind a druid can train, and this one has not"); eq(Roster.Untrained(druid, 10), false, "staves it has")
    eq(Roster.Untrained(druid, 7), false, "a sword is no kind a druid can ever train: that is another matter"); eq(Roster.Untrained(druid, 99), false, "as is what is no kind at all")
    eq(Wants.KindOut(druid, 4), true, "a kind not trained is left out until it is ticked"); eq(Wants.KindOut(druid, 10), false, "one that is trained is not")
    local _, gone, changed = Wants.KindsOut(druid)
    eq(gone, 4, "four of a druid's six kinds are out"); eq(changed, 0, "none of them by the player's doing"); eq(Wants.Of(druid).kinds[4], true, "which is asked of its gear")

    local tab = Tab()
    local Row, Rows, Settle, menu = tab.Row, tab.Rows, tab.Settle, tab.menu
    tab.frame.ProfileDropdown:Pick(3)
    W.Run(0.5)
    eq(Roster.Target(), druid, "the lists are for the druid")
    local MACES = "One-Handed Maces (not trained)"
    -- How many upgrades the list counts as left out by a filter, seen and unseen.
    local function LeftOut()
        local _, _, unwanted = ns.Results.Collect(S.offers, S.ctx, { money = GetMoney(), wants = Wants.Of(druid) })
        return unwanted + S.Unchecked().unwanted
    end
    eq(menu:Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | [ ] " .. MACES .. " | [x] Daggers | [ ] Fist Weapons (not trained) | / | "
        .. "[ ] Two-Handed Maces (not trained) | [ ] Polearms (not trained) | [x] Staves", "the druid's menu, by its card")
    SetView(false, false)
    tab.frame.ScanButton:Click()
    Settle()
    eq(Rows(), "Elder Staff, Moon Dagger", "the druid's list: the staff and the dagger, and neither mace nor claw")
    eq(tab.Names(), "", "no filter beside the field"); eq(LeftOut(), 0, "and nothing counted as left out")
    -- Maces ticked for the druid.
    local searches = W.AH.calls.search
    menu:Click(MACES)
    check(Row("Stone Mace") ~= nil, "the mace is in the list at once")
    Settle()
    eq(W.AH.calls.search, searches + 1, "one item search, for its price"); check(Offer("Stone Mace") ~= nil, "which is known")
    eq(Rows(), "Elder Staff, Moon Dagger, Stone Mace", "the list with the mace")
    eq(Row("Smith's Mace"), nil, "a mace that asks for a profession the druid has not is out of its reach, trained or not")
    eq(Row("Bear Claw"), nil, "and the claw is of another kind not trained, and not ticked")
    check(tab.Tip(Row("Stone Mace")):find("One-Handed Maces has to be trained to use this weapon.", 1, true) ~= nil,
        "the row's tooltip says what the mace takes, of a character that is not the one played: " .. tab.Tip(Row("Stone Mace")))
    eq(tab.Names(), "Weapons 3/6", "named beside the field")
    -- No set for a budget is made of a weapon that cannot be held yet.
    local function Rungs(name) return #ns.Plan.Ladder({ Offer(name) }, S.ctx, GetMoney(), Wants.Of(druid)) end
    eq(Rungs("Stone Mace"), 1, "no set is made of the mace"); eq(Rungs("Moon Dagger"), 2, "as one is of the dagger")
    -- Unticked again.
    menu:Click(MACES)
    eq(Rows(), "Elder Staff, Moon Dagger", "unticked: the mace is gone"); eq(tab.Names(), "", "and so is the name beside the field")
    eq(LeftOut(), 0, "nothing is counted as left out")

    -- A card that does not say what the character had learned (the game would not tell):
    -- every kind of its class counts as trained, as it always did. The maces, which the
    -- player unticked, stay unticked, and are a filter now.
    druid.weapons = nil
    eq(menu:Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | [ ] One-Handed Maces | [x] Daggers | [x] Fist Weapons | / | "
        .. "[x] Two-Handed Maces | [x] Polearms | [x] Staves", "the menu of a card that does not say: no kind marked, and the maces as the player left them")
    tab.frame.ScanButton:Click()
    Settle()
    eq(Rows(), "Bear Claw, Elder Staff, Moon Dagger", "the list: the claw as well"); eq(tab.Names(), "Weapons 5/6", "five kinds of six")
    eq(LeftOut(), 1, "and the mace is counted as left out by a filter, which it now is")
    check(tab.Tip(Row("Bear Claw")):find("trained", 1, true) == nil, "the claw's row has no note")
    -- Nonsense on a card, which comes out of a saved file.
    for _, junk in ipairs({ 5, "all", true, false, function() end }) do
        druid.weapons = junk
        eq(Roster.Untrained(druid, 4), false, "a card with a " .. type(junk) .. " for what was learned says nothing: every kind counts as trained")
    end
    druid.weapons = { [10] = "yes", [15] = 1, [4] = true }
    eq(Roster.Untrained(druid, 10), true, "only what is plainly learned is"); eq(Roster.Untrained(druid, 4), false, "as the maces here")
    druid.weapons = { [10] = true, [15] = true }
    druid.byProfile = { [Wants.ProfileKey(druid)] = { kinds = { [4] = "yes", [13] = 1, [5] = 0, [10] = "no", [6] = {} } } }
    eq(Wants.KindOut(druid, 4), true, "a box with nonsense for its tick is a box not touched: not trained, out"); eq(Wants.KindOut(druid, 10), false, "trained, offered")
    _, gone, changed = Wants.KindsOut(druid)
    eq(gone, 4, "four kinds out, as with nothing written"); eq(changed, 0, "and none by the player")
    Wants.SetKind(druid, 4, true)
    eq(Wants.KindOut(druid, 4), false, "a tick is written over the nonsense")

    -- What is red in a tooltip: the kind alone, or more than the kind.
    local RED, WHITE, TYPES = RED_FONT_COLOR, HIGHLIGHT_FONT_COLOR, Enum.TooltipDataLineType
    local name = { leftText = "Blade", leftColor = WHITE }
    local slot = { leftText = "One-Hand", leftColor = WHITE, rightText = "Sword", rightColor = RED }
    eq(ns.OnlyKindRed({ name, slot }), true, "the kind in red on the right of its line, and nothing else")
    eq(ns.OnlyKindRed({ name, { leftText = "One-Hand", leftColor = WHITE, rightText = "Sword", rightColor = WHITE } }), false, "nothing in red")
    eq(ns.OnlyKindRed({ name, slot, { leftText = "Requires Level 30", leftColor = RED, type = TYPES.UsageRequirement, requirementType = 5 } }), false, "a level in red beside it")
    eq(ns.OnlyKindRed({ name, { leftText = "Off Hand", leftColor = RED, rightText = "Sword", rightColor = RED } }), false, "the way it is held in red as well")
    slot.type = TYPES.EquipSlot
    eq(ns.OnlyKindRed({ name, slot }), true, "the line marked as the game's documentation has it")
    slot.type = TYPES.None
    eq(ns.OnlyKindRed({ name, slot }), true, "or not marked at all")
    slot.type = TYPES.UsageRequirement
    eq(ns.OnlyKindRed({ name, slot }), false, "a line that asks something of the owner is not the kind, whichever side of it is red")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- "Just came here for the same thing, want 2h Staff options to show as well as 1h+Offhand on
-- my Lock."
-- A warlock with a dagger (10) and an orb (5). For sale: a staff that beats the two together,
-- one that does not, a sword, an orb and a wand.
function scenarios.weapons_warlock()
    MoreProfiles()
    W.player = { name = "Hexy", level = 20, class = "WARLOCK", money = 100000, dualWield = false, mana = 500 }
    local function Lock(def, score, price)
        def.value, def.values, def.level = 0, { L1 = score }, def.level or 15
        if price then return Sell(def, price) end
        return W.AddItem(def)
    end
    Lock({ id = 730, name = "Worn Athame", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 15 }, 10)
    Lock({ id = 731, name = "Worn Orb", equipLoc = "INVTYPE_HOLDABLE", subClassID = 0 }, 5)
    W.equipped = { [16] = W.Link(730), [17] = W.Link(731) }
    Lock({ id = 740, name = "Rune Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10 }, 22, 2000)
    Lock({ id = 741, name = "Bone Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10 }, 14, 500)
    Lock({ id = 742, name = "Hex Blade", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7 }, 14, 1500)
    Lock({ id = 743, name = "Soul Orb", equipLoc = "INVTYPE_HOLDABLE", subClassID = 0 }, 8, 800)
    Lock({ id = 744, name = "Bone Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subClassID = 19 }, 3, 200)
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local me = ns.Roster.Me()
    local tab = Tab()
    local Row, Rows, Settle, menu = tab.Row, tab.Rows, tab.Settle, tab.menu
    eq(menu:Lines(), "(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | [x] One-Handed Swords | [x] Daggers | / | [x] Staves | / | [x] Wands",
        "a warlock's menu of weapons")

    -- Any way: staves and what goes into one hand and the other, side by side. A staff has to
    -- beat the dagger and the orb together, and is said to take both hands.
    SetView(false, false)
    ScanToEnd()
    W.Run(0.5)
    eq(Rows(), "Bone Wand, Hex Blade, Rune Staff, Soul Orb", "any way: the staff, the sword, the orb, and the wand")
    eq(Row("Rune Staff").Upgrade:GetText(), "+47%", "the staff: 22 against the 15 of both hands")
    eq(Row("Hex Blade").Upgrade:GetText(), "+27%", "the sword: 4 more, of the same 15")
    eq(Row("Bone Staff"), nil, "a staff that does not beat the two together is no upgrade")
    -- Staves alone.
    menu:Click("Two-hand")
    eq(Rows(), "Bone Wand, Rune Staff", "two hands: the staff, and the wand, which is held in neither")
    eq(tab.Names(), "Two-hand", "named beside the Filters field")
    -- One hand and the off hand alone.
    menu:Click("One-hand, shield and off-hand")
    eq(Rows(), "Bone Wand, Hex Blade, Soul Orb", "one hand: the sword and the orb"); eq(tab.Names(), "One-hand", "named beside the field")
    -- Or by the kind: both ways of holding, and no swords.
    menu:Click("Any")
    menu:Click("One-Handed Swords")
    eq(Rows(), "Bone Wand, Rune Staff, Soul Orb", "any way, without swords"); eq(tab.Names(), "Weapons 3/4", "three kinds of four")
    menu:Click("One-Handed Swords")
    eq(Chosen(me).hands, "ANY", "the card has the choice of any way"); eq(Chosen(me).kinds[7], true, "and every kind, the swords by a tick")
    eq(tab.Names(), "", "which is the menu as it first was: nothing beside the field")

    -- The staff goes on. Any way, nothing is offered for the off hand beside it, and no
    -- sword that does not beat it; with one hand chosen the orb is, as what the off hand will
    -- hold, and the sword, as what the main hand will, and no better staff.
    Sell({ id = 745, name = "Elder Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 10, value = 0, values = { L1 = 30 }, level = 18 }, 4000)
    W.equipped = { [16] = W.Link(740) }
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1.5)
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(0.5)
    eq(Rows(), "Bone Wand, Elder Staff", "with the staff held, any way: a better staff, and nothing for the off hand")
    local searches = W.AH.calls.search
    menu:Click("One-hand, shield and off-hand")
    eq(Rows(), "Bone Wand, Hex Blade, Soul Orb", "one hand: the orb and the sword are listed at once, and the staff is not")
    eq(Row("Soul Orb").Upgrade:GetText(), "New", "for the off hand as it will be, empty")
    eq(Row("Hex Blade").Upgrade:GetText(), "New", "the sword for the main hand as it will be: no gain is claimed over the staff held (14 against 22)")
    eq(Row("Hex Blade").entry.note, "REPLACES_TWO_HAND", "whose place it is said to take")
    Settle()
    eq(W.AH.calls.search, searches + 2, "and their prices are looked up")
    eq(Offer("Soul Orb").buyout, 800, "the orb has its own"); eq(Offer("Hex Blade").buyout, 1500, "and the sword")
    menu:Click("Any")
    eq(Rows(), "Bone Wand, Elder Staff", "any way again: the sword and the orb are gone, the staff is back")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- A Protection paladin of level 17: "If I have a two-hand equipped it doesn't suggest
-- changing to a one-hand + shield, and even if I equip a shield it still offers many
-- two-hand... could lead new players to the wrong path."
-- On the weights the addon comes with (Weights.lua), and gear as a paladin of that level
-- finds it: stats by the game's names, a weapon's damage per second among them. The paladin
-- holds a two-handed mace of 15 damage per second. For sale: a stronger two-hander, two
-- swords of 11.6 and 9.2, two shields and a helm. On Protection a point of a weapon's damage
-- per second outweighs every other stat by far: neither sword comes near the maul, nor does
-- the better sword with the better shield beside it come near the two-hander for sale. So
-- the swords are measured as the profile means them to be held, and not against the maul.
function scenarios.weapons_paladin()
    moreWeights = function(data)
        local real = {}
        assert(loadfile(ADDON_DIR .. "Weights.lua"))("UpgradeScout", real)
        for key in pairs(data) do data[key] = nil end
        for key, value in pairs(real.Weights) do data[key] = value end
    end
    W.player = { name = "Shieldy", level = 17, class = "PALADIN", money = 100000, dualWield = false, mana = 300,
        talents = { { name = "Holy", points = 0 }, { name = "Protection", points = 8 }, { name = "Retribution", points = 0 } } }
    local DPS, STRENGTH, STAMINA, ARMOR = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT", "RESISTANCE0_NAME"
    local BLOCK = "ITEM_MOD_BLOCK_VALUE_SHORT"
    -- stats: what the game counts of the item; a shield's block stands in its tooltip alone.
    local function Pala(def, stats, price)
        def.game, def.level = stats, def.level or 15
        if price then return Sell(def, price) end
        return W.AddItem(def)
    end
    local maul = Pala({ id = 750, name = "Worn Maul", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 5, speed = 3.2 },
        { [DPS] = 15, [STRENGTH] = 4, [STAMINA] = 3 })
    W.equipped = { [16] = W.Link(750) }
    local great = Pala({ id = 760, name = "Great Hammer", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 5, speed = 3.4, level = 17 },
        { [DPS] = 17.5, [STRENGTH] = 6, [STAMINA] = 5 }, 3000)
    local guard = Pala({ id = 761, name = "Guard Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, speed = 2.3, level = 17 },
        { [DPS] = 11.6, [STRENGTH] = 2, [STAMINA] = 3 }, 2000)
    local dull = Pala({ id = 762, name = "Dull Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7, speed = 2.1, level = 13 },
        { [DPS] = 9.2, [STAMINA] = 1 }, 400)
    local tower = Pala({ id = 763, name = "Tower Shield", equipLoc = "INVTYPE_SHIELD", subClassID = 6, block = 8, level = 17 },
        { [ARMOR] = 395, [STAMINA] = 4 }, 900)
    local buckler = Pala({ id = 764, name = "Buckler", equipLoc = "INVTYPE_SHIELD", subClassID = 6, block = 5, level = 12 },
        { [ARMOR] = 239, [STAMINA] = 1 }, 300)
    Pala({ id = 765, name = "Chain Coif", equipLoc = "INVTYPE_HEAD", subClassID = 3 }, { [ARMOR] = 138, [STAMINA] = 4, [STRENGTH] = 3 }, 400)
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local me, S = ns.Roster.Me(), ns.Scanner
    eq(ns.Weights.source, "wowsims/forever", "the weights are the ones the addon comes with")
    eq(ns.Score.Current().name, "PALADIN_PROTECTION", "a paladin with its talents in Protection is scored on Protection")
    -- What the profile makes of each: the sum the addon itself is to come to (Score.Value).
    local weights = ns.Weights.profiles.PALADIN_PROTECTION
    local function Worth(def)
        local sum = (def.block or 0) * weights.weights[BLOCK]
        for name, amount in pairs(def.game) do sum = sum + amount * (name == DPS and weights.mh or weights.weights[name]) end
        return sum
    end
    check(Worth(guard) < 0.8 * Worth(maul), "on those weights the better sword is far below the maul, by its damage per second")
    check(Worth(dull) < Worth(guard), "and the other sword below that one")
    check(Worth(guard) + Worth(tower) < Worth(great), "the better sword and the better shield together are below the two-hander for sale")
    check(Worth(buckler) > 0 and Worth(buckler) < Worth(tower), "and both shields are worth something")
    eq(me.byProfile, nil, "it has chosen nothing about its hands")
    local tab = Tab()
    local Row, Rows, Settle, menu = tab.Row, tab.Rows, tab.Settle, tab.menu
    local function Arrow(slot)
        local arrow = ContainerFrameCombinedBags.Items[slot].UpgradeScoutArrow
        return arrow ~= nil and arrow:IsShown()
    end
    local hammer = W.PutInBags(W.Link(760))
    W.OpenBags()

    -- With the two-hander held: one hand and a shield, by the profile. Both swords are offered
    -- for the main hand and both shields for the off hand, each hand as it will be without
    -- the maul, and no two-hander: not in the list, not by an arrow in the bags.
    SetView(false, false)
    local searches = W.AH.calls.search
    ScanToEnd()
    W.Run(0.5)
    eq(menu:Lines():find("( ) Any | ( ) Two-hand | (x) One-hand, shield and off-hand | / | ", 1, true), 1, "the menu marks one hand, which the profile chose")
    eq(tab.Names(), "One-hand", "and it is named beside the Filters field")
    local ONE = "Buckler, Chain Coif, Dull Sword, Guard Sword, Tower Shield"
    eq(Rows(), ONE, "the list: both swords, both shields, a helm; no two-hander")
    eq(Row("Tower Shield").Upgrade:GetText(), "New", "a shield for the off hand as it will be"); eq(Row("Tower Shield").entry.note, "NEEDS_ONE_HAND", "which takes a weapon for one hand")
    near(Row("Tower Shield").entry.delta, Worth(tower), "at its own worth, its block read from its tooltip")
    -- The swords: "New", as what goes into a hand that holds nothing to measure it by. No
    -- gain over the maul is claimed, in percent or in points; the maul is what comes off.
    local sword = Row("Guard Sword")
    eq(sword.Upgrade:GetText(), "New", "the better sword claims no gain over the maul"); eq(sword.Hand:GetText(), "One-Hand", "the row says how it is held")
    eq(sword.entry.group, "MAINHAND", "it is for the main hand"); eq(sword.entry.note, "REPLACES_TWO_HAND", "in the place of the maul, which the choice leaves out")
    near(sword.entry.delta, Worth(guard), "at its own worth on the profile"); near(sword.entry.base, 0, "against no weapon"); eq(sword.entry.percent, nil, "with no percent")
    eq(#sword.entry.replaced, 1, "one item comes off for it"); eq(sword.entry.replaced[1], S.ctx.equipped[16].link, "the maul")
    eq(Row("Dull Sword").Upgrade:GetText(), "New", "the other sword the same"); near(Row("Dull Sword").entry.delta, Worth(dull), "at its worth")
    eq(sword.entry.pick, "UPGRADE", "the best upgrade for the main hand is the stronger sword"); eq(Row("Dull Sword").entry.pick, "VALUE", "and the best value the cheap one")
    eq(W.AH.calls.search, searches + 5, "five item searches: none for the two-hander")
    eq(Offer("Great Hammer"), nil, "whose price was not looked up")
    eq(Arrow(hammer), false, "and the one in the bags has no arrow, for all it has over the maul")
    local rows, summary = ns.Results.Build(S.offers, S.ctx, { money = GetMoney(), wants = ns.Wants.Of(me), unchecked = S.Unchecked() })
    eq(summary.unwanted, 1, "it is counted as left out by the character's filters")
    local main = {}
    for _, row in ipairs(rows) do
        if row.kind == "item" and row.entry.group == "MAINHAND" then main[#main + 1] = row.entry.offer.name end
    end
    eq(table.concat(main, ", "), "Guard Sword, Dull Sword", "the main hand's rows stand in the order of their own worth")

    -- "Any" is the player's to choose, with the maul still held: the two-hander is then
    -- offered, as it always was, and the swords and the shields are gone. The swords are
    -- measured against the maul again, and lose; nothing is held beside it.
    menu:Click("Any")
    eq(Chosen(me).hands, "ANY", "any way, chosen")
    eq(Rows(), "Chain Coif, Great Hammer", "any way: the two-hander is listed at once, and neither sword nor shield")
    Settle()
    check(Offer("Great Hammer") ~= nil, "its price is looked up"); eq(Row("Great Hammer").entry.note, nil, "it takes the maul's place, and nothing more to note")
    near(Row("Great Hammer").entry.delta, Worth(great) - Worth(maul), "at what it has over the maul")
    eq(tab.Names(), "", "no filter is on")
    W.Run(1.5)
    eq(Arrow(hammer), true, "and the one in the bags has its arrow")
    -- And one hand again, chosen this time: the swords and the shields are back at once, as
    -- they were, with no scan and no price looked up anew.
    searches = W.AH.calls.search
    menu:Click("One-hand, shield and off-hand")
    eq(Chosen(me).hands, "ONE", "one hand, chosen")
    eq(Rows(), ONE, "one hand again: the list it had"); eq(Row("Guard Sword").Upgrade:GetText(), "New", "the sword as it was")
    Settle()
    eq(W.AH.calls.search, searches, "and no item search is sent: their prices are known")
    -- The best set for all its gold: the stronger sword in the maul's place and the better
    -- shield beside it, each as its row has it.
    local set = {}
    for _, row in ipairs(ns.Plan.Rows(ns.Plan.Choose(ns.Plan.Ladder(S.offers, S.ctx, GetMoney(), ns.Wants.Of(me)), GetMoney()))) do
        if row.kind == "item" then set[#set + 1] = row.entry.offer.name end
    end
    eq(table.concat(set, ", "), "Chain Coif, Guard Sword, Tower Shield", "the best set: the helm, the sword and the shield")

    -- The sword and the tower shield go on. The list follows the gear at once: the weaker
    -- sword and the weaker shield have no place any more. A two-hander that beats the two
    -- together is still not offered.
    W.equipped = { [16] = W.Link(761), [17] = W.Link(763) }
    W.Fire("PLAYER_EQUIPMENT_CHANGED")
    W.Run(1.5)
    eq(Rows(), "Chain Coif", "with the sword and the shield held: the helm alone, before any scan")
    W.RunUntil(function() return W.AH.ready end, 5)
    ScanToEnd()
    W.Run(1.5)
    eq(Rows(), "Chain Coif", "and after one: the helm, and no two-hander")
    eq(Arrow(hammer), false, "nor an arrow in the bags")

    -- "Any" again: the two-hander is offered against the two together.
    menu:Click("Any")
    check(Row("Great Hammer") ~= nil, "any way: the two-hander is listed at once")
    Settle()
    eq(Row("Great Hammer").entry.note, "BOTH_HANDS", "and it is said to take both hands")
    W.Run(1.5)
    eq(Arrow(hammer), true, "and the one in the bags has its arrow")
    -- On another profile of the paladin's nothing is chosen for it: any way was chosen for
    -- Protection, and is Protection's. With that choice taken back as well, Retribution offers
    -- the two-hander and Protection does not.
    eq(me.byProfile["own:PALADIN_PROTECTION"].hands, "ANY", "any way, chosen for Protection")
    me.byProfile = nil
    tab.frame.ProfileDropdown:Pick(3)
    Settle()
    eq(me.profile, "PALADIN_RETRIBUTION", "Retribution chosen"); eq(me.byProfile, nil, "for which nothing is chosen")
    eq(menu:Lines():find("(x) Any | ( ) Two-hand | ( ) One-hand, shield and off-hand | / | ", 1, true), 1, "the menu marks any way")
    check(Row("Great Hammer") ~= nil, "and the two-hander is listed, which beats the sword and the shield there as well")
    tab.frame.ProfileDropdown:Pick(2)
    Settle()
    eq(me.profile, "PALADIN_PROTECTION", "Protection chosen"); eq(ns.Wants.Hands(me), "ONE", "where the profile says one hand")
    eq(Row("Great Hammer"), nil, "the two-hander is not listed")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- Pawn scores, or Forever Companion: no profile of the addon's has a say on the hands then,
-- a choice of the player's holds as ever, and what a Pawn scale says of weapons stands beside
-- it. The stricter of the two is what the list shows.
function scenarios.weapons_others()
    MoreProfiles()
    TwoHandWorld()
    W.player.talents = { { name = "Arms", points = 7 }, { name = "Fury", points = 0 }, { name = "Protection", points = 1 } }
    PawnWorld()
    W.AddPawnScale({ name = "WARRIOR_PROTECTION", shown = true, values = { TEST_S2 = 1 } })
    CompanionWorld()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score, Wants, S, me = ns.Score, ns.Wants, ns.Scanner, ns.Roster.Me()
    local tools = ScanTools()
    local Scan, More, Shown = tools.Scan, tools.More, tools.Shown

    -- The addon's own weights, on Protection: one hand, by the profile.
    me.profile = "WARRIOR_PROTECTION"
    eq(Wants.Hands(me), "ONE", "the addon's own Protection says one hand")
    Wants.SetHands(me, "TWO")
    eq(Wants.ProfileKey(me), "own:WARRIOR_PROTECTION", "two hands chosen there: kept for the addon's own profile")
    -- Pawn chosen: the profile has no say, on whatever scale. Pawn's scales say for
    -- themselves what they show of weapons. Nor has the choice made on the addon's own
    -- profile: a scale of Pawn's is another profile, whatever its name.
    Score.SetEngine("pawn")
    eq(Score.Engine(), "pawn", "Pawn scores"); eq(Score.Current().name, ARMS, "on its scale for the talents")
    eq(Wants.Hands(me), "ANY", "and nothing is chosen for the character"); eq(Wants.Of(me), nil, "nothing asked")
    Score.Choose(me, PROT)
    eq(Score.Current().name, PROT, "on Pawn's own scale for Protection"); eq(Wants.Hands(me), "ANY", "the same")
    -- Not even on a scale the player named as the addon names its own profile.
    Score.Choose(me, "WARRIOR_PROTECTION")
    eq(Score.Current().name, "WARRIOR_PROTECTION", "on a scale of the player's by that very name"); eq(Wants.Hands(me), "ANY", "the same still")
    eq(Wants.ProfileKey(me), "pawn:WARRIOR_PROTECTION", "a choice there is kept as that scale's, and what the addon's own profile of that name has is not its")
    Score.Choose(me, ARMS)

    -- A scale that shows every weapon, and the player's choice.
    W.OpenAuctionHouse()
    SetView(false, false)
    Scan()
    eq(S.ctx.profile, ARMS, "a scan on the scale for Arms"); eq(S.ctx.show2H, true, "which shows two-handers"); eq(S.ctx.show1H, true, "and the rest")
    eq(Shown(), "Helm, Long Axe, Sharp Sword, Short Bow", "no choice: the list of one that holds a two-hander")
    Wants.SetHands(me, "ONE")
    local list, unwanted, entries = Shown()
    eq(list, "Blunt Mace, Helm, Lantern, Oak Shield, Sharp Sword, Short Bow", "one hand, chosen: it holds with Pawn scoring")
    eq(entries["Oak Shield"].note, "NEEDS_ONE_HAND", "the shield for the off hand as it will be"); eq(unwanted, 1, "the axe left out")
    eq(entries["Blunt Mace"].note, "REPLACES_TWO_HAND", "the mace, weaker than the maul, for the main hand as it will be")
    near(entries["Blunt Mace"].delta, 20, "at what the scale makes of it"); near(entries["Sharp Sword"].delta, 36, "as the sword is")
    eq(More(), 3, "the prices of the shield, the lantern and the mace are looked up")

    -- A scale that shows no two-handers, with each choice beside it.
    Wants.SetHands(me, "ANY")
    Score.Choose(me, PROT)
    Scan()
    eq(S.ctx.profile, PROT, "a scan on the scale for Protection"); eq(S.ctx.show2H, false, "which shows no two-handers")
    list, unwanted = Shown()
    eq(list, "Helm, Sharp Sword, Short Bow", "any way: no two-hander, by the scale"); eq(unwanted, 0, "which is the scale's to leave out, and not counted as the character's")
    Wants.SetHands(me, "TWO")
    list, unwanted = Shown()
    eq(list, "Helm, Short Bow", "a two-hander chosen, on a scale that shows none: nothing for the hands"); eq(unwanted, 1, "the sword left out by the choice")
    Wants.SetHands(me, "ONE")
    list, unwanted, entries = Shown()
    eq(list, "Blunt Mace, Helm, Lantern, Oak Shield, Sharp Sword, Short Bow", "one hand: the shield, the lantern and the mace, as the scale has nothing against them")
    eq(unwanted, 0, "and nothing left out by the choice: the axe was out already")
    eq(entries["Oak Shield"].note, "NEEDS_ONE_HAND", "with the note")
    eq(More(), 3, "their prices are looked up")
    eq(#W.pawn.fails, 0, "Pawn is asked about no scale it has not")

    -- Forever Companion scores: the same. Its scale of a tank chooses nothing for the
    -- character, it has no say on weapons, and a choice of the player's holds. What was
    -- chosen on a scale of Pawn's is that scale's, and no choice here.
    eq(Wants.ProfileKey(me), "pawn:" .. PROT, "one hand was chosen on Pawn's scale for Protection")
    Score.SetEngine("companion")
    eq(Score.Engine(), "companion", "Forever Companion scores")
    local tank
    for _, scale in ipairs(Score.Profiles()) do
        if scale.title == "Mitigation Tank" then tank = scale.name end
    end
    check(tank ~= nil, "it has a scale of a tank")
    Score.Choose(me, tank)
    eq(Score.Current().name, tank, "which is the one in use"); eq(Wants.Hands(me), "ANY", "and nothing is chosen for the character")
    eq(Wants.ProfileKey(me), "companion:" .. tank, "on a scale of Forever Companion's")
    Scan()
    eq(S.ctx.profile, tank, "a scan on that scale"); eq(S.ctx.show2H, true, "which shows every weapon")
    eq(Shown(), "Helm, Long Axe, Sharp Sword, Short Bow", "no choice: two-handers and all")
    Wants.SetHands(me, "ONE")
    list, unwanted = Shown()
    eq(list, "Blunt Mace, Helm, Lantern, Oak Shield, Sharp Sword, Short Bow", "one hand, chosen: the list for one hand"); eq(unwanted, 1, "the axe left out")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- Forever Leveling BiS scores: no profile of the addon's has a say on the hands, a choice of
-- the player's holds, and no row says more than that addon says an item gains. It measures
-- an item for the off hand against the two-hander it would take the place of: so the off
-- hand of one who goes over to one hand has a shield only where that addon says the shield
-- gains, and at that gain.
function scenarios.weapons_leveling()
    MoreProfiles()
    TwoHandWorld()
    Sell({ id = 608, name = "Great Wall", equipLoc = "INVTYPE_SHIELD", subClassID = 6, value = 40, level = 9 }, 5000)
    LevelingWorld()
    LoadAddon()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Run(1.5)
    local Score, Wants, S, me = ns.Score, ns.Wants, ns.Scanner, ns.Roster.Me()
    local tools = ScanTools()
    local Scan, More, Shown = tools.Scan, tools.More, tools.Shown

    me.profile = "WARRIOR_PROTECTION"
    eq(Wants.Hands(me), "ONE", "the addon's own Protection says one hand")
    Score.SetEngine("leveling")
    eq(Score.Engine(), "leveling", "Forever Leveling BiS scores"); eq(Score.Current().name, MAIN_ARMS, "on its main spec")
    eq(Wants.Hands(me), "ANY", "and nothing is chosen for the character")

    W.OpenAuctionHouse()
    SetView(false, false)
    Scan()
    eq(type(S.ctx.hands), "function", "the comparison has that addon's say on the hands")
    eq(Shown(), "Helm, Long Axe, Sharp Sword, Short Bow", "no choice: the list of one that holds a two-hander")
    -- One hand chosen. The oak shield (12) and the lantern (5) gain nothing by that addon's
    -- count, which is against the maul (30): no row. The great wall (40) gains 10 by it.
    Wants.SetHands(me, "ONE")
    eq(Wants.ProfileKey(me), "leveling:arms", "kept for that addon's spec, by the name the spec has whoever of the account shops for the character")
    local list, unwanted, entries = Shown()
    eq(list, "Great Wall, Helm, Sharp Sword, Short Bow", "one hand: the shield that addon says gains, and no other")
    local wall = entries["Great Wall"]
    eq(wall.group, "OFFHAND", "for the off hand"); eq(wall.note, "NEEDS_ONE_HAND", "with the note")
    near(wall.delta, 10, "at the gain that addon says, 40 against the maul's 30, and not at its whole score")
    eq(unwanted, 1, "the axe left out by the choice")
    near(entries["Sharp Sword"].delta, 6, "the sword as that addon has it too: 36 against 30")
    eq(More(), 1, "the wall's price is looked up"); eq(Offer("Great Wall").buyout, 5000, "and known")
    eq(Unsure("Oak Shield"), nil, "the oak shield is not kept at all: no choice has a place for it there")
    -- That addon's answer is asked about the character being played alone: the list for
    -- another one goes by the scores, as it always did.
    local other = Score.Context("WARRIOR:arms", { class = "WARRIOR", level = 10, gear = { [16] = W.Link(590) } })
    eq(other.hands, nil, "the comparison for another character has no say of that addon's")
    eq(other.equipped[16].invType, "INVTYPE_2HWEAPON", "it holds the same maul")
    local place = ns.Compare.Place({ link = W.Link(603), itemID = 603, invType = "INVTYPE_SHIELD", value = 12 }, other, "ONE")[1]
    check(place ~= nil and place.note == "NEEDS_ONE_HAND", "and its off hand is offered the oak shield by the choice")
    near(place.delta, 12, "at the shield's own worth")
    CheckLevelingAsked("the hands")
    eq(#W.errors, 0, "nothing of it is an error")
end

-- The tabs addons add to the auction window stand in one row of LibAHTab's, which is drawn
-- smaller when it would end past the window's right edge.
function scenarios.tab_row()
    LoadAddon()
    W.OpenAuctionHouse()
    local window, lib = AuctionHouseFrame, LibStub("LibAHTab-1-0")
    local game = window.Tabs
    local ours = { lib:GetButton("UpgradeScout"), lib:GetButton("UpgradeScoutSupplies") }
    local row = ours[1]:GetParent()
    eq(row:GetParent(), window, "the library's tabs are in a frame of its own in the window")
    eq(row:GetLeft(), nil, "where the window stands is not known yet")
    eq(row:GetScale(), 1, "and the row is left as it is")
    -- How many times the row is given a scale, from here on.
    local scaled, SetScale = 0, row.SetScale
    row.SetScale = function(...)
        scaled = scaled + 1
        return SetScale(...)
    end
    -- An edge of a frame as the eye has it against the window: in the window's units.
    local function Left(part) return part:GetLeft() * part:GetEffectiveScale() / window:GetEffectiveScale() end
    local function Right(part) return part:GetRight() * part:GetEffectiveScale() / window:GetEffectiveScale() end
    -- A tab as it was made: its words, its width, its own scale and what it hangs on.
    local function Made(tab)
        local at = tab._points[1]
        return table.concat({ tab:GetText(), tab:GetWidth(), tab:GetScale(), #tab._points, at.point, at.toPoint, at.x, at.y }, " "), at.to
    end
    -- The row hangs by its top left corner on the top right corner of the game's last tab.
    local function Hung()
        local at = row._points[1]
        return #row._points == 1 and at.point == "TOPLEFT" and at.to == game[3] and at.toPoint == "TOPRIGHT" and at.x == 0 and at.y == 0
    end
    -- The player closes the window and opens it again: the row is fitted as the window shows,
    -- and once more when the next frame is drawn.
    local function Reopen()
        W.CloseAuctionHouse()
        W.OpenAuctionHouse()
        W.Tick()
    end

    -- The window is 800 wide and drawn at 0.8 of the screen's size, from 300 of its own units
    -- to 1100. The game's tabs start 20 in, 3 apart: Buy and Sell 70 wide, Auctions 88.
    window._left, window._scale = 300, 0.8
    near(window:GetRight(), 1100, "the window's right edge"); near(Right(game[3]), 554, "the end of the game's last tab")
    local gameMade = { Made(game[1]), Made(game[2]), Made(game[3]) }
    Reopen()
    near(Left(row), 554, "the row starts where the game's tabs end")
    near(Right(ours[1]), 645, "Upgrades, 88 wide, 3 from there"); near(Right(ours[2]), 754, "and Consumables, 106 wide")
    eq(row:GetScale(), 1, "our two tabs fit: the row is drawn at its full size"); eq(scaled, 0, "and never given another")

    -- Another addon makes its four tabs after ours, through the same library. The last one
    -- would end at 1142, 42 past the window's edge.
    local theirs, words = {}, { "Shopping", "Selling", "Cancelling", "Auctionator" }
    for i, text in ipairs(words) do
        lib:CreateTab("AuctionatorTabs_" .. i, CreateFrame("Frame", nil, window), text)
        theirs[i] = lib:GetButton("AuctionatorTabs_" .. i)
    end
    -- At its full size the row is 588 long, and there are 534 from its start to 12 short of
    -- the edge.
    near(row:GetScale(), 534 / 588, "the row is drawn just small enough to fit")
    near(Right(theirs[4]), 1100 - 12, "its last tab ends 12 short of the window's right edge")
    near(Left(row), 554, "it starts where it did"); check(Hung(), "and hangs level with the game's tabs as before")
    for i, tab in ipairs(theirs) do
        local made, on = Made(tab)
        eq(made, words[i] .. " " .. (#words[i] * 6 + 40) .. " 1 1 TOPLEFT TOPRIGHT 3 0", "the other addon's tab " .. i .. " is as it was made")
        eq(on, theirs[i - 1] or ours[2], "and hangs on the tab before it")
    end
    for i, tab in ipairs(game) do eq(Made(tab), gameMade[i], "the game's tab " .. i .. " is as it was") end
    near(Left(game[1]), 320, "the game's tabs are where they were"); near(Right(game[3]), 554, "to their end")
    eq(ours[1]:GetWidth(), 88, "our own tabs are as wide as before"); eq(ours[2]:GetWidth(), 106, "both")

    -- Fitted again, nothing changes: the row is measured at its full size, whatever size it
    -- is drawn at.
    local fitted, times = row:GetScale(), scaled
    W.Tick()
    Reopen()
    eq(row:GetScale(), fitted, "fitted a second and a third time, the row has the same scale"); eq(scaled, times, "and is not given it again")
    SetScale(row, 0.8)
    Reopen()
    near(row:GetScale(), 534 / 588, "from another scale it comes to the same one")
    near(Right(theirs[4]), 1100 - 12, "and the same end")

    -- A tab out of view takes no room: without the last one the row ends at 1033 and fits.
    theirs[4]:Hide()
    Reopen()
    eq(row:GetScale(), 1, "a row that fits again is drawn at its full size again")
    theirs[4]:Show()
    Reopen()
    near(row:GetScale(), 534 / 588, "and smaller when it does not")

    -- Two more tabs, 130 and 106 wide: the row is 830 long, and 534 of room is 0.64 of that.
    lib:CreateTab("Orders", CreateFrame("Frame", nil, window), "Crafting Orders")
    lib:CreateTab("Collections", CreateFrame("Frame", nil, window), "Collections")
    W.Tick()
    eq(row:GetScale(), 0.75, "a row too long for that is drawn no smaller than three quarters")
    near(Right(lib:GetButton("Collections")), 554 + 830 * 0.75, "and ends past the window's edge, where it can still be read")
    near(Left(row), 554, "from the same start"); check(Hung(), "on the same corner")

    -- A row that is not there to be measured is left alone, and nothing fails: a window whose
    -- place the game has not worked out, our tab in no frame, a library that has made no tab.
    SetScale(row, 1)
    times = scaled
    window._left = nil
    Reopen()
    window._left = 300
    local frame = ours[1]._parent
    ours[1]._parent = nil
    Reopen()
    ours[1]._parent = frame
    lib.internalState = nil
    Reopen()
    eq(row:GetScale(), 1, "the row is as it was left"); eq(scaled, times, "and was given no scale")
    eq(#W.errors, 0, "nothing of it is an error")
end

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
