# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout 로고" width="128" align="right">

**경매장에서 지금 장비보다 좋고 살 수 있는 장비를 찾아줍니다.** World of Warcraft Forever용 애드온입니다.

**[CurseForge에서 내려받기](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · 한국어 · [繁體中文](README.zh-TW.md)

경매장을 열고 **장비 향상** 탭을 누른 다음 **스캔**을 누르세요. 지금 착용한 것보다 좋은 장비가 부위별로, 가격과 함께 나옵니다. 마음에 드는 장비에서 **구매**를 누르면 됩니다.

## 기능

- [Pawn](https://www.curseforge.com/wow/addons/pawn)으로 장비 점수를 매깁니다. 그래서 목록이 Pawn의 초록색 화살표와 일치합니다.
- 지금 바로 착용할 수 있고 살 수 있는 것만 보여줍니다.
- 부위마다 두 가지를 표시합니다. **최고 향상**은 가장 강한 장비이고, **최고 가성비**는 향상 점수당 가격이 가장 싼 장비입니다.
- **예산 내 최고 세트**는 가진 골드나 입력한 금액으로 함께 샀을 때 가장 많이 향상되는 장비들을 골라줍니다.
- **소비용품** 탭은 쓸 수 있는 물약, 비약, 음식, 붕대를 보여줍니다. 캐릭터에게 가장 쓸모 있는 것이 먼저 나옵니다.
- 두 탭 모두 다른 내 캐릭터용으로도 쓸 수 있습니다.

모든 직업, 모든 레벨. 영어, 중국어 간체, 독일어, 러시아어, 프랑스어, 스페인어, 브라질 포르투갈어, 한국어, 중국어 번체.

## 설치

**[CurseForge에서 설치](https://www.curseforge.com/wow/addons/upgrade-scout)**

CurseForge 앱이 Pawn까지 알아서 설치해 줍니다.

World of Warcraft Forever (1.60.1)와 [Pawn](https://www.curseforge.com/wow/addons/pawn)이 필요합니다. Pawn이 없으면 애드온이 불러와지지 않습니다.

직접 설치하려면:

1. [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)나 [GitHub 릴리스](https://github.com/dibenkobit/upgrade-scout/releases)에서 `UpgradeScout-<버전>-forever.zip`을 내려받으세요.
2. `World of Warcraft\_forever_\Interface\AddOns`에 압축을 푸세요.
3. 게임을 다시 시작하세요.

## 알아 두면 좋은 것

- 가격은 즉시 구입가입니다. 입찰만 받는 경매는 건너뜁니다.
- **부위별 상위 5개**는 목록을 짧게 유지합니다. 끄면 모든 향상이 보입니다. 그러면 스캔이 더 오래 걸리고, 붐비는 경매장에서는 몇 분까지 걸립니다.
- 이름 뒤의 노란색 `*`는 Pawn이 점수를 매기지 못하는 효과가 있다는 뜻입니다.
- 생명력 물약과 마나 물약에는 점수가 없습니다. Pawn에는 “생명력 700 회복”에 해당하는 수치가 없기 때문입니다.
- “호랑이의” 장화와 “고래의” 장화는 가격이 다른 별개의 아이템입니다. 게임의 “판매” 탭은 이들을 한 목록에 모두 보여주므로, 거기 보이는 최저가는 다른 아이템의 가격일 수 있습니다.

## 다른 캐릭터를 위해 사기

1. 애드온을 설치한 상태에서 다른 캐릭터로 한 번 접속하세요. 애드온이 그 캐릭터의 장비, 레벨, 기술을 저장합니다.
2. 경매장에 있는 캐릭터에서 **Pawn 능력치 비율** 목록에 있는 다른 캐릭터의 능력치 비율을 고르고 **스캔**을 누르세요.

이제 목록은 그 캐릭터용입니다. 돈은 여전히 지금 플레이하는 캐릭터가 냅니다.

우체통에서 산 장비를 우편에서 꺼내세요. 우편 창 아래의 버튼이 그 장비를 그 캐릭터에게 보내는 편지에 넣어 줍니다. 편지를 확인하고 **보내기**를 누르세요. 소비용품은 직접 보내야 합니다.

애드온은 다른 캐릭터를 마지막으로 플레이했을 때의 모습으로 기억합니다. 레벨이 오르거나 장비가 바뀌면 다시 접속하세요.

## 명령어

- `/upscout`: “장비 향상” 탭을 엽니다. 경매장이 열려 있어야 합니다.
- `/upscout stats`: 마지막 스캔에 걸린 시간을 보여줍니다.
- `/upscout forget 이름`: 삭제한 캐릭터를 목록에서 지웁니다.

## 개발

테스트와 릴리스 방법은 [영어판](../README.md#development)에 있습니다.

## 라이선스

모든 권리 보유. [LICENSE](../LICENSE)를 보세요. Pawn은 Vger가 만든 별도의 애드온이며 포함되어 있지 않습니다.
