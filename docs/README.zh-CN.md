# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout 图标" width="128" align="right">

**在拍卖行中找出比你身上更好、而且你买得起的装备。** 一款用于 World of Warcraft Forever 的插件。

**[在 CurseForge 下载](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [Русский](README.ru.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · 简体中文

打开拍卖行，点击**装备提升**标签页，然后按**扫描**。你会得到一份比你身上更好的装备列表，按部位排列，并标有价格。在想要的装备上按**购买**即可。

## 功能

- 用 [Pawn](https://www.curseforge.com/wow/addons/pawn) 给装备评分，所以列表和 Pawn 的绿色箭头一致。
- 只显示你现在能装备、也买得起的装备。
- 在每个部位标出两件装备。**最大提升**是最强的那件。**最高性价比**是每点提升花费最少的那件。
- **预算内的最佳组合**会选出一组提升：用你全部的金币，或你输入的金额，合起来提升最多。
- **消耗品**标签页列出你能使用的药水、药剂、食物和绷带，对你的角色最有用的排在前面。
- 两个标签页也都能为你的其他角色使用。

支持所有职业和等级。支持简体中文、英语、俄语、德语、法语、西班牙语和巴西葡萄牙语。

## 安装

**[通过 CurseForge 安装](https://www.curseforge.com/wow/addons/upgrade-scout)**

CurseForge 客户端会帮你装好一切，包括 Pawn。

你需要 World of Warcraft Forever (1.60.1) 和 [Pawn](https://www.curseforge.com/wow/addons/pawn)。没有 Pawn，插件不会加载。

手动安装：

1. 从 [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) 或 [GitHub 发布页](https://github.com/dibenkobit/upgrade-scout/releases)下载 `UpgradeScout-<版本>-forever.zip`。
2. 解压到 `World of Warcraft\_forever_\Interface\AddOns`。
3. 重启游戏。

## 须知

- 价格都是一口价。只能竞标的拍卖会被跳过。
- **每个部位前5件**让列表保持简短。关闭它可以看到所有提升，但扫描会更久，在繁忙的拍卖行里可能要几分钟。
- 名称后面的黄色 `*` 表示这件装备有 Pawn 无法评分的效果。
- 生命药水和法力药水没有评分：Pawn 没法给“恢复700点生命值”算分。
- “猛虎之”靴子和“巨鲸之”靴子是不同的物品，价格也不同。游戏的“出售”标签页把它们放在同一个列表里，所以那里的最低价可能是另一件物品的。

## 为其他角色购买

1. 在装了插件的情况下登录一次另一个角色。插件会记下它的装备、等级和技能。
2. 用站在拍卖行的角色，在 **Pawn 属性权重**下拉列表中选择另一个角色的权重，然后按**扫描**。

现在列表是为那个角色生成的。付钱的仍然是你正在玩的角色。

在邮箱处把买到的装备从邮件中取出。邮件窗口下方的按钮会把它们放进一封寄给那个角色的信里。检查一下信，然后按**发送**。消耗品需要你自己寄。

插件记住的是你上次玩那个角色时的状态。它升级或换了装备之后，请再登录一次。

## 命令

- `/upscout` 打开“装备提升”标签页。拍卖行必须处于打开状态。
- `/upscout stats` 显示上次扫描用了多久。
- `/upscout forget 名字` 把已删除的角色从列表中移除。

## 开发

测试和发布方法见[英文版](../README.md#development)。

## 许可

保留所有权利，见 [LICENSE](../LICENSE)。Pawn 是 Vger 开发的独立插件，不包含在内。
