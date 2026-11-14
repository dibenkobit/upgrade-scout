# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout 圖示" width="128" align="right">

**在拍賣場中找出比你身上更好、而且你買得起的裝備。** 一款用於 World of Warcraft Forever 的插件。

**[在 CurseForge 下載](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · 繁體中文 · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

打開拍賣場，點擊**裝備提升**分頁，然後按**掃描**。你會得到一份比你身上更好的裝備列表，按部位排列，並標有價格。在想要的裝備上按**購買**即可。

## 功能

- 用自己的屬性權重給裝備評分，每個天賦系各有一套，由 [wowsims/forever](https://github.com/wowsims/forever) 模擬器算出。不需要 Pawn。
- 只顯示你現在能裝備、也買得起的裝備。
- 在每個部位標出兩件裝備。**最大提升**是最強的那件。**最划算**是每點提升花費最少的那件。
- **預算內的最佳組合**會選出一組提升：用你全部的金幣，或你輸入的金額，合起來提升最多。
- **消耗品**分頁列出你能使用的藥水、藥劑、食物和繃帶，對你的角色最有用的排在前面。
- 兩個分頁也都能為你的其他角色使用。

支援所有職業和等級。支援英語、簡體中文、繁體中文、德語、俄語、法語、西班牙語、巴西葡萄牙語和韓語。

## 安裝

**[透過 CurseForge 安裝](https://www.curseforge.com/wow/addons/upgrade-scout)**

CurseForge 應用程式會幫你裝好一切。

你需要 World of Warcraft Forever (1.60.1)，不需要其他插件。

手動安裝：

1. 從 [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) 或 [GitHub 發布頁](https://github.com/dibenkobit/upgrade-scout/releases)下載 `UpgradeScout-<版本>-forever.zip`。
2. 解壓縮到 `World of Warcraft\_forever_\Interface\AddOns`。
3. 重新啟動遊戲。

## 須知

- 物品的評分是它各項屬性乘以方案中對應權重之和。方案在**方案**下拉列表中選擇，一開始選的是適合你職業的那個，你可以改選自己天賦系的方案。列表的滑鼠提示會說明權重的來源。
- 權重是按60級角色計算的，所以只是近似值。60級以下，命中、致命一擊、加速和熟練的價值會打折扣，這是按練級角色模擬得出的。
- 耐力（坦克除外），以及治療者的智力、精神和法力恢復，是手動設定的：傷害模擬無法衡量生存或法力耗盡的代價。
- 方案名稱後面的 `~` 表示這個天賦系還沒有模擬，權重是估算的。
- 價格都是直購價。只能競標的拍賣會被跳過。
- **每個部位前5件**讓列表保持簡短。關閉它可以看到所有提升，但掃描會更久，在繁忙的拍賣場裡可能要幾分鐘。
- **提升**一欄用百分比表示這件裝備比它要取代的那件好多少。**新增**表示該部位是空的，或者你在那裡穿的裝備對你的方案毫無用處。
- 名稱後面的黃色 `*` 表示這件裝備有評分沒有算進去的效果。
- 生命藥水和法力藥水沒有評分：沒有哪個權重能給「恢復700點生命力」算分。
- 「猛虎之」靴子和「巨鯨之」靴子是不同的物品，價格也不同。遊戲的「賣出」分頁把它們放在同一個列表裡，所以那裡的最低價可能是另一件物品的。

## 為其他角色購買

1. 在裝了插件的情況下登入一次另一個角色。插件會記下它的裝備、等級和技能。
2. 用站在拍賣場的角色，在**方案**下拉列表中選擇另一個角色的方案，然後按**掃描**。

現在列表是為那個角色產生的。付錢的仍然是你正在玩的角色。

在郵箱處把買到的裝備從信件中取出。信件視窗下方的按鈕會把它們放進一封寄給那個角色的信裡。檢查一下信，然後按**發送**。消耗品需要你自己寄。

插件記住的是你上次玩那個角色時的狀態。它升級或換了裝備之後，請再登入一次。

## 指令

- `/upscout` 打開「裝備提升」分頁。拍賣場必須處於打開狀態。
- `/upscout stats` 顯示上次掃描用了多久。
- `/upscout stats` 加上一件物品（按住Shift點擊物品，把它放進聊天輸入框）會列出這件物品的每項屬性、它在方案中的權重以及合計。
- `/upscout forget 名字` 把已刪除的角色從列表中移除。

## 開發

測試和發布方法見[英文版](../README.md#development)。

## 授權

保留所有權利，見 [LICENSE](../LICENSE)。屬性權重由 [wowsims/forever](https://github.com/wowsims/forever) 算出，60級以下的折扣由 [MythicSim](https://github.com/sage3648/mythicsim-forever-engine) 算出，兩者都採用 MIT 授權。
