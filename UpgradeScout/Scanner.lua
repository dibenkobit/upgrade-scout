local _, ns = ...
local L = ns.L
local AH = C_AuctionHouse

-- The scan, in three steps:
--   browse  one search for all weapons and armor; gives a row per item with its lowest price
--   score   Pawn scores each row's item; rows that can beat the player's gear become
--           "candidates", the rest drop out
--   verify  an item search per candidate reads the real auctions, keeps those with a buyout
--           price the player can equip, and remembers the cheapest of each ("offers")
-- The auction house lets a client send only one request at a time ("throttle"), so everything
-- that talks to the server goes through Send() and waits its turn. That makes the item
-- searches the slow part, and the scan sends only those whose answer the list can show: see
-- SkipReason. The candidates stay in memory after the scan, so when the list starts to need a
-- skipped one (a filter is switched off, an offer is bought), S.Demand() looks it up then.
local S = {}
ns.Scanner = S

local BROWSE_TIMEOUT = 15      -- seconds to wait for an answer to a browse request
local MAX_ROWS = 60000         -- browse rows read before giving up on the rest
local EARLY_STOP_RUN = 100     -- rows above the player's level in a row that end a level-sorted browse
local LOAD_TIMEOUT = 4         -- seconds to wait for the client to load item data
local JOB_TIMEOUT = 8          -- seconds to wait for an answer to an item search
local JOB_RETRIES = 1
local FAIL_STREAK = 3          -- unanswered item searches in a row that end the price checks
local PACE_WEIGHT = 5          -- searches the last scan's pace counts for in the time-left estimate,
                               -- and the fewest this run must time when there is no last scan
local FLOOR_MISSES = 3         -- buyouts found below a row's lowest price before that price is distrusted,
local FLOOR_MISS_SHARE = 0.05  -- and the share of the rows checked that they must exceed
local MAX_CANDIDATES = 2000
local MAX_AUCTIONS = 250       -- auctions read per item
local EVAL_RETRIES = 8
local FRAME_BUDGET_MS = 6      -- scoring time per frame, to keep the game smooth

-- Milliseconds, for the per-frame budget.
local Clock = debugprofilestop

S.state = "idle"               -- idle | browse | score | verify
S.mode = nil                   -- what the current work is for:
                               --   scan     a full scan
                               --   more     prices the list started to need after a scan
                               --   buy      the lookup before a purchase
                               --   refresh  the lookup after one
                               --   supplies a scan for consumables (see "Consumables" below)
                               --   supply   the lookup before a consumable is bought
S.offers = {}                  -- offer id -> offer
S.ctx = nil                    -- comparison context of the last scan (see PawnBridge.Context)
S.info = { rows = 0, scored = 0, toScore = 0, verified = 0, toVerify = 0 }
S.message = nil                -- note for the status line
S.partial = false              -- the last scan did not see everything
S.halted = false               -- the price checks were stopped and wait for S.Resume()
S.finishedAt = nil
S.stats = nil                  -- what the last scan sent and how long it took (see NewStats)
S.changes = 0                  -- goes up whenever the offers or the gear snapshot change

-- For the best set for a budget (see Plan.lua), which the list shows when ns.db.plan is on.
S.budget = nil                 -- the most the set may cost, in copper; nil for all the gold there is
S.acquired = {}                -- gear bought here and not yet put on: { link, itemID, invType,
                               -- value, unique }. A set is measured against it as if it were worn.

-- The same for consumables, which have a scan and a list of their own.
S.supplies = {}                -- id -> consumable for sale that the player can use (see ScoreSupply)
S.suppliesAt = nil             -- when the last scan for them ended
S.suppliesPartial = false      -- it did not see everything
S.suppliesNote = nil           -- note for their status line
S.suppliesWho = nil            -- whom the last scan for them was for: a card from Roster, nil
                               -- for the character being played (as ctx.who is for gear)

local ahOpen = false
local run                      -- state of the work in progress
local scan                     -- what the last scan learned; kept until the next scan
local pending                  -- request waiting for the throttle
local lastRequest              -- request sent last, repeated if the server drops it
local sendingBrowse = false
local purchases = {}           -- auction id -> offer, for purchases the player confirmed
local confirming = false       -- the player is looking at the "Buy this?" box
local quote                    -- the consumable purchase the server was asked to price (see QuoteSupply)
local supplyBids = {}          -- auction id -> { supply, tiers }, for consumables bought as one auction
local stateSince = 0

local ITEM_SORTS = {
    { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Bid, reverseSort = false },
}

-- The heaviest armor each class can ever wear (the same class lists Pawn uses). Rows with
-- heavier armor are dropped before scoring; this only saves time, Pawn would score them 0.
local ARMOR_LIMIT = {
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
    ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}
local ARMOR_CLASS = Enum.ItemClass.Armor
local WEAPON_CLASS = Enum.ItemClass.Weapon
local CONSUMABLE_CLASS = Enum.ItemClass.Consumable

-- Gear of a character that is not being played which the client has and Pawn gave nothing
-- for (ctx.unread, see PawnBridge.Context): most likely Pawn read the tooltip a moment before
-- the game had filled it in. The gear snapshot is made again a few times, a second apart; an
-- item that truly has no stats stays at 0, as it should.
local CONTEXT_RETRIES = 3
local contextTries = 0
local function Recheck()
    local ctx = S.ctx
    if not ctx or not ctx.unread or contextTries >= CONTEXT_RETRIES then return end
    contextTries = contextTries + 1
    C_Timer.After(1, function()
        if S.ctx == ctx then S.RefreshContext() end
    end)
end

---------------------------------------------------------------------------
-- State and the request throttle
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()

local Reacquire

local function IsScanMode(mode)
    return mode == "scan" or mode == "more"
end

local function SetState(state)
    -- Time spent in the step that just ended, for the scan's statistics.
    local stats = S.stats
    local now = GetTime()
    if stats and stats[S.state] and IsScanMode(S.mode) then
        stats[S.state] = stats[S.state] + (now - stateSince)
    end
    stateSince = now

    S.state = state
    if state == "idle" then
        S.mode = nil
        driver:Hide()
    else
        driver:Show()
    end
    ns.Fire("SCAN_STATE")
end

local function Pump()
    if pending and ahOpen and AH.IsThrottledMessageSystemReady() then
        local request = pending
        pending = nil
        lastRequest = request
        request()
    end
end

local function Send(request)
    pending = request
    Pump()
end

---------------------------------------------------------------------------
-- Statistics of the last scan (/upscout stats)
---------------------------------------------------------------------------
local function NewStats()
    return {
        browse = 0, score = 0, verify = 0,  -- seconds spent in each step
        requests = 0,                       -- browse requests sent
        rows = 0,                           -- browse rows read
        candidates = 0,                     -- rows that scored as upgrades
        searches = 0,                       -- item searches sent
        pages = 0,                          -- further pages of item search results asked for
        timeouts = 0,                       -- item searches that got no answer
        skipped = 0,                        -- candidates whose price the list did not need
        checked = 0,                        -- rows whose auctions were read
        belowFloor = 0,                     -- of those, rows with a buyout below the row's lowest price
        early = false,                      -- the browse stopped before the last page
    }
end

local function SaveStats()
    local stats = S.stats
    if not stats then return end
    stats.rows = S.info.rows
    stats.candidates = scan and #scan.candidates or 0
    stats.skipped = 0
    if scan then
        stats.checked, stats.belowFloor = scan.checked, scan.belowFloor
        for i = 1, #scan.candidates do
            if not scan.candidates[i].status then stats.skipped = stats.skipped + 1 end
        end
    end
    stats.at = time()
    -- Kept with the character's settings, so the numbers of a real scan can be read later.
    ns.db.lastScan = stats
end

function S.StatsText()
    local stats = S.stats or ns.db.lastScan
    if type(stats) ~= "table" then return L.STATS_NONE end
    local function Sec(value) return math.floor((value or 0) + 0.5) end
    return L.STATS:format(
        Sec((stats.browse or 0) + (stats.score or 0) + (stats.verify or 0)),
        Sec(stats.browse), stats.requests or 0, stats.rows or 0,
        Sec(stats.score), stats.candidates or 0,
        Sec(stats.verify), stats.searches or 0, stats.pages or 0, stats.timeouts or 0,
        stats.skipped or 0)
end

---------------------------------------------------------------------------
-- Scoring one item
---------------------------------------------------------------------------
-- The seventh field of an item link is its random suffix ("of the Bear"); 0 when it has none.
local function LinkSuffix(link)
    local suffix = link:match("item:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:(%-?%d*)")
    return tonumber(suffix) or 0
end

local function IsUnique(itemID)
    return itemID ~= nil and C_Item.GetItemUniquenessByID(itemID) == true
end

-- Scores an item link with Pawn.
--   table  the item can be worn by this class at this level and Pawn gives it a score
--   false  it never will be an offer (wrong type, too high level, nothing Pawn values)
--   nil    the client has not loaded the item yet; ask again later
local function EvalLink(link)
    local cache = run.evalCache
    local known = cache[link]
    if known ~= nil then return known end

    local name, fullLink, quality, _, minLevel, _, _, _, equipLoc, icon = C_Item.GetItemInfo(link)
    if not name or not fullLink then return nil end

    local result = false
    local ctx = S.ctx
    if (minLevel or 0) <= ctx.level and ns.Compare.Handles(equipLoc) then
        local item = ns.Pawn.Item(fullLink)
        if item and ns.Pawn.ClassCanUse(item, ctx.who) then
            local value = ns.Pawn.Value(item, ctx.scale)
            if value > 0 then
                local itemID = C_Item.GetItemInfoInstant(fullLink)
                result = {
                    link = fullLink,
                    name = name,
                    quality = quality,
                    icon = icon,
                    reqLevel = minLevel or 0,
                    invType = equipLoc,
                    itemID = itemID,
                    unique = IsUnique(itemID),
                    value = value,
                    effects = ns.Pawn.HasUnscoredEffects(item),
                }
            end
        end
    end
    cache[link] = result
    return result
end

-- The game colours a tooltip line red when the player does not meet it: level, class, armor
-- or weapon skill not learned, and so on. That is the most direct answer to "can I equip
-- this right now". The lines are read as data (C_TooltipInfo), the same data the game builds
-- its tooltips from, so no tooltip frame is involved.
-- Red is about the character being played. When the lists are for another one (run.who, a
-- card from Roster), the same lines are judged by what the card knows of that character.
local function IsRed(text, color)
    if not text or text == "" or not color then return false end
    local r, g, b = color:GetRGB()
    return r > 0.9 and g < 0.2 and b < 0.2
end

-- Is anything in these lines red?
local function AnyRed(lines)
    for i = 2, #lines do
        local line = lines[i]
        if IsRed(line.leftText, line.leftColor) or IsRed(line.rightText, line.rightColor) then
            return true
        end
    end
    return false
end

--   true = the character can equip it, false = it cannot, nil = the client has not loaded
--   the item yet
local function Usable(link)
    local data = C_TooltipInfo.GetHyperlink(link)
    local lines = data and data.lines
    local name = lines and lines[1] and lines[1].leftText
    if not name or name == "" or name == RETRIEVING_ITEM_INFO then return nil end
    local who = run.who
    if who then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
        return ns.Roster.Wields(who, classID, subClassID) and ns.Roster.Allows(who, lines)
    end
    return not AnyRed(lines)
end

---------------------------------------------------------------------------
-- Candidates: which of them need an item search
---------------------------------------------------------------------------
local function AddCandidate(row, eval)
    local list = scan.candidates
    if #list >= MAX_CANDIDATES then
        S.partial = true
        return
    end
    local minPrice = row.minPrice or 0
    list[#list + 1] = {
        key = row.key,
        ks = row.ks,
        -- The row's lowest price. No auction in the row has a buyout below it.
        minPrice = minPrice,
        -- The scored sample auction, when every auction in the row is that same item. Without
        -- it only the item search can tell what the row holds.
        eval = eval,
        expect = eval and eval.value or nil,
        -- A buyout at this price settles the search: see CheapestLoaded.
        stopAt = eval and minPrice > 0 and minPrice or nil,
        -- status: nil = price not looked up, "done", "failed"
    }
end

-- Where the candidate's item would go and by how much it beats the gear there.
local function Placements(cand)
    if cand.placedFor ~= S.ctx then
        cand.placedFor = S.ctx
        cand.placements = ns.Compare.Place(cand.eval, S.ctx)
        local best = 0
        for i = 1, #cand.placements do
            if cand.placements[i].delta > best then best = cand.placements[i].delta end
        end
        cand.best = best
    end
    return cand.placements
end

-- The verified offers as the list groups them (see Results.Collect), rebuilt when they change.
local front = {}
local function Front()
    local money = GetMoney()
    local afford = ns.db.affordableOnly and true or false
    if front.dirty or front.offers ~= S.offers or front.ctx ~= S.ctx
        or front.money ~= money or front.afford ~= afford then
        front.groups = ns.Results.Collect(S.offers, S.ctx, { money = money, affordableOnly = afford })
        front.offers, front.ctx, front.money, front.afford, front.dirty = S.offers, S.ctx, money, afford, false
    end
    return front.groups
end

-- The most the best set for a budget may cost: the budget, and never more than there is.
function S.PlanCap()
    local money = GetMoney()
    return S.budget and math.min(S.budget, money) or money
end

-- The verified offers by the way they are worn, put together again when they have changed.
local byType = {}
local function OffersWornAs(invType)
    if byType.changes ~= S.changes or byType.offers ~= S.offers then
        byType = { changes = S.changes, offers = S.offers, lists = {} }
        for _, offer in pairs(S.offers) do
            local list = byType.lists[offer.invType]
            if not list then
                list = {}
                byType.lists[offer.invType] = list
            end
            list[#list + 1] = offer
        end
    end
    return byType.lists[invType]
end

-- Can no set need the candidate? True when as many verified offers as can be worn at once
-- (two rings, one chest) are worn the same way, are at least as strong and cost no more than
-- the lowest price in the candidate's row: whatever set the candidate could be in, one of
-- those would stand in its place for no more money. It must stay in step with Plan.lua's
-- own rule for the offers a set can need.
local function Outdone(cand)
    local list = OffersWornAs(cand.eval.invType)
    if not list then return false end
    local _, room = ns.Compare.Kind(cand.eval.invType)
    room = room or 1
    local better = 0
    for i = 1, #list do
        local offer = list[i]
        if offer.value >= cand.eval.value and offer.buyout <= cand.minPrice then
            better = better + 1
            if better >= room then return true end
        end
    end
    return false
end

-- Why the candidate's price is not worth an item search right now; nil when it is. Every
-- reason is a proof that the list, as the player has it set up, would not show the item
-- whatever the search found, so skipping it never changes what the list shows:
--   worse      it no longer beats the player's gear
--   price      "only what I can afford" is on and even the row's lowest price is too high
--   dominated  "top N per slot" is on and, in every slot it fits, an offer already verified
--              is stronger and no dearer per point than this could possibly be
-- The last two rest on the row's lowest price being a floor under its buyouts. ReadJob checks
-- that against every row it reads; if the server turns out to mean something else by that
-- number (scan.floorBroken), nothing is skipped for its price any more.
-- With the best set for a budget on, the list shows that set, and the two filters have no say.
-- A set can need an offer that "top N" would hide: the strongest chest may leave no money for
-- anything else. So the reasons are then:
--   price      even the row's lowest price is more than the budget
--   outdone    no set can need it (see Outdone)
local function SkipReason(cand)
    if not cand.eval or scan.bucketsVary then return nil end
    local placements = Placements(cand)
    if #placements == 0 then return "worse" end
    if scan.floorBroken then return nil end
    if ns.db.plan then
        if cand.minPrice > S.PlanCap() then return "price" end
        if Outdone(cand) then return "outdone" end
        return nil
    end
    if ns.db.affordableOnly and cand.minPrice > GetMoney() then return "price" end
    if ns.db.topOnly then
        local groups = Front()
        for i = 1, #placements do
            local p = placements[i]
            local entries = groups[p.group]
            if not entries or not ns.Results.Dominated(entries, p.delta, cand.minPrice) then
                return nil
            end
        end
        return "dominated"
    end
    return nil
end

-- The next candidate to look up, and how many are waiting in all.
local function PickCandidate()
    local first, left = nil, 0
    local list = scan.candidates
    for i = 1, #list do
        local cand = list[i]
        if not cand.status and not SkipReason(cand) then
            left = left + 1
            first = first or cand
        end
    end
    return first, left
end

-- Biggest upgrades first: each verified offer then rules out the weaker candidates that
-- cannot beat its price per point. When everything is going to be listed anyway, the rows
-- the player can pay for go first so that the useful part of the list fills in early.
local function SortCandidates()
    local list = scan.candidates
    local money = GetMoney()
    local reachFirst = not ns.db.topOnly
    for i = 1, #list do
        local cand = list[i]
        if cand.eval then Placements(cand) else cand.best = 0 end
        cand.inReach = cand.minPrice <= money
    end
    table.sort(list, function(a, b)
        if reachFirst and a.inReach ~= b.inReach then return a.inReach end
        if a.best ~= b.best then return a.best > b.best end
        return a.ks < b.ks
    end)
end

-- Candidates whose price has not been looked up, as the list counts them:
--   groups[slot group] = how many would go into that slot
--   tooDear            = how many cost more than the player has ("only what I can afford")
function S.Unchecked()
    local out = { groups = {}, tooDear = 0 }
    if not scan or scan.bucketsVary or not S.ctx then return out end
    local money = GetMoney()
    local afford = ns.db.affordableOnly and not scan.floorBroken
    local list = scan.candidates
    for i = 1, #list do
        local cand = list[i]
        if not cand.status and cand.eval then
            local placements = Placements(cand)
            if #placements > 0 then
                if afford and cand.minPrice > money then
                    out.tooDear = out.tooDear + 1
                else
                    for p = 1, #placements do
                        local group = placements[p].group
                        out.groups[group] = (out.groups[group] or 0) + 1
                    end
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Step 3: item searches ("jobs")
---------------------------------------------------------------------------
local NextJob

local function FinishRun(ok)
    local done = run.onDone
    local mode = run.mode
    run = nil
    pending = nil
    if mode == "scan" then S.finishedAt = time() end
    if mode == "supplies" then S.suppliesAt = time() end
    SetState("idle")
    if IsScanMode(mode) then SaveStats() end
    if done then done(ok) end
    ns.Fire("OFFERS_CHANGED")
end

local function SendJob(job)
    job.state = "query"
    job.deadline = GetTime() + JOB_TIMEOUT
    Send(function()
        job.deadline = GetTime() + JOB_TIMEOUT
        if run.stats then run.stats.searches = run.stats.searches + 1 end
        -- 0, 0 is "no level filter", as the auction window itself sends by default.
        AH.SendSearchQuery(job.key, ITEM_SORTS, false, 0, 0)
    end)
end

function NextJob()
    run.job = nil
    local job
    if run.single then
        job, run.single = run.single, nil
    elseif IsScanMode(run.mode) then
        local left
        job, left = PickCandidate()
        if not job and scan.bucketsVary and not scan.requeued then
            -- Scoring assumed every auction in a row is the same item. An item search just
            -- showed that is not true here, so the rows dropped by score are searched too
            -- (and SkipReason now lets every candidate through).
            scan.requeued = true
            for i = 1, #scan.rejected do
                AddCandidate(scan.rejected[i])
            end
            job, left = PickCandidate()
        end
        S.info.toVerify = S.info.verified + left
    end
    if not job then
        FinishRun(not run.failed)
        return
    end
    run.job = job
    job.tries = 0
    job.evalTries = 0
    job.partial = false
    SendJob(job)
end

-- A job with `stopAt` covers auctions that are all the same item, none of them with a buyout
-- below that price. Once one at exactly that price has arrived (not the player's own), the
-- cheapest buyout is known and further pages cannot change it.
local function CheapestLoaded(job, count)
    if not job.stopAt then return false end
    if job.minPrice and scan.floorBroken then return false end
    for i = 1, count do
        local info = AH.GetItemSearchResultInfo(job.key, i)
        if info and info.buyoutAmount == job.stopAt
            and not info.containsOwnerItem and not info.containsAccountItem then
            return true
        end
    end
    return false
end

-- Called when the client has (some of) the auctions for the current job.
local function ContinueJob(job)
    local key = job.key
    local count = AH.GetNumItemSearchResults(key) or 0
    if not AH.HasFullItemSearchResults(key) and count < MAX_AUCTIONS then
        if CheapestLoaded(job, count) then
            job.partial = true          -- price settled; how many more there are is not known
        else
            job.state = "more"
            job.deadline = GetTime() + JOB_TIMEOUT
            Send(function()
                job.deadline = GetTime() + JOB_TIMEOUT
                if run.stats then run.stats.pages = run.stats.pages + 1 end
                if AH.RequestMoreItemSearchResults(key) then
                    job.state = "read"  -- nothing more to fetch after all
                end
            end)
            return
        end
    end
    job.state = "read"
end

local function ReadJob(job)
    local key = job.key
    local count = math.min(AH.GetNumItemSearchResults(key) or 0, MAX_AUCTIONS)
    local found = {}
    local notReady = false
    local lowest                -- the cheapest buyout in the row, whoever sells it

    for i = 1, count do
        local info = AH.GetItemSearchResultInfo(key, i)
        local buyout = info and info.buyoutAmount or 0
        if buyout > 0 and (not lowest or buyout < lowest) then lowest = buyout end
        -- Buyout only: an auction without a buyout price is skipped, and so are the
        -- player's own auctions.
        if info and info.itemLink and (info.buyoutAmount or 0) > 0
            and not info.containsOwnerItem and not info.containsAccountItem then
            local eval = EvalLink(info.itemLink)
            if eval == nil then
                notReady = true
            elseif eval == false then
                if job.expect and scan then scan.bucketsVary = true end
            else
                if eval.usable == nil then eval.usable = Usable(eval.link) end
                if eval.usable == nil then
                    notReady = true
                elseif eval.usable then
                    if job.expect and scan and math.abs(eval.value - job.expect) > job.expect * 0.005 then
                        scan.bucketsVary = true
                    end
                    local id = eval.itemID .. ":" .. LinkSuffix(eval.link) .. ":" .. string.format("%.2f", eval.value)
                    local offer = found[id]
                    if #ns.Compare.Place(eval, S.ctx) == 0 then
                        -- For sale and wearable, but no better than what the player has.
                    elseif not offer then
                        found[id] = {
                            id = id,
                            ks = job.ks,
                            key = key,
                            link = eval.link,
                            name = eval.name,
                            quality = eval.quality,
                            icon = eval.icon,
                            reqLevel = eval.reqLevel,
                            invType = eval.invType,
                            itemID = eval.itemID,
                            unique = eval.unique,
                            value = eval.value,
                            effects = eval.effects,
                            buyout = info.buyoutAmount,
                            auctionID = info.auctionID,
                            count = 1,
                            -- Not every auction of the item was read: there may be more of it.
                            more = job.partial or nil,
                            -- Every auction in this row is this item (see CheapestLoaded).
                            uniform = job.stopAt ~= nil or nil,
                        }
                    else
                        offer.count = offer.count + 1
                        if info.buyoutAmount < offer.buyout then
                            offer.buyout = info.buyoutAmount
                            offer.auctionID = info.auctionID
                        end
                    end
                end
            end
        end
    end

    if notReady and job.evalTries < EVAL_RETRIES then
        job.evalTries = job.evalTries + 1
        job.state = "wait"
        job.retryAt = GetTime() + 0.3
        return
    end

    -- Replace whatever this item had in the list with what is for sale now.
    for id, offer in pairs(S.offers) do
        if offer.ks == job.ks then S.offers[id] = nil end
    end
    for id, offer in pairs(found) do
        S.offers[id] = offer
    end
    front.dirty = true
    S.changes = S.changes + 1

    -- Is the row's lowest price really a floor under its buyouts? Now and then a cheaper
    -- auction is posted between the browse and this search; more than that means the server
    -- reports something else, and the scan stops relying on it.
    if scan and IsScanMode(run.mode) and (job.minPrice or 0) > 0 then
        scan.checked = scan.checked + 1
        if lowest and lowest < job.minPrice then
            scan.belowFloor = scan.belowFloor + 1
            if scan.belowFloor >= FLOOR_MISSES and scan.belowFloor > scan.checked * FLOOR_MISS_SHARE then
                scan.floorBroken = true
            end
        end
    end

    job.status = "done"
    run.failStreak = 0
    S.info.verified = S.info.verified + 1
    ns.Fire("OFFERS_CHANGED")
    NextJob()
end

-- Seconds one item search took in the scan before this one, to have an estimate of the time
-- left before this run has timed any of its own. nil when there is nothing to go by.
local function LastPace()
    local last = ns.db.lastScan
    if type(last) ~= "table" then return nil end
    local searches, seconds = tonumber(last.searches) or 0, tonumber(last.verify) or 0
    if searches < PACE_WEIGHT or seconds <= 0 then return nil end
    return seconds / searches
end

local function StartVerify()
    if IsScanMode(run.mode) then SortCandidates() end
    S.info.verified = 0
    S.info.toVerify = run.single and 1 or 0
    run.paceStart = GetTime()
    run.pacePrior = LastPace()
    SetState("verify")
    NextJob()
end

-- Seconds the price checks still need, or nil when that cannot be told:
--   * with "top N per slot" on, most of the candidates still waiting are ruled out by the
--     offers found on the way, so their number says nothing about the time left;
--   * nothing has been timed yet, in this run or in an earlier scan.
-- The estimate is the searches left times the seconds one search takes. That pace starts as
-- the last scan's and gives way to this run's own as its searches come back.
function S.TimeLeft()
    if S.state ~= "verify" or not run or not scan or not IsScanMode(run.mode) then return nil end
    if (ns.db.topOnly or ns.db.plan) and not scan.bucketsVary and not scan.floorBroken then return nil end
    local left = S.info.toVerify - S.info.verified
    if left <= 0 then return nil end
    local done = S.info.verified
    local elapsed = GetTime() - run.paceStart
    local pace
    if run.pacePrior then
        pace = (run.pacePrior * PACE_WEIGHT + elapsed) / (PACE_WEIGHT + done)
    elseif done >= PACE_WEIGHT then
        pace = elapsed / done
    else
        return nil
    end
    return left * pace
end

local function StepJobs(now)
    local job = run.job
    if not job then return end
    if job.state == "read" or (job.state == "wait" and now >= job.retryAt) then
        ReadJob(job)
    elseif (job.state == "query" or job.state == "more") and now > job.deadline then
        if job.state == "more" then
            job.state = "read"          -- read what did arrive
        elseif job.tries < JOB_RETRIES then
            job.tries = job.tries + 1
            SendJob(job)
        else
            run.failed = true
            job.status = "failed"
            if run.stats then run.stats.timeouts = run.stats.timeouts + 1 end
            S.info.verified = S.info.verified + 1
            if IsScanMode(run.mode) then
                S.partial = true
                -- Three in a row without an answer: the auction house is not talking to us,
                -- and waiting out every remaining search would take minutes.
                run.failStreak = (run.failStreak or 0) + 1
                if run.failStreak >= FAIL_STREAK then
                    S.Stop(L.ERR_BROWSE)
                    return
                end
            end
            NextJob()
        end
    end
end

local ReadLookupAuctions

local function OnItemResults(itemKey)
    if S.state ~= "verify" or not run then return end
    if run.lookup then
        ReadLookupAuctions(itemKey)
        return
    end
    local job = run.job
    if job and (job.state == "query" or job.state == "more") and ns.SameKey(itemKey, job.key) then
        ContinueJob(job)
    end
end

---------------------------------------------------------------------------
-- Step 2: scoring the browse rows
---------------------------------------------------------------------------
-- true when the row is settled, false when it has to wait for the client to load something.
local function ScoreRow(row)
    local key = row.key
    local itemID = key.itemID
    if not C_Item.IsItemDataCachedByID(itemID) then
        if not run.requested[itemID] then
            run.requested[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return false
    end

    -- The link of one real auction in this row. Without it the score would be a guess for
    -- items with random suffixes, so then the item search decides instead.
    local suffix = key.itemSuffix or 0
    local link = AH.GetItemKeySampleLink(key)
    if not link then
        if suffix > 0 then
            link = "item:" .. itemID .. "::::::" .. suffix
        else
            if not row.asked then
                row.asked = true
                AH.GetItemKeyInfo(key)      -- asks the server; the answer is a sample link
            end
            return false
        end
    end

    local eval = EvalLink(link)
    if eval == nil then return false end

    if suffix == 0 and LinkSuffix(link) ~= 0 then
        -- One row covers several suffix variants; only the item search can tell them apart.
        AddCandidate(row)
        return true
    end

    local upgrade = false
    if eval then
        local placements = ns.Compare.Place(eval, S.ctx)
        upgrade = #placements > 0
    end
    if upgrade then
        -- Red text is about the item, not the auction, so the sample answers for the row.
        if eval.usable == nil then eval.usable = Usable(eval.link) end
        if eval.usable == nil then return false end
        if eval.usable then
            AddCandidate(row, eval)
            return true
        end
    end
    scan.rejected[#scan.rejected + 1] = row
    return true
end

---------------------------------------------------------------------------
-- Consumables
---------------------------------------------------------------------------
-- A scan for consumables is the first two steps of the scan for gear, with other questions:
--   browse  one search for the whole Consumables category
--   score   each row's item is kept if the player can use it right now (nothing red in its
--           tooltip) and its tooltip says what it does: the line that starts with "Use:"
-- There is no third step. Consumables are sold by the piece out of one pile per item, without
-- bids, so the lowest price in a browse row is the price of one piece.
-- Which of them do the same thing, what each is worth to this character and which is the
-- best is Supplies.lua's business: it is settled when the list is drawn, so another Pawn
-- scale needs no new scan.
local ItemSpell = C_Item.GetItemSpell or GetItemSpell

-- What the game says about a consumable:
--   usable  true = the character can use it (nothing red; for a character that is not being
--           played, nothing its card falls short of), false = it cannot, nil = the client
--           has not loaded it yet
--   effect  the first line that starts with "Use:", without those words; nil if there is none
local function ReadSupply(link)
    local data = C_TooltipInfo.GetHyperlink(link)
    local lines = data and data.lines
    local name = lines and lines[1] and lines[1].leftText
    if not name or name == "" or name == RETRIEVING_ITEM_INFO then return nil end
    local effect = nil
    local prefix = ITEM_SPELL_TRIGGER_ONUSE
    for i = 2, #lines do
        local text = lines[i].leftText
        if not effect and text and type(prefix) == "string" and text:sub(1, #prefix) == prefix then
            effect = text:sub(#prefix + 1):match("^%s*(.-)%s*$")
        end
    end
    local who = run.who
    local usable
    if who then usable = ns.Roster.Allows(who, lines) else usable = not AnyRed(lines) end
    return usable, effect
end

-- true when the row is settled, false when it has to wait for the client to load something.
-- `final`: the wait is over, settle the row with what is known.
local function ScoreSupply(row, final)
    local itemID = row.key.itemID
    if not C_Item.IsItemDataCachedByID(itemID) then
        if not run.requested[itemID] then
            run.requested[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return final or false
    end
    local name, link, quality, _, _, _, _, stack, _, icon, _, _, subClassID = C_Item.GetItemInfo(itemID)
    if not name or not link then return final or false end

    local usable, effect = ReadSupply(link)
    if usable == nil then return final or false end
    if not usable then return true end
    if not effect or effect == "" then
        -- Nothing to use: a reagent or a leftover filed under Consumables. If the item does
        -- cast something, the line about it is still on its way.
        if not (ItemSpell and ItemSpell(itemID)) then return true end
        if not final then return false end
        effect = nil
    end

    local kind, power = "item:" .. itemID, 0
    if effect then kind, power = ns.Supplies.Describe(effect) end
    S.supplies[row.ks] = {
        id = row.ks,
        key = row.key,
        itemID = itemID,
        link = link,
        name = name,
        quality = quality,
        icon = icon,
        sub = subClassID or -1,
        reqLevel = row.required,
        stack = math.max(stack or 1, 1),
        effect = effect,
        kind = kind,            -- the same for every consumable that does the same thing
        power = power,
        -- What the game's tables say it gives, where they say it (see SupplyData.lua):
        stats = ns.SupplyData.stats[itemID],        -- { Strength = 25, ... } for Pawn to score
        restores = ns.SupplyData.restores[itemID],  -- "H" health, "M" mana, "HM" both...
        price = row.minPrice,   -- of one piece
        quantity = row.quantity,
    }
    return true
end

local function StepScore(now)
    local started = Clock()
    local list = run.toScore
    local supplies = run.mode == "supplies"
    local Score = supplies and ScoreSupply or ScoreRow
    while run.scoreIndex <= #list do
        local row = list[run.scoreIndex]
        run.scoreIndex = run.scoreIndex + 1
        if Score(row) then
            S.info.scored = S.info.scored + 1
            run.lastLoad = now
        else
            run.waiting[#run.waiting + 1] = row
        end
        if Clock() - started > FRAME_BUDGET_MS then
            ns.Fire("SCAN_PROGRESS")
            return
        end
    end

    if #run.waiting > 0 then
        if now - run.lastLoad > LOAD_TIMEOUT then
            -- The client is not going to tell us more: let the item search decide these.
            -- (A consumable has no item search to go to: it is taken as far as it is known.)
            for i = 1, #run.waiting do
                if supplies then
                    ScoreSupply(run.waiting[i], true)
                else
                    AddCandidate(run.waiting[i])
                end
            end
            S.info.scored = S.info.scored + #run.waiting
            run.waiting = {}
        elseif now >= run.nextRetry then
            run.nextRetry = now + 0.25
            run.toScore, run.waiting, run.scoreIndex = run.waiting, {}, 1
            return
        else
            return
        end
    end

    ns.Fire("SCAN_PROGRESS")
    if supplies then
        FinishRun(true)
        return
    end
    scan.ready = true
    StartVerify()
end

---------------------------------------------------------------------------
-- Step 1: the browse search
---------------------------------------------------------------------------
local function BrowseQuery(variant)
    local order = Enum.AuctionHouseSortOrder
    local sorts
    if variant == 1 then
        -- Sorted by level, the rows the player can use come first and the scan can stop
        -- early. Whether the server really sorts that way is checked as the rows arrive.
        sorts = { { sortOrder = order.Level, reverseSort = false }, { sortOrder = order.Price, reverseSort = false } }
    else
        sorts = { { sortOrder = order.Price, reverseSort = false } }
    end
    local filter = Enum.AuctionHouseFilter
    return {
        searchString = "",
        sorts = sorts,
        -- Every quality, as the Buy tab has them ticked by default.
        filters = {
            filter.PoorQuality, filter.CommonQuality, filter.UncommonQuality, filter.RareQuality,
            filter.EpicQuality, filter.LegendaryQuality, filter.ArtifactQuality,
        },
        itemClassFilters = run.mode == "supplies" and { { classID = CONSUMABLE_CLASS } }
            or { { classID = WEAPON_CLASS }, { classID = ARMOR_CLASS } },
    }
end

local function ResetOrder()
    run.order = { last = -1, count = 0, inversions = 0, above = 0 }
end

-- Notes the required level of each row in arrival order.
local function TrackOrder(required)
    local order = run.order
    order.count = order.count + 1
    if required < order.last then order.inversions = order.inversions + 1 end
    order.last = required
    if required > run.level then
        order.above = order.above + 1
    else
        order.above = 0
    end
end

-- The browse can stop before the end only if the rows really are arriving in level order
-- and a long unbroken run of them is already above the player's level.
local function CanStopEarly()
    local order = run.order
    return run.variant == 1
        and order.above >= EARLY_STOP_RUN
        and order.count >= EARLY_STOP_RUN * 2
        and order.inversions <= order.count * 0.02
end

local function AddRow(result)
    local key = result.itemKey
    if not key or not key.itemID then return end
    run.rowCount = run.rowCount + 1

    local required = AH.GetItemKeyRequiredLevel(key) or 0
    TrackOrder(required)
    if required > run.level then return end

    local ks = ns.KeyString(key)
    if run.rows[ks] then return end

    if run.mode == "supplies" then
        -- A row without a price has nothing to buy in it.
        if (result.minPrice or 0) > 0 then
            local row = { key = key, ks = ks, minPrice = result.minPrice, required = required,
                quantity = result.totalQuantity or 0 }
            run.rows[ks] = row
            run.toScore[#run.toScore + 1] = row
        end
        return
    end

    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(key.itemID)
    if not ns.Compare.Handles(equipLoc) then return end
    if classID == ARMOR_CLASS and run.armorLimit and subClassID
        and subClassID >= 1 and subClassID <= 4 and subClassID > run.armorLimit then
        return
    end

    local row = { key = key, ks = ks, minPrice = result.minPrice }
    run.rows[ks] = row
    run.toScore[#run.toScore + 1] = row
end

local function FinishBrowse(partial)
    if partial then
        if run.mode == "supplies" then S.suppliesPartial = true else S.partial = true end
    end
    -- Gear of a character that is not being played may have still been on its way from the
    -- server when the scan began (see PawnBridge.Context): by now it has had time to come.
    if run.mode ~= "supplies" and S.ctx and S.ctx.pending then
        S.ctx = ns.Pawn.Context(S.ctx.scale, S.ctx.who)
        Recheck()
        S.changes = S.changes + 1
    end
    S.info.toScore = #run.toScore
    S.info.scored = 0
    run.scoreIndex = 1
    run.lastLoad = GetTime()
    run.nextRetry = 0
    SetState("score")
end

local function ReadBrowse()
    local results = AH.GetBrowseResults() or {}
    local count = #results
    for i = run.seen + 1, count do
        AddRow(results[i])
    end
    run.seen = count
    run.answered = true
    S.info.rows = run.rowCount
    ns.Fire("SCAN_PROGRESS")

    if CanStopEarly() or AH.HasFullBrowseResults() then
        run.stats.early = not AH.HasFullBrowseResults()
        FinishBrowse(false)
    elseif count >= MAX_ROWS then
        FinishBrowse(true)
    else
        run.deadline = GetTime() + BROWSE_TIMEOUT
        Send(function()
            run.deadline = GetTime() + BROWSE_TIMEOUT
            run.stats.requests = run.stats.requests + 1
            AH.RequestMoreBrowseResults()
        end)
    end
end

local function SendBrowse()
    run.sent = false
    run.answered = false
    run.deadline = GetTime() + BROWSE_TIMEOUT
    Send(function()
        run.deadline = GetTime() + BROWSE_TIMEOUT
        run.seen = 0
        run.sent = true
        run.stats.requests = run.stats.requests + 1
        sendingBrowse = true
        AH.SendBrowseQuery(BrowseQuery(run.variant))
        sendingBrowse = false
    end)
end

local function StepBrowse(now)
    if now <= run.deadline then return end
    if run.answered then
        FinishBrowse(true)              -- keep the rows that did arrive
    elseif run.variant == 1 then
        run.variant = 2                 -- no answer: try the plain price-sorted search
        SendBrowse()
    else
        S.Stop(L.ERR_BROWSE)
    end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
local function NewRun(mode)
    S.mode = mode
    lastRequest = nil
    local scanning = IsScanMode(mode)
    local supplies = mode == "supplies" or mode == "supply"
    -- The character the work is for, when it is not the one being played (a card from Roster).
    local who
    if supplies then who = S.suppliesWho else who = S.ctx and S.ctx.who end
    run = {
        mode = mode,
        who = who,
        -- Rows that ask for a higher level are of no use to the character.
        level = not supplies and S.ctx and S.ctx.level or who and who.level or UnitLevel("player"),
        variant = 1,
        rows = {},          -- key string -> row
        rowCount = 0,
        seen = 0,
        toScore = {},
        scoreIndex = 1,
        waiting = {},       -- rows waiting for the client to load item data
        requested = {},
        -- A lookup around a purchase scores its item afresh; a scan keeps its scores.
        evalCache = scanning and scan.evalCache or {},
        -- A scan for consumables counts its requests too, but nobody reads the numbers.
        stats = scanning and S.stats or (mode == "supplies" and NewStats() or nil),
        deadline = 0,
        lastLoad = 0,
        nextRetry = 0,
    }
    ResetOrder()
end

function S.IsOpen()
    return ahOpen
end

-- Forgets the last scan for gear (its scores belong to another Pawn scale, for instance).
-- Consumables are left alone, and so is a scan for them that is running: what they are worth
-- is worked out when their list is drawn.
function S.Reset()
    local mode = run and run.mode
    if mode ~= "supplies" and mode ~= "supply" then S.Stop() end
    S.offers = {}
    S.changes = S.changes + 1
    S.ctx = nil
    S.finishedAt = nil
    S.message = nil
    S.partial = false
    S.halted = false
    scan = nil
end

-- The lists are to be for another character (Roster.Target): what was found for the last one
-- goes, gear and consumables alike, and whatever is running for it stops.
function S.Retarget()
    S.Stop()
    S.Reset()
    S.acquired = {}
    S.budget = nil
    S.supplies = {}
    S.suppliesAt = nil
    S.suppliesPartial = false
    S.suppliesNote = nil
    S.suppliesWho = nil
    ns.Fire("OFFERS_CHANGED")
end

-- Brings what was bought (S.acquired) in line with a gear snapshot that was just made: what
-- has been put on since is gear now, and the rest is scored on the snapshot's scale, which
-- may be another one than it was bought under.
function Reacquire()
    local ctx = S.ctx
    for i = #S.acquired, 1, -1 do
        local item = S.acquired[i]
        local worn = false
        -- Only the character being played puts anything on while the addon looks.
        if not ctx.who then
            for _, gear in pairs(ctx.equipped) do
                if gear.itemID == item.itemID then worn = true break end
            end
        end
        local scored = not worn and ns.Pawn.Item(item.link) or nil
        if scored then
            item.value = ns.Pawn.Value(scored, ctx.scale)
        else
            table.remove(S.acquired, i)
        end
    end
end

-- Starts a full scan for the character the lists are for. Returns false and sets S.message
-- when it cannot.
function S.Start()
    if S.state ~= "idle" then return false end
    S.message = nil
    if not ahOpen then
        S.message = L.ERR_AH_CLOSED
        ns.Fire("SCAN_STATE")
        return false
    end
    local who = ns.Roster.Target()
    local problem = ns.Pawn.Problem()
    local scale = not problem and ns.Pawn.CurrentScale(who) or nil
    if problem or not scale then
        S.message = problem or L.ERR_NO_SCALE
        ns.Fire("SCAN_STATE")
        return false
    end

    S.ctx = ns.Pawn.Context(scale.name, who)
    contextTries = 0
    Recheck()
    Reacquire()
    S.offers = {}
    S.changes = S.changes + 1
    S.partial = false
    S.halted = false
    S.finishedAt = nil
    S.info = { rows = 0, scored = 0, toScore = 0, verified = 0, toVerify = 0 }
    S.stats = NewStats()
    confirming = false
    scan = {
        candidates = {},    -- rows whose item scored as an upgrade (see AddCandidate)
        rejected = {},      -- rows dropped by score alone
        evalCache = {},     -- item link -> score (see EvalLink)
        ready = false,      -- scoring finished: the candidates are all known
        bucketsVary = false,-- some row held items that differ from its sample
        requeued = false,
        checked = 0,        -- rows whose auctions were read
        belowFloor = 0,     -- of those, rows with a buyout below the row's lowest price
        floorBroken = false,-- so many of them that the row's lowest price cannot be relied on
    }
    NewRun("scan")
    run.armorLimit = ARMOR_LIMIT[S.ctx.class]
    SetState("browse")
    SendBrowse()
    return true
end

function S.Stop(message)
    if S.state == "idle" then return end
    local mode = run and run.mode
    local state = S.state
    run = nil
    pending = nil
    if IsScanMode(mode) then
        if state == "verify" then
            -- Every candidate is known; only prices are missing, and those can be resumed.
            S.halted = true
        else
            S.partial = true
            scan = nil
        end
        if mode == "scan" then S.finishedAt = time() end
    end
    if mode == "supplies" then
        -- What was read before the stop stays in the list.
        S.suppliesPartial = true
        S.suppliesAt = time()
    end
    if mode == "supplies" or mode == "supply" then
        S.suppliesNote = message
    else
        S.message = message
    end
    SetState("idle")
    if IsScanMode(mode) then SaveStats() end
    ns.Fire("OFFERS_CHANGED")
end

-- The player changed what the list shows, which is a request to see it: price checks that
-- were stopped may go on.
function S.Resume()
    if not S.halted then return end
    S.halted = false
    S.message = nil
end

-- Looks up the prices the list needs now and does not have. Called whenever the list is
-- redrawn; does nothing unless a scan left candidates that the current settings would show.
function S.Demand()
    if S.state ~= "idle" or S.halted or confirming then return false end
    if not ahOpen or not S.ctx or not scan or not scan.ready then return false end
    if ns.Pawn.Problem() then return false end
    if not PickCandidate() then return false end
    S.stats = S.stats or NewStats()
    NewRun("more")
    StartVerify()
    return true
end

-- Runs one item search outside a full scan. onDone(ok) is called when it finishes.
local function SearchOne(mode, offer, onDone, stopAt)
    NewRun(mode)
    run.onDone = onDone
    run.single = { key = offer.key, ks = offer.ks, stopAt = stopAt }
    StartVerify()
end

-- Before buying, look the item up again: the scan may be minutes old. Fires CONFIRM_BUY
-- with the fresh offer when it is still there at the same price.
function S.Buy(offer)
    if S.state ~= "idle" then
        ns.Print(L.ERR_BUSY)
        return
    end
    if not ahOpen or not S.ctx then return end
    if GetMoney() < offer.buyout then
        ns.Print(L.MSG_CANT_AFFORD)
        return
    end
    confirming = false
    local id, link, price = offer.id, offer.link, offer.buyout
    -- "Is it still there at this price" is answered by the first auction at that price.
    SearchOne("buy", offer, function(ok)
        local fresh = S.offers[id]
        if not ok then
            ns.Print(L.ERR_BROWSE)
        elseif not fresh then
            ns.Print(L.MSG_GONE:format(link))
        elseif fresh.buyout ~= price then
            ns.Print(L.MSG_PRICE:format(link, ns.Money(fresh.buyout), ns.Money(price)))
        else
            confirming = true
            ns.Fire("CONFIRM_BUY", fresh)
        end
    end, offer.uniform and price or nil)
end

-- The player said yes in the confirmation box.
function S.ConfirmPurchase(offer)
    confirming = false
    if not ahOpen then return end
    purchases[offer.auctionID] = offer
    AH.PlaceBid(offer.auctionID, offer.buyout)
end

-- The confirmation box went away, with or without a purchase.
function S.CancelPurchase()
    if not confirming then return end
    confirming = false
    ns.Fire("OFFERS_CHANGED")
end

-- Rebuilds the gear snapshot (after the player changes equipment, or when gear of a
-- character that is not being played has come from the server). The offers keep their
-- scores, so the list can be re-ranked without another scan.
function S.RefreshContext()
    if not S.ctx or ns.Pawn.Problem() then return end
    S.ctx = ns.Pawn.Context(S.ctx.scale, S.ctx.who)
    Recheck()
    Reacquire()
    S.changes = S.changes + 1
    ns.Fire("OFFERS_CHANGED")
end

---------------------------------------------------------------------------
-- Consumables: the scan and the purchase
---------------------------------------------------------------------------
-- Starts a scan for consumables. Returns false and sets S.suppliesNote when it cannot.
function S.StartSupplies()
    if S.state ~= "idle" then return false end
    S.suppliesNote = nil
    if not ahOpen then
        S.suppliesNote = L.ERR_AH_CLOSED
        ns.Fire("SCAN_STATE")
        return false
    end
    S.supplies = {}
    S.suppliesPartial = false
    S.suppliesAt = nil
    S.suppliesWho = ns.Roster.Target()
    S.info = { rows = 0, scored = 0, toScore = 0, verified = 0, toVerify = 0 }
    confirming = false
    NewRun("supplies")
    SetState("browse")
    SendBrowse()
    return true
end

-- A consumable is bought by the piece, and what a purchase costs depends on how many pieces
-- it takes: the cheapest go first. So a purchase goes in steps, as on the game's Buy tab:
--   lookup   an item search reads who sells how many at what price      S.BuySupply
--   choose   the player says how many                                   CONFIRM_SUPPLY
--   quote    the server names the price of exactly that many            S.QuoteSupply
--   confirm  the player agrees to that price                            S.ConfirmSupply
-- The game takes the last two only from a click, so each is called straight from one.
-- A "price list" is { { price = of one piece, quantity = pieces at that price }, ... },
-- cheapest first.

-- What `count` pieces cost; nil when the price list does not hold that many.
function S.SupplyCost(tiers, count)
    local cost, left = 0, count
    for i = 1, #tiers do
        local take = math.min(left, tiers[i].quantity)
        cost = cost + take * tiers[i].price
        left = left - take
        if left <= 0 then return cost end
    end
    return nil
end

-- True when the auction house would take a request this very moment.
function S.Ready()
    return ahOpen and AH.IsThrottledMessageSystemReady()
end

-- The list shows what the price list holds: its lowest price and how many pieces there are.
-- A consumable with nothing left for sale leaves the list.
local function ApplyTiers(supply, tiers)
    if not tiers[1] then
        S.supplies[supply.id] = nil
        return false
    end
    local stock = 0
    for i = 1, #tiers do stock = stock + tiers[i].quantity end
    supply.price, supply.quantity = tiers[1].price, stock
    return true
end

local function SendLookup()
    local lookup = run.lookup
    lookup.deadline = GetTime() + JOB_TIMEOUT
    Send(function()
        lookup.deadline = GetTime() + JOB_TIMEOUT
        AH.SendSearchQuery(lookup.supply.key, ITEM_SORTS, false, 0, 0)
    end)
end

local function StepLookup(now)
    local lookup = run.lookup
    if now <= lookup.deadline then return end
    if lookup.tries < JOB_RETRIES then
        lookup.tries = lookup.tries + 1
        SendLookup()
    else
        S.Stop(L.ERR_BROWSE)
    end
end

local function FinishLookup(tiers)
    local supply = run.lookup.supply
    table.sort(tiers, function(a, b) return a.price < b.price end)
    run.onDone = function()
        if not ApplyTiers(supply, tiers) then
            ns.Print(L.MSG_GONE:format(supply.link))
            return
        end
        confirming = true
        ns.Fire("CONFIRM_SUPPLY", supply, tiers)
    end
    FinishRun(true)
end

-- The answer for something sold by the piece.
local function ReadLookupPieces(itemID)
    local lookup = run and run.lookup
    if not lookup or lookup.supply.itemID ~= itemID then return end
    local tiers = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local info = AH.GetCommoditySearchResultInfo(itemID, i)
        -- The player's own pieces are in the list too, and cannot be bought.
        local quantity = info and (info.quantity or 0) - (info.numOwnerItems or 0) or 0
        if quantity > 0 and (info.unitPrice or 0) > 0 then
            tiers[#tiers + 1] = { price = info.unitPrice, quantity = quantity }
        end
    end
    FinishLookup(tiers)
end

-- The answer for something sold as separate auctions, which a few consumables are. Each
-- auction is bought whole, so each is an entry of its own, with its auction and its price.
function ReadLookupAuctions(itemKey)
    if not ns.SameKey(itemKey, run.lookup.supply.key) then return end
    local tiers = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local info = AH.GetItemSearchResultInfo(itemKey, i)
        local buyout = info and info.buyoutAmount or 0
        if buyout > 0 and not info.containsOwnerItem and not info.containsAccountItem then
            local quantity = math.max(info.quantity or 1, 1)
            tiers[#tiers + 1] = { price = buyout / quantity, quantity = quantity, cost = buyout, auctionID = info.auctionID }
        end
    end
    FinishLookup(tiers)
end

-- Step one of a purchase. Fires CONFIRM_SUPPLY with the consumable and its price list.
function S.BuySupply(supply)
    if S.state ~= "idle" then
        ns.Print(L.ERR_BUSY)
        return
    end
    if not ahOpen then return end
    S.CancelSupply()
    S.suppliesNote = nil
    NewRun("supply")
    run.lookup = { supply = supply, tries = 0, deadline = 0 }
    SetState("verify")
    SendLookup()
end

-- Step three, from a click. SUPPLY_QUOTED follows with what `count` pieces cost in all.
function S.QuoteSupply(supply, tiers, count)
    quote = { supply = supply, tiers = tiers, count = count }
    AH.StartCommoditiesPurchase(supply.itemID, count)
end

-- Step four, from a click: buys at the price the server named.
function S.ConfirmSupply()
    if not quote or not quote.total or quote.sent then return end
    quote.sent = true
    AH.ConfirmCommoditiesPurchase(quote.supply.itemID, quote.count)
end

-- From a click: buys the cheapest auction of a consumable that is sold as separate auctions.
function S.BuySupplyAuction(supply, tiers)
    local auction = tiers[1]
    supplyBids[auction.auctionID] = { supply = supply, tiers = tiers }
    AH.PlaceBid(auction.auctionID, auction.cost)
end

-- The player closed the box, at whatever step.
function S.CancelSupply()
    if quote then
        -- The answer to a purchase that was confirmed is still to come.
        if quote.sent then return end
        AH.CancelCommoditiesPurchase()
        quote = nil
    end
    if not confirming then return end
    confirming = false
    ns.Fire("OFFERS_CHANGED")
end

-- A purchase came through: the pieces that were bought leave the price list.
local function SupplyBought(supply, tiers, count, cost)
    confirming = false
    ns.Print(L.MSG_BOUGHT_SUP:format(count, supply.link, ns.Money(cost)))
    local left = count
    while left > 0 and tiers[1] do
        local take = math.min(left, tiers[1].quantity)
        tiers[1].quantity = tiers[1].quantity - take
        left = left - take
        if tiers[1].quantity <= 0 then table.remove(tiers, 1) end
    end
    ApplyTiers(supply, tiers)
    ns.Fire("SUPPLY_DONE")
    ns.Fire("OFFERS_CHANGED")
end

function S.Step()
    if not run then return end
    Pump()
    local now = GetTime()
    if S.state == "browse" then
        StepBrowse(now)
    elseif S.state == "score" then
        StepScore(now)
    elseif S.state == "verify" then
        if run.lookup then StepLookup(now) else StepJobs(now) end
    end
end

driver:SetScript("OnUpdate", S.Step)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.On("AUCTION_HOUSE_SHOW", function()
    ahOpen = true
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
    ahOpen = false
    confirming = false
    quote = nil         -- the server drops a purchase that was not confirmed
    S.Stop()
end)

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", Pump)

ns.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    -- The server threw a request away. If it was ours, ask again.
    if run and not pending and lastRequest then
        pending = lastRequest
    end
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if S.state ~= "browse" or not run.sent then return end
    -- A fresh list: start reading from the top (rows already taken are skipped by key).
    run.seen = 0
    run.rowCount = 0
    ResetOrder()
    ReadBrowse()
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function()
    if S.state ~= "browse" or not run.sent then return end
    ReadBrowse()
end)

ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function()
    if S.state == "browse" and run.sent then run.deadline = 0 end
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
ns.On("ITEM_SEARCH_RESULTS_ADDED", OnItemResults)

-- The gear snapshot is made again a moment after it goes out of date, and once however many
-- times the game says so: a set of gear is put on piece by piece.
local contextTimer = false
local function QueueContext()
    if not S.ctx or contextTimer then return end
    contextTimer = true
    C_Timer.After(0.5, function()
        contextTimer = false
        S.RefreshContext()
    end)
end

local function OnItemLoaded(itemID)
    if run and S.state == "score" then run.lastLoad = GetTime() end
    -- An item the gear snapshot was waiting for (see PawnBridge.Context).
    local ctx = S.ctx
    if ctx and ctx.pending and itemID ~= nil and ctx.pending[itemID] then QueueContext() end
end
ns.On("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
ns.On("GET_ITEM_INFO_RECEIVED", OnItemLoaded)

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", ReadLookupPieces)

ns.On("COMMODITY_PRICE_UPDATED", function(_, total)
    if not quote or quote.sent or type(total) ~= "number" then return end
    quote.total = total
    ns.Fire("SUPPLY_QUOTED", total)
end)

ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
    if not quote or not quote.sent then return end
    local done = quote
    quote = nil
    SupplyBought(done.supply, done.tiers, done.count, done.total)
end)

ns.On("COMMODITY_PURCHASE_FAILED", function()
    if not quote then return end
    local supply = quote.supply
    quote = nil
    confirming = false
    ns.Print(L.MSG_BUY_FAILED:format(supply.link))
    ns.Fire("SUPPLY_DONE")
    ns.Fire("OFFERS_CHANGED")
end)

ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    local bid = supplyBids[auctionID]
    if bid then
        supplyBids[auctionID] = nil
        local auction = bid.tiers[1]
        SupplyBought(bid.supply, bid.tiers, auction.quantity, auction.cost)
        return
    end
    local offer = purchases[auctionID]
    if not offer then return end
    purchases[auctionID] = nil
    ns.Print(L.MSG_BOUGHT:format(offer.link, ns.Money(offer.buyout)))
    S.offers[offer.id] = nil
    front.dirty = true
    S.changes = S.changes + 1
    -- It is on its way by mail: until it is put on, a set is measured against it.
    S.acquired[#S.acquired + 1] = {
        link = offer.link, itemID = offer.itemID, invType = offer.invType, value = offer.value, unique = offer.unique,
    }
    -- A budget that was set is for what is still to be spent.
    if S.budget then S.budget = math.max(0, S.budget - offer.buyout) end
    ns.Fire("OFFERS_CHANGED")
    -- More of the same item may be for sale at a higher price: look it up again.
    if (offer.count > 1 or offer.more) and S.state == "idle" and ahOpen and S.ctx then
        SearchOne("refresh", offer)
    end
end)

ns.On("PLAYER_EQUIPMENT_CHANGED", QueueContext)

-- Another search (the Buy tab, another addon) replaces the browse list we are reading.
local function OnForeignBrowse()
    if S.state == "browse" and not sendingBrowse then
        S.Stop(L.ST_INTERRUPTED)
    end
end
hooksecurefunc(AH, "SendBrowseQuery", OnForeignBrowse)
hooksecurefunc(AH, "SearchForFavorites", OnForeignBrowse)
hooksecurefunc(AH, "SearchForItemKeys", OnForeignBrowse)
