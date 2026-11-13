local _, ns = ...

-- English is the default; a missing translation falls back to it.
local L = {
    TAB = "Upgrades",
    TITLE = "Gear upgrades for sale",

    SCAN = "Scan",
    STOP = "Stop",
    BUY = "Buy",
    AFFORD = "Only what I can afford",
    TOP = "Top %d per slot",
    TOP_TIP = "Up to %d options per slot, from the best upgrade down to the best value. An item is left out when a stronger one costs the same or less per point.",
    TOP_OF = "%d of %d",
    TOP_OF_ABOUT = "%d of about %d",
    SCALE = "Pawn scale:",
    SCALE_TIP = "The Pawn scale used to score items. Scales are enabled and edited in Pawn (/pawn).",

    COL_ITEM = "Item",
    COL_PICK = "Pick",
    COL_UPGRADE = "Upgrade",
    COL_PRICE = "Buyout",
    COL_PER = "Per point",

    PICK_UPGRADE = "Best upgrade",
    PICK_VALUE = "Best value",
    PICK_BOTH = "Best of both",

    NEW = "new",

    HINT = "Press Scan. The list will show gear on the auction house that you can equip right now and that scores higher than what you are wearing on the Pawn scale \"%s\".",
    ST_BROWSE = "Reading the auction list: %d rows",
    ST_SCORE = "Scoring items: %d of %d",
    ST_VERIFY = "Checking buyout prices: %d of %d",
    ST_LEFT = ", about %s left",
    ST_BUYCHECK = "Checking that the item is still for sale…",
    ST_DONE = "%d upgrades in %d slots.",
    ST_DONE_HIDDEN = "%d upgrades in %d slots. %d more cost more than you have.",
    ST_NONE = "No upgrades with a buyout price are for sale right now.",
    ST_NONE_AFFORD = "Nothing you can afford. %d upgrades cost more than you have.",
    ST_PARTIAL = "The scan stopped early, so the list may be incomplete.",
    ST_STOPPED = "Scan stopped.",
    ST_INTERRUPTED = "Another search replaced the auction list, so the scan stopped. Press Scan again.",
    ST_AGE = "Scanned %s ago.",

    ERR_PAWN_API = "Pawn is loaded, but its function %s is missing. Update Pawn.",
    ERR_PAWN_NOT_READY = "Pawn has not finished loading yet. Try again in a moment.",
    ERR_NO_SCALE = "No Pawn scale is active for this character. Open Pawn (/pawn) and enable one.",
    ERR_AH_CLOSED = "Open the auction house first.",
    ERR_BROWSE = "The auction house did not answer the search. Try again.",
    ERR_BUSY = "Wait for the scan to finish.",

    STATS = "Last scan: %d s. Auction list %d s (%d requests, %d rows). Scoring %d s (%d upgrades by score). Prices %d s (%d item searches, %d extra pages, %d unanswered; %d not needed for the list).",
    STATS_NONE = "No scan yet.",

    TT_SCORE = "Pawn score: %s, yours: %s (+%s)",
    TT_SCORE_EMPTY = "Pawn score: %s, slot is empty",
    TT_REPLACES = "Replaces: %s",
    TT_COST = "Cost per point: %s",
    TT_EFFECTS = "Has effects that Pawn does not score.",
    TT_OFFHAND_EMPTY = "Your off hand will be empty.",
    TT_BOTH_HANDS = "Takes both hands.",
    TT_MORE = "%d more for sale at a higher price.",
    TT_MORE_SOME = "More of them are for sale at a higher price.",
    TT_CANT_AFFORD = "You are %s short.",

    MSG_GONE = "%s is no longer for sale.",
    MSG_PRICE = "%s now costs %s (was %s).",
    MSG_BOUGHT = "Bought %s for %s. It will arrive by mail.",
    MSG_CANT_AFFORD = "You can't afford that.",

    HEAD = "Head", NECK = "Neck", SHOULDER = "Shoulders", BACK = "Back", CHEST = "Chest",
    WRIST = "Wrist", HANDS = "Hands", WAIST = "Waist", LEGS = "Legs", FEET = "Feet",
    FINGER = "Finger", TRINKET = "Trinket", MAINHAND = "Main Hand", OFFHAND = "Off Hand", RANGED = "Ranged",

    -- Used only if the game does not have its own text under the same name.
    INVTYPE_WEAPON = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_SHIELD = "Off Hand", INVTYPE_HOLDABLE = "Held In Off-hand",
}

if GetLocale() == "ruRU" then
    local R = {
        TAB = "Улучшения",
        TITLE = "Улучшения экипировки на аукционе",

        SCAN = "Скан",
        STOP = "Стоп",
        BUY = "Купить",
        AFFORD = "Только то, что по карману",
        TOP = "Топ-%d в слоте",
        TOP_TIP = "До %d вариантов в слоте: от лучшего улучшения до самого выгодного. Вещь не показывается, если другая сильнее и стоит столько же или меньше за очко.",
        TOP_OF = "%d из %d",
        TOP_OF_ABOUT = "%d из примерно %d",
        SCALE = "Шкала Pawn:",
        SCALE_TIP = "Шкала Pawn, по которой оцениваются вещи. Шкалы включаются и настраиваются в Pawn (/pawn).",

        COL_ITEM = "Предмет",
        COL_PICK = "Выбор",
        COL_UPGRADE = "Улучшение",
        COL_PRICE = "Выкуп",
        COL_PER = "За очко",

        PICK_UPGRADE = "Лучшее улучшение",
        PICK_VALUE = "Самое выгодное",
        PICK_BOTH = "Лучшее и выгодное",

        NEW = "новое",

        HINT = "Нажми «Скан». В списке появятся вещи с аукциона, которые можно надеть прямо сейчас и которые по шкале Pawn «%s» лучше надетых.",
        ST_BROWSE = "Читаю список лотов: %d строк",
        ST_SCORE = "Оцениваю вещи: %d из %d",
        ST_VERIFY = "Проверяю цены выкупа: %d из %d",
        ST_LEFT = ", осталось примерно %s",
        ST_BUYCHECK = "Проверяю, что вещь ещё продаётся…",
        ST_DONE = "Улучшений: %d, слотов: %d.",
        ST_DONE_HIDDEN = "Улучшений: %d, слотов: %d. Ещё %d стоят больше, чем у тебя есть.",
        ST_NONE = "Сейчас нет улучшений с ценой выкупа.",
        ST_NONE_AFFORD = "Ничего по карману. Улучшений дороже твоего золота: %d.",
        ST_PARTIAL = "Скан остановился раньше времени, список может быть неполным.",
        ST_STOPPED = "Скан остановлен.",
        ST_INTERRUPTED = "Другой поиск заменил список лотов, скан остановлен. Нажми «Скан» ещё раз.",
        ST_AGE = "Скан был %s назад.",

        ERR_PAWN_API = "Pawn загружен, но в нём нет функции %s. Обнови Pawn.",
        ERR_PAWN_NOT_READY = "Pawn ещё не загрузился. Попробуй через пару секунд.",
        ERR_NO_SCALE = "У этого персонажа нет активной шкалы Pawn. Открой Pawn (/pawn) и включи шкалу.",
        ERR_AH_CLOSED = "Сначала открой аукцион.",
        ERR_BROWSE = "Аукцион не ответил на поиск. Попробуй ещё раз.",
        ERR_BUSY = "Дождись конца скана.",

        STATS = "Последний скан: %d с. Список лотов %d с (запросов: %d, строк: %d). Оценка %d с (улучшений по оценке: %d). Цены %d с (поисков: %d, доп. страниц: %d, без ответа: %d; не понадобилось для списка: %d).",
        STATS_NONE = "Скана ещё не было.",

        TT_SCORE = "Оценка Pawn: %s, у тебя: %s (+%s)",
        TT_SCORE_EMPTY = "Оценка Pawn: %s, слот пуст",
        TT_REPLACES = "Заменяет: %s",
        TT_COST = "Цена за очко: %s",
        TT_EFFECTS = "Есть эффекты, которые Pawn не оценивает.",
        TT_OFFHAND_EMPTY = "Левая рука останется пустой.",
        TT_BOTH_HANDS = "Занимает обе руки.",
        TT_MORE = "Ещё %d в продаже по более высокой цене.",
        TT_MORE_SOME = "В продаже есть ещё, по более высокой цене.",
        TT_CANT_AFFORD = "Не хватает %s.",

        MSG_GONE = "%s уже не продаётся.",
        MSG_PRICE = "%s теперь стоит %s (было %s).",
        MSG_BOUGHT = "Куплено: %s за %s. Вещь придёт по почте.",
        MSG_CANT_AFFORD = "На это не хватает золота.",

        HEAD = "Голова", NECK = "Шея", SHOULDER = "Плечи", BACK = "Спина", CHEST = "Грудь",
        WRIST = "Запястья", HANDS = "Кисти рук", WAIST = "Пояс", LEGS = "Ноги", FEET = "Ступни",
        FINGER = "Палец", TRINKET = "Аксессуар", MAINHAND = "Правая рука", OFFHAND = "Левая рука", RANGED = "Дальний бой",

        INVTYPE_WEAPON = "Одноручное", INVTYPE_2HWEAPON = "Двуручное", INVTYPE_WEAPONMAINHAND = "Правая рука",
        INVTYPE_WEAPONOFFHAND = "Левая рука", INVTYPE_SHIELD = "Левая рука", INVTYPE_HOLDABLE = "Левая рука",
    }
    for k, v in pairs(R) do L[k] = v end
end

if GetLocale() == "deDE" then
    local D = {
        TAB = "Verbesserungen",
        TITLE = "Ausrüstungsverbesserungen im Auktionshaus",

        SCAN = "Scannen",
        STOP = "Stopp",
        BUY = "Kaufen",
        AFFORD = "Nur Bezahlbares",
        TOP = "Top %d pro Slot",
        TOP_TIP = "Bis zu %d Optionen pro Slot, von der besten Verbesserung bis zur besten Preis-Leistung. Ein Gegenstand wird ausgelassen, wenn ein stärkerer pro Punkt gleich viel oder weniger kostet.",
        TOP_OF = "%d von %d",
        TOP_OF_ABOUT = "%d von etwa %d",
        SCALE = "Pawn-Skala:",
        SCALE_TIP = "Die Pawn-Skala, nach der Gegenstände bewertet werden. Skalen werden in Pawn (/pawn) aktiviert und bearbeitet.",

        COL_ITEM = "Gegenstand",
        COL_PICK = "Empfehlung",
        COL_UPGRADE = "Verbesserung",
        COL_PRICE = "Sofortkauf",
        COL_PER = "Pro Punkt",

        PICK_UPGRADE = "Beste Verbesserung",
        PICK_VALUE = "Beste Preis-Leistung",
        PICK_BOTH = "Beste in beidem",

        NEW = "neu",

        HINT = "Klicke auf »Scannen«. Die Liste zeigt dann Ausrüstung aus dem Auktionshaus, die du sofort anlegen kannst und die nach der Pawn-Skala »%s« besser ist als das, was du gerade trägst.",
        ST_BROWSE = "Lese Auktionsliste: %d Zeilen",
        ST_SCORE = "Bewerte Gegenstände: %d von %d",
        ST_VERIFY = "Prüfe Sofortkaufpreise: %d von %d",
        ST_LEFT = ", noch etwa %s",
        ST_BUYCHECK = "Prüfe, ob der Gegenstand noch angeboten wird…",
        ST_DONE = "Verbesserungen: %d, Slots: %d.",
        ST_DONE_HIDDEN = "Verbesserungen: %d, Slots: %d. Für dich zu teuer: %d weitere.",
        ST_NONE = "Derzeit werden keine Verbesserungen mit Sofortkaufpreis angeboten.",
        ST_NONE_AFFORD = "Nichts, was du dir leisten kannst. Zu teure Verbesserungen: %d.",
        ST_PARTIAL = "Der Scan wurde vorzeitig beendet, die Liste ist möglicherweise unvollständig.",
        ST_STOPPED = "Scan gestoppt.",
        ST_INTERRUPTED = "Eine andere Suche hat die Auktionsliste ersetzt, daher wurde der Scan gestoppt. Klicke erneut auf »Scannen«.",
        ST_AGE = "Gescannt vor %s.",

        ERR_PAWN_API = "Pawn ist geladen, aber die Funktion %s fehlt. Aktualisiere Pawn.",
        ERR_PAWN_NOT_READY = "Pawn ist noch nicht fertig geladen. Versuche es gleich noch einmal.",
        ERR_NO_SCALE = "Für diesen Charakter ist keine Pawn-Skala aktiv. Öffne Pawn (/pawn) und aktiviere eine.",
        ERR_AH_CLOSED = "Öffne zuerst das Auktionshaus.",
        ERR_BROWSE = "Das Auktionshaus hat auf die Suche nicht geantwortet. Versuche es noch einmal.",
        ERR_BUSY = "Warte, bis der Scan abgeschlossen ist.",

        STATS = "Letzter Scan: %d s. Auktionsliste %d s (Anfragen: %d, Zeilen: %d). Bewertung %d s (Verbesserungen nach Wertung: %d). Preise %d s (Gegenstandssuchen: %d, zusätzliche Seiten: %d, unbeantwortet: %d; für die Liste nicht benötigt: %d).",
        STATS_NONE = "Noch kein Scan.",

        TT_SCORE = "Pawn-Wertung: %s, deine: %s (+%s)",
        TT_SCORE_EMPTY = "Pawn-Wertung: %s, Slot ist leer",
        TT_REPLACES = "Ersetzt: %s",
        TT_COST = "Kosten pro Punkt: %s",
        TT_EFFECTS = "Hat Effekte, die Pawn nicht bewertet.",
        TT_OFFHAND_EMPTY = "Deine Schildhand bleibt leer.",
        TT_BOTH_HANDS = "Belegt beide Hände.",
        TT_MORE = "%d weitere zu einem höheren Preis im Angebot.",
        TT_MORE_SOME = "Weitere sind zu einem höheren Preis im Angebot.",
        TT_CANT_AFFORD = "Dir fehlen %s.",

        MSG_GONE = "%s wird nicht mehr angeboten.",
        MSG_PRICE = "%s kostet jetzt %s (vorher %s).",
        MSG_BOUGHT = "%s für %s gekauft. Der Gegenstand kommt per Post.",
        MSG_CANT_AFFORD = "Das kannst du dir nicht leisten.",

        HEAD = "Kopf", NECK = "Hals", SHOULDER = "Schultern", BACK = "Rücken", CHEST = "Brust",
        WRIST = "Handgelenke", HANDS = "Hände", WAIST = "Taille", LEGS = "Beine", FEET = "Füße",
        FINGER = "Finger", TRINKET = "Schmuck", MAINHAND = "Waffenhand", OFFHAND = "Schildhand", RANGED = "Distanz",

        INVTYPE_WEAPON = "Einhändig", INVTYPE_2HWEAPON = "Zweihändig", INVTYPE_WEAPONMAINHAND = "Waffenhand",
        INVTYPE_WEAPONOFFHAND = "Schildhand", INVTYPE_SHIELD = "Schildhand", INVTYPE_HOLDABLE = "In Schildhand geführt",
    }
    for k, v in pairs(D) do L[k] = v end
end

-- Terms follow Pawn's own frFR text: échelle (scale), amélioration (upgrade), emplacement (slot).
if GetLocale() == "frFR" then
    local F = {
        TAB = "Améliorations",
        TITLE = "Améliorations d'équipement en vente",

        SCAN = "Scanner",
        STOP = "Arrêter",
        BUY = "Acheter",
        AFFORD = "Seulement ce que je peux payer",
        TOP = "Top %d par emplacement",
        TOP_TIP = "Jusqu'à %d options par emplacement, de la meilleure amélioration à la meilleure affaire. Un objet est écarté lorsqu'un objet plus puissant coûte autant ou moins par point.",
        TOP_OF = "%d sur %d",
        TOP_OF_ABOUT = "%d sur environ %d",
        SCALE = "Échelle Pawn :",
        SCALE_TIP = "L'échelle Pawn utilisée pour évaluer les objets. Les échelles s'activent et se modifient dans Pawn (/pawn).",

        COL_ITEM = "Objet",
        COL_PICK = "Choix",
        COL_UPGRADE = "Amélioration",
        COL_PRICE = "Achat immédiat",
        COL_PER = "Par point",

        PICK_UPGRADE = "Meilleure amélioration",
        PICK_VALUE = "Meilleure affaire",
        PICK_BOTH = "Les deux à la fois",

        NEW = "nouveau",

        HINT = "Cliquez sur « Scanner ». La liste affichera l'équipement de l'hôtel des ventes que vous pouvez équiper dès maintenant et dont le score dépasse celui de votre équipement actuel selon l'échelle Pawn « %s ».",
        ST_BROWSE = "Lecture de la liste des enchères : %d lignes",
        ST_SCORE = "Évaluation des objets : %d sur %d",
        ST_VERIFY = "Vérification des prix d'achat immédiat : %d sur %d",
        ST_LEFT = ", encore environ %s",
        ST_BUYCHECK = "Vérification que l'objet est toujours en vente…",
        ST_DONE = "Améliorations : %d, emplacements : %d.",
        ST_DONE_HIDDEN = "Améliorations : %d, emplacements : %d. Trop chères pour vous : %d de plus.",
        ST_NONE = "Aucune amélioration avec un prix d'achat immédiat n'est en vente actuellement.",
        ST_NONE_AFFORD = "Rien dans vos moyens. Améliorations trop chères pour vous : %d.",
        ST_PARTIAL = "Le scan s'est arrêté prématurément, la liste est peut-être incomplète.",
        ST_STOPPED = "Scan arrêté.",
        ST_INTERRUPTED = "Une autre recherche a remplacé la liste des enchères, le scan s'est donc arrêté. Cliquez de nouveau sur « Scanner ».",
        ST_AGE = "Scanné il y a %s.",

        ERR_PAWN_API = "Pawn est chargé, mais sa fonction %s est introuvable. Mettez Pawn à jour.",
        ERR_PAWN_NOT_READY = "Pawn n'a pas encore fini de se charger. Réessayez dans un instant.",
        ERR_NO_SCALE = "Aucune échelle Pawn n'est active pour ce personnage. Ouvrez Pawn (/pawn) et activez-en une.",
        ERR_AH_CLOSED = "Ouvrez d'abord l'hôtel des ventes.",
        ERR_BROWSE = "L'hôtel des ventes n'a pas répondu à la recherche. Réessayez.",
        ERR_BUSY = "Attendez la fin du scan.",

        STATS = "Dernier scan : %d s. Liste des enchères %d s (requêtes : %d, lignes : %d). Évaluation %d s (améliorations d'après le score : %d). Prix %d s (recherches d'objets : %d, pages supplémentaires : %d, sans réponse : %d ; inutiles pour la liste : %d).",
        STATS_NONE = "Aucun scan pour l'instant.",

        TT_SCORE = "Score Pawn : %s, le vôtre : %s (+%s)",
        TT_SCORE_EMPTY = "Score Pawn : %s, l'emplacement est vide",
        TT_REPLACES = "Remplace : %s",
        TT_COST = "Coût par point : %s",
        TT_EFFECTS = "Possède des effets que Pawn n'évalue pas.",
        TT_OFFHAND_EMPTY = "Votre main gauche sera vide.",
        TT_BOTH_HANDS = "Occupe les deux mains.",
        TT_MORE = "%d de plus en vente à un prix plus élevé.",
        TT_MORE_SOME = "D'autres sont en vente à un prix plus élevé.",
        TT_CANT_AFFORD = "Il vous manque %s.",

        MSG_GONE = "%s n'est plus en vente.",
        MSG_PRICE = "%s coûte maintenant %s (%s auparavant).",
        MSG_BOUGHT = "Achat de %s pour %s. L'objet arrivera par courrier.",
        MSG_CANT_AFFORD = "Vous n'avez pas assez d'argent.",

        HEAD = "Tête", NECK = "Cou", SHOULDER = "Épaules", BACK = "Dos", CHEST = "Torse",
        WRIST = "Poignets", HANDS = "Mains", WAIST = "Taille", LEGS = "Jambes", FEET = "Pieds",
        FINGER = "Doigt", TRINKET = "Bijou", MAINHAND = "Main droite", OFFHAND = "Main gauche", RANGED = "À distance",

        INVTYPE_WEAPON = "À une main", INVTYPE_2HWEAPON = "Deux mains", INVTYPE_WEAPONMAINHAND = "Main droite",
        INVTYPE_WEAPONOFFHAND = "Main gauche", INVTYPE_SHIELD = "Main gauche", INVTYPE_HOLDABLE = "Tenu en main gauche",
    }
    for k, v in pairs(F) do L[k] = v end
end

-- Terms follow Pawn's own zhCN text: 属性权重 (scale), 提升 (upgrade), 部位 (slot).
if GetLocale() == "zhCN" then
    local Z = {
        TAB = "装备提升",
        TITLE = "拍卖行中的装备提升",

        SCAN = "扫描",
        STOP = "停止",
        BUY = "购买",
        AFFORD = "只看买得起的",
        TOP = "每个部位前%d件",
        TOP_TIP = "每个部位最多显示%d个选项，从提升最大的到性价比最高的。如果另一件物品更强，且每点提升的花费相同或更低，较弱的那件就不会显示。",
        TOP_OF = "%d/%d",
        TOP_OF_ABOUT = "%d/约%d",
        SCALE = "Pawn 属性权重：",
        SCALE_TIP = "用来给物品评分的 Pawn 属性权重。属性权重在 Pawn（/pawn）中启用和编辑。",

        COL_ITEM = "物品",
        COL_PICK = "推荐",
        COL_UPGRADE = "提升",
        COL_PRICE = "一口价",
        COL_PER = "每点花费",

        PICK_UPGRADE = "最大提升",
        PICK_VALUE = "最高性价比",
        PICK_BOTH = "两项最佳",

        NEW = "新增",

        HINT = "点击“扫描”。列表会显示拍卖行中你现在就能装备，并且按 Pawn 属性权重“%s”评分高于你当前装备的物品。",
        ST_BROWSE = "正在读取拍卖列表：%d行",
        ST_SCORE = "正在给物品评分：%d/%d",
        ST_VERIFY = "正在核对一口价：%d/%d",
        ST_LEFT = "，大约还需%s",
        ST_BUYCHECK = "正在确认物品是否仍在出售……",
        ST_DONE = "找到%d件提升装备，涉及%d个部位。",
        ST_DONE_HIDDEN = "找到%d件提升装备，涉及%d个部位。另有%d件你买不起。",
        ST_NONE = "目前没有带一口价的提升装备在售。",
        ST_NONE_AFFORD = "没有你买得起的提升装备。有%d件超出了你现有的金币。",
        ST_PARTIAL = "扫描提前结束，列表可能不完整。",
        ST_STOPPED = "扫描已停止。",
        ST_INTERRUPTED = "另一次搜索替换了拍卖列表，扫描已停止。请再次点击“扫描”。",
        ST_AGE = "%s前扫描。",

        ERR_PAWN_API = "Pawn 已加载，但缺少函数 %s。请更新 Pawn。",
        ERR_PAWN_NOT_READY = "Pawn 尚未加载完成，请稍后再试。",
        ERR_NO_SCALE = "当前角色没有启用任何 Pawn 属性权重。请打开 Pawn（/pawn）并启用一个。",
        ERR_AH_CLOSED = "请先打开拍卖行。",
        ERR_BROWSE = "拍卖行没有响应搜索，请重试。",
        ERR_BUSY = "请等待扫描完成。",

        STATS = "上次扫描：%d秒。拍卖列表%d秒（%d次请求，%d行）。评分%d秒（按评分有%d件提升装备）。价格%d秒（%d次物品搜索，%d个额外页面，%d次无响应；%d件无需查价）。",
        STATS_NONE = "还没有扫描过。",

        TT_SCORE = "Pawn 评分：%s，当前装备：%s（+%s）",
        TT_SCORE_EMPTY = "Pawn 评分：%s，该部位为空",
        TT_REPLACES = "替换：%s",
        TT_COST = "每点提升花费：%s",
        TT_EFFECTS = "带有 Pawn 不计入评分的效果。",
        TT_OFFHAND_EMPTY = "你的副手将会空出。",
        TT_BOTH_HANDS = "占用双手。",
        TT_MORE = "另有%d件以更高的价格在售。",
        TT_MORE_SOME = "还有更多以更高的价格在售。",
        TT_CANT_AFFORD = "还差 %s。",

        MSG_GONE = "%s 已不再出售。",
        MSG_PRICE = "%s 现在售价 %s（之前为 %s）。",
        MSG_BOUGHT = "已购买 %s，花费 %s。物品将通过邮件送达。",
        MSG_CANT_AFFORD = "你的金币不够。",

        HEAD = "头部", NECK = "颈部", SHOULDER = "肩部", BACK = "背部", CHEST = "胸部",
        WRIST = "手腕", HANDS = "手", WAIST = "腰部", LEGS = "腿部", FEET = "脚",
        FINGER = "手指", TRINKET = "饰品", MAINHAND = "主手", OFFHAND = "副手", RANGED = "远程",

        INVTYPE_WEAPON = "单手", INVTYPE_2HWEAPON = "双手", INVTYPE_WEAPONMAINHAND = "主手",
        INVTYPE_WEAPONOFFHAND = "副手", INVTYPE_SHIELD = "副手", INVTYPE_HOLDABLE = "副手物品",
    }
    for k, v in pairs(Z) do L[k] = v end
end

-- Terms follow Pawn's own ptBR text (escala, melhoria) and the game's (Casa de Leilões, arremate,
-- espaço). Counts go after a colon where a number of 1 would otherwise break the plural.
if GetLocale() == "ptBR" then
    local P = {
        TAB = "Melhorias",
        TITLE = "Melhorias de equipamento à venda",

        SCAN = "Escanear",
        STOP = "Parar",
        BUY = "Comprar",
        AFFORD = "Só o que posso pagar",
        TOP = "Top %d por espaço",
        TOP_TIP = "Até %d opções por espaço, da maior melhoria ao melhor custo-benefício. Um item fica de fora quando outro mais forte custa o mesmo ou menos por ponto.",
        TOP_OF = "%d de %d",
        TOP_OF_ABOUT = "%d de cerca de %d",
        SCALE = "Escala do Pawn:",
        SCALE_TIP = "A escala do Pawn usada para avaliar os itens. As escalas são ativadas e editadas no Pawn (/pawn).",

        COL_ITEM = "Item",
        COL_PICK = "Destaque",
        COL_UPGRADE = "Melhoria",
        COL_PRICE = "Arremate",
        COL_PER = "Por ponto",

        PICK_UPGRADE = "Maior melhoria",
        PICK_VALUE = "Melhor custo-benefício",
        PICK_BOTH = "Melhor nos dois",

        NEW = "novo",

        HINT = "Clique em Escanear. A lista mostrará equipamentos da Casa de Leilões que você pode equipar agora mesmo e que pontuam mais do que os que você está usando na escala \"%s\" do Pawn.",
        ST_BROWSE = "Lendo a lista de leilões: %d linhas",
        ST_SCORE = "Avaliando itens: %d de %d",
        ST_VERIFY = "Verificando preços de arremate: %d de %d",
        ST_LEFT = ", tempo restante: cerca de %s",
        ST_BUYCHECK = "Verificando se o item ainda está à venda…",
        ST_DONE = "Melhorias: %d, espaços: %d.",
        ST_DONE_HIDDEN = "Melhorias: %d, espaços: %d. Mais %d fora do seu orçamento.",
        ST_NONE = "No momento não há melhorias à venda com preço de arremate.",
        ST_NONE_AFFORD = "Nada que você possa pagar. Melhorias fora do seu orçamento: %d.",
        ST_PARTIAL = "O escaneamento parou antes do fim, então a lista pode estar incompleta.",
        ST_STOPPED = "Escaneamento interrompido.",
        ST_INTERRUPTED = "Outra busca substituiu a lista de leilões, então o escaneamento parou. Clique em Escanear de novo.",
        ST_AGE = "Escaneado há %s.",

        ERR_PAWN_API = "O Pawn está carregado, mas a função %s não existe. Atualize o Pawn.",
        ERR_PAWN_NOT_READY = "O Pawn ainda não terminou de carregar. Tente de novo em instantes.",
        ERR_NO_SCALE = "Nenhuma escala do Pawn está ativa para este personagem. Abra o Pawn (/pawn) e ative uma.",
        ERR_AH_CLOSED = "Abra a Casa de Leilões primeiro.",
        ERR_BROWSE = "A Casa de Leilões não respondeu à busca. Tente de novo.",
        ERR_BUSY = "Aguarde o fim do escaneamento.",

        STATS = "Último escaneamento: %d s. Lista de leilões %d s (consultas: %d, linhas: %d). Avaliação %d s (melhorias pela pontuação: %d). Preços %d s (buscas de itens: %d, páginas extras: %d, sem resposta: %d; desnecessárias para a lista: %d).",
        STATS_NONE = "Nenhum escaneamento ainda.",

        TT_SCORE = "Pontuação do Pawn: %s, a sua: %s (+%s)",
        TT_SCORE_EMPTY = "Pontuação do Pawn: %s, o espaço está vazio",
        TT_REPLACES = "Substitui: %s",
        TT_COST = "Custo por ponto: %s",
        TT_EFFECTS = "Tem efeitos que o Pawn não avalia.",
        TT_OFFHAND_EMPTY = "Sua mão secundária ficará vazia.",
        TT_BOTH_HANDS = "Ocupa as duas mãos.",
        TT_MORE = "Mais %d à venda por um preço maior.",
        TT_MORE_SOME = "Há outros à venda por um preço maior.",
        TT_CANT_AFFORD = "Faltam %s.",

        MSG_GONE = "%s não está mais à venda.",
        MSG_PRICE = "%s agora custa %s (antes: %s).",
        MSG_BOUGHT = "Você comprou %s por %s. O item chegará pelo correio.",
        MSG_CANT_AFFORD = "Você não tem dinheiro suficiente para isso.",

        HEAD = "Cabeça", NECK = "Pescoço", SHOULDER = "Ombros", BACK = "Costas", CHEST = "Torso",
        WRIST = "Pulsos", HANDS = "Mãos", WAIST = "Cintura", LEGS = "Pernas", FEET = "Pés",
        FINGER = "Dedo", TRINKET = "Berloque", MAINHAND = "Mão Principal", OFFHAND = "Mão Secundária", RANGED = "Longo Alcance",

        INVTYPE_WEAPON = "Uma Mão", INVTYPE_2HWEAPON = "Duas Mãos", INVTYPE_WEAPONMAINHAND = "Mão Principal",
        INVTYPE_WEAPONOFFHAND = "Mão Secundária", INVTYPE_SHIELD = "Mão Secundária", INVTYPE_HOLDABLE = "Empunhado na Mão Secundária",
    }
    for k, v in pairs(P) do L[k] = v end
end

-- One text for both Spanish clients. Terms follow Pawn's own Spanish text: escala (scale),
-- mejora (upgrade).
if GetLocale() == "esES" or GetLocale() == "esMX" then
    local E = {
        TAB = "Mejoras",
        TITLE = "Mejoras de equipo en venta",

        SCAN = "Escanear",
        STOP = "Detener",
        BUY = "Comprar",
        AFFORD = "Solo lo que puedo pagar",
        TOP = "Top %d por ranura",
        TOP_TIP = "Hasta %d opciones por ranura, desde la mayor mejora hasta la más rentable. Un objeto se omite cuando otro más fuerte cuesta lo mismo o menos por punto.",
        TOP_OF = "%d de %d",
        TOP_OF_ABOUT = "%d de unos %d",
        SCALE = "Escala de Pawn:",
        SCALE_TIP = "La escala de Pawn con la que se puntúan los objetos. Las escalas se activan y se editan en Pawn (/pawn).",

        COL_ITEM = "Objeto",
        COL_PICK = "Recomendación",
        COL_UPGRADE = "Mejora",
        COL_PRICE = "Compra",
        COL_PER = "Por punto",

        PICK_UPGRADE = "Mayor mejora",
        PICK_VALUE = "Más rentable",
        PICK_BOTH = "Mejor en ambos",

        NEW = "nuevo",

        HINT = "Pulsa «Escanear». La lista mostrará el equipo de la casa de subastas que puedes equiparte ahora mismo y que, según la escala de Pawn «%s», puntúa más que lo que llevas puesto.",
        ST_BROWSE = "Leyendo la lista de subastas: %d filas",
        ST_SCORE = "Puntuando objetos: %d de %d",
        ST_VERIFY = "Comprobando precios de compra: %d de %d",
        ST_LEFT = ", faltan unos %s",
        ST_BUYCHECK = "Comprobando que el objeto sigue en venta…",
        ST_DONE = "Mejoras: %d, ranuras: %d.",
        ST_DONE_HIDDEN = "Mejoras: %d, ranuras: %d. Demasiado caras para ti: %d más.",
        ST_NONE = "Ahora mismo no hay mejoras en venta con precio de compra.",
        ST_NONE_AFFORD = "Nada que puedas pagar. Mejoras que cuestan más de lo que tienes: %d.",
        ST_PARTIAL = "El escaneo se detuvo antes de tiempo, así que la lista puede estar incompleta.",
        ST_STOPPED = "Escaneo detenido.",
        ST_INTERRUPTED = "Otra búsqueda reemplazó la lista de subastas, así que el escaneo se detuvo. Pulsa «Escanear» de nuevo.",
        ST_AGE = "Escaneado hace %s.",

        ERR_PAWN_API = "Pawn está cargado, pero falta su función %s. Actualiza Pawn.",
        ERR_PAWN_NOT_READY = "Pawn aún no ha terminado de cargarse. Inténtalo de nuevo en un momento.",
        ERR_NO_SCALE = "Este personaje no tiene ninguna escala de Pawn activa. Abre Pawn (/pawn) y activa una.",
        ERR_AH_CLOSED = "Abre primero la casa de subastas.",
        ERR_BROWSE = "La casa de subastas no respondió a la búsqueda. Inténtalo de nuevo.",
        ERR_BUSY = "Espera a que termine el escaneo.",

        STATS = "Último escaneo: %d s. Lista de subastas %d s (peticiones: %d, filas: %d). Puntuación %d s (mejoras por puntuación: %d). Precios %d s (búsquedas de objetos: %d, páginas extra: %d, sin respuesta: %d; no necesarias para la lista: %d).",
        STATS_NONE = "Aún no se ha hecho ningún escaneo.",

        TT_SCORE = "Puntuación de Pawn: %s, la tuya: %s (+%s)",
        TT_SCORE_EMPTY = "Puntuación de Pawn: %s, la ranura está vacía",
        TT_REPLACES = "Reemplaza a: %s",
        TT_COST = "Precio por punto: %s",
        TT_EFFECTS = "Tiene efectos que Pawn no puntúa.",
        TT_OFFHAND_EMPTY = "Tu mano izquierda quedará vacía.",
        TT_BOTH_HANDS = "Ocupa ambas manos.",
        TT_MORE = "Hay %d más en venta a un precio más alto.",
        TT_MORE_SOME = "Hay más en venta a un precio más alto.",
        TT_CANT_AFFORD = "Te faltan %s.",

        MSG_GONE = "%s ya no está en venta.",
        MSG_PRICE = "%s ahora cuesta %s (antes %s).",
        MSG_BOUGHT = "Has comprado %s por %s. Llegará por correo.",
        MSG_CANT_AFFORD = "No tienes suficiente dinero.",

        HEAD = "Cabeza", NECK = "Cuello", SHOULDER = "Hombros", BACK = "Espalda", CHEST = "Pecho",
        WRIST = "Muñecas", HANDS = "Manos", WAIST = "Cintura", LEGS = "Piernas", FEET = "Pies",
        FINGER = "Dedo", TRINKET = "Abalorio", MAINHAND = "Mano derecha", OFFHAND = "Mano izquierda", RANGED = "A distancia",

        INVTYPE_WEAPON = "Una mano", INVTYPE_2HWEAPON = "Dos manos", INVTYPE_WEAPONMAINHAND = "Mano derecha",
        INVTYPE_WEAPONOFFHAND = "Mano izquierda", INVTYPE_SHIELD = "Mano izquierda", INVTYPE_HOLDABLE = "Sostener con la mano izquierda",
    }
    for k, v in pairs(E) do L[k] = v end
end

-- Terms follow Pawn's own itIT text: formula (scale), miglioramento (upgrade).
if GetLocale() == "itIT" then
    local I = {
        TAB = "Miglioramenti",
        TITLE = "Miglioramenti dell'equipaggiamento in vendita",

        SCAN = "Scansiona",
        STOP = "Ferma",
        BUY = "Compra",
        AFFORD = "Solo ciò che posso permettermi",
        TOP = "Top %d per slot",
        TOP_TIP = "Fino a %d opzioni per slot, dal miglioramento più forte al più conveniente. Un oggetto viene escluso quando uno più forte costa uguale o meno per punto.",
        TOP_OF = "%d di %d",
        TOP_OF_ABOUT = "%d di circa %d",
        SCALE = "Formula di Pawn:",
        SCALE_TIP = "La formula di Pawn usata per valutare gli oggetti. Le formule si attivano e si modificano in Pawn (/pawn).",

        COL_ITEM = "Oggetto",
        COL_PICK = "Scelta",
        COL_UPGRADE = "Miglioramento",
        COL_PRICE = "Acquisto",
        COL_PER = "Per punto",

        PICK_UPGRADE = "Il più forte",
        PICK_VALUE = "Il più conveniente",
        PICK_BOTH = "Migliore in entrambi",

        NEW = "nuovo",

        HINT = "Premi «Scansiona». L'elenco mostrerà l'equipaggiamento in vendita alla Casa d'Aste che puoi indossare subito e che, secondo la formula di Pawn «%s», ha un punteggio più alto di quello che indossi.",
        ST_BROWSE = "Lettura dell'elenco delle aste: %d righe",
        ST_SCORE = "Valutazione degli oggetti: %d di %d",
        ST_VERIFY = "Verifica dei prezzi di acquisto diretto: %d di %d",
        ST_LEFT = ", mancano circa %s",
        ST_BUYCHECK = "Controllo che l'oggetto sia ancora in vendita…",
        ST_DONE = "Miglioramenti: %d, slot: %d.",
        ST_DONE_HIDDEN = "Miglioramenti: %d, slot: %d. Troppo cari per te: altri %d.",
        ST_NONE = "Al momento non ci sono miglioramenti in vendita con un prezzo di acquisto diretto.",
        ST_NONE_AFFORD = "Niente che tu possa permetterti. Miglioramenti che costano più di quanto possiedi: %d.",
        ST_PARTIAL = "La scansione si è fermata in anticipo, quindi l'elenco potrebbe essere incompleto.",
        ST_STOPPED = "Scansione interrotta.",
        ST_INTERRUPTED = "Un'altra ricerca ha sostituito l'elenco delle aste, quindi la scansione si è fermata. Premi di nuovo «Scansiona».",
        ST_AGE = "Scansione effettuata %s fa.",

        ERR_PAWN_API = "Pawn è caricato, ma manca la sua funzione %s. Aggiorna Pawn.",
        ERR_PAWN_NOT_READY = "Pawn non ha ancora finito di caricarsi. Riprova tra un attimo.",
        ERR_NO_SCALE = "Nessuna formula di Pawn è attiva per questo personaggio. Apri Pawn (/pawn) e attivane una.",
        ERR_AH_CLOSED = "Apri prima la Casa d'Aste.",
        ERR_BROWSE = "La Casa d'Aste non ha risposto alla ricerca. Riprova.",
        ERR_BUSY = "Attendi la fine della scansione.",

        STATS = "Ultima scansione: %d s. Elenco delle aste %d s (richieste: %d, righe: %d). Valutazione %d s (miglioramenti per punteggio: %d). Prezzi %d s (ricerche di oggetti: %d, pagine extra: %d, senza risposta: %d; non necessarie per l'elenco: %d).",
        STATS_NONE = "Nessuna scansione finora.",

        TT_SCORE = "Punteggio Pawn: %s, il tuo: %s (+%s)",
        TT_SCORE_EMPTY = "Punteggio Pawn: %s, lo slot è vuoto",
        TT_REPLACES = "Sostituisce: %s",
        TT_COST = "Costo per punto: %s",
        TT_EFFECTS = "Ha effetti che Pawn non valuta.",
        TT_OFFHAND_EMPTY = "La tua mano secondaria resterà vuota.",
        TT_BOTH_HANDS = "Occupa entrambe le mani.",
        TT_MORE = "Altre aste a un prezzo più alto: %d.",
        TT_MORE_SOME = "Ce ne sono altri in vendita a un prezzo più alto.",
        TT_CANT_AFFORD = "Ti mancano %s.",

        MSG_GONE = "%s non è più in vendita.",
        MSG_PRICE = "%s ora costa %s (prima %s).",
        MSG_BOUGHT = "Hai comprato %s per %s. Arriverà per posta.",
        MSG_CANT_AFFORD = "Non puoi permettertelo.",

        HEAD = "Testa", NECK = "Collo", SHOULDER = "Spalle", BACK = "Schiena", CHEST = "Torso",
        WRIST = "Polsi", HANDS = "Mani", WAIST = "Fianchi", LEGS = "Gambe", FEET = "Piedi",
        FINGER = "Dito", TRINKET = "Monile", MAINHAND = "Mano primaria", OFFHAND = "Mano secondaria", RANGED = "A distanza",

        INVTYPE_WEAPON = "A una mano", INVTYPE_2HWEAPON = "A due mani", INVTYPE_WEAPONMAINHAND = "Mano primaria",
        INVTYPE_WEAPONOFFHAND = "Mano secondaria", INVTYPE_SHIELD = "Mano secondaria", INVTYPE_HOLDABLE = "Accessorio",
    }
    for k, v in pairs(I) do L[k] = v end
end

ns.L =setmetatable(L, { __index = function(_, k) return k end })
