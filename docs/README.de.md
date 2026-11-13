# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout Logo" width="128" align="right">

**Findet im Auktionshaus Ausrüstung, die besser ist als deine und die du dir leisten kannst.** Ein Addon für World of Warcraft Forever.

**[Auf CurseForge herunterladen](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · Deutsch · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Öffne das Auktionshaus, klicke auf den Tab **Verbesserungen** und drücke **Scannen**. Du bekommst
eine Liste mit Ausrüstung, die besser ist als das, was du trägst, Slot für Slot und mit Preisen.
Drücke **Kaufen** bei dem Gegenstand, den du willst.

## Was es kann

- Bewertet Ausrüstung mit [Pawn](https://www.curseforge.com/wow/addons/pawn), deshalb passt die Liste zu den
  grünen Pfeilen von Pawn.
- Zeigt nur, was du jetzt anlegen und bezahlen kannst.
- Markiert in jedem Slot zwei Gegenstände. **Beste Verbesserung** ist der stärkste.
  **Beste Preis-Leistung** ist der günstigste pro Punkt Verbesserung.
- **Bestes Set für** wählt die Verbesserungen, die zusammen am meisten für dein Gold bringen, oder
  für einen Betrag, den du eintippst.
- Der Tab **Verbrauchbares** zeigt Tränke, Elixiere, Essen und Verbände, die du benutzen kannst.
  Das Nützlichste für deinen Charakter steht oben.
- Beide Tabs funktionieren auch für deine anderen Charaktere.

Jede Klasse, jede Stufe. Englisch, Chinesisch (vereinfacht und traditionell), Deutsch, Russisch,
Französisch, Spanisch, brasilianisches Portugiesisch und Koreanisch.

## Installation

**[Über CurseForge installieren](https://www.curseforge.com/wow/addons/upgrade-scout)**

Die CurseForge-App erledigt alles für dich, auch Pawn.

Du brauchst World of Warcraft Forever (1.60.1) und [Pawn](https://www.curseforge.com/wow/addons/pawn).
Ohne Pawn lädt das Addon nicht.

Von Hand:

1. Lade `UpgradeScout-<Version>-forever.zip` von [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   oder von den [GitHub-Releases](https://github.com/dibenkobit/upgrade-scout/releases) herunter.
2. Entpacke die Datei nach `World of Warcraft\_forever_\Interface\AddOns`.
3. Starte das Spiel neu.

## Gut zu wissen

- Die Preise sind Sofortkaufpreise. Auktionen, auf die man nur bieten kann, werden übersprungen.
- **Top 5 pro Slot** hält die Liste kurz. Schalte es aus, um jede Verbesserung zu sehen. Der Scan
  dauert dann länger, in einem vollen Auktionshaus bis zu ein paar Minuten.
- Ein gelbes `*` hinter dem Namen heißt: Der Gegenstand hat Effekte, die Pawn nicht bewerten kann.
- Heil- und Manatränke haben keine Wertung: Pawn hat keine Zahl für „stellt 700 Gesundheit wieder her“.
- Stiefel „des Tigers“ und Stiefel „des Wals“ sind verschiedene Gegenstände mit verschiedenen
  Preisen. Der Tab „Verkaufen“ im Spiel zeigt sie alle in einer Liste. Der niedrigste Preis dort
  kann also zu einem anderen Gegenstand gehören.

## Für einen anderen Charakter kaufen

1. Logge dich einmal mit dem anderen Charakter ein, während das Addon installiert ist. Das Addon
   merkt sich seine Ausrüstung, seine Stufe und seine Fertigkeiten.
2. Wähle mit dem Charakter im Auktionshaus die Skala des anderen Charakters in der Liste
   **Pawn-Skala** und drücke **Scannen**.

Die Liste gilt jetzt für diesen Charakter. Es bezahlt weiterhin der Charakter, den du gerade spielst.

Hol die gekaufte Ausrüstung am Briefkasten aus der Post. Ein Button unter dem Postfenster legt sie
dann in einen Brief an diesen Charakter. Prüfe den Brief und drücke **Senden**. Verbrauchsgüter
schickst du selbst.

Das Addon kennt den anderen Charakter so, wie er war, als du ihn zuletzt gespielt hast. Logge dich
wieder mit ihm ein, wenn er eine Stufe aufgestiegen ist oder neue Ausrüstung trägt.

## Befehle

- `/upscout` öffnet den Tab „Verbesserungen“. Das Auktionshaus muss offen sein.
- `/upscout stats` zeigt, wie lange der letzte Scan gedauert hat.
- `/upscout forget Name` entfernt einen gelöschten Charakter aus der Liste.

## Entwicklung

Tests und Releases sind in der [englischen Version](../README.md#development) beschrieben.

## Lizenz

Alle Rechte vorbehalten, siehe [LICENSE](../LICENSE). Pawn ist ein eigenes Addon von Vger und nicht
enthalten.
