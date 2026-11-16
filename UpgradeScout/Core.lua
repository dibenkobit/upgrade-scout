local ADDON, ns = ...

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns.On(event, fn)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    list[#list + 1] = fn
end

-- Each handler is called on its own (securecallfunction): an error in one is reported the
-- usual way, and the handlers after it still hear the event.
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    for i = 1, #list do
        securecallfunction(list[i], ...)
    end
end)

---------------------------------------------------------------------------
-- Messages between this addon's own files
---------------------------------------------------------------------------
local listeners = {}

function ns.Listen(message, fn)
    local list = listeners[message]
    if not list then
        list = {}
        listeners[message] = list
    end
    list[#list + 1] = fn
end

function ns.Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        securecallfunction(list[i], ...)
    end
end

---------------------------------------------------------------------------
-- Once for many reasons
---------------------------------------------------------------------------
-- Gear, bags and skills change in bursts, and the game says so many times over. This makes
-- a function that runs `fn` once, `delay` seconds after the first of however many calls.
function ns.Soon(delay, fn)
    local queued = false
    return function()
        if queued then return end
        queued = true
        C_Timer.After(delay, function()
            queued = false
            fn()
        end)
    end
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
-- Per character. collapsed: slot id -> true for the slots the player folded away in the list.
-- Off until ticked, and so not listed here: plan (the best set for a budget, see Plan.lua) and
-- net (gear priced at its net cost, see Results.Cost).
ns.db = { affordableOnly = true, topOnly = true, bestOnly = true, collapsed = {} }
-- For the whole account. chars: the characters of the account as each was last seen, by
-- name (see Roster.lua). On until switched off in the welcome window (Welcome.lua), and so
-- written down only as false: where the score shows in an item's tooltip, which is tooltip
-- (anywhere in the game but our own tabs: the bags, loot, the chat) and rowTooltip (the rows
-- of our tabs at the auction house); rowNotes (the notes in the tooltip of such a row: what
-- the player is short of and the like, see AddNotes in UI.lua); and arrows (the arrow on an
-- upgrade in the bags). Off
-- until chosen there, and so written down only as true: ownTree (see ns.OwnTree). welcomed:
-- that window has been seen. minimap: where the button at the minimap is (Minimap.lua).
ns.account = { chars = {} }
-- Also for the whole account, and chosen in the same window: engine, "pawn" when gear is to
-- be scored by the player's Pawn scales and not by the addon's own weights, "companion"
-- when by Forever Companion's gear scales (Score.Engine). pawnOffered, companionOffered:
-- the window has been seen since that choice could be made in it, with that addon there.

-- Is this part of the addon on: "tooltip", "rowTooltip", "rowNotes" or "arrows"?
function ns.Shows(part)
    return ns.account[part] ~= false
end

-- How our lines in a tooltip are written, wherever they show: true for one line, for the
-- profile in use (Tooltip.AddOwn), and not a line for every profile of the class.
function ns.OwnTree()
    return ns.account.ownTree == true
end

EventUtil.ContinueOnAddOnLoaded(ADDON, function()
    if type(UpgradeScoutCharDB) ~= "table" then UpgradeScoutCharDB = {} end
    local db = UpgradeScoutCharDB
    if db.affordableOnly == nil then db.affordableOnly = true end
    if db.topOnly == nil then db.topOnly = true end
    if db.bestOnly == nil then db.bestOnly = true end
    if type(db.collapsed) ~= "table" then db.collapsed = {} end
    ns.db = db

    if type(UpgradeScoutDB) ~= "table" then UpgradeScoutDB = {} end
    if type(UpgradeScoutDB.chars) ~= "table" then UpgradeScoutDB.chars = {} end
    -- What the in-game check of the stats wrote while 2.0 was made (tag pre-2.0-check): a few
    -- megabytes the game would otherwise read at every login. (Take this out with the check, if
    -- it is ever brought back.)
    UpgradeScoutDB.check = nil
    -- For an hour while 2.6.0 was made, the two filters about gear (Wants.lua) were the
    -- account's and not each character's: bestArmor, minGain and minGainOn here, with what
    -- the cards had held moved over and wiped. No release had them so. What such a build left
    -- ticked goes back onto the cards, onto every one: whose it had been is not known any more.
    local account = UpgradeScoutDB
    if account.bestArmor ~= nil or account.minGain ~= nil or account.minGainOn ~= nil then
        for _, card in pairs(account.chars) do
            if type(card) == "table" then
                if account.bestArmor == true then card.armorOnly = true end
                if card.minGain == nil and type(account.minGain) == "number" then card.minGain = account.minGain end
                if account.minGainOn == true then card.minGainOn = true end
            end
        end
        account.bestArmor, account.minGain, account.minGainOn = nil, nil, nil
    end
    ns.account = UpgradeScoutDB
end)

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
-- An amount of money as the game writes it in text: coin icons (letters in colourblind mode),
-- thousands of gold separated, zero parts left out.
function ns.Money(copper)
    return GetMoneyString(copper or 0, MoneyStringConstants.SeparateThousands)
end

-- Decimals that keep about two digits of a number: 12.4, 4.7, 0.55, 0.048. With one decimal
-- everywhere a +0.048 upgrade reads as "+0".
function ns.Decimals(value)
    value = math.abs(value)
    if value >= 1 or value == 0 then return 1 end
    if value >= 0.1 then return 2 end
    return 3
end

-- A score as text, without trailing zeros: 12.4, 7, 0.55. Pass `decimals` to show several
-- numbers to the same precision.
function ns.Num(value, decimals)
    local text = string.format("%." .. (decimals or ns.Decimals(value)) .. "f", value)
    text = text:gsub("0+$", "")
    return (text:gsub("%.$", ""))
end

function ns.Print(message)
    print("|cff33ff99Upgrade Scout|r: " .. tostring(message))
end

-- Times use the game's own short units (SECONDS_ABBR and so on), so they read right in every
-- language the game has.
-- "5 Min", "2 Hr", "3 Days"
function ns.Ago(seconds)
    if seconds < 90 then return SECONDS_ABBR:format(math.max(1, math.floor(seconds))) end
    if seconds < 5400 then return MINUTES_ABBR:format(math.floor(seconds / 60 + 0.5)) end
    -- Days only for what was a day and a half ago or more: a character last played.
    if seconds < 129600 then return HOURS_ABBR:format(math.floor(seconds / 3600 + 0.5)) end
    return DAYS_ABBR:format(math.floor(seconds / 86400 + 0.5))
end

-- A wait as one would say it: "15 Sec" (to the nearest five), "7 Min".
function ns.Duration(seconds)
    if seconds < 90 then
        return SECONDS_ABBR:format(math.max(5, math.floor(seconds / 5 + 0.5) * 5))
    end
    return MINUTES_ABBR:format(math.floor(seconds / 60 + 0.5))
end

-- An item name in the colour of its quality (the player's own colours, if they changed them).
function ns.QualityText(name, quality)
    local data = ColorManager.GetColorDataForItemQuality(quality)
    return data and data.color:WrapTextInColorCode(name) or name
end

-- The same colour as three numbers, white for a quality the game has no colour for.
function ns.QualityColor(quality)
    local data = ColorManager.GetColorDataForItemQuality(quality)
    if data then return data.color:GetRGB() end
    return 1, 1, 1
end

-- Capitals, for headings: A to Z and the two-byte letters of UTF-8, accented Latin and
-- Cyrillic, which covers every language the addon has (Chinese has no capitals). Letters are
-- picked out byte by byte: string.upper on a whole text goes by the computer's own alphabet
-- and can break the bytes of another. Not for text with colour codes or format placeholders.
function ns.Upper(text)
    return (text:gsub("[a-z]", string.upper):gsub("[\195\208\209][\128-\191]", function(pair)
        local lead, tail = pair:byte(1, 2)
        if lead == 195 then
            -- U+00E0 to U+00FE, "à" to "þ", but for the division sign U+00F7
            if tail >= 160 and tail <= 190 and tail ~= 183 then return string.char(195, tail - 32) end
        elseif lead == 208 then
            -- U+0430 to U+043F, "а" to "п"
            if tail >= 176 then return string.char(208, tail - 32) end
        elseif tail <= 143 then
            -- U+0440 to U+044F, "р" to "я"
            return string.char(208, tail + 32)
        elseif tail == 145 then
            -- U+0451, "ё"
            return string.char(208, 129)
        end
    end))
end

---------------------------------------------------------------------------
-- What the character being played falls short of
---------------------------------------------------------------------------
-- The game colours a tooltip line red when the player does not meet it: level, class, armor
-- or weapon skill not learned, and so on. That is the most direct answer to "can I equip
-- this right now". The lines are read as data (C_TooltipInfo), the same data the game builds
-- its tooltips from, so no tooltip frame is involved.
local function IsRed(text, color)
    if not text or text == "" or not color then return false end
    local r, g, b = color:GetRGB()
    return r > 0.9 and g < 0.2 and b < 0.2
end

-- Is this line of a tooltip red, on the left or on the right?
function ns.IsRedLine(line)
    return IsRed(line.leftText, line.leftColor) or IsRed(line.rightText, line.rightColor)
end

-- Is anything in these lines (after the name) red?
function ns.AnyRed(lines)
    for i = 2, #lines do
        if ns.IsRedLine(lines[i]) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Telling items apart
---------------------------------------------------------------------------
-- An item by what the player sees of it: its number and its name, "of the Tiger" and all.
-- On Forever a link does not carry the variant in a field of its own that could be read (the
-- seventh, where the first game had the suffix, is empty; a bonus ID names it), and its other
-- fields (the level of the one looking, for one) change without the item changing.
-- nil for what is not an item link.
function ns.ItemKey(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    if not id then return nil end
    return id .. ":" .. (link:match("%[(.-)%]") or "")
end

-- An auction item key as one string, to index tables with. A row of the auction house is one
-- item, variant and all: "of the Tiger" and "of the Whale" have rows of their own, told apart
-- by the key's itemSuffix.
function ns.KeyString(key)
    return (key.itemID or 0) .. ":" .. (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0)
end

function ns.SameKey(a, b)
    return a and b and a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
        and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end
