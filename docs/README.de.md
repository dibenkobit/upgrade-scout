# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout Logo" width="128" align="right">

**Findet im Auktionshaus Ausrüstungsverbesserungen und Verbrauchsgüter, die du benutzen und dir leisten kannst.** Ein Addon für World of Warcraft Forever.

**Auf [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) oder [Wago](https://addons.wago.io/addons/upgrade-scout) herunterladen**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · Deutsch · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Öffne das Auktionshaus, klicke auf den Tab **Verbesserungen** und drücke **Scannen**. Du bekommst
eine Liste mit Ausrüstung, die besser ist als das, was du trägst, Slot für Slot und mit Preisen.
Drücke **Kaufen** bei dem Gegenstand, den du willst.

Der Tab **Verbrauchbares** macht dasselbe für Tränke, Elixiere, Fläschchen, Essen, Verbände und
Öle. Er zeigt, was dein Charakter benutzen kann, und bewertet, was jedes davon bringt.
**Das Beste für mich** behält eins von jeder Art: das, was dir am meisten bringt, zum niedrigsten
Preis.

Außerhalb des Auktionshauses zeigt der Tooltip jedes Gegenstands, wie viel besser er ist als das,
was du trägst: in deinen Taschen, in der Beute, in einer Questbelohnung und in einem Chat-Link.

## Was es kann

- Der Scan zeigt nur, was du jetzt anlegen und bezahlen kannst.
- Der Tab **Verbrauchbares** zeigt Tränke, Elixiere, Fläschchen, Essen, Verbände und Öle, die du
  benutzen kannst. Das Nützlichste für deinen Charakter steht oben. Was dir nichts nützt, wird
  ausgelassen.
- Markiert in jedem Slot zwei Gegenstände. **Beste Verbesserung** ist der stärkste.
  **Beste Preis-Leistung** ist der günstigste pro Punkt Verbesserung.
- Jede Zeile hat zwei Preise: den **Sofortkauf** und die **Nettokosten**, also was dich ein
  Gegenstand am Ende kostet: der Sofortkauf abzüglich dessen, was ein Händler dafür zahlt, wenn du
  ihn nicht mehr brauchst. Für 4 Silber gekauft und für 3 verkauft, hat er dich 1 gekostet.
- **Bestes Set für** wählt die Verbesserungen, die zusammen am meisten für dein Gold bringen, oder
  für einen Betrag, den du eintippst.
- Das Menü **Filter** grenzt die Liste ein. **Beste Rüstungsart für die Klasse** lässt Rüstung
  weg, die leichter ist als die schwerste, die dein Charakter trägt. **Verbesserung ab** lässt
  Verbesserungen weg, die kleiner sind als der Prozentwert, den du eintippst.
- Kauft auch für deine anderen Charaktere ein. Ein Button am Briefkasten legt die gekaufte
  Ausrüstung in einen Brief an sie.
- Der Tooltip jedes Gegenstands zeigt, wie viel besser er ist als das, was du trägst, für jeden
  Talentbaum deiner Klasse, etwa Waffen, Furor und Schutz beim Krieger. Im Fenster des Addons
  kannst du eine Zeile behalten, die für deinen Baum, und wählen, wo die Zeilen erscheinen: in
  den Tabs des Addons im Auktionshaus, im Rest des Spiels oder nirgends.
- Ein grüner Pfeil auf dem Symbol eines Gegenstands in deinen Taschen oder der Bank heißt: eine
  Verbesserung, die du jetzt anlegen kannst. Ein grauer: eine Verbesserung, sobald du ihre Stufe
  erreichst.
- Funktioniert gleich nach der Installation. In der Liste **Profil** steht anfangs der Talentbaum,
  in dem du die meisten Punkte hast.
- Beim ersten Einloggen zeigt ein Fenster, was das Addon macht. Dort kannst du die Zeilen im
  Tooltip und die Pfeile in den Taschen abschalten. Die Schaltfläche des Addons an der Minikarte
  öffnet es wieder.
- Bewertet Ausrüstung mit eigenen Gewichten für jeden Talentbaum, berechnet mit dem Simulator
  [wowsims/forever](https://github.com/wowsims/forever). Ein anderes Addon ist nicht nötig.
- Du nutzt Pawn? Wähle im Fenster des Addons **Pawn**, dann wird Ausrüstung nach deinen
  Bewertungsprofilen in Pawn bewertet statt nach den Gewichten des Addons. Die Listen und die Pfeile
  in den Taschen richten sich danach, die Zeilen im Tooltip schreibt Pawn selbst.

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
  Profil wählst du in der Liste **Profil**; anfangs steht dort der Talentbaum, in dem du die
  meisten Punkte hast. Du kannst einen anderen wählen.
- Die Gewichte sind für einen Charakter der Stufe 60 berechnet, also eine Näherung. Unter Stufe 60
  zählen Treffer, kritische Treffer, Tempo und Waffenkunde weniger, wie Simulationen von Charakteren
  beim Leveln zeigen.
- Ausdauer (außer bei Tanks) und bei Heilern Intelligenz, Willenskraft und Manaregeneration sind von Hand festgelegt: Eine Schadenssimulation kann nicht zeigen, was Überleben oder ein leerer Manavorrat kostet.
- Rüstung, Blockwert, Verteidigung, Ausweichen und Parieren zählen in jedem Profil: im Verhältnis zur Ausdauer so viel, wie sie dem Tank im Simulator nützen.
- Ein `~` hinter dem Namen eines Profils heißt: Für diesen Baum gibt es noch
  keine Simulation, seine Gewichte sind geschätzt.
- Die Preise sind Sofortkaufpreise. Auktionen, auf die man nur bieten kann, werden übersprungen.
- Mit **Preis-Leistung nach Nettokosten** richtet sich **Beste Preis-Leistung** nach den
  Nettokosten statt nach dem Sofortkauf. Was du dir leisten kannst und **Bestes Set für** richten
  sich weiter nach dem Sofortkauf: Den zahlst du.
- **Top 5 pro Slot** hält die Liste kurz. Schalte es aus, um jede Verbesserung zu sehen. Der Scan
  dauert dann länger, in einem vollen Auktionshaus bis zu ein paar Minuten.
- **Verbesserung** zeigt in Prozent, wie viel besser ein Gegenstand ist als der, den er ersetzt.
  **Neu** heißt: Der Slot ist leer. Punkte wie `+6 Pkt.` heißen: Was du dort trägst, bringt
  deinem Profil nichts.
- **Beste Rüstungsart für die Klasse** behält die schwerste Rüstung, die dein Charakter schon
  tragen gelernt hat: Leder beim Jäger, schwere Rüstung, sobald er sie gelernt hat. Umhänge,
  Ringe, Waffen und Schilde bleiben in der Liste. Magier, Priester und Hexenmeister tragen nur
  Stoff: Für sie ändert sich nichts.
- **Verbesserung ab** richtet sich nach dem Prozentwert in der Spalte **Verbesserung**. Ein
  Gegenstand für einen leeren Slot bleibt immer.
- Beide Einstellungen gelten für alle deine Charaktere. Kaufst du für einen anderen Charakter
  ein, bleiben sie, wie sie sind.
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

- `/upscout` öffnet das Fenster des Addons: was es macht und seine Einstellungen. Im Auktionshaus
  öffnet es den Tab „Verbesserungen“.
- `/upscout stats` zeigt, wie lange der letzte Scan gedauert hat.
- `/upscout stats` und ein Gegenstand (per Umschalt-Klick in die Chatzeile) zeigt jeden Wert des
  Gegenstands, sein Gewicht im Profil und was zusammenkommt.
- `/upscout forget Name` entfernt einen gelöschten Charakter aus der Liste.

## Entwicklung

Tests und Releases sind in der [englischen Version](DEVELOPMENT.md) beschrieben.

## Lizenz

Alle Rechte vorbehalten, siehe [LICENSE](../LICENSE). Die Gewichte wurden mit
[wowsims/forever](https://github.com/wowsims/forever) berechnet, ihr Anteil unter Stufe 60 mit [MythicSim](https://github.com/sage3648/mythicsim-forever-engine).
Beide stehen unter der MIT-Lizenz.
