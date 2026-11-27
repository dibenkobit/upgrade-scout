# Upgrade Scout

<img src="logo/logo.png" alt="Upgrade Scout Logo" width="128" align="right">

**Findet im Auktionshaus Ausrüstungsverbesserungen und Verbrauchsgüter, die du benutzen und dir leisten kannst.** Ein Addon für World of Warcraft Forever.

**Auf [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) oder [Wago](https://addons.wago.io/addons/upgrade-scout) herunterladen**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · Deutsch · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Öffne das Auktionshaus, klicke auf den Tab **Verbesserungen** und drücke **Scannen**. Du bekommst
eine Liste mit Ausrüstung, die besser ist als das, was du trägst, Slot für Slot und mit Preisen.
Drücke **Kaufen** bei dem Gegenstand, den du willst.

Der Tab **Verbrauchbares** macht dasselbe für Tränke, Elixiere, Fläschchen, Essen, Verbände und
Öle. Er zeigt, was deinem Charakter etwas bringt, und bewertet es.
**Das Beste für mich** behält eins von jeder Art: das, was dir am meisten bringt, zum niedrigsten
Preis. **Alles, was ich benutzen kann** zeigt auch, was keine Wertung hat: einfaches Essen und
Trinken, Heil- und Manatränke, Verbände.

Außerhalb des Auktionshauses zeigt der Tooltip jedes Gegenstands, wie viel besser er ist als das,
was du trägst: in deinen Taschen, in der Beute, in einer Questbelohnung und in einem Chat-Link.

## Was es kann

- Der Scan zeigt nur, was du jetzt anlegen und bezahlen kannst.
- Der Tab **Verbrauchbares** zeigt Tränke, Elixiere, Fläschchen, Essen und Öle, die deinem
  Charakter etwas bringen. Das Nützlichste steht oben. **Alles, was ich benutzen kann** im Menü
  **Filter** zeigt auch, was keine Wertung hat: einfaches Essen und Trinken, Heil- und
  Manatränke, Verbände.
- Markiert in jedem Slot zwei Gegenstände. **Beste Verbesserung** ist der stärkste.
  **Beste Preis-Leistung** ist der günstigste pro Punkt Verbesserung.
- Jede Zeile hat zwei Preise: den **Sofortkauf** und die **Nettokosten**, also was dich ein
  Gegenstand am Ende kostet: der Sofortkauf abzüglich dessen, was ein Händler dafür zahlt, wenn du
  ihn nicht mehr brauchst. Für 4 Silber gekauft und für 3 verkauft, hat er dich 1 gekostet.
- **Bestes Set für** wählt die Verbesserungen, die zusammen am meisten für dein Gold bringen, oder
  für einen Betrag, den du eintippst.
- Das Menü **Filter** grenzt die Liste ein. **Beste Rüstungsart für die Klasse** lässt Rüstung
  weg, die leichter ist als die schwerste, die dein Charakter trägt. **Verbesserung ab** lässt
  Verbesserungen weg, die kleiner sind als der Prozentwert, den du eintippst. **Sofortkauf bis**
  lässt Gegenstände weg, die mehr kosten als der Betrag, den du eintippst: **Beste
  Verbesserung** ist dann in jedem Slot die beste für diesen Preis. **Ausrüstung höchstens 10
  Stufen unter dem Charakter** lässt Ausrüstung weg, die für Stufen weit unter der deines
  Charakters gemacht ist, und der Scan wird kürzer. **Waffen** legt fest, wie dein Charakter
  seine Hände füllt, mit einer Zweihandwaffe oder mit Einhandwaffe und Schild, und welche
  Waffenarten er angeboten bekommt.
- Kauft auch für deine anderen Charaktere ein. Ein Button am Briefkasten legt die gekaufte
  Ausrüstung in einen Brief an sie.
- Der Tooltip jedes Gegenstands zeigt, wie viel besser er ist als das, was du trägst, für jeden
  Talentbaum deiner Klasse, etwa Waffen, Furor und Schutz beim Krieger. Im Fenster des Addons
  kannst du eine Zeile behalten, die für deinen Baum, und wählen, wo die Zeilen erscheinen: in
  den Tabs des Addons im Auktionshaus, im Rest des Spiels oder nirgends.
- Ein grüner Pfeil auf dem Symbol eines Gegenstands in deinen Taschen oder der Bank heißt: eine
  Verbesserung, die du jetzt anlegen kannst. Ein grauer: eine Verbesserung, sobald du ihre Stufe
  erreichst. Die Pfeile erscheinen auch in den Taschen- und Bankfenstern von EllesmereUI.
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
- Du nutzt Forever Companion? Wähle dort **Forever Companion**, dann wird Ausrüstung nach seinen
  Bewertungsprofilen bewertet. Die Listen richten sich danach, die Zeile im Tooltip und die Pfeile
  in den Taschen kommen von Forever Companion selbst.
- Du nutzt Forever Leveling BiS? Wähle dort **Forever Leveling BiS**, dann wird Ausrüstung so
  bewertet, wie es sie bewertet: für die primäre Spezialisierung, die du dort gewählt hast. Die
  Zeilen im Tooltip und die Pfeile in den Taschen kommen von Forever Leveling BiS selbst.
- Du nutzt GearQuest? Wähle dort **GearQuest**, dann wird Ausrüstung so bewertet, wie es sie
  bewertet: Ein Gegenstand aus seinen Listen bekommt seine eigene Wertung, jeder andere wird
  nach seinen Gewichten bewertet. Die Listen und die Pfeile in den Taschen richten sich danach,
  und für Gegenstände aus seinen Listen schreibt GearQuest die Zeile im Tooltip selbst.

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
- Die Liste erscheint, bevor die Preise geprüft sind. Bis ein Gegenstand geprüft ist, zeigt er
  den niedrigsten Preis unter seinen Auktionen, und der kann sich als Gebot herausstellen. Du
  kannst sofort kaufen: Der Preis wird vor jedem Kauf geprüft.
- Mit **Preis-Leistung nach Nettokosten** richtet sich **Beste Preis-Leistung** nach den
  Nettokosten statt nach dem Sofortkauf. Was du dir leisten kannst und **Bestes Set für** richten
  sich weiter nach dem Sofortkauf: Den zahlst du.
- **Top 5 pro Slot** behält in jedem Slot fünf Gegenstände: die **Beste Verbesserung**, die **Beste
  Preis-Leistung** und die nächstgrößten Verbesserungen. Statt der 5 kannst du eine andere Zahl
  eintippen, von 1 bis 99. Schalte es aus, um jede Verbesserung zu sehen. Alle Preise zu prüfen
  dauert dann länger, in einem vollen Auktionshaus bis zu ein paar Minuten.
- **Schlechtere Angebote ausblenden**, das Häkchen direkt darunter, ist aus, bis du es setzt.
  Es blendet einen Gegenstand aus, wenn es im selben Slot einen anderen gibt, der stärker und
  zugleich das bessere Angebot ist. Beispiel: +30% für 5 Gold und +20% für 4 Gold. Der zweite
  ist schwächer, und du zahlst mehr für das, was er bringt, also wird er ausgeblendet. Es
  bleiben die **Beste Verbesserung**, die **Beste Preis-Leistung** und was dazwischen liegt.
  Ist auch **Top 5 pro Slot** angehakt, werden dessen größte Verbesserungen aus dem genommen,
  was bleibt. Mit diesem Häkchen werden weniger Preise geprüft, nachdem die Liste erschienen
  ist.
- **Verbesserung** zeigt in Prozent, wie viel besser ein Gegenstand ist als der, den er ersetzt.
  **Neu** heißt: Der Slot ist leer. Punkte wie `+6 Pkt.` heißen: Was du dort trägst, bringt
  deinem Profil nichts.
- **Beste Rüstungsart für die Klasse** behält die schwerste Rüstung, die dein Charakter schon
  tragen gelernt hat: Leder beim Jäger, schwere Rüstung, sobald er sie gelernt hat. Umhänge,
  Ringe, Waffen und Schilde bleiben in der Liste. Magier, Priester und Hexenmeister tragen nur
  Stoff und haben dieses Häkchen nicht.
- **Verbesserung ab** richtet sich nach dem Prozentwert in der Spalte **Verbesserung**. Ein
  Gegenstand für einen leeren Slot bleibt immer.
- **Sofortkauf bis** ist die Obergrenze für einen einzelnen Gegenstand. **Bestes Set für** hat
  sein eigenes Budget und richtet sich nicht danach.
- **Ausrüstung höchstens 10 Stufen unter dem Charakter** ist aus, bis du das Häkchen setzt. Der
  Filter lässt Ausrüstung weg, die für eine Stufe gemacht ist, die um mehr als diese Zahl unter
  der deines Charakters liegt. Du kannst eine andere Zahl eintippen, von 1 bis 59. Ein Scan mit
  diesem Filter überspringt solche Ausrüstung ebenfalls und ist deshalb kürzer: je höher deine
  Stufe, desto mehr spart er. Ausrüstung, die keine Stufe verlangt, lässt der Filter in Ruhe:
  Sie steht in der Liste, wenn sie eine Verbesserung ist. Erhöhst du nach einem Scan die Zahl
  oder entfernst das Häkchen, scannt das Addon von selbst erneut. Die Pfeile in den Taschen
  richten sich nicht nach diesem Filter.
- **Waffen** öffnet ein eigenes Menü. **Beliebig** zeigt Einhand- und Zweihandwaffen
  gleichermaßen. **Zweihändig** lässt Einhandwaffen, Schilde und Gegenstände für die Schildhand
  weg. **Einhändig, Schild und Schildhand** lässt Zweihandwaffen weg. Darunter steht ein Häkchen
  für jede Waffenart, die deine Klasse führen kann: Ohne Häkchen bleiben Waffen dieser Art weg.
  Die Pfeile in den Taschen richten sich ebenfalls nach alldem.
- Jedes Profil eines Charakters hat unter **Waffen** seine eigene Auswahl und seine eigenen
  Häkchen: Ein Krieger kann mit Furor Zweihandwaffen nehmen und mit Schutz einen Schild. Über
  dem Menü steht das Profil, das es zeigt, etwa **Profil: Schutz**.
- Eine Waffenart, die dein Charakter nicht erlernt hat, trägt hinter ihrem Namen **(nicht
  erlernt)** und hat kein Häkchen, bis du es setzt. Mit Häkchen stehen ihre Waffen trotzdem in
  der Liste, sofern nichts anderes sie deinem Charakter verwehrt, etwa die Stufe, die sie
  verlangen. Der Tooltip der Zeile sagt, dass die Fertigkeit erlernt werden muss. **Bestes Set
  für** nimmt keine davon. Bei einem Jäger haben auch Wurfwaffen kein Häkchen, bis du es
  setzt: Eine Wurfwaffe nimmt den Platz von Bogen oder Gewehr ein.
- Ein Krieger oder Paladin mit dem Profil **Schutz** beginnt mit **Einhändig, Schild und
  Schildhand**, solange die Gewichte des Addons bewerten: Es sind die eines Tanks mit Schild.
  Wähle **Beliebig**, um auch Zweihandwaffen zu sehen.
- Ist **Einhändig, Schild und Schildhand** gewählt und führt der Charakter eine Zweihandwaffe,
  stehen Einhandwaffen, Schilde und Gegenstände für die Schildhand als **Neu** in der Liste:
  Jeder zählt für sich, nicht im Vergleich zur Zweihandwaffe. Bewertet Forever Leveling BiS,
  wird eine Waffe weiterhin mit der Zweihandwaffe verglichen.
- Jeder Charakter hat sein eigenes Häkchen **Beste Rüstungsart für die Klasse**, seine eigene
  Zahl bei **Verbesserung ab**, seinen eigenen Betrag bei **Sofortkauf bis** sowie sein eigenes
  Häkchen und seine eigene Zahl bei **Ausrüstung höchstens 10 Stufen unter dem Charakter**. Die
  Auswahl unter **Waffen** wird für jedes seiner Profile einzeln gemerkt. Kaufst du für einen
  anderen Charakter ein, siehst und änderst du dessen Einstellungen.
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
