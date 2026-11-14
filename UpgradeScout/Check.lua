local _, ns = ...

-- A check of Stats.lua against Pawn, for as long as Pawn is what scores the gear.
--
-- The addon is on its way to reading an item's stats from the game (Stats.lua) and not from
-- Pawn. Whether the game's numbers say all that Pawn's reading of the tooltip says cannot be
-- told without the game, so the game is asked: with the check on (/upscout check), every row
-- of a scan for gear is read both ways and written down in UpgradeScoutDB.check, to be
-- compared afterwards outside the game. Every row means every row: the ones above the
-- character's level and the armor it cannot wear as well, and the scan reads the auction
-- list to its end and does not stop early. The scan's own list is made as always.
--
-- The check has no part in what the addon shows, and goes when Pawn does. Its few words to
-- the player are therefore here and in two languages, not in Locale.lua.
local Check = {}
ns.Check = Check

local AH = C_AuctionHouse

local T = {
    ON = "Check against Pawn is on. Open the auction house and press Scan: every piece of gear for sale will be read twice, by the game and by Pawn.",
    STARTED = "Check against Pawn is on, and a scan has begun: every piece of gear for sale will be read twice, by the game and by Pawn.",
    OFF = "Check against Pawn is off. What it wrote down stays until the next check.",
    NO_PAWN = "The check needs Pawn, and Pawn is not answering.",
    DONE = "Check done: %d items read. With a suffix: %d, with ratings: %d, with healing: %d. Pawn read nothing for %d, the game for %d; %d rows gave no item.",
    MISSING = "Not for sale right now, so not checked: items %s. Run the check again when there are some.",
    FULL = "The check stopped writing at %d items.",
    CLOSED = "The auction house was closed before the check was through: %d rows were left unread.",
    SAVE = "Type /reload to save what the check wrote down.",
    SUFFIX = "with a suffix", RATINGS = "with ratings", HEALING = "with healing",
    PAWN = "Pawn: %s",
    PAWN_NONE = "Pawn: nothing",
}
if GetLocale() == "ruRU" then
    T = {
        ON = "Сверка с Pawn включена. Открой аукцион и нажми «Скан»: каждая вещь в продаже будет прочитана дважды, игрой и Pawn.",
        STARTED = "Сверка с Pawn включена, скан пошёл: каждая вещь в продаже будет прочитана дважды, игрой и Pawn.",
        OFF = "Сверка с Pawn выключена. Записанное хранится до следующей сверки.",
        NO_PAWN = "Сверке нужен Pawn, а он не отвечает.",
        DONE = "Сверка готова: прочитано вещей: %d. С суффиксом: %d, с рейтингами: %d, лечебных: %d. Pawn ничего не прочитал у %d, игра у %d; строк без предмета: %d.",
        MISSING = "Сейчас не продаются и потому не проверены: вещи %s. Повтори сверку, когда такие появятся.",
        FULL = "Сверка перестала записывать на %d вещах.",
        CLOSED = "Аукцион закрыли до конца сверки: непрочитанных строк: %d.",
        SAVE = "Набери /reload, чтобы записанное сохранилось.",
        SUFFIX = "с суффиксом", RATINGS = "с рейтингами", HEALING = "лечебные",
        PAWN = "Pawn: %s",
        PAWN_NONE = "Pawn: ничего",
    }
end

local LIMIT = 20000         -- rows written down at most: the saved file is read at every login
local BUDGET_MS = 8         -- reading time per step, to keep the game smooth
local STEP = 0.05           -- seconds between steps
local RETRY = 0.5           -- seconds before a row that had to wait is looked at again
local PATIENCE = 15         -- seconds a row may wait for the client to load it
local PAWN_TRIES = 3        -- Pawn may read a tooltip a moment too early: it is asked again
local QUIET = 1             -- seconds without work before the check says it is done

local on = false
local data                  -- UpgradeScoutDB.check
local queue, head = {}, 1   -- rows to read, from `head` on
local known = {}            -- key string -> true, for every row taken
local lastWork = 0
local lastRead = 0          -- when a row was last settled
local said = true          -- the outcome has been said and nothing came after it
local stepping = false

-- A table of stats as it can be saved: its numbers and nothing else; false for none.
local function Numbers(stats)
    if type(stats) ~= "table" then return false end
    local out = {}
    for name, amount in pairs(stats) do
        if type(name) == "string" and type(amount) == "number" then out[name] = amount end
    end
    return out
end

local function HasKey(stats, pattern)
    if not stats then return false end
    for name in pairs(stats) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Reads one row both ways and writes it down.
--   true   the row is settled: written down, or not gear
--   false  the client or Pawn is not ready for it yet
local function Read(row)
    local key = row.key
    if not C_Item.IsItemDataCachedByID(key.itemID) then
        if not row.requested then
            row.requested = true
            C_Item.RequestLoadItemDataByID(key.itemID)
        end
        return false
    end
    -- The link of one real auction of the row: the item as it is for sale, suffix and all.
    local link = AH.GetItemKeySampleLink(key)
    if not link then
        if not row.asked then
            row.asked = true
            AH.GetItemKeyInfo(key)
        end
        return false
    end
    local name, fullLink, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(link)
    if not name or not fullLink then return false end
    if not ns.Compare.Handles(equipLoc) then return true end

    local item = PawnGetItemData(fullLink)
    if not item and row.tries < PAWN_TRIES then
        row.tries = row.tries + 1
        return false
    end
    local game = ns.Stats.Read(fullLink)
    local pawn = item and Numbers(item.UnenchantedStats or item.Stats) or false

    local record = {
        link = fullLink:match("item:[%-%d:]+") or fullLink,
        name = name,
        suffix = key.itemSuffix or 0,
        game = game or false,
        pawn = pawn,
    }
    -- The lines of the tooltip Pawn could make nothing of.
    if item and type(item.UnknownLines) == "table" then
        local lines = {}
        for line in pairs(item.UnknownLines) do
            if type(line) == "string" then lines[#lines + 1] = line end
        end
        if #lines > 0 then
            table.sort(lines)
            record.unknown = lines
        end
    end
    data.items[row.ks] = record

    data.count = data.count + 1
    if record.suffix ~= 0 then data.suffixed = data.suffixed + 1 end
    if HasKey(game, "RATING") or HasKey(pawn, "Rating$") then data.ratings = data.ratings + 1 end
    if HasKey(game, "HEALING") or HasKey(pawn, "^Healing$") then data.healing = data.healing + 1 end
    if not pawn then data.noPawn = data.noPawn + 1 end
    if not game or next(game) == nil then data.noGame = data.noGame + 1 end
    return true
end

local function Say()
    said = true
    data.finished = time()
    ns.Print(T.DONE:format(data.count, data.suffixed, data.ratings, data.healing, data.noPawn, data.noGame, data.unread))
    local missing = {}
    if data.suffixed == 0 then missing[#missing + 1] = T.SUFFIX end
    if data.ratings == 0 then missing[#missing + 1] = T.RATINGS end
    if data.healing == 0 then missing[#missing + 1] = T.HEALING end
    if #missing > 0 then ns.Print(T.MISSING:format(table.concat(missing, ", "))) end
    if data.full then ns.Print(T.FULL:format(LIMIT)) end
    ns.Print(T.SAVE)
end

local Schedule

local function Step()
    stepping = false
    if not on then return end
    local now = GetTime()
    local started = debugprofilestop()
    while head <= #queue do
        local row = queue[head]
        if row.after and row.after > now then break end
        head = head + 1
        row.first = row.first or now
        if Read(row) then
            lastRead = now
        elseif now - row.first > PATIENCE and now - lastRead > PATIENCE then
            -- The client loads items a few at a time: a row is given up on only when it
            -- has waited long and no other row has come through meanwhile either.
            data.unread = data.unread + 1
        else
            row.after = now + RETRY
            queue[#queue + 1] = row
        end
        lastWork = now
        if debugprofilestop() - started > BUDGET_MS then break end
    end
    if head > #queue then
        queue, head = {}, 1
        -- Rows come while the scan reads the auction list, and at no other time.
        if not said and now - lastWork >= QUIET and ns.Scanner.state ~= "browse" then Say() end
    end
    Schedule()
end

function Schedule()
    if on and not stepping and (head <= #queue or not said) then
        stepping = true
        C_Timer.After(STEP, Step)
    end
end

---------------------------------------------------------------------------
-- For the scanner and the slash command
---------------------------------------------------------------------------
function Check.Active()
    return on
end

-- A row of a scan for gear, as the auction house lists it.
function Check.Row(key)
    if not on then return end
    local ks = ns.KeyString(key)
    if known[ks] then return end
    known[ks] = true
    data.seen = data.seen + 1
    if data.seen > LIMIT then
        data.full = true
        return
    end
    queue[#queue + 1] = { key = key, ks = ks, tries = 0 }
    said = false
    Schedule()
end

-- /upscout check
function Check.Start()
    if type(PawnGetItemData) ~= "function" then
        ns.Print(T.NO_PAWN)
        return
    end
    local me = ns.Roster.Me()
    local version, build = GetBuildInfo()
    data = {
        at = time(), locale = GetLocale(), client = version, build = build,
        class = me and me.class, level = me and me.level,
        seen = 0,           -- rows of the auction list taken
        count = 0,          -- items written down
        suffixed = 0, ratings = 0, healing = 0,     -- of them: with a suffix, with a rating, with healing
        noPawn = 0, noGame = 0,                     -- of them: Pawn gave nothing, the game gave nothing
        unread = 0,         -- rows the client never loaded
        items = {},         -- key string -> { link, name, suffix, game, pawn, unknown }
        worn = {},          -- inventory slot -> { link, game, bare, pawn, pawnBare }
    }
    ns.account.check = data
    on = true
    queue, head, known = {}, 1, {}
    said = true
    lastRead = GetTime()

    -- What the character wears, read four ways: as it is and without its enchantment, by the
    -- game and by Pawn. Gear is scored without enchantments, so that an enchanted piece is
    -- not unfairly hard to beat; this shows whether the game's numbers allow the same.
    for slot = 1, ns.Roster.LAST_SLOT do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local item = PawnGetItemData(link)
            data.worn[slot] = {
                link = link:match("item:[%-%d:]+") or link,
                game = ns.Stats.Read(link) or false,
                bare = ns.Stats.Read(ns.Stats.Bare(link)) or false,
                pawn = item and Numbers(item.Stats) or false,
                pawnBare = item and Numbers(item.UnenchantedStats) or false,
            }
        end
    end

    local S = ns.Scanner
    if S.IsOpen() and S.state == "idle" and S.Start() then
        ns.Print(T.STARTED)
    else
        ns.Print(T.ON)
    end
end

-- /upscout check off
function Check.Stop()
    on = false
    queue, head = {}, 1
    ns.Print(T.OFF)
end

-- What Pawn read for an item, as one line for /upscout stats; nil when Pawn cannot be asked.
function Check.PawnLine(link)
    if type(PawnGetItemData) ~= "function" then return nil end
    local item = PawnGetItemData(link)
    local stats = item and Numbers(item.UnenchantedStats or item.Stats)
    if not stats then return T.PAWN_NONE end
    local parts = {}
    for name, amount in pairs(stats) do parts[#parts + 1] = name .. " " .. ns.Num(amount) end
    table.sort(parts)
    return T.PAWN:format(table.concat(parts, ", "))
end

-- Without the auction house there are no rows to read: what is left is let go.
ns.On("AUCTION_HOUSE_CLOSED", function()
    if not on or said then return end
    local left = #queue - head + 1
    queue, head = {}, 1
    if left > 0 then ns.Print(T.CLOSED:format(left)) end
    Say()
end)
