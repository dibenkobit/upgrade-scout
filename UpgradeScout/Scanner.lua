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
S.offers = {}                  -- offer id -> offer
S.ctx = nil                    -- comparison context of the last scan (see PawnBridge.Context)
S.info = { rows = 0, scored = 0, toScore = 0, verified = 0, toVerify = 0 }
S.message = nil                -- note for the status line
S.partial = false              -- the last scan did not see everything
S.halted = false               -- the price checks were stopped and wait for S.Resume()
S.finishedAt = nil
S.stats = nil                  -- what the last scan sent and how long it took (see NewStats)

local ahOpen = false
local run                      -- state of the work in progress
local scan                     -- what the last scan learned; kept until the next scan
local pending                  -- request waiting for the throttle
local lastRequest              -- request sent last, repeated if the server drops it
local sendingBrowse = false
local purchases = {}           -- auction id -> offer, for purchases the player confirmed
local confirming = false       -- the player is looking at the "Buy this?" box
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

---------------------------------------------------------------------------
-- State and the request throttle
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()

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
        if item and ns.Pawn.ClassCanUse(item) then
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
local function IsRed(text, color)
    if not text or text == "" or not color then return false end
    local r, g, b = color:GetRGB()
    return r > 0.9 and g < 0.2 and b < 0.2
end

--   true = nothing red, false = something red, nil = the client has not loaded the item yet
local function Usable(link)
    local data = C_TooltipInfo.GetHyperlink(link)
    local lines = data and data.lines
    local name = lines and lines[1] and lines[1].leftText
    if not name or name == "" or name == RETRIEVING_ITEM_INFO then return nil end
    for i = 2, #lines do
        local line = lines[i]
        if IsRed(line.leftText, line.leftColor) or IsRed(line.rightText, line.rightColor) then
            return false
        end
    end
    return true
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
local function SkipReason(cand)
    if not cand.eval or scan.bucketsVary then return nil end
    local placements = Placements(cand)
    if #placements == 0 then return "worse" end
    if scan.floorBroken then return nil end
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
    if ns.db.topOnly and not scan.bucketsVary and not scan.floorBroken then return nil end
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

local function OnItemResults(itemKey)
    if S.state ~= "verify" or not run then return end
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

local function StepScore(now)
    local started = Clock()
    local list = run.toScore
    while run.scoreIndex <= #list do
        local row = list[run.scoreIndex]
        run.scoreIndex = run.scoreIndex + 1
        if ScoreRow(row) then
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
            for i = 1, #run.waiting do
                AddCandidate(run.waiting[i])
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
        itemClassFilters = { { classID = WEAPON_CLASS }, { classID = ARMOR_CLASS } },
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
    if required > S.ctx.level then
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
    if required > S.ctx.level then return end

    local ks = ns.KeyString(key)
    if run.rows[ks] then return end

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
    if partial then S.partial = true end
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
    run = {
        mode = mode,
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
        stats = scanning and S.stats or nil,
        deadline = 0,
        lastLoad = 0,
        nextRetry = 0,
    }
    ResetOrder()
end

function S.IsOpen()
    return ahOpen
end

-- Forgets the last scan (its scores belong to another Pawn scale, for instance).
function S.Reset()
    S.Stop()
    S.offers = {}
    S.ctx = nil
    S.finishedAt = nil
    S.message = nil
    S.partial = false
    S.halted = false
    scan = nil
end

-- Starts a full scan. Returns false and sets S.message when it cannot.
function S.Start()
    if S.state ~= "idle" then return false end
    S.message = nil
    if not ahOpen then
        S.message = L.ERR_AH_CLOSED
        ns.Fire("SCAN_STATE")
        return false
    end
    local problem = ns.Pawn.Problem()
    local scale = not problem and ns.Pawn.CurrentScale() or nil
    if problem or not scale then
        S.message = problem or L.ERR_NO_SCALE
        ns.Fire("SCAN_STATE")
        return false
    end

    S.ctx = ns.Pawn.Context(scale.name)
    S.offers = {}
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
    local _, class = UnitClass("player")
    run.armorLimit = ARMOR_LIMIT[class]
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
    S.message = message
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

-- Rebuilds the gear snapshot (after the player changes equipment). The offers keep their
-- scores, so the list can be re-ranked without another scan.
function S.RefreshContext()
    if not S.ctx or ns.Pawn.Problem() then return end
    S.ctx = ns.Pawn.Context(S.ctx.scale)
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
        StepJobs(now)
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

local function OnItemLoaded()
    if run and S.state == "score" then run.lastLoad = GetTime() end
end
ns.On("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
ns.On("GET_ITEM_INFO_RECEIVED", OnItemLoaded)

ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    local offer = purchases[auctionID]
    if not offer then return end
    purchases[auctionID] = nil
    ns.Print(L.MSG_BOUGHT:format(offer.link, ns.Money(offer.buyout)))
    S.offers[offer.id] = nil
    front.dirty = true
    ns.Fire("OFFERS_CHANGED")
    -- More of the same item may be for sale at a higher price: look it up again.
    if (offer.count > 1 or offer.more) and S.state == "idle" and ahOpen and S.ctx then
        SearchOne("refresh", offer)
    end
end)

local contextTimer = false
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    if not S.ctx or contextTimer then return end
    contextTimer = true
    C_Timer.After(0.5, function()
        contextTimer = false
        S.RefreshContext()
    end)
end)

-- Another search (the Buy tab, another addon) replaces the browse list we are reading.
local function OnForeignBrowse()
    if S.state == "browse" and not sendingBrowse then
        S.Stop(L.ST_INTERRUPTED)
    end
end
hooksecurefunc(AH, "SendBrowseQuery", OnForeignBrowse)
hooksecurefunc(AH, "SearchForFavorites", OnForeignBrowse)
hooksecurefunc(AH, "SearchForItemKeys", OnForeignBrowse)
