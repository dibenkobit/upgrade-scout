local _, ns = ...

-- The characters of this account, as the addon last saw each of them.
--
-- The game tells an addon about the character being played and about nobody else: what
-- another character of the account wears, its level, the weapons it has learned are out of
-- reach while it is not the one logged in. So every character is written down while it is
-- played (a "card", kept for the whole account in UpgradeScoutDB), and the lists can then be
-- made for any of them: see Roster.Target.
--
-- A card:
--   key         what the character is filed under: "Name Surname" in Forever
--   name, last  its first name, which the tab shows, and its surname where the game has them
--   realm, faction, class ("WARRIOR"), className and race (as the game writes them), level
--   mana        it has mana
--   dualWield   it can hold a weapon in the off hand
--   gear        { [inventory slot] = item link } for slots 1 to 18
--   weapons     { [weapon subclass] = true } for the kinds it has learned; nil when the game
--   armor       { [armor subclass] = true }   would not say (or said too little to be
--               believed: see Roster.Update), and then its class decides
--   skills      { [profession, as the game names it] = rank }
--   profile     the profile chosen for it (see Score.lua)
--   scale       the Pawn scale chosen for it, for when Pawn scores (see Pawn.lua)
--   companion   the Forever Companion scale chosen for it while another character was
--               played, for when Forever Companion scores (see Companion.lua)
--   leveling    the spec of Forever Leveling BiS chosen for it while another character was
--               played, for when that addon scores (see Leveling.lua)
--   talents     the profile for the talent tree it has the most points in; what it is
--               scored on while none is chosen
--   armorOnly, minGain, minGainOn
--               what it wants of its gear: the list's filters that are its own (see Wants.lua)
--   maxPrice, maxPriceOn
--               the most to pay for one item for it: "Buyout up to" (see Wants.lua)
--   seen        when it was last written down (time())
local Roster = {}
ns.Roster = Roster

local WEAPON_CLASS = Enum.ItemClass.Weapon
local ARMOR_CLASS = Enum.ItemClass.Armor
local MANA = Enum.PowerType.Mana
local LAST_SLOT = 18            -- the ranged slot; the shirt and the tabard are not gear
Roster.LAST_SLOT = LAST_SLOT

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

-- The heaviest armor a class can ever wear: 1 cloth, 2 leather, 3 mail, 4 plate.
function Roster.HeaviestArmor(class)
    local heaviest
    for sub = 1, 4 do
        if ARMOR[sub].classes[class] then heaviest = sub end
    end
    return heaviest
end

-- The kinds of `kinds` the character being played has learned; nil when it seems to have
-- learned none, which is the game not answering rather than the truth.
local function Learned(kinds)
    local out, any = {}, false
    for sub, kind in pairs(kinds) do
        if C_SpellBook.IsSpellKnown(kind.spell) then
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
function Roster.Wields(card, classID, subClassID)
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

-- The game marks a tooltip line that asks something of the item's owner (line.type), and
-- says what kind of thing it asks for (line.requirementType), whatever the language of its
-- words. These are the kinds a card says nothing about: which side the character is on in a
-- form a line could be held against, its standing with a faction, a rank, a rating.
local REQUIREMENT = Enum.TooltipDataLineType.UsageRequirement
local UNKNOWABLE = {}
for _, name in ipairs({ "Faction", "PvPMedal", "Reputation", "Guild", "Achievement", "PvPRank", "ArenaRating",
    "EarnCurrency", "Specialization" }) do
    UNKNOWABLE[Enum.TooltipDataUsageRequirementType[name]] = true
end

-- The names the game may write the character's class by: some languages name a class one way
-- for men and another for women. (Three places, any of which may be empty.)
local function ClassNames(card)
    return { LOCALIZED_CLASS_NAMES_MALE[card.class], LOCALIZED_CLASS_NAMES_FEMALE[card.class], card.className }
end

-- Is the character's class in a list like "Warrior, Paladin"?
local function ClassListed(card, list)
    local names = ClassNames(card)
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
-- what a card cannot tell (standing with a faction, a rank) is taken to be out of reach: by
-- the kind of its line, and for standing with a faction by the line's words as well.
-- The item's level and its kind of weapon or armor are not judged here: see Roster.Wields.
function Roster.Allows(card, lines)
    for i = 2, #lines do
        local line = lines[i]
        if line.type == REQUIREMENT and UNKNOWABLE[line.requirementType] then return false end
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
    -- Forever gives a character a surname, other clients a realm. The cards have been kept
    -- under this name since the first version.
    local key = last and (first .. " " .. last) or (first .. "-" .. (GetRealmName() or ""))
    return key, first, last
end

-- The facts that take nothing to read.
local function Describe(card)
    local className, class = UnitClass("player")
    card.name, card.last = myName, myLast
    card.class = class or card.class
    card.className = className
    card.race = UnitRace("player")
    -- (The game now and then has no name for the realm when a character comes into the
    -- world, and gives an empty one: what the card knew before then stands.)
    local realm = GetRealmName()
    if type(realm) == "string" and realm ~= "" then
        card.realm = realm
    elseif card.realm == "" then
        card.realm = nil
    end
    card.faction = UnitFactionGroup("player")
    local level = UnitLevel("player") or 0
    if levelUp and levelUp > level then level = levelUp end
    if level > 0 then card.level = level end
    -- The game may keep this number to itself in a fight (a "secret" value, which cannot even
    -- be compared): what the card said before then stands.
    local mana = UnitPowerMax("player", MANA)
    if not issecretvalue(mana) then card.mana = mana > 0 end
    card.dualWield = CanDualWield() and true or false
end

-- The card of the character being played, made on the first call. nil only if the game does
-- not know the character's name yet.
function Roster.Me()
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
    return card
end

-- The character's professions and how far each has got, by the names the game shows: an
-- item that asks for one ("Requires First Aid (225)") names it the same way.
-- GetProfessions gives a place for each kind of profession (the two main ones, first aid,
-- fishing, cooking), empty for one the character has not got.
local function Skills()
    local out = {}
    local found = { GetProfessions() }
    for i = 1, table.maxn(found) do
        if found[i] then
            local name, _, rank = GetProfessionInfo(found[i])
            if name and rank then out[name] = rank end
        end
    end
    return out
end

-- The talent tree the character has the most points in: its name as the game writes it, its
-- place among the class's trees from the left, and how many trees there are. nil with no
-- points spent, or when the game does not say.
-- Forever keeps talents the way the game's later versions do: a tree of "traits" whose nodes
-- stand in groups, one group for each talent tree of the first game, and the game counts the
-- points spent in a group. (Mastercraft, the one addon made for this client, reads them the
-- same way.)
local function TalentTree()
    if not (C_ClassTalents and C_Traits) then return nil end
    local config = C_ClassTalents.GetActiveConfigID()
    if type(config) ~= "number" then return nil end
    local info = C_Traits.GetConfigInfo(config)
    local tree = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1] or nil
    if type(tree) ~= "number" then return nil end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(tree)
    if type(groups) ~= "table" or #groups == 0 then return nil end

    -- Left to right, as the talents window has them.
    local order, ids = {}, {}
    for i = 1, #groups do
        order[i] = { group = groups[i], at = i }
        ids[i] = groups[i].groupID
    end
    table.sort(order, function(a, b)
        local aIndex, bIndex = a.group.orderIndex or 0, b.group.orderIndex or 0
        if aIndex ~= bIndex then return aIndex < bIndex end
        return a.at < b.at
    end)

    local spent = {}
    for _, counted in ipairs(C_Traits.GetGroupCurrencyInfo(config, ids) or {}) do
        local currency = type(counted.currencyInfos) == "table" and counted.currencyInfos[1] or nil
        local points = type(currency) == "table" and currency.spent or nil
        if not issecretvalue(points) and type(points) == "number" then spent[counted.traitNodeGroupID] = points end
    end
    local best, most = nil, 0
    for place = 1, #order do
        local points = spent[order[place].group.groupID] or 0
        if points > most then best, most = place, points end
    end
    if not best then return nil end
    return order[best].group.displayName, best, #order
end

-- The profile for that tree (Score.ForTree), nil when there is nothing to go by. These
-- functions of the game are known from its documentation, not from the game itself: an error
-- in them is taken as no answer.
function Roster.TalentProfile(class)
    local ok, name, place, count = pcall(TalentTree)
    if not ok or not place then return nil end
    return ns.Score.ForTree(class, name, place, count)
end

-- Writes the character being played down as it is now.
--   gearChanged  the game has just said that the gear changed
function Roster.Update(gearChanged)
    local card = Roster.Me()
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
    card.skills = Skills()

    -- The profile for the tree its talents are in: what the character is scored on until the
    -- player chooses another (Score.Current). No answer leaves what was known.
    local talents = Roster.TalentProfile(card.class)
    if talents and talents ~= card.talents then
        local before = ns.Score.Current(card)
        card.talents = talents
        local after = ns.Score.Current(card)
        if before and after and before.name ~= after.name then
            -- A list of gear made for this character was made on the other profile.
            if not Roster.Target() and ns.Scanner.ctx then
                ns.Scanner.Reset()
                ns.Fire("OFFERS_CHANGED")
            end
            ns.Fire("PROFILE_CHANGED", card)
        end
    end

    card.seen = time()
end

---------------------------------------------------------------------------
-- The cards of the account
---------------------------------------------------------------------------
-- A card read from the saved file is used only if it holds what the lists need.
local function Sound(key, card)
    return type(card) == "table" and card.key == key and type(card.name) == "string" and card.name ~= ""
        and EVERYONE[card.class or ""] == true and type(card.level) == "number"
end

-- Every character there is a card for: the one being played first, then the others, those
-- of this realm before the rest, by name. A character of the other faction is left out:
-- nothing bought here can be mailed to it. (One whose card does not say its faction stays.)
function Roster.List()
    local me = Roster.Me()
    local out, others = {}, {}
    if me then out[1] = me end
    local faction = me and me.faction
    for key, card in pairs(ns.account.chars) do
        local sameSide = not faction or not card.faction or card.faction == faction
        if card ~= me and sameSide and Sound(key, card) then others[#others + 1] = card end
    end
    table.sort(others, function(a, b)
        local aHere, bHere = Roster.SameRealm(a, me), Roster.SameRealm(b, me)
        if aHere ~= bHere then return aHere end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    for i = 1, #others do out[#out + 1] = others[i] end
    return out
end

function Roster.Get(key)
    local card = key ~= nil and ns.account.chars[key] or nil
    if card and (key == myKey or Sound(key, card)) then return card end
    return nil
end

-- The character the lists are for, when it is not the one being played: its card. nil for
-- the character being played, whom the game is asked about directly.
-- The choice lasts until the interface is loaded again: a list for someone else must be asked
-- for, not come up by itself a week later.
local target
function Roster.Target()
    if not target then return nil end
    local card = target ~= myKey and Roster.Get(target) or nil
    if not card then target = nil end
    return card
end

-- card: one of Roster.List(); nil or the card of the character being played for that character.
function Roster.SetTarget(card)
    target = card and card ~= Roster.Me() and card.key or nil
end

-- Takes a character other than the one being played out of the account's cards, by its
-- name as the tab shows it or in full. Returns the card, or nil if there is none.
function Roster.Forget(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    local me = Roster.Me()
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
-- The character's whole name: the first name, and the surname Forever gives it.
function Roster.FullName(card)
    if type(card.last) == "string" and card.last ~= "" then return card.name .. " " .. card.last end
    return card.name
end

-- Are two characters of one realm? A card that does not say its realm (the game had no
-- name for it yet) is taken to be of the same one, as an account's characters mostly are.
function Roster.SameRealm(a, b)
    local one, other = a and a.realm, b and b.realm
    if type(one) ~= "string" or one == "" or type(other) ~= "string" or other == "" then return true end
    return one == other
end

function Roster.Colored(card, text)
    local color = RAID_CLASS_COLORS[card.class]
    return color and color:WrapTextInColorCode(text) or text
end


---------------------------------------------------------------------------
-- Keeping the card of the character being played up to date
---------------------------------------------------------------------------
-- Gear, level and skills change in bursts (a set of gear put on, a visit to a trainer), and
-- the game says so many times over: the card is written once, a moment later.
local gearNews = false      -- one of the reasons to write it was that the gear changed
local WriteSoon = ns.Soon(1, function()
    local news = gearNews
    gearNews = false
    Roster.Update(news)
end)

local function Queue(gearChanged)
    gearNews = gearNews or gearChanged
    WriteSoon()
end

ns.On("PLAYER_ENTERING_WORLD", function() Queue(false) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() Queue(true) end)
ns.On("PLAYER_LEVEL_UP", function(level)
    levelUp = level
    Queue(false)
end)
ns.On("SPELLS_CHANGED", function() Queue(false) end)
ns.On("SKILL_LINES_CHANGED", function() Queue(false) end)
-- Talents learned or taken back.
ns.On("TRAIT_CONFIG_UPDATED", function() Queue(false) end)
ns.On("AUCTION_HOUSE_SHOW", function() Queue(false) end)
-- The last word on the character before another one is played. No timer outlives a logout.
ns.On("PLAYER_LOGOUT", function() Roster.Update(gearNews) end)
