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

-- /upscout stats <item>: says in the chat how an item comes by its score: each stat the
-- game counts for it, the weight the profile in use gives that stat, and what the two come
-- to. `text` is what the player put after the command: a link (an item shift-clicked into
-- the chat line) or the item's number. The profile and the level are those of the character
-- the lists are for.
function Stats.Report(text)
    local item = text:match("item:[%-%d:]+")
    local id = tonumber(item and item:match("^item:(%d+)") or text:match("^(%d+)$"))
    if not id then
        ns.Print(L.ITEM_STATS_HELP)
        return
    end
    item = item or ("item:" .. id)

    local name, link = C_Item.GetItemInfo(item)
    local scored = name and ns.Score.Item(link or item) or nil
    if not scored then
        -- The game answers for an item only once it has loaded it; asking makes it load.
        C_Item.RequestLoadItemDataByID(id)
        ns.Print(L.ITEM_STATS_WAIT)
        return
    end

    local who = ns.Roster.Target()
    local profile = ns.Score.Current(who)
    local parts, total = ns.Score.Parts(scored, profile and profile.name, who and who.level or UnitLevel("player"))
    if #parts == 0 then
        ns.Print(L.ITEM_STATS_NONE:format(link or name))
    else
        ns.Print(L.ITEM_STATS:format(link or name, profile and profile.title or NONE, ns.Num(total)))
        for i = 1, #parts do
            local part = parts[i]
            -- (With Pawn scoring a stat goes by Pawn's name for it, which is its label.)
            local line = (part.label or Stats.Label(part.name)) .. ": " .. ns.Num(part.amount) .. " × " .. ns.Num(part.weight)
            if part.weight ~= 0 then line = line .. " = " .. ns.Num(part.points) end
            print("   " .. line)
        end
    end
end
