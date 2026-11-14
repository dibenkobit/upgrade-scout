-- Read by luacheck (https://github.com/lunarmodules/luacheck), which finds what a test does not
-- run into: a name that is not the game's, a variable nobody reads, a name that hides another.
--   luacheck UpgradeScout tests
std = "lua51"
max_line_length = false
exclude_files = { "UpgradeScout/Libs" }     -- other people's libraries

-- What the addon reads of the game. A name luacheck does not find here is a slip of
-- the pen, or something new: to be looked up in the client's own interface source (the branch
-- `forever` of Gethe/wow-ui-source on GitHub) and added.
read_globals = {
    -- functions of the game
    "CanDualWield", "Clamp", "CreateDataProvider", "CreateFrame", "CreateScrollBoxListLinearView", "CursorHasItem",
    "FormatPercentage", "GenerateClosure", "GetInventoryItemLink", "GetLocale", "GetMoney", "GetMoneyString",
    "GetProfessionInfo", "GetProfessions", "GetRealmName", "GetSendMailItem", "GetTime", "HandleModifiedItemClick",
    "IsModifiedClick", "MoneyFrame_Update", "PlaySound", "ResetCursor", "ShowInspectCursor", "StaticPopup_Hide",
    "StaticPopup_OnAcceptWithSpinner", "StaticPopup_Show", "UnitClass", "UnitFactionGroup", "UnitLevel", "UnitName",
    "UnitPowerMax", "UnitRace", "debugprofilestop", "hooksecurefunc", "issecretvalue", "securecallfunction", "time",
    "GameTooltip_AddBlankLineToTooltip", "GameTooltip_AddColoredLine", "GameTooltip_AddDisabledLine",
    "GameTooltip_AddErrorLine", "GameTooltip_AddHighlightLine", "GameTooltip_AddNormalLine", "GameTooltip_Hide",
    "GameTooltip_SetTitle", "GameTooltip_ShowCompareItem",
    -- its tables of functions and of numbers
    "C_AuctionHouse", "C_Container", "C_Item", "C_SpellBook", "C_Timer", "C_TooltipInfo", "ColorManager", "Constants",
    "Enum", "EventUtil", "MoneyStringConstants", "PixelUtil", "SOUNDKIT", "ScrollBoxConstants", "ScrollUtil",
    -- its frames, fonts and colours
    "AuctionHouseFrame", "GameTooltip", "MailFrame", "MailFrameTab2", "SendMailNameEditBox", "SendMailSubjectEditBox",
    "ShoppingTooltip1", "UIParent", "Number13FontWhite", "PriceFontRed", "PriceFontWhite", "STANDARD_TEXT_FONT",
    "GREEN_FONT_COLOR", "NORMAL_FONT_COLOR", "RAID_CLASS_COLORS",
    -- its words
    "ACCEPT", "BUYOUT_AUCTION_CONFIRMATION", "CANCEL", "DAYS_ABBR", "HOURS_ABBR", "MINUTES_ABBR", "SECONDS_ABBR", "NONE",
    "ITEM_CLASSES_ALLOWED", "ITEM_MIN_SKILL", "ITEM_RACES_ALLOWED", "ITEM_REQ_REPUTATION", "ITEM_SPELL_TRIGGER_ONUSE",
    "ITEM_UNIQUE_EQUIPPABLE", "LARGE_NUMBER_SEPERATOR", "LOCALIZED_CLASS_NAMES_FEMALE", "LOCALIZED_CLASS_NAMES_MALE",
    "RETRIEVING_ITEM_INFO", "SHIELD_BLOCK_TEMPLATE",
    -- its numbers
    "ATTACHMENTS_MAX_SEND", "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    -- the libraries that come with the addon
    "LibStub",
}

-- What the addon writes: its saved variables, its slash command, its question before a purchase.
globals = {
    "UpgradeScoutCharDB", "UpgradeScoutDB", "SLASH_UPGRADESCOUT1", "SLASH_UPGRADESCOUT2", "SlashCmdList", "StaticPopupDialogs",
}

-- The tests stand in for the game. They define its globals, which is their job, with the game's
-- own arguments whether they have a use for them or not.
files["tests"] = { global = false, self = false, unused_args = false, ignore = { "432" } }
