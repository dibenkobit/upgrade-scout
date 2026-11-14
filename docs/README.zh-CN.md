# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout 图标" width="128" align="right">

**在拍卖行中找出比你身上更好、而且你买得起的装备。** 一款用于《魔兽世界》：“无限”（World of Warcraft Forever）的插件。

**[在 CurseForge 下载](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · 简体中文 · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

打开拍卖行，点击**装备提升**标签页，然后按**扫描**。你会得到一份比你身上更好的装备列表，按部位排列，并标有价格。在想要的装备上按**购买**即可。

## 功能

- 用自己的属性权重给装备评分，每个天赋系各有一套，由 [wowsims/forever](https://github.com/wowsims/forever) 模拟器算出。不需要 Pawn。
- 只显示你现在能装备、也买得起的装备。
- 在每个部位标出两件装备。**最大提升**是最强的那件。**最高性价比**是每点提升花费最少的那件。
- **预算内的最佳组合**会选出一组提升：用你全部的金币，或你输入的金额，合起来提升最多。
- **消耗品**标签页列出你能使用的药水、药剂、食物和绷带，对你的角色最有用的排在前面。
- 两个标签页也都能为你的其他角色使用。

支持所有职业和等级。支持英语、简体中文、繁体中文、德语、俄语、法语、西班牙语、巴西葡萄牙语和韩语。

## 安装

**[通过 CurseForge 安装](https://www.curseforge.com/wow/addons/upgrade-scout)**

CurseForge 客户端会帮你装好一切。

你需要《魔兽世界》：“无限”（World of Warcraft Forever，1.60.1），不需要其他插件。

手动安装：

1. 从 [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) 或 [GitHub 发布页](https://github.com/dibenkobit/upgrade-scout/releases)下载 `UpgradeScout-<版本>-forever.zip`。
2. 解压到 `World of Warcraft\_forever_\Interface\AddOns`。
3. 重启游戏。

## 须知

- 物品的评分是它各项属性乘以方案中对应权重之和。方案在**方案**下拉列表中选择，一开始选的是适合你职业的那个，你可以改选自己天赋系的方案。
- 权重是按60级角色计算的，所以只是近似值。60级以下，命中、暴击、急速和精准的价值会打折扣，这是按练级角色模拟得出的。
- 耐力（坦克除外），以及治疗者的智力、精神和法力回复，是手动设定的：伤害模拟无法衡量生存或法力耗尽的代价。
- 方案名称后面的 `~` 表示这个天赋系还没有模拟，权重是估算的。
- 价格都是一口价。只能竞标的拍卖会被跳过。
- **每个部位前5件**让列表保持简短。关闭它可以看到所有提升，但扫描会更久，在繁忙的拍卖行里可能要几分钟。
- **提升**一栏用百分比表示这件装备比它要替换的那件好多少。**新增**表示该部位是空的。显示分数（如 `+6 分`）表示你在那里穿的装备对你的方案毫无用处。
- 名称后面的黄色 `*` 表示这件装备有评分没有算进去的效果。
- 生命药水和法力药水没有评分：没有哪个权重能给“恢复700点生命值”算分。
- “猛虎之”靴子和“巨鲸之”靴子是不同的物品，价格也不同。游戏的“出售”标签页把它们放在同一个列表里，所以那里的最低价可能是另一件物品的。

## 为其他角色购买

1. 在装了插件的情况下登录一次另一个角色。插件会记下它的装备、等级和技能。
2. 用站在拍卖行的角色，在**方案**下拉列表中选择另一个角色的方案，然后按**扫描**。

现在列表是为那个角色生成的。付钱的仍然是你正在玩的角色。

在邮箱处把买到的装备从邮件中取出。邮件窗口下方的按钮会把它们放进一封寄给那个角色的信里。检查一下信，然后按**发送**。消耗品需要你自己寄。

插件记住的是你上次玩那个角色时的状态。它升级或换了装备之后，请再登录一次。

## 命令

- `/upscout` 打开“装备提升”标签页。拍卖行必须处于打开状态。
- `/upscout stats` 显示上次扫描用了多久。
- `/upscout stats` 加上一件物品（按住Shift点击物品，把它放进聊天输入框）会列出这件物品的每项属性、它在方案中的权重以及合计。
- `/upscout forget 名字` 把已删除的角色从列表中移除。

## 开发

测试和发布方法见[英文版](../README.md#development)。

## 许可

保留所有权利，见 [LICENSE](../LICENSE)。属性权重由 [wowsims/forever](https://github.com/wowsims/forever) 算出，60级以下的折扣由 [MythicSim](https://github.com/sage3648/mythicsim-forever-engine) 算出，两者都采用 MIT 许可。
