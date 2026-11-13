# Upgrade Scout

<img src="logo/logo.png" alt="Logo do Upgrade Scout" width="128" align="right">

**Encontra na Casa de Leilões equipamentos melhores que os seus e que cabem no seu bolso.** Um addon para World of Warcraft Forever.

**[Baixar no CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [Русский](README.ru.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · Português · [简体中文](README.zh-CN.md)

Abra a Casa de Leilões, clique na aba **Melhorias** e aperte **Escanear**. Você recebe uma lista de
equipamentos melhores do que os que está usando, espaço por espaço, com os preços. Aperte
**Comprar** no item que quiser.

## O que ele faz

- Avalia os equipamentos com o [Pawn](https://www.curseforge.com/wow/addons/pawn), então a lista bate com as
  setas verdes do Pawn.
- Mostra só o que você pode equipar agora e pagar.
- Marca dois itens em cada espaço. **Maior melhoria** é o mais forte. **Melhor custo-benefício** é
  o mais barato por ponto de melhoria.
- **Melhor conjunto por** escolhe as melhorias que, juntas, rendem mais pelo seu ouro ou por um
  valor que você digitar.
- A aba **Consumíveis** mostra poções, elixires, comida e ataduras que você pode usar. Primeiro, os
  mais úteis para o seu personagem.
- As duas abas também funcionam para os seus outros personagens.

Qualquer classe, qualquer nível. Português do Brasil, inglês, russo, alemão, francês, espanhol e
chinês simplificado.

## Instalação

**[Instalar pelo CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

O aplicativo do CurseForge faz tudo por você, inclusive instalar o Pawn.

Você precisa do World of Warcraft Forever (1.60.1) e do [Pawn](https://www.curseforge.com/wow/addons/pawn).
Sem o Pawn, o addon não carrega.

Manualmente:

1. Baixe `UpgradeScout-<versão>-forever.zip` no [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   ou nos [lançamentos do GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Descompacte em `World of Warcraft\_forever_\Interface\AddOns`.
3. Reinicie o jogo.

## Bom saber

- Os preços são de arremate. Leilões que só aceitam lances são ignorados.
- **Top 5 por espaço** deixa a lista curta. Desative para ver todas as melhorias. O escaneamento
  então demora mais, até alguns minutos em uma Casa de Leilões movimentada.
- Um `*` amarelo depois do nome: o item tem efeitos que o Pawn não sabe avaliar.
- Poções de vida e de mana não têm pontuação: o Pawn não tem um número para "restaura 700 de vida".
- Botas "do Tigre" e botas "da Baleia" são itens diferentes, com preços diferentes. A aba "Vender"
  do jogo mostra todos em uma lista só, então o menor preço ali pode ser de outro item.

## Comprar para outro personagem

1. Entre uma vez no outro personagem com o addon instalado. O addon guarda o equipamento, o nível
   e as perícias dele.
2. No personagem que está na Casa de Leilões, escolha a escala do outro personagem na lista
   **Escala do Pawn** e aperte **Escanear**.

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
- `/upscout forget Nome` remove da lista um personagem excluído.

## Desenvolvimento

Os testes e a publicação de versões estão descritos na [versão em inglês](../README.md#development).

## Licença

Todos os direitos reservados, veja [LICENSE](../LICENSE). O Pawn é um addon separado, de Vger, e não
está incluído.
