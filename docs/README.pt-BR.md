# Upgrade Scout

<img src="logo/logo.png" alt="Logo do Upgrade Scout" width="128" align="right">

**Encontra na Casa de Leilões as melhorias de equipamento e os consumíveis que você pode usar e que cabem no seu bolso.** Um addon para World of Warcraft Forever.

**Baixar no [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) ou no [Wago](https://addons.wago.io/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · Português · [한국어](README.ko.md)

Abra a Casa de Leilões, clique na aba **Melhorias** e aperte **Escanear**. Você recebe uma lista de
equipamentos melhores do que os que está usando, espaço por espaço, com os preços. Aperte
**Comprar** no item que quiser.

A aba **Consumíveis** faz o mesmo com poções, elixires, frascos, comida, bandagens e óleos. Ela
mostra os que o seu personagem pode usar e avalia o que cada um acrescenta. **O melhor para mim**
deixa um de cada tipo: o que mais acrescenta a você, pelo menor preço.

Fora da Casa de Leilões, a dica de qualquer item mostra quanto ele é melhor do que o que você usa:
nas bolsas, no saque, numa recompensa de missão e num link do chat.

## O que ele faz

- O escaneamento mostra só o que você pode equipar agora e pagar.
- A aba **Consumíveis** mostra poções, elixires, frascos, comida, bandagens e óleos que você pode
  usar. Primeiro, os mais úteis para o seu personagem. O que não serve para você fica de fora.
- Marca dois itens em cada espaço. **Maior melhoria** é o mais forte. **Melhor custo-benefício** é
  o mais barato por ponto de melhoria.
- Cada linha tem dois preços: o **Arremate** e o **Custo líquido**, quanto um item custa no fim das
  contas: o arremate menos o que um mercador paga por ele quando você não precisar mais dele.
  Comprado por 4 de prata e vendido por 3, custou 1.
- **Melhor conjunto por** escolhe as melhorias que, juntas, rendem mais pelo seu ouro ou por um
  valor que você digitar.
- O menu **Filtros** enxuga a lista. **Melhor tipo de armadura da classe** deixa de fora as
  armaduras mais leves que a mais pesada que o seu personagem usa. **Melhoria de pelo menos**
  deixa de fora as melhorias menores que a porcentagem que você digitar.
- Compra também para os seus outros personagens. Um botão na caixa de correio coloca os
  equipamentos comprados numa carta para eles.
- A dica de qualquer item mostra quanto ele é melhor do que o que você usa, para cada árvore de
  talentos da sua classe, como Armas, Fúria e Proteção para um guerreiro. Na janela do addon
  dá para deixar uma linha só, a da sua árvore, e escolher onde as linhas aparecem: nas abas
  do addon na Casa de Leilões, no resto do jogo ou em lugar nenhum.
- Uma seta verde no ícone de um item nas bolsas ou no banco indica uma melhoria que você pode
  equipar agora. Uma cinza: uma melhoria assim que você chegar ao nível dela.
- Funciona logo depois de instalado. A lista **Perfil** já começa na árvore de talentos em que
  você tem mais pontos.
- No primeiro login, uma janela mostra o que o addon faz. Nela você pode desligar as linhas na
  dica de contexto e as setas nas bolsas. O botão do addon ao lado do minimapa abre a janela de
  novo.
- Avalia os equipamentos com pesos próprios para cada árvore de talentos, calculados com o
  simulador [wowsims/forever](https://github.com/wowsims/forever). Nenhum outro addon é necessário.
- Usa o Pawn? Escolha **Pawn** na janela do addon e os equipamentos passam a ser avaliados pelas suas
  escalas do Pawn, e não pelos pesos do addon. As listas e as setas nas bolsas seguem essas escalas,
  e as linhas na dica de contexto são as do próprio Pawn.

Qualquer classe, qualquer nível. Inglês, chinês (simplificado e tradicional), alemão, russo,
francês, espanhol, português do Brasil e coreano.

## Instalação

**Instalar pelo [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) ou pelo [Wago](https://addons.wago.io/addons/upgrade-scout)**

O aplicativo do CurseForge ou do Wago faz tudo por você.

Você precisa do World of Warcraft Forever (1.60.1). Nenhum outro addon é necessário.

Manualmente:

1. Baixe `UpgradeScout-<versão>-forever.zip` no [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout), no [Wago](https://addons.wago.io/addons/upgrade-scout)
   ou nos [lançamentos do GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Descompacte em `World of Warcraft\_forever_\Interface\AddOns`.
3. Reinicie o jogo.

## Bom saber

- A pontuação de um item é a soma dos seus atributos, cada um vezes o seu peso no perfil. O perfil
  se escolhe na lista **Perfil**; no começo ela traz a árvore de talentos em que você tem mais
  pontos. Você pode escolher outra.
- Os pesos são calculados para um personagem de nível 60, então são uma aproximação. Abaixo do
  nível 60, acerto, crítico, aceleração e especialização valem menos, segundo simulações de
  personagens subindo de nível.
- Vigor (exceto para tanques) e, para curadores, intelecto, espírito e regeneração de mana são definidos à mão: uma simulação de dano não mostra quanto custa sobreviver ou ficar sem mana.
- Armadura, valor de bloqueio, defesa, esquiva e aparo contam em todo perfil: em relação ao vigor, tanto quanto ajudam o tanque do simulador.
- Um `~` depois do nome de um perfil quer dizer que essa árvore ainda não tem
  simulação e os pesos dela são estimados.
- Os preços são de arremate. Leilões que só aceitam lances são ignorados.
- Com **Custo-benefício pelo custo líquido** marcado, o **Melhor custo-benefício** segue o custo
  líquido, não o arremate. O que você pode pagar e o **Melhor conjunto por** continuam seguindo o
  arremate: é o que você paga.
- **Top 5 por espaço** deixa a lista curta. Desative para ver todas as melhorias. O escaneamento
  então demora mais, até alguns minutos em uma Casa de Leilões movimentada.
- **Melhoria** diz quanto um item é melhor do que o que ele substitui, em porcentagem. **Novo**
  quer dizer que o espaço está vazio. Pontos, como `+6 pts`, querem dizer que o que você usa ali
  não acrescenta nada ao seu perfil.
- **Melhor tipo de armadura da classe** mantém a armadura mais pesada que o seu personagem já
  aprendeu a usar: couro para um caçador, malha depois que ele aprender. Capas, anéis, armas e
  escudos continuam na lista. Mago, sacerdote e bruxo só usam tecido e não têm essa caixa.
- **Melhoria de pelo menos** segue a porcentagem da coluna **Melhoria**. Um item para um espaço
  vazio sempre fica.
- Cada personagem tem a sua própria caixa **Melhor tipo de armadura da classe** e o seu próprio
  número em **Melhoria de pelo menos**. Ao comprar para outro personagem, você vê e muda os dele.
- Um `*` amarelo depois do nome: o item tem efeitos que a pontuação não conta.
- Poções de vida e de mana não têm pontuação: nenhum peso dá um número para "restaura 700 de vida".
- Botas "do Tigre" e botas "da Baleia" são itens diferentes, com preços diferentes. A aba "Vender"
  do jogo mostra todos em uma lista só, então o menor preço ali pode ser de outro item.

## Comprar para outro personagem

1. Entre uma vez no outro personagem com o addon instalado. O addon guarda o equipamento, o nível
   e as perícias dele.
2. No personagem que está na Casa de Leilões, escolha o perfil do outro personagem na lista
   **Perfil** e aperte **Escanear**.

Agora a lista é para esse personagem. Quem paga continua sendo o personagem com que você está
jogando.

Em uma caixa de correio, retire do correio os equipamentos que comprou. Um botão abaixo da janela
do correio coloca tudo em uma carta para esse personagem. Confira a carta e aperte **Enviar**. Os
consumíveis você mesmo envia.

O addon conhece o outro personagem como ele estava na última vez em que você jogou com ele. Entre
nele de novo quando ele subir de nível ou trocar de equipamento.

## Comandos

- `/upscout` abre a janela do addon: o que ele faz e as configurações. Na Casa de Leilões, abre a
  aba "Melhorias".
- `/upscout stats` mostra quanto tempo levou o último escaneamento.
- `/upscout stats` e um item (Shift-clique nele para colocá-lo na linha do chat) mostra cada
  atributo do item, o peso dele no perfil e quanto somam.
- `/upscout forget Nome` remove da lista um personagem excluído.

## Desenvolvimento

Os testes e a publicação de versões estão descritos na [versão em inglês](DEVELOPMENT.md).

## Licença

Todos os direitos reservados, veja [LICENSE](../LICENSE). Os pesos foram calculados com o
[wowsims/forever](https://github.com/wowsims/forever), e a parte deles abaixo do nível 60 com o [MythicSim](https://github.com/sage3648/mythicsim-forever-engine).
Os dois têm licença MIT.
