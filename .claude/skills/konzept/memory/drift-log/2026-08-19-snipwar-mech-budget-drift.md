---
ticket: snipwar-mech-budget-metric
datum: 2026-08-19
status: offen
scope: nicht-rekursiv
---

# Drift-Ticket: Sichtbarkeitsbudget messen

## Ziel

Die automatische Kompression soll erst auf echte Renderlast reagieren, nicht auf eine angenommene Instanzgrenze. Dieses Ticket definiert nur den Messpunkt und die Umschaltregel; es ändert noch keine Laufzeitlogik.

## Messpunkt

- **Signal:** `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`.
- **Abtastung:** Ein Wert pro 0,5 Sekunden; für die Entscheidung den Median der letzten drei Werte verwenden.
- **Startbudget:** 250 Draw Calls pro Frame als vorläufiger Kalibrierwert.

## Minimale Hysterese

- In die komprimierte Darstellung wechseln, wenn der Median mindestens drei Abtastungen lang **über 250** liegt.
- Zur detaillierteren Darstellung zurückkehren, wenn der Median mindestens drei Abtastungen lang **unter 225** liegt (10 % Abstand).
- Zwischen den Grenzen bleibt die aktuelle Darstellung unverändert.

## Abnahmekriterien

- Die Metrik wird nur an einer Stelle gelesen und beeinflusst ausschließlich die sichtbare Kompression.
- Der logische Einheitenzähler und die K/M/L-Schwellen ändern sich dadurch nicht.
- Kein Wechsel bei einem einzelnen Spike; die drei Abtastungen verhindern Flattern.
- Die Werte 250/225 werden nach einer Messung im Zielgerät kalibriert, ohne die Hysterese-Regel neu zu entwerfen.

## Bewusste Nicht-Ziele

- Keine rekursive Detail-/Asset-Auswahl.
- Keine Änderung der logischen K/M/L-Packung; die Formation ist nur Transitdarstellung und keine neue Einheitenlogik.
- Keine neue Render- oder Entity-Architektur in diesem Ticket.
