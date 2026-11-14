# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout Logo" width="128" align="right">

**Findet im Auktionshaus Ausrüstung, die besser ist als deine und die du dir leisten kannst.** Ein Addon für World of Warcraft Forever.

**Auf [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) oder [Wago](https://addons.wago.io/addons/upgrade-scout) herunterladen**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · Deutsch · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Öffne das Auktionshaus, klicke auf den Tab **Verbesserungen** und drücke **Scannen**. Du bekommst
eine Liste mit Ausrüstung, die besser ist als das, was du trägst, Slot für Slot und mit Preisen.
Drücke **Kaufen** bei dem Gegenstand, den du willst.

## Was es kann

- Bewertet Ausrüstung mit eigenen Gewichten für jeden Talentbaum, berechnet mit dem Simulator
  [wowsims/forever](https://github.com/wowsims/forever). Pawn wird nicht gebraucht.
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

**Über [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) oder [Wago](https://addons.wago.io/addons/upgrade-scout) installieren**

Die App von CurseForge oder Wago erledigt alles für dich.

Du brauchst World of Warcraft Forever (1.60.1). Ein anderes Addon ist nicht nötig.

Von Hand:

1. Lade `UpgradeScout-<Version>-forever.zip` von [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout), [Wago](https://addons.wago.io/addons/upgrade-scout)
   oder von den [GitHub-Releases](https://github.com/dibenkobit/upgrade-scout/releases) herunter.
2. Entpacke die Datei nach `World of Warcraft\_forever_\Interface\AddOns`.
3. Starte das Spiel neu.

## Gut zu wissen

- Die Wertung eines Gegenstands ist die Summe seiner Werte, jeder mal sein Gewicht im Profil. Das
  Profil wählst du in der Liste **Profil**; anfangs steht dort eines, das zu deiner Klasse passt.
  Wähle das für deinen Talentbaum.
- Die Gewichte sind für einen Charakter der Stufe 60 berechnet, also eine Näherung. Unter Stufe 60
  zählen Treffer, kritische Treffer, Tempo und Waffenkunde weniger, wie Simulationen von Charakteren
  beim Leveln zeigen.
- Ausdauer (außer bei Tanks) und bei Heilern Intelligenz, Willenskraft und Manaregeneration sind von Hand festgelegt: Eine Schadenssimulation kann nicht zeigen, was Überleben oder ein leerer Manavorrat kostet.
- Rüstung, Blockwert, Verteidigung, Ausweichen und Parieren zählen in jedem Profil: im Verhältnis zur Ausdauer so viel, wie sie dem Tank im Simulator nützen.
- Ein `~` hinter dem Namen eines Profils heißt: Für diesen Baum gibt es noch
  keine Simulation, seine Gewichte sind geschätzt.
- Die Preise sind Sofortkaufpreise. Auktionen, auf die man nur bieten kann, werden übersprungen.
- **Top 5 pro Slot** hält die Liste kurz. Schalte es aus, um jede Verbesserung zu sehen. Der Scan
  dauert dann länger, in einem vollen Auktionshaus bis zu ein paar Minuten.
- **Verbesserung** zeigt in Prozent, wie viel besser ein Gegenstand ist als der, den er ersetzt.
  **Neu** heißt: Der Slot ist leer. Punkte wie `+6 Pkt.` heißen: Was du dort trägst, bringt
  deinem Profil nichts.
- Fahre mit der Maus über einen Gegenstand, um die Verbesserung für jedes Profil deiner Klasse zu sehen. Das gewählte steht in Gold.
- Ein gelbes `*` hinter dem Namen heißt: Der Gegenstand hat Effekte, die die Wertung nicht mitzählt.
- Heil- und Manatränke haben keine Wertung: Kein Gewicht macht aus „stellt 700 Gesundheit wieder her“
  eine Zahl.
- Stiefel „des Tigers“ und Stiefel „des Wals“ sind verschiedene Gegenstände mit verschiedenen
  Preisen. Der Tab „Verkaufen“ im Spiel zeigt sie alle in einer Liste. Der niedrigste Preis dort
  kann also zu einem anderen Gegenstand gehören.

## Für einen anderen Charakter kaufen

1. Logge dich einmal mit dem anderen Charakter ein, während das Addon installiert ist. Das Addon
   merkt sich seine Ausrüstung, seine Stufe und seine Fertigkeiten.
2. Wähle mit dem Charakter im Auktionshaus das Profil des anderen Charakters in der Liste
   **Profil** und drücke **Scannen**.

Die Liste gilt jetzt für diesen Charakter. Es bezahlt weiterhin der Charakter, den du gerade spielst.

Hol die gekaufte Ausrüstung am Briefkasten aus der Post. Ein Button unter dem Postfenster legt sie
dann in einen Brief an diesen Charakter. Prüfe den Brief und drücke **Senden**. Verbrauchsgüter
schickst du selbst.

Das Addon kennt den anderen Charakter so, wie er war, als du ihn zuletzt gespielt hast. Logge dich
wieder mit ihm ein, wenn er eine Stufe aufgestiegen ist oder neue Ausrüstung trägt.

## Befehle

- `/upscout` öffnet den Tab „Verbesserungen“. Das Auktionshaus muss offen sein.
- `/upscout stats` zeigt, wie lange der letzte Scan gedauert hat.
- `/upscout stats` und ein Gegenstand (per Umschalt-Klick in die Chatzeile) zeigt jeden Wert des
  Gegenstands, sein Gewicht im Profil und was zusammenkommt.
- `/upscout forget Name` entfernt einen gelöschten Charakter aus der Liste.

## Entwicklung

Tests und Releases sind in der [englischen Version](../README.md#development) beschrieben.

## Lizenz

Alle Rechte vorbehalten, siehe [LICENSE](../LICENSE). Die Gewichte wurden mit
[wowsims/forever](https://github.com/wowsims/forever) berechnet, ihr Anteil unter Stufe 60 mit [MythicSim](https://github.com/sage3648/mythicsim-forever-engine).
Beide stehen unter der MIT-Lizenz.
