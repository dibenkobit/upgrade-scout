local _, ns = ...
local L = ns.L
local AH = C_AuctionHouse

-- The scan, in three steps:
--   browse  one search for all weapons and armor; gives a row per item with its lowest price
--   score   each row's item is scored; rows that can beat the player's gear become
--           "candidates", the rest drop out
--   verify  an item search per candidate reads the real auctions, keeps those with a buyout
--           price the player can equip, and remembers the cheapest of each ("offers")
-- The auction house lets a client send only one request at a time ("throttle"), so everything
-- that talks to the server goes through Send() and waits its turn. That makes the item
-- searches the slow part, and the scan sends only those whose answer the list can show: see
-- SkipReason. The candidates stay in memory after the scan, so when the list starts to need a
-- skipped one (a filter is switched off, an offer is bought), S.Demand() looks it up then.
-- The player does not wait for the third step: the candidates are in the list as soon as the
-- second is over, each at its row's lowest price, and the third puts those prices right as
-- it goes (see ListCandidates). A purchase can begin meanwhile (S.CanBuy).
-- How long a scan takes grows with what it reads, which is every row from the first level up
-- to the character's own. A character that is to be offered nothing made for levels far
-- below its own ("Gear at most N levels below", Wants.lua) has a shorter one: the first step
-- asks the auction house for nothing below that level, and drops what comes below it all
-- the same (see BrowseQuery and AddRow).
local S = {}
ns.Scanner = S

local BROWSE_TIMEOUT = 15      -- seconds to wait for an answer to a browse request
local MAX_ROWS = 60000         -- browse rows read before giving up on the rest
local EARLY_STOP_RUN = 100     -- rows above the player's level in a row that end a level-sorted browse
local LOAD_TIMEOUT = 4         -- seconds without a row read after which the client is not waited for any more
local LOAD_QUIET = 1           -- and after which the list no longer waits for the rows still unread: they
                               -- are read on while the prices are looked up (see StepLate). A real scan:
                               -- 13 rows of 10,000 never were read, and the list stood four seconds for them
local UNREAD_FEW = 60          -- That is for a few rows: this many, or
local UNREAD_SHARE = 0.02      -- this share of the rows if that is more, and never more than
local UNREAD_MOST = 0.25       -- this share of them. A real scan: 37 rows of 9,500 were never told of,
                               -- starter clothes among them. More rows unread are a client still loading
                               -- its items (a game that had just been updated: 1,985 rows): they are
                               -- waited for as long as it goes on telling of them (StepScore)
local UNREAD_SEARCHED = 30     -- rows never read that a scan sends to their item searches, at most (GiveUp)
local STALL_SAID = 2           -- seconds without a row read after which the status line says that the scan
                               -- waits for the game, where it does
local SUPPLY_RIPE = 1.5        -- seconds a few rows of consumables are waited for (they have no item search
                               -- to go to, and are not read on later)
local LOAD_LONGEST = 60        -- seconds the rows are waited for at the very most, however the client goes on
local SETTLE_FOR = 2           -- seconds an item the game names without saying what it gives is asked again
                               -- before it is taken to give nothing (see EvalLink)
local LATE_KEPT = 12           -- rows never read that the last scan's numbers name (lastScan.unreadItems)
local SCANS_KEPT = 6           -- scans whose numbers are kept (ns.db.scans)
local JOB_TIMEOUT = 8         -- seconds to wait for an answer to an item search
local JOB_FIRST_WAIT = 3       -- and at most for the answer to its first sending: a search left without it
                               -- has been answered when sent again (a real scan: 6 of 39 searches, 8
                               -- seconds lost on each). Once answers have come it is waited for
local JOB_FIRST_TIMES = 4      -- this many times as long as the slowest of them took (in real scans a
local JOB_FIRST_LEAST = 1      -- quarter of a second), and never less than this (see FirstWait)
local JOB_RETRIES = 1
local SLOW_JOB = 2             -- seconds from which a search is written down as a slow one (lastScan.slow),
                               -- as is one that went out twice, however long it took,
local SLOW_KEPT = 12           -- and how many of those are kept
local FAIL_STREAK = 3          -- unanswered item searches in a row that end the price checks
local PACE_WEIGHT = 5          -- searches the last scan's pace counts for in the time-left estimate,
                               -- and the fewest this run must time when there is no last scan
local FLOOR_MISSES = 3         -- buyouts found below a row's lowest price before that price is distrusted,
local FLOOR_MISS_SHARE = 0.05  -- and the share of the rows checked that they must exceed
local MAX_CANDIDATES = 2000
local MAX_AUCTIONS = 250       -- auctions read per item
local EVAL_RETRIES = 8
local UNREAD_RETRIES = 2       -- and for a row that was never read: it has had its time (see GiveUp)
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
S.ctx = nil                    -- comparison context of the last scan (see Score.Context)
S.info = { rows = 0, scored = 0, toScore = 0, verified = 0, toVerify = 0 }
S.message = nil                -- note for the status line
S.partial = false              -- the last scan stopped before it had seen everything
S.unanswered = 0               -- item searches the auction house did not answer since the last scan
                               -- began: the scan went on without those prices
S.unread = 0                   -- rows of the last scan the game told nothing of, too many to look up one
                               -- by one: the list is short of whatever they hold (see StepScore)
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
S.suppliesUnread = 0           -- rows of that scan the game told nothing of, when they were many (S.unread)
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
local asking                   -- the item lookup that the box, already up, is waiting for (see S.BuyAgain)
local quote                    -- the consumable purchase the server was asked to price (see QuoteSupply)
local supplyBids = {}          -- auction id -> { supply, tiers }, for consumables bought as one auction
local stateSince = 0

local ITEM_SORTS = {
    { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Bid, reverseSort = false },
}

local ARMOR_CLASS = Enum.ItemClass.Armor
local WEAPON_CLASS = Enum.ItemClass.Weapon
local CONSUMABLE_CLASS = Enum.ItemClass.Consumable

-- Gear which the client has and still gave no stats for (ctx.unread, see Score.Context):
-- most likely it was asked a moment before the game had the whole item. The gear snapshot is made again a few times, a second apart; an item that
-- truly has no stats stays at 0, as it should.
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
        exact = 0,                          -- and rows whose cheapest buyout was that price: the one an item
                                            -- is listed at before its search (see ListCandidates)
        early = false,                      -- the browse stopped before the last page
        listed = 0,                         -- candidates put into the list before their search
        own = 0,                            -- candidates whose row holds an auction of the player's own
        -- Where the time of the price checks went, to be read after a real scan:
        resent = 0,                         -- item searches that went out a second time for want of an answer
        dropped = 0,                        -- requests the game said were thrown away, and sent again
        waits = 0,                          -- times a search's auctions were not loaded yet when read
        foreign = 0,                        -- searches somebody else sent to the auction house meanwhile
        slowest = 0,                        -- the longest an answer took to come from a search's first sending, in seconds
        slow = {},                          -- the searches that took long: { item, sec, tries, after, waits, auctions }
        -- Rows the client was slow to tell about, or never did (see StepScore and StepLate):
        late = 0,                           -- rows the list did not wait for
        lateWhy = {},                       -- what those were waiting for: { data, sample, link, tip = rows }
        lateRead = 0,                       -- of them, rows read while the prices were looked up
        unread = {},                        -- rows never read, by what was missing, as lateWhy
        unreadItems = {},                   -- the first of those: "item number:suffix what"
        waiting = 0,                        -- rows still unread when every row had had its turn once,
        waitingWhy = {},                    -- by what was missing, as lateWhy
        left = 0,                           -- rows never read that were not looked up either
        stalled = false,                    -- the scoring stood still for the client, and the status line said so
        forced = 0,                         -- rows read though the client never said it had loaded their item
        dead = 0,                           -- items the client said it could not load
        -- A scan that read no gear below a level (scan.fromLevel, see S.Start). Whether the
        -- auction house goes by the level it is asked for is told by these after one scan:
        fromLevel = 0,                      -- that level; 0 for a scan that read gear of every level
        levelAsked = false,                 -- the search named it (see BrowseQuery); false again when that
                                            -- search brought nothing and went out without (SendUnbounded)
        belowLevel = 0,                     -- rows that came back below it all the same, and were dropped:
                                            -- none from an auction house that goes by it
        noLevel = 0,                        -- rows that came back with no level to them (see AddRow)
    }
end

-- A row the client never told enough about goes to its item search unread; what it was
-- waiting for (row.why, see ScoreRow) is counted, and the first few are named.
local function NoteUnread(row)
    local stats = S.stats
    if not stats or not stats.unread then return end
    local why = row.why or "?"
    stats.unread[why] = (stats.unread[why] or 0) + 1
    if #stats.unreadItems < LATE_KEPT then
        stats.unreadItems[#stats.unreadItems + 1] = tostring(row.key.itemID) .. ":" .. tostring(row.key.itemSuffix or 0) .. " " .. why
    end
end

-- Writes a search down when it took long (see NewStats): which item, how many seconds from
-- its first sending to its end, how often it went out, how long after the last time the
-- answer came, how often its auctions were waited for, and how many it had. answered: false
-- for one that never got an answer.
local function NoteJob(job, answered)
    local stats = run and run.stats
    if not stats or not job.firstAt then return end
    local took = GetTime() - job.firstAt
    if (took < SLOW_JOB and job.sent < 2) or #stats.slow >= SLOW_KEPT then return end
    local key = job.key
    stats.slow[#stats.slow + 1] = {
        item = (job.eval and job.eval.name or "?") .. " " .. tostring(key.itemID) .. ":" .. tostring(key.itemSuffix or 0),
        sec = math.floor(took * 10 + 0.5) / 10,
        tries = job.sent,
        -- (From the last sending to the answer: a fraction of a second says that the search
        -- sent again was the one answered. -1 for a search never answered.)
        after = job.answered and math.floor(job.answered * 10 + 0.5) / 10 or -1,
        waits = job.evalTries,
        auctions = answered and (AH.GetNumItemSearchResults(key) or 0) or -1,
    }
end

local function SaveStats()
    local stats = S.stats
    if not stats then return end
    stats.rows = S.info.rows
    stats.candidates = scan and #scan.candidates or 0
    stats.skipped = 0
    if scan then
        stats.checked, stats.belowFloor, stats.exact = scan.checked, scan.belowFloor, scan.exact
        stats.listed, stats.own = scan.listed, 0
        for i = 1, #scan.candidates do
            local cand = scan.candidates[i]
            if cand.spare and not cand.listed and not cand.status then
                -- Kept for another way of filling the hands, which the character never
                -- took (see AddCandidate): no upgrade by score, and nothing the list
                -- did without.
                stats.candidates = stats.candidates - 1
            elseif not cand.status then
                stats.skipped = stats.skipped + 1
            end
            if cand.own then stats.own = stats.own + 1 end
        end
    end
    stats.at = time()
    -- Kept with the character's settings, so the numbers of a real scan can be read later:
    -- the last scan's, and the last few's (a scan stopped as soon as it began would else
    -- leave nothing of the one before it).
    ns.db.lastScan = stats
    local kept = ns.db.scans
    if type(kept) ~= "table" then
        kept = {}
        ns.db.scans = kept
    end
    if kept[#kept] ~= stats then
        kept[#kept + 1] = stats
        while #kept > SCANS_KEPT do table.remove(kept, 1) end
    end
end

function S.StatsText()
    local stats = S.stats or ns.db.lastScan
    if type(stats) ~= "table" then return L.STATS_NONE end
    local function Sec(value) return math.floor((value or 0) + 0.5) end
    local text = L.STATS:format(
        Sec((stats.browse or 0) + (stats.score or 0) + (stats.verify or 0)),
        Sec(stats.browse), stats.requests or 0, stats.rows or 0,
        Sec(stats.score), stats.candidates or 0,
        Sec(stats.verify), stats.searches or 0, stats.pages or 0, stats.timeouts or 0,
        stats.skipped or 0)
    -- A scan that read no gear below a level: what the auction house made of being asked so.
    -- (The numbers may come out of a saved file, written by a version that had none of them.)
    local from = tonumber(stats.fromLevel) or 0
    if from > 0 then
        text = text .. " " .. (stats.levelAsked and L.STATS_LEVEL or L.STATS_LEVEL_PLAIN):format(
            from, tonumber(stats.belowLevel) or 0, tonumber(stats.noLevel) or 0)
    end
    return text
end

---------------------------------------------------------------------------
-- Scoring one item
---------------------------------------------------------------------------
local function IsUnique(itemID)
    return itemID ~= nil and C_Item.GetItemUniquenessByID(itemID) == true
end

-- Scores an item link on the profile in use.
--   table  the item can be worn by this class at this level and scores above nothing
--   false  it never will be an offer (wrong type, too high level, nothing the profile values)
--   nil    the client has not loaded the item yet; ask again later
local function EvalLink(link)
    local cache = run.evalCache
    local known = cache[link]
    if known ~= nil then return known end

    local name, fullLink, quality, _, minLevel, _, _, _, equipLoc, icon, sellPrice = C_Item.GetItemInfo(link)
    if not name or not fullLink then return nil end

    local result = false
    local ctx = S.ctx
    if (minLevel or 0) <= ctx.level and ns.Compare.Handles(equipLoc) then
        local item = ns.Score.Item(fullLink)
        if not item then
            -- No reading of the item. Where the game itself has none yet, though it has the
            -- item's name (a client still loading its items has the one a moment before the
            -- other), it is asked again for a while, and taken to give nothing only then.
            -- Where the game has one, the scorer has nothing for the item and never will
            -- (an item Pawn does not know): that is an answer.
            if ns.Stats.Read(ns.Stats.Bare(fullLink)) == nil then
                local now = GetTime()
                local first = run.unsettled[fullLink]
                if not first then
                    first = now
                    run.unsettled[fullLink] = now
                end
                if now - first < SETTLE_FOR then return nil end
            end
        elseif ns.Score.ClassCanUse(item, ctx.who) then
            local value = ns.Score.Value(item, ctx.profile, ctx.level)
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
                    -- What it is worth in the off hand, where that is another number
                    -- (Score.OffValue); nil for nearly everything.
                    offValue = ns.Score.OffValue(item, ctx.profile, ctx.level),
                    -- Its kind of armor, where it has one: cloth, leather, mail or plate
                    -- (see Wants.lua).
                    armor = ns.Wants.ArmorOf(equipLoc, item.classID, item.subClassID),
                    -- And its kind of weapon, for one that is a weapon: a dagger, a staff.
                    weapon = ns.Wants.WeaponOf(item.classID, item.subClassID),
                    effects = ns.Score.HasUnscoredEffects(item),
                    -- What a vendor pays for it, in copper; 0 for an item no vendor buys.
                    -- The net cost of an offer is its buyout less this (Results.Net).
                    sell = sellPrice or 0,
                }
            end
        end
    end
    cache[link] = result
    return result
end

-- Whether the player can equip or use an item right now: nothing in its tooltip is red (see
-- ns.AnyRed). Red is about the character being played. When the lists are for another one
-- (run.who, a card from Roster), the same lines are judged by what the card knows of that
-- character.
local AnyRed = ns.AnyRed

-- Reads the tooltip of a scored item (see EvalLink) for what only the tooltip tells:
--   eval.usable  true = the character can equip it, false = it cannot. Left nil while the
--                client has not loaded the item.
--   eval.untrained  set for a weapon the character cannot equip for one reason alone: it
--                has not trained that kind of weapon yet, and its class can (Roster.Untrained).
--                Such a weapon is kept for the character to say that it will train
--                (AddCandidate). For the one being played: its card says the kind is not
--                trained, and the kind is all that is red in the tooltip (ns.OnlyKindRed); a
--                level, a class or a standing in red beside it leaves the item out as ever.
--                For another character: its card has not the kind, and nothing else the
--                tooltip asks is beyond it (Roster.Allows).
--   eval.unique  set for "Unique-Equipped" too. Nothing says that the game's function for
--                uniqueness counts it, and a second copy of such an item cannot be worn
--                beside the first any more than of a plain unique one.
local function ReadTooltip(eval)
    local data = C_TooltipInfo.GetHyperlink(eval.link)
    local lines = data and data.lines
    local name = lines and lines[1] and lines[1].leftText
    if not name or name == "" or name == RETRIEVING_ITEM_INFO then return end
    for i = 2, #lines do
        if lines[i].leftText == ITEM_UNIQUE_EQUIPPABLE then eval.unique = true end
    end
    local who = run.who
    local untrained
    if who then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(eval.link)
        local wields, allowed = ns.Roster.Wields(who, classID, subClassID), ns.Roster.Allows(who, lines)
        eval.usable = wields and allowed
        untrained = allowed and not wields and eval.weapon ~= nil and ns.Roster.Untrained(who, eval.weapon)
    else
        eval.usable = not AnyRed(lines)
        local me = ns.Roster.Me()
        untrained = not eval.usable and eval.weapon ~= nil and me ~= nil
            and ns.Roster.Untrained(me, eval.weapon) and ns.OnlyKindRed(lines)
    end
    eval.untrained = untrained or nil
end

---------------------------------------------------------------------------
-- Candidates: which of them need an item search
---------------------------------------------------------------------------
-- spare: the row's item is better than the gear nowhere as things stand, and would be for a
-- character that fills its hands another way than it has said: a shield beside a two-hander,
-- or a weapon for one hand that does not beat it (Compare.Possible). It is kept, so that the
-- list has it the moment the character says so, and until then it is no row of the list and
-- no price is looked up for it. Such rows are many for one that holds a two-hander (every
-- weapon for one hand there is), so they are counted by themselves: they do not crowd the
-- others out. Nor does one too many of them make the scan one that stopped early, while the
-- list has no use for them: see ListCandidates.
-- A weapon of a kind the character has not trained yet (eval.untrained) is kept the same
-- way, whatever it would be better than: it is for a character that says it will train that
-- kind, by a tick in the Weapons menu (Wants.lua), and until then it is no row of the list,
-- no price is looked up for it, and it is not counted as left out by a filter either.
local function AddCandidate(row, eval, spare)
    local list = scan.candidates
    local known = spare and scan.spares or #list - scan.spares
    if known >= MAX_CANDIDATES then
        if spare then scan.sparesCut = true else S.partial = true end
        return
    end
    if spare then scan.spares = scan.spares + 1 end
    local minPrice = row.minPrice or 0
    list[#list + 1] = {
        key = row.key,
        ks = row.ks,
        spare = spare or nil,
        -- The row's lowest price. No auction in the row has a buyout below it.
        minPrice = minPrice,
        -- The scored sample auction, when every auction in the row is that same item. Without
        -- it only the item search can tell what the row holds.
        eval = eval,
        expect = eval and eval.value or nil,
        -- A buyout at this price settles the search: see CheapestLoaded.
        stopAt = eval and minPrice > 0 and minPrice or nil,
        -- One of the row's auctions is the player's own (counted for the statistics).
        own = row.own,
        -- status: nil = price not looked up, "done", "failed"
    }
end

-- Rows of gear the client never told enough about, when their time is over.
-- Where it has the row's item and no link of an auction in the row ("sample"), or not the
-- tooltip of what scored as an upgrade ("tip"), an item search can tell what the row holds:
-- the row is a candidate without a sample (AddCandidate), up to UNREAD_SEARCHED of a scan.
-- Where it never loaded the item itself ("data", "link") a search has nothing to score the
-- row's auctions by either, and none is sent. In real scans those were a few dozen rows of
-- junk, and the searches once sent for them, a second and more each, found nothing.
-- Returns how many rows were left out.
local function GiveUp(rows)
    local list = scan.candidates
    local stats = S.stats
    local left = 0
    for i = 1, #rows do
        local row = rows[i]
        NoteUnread(row)
        local known = #list
        if (row.why == "sample" or row.why == "tip") and scan.searchedUnread < UNREAD_SEARCHED then
            AddCandidate(row)
        end
        if #list > known then
            scan.searchedUnread = scan.searchedUnread + 1
            -- (The client has had seconds to tell of the row: its search does not wait as
            -- long again for the same: ReadJob.)
            list[#list].unread = true
        else
            left = left + 1
        end
    end
    if stats and stats.left then stats.left = stats.left + left end
    return left
end

-- Where the candidate's item would go and by how much it beats the gear there. `hands` is
-- how the character means to fill its hands (its wants have it, see Wanted), which has a say
-- in that: a candidate is whatever some choice of it has a place for (Compare.Possible), and
-- may have none by the choice that stands.
local function Placements(cand, hands)
    if cand.placedFor ~= S.ctx or cand.placedHands ~= hands then
        cand.placedFor, cand.placedHands = S.ctx, hands
        cand.placements = ns.Compare.Place(cand.eval, S.ctx, hands)
        local best = 0
        for i = 1, #cand.placements do
            if cand.placements[i].delta > best then best = cand.placements[i].delta end
        end
        cand.best = best
    end
    return cand.placements
end

-- What the character the scan is for wants of its gear (see Wants.lua); nil when it leaves
-- nothing out.
local function Wanted()
    local ctx = S.ctx
    if not ctx then return nil end
    return ns.Wants.Of(ctx.who or ns.Roster.Me())
end

-- Is the item (a scored one, or an offer) a weapon of a kind the character has not trained
-- and has not asked to be offered either? It is kept aside then, as if it were not for sale.
local function Aside(item, wants)
    return item.untrained == true and wants ~= nil and wants.kinds ~= nil and wants.kinds[item.weapon] == true
end

-- Puts aside the offers that are that, out of the list and out of every count of it, and
-- back into the list those the character has asked for since: a tick in the Weapons menu
-- brings them at once, and unticking takes them away, with no price looked up twice.
local function SetAside()
    if not scan then return end
    local wants = Wanted()
    local aside, moved = scan.aside, false
    for id, offer in pairs(S.offers) do
        if Aside(offer, wants) then
            aside[id], S.offers[id], moved = offer, nil, true
        end
    end
    for id, offer in pairs(aside) do
        if not Aside(offer, wants) then
            -- (What a search has found of its row since is the newer.)
            if S.offers[id] == nil then S.offers[id] = offer end
            aside[id], moved = nil, true
        end
    end
    return moved
end

-- The most to pay for one item for that character ("Buyout up to", see Wants.lua), in copper;
-- nil when no sum is asked for.
local function Cap()
    local ctx = S.ctx
    if not ctx then return nil end
    return ns.Wants.Price(ctx.who or ns.Roster.Me())
end

-- The most a row of the list may cost, by the two price filters: the sum typed for the
-- character ("Buyout up to") and what the buyer has ("Only what I can afford"), whichever is
-- less; nil when neither is on. Also returns whether it is the sum typed and not the purse:
-- the status line says which of them left upgrades out.
function S.Ceiling()
    local cap = Cap()
    local money = ns.db.affordableOnly and GetMoney() or nil
    if cap and (not money or cap < money) then return cap, true end
    return money, false
end

-- The offers whose price has been looked up: id -> offer. A candidate is in the list from the
-- moment it is known, at its row's lowest price (see ListCandidates), and that price proves
-- nothing: whatever is reasoned from the offers about what a search can be spared goes by
-- these alone.
local checked = {}
local function Checked()
    if checked.changes ~= S.changes or checked.from ~= S.offers then
        local list = {}
        for id, offer in pairs(S.offers) do
            if not offer.unsure then list[id] = offer end
        end
        checked = { changes = S.changes, from = S.offers, list = list }
    end
    return checked.list
end

-- The verified offers as the list groups them (see Results.Collect), rebuilt when they change.
-- `wants` is what the character wants of its gear (Wanted): whoever asks for every candidate
-- in turn has asked that once.
local front = {}
local function Front(wants)
    local money = GetMoney()
    local afford = ns.db.affordableOnly and true or false
    local cap = Cap()
    if front.dirty or front.offers ~= S.offers or front.ctx ~= S.ctx
        or front.money ~= money or front.afford ~= afford or front.wants ~= wants or front.cap ~= cap then
        front.groups = ns.Results.Collect(Checked(), S.ctx, { money = money, affordableOnly = afford, cap = cap, wants = wants })
        front.offers, front.ctx, front.money, front.afford, front.dirty = S.offers, S.ctx, money, afford, false
        front.wants, front.cap = wants, cap
    end
    return front.groups
end

-- The most the best set for a budget may cost: the budget, and never more than there is.
function S.PlanCap()
    local money = GetMoney()
    return S.budget and math.min(S.budget, money) or money
end

-- The verified offers by the way they are worn, put together again when they have changed.
-- Only those the character would have at all (Wants.Fits): a set is made of nothing else.
local byType = {}
local function OffersWornAs(invType, wants)
    if byType.changes ~= S.changes or byType.offers ~= S.offers or byType.wants ~= wants then
        byType = { changes = S.changes, offers = S.offers, wants = wants, lists = {} }
        for _, offer in pairs(Checked()) do
            -- (Nor of a weapon the character cannot hold yet: Plan.Ladder.)
            if ns.Wants.Fits(wants, offer) and not offer.untrained then
                local list = byType.lists[offer.invType]
                if not list then
                    list = {}
                    byType.lists[offer.invType] = list
                end
                list[#list + 1] = offer
            end
        end
    end
    return byType.lists[invType]
end

-- Can no set need the candidate? True when as many verified offers as can be worn at once
-- (two rings, one chest) are worn the same way, are at least as strong and cost no more than
-- the lowest price in the candidate's row: whatever set the candidate could be in, one of
-- those would stand in its place for no more money. It must stay in step with Plan.lua's
-- own rule for the offers a set can need.
local function Outdone(cand, wants)
    local list = OffersWornAs(cand.eval.invType, wants)
    if not list then return false end
    local _, room = ns.Compare.Kind(cand.eval.invType)
    room = room or 1
    local better = 0
    for i = 1, #list do
        local offer = list[i]
        -- (As strong in either hand, where a weapon has a score of its own for the off hand.)
        if offer.value >= cand.eval.value and offer.buyout <= cand.minPrice
            and (offer.offValue or offer.value) >= (cand.eval.offValue or cand.eval.value) then
            better = better + 1
            if better >= room then return true end
        end
    end
    return false
end

-- Why the candidate's price is not worth an item search right now; nil when it is. Every
-- reason is a proof that the list, as the player has it set up, would not show the item
-- whatever the search found, so skipping it never changes what the list shows:
--   worse      it no longer beats the player's gear, or has no place in the hands as the
--              character fills them (a shield beside a two-hander it means to keep)
--   unwanted   the character's own filters leave it out (Wants.lua): it is armor lighter than
--              the character is to be offered, or made for a level further below the
--              character's than it is to be offered, a kind of weapon it left out or one
--              for the hands it does not fill that way, or it adds less than was asked for
--              in every slot it fits
--   price      a price filter is on ("only what I can afford", "buyout up to") and even the
--              row's lowest price is more than it lets through (see S.Ceiling)
--   outranked  "top N per slot" is on, "hide worse deals" is not, and in every slot it fits
--              the slot has no row for it (Results.LeftOut, with the N the buyer typed). N
--              offers already verified are bigger upgrades, or as big for less than this
--              could possibly cost: it is not one of the N biggest, whatever N is. And
--              it cannot be the slot's best value: one of those offers is no dearer per
--              point than this could possibly be, or this gives too little beside the
--              strongest of them to be a best value at any price. What is verified later
--              takes none of that away: another offer is one more that may stand before
--              this, and a stronger one asks more of a best value. Meanwhile the candidate
--              is in the list at its row's lowest price (ListCandidates), which is one of
--              the prices the proof is for: it has no row there either, and the picks are
--              the same with it as without. All of that must hold both by buyout and by net
--              cost (Results.Cost), where the least the candidate can cost is its row's
--              lowest price less what a vendor pays for the item: the "Net cost" box only
--              changes how the prices are shown, so ticking it must not leave the list short
--              of one. The box has no say here for that reason.
--   dominated  "hide worse deals" is on and, in every slot it fits, an offer already
--              verified is stronger and no dearer per point than this could possibly be,
--              or as strong for less than this could possibly cost (Results.Dominated):
--              the slot leaves it out for its price, whatever is verified later. That holds
--              with "top N per slot" on as with it off, the N rows being taken from what
--              the slot does not leave out. It is the only proof there is then: the one of
--              `outranked` counts offers that may themselves be left out for their price,
--              and says of an upgrade too small to be the best value only that it has no
--              row as that, so what it rules out may yet be one of the N. At its row's
--              lowest price the candidate is left out too, takes the row of no other offer
--              and changes no pick. By buyout and by net cost alike, as above.
-- The last three rest on the row's lowest price being a floor under its buyouts. ReadJob checks
-- that against every row it reads; if the server turns out to mean something else by that
-- number (scan.floorBroken), nothing is skipped for its price any more.
-- With neither "top N per slot" nor "hide worse deals" on, every upgrade a price filter lets
-- through has a row, and nothing is skipped for either reason.
-- With the best set for a budget on, the list shows that set, and the price filters, "top N"
-- and "hide worse deals" have no say.
-- A set can need an offer that those would hide: the strongest chest may leave no money for
-- anything else. So the reasons are then, after the first two:
--   price      even the row's lowest price is more than the budget
--   outdone    no set can need it (see Outdone)
-- `wants` is what the character wants of its gear (Wanted) and `ceiling` the most a row of
-- the list may cost (S.Ceiling), both asked once for all the candidates.
local function SkipReason(cand, wants, ceiling)
    if not cand.eval or scan.bucketsVary then return nil end
    local placements = Placements(cand, wants and wants.hands)
    if #placements == 0 then return "worse" end
    -- The slots the list would show it in.
    placements = ns.Wants.Keep(wants, cand.eval, placements)
    if #placements == 0 then return "unwanted" end
    if scan.floorBroken then return nil end
    if ns.db.plan then
        if cand.minPrice > S.PlanCap() then return "price" end
        -- (No set takes a weapon the character has not trained for: Plan.Ladder.)
        if cand.eval.untrained or Outdone(cand, wants) then return "outdone" end
        return nil
    end
    if ceiling and cand.minPrice > ceiling then return "price" end
    local R = ns.Results
    local top, frontier = ns.db.topOnly and R.TopCount() or nil, ns.db.hideWorse
    if not top and not frontier then return nil end
    local groups = Front(wants)
    local least, leastNet = cand.minPrice, R.Net(cand.minPrice, cand.eval.sell)
    for i = 1, #placements do
        local p = placements[i]
        local entries = groups[p.group]
        if not entries then return nil end
        if frontier then
            if not R.Dominated(entries, p.delta, least, false) or not R.Dominated(entries, p.delta, leastNet, true) then
                return nil
            end
        elseif not R.LeftOut(entries, p.delta, least, false, top) or not R.LeftOut(entries, p.delta, leastNet, true, top) then
            return nil
        end
    end
    return frontier and "dominated" or "outranked"
end

-- The next candidate to look up, and how many are waiting in all.
local function PickCandidate()
    local first, left = nil, 0
    local list = scan.candidates
    local wants, ceiling = Wanted(), (S.Ceiling())
    for i = 1, #list do
        local cand = list[i]
        if not cand.status and not SkipReason(cand, wants, ceiling) then
            left = left + 1
            first = first or cand
        end
    end
    return first, left
end

-- Biggest upgrades first: those are the rows "top N per slot" shows, and once a slot has
-- them verified they rule out the weaker candidates that cannot be its best value either;
-- and under "hide worse deals" each verified offer rules out the weaker candidates that
-- cannot beat its price per point (see SkipReason). When everything is going to be listed
-- anyway, the rows the player can pay for go first so that the useful part of the list
-- fills in early.
local function SortCandidates()
    local list = scan.candidates
    local money = GetMoney()
    local reachFirst = not ns.db.topOnly and not ns.db.hideWorse
    local wants = Wanted()
    local hands = wants and wants.hands
    for i = 1, #list do
        local cand = list[i]
        if cand.eval then Placements(cand, hands) else cand.best = 0 end
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
--   tooDear            = how many cost more than a price filter lets through (S.Ceiling)
--   unwanted           = how many the character's own filters leave out (Wants.lua)
function S.Unchecked()
    local out = { groups = {}, tooDear = 0, unwanted = 0 }
    if not scan or scan.bucketsVary or not S.ctx then return out end
    local ceiling = not scan.floorBroken and S.Ceiling() or nil
    local wants = Wanted()
    local list = scan.candidates
    for i = 1, #list do
        local cand = list[i]
        -- (A candidate that is in the list at its row's lowest price is counted there. One
        -- kept aside for a kind of weapon not trained is counted nowhere: no filter that
        -- anybody set leaves it out.)
        if not cand.status and cand.eval and not cand.listed and not Aside(cand.eval, wants) then
            local placements = Placements(cand, wants and wants.hands)
            if #placements > 0 then
                placements = ns.Wants.Keep(wants, cand.eval, placements)
                if #placements == 0 then
                    out.unwanted = out.unwanted + 1
                elseif ceiling and cand.minPrice > ceiling then
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

-- The answer to a search comes in well under a second. Now and then none comes at all, and
-- the same search sent again is answered at once: so the first sending is not waited for
-- as long as the second, after which the search is given up (StepJobs), but a few times as
-- long as answers take (FirstWait). That is so only
-- where the second can go out at once: while the client is still busy with the first, its
-- answer may be on the way, and the longer time holds, as it does until a request has gone
-- out at all (it waits its turn: Send).
-- How long the answers to first sendings have taken since the last scan began: the least and
-- the most, in seconds; nil until one came. The first sending of a search is waited for a
-- few times as long as the slowest of them, so that the wait fits how fast the auction
-- house answers this player, whatever that is.
local answers = {}

local function FirstWait()
    if not answers.most then return JOB_FIRST_WAIT end
    return math.max(JOB_FIRST_LEAST, math.min(JOB_FIRST_WAIT, answers.most * JOB_FIRST_TIMES))
end

-- A search that went out twice and has its answer: { key, took = seconds from its first
-- sending to that answer, till }. Which of the two sendings was answered cannot be told
-- then. It can a moment later: when a second answer comes for the same item, both were
-- answered, so the first was late and not lost, and answers take as long as `took` here
-- (NoteStray). With none lost the next searches are then waited for long enough, and no
-- search goes out twice for nothing; with one lost the wait stays short.
local doubled
local DOUBLED_FOR = 5           -- seconds the second answer is looked out for

-- An answer came to the job's search, `took` seconds after its last sending.
local function NoteAnswer(job, took, now)
    if job.sent == 1 then
        answers.least = math.min(answers.least or took, took)
        answers.most = math.max(answers.most or took, took)
    else
        doubled = { key = job.key, took = now - job.firstAt, till = now + DOUBLED_FOR }
    end
end

-- An answer to an item search that no job is waiting for.
local function NoteStray(itemKey)
    if doubled and GetTime() <= doubled.till and ns.SameKey(itemKey, doubled.key) then
        answers.most = math.max(answers.most or doubled.took, doubled.took)
        doubled = nil
    end
end

local sendingSearch = false
local function SendJob(job)
    job.state = "query"
    job.deadline = GetTime() + JOB_TIMEOUT
    job.early = nil
    Send(function()
        -- Answered while this waited its turn, or over: there is nothing to ask. (A search
        -- sent for a job that has its answer would take the answer away again.)
        if not run or run.job ~= job or job.state ~= "query" then return end
        local now = GetTime()
        job.deadline = now + JOB_TIMEOUT
        -- When the first sending is given up, if another request can go out by then (Overdue).
        job.early = job.tries == 0 and now + FirstWait() or nil
        job.sentAt, job.firstAt = now, job.firstAt or now
        job.sent = job.sent + 1
        if run.stats then
            run.stats.searches = run.stats.searches + 1
            if job.sent > 1 then run.stats.resent = run.stats.resent + 1 end
        end
        -- 0, 0 is "no level filter", as the auction window itself sends by default.
        sendingSearch = true
        AH.SendSearchQuery(job.key, ITEM_SORTS, false, 0, 0)
        sendingSearch = false
    end)
end

local function NextJob()
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
        if not job and scan.late then
            -- Nothing is left to look up, and a few rows are still being read (StepLate).
            -- The scan does not stand still for them with every price it has checked:
            -- they go to their item searches now, which can tell what a row holds.
            GiveUp(scan.late.rows)
            scan.late = nil
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
    job.sentAt, job.firstAt, job.answered = nil, nil, nil
    job.sent = 0                -- times its search went out
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
    -- (How long the answer took to come, from the search's first sending, and from its last:
    -- the longest of a scan is kept, and a slow search is written down with both, NoteJob.)
    if job.firstAt and job.state == "query" then
        local now = GetTime()
        job.answered = now - job.sentAt
        NoteAnswer(job, job.answered, now)
        if run.stats then
            run.stats.slowest = math.max(run.stats.slowest, math.floor((now - job.firstAt) * 100 + 0.5) / 100)
        end
    end
    local count = AH.GetNumItemSearchResults(key) or 0
    if not AH.HasFullItemSearchResults(key) and count < MAX_AUCTIONS then
        if CheapestLoaded(job, count) then
            job.partial = true          -- price settled; how many more there are is not known
        else
            job.state = "more"
            job.deadline = GetTime() + JOB_TIMEOUT
            Send(function()
                if not run or run.job ~= job or job.state ~= "more" then return end
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

-- Counts one auction of a search towards its offers. An offer is what a row holds of one item,
-- at the price of the cheapest auction of it.
-- Its id is the row's key and the item's score. The key is the item, variant and all: two
-- variants that score the same are rows of their own, and so offers of their own. The score
-- is there for a row that holds more than one item after all (scan.bucketsVary).
--   found   offer id -> offer, false for an item that is no better than the gear
local function CountAuction(found, job, eval, info)
    local id = job.ks .. ":" .. string.format("%.2f", eval.value)
    local offer = found[id]
    if offer == nil and not ns.Compare.Possible(eval, S.ctx) then
        -- For sale and wearable, but no better than what the character has, however it
        -- fills its hands. (What is better for one way of that only is an offer: the list
        -- has it the moment the character says it goes that way, see Results.Collect.)
        offer = false
        found[id] = false
    end
    if offer == false then return end
    if offer and info.buyoutAmount >= offer.buyout then
        offer.count = offer.count + 1
        return
    end
    found[id] = {
        id = id,
        ks = job.ks,
        key = job.key,
        link = eval.link,
        name = eval.name,
        quality = eval.quality,
        icon = eval.icon,
        reqLevel = eval.reqLevel,
        invType = eval.invType,
        itemID = eval.itemID,
        unique = eval.unique,
        value = eval.value,
        offValue = eval.offValue,
        armor = eval.armor,
        weapon = eval.weapon,
        -- A weapon of a kind the character has not trained yet (see ReadTooltip): its row
        -- says so, and no set for a budget takes it.
        untrained = eval.untrained,
        effects = eval.effects,
        sell = eval.sell,
        buyout = info.buyoutAmount,
        auctionID = info.auctionID,
        count = offer and offer.count + 1 or 1,
        -- Not every auction of the item was read: there may be more of it.
        more = job.partial or nil,
        -- Every auction in this row is this item (see CheapestLoaded).
        uniform = job.stopAt ~= nil or nil,
    }
end

-- Puts the candidates into the list as soon as they are known, each at its row's lowest
-- price: the player has a list to read, and to buy from, while the prices are looked up.
-- Such a price is provisional (`unsure` on the offer). It may be a bid and not a buyout, or
-- the auction may be the player's own: the search that follows puts the row right, or takes
-- it out. Nothing is reasoned from such an offer (see Checked), and a purchase looks the
-- item up first, as it always does (S.Buy).
-- A candidate without a sample, or a row without a price, has nothing to be listed by until
-- its search.
-- One kept for another way of filling the hands (`spare`, see AddCandidate) is listed once
-- it has a place: when the character says it goes that way (WANTS_CHANGED, below), or when
-- its gear changes so (S.RefreshContext). Where more of those were found than are kept, a
-- list made for that way is short of some, and the scan says that it has not everything.
-- One kept for a kind of weapon not trained yet is listed, where it has a place, once the
-- character asks for that kind; and a list that has such a kind is short in the same way.
local function ListCandidates()
    local list = scan.candidates
    local found = {}
    local wants = Wanted()
    local hands = wants and wants.hands
    if scan.sparesCut and hands == "ONE" then S.partial = true end
    for i = 1, #list do
        local cand = list[i]
        local eval = cand.eval
        local held = eval ~= nil and Aside(eval, wants)
        if scan.sparesCut and eval and eval.untrained and not held then S.partial = true end
        if not cand.status and not cand.listed and eval and cand.minPrice > 0 and not held
            and (not cand.spare or #Placements(cand, hands) > 0) then
            cand.listed = true
            scan.listed = scan.listed + 1
            CountAuction(found, cand, cand.eval, { buyoutAmount = cand.minPrice })
        end
    end
    local any = false
    for id, offer in pairs(found) do
        if offer then
            offer.unsure = true
            S.offers[id] = offer
            any = true
        end
    end
    if any then
        front.dirty = true
        S.changes = S.changes + 1
        ns.Fire("OFFERS_CHANGED")
    end
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
        if buyout > 0 and info.itemLink and not info.containsOwnerItem and not info.containsAccountItem then
            local eval = EvalLink(info.itemLink)
            if eval == nil then
                notReady = true
            elseif eval == false then
                if job.expect and scan then scan.bucketsVary = true end
            else
                if eval.usable == nil then ReadTooltip(eval) end
                if eval.usable == nil then
                    notReady = true
                elseif eval.usable or eval.untrained then
                    if job.expect and scan and math.abs(eval.value - job.expect) > job.expect * 0.005 then
                        scan.bucketsVary = true
                    end
                    CountAuction(found, job, eval, info)
                end
            end
        end
    end

    if notReady and job.evalTries < (job.unread and UNREAD_RETRIES or EVAL_RETRIES) then
        job.evalTries = job.evalTries + 1
        if run.stats then run.stats.waits = run.stats.waits + 1 end
        job.state = "wait"
        job.retryAt = GetTime() + 0.3
        return
    end

    -- Replace whatever this row had in the list with what is for sale now.
    for id, offer in pairs(S.offers) do
        if offer.ks == job.ks then S.offers[id] = nil end
    end
    for id, offer in pairs(scan and scan.aside or {}) do
        if offer.ks == job.ks then scan.aside[id] = nil end
    end
    for id, offer in pairs(found) do
        if offer then S.offers[id] = offer end
    end
    -- (A weapon of a kind not trained, which the character has not asked for: found, and
    -- kept out of the list all the same.)
    SetAside()
    front.dirty = true
    S.changes = S.changes + 1

    -- Is the row's lowest price really a floor under its buyouts? Now and then a cheaper
    -- auction is posted between the browse and this search; more than that means the server
    -- reports something else, and the scan stops relying on it.
    if scan and IsScanMode(run.mode) and (job.minPrice or 0) > 0 then
        scan.checked = scan.checked + 1
        -- (How often the price an item is listed at before its search is the right one.)
        if lowest and lowest == job.minPrice then scan.exact = scan.exact + 1 end
        if lowest and lowest < job.minPrice then
            scan.belowFloor = scan.belowFloor + 1
            if scan.belowFloor >= FLOOR_MISSES and scan.belowFloor > scan.checked * FLOOR_MISS_SHARE then
                scan.floorBroken = true
            end
        end
    end

    job.status = "done"
    NoteJob(job, true)
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
--   * with "top N per slot" or "hide worse deals" on, most of the candidates still waiting
--     are ruled out by the offers found on the way, so their number says nothing about the
--     time left;
--   * nothing has been timed yet, in this run or in an earlier scan.
-- The estimate is the searches left times the seconds one search takes. That pace starts as
-- the last scan's and gives way to this run's own as its searches come back.
function S.TimeLeft()
    if S.state ~= "verify" or not run or not scan or not IsScanMode(run.mode) then return nil end
    if (ns.db.topOnly or ns.db.hideWorse or ns.db.plan) and not scan.bucketsVary and not scan.floorBroken then return nil end
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

-- Has the job waited long enough for an answer? Its first sending is given up early (see
-- SendJob), but only when another request can go out at once.
local function Overdue(job, now)
    if now > job.deadline then return true end
    return job.state == "query" and job.early ~= nil and now > job.early and AH.IsThrottledMessageSystemReady()
end

local function StepJobs(now)
    local job = run.job
    if not job then return end
    if job.state == "read" or (job.state == "wait" and now >= job.retryAt) then
        ReadJob(job)
    elseif (job.state == "query" or job.state == "more") and Overdue(job, now) then
        if job.state == "more" then
            job.state = "read"          -- read what did arrive
        elseif job.tries < JOB_RETRIES then
            job.tries = job.tries + 1
            SendJob(job)
        else
            run.failed = true
            job.status = "failed"
            NoteJob(job, false)
            if run.stats then run.stats.timeouts = run.stats.timeouts + 1 end
            S.info.verified = S.info.verified + 1
            if IsScanMode(run.mode) then
                -- The scan goes on without this price, and the list says that one is missing.
                S.unanswered = S.unanswered + 1
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

---------------------------------------------------------------------------
-- Step 2: scoring the browse rows
---------------------------------------------------------------------------
-- true when the row is settled; false when it has to wait for the client to load something,
-- and then what: "data" the item itself, "sample" a link of one of the row's auctions,
-- "link" what that link stands for, "tip" its tooltip.
-- force: the row is read though the client does not say that it has loaded the item. Of a
-- few dozen items of a scan it never says so, however long it is waited for, while the
-- row's own link may tell all there is to know. A row that cannot be read so either still
-- waits for "data": its item is what the client lacks.
local function ScoreRow(row, force)
    local key = row.key
    local itemID = key.itemID
    local cached = C_Item.IsItemDataCachedByID(itemID)
    if not cached then
        if not run.requested[itemID] then
            run.requested[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        if not force then return false, "data" end
    end

    -- An item that stacks is sold by the piece out of one pile, as consumables are, whatever
    -- it is filed under (a grey necklace that is a quest's trophy is Armor). It has no
    -- auctions to read or to bid on, and no sample link either: the row would wait for one,
    -- and the search for it is answered with a price list. Nothing for this list.
    if (C_Item.GetItemMaxStackSizeByID(itemID) or 1) > 1 then return true end

    -- The link of one real auction in this row: the item as it is for sale, "of the Tiger"
    -- and all. No link made from the row's key could stand in for it: the variant is in no
    -- field of a link that the key could fill in, and the plain item scores as something else.
    -- So a row without a sample waits for one, and if none comes the item search decides
    -- (see GiveUp).
    local link = AH.GetItemKeySampleLink(key)
    if not link then
        if not row.asked then
            row.asked = true
            -- Has the client fetch what it lacks about the row's item; it says
            -- ITEM_KEY_ITEM_INFO_RECEIVED when it has. (Whether that brings a sample link
            -- is not written down anywhere, hence the wait and not a promise.)
            AH.GetItemKeyInfo(key)
        end
        return false, cached and "sample" or "data"
    end

    local eval = EvalLink(link)
    if eval == nil then return false, cached and "link" or "data" end

    -- A row that came without a level, and was kept for its item to say (see AddRow): made
    -- for less than this scan reads, it is nothing for the list, as the rows dropped when
    -- they came are not. Gear that asks for no level (0) is not made for less: the filter
    -- leaves it alone, and it is judged like any other row.
    -- (Not among the rows dropped by score either: no search of it could find anything.)
    if eval and scan.fromLevel and eval.reqLevel > 0 and eval.reqLevel < scan.fromLevel then
        if not cached and run.stats then run.stats.forced = run.stats.forced + 1 end
        return true
    end

    -- A candidate is what is better than the gear in some place. Also one that would be for
    -- a character that fills its hands another way than it has said (`spare`): that may be
    -- said by the time the list is read, and the row is not read again then.
    local better = eval and #ns.Compare.Place(eval, S.ctx) > 0
    local spare = eval and not better and ns.Compare.Possible(eval, S.ctx)
    if better or spare then
        -- Red text is about the item, not the auction, so the sample answers for the row.
        if eval.usable == nil then ReadTooltip(eval) end
        if eval.usable == nil then return false, cached and "tip" or "data" end
        -- (An item the tooltip has just called unique-equipped, and that is worn, is a
        -- candidate still: SkipReason finds it no better than the gear.)
        -- A weapon the character cannot hold for want of training alone is kept as the
        -- spare ones are, for the character to say that it will train: see AddCandidate.
        if eval.usable or eval.untrained then
            if not cached and run.stats then run.stats.forced = run.stats.forced + 1 end
            AddCandidate(row, eval, spare or eval.untrained)
            return true
        end
    end
    if not cached and run.stats then run.stats.forced = run.stats.forced + 1 end
    scan.rejected[#scan.rejected + 1] = row
    -- (A row read late, after the rows dropped by score were sent to their searches: NextJob.)
    if scan.requeued then AddCandidate(row) end
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
-- best is Supplies.lua's business: it is settled when the list is drawn, so another
-- profile needs no new scan.

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
        if not effect and text and text:sub(1, #prefix) == prefix then
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
        if not C_Item.GetItemSpell(itemID) then return true end
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
        stats = ns.SupplyData.stats[itemID],        -- { ITEM_MOD_STRENGTH_SHORT = 25, ... } to be scored
        restores = ns.SupplyData.restores[itemID],  -- "H" health, "M" mana, "HM" both...
        price = row.minPrice,   -- of one piece
        quantity = row.quantity,
    }
    return true
end

-- The list does not wait for a few rows the client is slow to tell about: once the others
-- are read and nothing more has come for a moment, the candidates are listed and their prices
-- looked up, and the rows still unread are read on meanwhile (StepLate). They belong to the
-- scan and not to the run: scan.late = { rows, at = when a row was last read, nextTry }.
-- (A few: see UNREAD_FEW. With more unread the client is still loading its items, and the
-- list waits: StepScore.)
-- Each is asked for once more: one asking is not known to be answered always.
local function HoldLate(rows)
    local stats = run.stats
    scan.late = { rows = rows, at = run.lastRead, nextTry = 0 }
    for i = 1, #rows do
        local row = rows[i]
        local why = row.why or "?"
        if stats then
            stats.late = stats.late + 1
            stats.lateWhy[why] = (stats.lateWhy[why] or 0) + 1
        end
        if why == "data" then
            C_Item.RequestLoadItemDataByID(row.key.itemID)
        elseif why == "sample" then
            AH.GetItemKeyInfo(row.key)
        end
    end
end

-- Are the rows few, of all the scan has to score? (See UNREAD_FEW.)
local function Few(count)
    local all = S.info.toScore
    return count <= math.max(UNREAD_FEW, all * UNREAD_SHARE) and count <= all * UNREAD_MOST
end

local function StepScore(now)
    local started = Clock()
    local list = run.toScore
    local supplies = run.mode == "supplies"
    while run.scoreIndex <= #list do
        local row = list[run.scoreIndex]
        run.scoreIndex = run.scoreIndex + 1
        local read, why
        if supplies then
            read = ScoreSupply(row)
        else
            -- A row the client has not told of for a while, when only a few are left, or
            -- whose item it said it cannot load, is read without its say (ScoreRow).
            local force = row.since ~= nil
                and (run.dead[row.key.itemID] or (run.few and now - row.since >= LOAD_QUIET)) or false
            if force then row.forced = true end
            read, why = ScoreRow(row, force)
        end
        if read then
            S.info.scored = S.info.scored + 1
            run.lastLoad, run.lastRead = now, now
        else
            row.why = why
            row.since = row.since or now
            run.waiting[#run.waiting + 1] = row
            run.awaited[row.key.itemID] = true
        end
        if Clock() - started > FRAME_BUDGET_MS then
            ns.Fire("SCAN_PROGRESS")
            return
        end
    end
    local waiting = #run.waiting
    -- Every row has had its turn once: the client has from now to tell of the rest.
    if not run.passed then
        run.passed = true
        run.passedAt = now
        run.lastRead = now
        -- (How many it had not told of by then, and for want of what: the scan's numbers.
        -- In a real scan two rows of three: the client loads an item when it is asked for.)
        local stats = run.stats
        if stats and stats.waitingWhy then
            stats.waiting = waiting
            for i = 1, waiting do
                local why = run.waiting[i].why or "?"
                stats.waitingWhy[why] = (stats.waitingWhy[why] or 0) + 1
            end
        end
    end
    -- A few rows the client is slow with, or never tells of, are not worth the list's time.
    -- Many are a client still loading its items: the list would be a few rows of what is
    -- for sale, so they are waited for as long as it goes on telling of them.
    local few = Few(waiting)
    run.few = few
    -- Once the scan has stood still for the client (a moment without a row read, and many
    -- to come, or a scan for consumables, which has nowhere to go on to), the status line
    -- says so and counts the rows down. Until then it counts the rows scored, as ever.
    if not run.stalled and (supplies or not few) and now - run.lastRead > STALL_SAID then
        run.stalled = true
        if run.stats and run.stats.waitingWhy then run.stats.stalled = true end
    end
    local said = run.stalled and waiting or 0
    if S.info.waiting ~= said then
        S.info.waiting = said
        ns.Fire("SCAN_PROGRESS")
    end

    if waiting > 0 then
        -- The client is not going to tell us more: nothing came for a while, or the wait
        -- has been long enough whatever comes.
        local over = now - run.lastLoad > LOAD_TIMEOUT or now - run.passedAt > LOAD_LONGEST
        local settled = false
        if supplies then
            -- A consumable has no item search to go to: it is taken as far as it is known.
            -- A few rows, each of which has had its moment, are not waited for longer:
            -- there are rows whose items the client never loads.
            local ripe = few
            for i = 1, ripe and waiting or 0 do
                if now - run.waiting[i].since < SUPPLY_RIPE then
                    ripe = false
                    break
                end
            end
            if over or ripe then
                local lost = 0
                for i = 1, waiting do
                    local row = run.waiting[i]
                    ScoreSupply(row, true)
                    if not S.supplies[row.ks] then lost = lost + 1 end
                end
                -- (Many: the client has not loaded its items, and the list says so.)
                if not few then S.suppliesUnread = lost end
                S.info.scored = S.info.scored + waiting
                settled = true
            end
        elseif few then
            -- Each of the few has had its moment and a look without the client's say: on
            -- with the list and the prices, and they are read on meanwhile (HoldLate).
            local ripe = true
            for i = 1, waiting do
                if not run.waiting[i].forced then
                    ripe = false
                    break
                end
            end
            if ripe or over then
                HoldLate(run.waiting)
                settled = true
            end
        elseif over then
            -- Many, and the client has stopped telling of them. What an item search can
            -- tell goes to one (GiveUp); the rest is left out, and the list says how many
            -- rows it is short of, which a scan a little later will have.
            S.unread = S.unread + GiveUp(run.waiting)
            S.info.scored = S.info.scored + waiting
            settled = true
        end
        if settled then
            run.waiting = {}
        elseif now >= run.nextRetry then
            run.nextRetry = now + 0.25
            run.toScore, run.waiting, run.scoreIndex = run.waiting, {}, 1
            return
        else
            return
        end
    end
    S.info.waiting = 0

    ns.Fire("SCAN_PROGRESS")
    if supplies then
        FinishRun(true)
        return
    end
    scan.ready = true
    ListCandidates()
    StartVerify()
end

-- Reads on the rows the list did not wait for (HoldLate), a few times a second, while the
-- prices are looked up. A row that is read is a candidate like any other: in the list at
-- once, and looked up in its turn. What is still unread when nothing more has come for
-- LOAD_TIMEOUT goes to the item searches, and so does what is unread when the other prices
-- have all been looked up (NextJob): the scan does not stand still for these rows.
local LATE_RETRY = 0.25

local function StepLate(now)
    local late = scan.late
    if now < late.nextTry then return end
    local started = Clock()
    local rows, unread = late.rows, {}
    local known = #scan.candidates
    local at = 1
    while at <= #rows do
        local row = rows[at]
        at = at + 1
        local read, why = ScoreRow(row, true)
        if read then
            late.at = now
            if run.stats then run.stats.lateRead = run.stats.lateRead + 1 end
        else
            row.why = why
            unread[#unread + 1] = row
        end
        if Clock() - started > FRAME_BUDGET_MS then break end
    end
    -- The rows this frame had no time for come first in the next one.
    local cut = at <= #rows
    if cut then
        local rest = {}
        for i = at, #rows do rest[#rest + 1] = rows[i] end
        for i = 1, #unread do rest[#rest + 1] = unread[i] end
        unread = rest
    end
    late.nextTry = cut and now or now + LATE_RETRY
    -- (Whether or not this frame had time for every row: the run must not wait on for rows
    -- that it never gets to the end of.)
    if #unread > 0 and now - late.at > LOAD_TIMEOUT then
        GiveUp(unread)
        unread = {}
    end
    late.rows = unread
    if #unread == 0 then scan.late = nil end

    if #scan.candidates > known then
        SortCandidates()
        ListCandidates()
        local _, left = PickCandidate()
        S.info.toVerify = S.info.verified + left
        ns.Fire("SCAN_PROGRESS")
    end
    -- Nothing was being looked up, for want of a candidate: there may be one now, and with
    -- nothing left to wait for either the scan is over.
    if not run.job and (#scan.candidates > known or not scan.late) then NextJob() end
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
    local query = {
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
    -- A scan that reads no gear below a level (run.fromLevel) asks for none, in the two
    -- fields the game's own auction window fills from the "Level Range" of its filter menu.
    -- That window sends 0 for a level that was not typed, so this is its search with the
    -- lower level alone typed in (Blizzard_AuctionHouseFrame.lua, SendBrowseQueryInternal).
    -- The higher level is not named: what is above the character's is left to the level
    -- sort and the early stop, as before. Rows that a lower bound should have left out can
    -- be seen and dropped (AddRow), and counted; rows that an upper bound wrongly left out
    -- would simply be missing.
    -- A scan without such a level sends neither field, as every scan did before there was one.
    if run.bounded then
        query.minLevel, query.maxLevel = run.fromLevel, 0
    end
    return query
end

local function ResetOrder()
    run.order = { last = -1, count = 0, inversions = 0, above = 0, below = 0, noLevel = 0 }
end

-- Notes the required level of each row in arrival order: of every row that arrives, kept or
-- not. A row below the level the scan reads from (run.fromLevel) is a row of the order like
-- any other, where the auction house sends such rows at all; where it does not, the rows
-- begin at that level and go up as before. Either way the run of rows above the character's
-- level, which is what ends the browse early, is neither made nor broken by the lower bound.
-- Such rows are counted, and so are the rows without a level: the scan's numbers say by
-- them whether the auction house goes by the level it was asked for (see NewStats).
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
    local from = run.fromLevel
    if from and required == 0 then
        order.noLevel = order.noLevel + 1
    elseif from and required < from then
        order.below = order.below + 1
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
    -- Gear made for a level further below the character's than it is to be offered: dropped
    -- here whether or not the auction house was asked to leave it out, so of gear that asks
    -- for a level the list is the same from one that does not go by what it is asked.
    -- A row without a level stays. The game gives 0 for gear that asks for no level, which
    -- the filter leaves alone, and nothing at all for a row it cannot tell the level of yet,
    -- which reads as 0 here too: the row's item says which it is when it is scored
    -- (ScoreRow). Whether such rows come at all is the auction house's to say. One that
    -- takes the lower bound of the search to leave out gear without a level sends none, and
    -- the list of that scan is without them: the search is not made wider for their sake
    -- (BrowseQuery), and a scan with the box unticked reads them.
    if run.fromLevel and required > 0 and required < run.fromLevel then return end

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
    -- Armor heavier than the class can ever wear (subclasses 1 to 4, cloth to plate) is dropped
    -- before scoring. This only saves time: it could never be an offer.
    if classID == ARMOR_CLASS and run.armorLimit and subClassID
        and subClassID >= 1 and subClassID <= 4 and subClassID > run.armorLimit then
        return
    end

    local row = { key = key, ks = ks, minPrice = result.minPrice, own = result.containsOwnerItem or nil }
    run.rows[ks] = row
    run.toScore[#run.toScore + 1] = row
end

local function FinishBrowse(partial)
    if partial then
        if run.mode == "supplies" then S.suppliesPartial = true else S.partial = true end
    end
    -- Gear may have still been on its way from the server when the scan began (see
    -- Score.Context): by now it has had time to come.
    if run.mode ~= "supplies" and S.ctx and S.ctx.pending then
        S.ctx = ns.Score.Context(S.ctx.profile, S.ctx.who)
        Recheck()
        S.changes = S.changes + 1
    end
    S.info.toScore = #run.toScore
    S.info.scored = 0
    run.scoreIndex = 1
    run.lastLoad = GetTime()
    run.lastRead = run.lastLoad
    run.nextRetry = 0
    SetState("score")
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

-- The search that names the lowest level to read (run.bounded, see BrowseQuery) brought
-- nothing: it goes out once more without the level, and is then the search every scan sent
-- before there was one. The scan reads more that way and its list is the same: the rows
-- below the level are dropped here either way (AddRow). Its numbers say that it went so.
local function SendUnbounded()
    run.bounded = false
    run.stats.levelAsked = false
    SendBrowse()
end

local function ReadBrowse()
    local results = AH.GetBrowseResults() or {}
    local count = #results
    for i = run.seen + 1, count do
        AddRow(results[i])
    end
    run.seen = count
    -- Asked for nothing below a level, and answered with nothing at all: an auction house
    -- without one piece of gear from that level up is less likely than one that makes
    -- something else of the two fields than the game's own window means by them.
    if run.bounded and count == 0 and AH.HasFullBrowseResults() then
        SendUnbounded()
        return
    end
    run.answered = true
    S.info.rows = run.rowCount
    -- (What the auction house sent of what it was asked to leave out, as far as the rows
    -- read so far tell: kept up with them, so that a scan stopped half way has it too.)
    if run.fromLevel then
        run.stats.belowLevel, run.stats.noLevel = run.order.below, run.order.noLevel
    end
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

local function StepBrowse(now)
    if now <= run.deadline then return end
    if run.answered then
        FinishBrowse(true)              -- keep the rows that did arrive
    elseif run.bounded then
        SendUnbounded()                 -- no answer to the search that names a level
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
    -- The character the work is for, when it is not the one being played (a card from
    -- Roster), and its level: rows that ask for a higher one are of no use to it. For gear both
    -- are in the gear snapshot.
    local who, level = nil, UnitLevel("player")
    if supplies then
        who = S.suppliesWho
        if who then level = who.level or level end
    elseif S.ctx then
        who, level = S.ctx.who, S.ctx.level
    end
    -- A scan for consumables counts its requests too, but nobody reads the numbers.
    local stats
    if scanning then stats = S.stats elseif mode == "supplies" then stats = NewStats() end
    run = {
        mode = mode,
        who = who,
        level = level,
        variant = 1,
        rows = {},          -- key string -> row
        rowCount = 0,
        seen = 0,
        toScore = {},
        scoreIndex = 1,
        waiting = {},       -- rows waiting for the client to load item data
        requested = {},
        -- Items of the rows that wait: one of them loaded is a sign of life; and those the
        -- client said it cannot load (OnItemLoaded).
        awaited = scanning and scan.awaited or {},
        dead = scanning and scan.dead or {},
        -- A lookup around a purchase scores its item afresh; a scan keeps its scores.
        evalCache = scanning and scan.evalCache or {},
        unsettled = scanning and scan.unsettled or {},  -- item link -> when it first had no reading (EvalLink)
        stats = stats,
        deadline = 0,
        lastLoad = 0,       -- when the client last loaded an item a row waits for, or a row was read
        lastRead = 0,       -- when a row was last read (see StepScore)
        passed = false,     -- every row has had its turn once
        nextRetry = 0,
    }
    ResetOrder()
end

function S.IsOpen()
    return ahOpen
end

-- Is the work in hand a scan for gear, or prices the list came to need after one? (As against
-- a scan for consumables, or a lookup around a purchase.)
function S.IsScan()
    return IsScanMode(S.mode)
end

-- Forgets the last scan for gear (its scores belong to another profile, for instance).
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
    S.unanswered = 0
    S.unread = 0
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
    S.suppliesUnread = 0
    S.suppliesNote = nil
    S.suppliesWho = nil
    ns.Fire("OFFERS_CHANGED")
end

-- Brings what was bought (S.acquired) in line with a gear snapshot that was just made: what
-- has been put on since is gear now, and the rest is scored on the snapshot's profile, which
-- may be another one than it was bought under.
local function Reacquire()
    local ctx = S.ctx
    -- Only the character being played puts anything on while the addon looks. What is worn
    -- is told by the item as the player sees it: another variant of the item that was bought
    -- ("of the Whale" on, "of the Tiger" in the mail) is not the purchase.
    local worn = {}
    if not ctx.who then
        for _, gear in pairs(ctx.equipped) do
            local key = ns.ItemKey(gear.link)
            if key then worn[key] = true end
        end
    end
    for i = #S.acquired, 1, -1 do
        local item = S.acquired[i]
        local scored = not worn[ns.ItemKey(item.link) or ""] and ns.Score.Item(item.link) or nil
        if scored then
            item.value = ns.Score.Value(scored, ctx.profile, ctx.level)
            item.offValue = ns.Score.OffValue(scored, ctx.profile, ctx.level)
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
    local profile = ns.Score.Current(who)
    if not profile then
        -- (With another addon scoring: the character has no scale there, as with no Pawn
        -- scale switched on.)
        S.message = ns.Score.Text("NO_SCALE") or L.ERR_NO_PROFILE
        ns.Fire("SCAN_STATE")
        return false
    end

    S.ctx = ns.Score.Context(profile.name, who)
    contextTries = 0
    Recheck()
    Reacquire()
    S.offers = {}
    S.changes = S.changes + 1
    S.partial = false
    S.unanswered = 0
    S.unread = 0
    S.halted = false
    S.finishedAt = nil
    S.info = { rows = 0, scored = 0, toScore = 0, verified = 0, toVerify = 0 }
    S.stats = NewStats()
    answers, doubled = {}, nil
    confirming = false
    scan = {
        candidates = {},    -- rows whose item scored as an upgrade (see AddCandidate)
        spares = 0,         -- of those, rows kept for another way of filling the hands
        sparesCut = false,  -- more of those were found than are kept
        aside = {},         -- offers of weapons of a kind not trained and not asked for (SetAside)
        rejected = {},      -- rows dropped by score alone
        evalCache = {},     -- item link -> score (see EvalLink)
        unsettled = {},     -- item link -> when the game first had no reading of it
        awaited = {},       -- item -> a row waits for it
        dead = {},          -- item -> the client said it cannot load it
        searchedUnread = 0, -- rows never read that went to their item searches (GiveUp)
        ready = false,      -- scoring finished: the candidates are all known
        bucketsVary = false,-- some row held items that differ from its sample
        requeued = false,
        checked = 0,        -- rows whose auctions were read
        belowFloor = 0,     -- of those, rows with a buyout below the row's lowest price
        exact = 0,          -- and rows whose cheapest buyout was that price
        listed = 0,         -- candidates put into the list before their search
        floorBroken = false,-- so many of them that the row's lowest price cannot be relied on
    }
    -- The lowest level gear may ask for and still be offered to the character (Wants.lua),
    -- as it is asked for when the scan begins: nothing below it is read, or kept. nil for a
    -- character that is offered gear of every level. The scan goes by this to its end,
    -- whatever is ticked meanwhile; what the list shows goes by what is asked then
    -- (Wants.Fits), and S.ReadFrom says when that is more than was read: the scan is then
    -- made again (S.Reread).
    local wants = Wanted()
    scan.fromLevel = wants and wants.level or nil
    NewRun("scan")
    run.armorLimit = ns.Roster.HeaviestArmor(S.ctx.class)
    -- The level is named in the search itself (BrowseQuery), until a search that names it
    -- brings nothing (SendUnbounded).
    run.fromLevel = scan.fromLevel
    run.bounded = run.fromLevel ~= nil
    S.stats.fromLevel, S.stats.levelAsked = run.fromLevel or 0, run.bounded
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
            -- (Rows that were still being read are candidates from here on, for their
            -- item searches to decide: nothing reads them on while no run is under way.)
            if scan and scan.late then
                GiveUp(scan.late.rows)
                scan.late = nil
            end
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

-- The level the last scan read gear from, or the one under way reads from, when the list is
-- now to show gear made for less: the character's filter of levels (Wants.lua) was made
-- wider or switched off since. What a scan did not read is not there to be shown, and
-- nothing short of a scan brings it (S.Demand looks up prices of rows that were read):
-- S.Reread makes that scan. nil when the list has all it is to show, and when there is no
-- list. (A filter made narrower since needs nothing: the rows it leaves out are hidden at
-- once.)
function S.ReadFrom()
    local from = scan and scan.fromLevel
    if not from then return nil end
    local wants = Wanted()
    if wants and wants.level and wants.level >= from then return nil end
    return from
end

-- Scans for gear again when the list is short in that way, with the filter as it is now; a
-- scan under way, or the price checks after one, is started over. Returns false, and neither
-- does nor says anything, when the list is not short or no scan can start: the auction
-- house is closed, a purchase is being looked up or waits for its "Buy this?", a scan for
-- consumables is under way, or the character has nothing to be scored by. The list is then
-- as it was. (The tab calls this a moment after the filter changed: RereadSoon in UI.lua.)
function S.Reread()
    if not S.ReadFrom() then return false end
    if not ahOpen or confirming then return false end
    if S.state ~= "idle" and not IsScanMode(S.mode) then return false end
    if not ns.Score.Current(ns.Roster.Target()) then return false end
    S.Stop()
    return S.Start()
end

-- Looks up the prices the list needs now and does not have. Called whenever the list is
-- redrawn; does nothing unless a scan left candidates that the current settings would show.
function S.Demand()
    if S.state ~= "idle" or S.halted or confirming then return false end
    if not ahOpen or not S.ctx or not scan or not scan.ready then return false end
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

-- Can a purchase begin now? When nothing is under way, and also during the price checks of a
-- scan: the list is there to buy from as soon as the candidates are known (ListCandidates),
-- and a purchase is not made to wait for the rest of the prices.
function S.CanBuy()
    return ahOpen and (S.state == "idle" or (S.state == "verify" and IsScanMode(S.mode)))
end

-- The price checks of a scan give way to a purchase. They are picked up again when the list
-- next asks for what it lacks (S.Demand), which it does once the purchase is over.
local function GiveWay()
    if S.state == "idle" then return end
    S.Stop()
    S.halted = false
end

-- Before buying, look the item up again: the scan may be minutes old, and a price that came
-- with the candidate was never looked up at all. Fires CONFIRM_BUY with the fresh offer when
-- it is still there, and with the price the list had when that is no longer its price: the
-- question then shows both.
function S.Buy(offer)
    if S.state ~= "idle" and not S.CanBuy() then
        ns.Print(L.ERR_BUSY)
        return
    end
    if not ahOpen or not S.ctx then return end
    if GetMoney() < offer.buyout then
        ns.Print(L.MSG_CANT_AFFORD)
        return
    end
    GiveWay()
    confirming, asking = false, nil
    local id, link, price = offer.id, offer.link, offer.buyout
    -- "Is it still there at this price" is answered by the first auction at that price.
    SearchOne("buy", offer, function(ok)
        local fresh = S.offers[id]
        if not ok then
            ns.Print(L.ERR_BROWSE)
        elseif not fresh then
            ns.Print(L.MSG_GONE:format(link))
        else
            confirming = true
            ns.Fire("CONFIRM_BUY", fresh, fresh.buyout ~= price and price or nil)
        end
    end, offer.uniform and price or nil)
end

-- The player said yes in the confirmation box. The box stays up until the auction house
-- answers, so `confirming` holds until it goes (S.CancelPurchase).
function S.ConfirmPurchase(offer)
    if not ahOpen then
        confirming = false
        return
    end
    purchases[offer.auctionID] = offer
    -- Whom it is bought for, should the lists be for someone else by the time it is bought.
    offer.boughtFor = S.ctx and S.ctx.who or nil
    AH.PlaceBid(offer.auctionID, offer.buyout)
end

-- The auction house turned the bid down: someone else was faster, most likely. The box is
-- still up, so the item is looked up once more and the box told what came of it:
--   CONFIRM_BUY  as after S.Buy: it is for sale, at the price the player agreed to or another
--   BUY_GONE     there is none left
--   BUY_FAILED   the auction house did not answer
-- Returns false, and does nothing, when it cannot look now.
function S.BuyAgain(offer)
    if S.state ~= "idle" or not ahOpen or not S.ctx then return false end
    local id, price = offer.id, offer.buyout
    local mine = {}
    asking = mine
    SearchOne("buy", offer, function(ok)
        local fresh = S.offers[id]
        -- The player closed the box meanwhile: there is nothing to show it. An item that has
        -- left the list for good is told in the chat.
        if asking ~= mine then
            if ok and not fresh then ns.Print(L.MSG_GONE:format(offer.link)) end
            return
        end
        asking = nil
        if not ok then
            ns.Print(L.ERR_BROWSE)
            ns.Fire("BUY_FAILED", offer)
        elseif not fresh then
            ns.Fire("BUY_GONE", offer)
        else
            confirming = true
            ns.Fire("CONFIRM_BUY", fresh, fresh.buyout ~= price and price or nil)
        end
    end, offer.uniform and price or nil)
    return true
end

-- The confirmation box went away, with or without a purchase.
function S.CancelPurchase()
    asking = nil
    if not confirming then return end
    confirming = false
    ns.Fire("OFFERS_CHANGED")
end

-- Rebuilds the gear snapshot (after the player changes equipment, or when gear the snapshot
-- was waiting for has come from the server). The offers keep their
-- scores, so the list can be re-ranked without another scan.
function S.RefreshContext()
    if not S.ctx then return end
    S.ctx = ns.Score.Context(S.ctx.profile, S.ctx.who)
    Recheck()
    Reacquire()
    S.changes = S.changes + 1
    -- (A candidate kept for another way of filling the hands may have its place now.)
    if scan and scan.ready then ListCandidates() end
    ns.Fire("OFFERS_CHANGED")
end

-- The character the list is for wants something else of its gear (Wants.lua). The list
-- follows by itself: it is made from the offers each time it is drawn, and asks for the
-- prices it then lacks (S.Demand). One thing is done here: a candidate kept for another way
-- of filling the hands, which is the way now, is put into the list as the others were, at its
-- row's lowest price, so that the list has it at once and not only when its price is known.
-- The same for one kept for a kind of weapon not trained, which is ticked now; and what was
-- listed of a kind that is unticked again goes out of the list, to where it was kept.
ns.Listen("WANTS_CHANGED", function(card)
    if not scan or not scan.ready or not S.ctx then return end
    if card ~= (S.ctx.who or ns.Roster.Me()) then return end
    if SetAside() then
        front.dirty = true
        S.changes = S.changes + 1
    end
    ListCandidates()
end)

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
    S.suppliesUnread = 0
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
-- The game takes a request for a price, like a bid, only from a click or a key press (its
-- documentation marks both as restricted), so each step is called straight from one.
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

-- The answer for something sold as separate auctions, which the consumables that do not stack
-- are. An auction is one piece, and its buyout is the price of that piece; a seller's auctions
-- at one price come as one line, whose `quantity` says how many they are (the game shows
-- that number beside the price). So a line is an entry of the price list like any other, with
-- the auction to bid on.
local function ReadLookupAuctions(itemKey)
    if not ns.SameKey(itemKey, run.lookup.supply.key) then return end
    local tiers = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local info = AH.GetItemSearchResultInfo(itemKey, i)
        local buyout = info and info.buyoutAmount or 0
        if buyout > 0 and not info.containsOwnerItem and not info.containsAccountItem then
            tiers[#tiers + 1] = { price = buyout, quantity = info.quantity, auctionID = info.auctionID }
        end
    end
    FinishLookup(tiers)
end

-- Step one of a purchase. Fires CONFIRM_SUPPLY with the consumable and its price list.
function S.BuySupply(supply)
    if S.state ~= "idle" and not S.CanBuy() then
        ns.Print(L.ERR_BUSY)
        return
    end
    if not ahOpen then return end
    GiveWay()
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

-- From a click: buys one piece of a consumable that is sold as separate auctions, the cheapest.
function S.BuySupplyAuction(supply, tiers)
    local auction = tiers[1]
    supplyBids[auction.auctionID] = { supply = supply, tiers = tiers }
    AH.PlaceBid(auction.auctionID, auction.price)
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
        -- (Either may have ended the run.)
        if run and scan and scan.late and IsScanMode(run.mode) then StepLate(now) end
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
    supplyBids = {}
    S.Stop()
end)

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", Pump)

ns.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    -- The server threw a request away. If it was ours, ask again.
    if run and not pending and lastRequest then
        pending = lastRequest
        if run.stats then run.stats.dropped = run.stats.dropped + 1 end
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

-- The answer to an item search: for the job of a scan, or for the lookup before a consumable
-- is bought.
local function OnItemResults(itemKey)
    if S.state ~= "verify" or not run then return end
    if run.lookup then
        ReadLookupAuctions(itemKey)
        return
    end
    local job = run.job
    if job and (job.state == "query" or job.state == "more") and ns.SameKey(itemKey, job.key) then
        ContinueJob(job)
    else
        NoteStray(itemKey)
    end
end
ns.On("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
ns.On("ITEM_SEARCH_RESULTS_ADDED", OnItemResults)

-- The gear snapshot is made again a moment after it goes out of date, and once however many
-- times the game says so: a set of gear is put on piece by piece.
local QueueContext = ns.Soon(0.5, function() S.RefreshContext() end)

local function OnItemLoaded(itemID, success)
    -- Of an item a row waits for. Loaded: a sign that the client is still telling of the
    -- rows (the game loads items for everybody all the time, and those say nothing). Not
    -- to be loaded, by its own word: the item's rows are not waited for (StepScore).
    if run and itemID ~= nil and run.awaited[itemID] then
        if success == false then
            if not run.dead[itemID] then
                run.dead[itemID] = true
                if run.stats then run.stats.dead = run.stats.dead + 1 end
            end
        elseif S.state == "score" then
            run.lastLoad = GetTime()
        elseif scan and scan.late then
            scan.late.at = GetTime()
        end
    end
    -- An item the gear snapshot was waiting for (see Score.Context).
    local ctx = S.ctx
    if ctx and ctx.pending and itemID ~= nil and ctx.pending[itemID] then QueueContext() end
end
ns.On("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
ns.On("GET_ITEM_INFO_RECEIVED", OnItemLoaded)
-- (What the client fetched about a row's item, asked for in ScoreRow.)
ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", function(itemID) OnItemLoaded(itemID) end)

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    -- An item search of the scan for gear that is answered with a price list was for
    -- something sold by the piece. ScoreRow lets through none that it knows to stack; this is
    -- one the client had not loaded by then. The answer is in, and it holds no auctions.
    local job = run and not run.lookup and run.job
    if job and S.state == "verify" and job.state == "query" and job.key.itemID == itemID then
        job.state = "read"
        return
    end
    ReadLookupPieces(itemID)
end)

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

-- A purchase of pieces fell through: the server would not name a price for them (they are
-- gone, or cost far more than the price list said), or it named one and someone was faster.
local function SupplyFailed()
    if not quote then return end
    local supply = quote.supply
    quote = nil
    confirming = false
    -- The game's own box calls the purchase off whenever it closes, whatever came of it.
    AH.CancelCommoditiesPurchase()
    ns.Print(L.MSG_BUY_FAILED:format(supply.link))
    ns.Fire("SUPPLY_DONE")
    ns.Fire("OFFERS_CHANGED")
end
ns.On("COMMODITY_PRICE_UNAVAILABLE", SupplyFailed)
ns.On("COMMODITY_PURCHASE_FAILED", SupplyFailed)

-- The auction house turned something down, and says no more than that. With a bid on a
-- consumable's auction out, the bid is what it turned down: the auction is gone, most likely.
-- (A bid on gear waits in the tab's box, which closes itself on this: see UI.lua.)
ns.On("AUCTION_HOUSE_SHOW_ERROR", function()
    if not next(supplyBids) then return end
    for _, bid in pairs(supplyBids) do
        ns.Print(L.MSG_BUY_FAILED:format(bid.supply.link))
    end
    supplyBids = {}
    confirming = false
    ns.Fire("SUPPLY_DONE")
    ns.Fire("OFFERS_CHANGED")
end)

ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    local bid = supplyBids[auctionID]
    if bid then
        supplyBids[auctionID] = nil
        SupplyBought(bid.supply, bid.tiers, 1, bid.tiers[1].price)
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
        offValue = offer.offValue,
    }
    -- A budget that was set is for what is still to be spent.
    if S.budget then S.budget = math.max(0, S.budget - offer.buyout) end
    -- Bought for another character: Mail.lua sees it on its way there.
    ns.Fire("GEAR_BOUGHT", offer, offer.boughtFor)
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

-- A search that is not ours, sent while the prices are looked up: the auction house takes
-- one request at a time, so it may cost one of ours its answer. Counted, to be read after a
-- real scan (lastScan.foreign).
local function OnForeignSearch()
    if S.state == "verify" and run and run.stats and not sendingSearch and not sendingBrowse then
        run.stats.foreign = run.stats.foreign + 1
    end
end
hooksecurefunc(AH, "SendSearchQuery", OnForeignSearch)
hooksecurefunc(AH, "SendBrowseQuery", OnForeignSearch)
hooksecurefunc(AH, "SendBrowseQuery", OnForeignBrowse)
hooksecurefunc(AH, "SearchForFavorites", OnForeignBrowse)
hooksecurefunc(AH, "SearchForItemKeys", OnForeignBrowse)
