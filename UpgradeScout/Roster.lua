local _, ns = ...

-- The characters of this account, as the addon last saw each of them.
--
-- The game tells an addon about the character being played and about nobody else: what
-- another character of the account wears, its level, the weapons it has learned are out of
-- reach while it is not the one logged in. So every character is written down while it is
-- played (a "card", kept for the whole account in UpgradeScoutDB), and the lists can then be
-- made for any of them: see R.Target.
--
-- A card:
--   key         the name Pawn files the character under ("Name Surname" in Forever)
--   name, last  its first name, which the tab shows, and its surname where the game has them
--   realm, faction, class ("WARRIOR"), className and race (as the game writes them), level
--   mana        it has mana
--   dualWield   it can hold a weapon in the off hand
--   gear        { [inventory slot] = item link } for slots 1 to 18
--   weapons     { [weapon subclass] = true } for the kinds it has learned; nil when the game
--   armor       { [armor subclass] = true }   would not say (or said too little to be
--               believed: see R.Update), and then its class decides
--   skills      { [profession, as the game names it] = rank }; nil when the game would not say
--   scale       the Pawn scale chosen for it
--   seen        when it was last written down (time())
local R = {}
ns.Roster = R

local WEAPON_CLASS = Enum.ItemClass.Weapon
local ARMOR_CLASS = Enum.ItemClass.Armor
local MANA = Enum.PowerType and Enum.PowerType.Mana or 0
local LAST_SLOT = 18            -- the ranged slot; the shirt and the tabard are not gear

---------------------------------------------------------------------------
-- Weapon and armor skills
---------------------------------------------------------------------------
local function Set(names)
    local set = {}
    for name in names:gmatch("%u+") do set[name] = true end
    return set
end

-- In Forever a weapon skill is learned, as it was in the first game: a mage starts with
-- staves and wands and may go to a trainer for swords. To the client a learned skill is a
-- spell the character knows. Below, for every kind of weapon and armor (item subclass): that
-- spell, and the classes that can ever have it. Both come from the game's own tables
-- (SkillLineAbility: Spell and ClassMask) for build 1.60.1.70938.
local EVERYONE = Set("WARRIOR PALADIN HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID")
local WEAPONS = {
    [0] = { spell = 196, classes = Set("WARRIOR PALADIN HUNTER ROGUE SHAMAN") },                        -- one-handed axes
    [1] = { spell = 197, classes = Set("WARRIOR PALADIN HUNTER SHAMAN") },                              -- two-handed axes
    [2] = { spell = 264, classes = Set("WARRIOR HUNTER ROGUE") },                                       -- bows
    [3] = { spell = 266, classes = Set("WARRIOR HUNTER ROGUE") },                                       -- guns
    [4] = { spell = 198, classes = Set("WARRIOR PALADIN ROGUE PRIEST SHAMAN DRUID") },                  -- one-handed maces
    [5] = { spell = 199, classes = Set("WARRIOR PALADIN SHAMAN DRUID") },                               -- two-handed maces
    [6] = { spell = 200, classes = Set("WARRIOR PALADIN HUNTER DRUID") },                               -- polearms
    [7] = { spell = 201, classes = Set("WARRIOR PALADIN HUNTER ROGUE MAGE WARLOCK") },                  -- one-handed swords
    [8] = { spell = 202, classes = Set("WARRIOR PALADIN HUNTER") },                                     -- two-handed swords
    [10] = { spell = 227, classes = Set("WARRIOR HUNTER PRIEST SHAMAN MAGE WARLOCK DRUID") },           -- staves
    [13] = { spell = 15590, classes = Set("WARRIOR HUNTER ROGUE SHAMAN DRUID") },                       -- fist weapons
    [15] = { spell = 1180, classes = Set("WARRIOR HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID") },    -- daggers
    [16] = { spell = 2567, classes = Set("WARRIOR HUNTER ROGUE") },                                     -- thrown
    [18] = { spell = 5011, classes = Set("WARRIOR HUNTER ROGUE") },                                     -- crossbows
    [19] = { spell = 5009, classes = Set("PRIEST MAGE WARLOCK") },                                      -- wands
}
-- `late`: the classes that get the skill at level 40 and not at the start.
local ARMOR = {
    [1] = { spell = 9078, classes = EVERYONE },                                                         -- cloth
    [2] = { spell = 9077, classes = Set("WARRIOR PALADIN HUNTER ROGUE SHAMAN DRUID") },                 -- leather
    [3] = { spell = 8737, classes = Set("WARRIOR PALADIN HUNTER SHAMAN"), late = Set("HUNTER SHAMAN") },-- mail
    [4] = { spell = 750, classes = Set("WARRIOR PALADIN"), late = Set("WARRIOR PALADIN") },             -- plate
    [6] = { spell = 9116, classes = Set("WARRIOR PALADIN SHAMAN") },                                    -- shields
}
local LATE_LEVEL = 40
-- Librams, idols and totems go by class alone.
local RELICS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }

-- The number the game and Pawn know each class by.
local CLASS_ID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
    MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}

function R.ClassID(card)
    return CLASS_ID[card.class]
end

-- Does the character being played know this spell? The client has had more than one
-- function for the question; a yes from any of them is a yes.
local function Knows(spell)
    local ask = { IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }
    for i = 1, 3 do
        if type(ask[i]) == "function" then
            local ok, known = pcall(ask[i], spell)
            -- In a fight the game may keep an answer to itself ("secret"); that is no answer.
            if ok and not (issecretvalue and issecretvalue(known)) and known == true then return true end
        end
    end
    return false
end

-- The kinds of `kinds` the character being played has learned; nil when it seems to have
-- learned none, which is the game not answering rather than the truth.
local function Learned(kinds)
    local out, any = {}, false
    for sub, kind in pairs(kinds) do
        if Knows(kind.spell) then
            out[sub] = true
            any = true
        end
    end
    return any and out or nil
end

-- Can the character of this card put on an item of this class and subclass?
-- What the character had learned when it was last played decides. A card without that
-- (the client would not say) goes by what its class can ever learn, which is a little too
-- generous: it takes a mage who never went for swords to have them.
function R.Wields(card, classID, subClassID)
    local kind, learned
    if classID == WEAPON_CLASS then
        kind, learned = WEAPONS[subClassID], card.weapons
    elseif classID == ARMOR_CLASS then
        local relic = RELICS[subClassID]
        if relic then return relic == card.class end
        kind, learned = ARMOR[subClassID], card.armor
    end
    -- Nothing to learn: a ring, a trinket, something held in the off hand, a fishing pole.
    if not kind then return true end
    if type(learned) == "table" then return learned[subClassID] == true end
    if not kind.classes[card.class or ""] then return false end
    if kind.late and kind.late[card.class] then return (card.level or 0) >= LATE_LEVEL end
    return true
end

---------------------------------------------------------------------------
-- What an item asks of its owner
---------------------------------------------------------------------------
-- A text of the game with places for values ("Requires %s (%d)") as a Lua pattern that finds
-- those values in a line written from it. Some languages number the places ("%2$s %1$d");
-- `order` says which value each capture is.
local function Pattern(text)
    if type(text) ~= "string" or text == "" then return nil end
    local parts, order = { "^" }, {}
    local at = 1
    while true do
        local from, to, index, kind = text:find("%%(%d*)%$?([sd])", at)
        if not from then break end
        parts[#parts + 1] = (text:sub(at, from - 1):gsub("%p", "%%%0"))
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.+)"
        order[#order + 1] = tonumber(index) or (#order + 1)
        at = to + 1
    end
    parts[#parts + 1] = (text:sub(at):gsub("%p", "%%%0"))
    parts[#parts + 1] = "$"
    return { pattern = table.concat(parts), order = order }
end

-- The (at most two) values of a line written from the text `compiled` was made of, in the
-- order the text names them; nil when the line was not written from it.
local function Match(compiled, line)
    if not compiled then return nil end
    local first, second = line:match(compiled.pattern)
    if first == nil then return nil end
    if compiled.order[1] == 2 then return second, first end
    return first, second
end

local CLASSES = Pattern(ITEM_CLASSES_ALLOWED)       -- "Classes: %s"
local RACES = Pattern(ITEM_RACES_ALLOWED)           -- "Races: %s"
local SKILL = Pattern(ITEM_MIN_SKILL)               -- "Requires %s (%d)"
local REPUTATION = Pattern(ITEM_REQ_REPUTATION)     -- "Requires %s - %s"

-- Kinds of tooltip line that ask for something a card says nothing about: standing with a
-- faction, a rank, a spell.
local UNKNOWABLE
do
    local kinds = Enum.TooltipDataLineType
    if type(kinds) == "table" then
        UNKNOWABLE = {}
        for _, name in ipairs({ "RestrictedReputation", "RestrictedPvPMedal", "RestrictedSpellKnown",
            "RestrictedArena", "RestrictedBg" }) do
            if kinds[name] ~= nil then UNKNOWABLE[kinds[name]] = true end
        end
    end
end

-- Is the character's class in a list like "Warrior, Paladin"? The list has the class as the
-- game names it, and some languages name a class one way for men and another for women.
local function ClassListed(card, list)
    local names = {
        card.className,
        type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[card.class] or nil,
        type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" and LOCALIZED_CLASS_NAMES_FEMALE[card.class] or nil,
    }
    for i = 1, 3 do
        local name = names[i]
        if type(name) == "string" and name ~= "" and list:find(name, 1, true) then return true end
    end
    return false
end

-- Would the game let the character of this card use an item whose tooltip has these lines
-- (C_TooltipInfo's)? For the character being played the game answers itself, by writing in
-- red what the character falls short of; for another one the lines are read here: the
-- classes and races an item is for, and the profession it asks for. An item that asks for
-- what a card cannot tell (standing with a faction) is taken to be out of reach.
-- The item's level and its kind of weapon or armor are not judged here: see R.Wields.
function R.Allows(card, lines)
    for i = 2, #lines do
        local line = lines[i]
        if UNKNOWABLE and line.type ~= nil and UNKNOWABLE[line.type] then return false end
        local text = line.leftText
        if type(text) == "string" and text ~= "" then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
            local classes = Match(CLASSES, text)
            local races = not classes and Match(RACES, text) or nil
            if classes then
                if not ClassListed(card, classes) then return false end
            elseif races then
                if type(card.race) == "string" and not races:find(card.race, 1, true) then return false end
            else
                local skill, rank = Match(SKILL, text)
                if skill then
                    local have = type(card.skills) == "table" and card.skills[skill] or nil
                    if type(have) ~= "number" or have < (tonumber(rank) or 0) then return false end
                elseif Match(REPUTATION, text) then
                    return false
                end
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- The card of the character being played
---------------------------------------------------------------------------
local myKey, myName, myLast
local levelUp               -- the level PLAYER_LEVEL_UP named; UnitLevel may be a moment behind

local function Identity()
    local first, last = UnitName("player")
    if type(first) ~= "string" or first == "" then return nil end
    -- Pawn's own name for the character where Pawn has settled on one, and the same rule
    -- where it has not yet: Forever gives a character a surname, other clients a realm.
    local key = type(PawnPlayerFullName) == "string" and PawnPlayerFullName ~= "" and PawnPlayerFullName or nil
    if not key then
        key = last and (first .. " " .. last) or (first .. "-" .. (GetRealmName() or ""))
    end
    return key, first, last
end

-- The facts that take nothing to read.
local function Describe(card)
    local className, class = UnitClass("player")
    card.name, card.last = myName, myLast
    card.class = class or card.class
    card.className = className
    card.race = UnitRace("player")
    card.realm = GetRealmName()
    card.faction = UnitFactionGroup("player")
    local level = UnitLevel("player") or 0
    if levelUp and levelUp > level then level = levelUp end
    if level > 0 then card.level = level end
    card.mana = (UnitPowerMax("player", MANA) or 0) > 0
    card.dualWield = CanDualWield() and true or false
end

-- The card of the character being played, made on the first call. nil only if the game does
-- not know the character's name yet.
function R.Me()
    if not myKey then
        myKey, myName, myLast = Identity()
        if not myKey then return nil end
    end
    local chars = ns.account.chars
    local card = chars[myKey]
    if type(card) ~= "table" then
        card = { key = myKey }
        chars[myKey] = card
    end
    card.key = myKey
    if not card.class or not card.level then Describe(card) end
    -- The scale used to be kept with the character's own settings; now a character's scale
    -- can be chosen while another one is played, so it is on the card.
    if ns.db.scale ~= nil then
        if card.scale == nil then card.scale = ns.db.scale end
        ns.db.scale = nil
    end
    return card
end

-- The character's professions and how far each has got, by the names the game shows: an
-- item that asks for one ("Requires First Aid (225)") names it the same way. nil when this
-- client has neither of the two ways of asking.
local function Skills()
    local out, asked = {}, false
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local found = { pcall(GetProfessions) }
        if found[1] then
            asked = true
            for i = 2, 7 do
                local index = found[i]
                if index then
                    local ok, name, _, rank = pcall(GetProfessionInfo, index)
                    if ok and type(name) == "string" and type(rank) == "number" then out[name] = rank end
                end
            end
        end
    end
    if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local ok, count = pcall(GetNumSkillLines)
        if ok and type(count) == "number" then
            asked = true
            for i = 1, count do
                local got, name, header, _, rank = pcall(GetSkillLineInfo, i)
                if got and not header and type(name) == "string" and type(rank) == "number" then
                    out[name] = math.max(out[name] or 0, rank)
                end
            end
        end
    end
    return asked and out or nil
end

-- Writes the character being played down as it is now.
--   gearChanged  the game has just said that the gear changed
function R.Update(gearChanged)
    local card = R.Me()
    if not card then return end
    Describe(card)

    local gear, any = {}, false
    for slot = 1, LAST_SLOT do
        local link = GetInventoryItemLink("player", slot)
        if link then
            gear[slot] = link
            any = true
        end
    end
    -- Right after logging in the game may not have the links yet. Nothing at all worn is
    -- believed only when the gear has just changed, or when nothing was known before.
    if any or gearChanged or type(card.gear) ~= "table" then card.gear = gear end

    -- What was read before stays when the game does not answer this time.
    local weapons = Learned(WEAPONS)
    if weapons then card.weapons = weapons end
    -- Which armor a class starts with is known, so an answer about armor can be checked: one
    -- that lacks any of it (cloth, say, which everyone wears) is the game answering in part,
    -- and is not believed. Which weapons a character starts with depends on its race too,
    -- and there is nothing to check an answer about them against.
    local armor = Learned(ARMOR)
    local whole = armor ~= nil
    for sub, kind in pairs(ARMOR) do
        local fromStart = kind.classes[card.class or ""] and not (kind.late and kind.late[card.class])
        if whole and fromStart and not armor[sub] then whole = false end
    end
    if whole then card.armor = armor end
    local skills = Skills()
    if skills then card.skills = skills end

    card.seen = time()
end

---------------------------------------------------------------------------
-- The cards of the account
---------------------------------------------------------------------------
-- A card read from the saved file is used only if it holds what the lists need.
local function Sound(key, card)
    return type(card) == "table" and card.key == key and type(card.name) == "string" and card.name ~= ""
        and CLASS_ID[card.class] ~= nil and type(card.level) == "number"
end

-- Every character there is a card for: the one being played first, then the others, those
-- of this realm before the rest, by name.
function R.List()
    local me = R.Me()
    local out, others = {}, {}
    if me then out[1] = me end
    for key, card in pairs(ns.account.chars) do
        if card ~= me and Sound(key, card) then others[#others + 1] = card end
    end
    local realm = me and me.realm
    table.sort(others, function(a, b)
        local aHere, bHere = a.realm == realm, b.realm == realm
        if aHere ~= bHere then return aHere end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    for i = 1, #others do out[#out + 1] = others[i] end
    return out
end

function R.Get(key)
    local card = key ~= nil and ns.account.chars[key] or nil
    if card and (key == myKey or Sound(key, card)) then return card end
    return nil
end

-- The character the lists are for, when it is not the one being played: its card. nil for
-- the character being played, whom the game is asked about directly.
-- The choice lasts until the interface is loaded again: a list for someone else must be asked
-- for, not come up by itself a week later.
local target
function R.Target()
    if not target then return nil end
    local card = target ~= myKey and R.Get(target) or nil
    if not card then target = nil end
    return card
end

-- card: one of R.List(); nil or the card of the character being played for that character.
function R.SetTarget(card)
    target = card and card ~= R.Me() and card.key or nil
end

-- Takes a character other than the one being played out of the account's cards, by its
-- name as the tab shows it or in full. Returns the card, or nil if there is none.
function R.Forget(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    local me = R.Me()
    for key, card in pairs(ns.account.chars) do
        if card ~= me and type(card) == "table" and (key == name or card.name == name) then
            ns.account.chars[key] = nil
            if target == key then target = nil end
            return card
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- How a card is shown
---------------------------------------------------------------------------
-- A text in the colour of the card's class.
function R.Colored(card, text)
    local color = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[card.class] or nil
    if type(color) == "table" then
        if color.WrapTextInColorCode then return color:WrapTextInColorCode(text) end
        if type(color.colorStr) == "string" then return "|c" .. color.colorStr .. text .. "|r" end
    end
    return text
end

-- A scale's title without the class it begins with ("Druid: Balance"): beside the
-- character's name, written in the colour of its class, the class is said twice.
function R.Short(card, title)
    local names = {
        type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[card.class] or nil,
        type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" and LOCALIZED_CLASS_NAMES_FEMALE[card.class] or nil,
        card.className,
    }
    for i = 1, 3 do
        local name = names[i]
        if type(name) == "string" and name ~= "" then
            local prefix = name .. ": "
            if #title > #prefix and title:sub(1, #prefix) == prefix then return title:sub(#prefix + 1) end
        end
    end
    return title
end

---------------------------------------------------------------------------
-- Keeping the card of the character being played up to date
---------------------------------------------------------------------------
-- Gear, level and skills change in bursts (a set of gear put on, a visit to a trainer), and
-- the game says so many times over: the card is written once, a moment later.
local queued, gearNews = false, false
local function Queue(gearChanged)
    gearNews = gearNews or gearChanged or false
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        local news = gearNews
        queued, gearNews = false, false
        R.Update(news)
    end)
end

-- A client that does not have an event refuses to listen for it; the others still come.
local function On(event, fn)
    pcall(ns.On, event, fn)
end

On("PLAYER_ENTERING_WORLD", function() Queue(false) end)
On("PLAYER_EQUIPMENT_CHANGED", function() Queue(true) end)
On("PLAYER_LEVEL_UP", function(level)
    if type(level) == "number" then levelUp = level end
    Queue(false)
end)
On("SPELLS_CHANGED", function() Queue(false) end)
On("SKILL_LINES_CHANGED", function() Queue(false) end)
On("AUCTION_HOUSE_SHOW", function() Queue(false) end)
-- The last word on the character before another one is played. No timer outlives a logout.
On("PLAYER_LOGOUT", function() R.Update(gearNews) end)
