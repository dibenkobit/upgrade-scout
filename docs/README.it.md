# Upgrade Scout

<img src="logo/logo.png" alt="Logo di Upgrade Scout" width="128" align="right">

**Trova alla Casa d'Aste equipaggiamento migliore del tuo e che puoi permetterti.** Un addon per World of Warcraft Forever.

**[Scarica da CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [Русский](README.ru.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · Italiano · [简体中文](README.zh-CN.md)

Apri la Casa d'Aste, clicca sulla scheda **Miglioramenti** e premi **Scansiona**. Ottieni un elenco
di equipaggiamento migliore di quello che indossi, slot per slot, con i prezzi. Premi **Compra**
sull'oggetto che vuoi.

## Cosa fa

- Valuta l'equipaggiamento con [Pawn](https://www.curseforge.com/wow/addons/pawn), quindi l'elenco coincide con
  le frecce verdi di Pawn.
- Mostra solo ciò che puoi equipaggiare subito e pagare.
- Segna due oggetti in ogni slot: **Il più forte** e **Il più conveniente**, cioè quello che costa
  meno per punto di miglioramento.
- **Miglior insieme per** sceglie i miglioramenti che, insieme, danno di più per il tuo oro o per
  una somma che scrivi tu.
- La scheda **Consumabili** elenca pozioni, elisir, cibo e bende che puoi usare. Prima i più utili
  per il tuo personaggio.
- Le due schede funzionano anche per gli altri tuoi personaggi.

Qualsiasi classe, qualsiasi livello. Italiano, inglese, russo, tedesco, francese, spagnolo,
portoghese brasiliano e cinese semplificato.

## Installazione

**[Installa da CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

L'app CurseForge fa tutto da sola, Pawn compreso.

Ti servono World of Warcraft Forever (1.60.1) e [Pawn](https://www.curseforge.com/wow/addons/pawn).
Senza Pawn l'addon non si carica.

A mano:

1. Scarica `UpgradeScout-<versione>-forever.zip` da [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   o dalle [release su GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Estrailo in `World of Warcraft\_forever_\Interface\AddOns`.
3. Riavvia il gioco.

## Buono a sapersi

- I prezzi sono prezzi di acquisto immediato. Le aste con la sola offerta vengono saltate.
- **Top 5 per slot** tiene corto l'elenco. Disattivalo per vedere tutti i miglioramenti. La
  scansione allora dura di più, fino a qualche minuto in una Casa d'Aste affollata.
- Un `*` giallo dopo il nome: l'oggetto ha effetti che Pawn non sa valutare.
- Le pozioni di salute e di mana non hanno punteggio: Pawn non ha un numero per «ripristina 700
  punti salute».
- Gli stivali «della Tigre» e gli stivali «della Balena» sono oggetti diversi con prezzi diversi.
  La scheda di vendita del gioco li mostra tutti in un unico elenco, quindi il prezzo più basso lì
  può essere di un altro oggetto.

## Comprare per un altro personaggio

1. Entra una volta con l'altro personaggio, con l'addon installato. L'addon salva il suo
   equipaggiamento, il suo livello e le sue abilità.
2. Con il personaggio che è alla Casa d'Aste, scegli la formula dell'altro personaggio nell'elenco
   **Formula di Pawn** e premi **Scansiona**.

Ora l'elenco è per quel personaggio. A pagare è sempre il personaggio con cui stai giocando.

A una cassetta della posta, ritira dalla posta l'equipaggiamento che hai comprato. Un pulsante
sotto la finestra della posta lo mette allora in una lettera per quel personaggio. Controlla la
lettera e inviala. I consumabili li spedisci tu.

L'addon conosce l'altro personaggio com'era l'ultima volta che ci hai giocato. Entra di nuovo con
lui quando sale di livello o cambia equipaggiamento.

## Comandi

- `/upscout` apre la scheda «Miglioramenti». La Casa d'Aste deve essere aperta.
- `/upscout stats` mostra quanto è durata l'ultima scansione.
- `/upscout forget Nome` toglie dall'elenco un personaggio eliminato.

## Sviluppo

I test e la pubblicazione delle versioni sono descritti nella [versione inglese](../README.md#development).

## Licenza

Tutti i diritti riservati, vedi [LICENSE](../LICENSE). Pawn è un addon separato, di Vger, e non è
incluso.
