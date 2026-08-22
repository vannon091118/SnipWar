# SnipWar Game Cycle — aktueller Architekturstand

> **Stand:** August 2026
> **Status:** Laufzeit- und Erweiterungsnotiz
> **Regel:** Der Code und die 29 Preflight-Constraints sind verbindlich. Historische Entwürfe werden hier nicht als bestehende Features ausgegeben.

---

## 1. Der aktuelle Kreislauf

SnipWar verbindet eine persistente Overworld mit deterministischen Kampf-Replays:

```text
Wirtschaft → Forschung → Aufklärung → Ausbau → Dispatch
     ↑                                      ↓
     └──── Ressourcenfluss ← Resolve ← Transit
```

`GameState` bleibt als Autoload über alle Laufzeitmodule hinweg die autoritative Quelle für Besitz, Ressourcen, Credits, Forschung, Upgrades, Schiffsassemblies, Transits und Scan-Intel. Die Overworld entscheidet, Simulatoren berechnen und Szenen visualisieren.

Der aktive Loop enthält:

- seed-deterministische Startkataloge und prozedurale Chunk-Expansion;
- Ressourcen-Deal, Faction-Vault, Credits, Worker-Produktion und persistente Gatherer;
- globale und planetare Forschung als zeitgesteuerte Jobs;
- einen kostenlosen Start-Scout, Forschungsschiffe und Scan-Intel;
- Planet-Upgrades mit Kosten, Prerequisites, Exklusivität und sichtbaren Strukturen;
- Worker-Missionen für Military, Cargo, Colony und Collect;
- modulare Schiffsassemblies mit Hull, Drive, Shield, Scanner, Weapon und Modulen;
- route-basierte FleetBattle- und planetare Conquest-Replays;
- ein UI, das vor dem Dispatch Menge, Ziel, Flugzeit und Konsequenz anzeigt.

---

## 2. Datenfluss und Verantwortungsgrenzen

```text
Definition / Resource
        ↓
GameState-Domain
        ↓
Transit- oder Build-Job
        ↓
Simulation / Arrival-Resolve
        ↓
Signal + EventLog
        ↓
UI / Replay / sichtbarer Weltzustand
```

### Autoritative Regeln

1. **Jobs sind keine Animationen.** Bau-, Forschungs- und Transitfortschritt stammt aus persistentem Zustand. Visuals lesen diesen Fortschritt und dürfen ihn nicht selbst takten.
2. **Vorschau ist keine Ausführung.** Flugzeit- und Dispatch-Preview verwenden dieselbe Berechnung wie der echte Transit, verändern aber keinen Zustand.
3. **Simulation ist rein.** `FleetBattleSimulator`, `ConquestSimulator` und die Engagement-Auflösung arbeiten deterministisch mit Snapshots und Seeds.
4. **Szenen illustrieren.** `BattleScene` und `ConquestScene` zeigen bereits berechnete Events und Resultate. Die Szenen entscheiden nicht eigenständig über Treffer, Besitz oder Verluste.
5. **GameState schreibt einmal.** Arrival-Resolver und ConflictManager committen Ergebnisse atomar über die GameState-Fassade; Capture läuft über `set_faction()`.

---

## 3. Layer 1 — Overworld und Entscheidungsoberfläche

`StarfieldBackground` wählt das Szenario, finalisiert den Layout-Seed und erzeugt den Startkatalog. Beide Shipped-Szenarien aktivieren die Chunk-Welt; `ChunkCoordinator` erzeugt weitere Planeten bei wachsendem Sichtbereich. Homeworlds und Start-Intel werden beim Boot deterministisch gesetzt.

`NavigationField` vereinigt Layout-Nachbarschaft, Moon-/Comet-Waypoints und den optionalen K-Nearest-Langstreckengraph. `find_route()` ist die gemeinsame Quelle für Scout, Worker, Forschungsschiff, ShipBase und Flugzeit-Preview.

### Dispatch-Vertrag

Das Planet-Panel trennt bewusst:

1. **Lage:** Planet, Fraktion, Produktion, lokale Vorräte, Bau- und Perimeter-Intel;
2. **Auftrag:** Ziel, Missionsart und sichtbare Bedeutung;
3. **Konsequenz:** `N / Maximum Einheiten`, verbleibende Garnison, Flugzeit, Rückkehrladung oder Konfliktrisiko;
4. **Bestätigung:** ein fixer Action-Footer mit **MISSION STARTEN**, unabhängig von der Scrollposition.

Die Karte wird bei offenem Panel dezent zurückgestuft. Gelb ist die aktive Dispatchroute, das übrige Netz ist Navigationsreferenz. Fog-of-War bleibt autoritativ: unbekannte Ziele werden nicht durch UI-Preview enthüllt.

### Wirtschaft und HUD

Der Economy-Timer startet erst nach `worker_automation`; der Gather-Timer läuft getrennt. Die VaultBar zeigt die fünf Rohstoffe, Credits, aktive Transportphasen, beobachtete Ertragsrate und den Countdown bis zum nächsten Tick. Die Darstellung ist ein Readback des Wirtschaftszustands, keine zweite Wirtschaftssimulation.

### Forschung und Werkstatt

`TechnologyMenu` nutzt die drei Kategorien **SCHIFFE**, **MECH** und **PLANET**. Jede Forschungskarte zeigt Rolle, Beschreibung, Kosten, Voraussetzung, Freischaltung und Jobstatus. Die Mech-Kategorie ist ein vorbereitetes, sichtbares Gate; `mech_frame` besitzt noch keine aktive Mech-Kampflogik.

Die Forschungsschiff-Ansicht verwaltet persistente Schiffe und Scan-Aufträge. Der Ship Builder kauft Teile, prüft Tech-Gates, montiert vollständige Loadouts, zeigt Build-Fortschritt und kann Assemblies in den Transit geben.

---

## 4. Layer 2 — FleetBattle-Resolve

Bei gegnerischen ShipBase-Transits prüft `ConflictManager` die Transitpfade. Gemeinsame Routensegmente oder passende Kreuzungen können ein Engagement erzeugen. Colony-Schiffe sind von diesem Kampfpfad ausgenommen.

```text
FleetSnapshot A + FleetSnapshot B + Routen + Engagement + Seed
        ↓
FleetBattleSimulator.simulate_route_battle()
        ↓
CombatReplay / BattleContext
        ↓
BattleScene als Replay
        ↓
GameState-Commit und Transitbereinigung
```

Ankunft am Ziel kann ebenfalls ein Fleet-vs-Fleet- oder Fleet-vs-Ground-Resolve auslösen. Der Replay-Typ und die Entscheidung werden aus dem Arrival-Kontext abgeleitet; sie sind kein frei erfundenes UI-Ereignis.

---

## 5. Layer 3 — Conquest-Resolve

Verteidigte Planeten führen den Conquest-Pfad mit Garnison, Defense-Rating, Perimeter-Slots, Reichweite, Gebäuden und Angreifer-Minions aus. Ein Schiffsloadout kann über `AssaultMinionDefinition.from_ship()` in den Bodenpfad übersetzt werden. Der Simulator bleibt deterministisch und ändert seine Balance-Konstanten nicht über UI-Parameter.

`ConquestScene` visualisiert Waves, Gebäude, Minions, Treffer und das Ergebnis. Bei einem Spieler-Capture kann anschließend die Capture-Decision-Overlay die nächste Besitzentscheidung entgegennehmen. Mech-Chassis sind registriert und sichtbar vorbereitet, aber noch keine aktive Kampfeinheit.

---

## 6. Was bewusst noch nicht behauptet wird

Diese Punkte sind Erweiterungsziele, keine aktuellen Features:

- feste Planetentyp→Ressourcen-Signaturen;
- ein allgemeiner Objekt×Transformer-Child-Pool für jede Domäne;
- aktive Mech-Kampflogik und Mech-Bataillone;
- vollständige Kampagnen-, Dominanz- und Game-Over-Regeln;
- mehrere parallel steuerbare Schiffsklassen mit freier Flotten-Missionsauswahl;
- frei laufende Echtzeit-Physik als Quelle für Kampfentscheidungen.

Die damaligen Entwurfsskizzen zu fehlenden Battle-/Conquest-Szenen, einem hypothetischen SceneTree-Wechsel und reinen Victory-Condition-Resources sind damit als historische Ideen ersetzt. Neue Erweiterungen müssen zuerst einen autoritativen Datenpfad, Laufzeitverbraucher und Preflight-Abdeckung erhalten.

---

## 7. Verifikation

```bash
$GODOT_BIN --headless --path . --quit-after 2
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd
```

Maßgeblich ist `RESULT: PASSED`. Headless-RID- und ObjectDB-Leaks des Dummy-Renderers am Teardown sind bekanntes Rauschen.

*SnipWar Game Cycle — aktuelle Fassung, August 2026*
