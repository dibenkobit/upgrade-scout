local _, ns = ...
local L = ns.L

-- What an item adds, as the game itself counts it.
--
-- The game keeps the stats of an item as numbers of their own, apart from the words of its
-- tooltip, and C_Item.GetItemStats hands them over under names that are the same in every
-- language: "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_CRIT_RATING_SHORT". Each of those names is
-- also the name of the game's own word for the stat (the global ITEM_MOD_STRENGTH_SHORT is
-- "Strength"), which is how a stat is shown to the player here. A variant of an item ("of the
-- Tiger") is told by its link, so the stats are asked for by link and not by item number.
local Stats = {}
ns.Stats = Stats

-- { [the game's name for a stat] = amount }: an empty table for an item that adds nothing,
-- nil when the game has no answer (it has not loaded the item, or this is not an item).
function Stats.Read(link)
    if type(link) ~= "string" then return nil end
    local got = C_Item.GetItemStats(link)
    if type(got) ~= "table" then return nil end
    local out = {}
    for name, amount in pairs(got) do
        if type(name) == "string" and type(amount) == "number" then out[name] = amount end
    end
    return out
end

-- The same link without the item's enchantment, which is the second field of a link
-- ("item:6551:66:..."): the item as it would be for sale.
function Stats.Bare(link)
    return (link:gsub("(item:%d+):%-?%d*", "%1:", 1))
end

-- The game's word for a stat, in the player's language; the name itself where it has none.
function Stats.Label(name)
    local text = _G[name]
    if type(text) == "string" and text ~= "" then return text end
    return name
end

-- "Armor: 120", "Strength: 5", by the alphabet of their words.
function Stats.Lines(stats)
    local lines = {}
    for name, amount in pairs(stats) do
        lines[#lines + 1] = Stats.Label(name) .. ": " .. ns.Num(amount)
    end
    table.sort(lines)
    return lines
end

-- /upscout stats <item>: says in the chat what the game counts for an item. `text` is what
-- the player put after the command: a link (an item shift-clicked into the chat line) or the
-- item's number.
function Stats.Report(text)
    local item = text:match("item:[%-%d:]+")
    local id = tonumber(item and item:match("^item:(%d+)") or text:match("^(%d+)$"))
    if not id then
        ns.Print(L.ITEM_STATS_HELP)
        return
    end
    item = item or ("item:" .. id)

    local name, link = C_Item.GetItemInfo(item)
    local stats = name and Stats.Read(link or item) or nil
    if not stats then
        -- The game answers for an item only once it has loaded it; asking makes it load.
        C_Item.RequestLoadItemDataByID(id)
        ns.Print(L.ITEM_STATS_WAIT)
        return
    end

    local lines = Stats.Lines(stats)
    if #lines == 0 then
        ns.Print(L.ITEM_STATS_NONE:format(link or name))
    else
        ns.Print(L.ITEM_STATS:format(link or name))
        for i = 1, #lines do print("   " .. lines[i]) end
    end
    -- While Pawn still scores the gear: what Pawn read for the same item (see Check.lua).
    local pawn = ns.Check.PawnLine(link or item)
    if pawn then print("   " .. pawn) end
end
