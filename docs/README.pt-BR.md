# Upgrade Scout

<img src="logo/logo.png" alt="Logo do Upgrade Scout" width="128" align="right">

**Encontra na Casa de Leilões equipamentos melhores que os seus e que cabem no seu bolso.** Um addon para World of Warcraft Forever.

**[Baixar no CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · Português · [한국어](README.ko.md)

Abra a Casa de Leilões, clique na aba **Melhorias** e aperte **Escanear**. Você recebe uma lista de
equipamentos melhores do que os que está usando, espaço por espaço, com os preços. Aperte
**Comprar** no item que quiser.

## O que ele faz

- Avalia os equipamentos com pesos próprios para cada árvore de talentos, calculados com o
  simulador [wowsims/forever](https://github.com/wowsims/forever). Não precisa do Pawn.
- Mostra só o que você pode equipar agora e pagar.
- Marca dois itens em cada espaço. **Maior melhoria** é o mais forte. **Melhor custo-benefício** é
  o mais barato por ponto de melhoria.
- **Melhor conjunto por** escolhe as melhorias que, juntas, rendem mais pelo seu ouro ou por um
  valor que você digitar.
- A aba **Consumíveis** mostra poções, elixires, comida e ataduras que você pode usar. Primeiro, os
  mais úteis para o seu personagem.
- As duas abas também funcionam para os seus outros personagens.

Qualquer classe, qualquer nível. Inglês, chinês (simplificado e tradicional), alemão, russo,
francês, espanhol, português do Brasil e coreano.

## Instalação

**[Instalar pelo CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

O aplicativo do CurseForge faz tudo por você.

Você precisa do World of Warcraft Forever (1.60.1). Nenhum outro addon é necessário.

Manualmente:

1. Baixe `UpgradeScout-<versão>-forever.zip` no [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   ou nos [lançamentos do GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Descompacte em `World of Warcraft\_forever_\Interface\AddOns`.
3. Reinicie o jogo.

## Bom saber

- A pontuação de um item é a soma dos seus atributos, cada um vezes o seu peso no perfil. O perfil
  se escolhe na lista **Perfil**; no começo ela traz um que combina com a sua classe. Escolha o da
  sua árvore de talentos.
- Os pesos são calculados para um personagem de nível 60, então são uma aproximação. Abaixo do
  nível 60, acerto, crítico, aceleração e especialização valem menos, segundo simulações de
  personagens subindo de nível.
- Vigor (exceto para tanques) e, para curadores, intelecto, espírito e regeneração de mana são definidos à mão: uma simulação de dano não mostra quanto custa sobreviver ou ficar sem mana.
- Armadura, valor de bloqueio, defesa, esquiva e aparo contam em todo perfil: em relação ao vigor, tanto quanto ajudam o tanque do simulador.
- Um `~` depois do nome de um perfil quer dizer que essa árvore ainda não tem
  simulação e os pesos dela são estimados.
- Os preços são de arremate. Leilões que só aceitam lances são ignorados.
- **Top 5 por espaço** deixa a lista curta. Desative para ver todas as melhorias. O escaneamento
  então demora mais, até alguns minutos em uma Casa de Leilões movimentada.
- **Melhoria** diz quanto um item é melhor do que o que ele substitui, em porcentagem. **Novo**
  quer dizer que o espaço está vazio. Pontos, como `+6 pts`, querem dizer que o que você usa ali
  não acrescenta nada ao seu perfil.
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

- `/upscout` abre a aba "Melhorias". A Casa de Leilões precisa estar aberta.
- `/upscout stats` mostra quanto tempo levou o último escaneamento.
- `/upscout stats` e um item (Shift-clique nele para colocá-lo na linha do chat) mostra cada
  atributo do item, o peso dele no perfil e quanto somam.
- `/upscout forget Nome` remove da lista um personagem excluído.

## Desenvolvimento

Os testes e a publicação de versões estão descritos na [versão em inglês](../README.md#development).

## Licença

Todos os direitos reservados, veja [LICENSE](../LICENSE). Os pesos foram calculados com o
[wowsims/forever](https://github.com/wowsims/forever), e a parte deles abaixo do nível 60 com o [MythicSim](https://github.com/sage3648/mythicsim-forever-engine).
Os dois têm licença MIT.
