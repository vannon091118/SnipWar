# SnipWar — PC-Entwicklungsprofil

**Zweck:** Reproduzierbare Erfassung des Rechners, auf dem SnipWar gebaut, getestet und mit Godot ausgeführt wird.

> Dieses Dokument ist ein Messprotokoll und keine Behauptung über unbekannte Hardware. Alle Werte wurden mit den unten angegebenen Tools gemessen.

## 1. Identität und Umgebung

| Feld | Wert |
|---|---|
| Hostname | `vannonDESKTOP` |
| Betriebssystem | Microsoft Windows 11 Pro |
| Build | 10.0.26200 |
| Architektur | x64-Bit |
| Benutzer | `Vannon` |
| Erfassungsdatum | 2026-08-29 |
| Git-Commit | `aa6d580` |
| Branch | `main` |
| Godot-Version | `4.7.2.stable.official.ed1daf0bf` |
| Python-Version | `3.14.7` |
| Node-Version | `v24.18.0` |
| BIOS/UEFI | American Megatrends Inc. V17.17 (2015-04-22) |

## 2. RAM-Taktung und Speicherintegrität

| Feld | Wert |
|---|---|
| Gesamtkapazität | 12 GB (12.882.989.056 Byte) |
| Modulanzahl | 2 von 2 Slots belegt |
| Modul 1 (DIMM1) | Nanya M2F8G64CC8HD5N-DI — **8 GB** — DDR3-1333 |
| Modul 2 (DIMM2) | Hersteller01 CL9-9-9 DDR3-13330 — **4 GB** — DDR3-1333 |
| DDR-Generation | DDR3 |
| JEDEC-Takt | 1333 MHz (Modulgeschwindigkeit) |
| XMP/EXPO-Profil | **Keines aktiv** — Mix aus verschiedenen Herstellern und Kapazitäten |
| Tatsächlicher Takt | 1333 MHz |
| ECC-Status | Nein (Consumer-Board) |
| RAM-Stabilität | **Nicht getestet** (MemTest86/Windows Memory Diagnostic noch nicht ausgeführt) |

### ⚠️ Befund: Gemischte RAM-Module

Zwei verschiedene Hersteller, zwei verschiedene Kapazitäten (8 GB + 4 GB), unterschiedliche Modellbezeichnungen. Kein XMP/EXPO-Profil aktiv. Die Module laufen auf JEDEC-Standard 1333 MHz.

**Risiko:** Gemischte Module können zu Stabilitätsproblemen führen, wenn Timings und Spannung nicht harmonieren. Der FX-6300 Memory Controller ist toleranter als moderne Plattformen, aber ein MemTest86-Lauf ist vor empfindlichen Arbeiten empfohlen.

## 3. CPU-Gesundheit

| Feld | Wert |
|---|---|
| Modell | AMD FX(tm)-6300 Six-Core Processor |
| Kerne/Threads | 3 Kerne / 6 Threads |
| Basistakt | 3500 MHz (3.5 GHz) |
| Boost-Takt | **Kein Turbo Boost / Precision Boost** (Architecture: Piledriver, BMJ-Klasse) |
| Aktueller Takt | 3500 MHz |
| Last (zum Zeitpunkt der Messung) | 40% |
| Temperatur Idle/Last | **Nicht messbar** — keine Sensordaten verfügbar |
| Package Power | **Nicht messbar** |
| Throttling | **Nicht beobachtbar** ohne HWiNFO/Prime95 |
| WHEA-Fehler | **Keine** (in den letzten Messungen) |
| Stabilitätstest | **Noch nicht ausgeführt** |

### ⚠️ Befund: Alter Prozessor ohne Boost

Der FX-6300 ist eine 2012er Architektur (Piledriver, 32nm). Kein Turbo-Boost, 95W TDP. Für Godot 4.7 Headless und Preflight ist die Single-Thread-Leistung der limitierende Faktor. Die Preflight-Suite dauert ~57-63 Sekunden, was für diese CPU erwartbar ist.

## 4. GPU-Gesundheit

| Feld | Wert |
|---|---|
| Modell | NVIDIA GeForce GTX 1050 |
| VRAM | 2048 MiB (2 GB) |
| Treiberversion | 560.94 |
| Treiberdatum | 2024-08-14 |
| GPU-Takt (Idle) | 139 MHz |
| VRAM-Takt (Idle) | 405 MHz |
| Temperatur (Idle) | 34 °C |
| Auslastung | 19% |
| Leistungsaufnahme | N/A |
| Power-Limit | 75.00 W |
| Artefakte | **Keine** |
| Treiber-Resets | **Keine** |

### Befund

Die GTX 1050 mit 2 GB VRAM ist die minimale Godot-Kompatibilität für sichtbare Szenen. Headless-Läufe verwenden die GPU nicht. Der Idle-Zustand (34 °C, 139 MHz) ist gesund.

## 5. Festplatten, SSDs und Dateisysteme

| Feld | Wert |
|---|---|
| Laufwerk | TOSHIBA HDWD110 |
| Kapazität | 1000 GB (~930 GB nutzbar) |
| Bus | SATA |
| Partitionierung | MBR |
| Dateisystem | NTFS |
| HealthStatus | Healthy |
| Festplattentyp | **HDD (mechanisch)** |
| SMART/Reliability | Nicht abrufbar (Berechtigung verweigert) |
| Freier Speicher (C:) | 732,7 GB von 930,6 GB (78,7%) |
| Volume-Scan | **Nicht ausführbar** (Benutzerrechte) |

### ⚠️ KRITISCH: Nur HDD, kein SSD

Das gesamte System läuft auf einer einzigen mechanischen Festplatte. Keine SSD vorhanden.

**Auswirkung auf SnipWar:**
- Godot-Editor-Start: langsamer als auf SSD
- Headless-Preflight: I/O-bound bei `compile_gate.gd` (586 Dateien, 113k LOC)
- Git-Operationen: langsamer
- Narrative Runtime: SQLite auf HDD
- Godot-Asset-Import: deutlich langsamer

**Keine SMART-Daten verfügbar** — `Get-StorageReliabilityCounter` erfordert Admin-Rechte. Die Toshiba HDWD110 ist eine Consumer-HDD (DT01ACA-Serie). Nach 2015er Bauzeit und 10+ Jahren Betrieb sollte der SMART-Zustand dringend überprüft werden.

## 6. I/O, Busse und Peripherie

| Feld | Wert |
|---|---|
| Ethernet | Realtek PCIe GBE Family Controller — **1 Gbps** — Up |
| Ethernet 2 | VirtualBox Host-Only Ethernet Adapter — **1 Gbps** — Up |
| Partitionierung | MBR (kein UEFI-GPT) |
| Fehlerhafte PnP-Geräte | `Microsoft-Hypervisor-Dienst` — Status: **Degraded** |
| Systemfehler (30 Tage) | Keine (außer WindowsUpdate) |
| Kernel-Power-Events (ID 41) | **Keine** — keine unerwarteten Abschaltungen |

### Befund

- Netzwerk stabil (1 Gbit Ethernet).
- VirtualBox Host-Only Adapter vorhanden — potenzieller Doppel-Netzwerk-Stack, aber ohne Einfluss auf SnipWar.
- `Microsoft-Hypervisor-Dienst` degradiert: typisch bei aktivem Hyper-V oder WSL2. Kein硬体defekt.
- MBR statt GPT: BIOS ist 2015, kein UEFI-Modus. Das schränkt künftige Plattenerweiterung ein, beeinflusst SnipWar nicht.

## 7. Temperaturen, Lüfter und Umgebung

| Sensor | Wert |
|---|---|
| GPU Idle | 34 °C |
| CPU Idle | **Nicht messbar** (kein HWiNFO/Sensorzugriff) |
| SSD/NVMe | **Nicht vorhanden** |
| Mainboard/VRM | **Nicht messbar** |
| Raumtemperatur | **Nicht dokumentiert** |
| Staub-/Kühlkörperzustand | **Nicht dokumentiert** |

**Für vollständige Temperaturerfassung:** HWiNFO64 oder Open Hardware Monitor installieren und Werte nach Idle (30 Min.) und Last (30 Min. Prime95/FurMark) eintragen.

## 8. Stromversorgung

| Feld | Wert |
|---|---|
| Netzteilhersteller/Modell | **Nicht bekannt** |
| Nennleistung | **Nicht bekannt** |
| Alter | **Nicht bekannt** |
| 80-PLUS-Klasse | **Nicht bekannt** |
| CPU-TDP | 95W (FX-6300) |
| GPU Power-Limit | 75W (GTX 1050) |
| Sonstige Last | ~30-50W (Mainboard, RAM, HDD, Lüfter) |
| Geschätzte Spitzenlast | ~200W |
| Kernel-Power-Events | **Keine** |
| USV/Überspannungsschutz | **Nicht bekannt** |

### Befund

Keine spontanen Abschaltungen im Eventlog. Die geschätzte Spitzenlast von ~200W ist moderat. Für den FX-6300 + GTX 1050 reicht ein qualitativ gutes 400W-Netzteil. Die PSU-Daten müssen bei nächster Gelegenheit physikalisch erfasst werden.

## 9. Entwicklungs-Stabilitätstest

| Test | Ergebnis | Datum |
|---|---|---|
| Godot Editor-Scan | ✅ abgeschlossen | 2026-08-29 |
| Compile Gate | ✅ PASS (313 Skripte) | 2026-08-29 |
| Chronicle Core Test | ✅ 22/22 PASS | 2026-08-29 |
| Chronicle Lifecycle Test | ✅ 21/21 PASS | 2026-08-29 |
| Historical Playback Test | ✅ 18/18 PASS | 2026-08-29 |
| Full Preflight | ✅ 43/43, 2024/2024 PASS | 2026-08-29 |
| RAM-Stabilitätstest | ❌ Noch nicht ausgeführt | — |
| CPU-Stresstest (30 Min.) | ❌ Noch nicht ausgeführt | — |
| GPU-Stresstest (30 Min.) | ❌ Noch nicht ausgeführt | — |
| SSD/SMART-Prüfung | ❌ SMART-Daten nicht abrufbar | — |
| Volume-Scan (C:) | ❌ Admin-Rechte erforderlich | — |

## 10. Befundtabelle

| Bereich | Messwert/Befund | Tool/Version | Datum | Status |
|---|---|---|---|---|
| RAM-Takt/Profil | 2× DDR3-1333 (8+4 GB gemischt), kein XMP | PowerShell/SMBIOS | 2026-08-29 | ⚠️ gemischt |
| RAM-Stabilität | Nicht getestet | — | — | 🟡 offen |
| CPU | AMD FX-6300, 3C/6T, 3.5 GHz, 40% Last | Win32_Processor | 2026-08-29 | ⚠️ alt |
| CPU-Stabilität | Nicht getestet | — | — | 🟡 offen |
| GPU | GTX 1050 2GB, 34°C Idle, 560.94 | nvidia-smi | 2026-08-29 | ✅ OK |
| GPU-Stabilität | Nicht getestet | — | — | 🟡 offen |
| SSD/NVMe SMART | **Kein SSD vorhanden** — nur HDD | Get-PhysicalDisk | 2026-08-29 | 🔴 HDD |
| HDD Gesundheit | Healthy (SMART nicht abrufbar) | Get-PhysicalDisk | 2026-08-29 | ⚠️ eingeschränkt |
| I/O/Busse | Realtek GBE 1Gbit, Hypervisor degraded | Get-NetAdapter/PnpDevice | 2026-08-29 | ✅ OK |
| Temperaturen | GPU 34°C Idle, CPU/Sensor nicht verfügbar | nvidia-smi | 2026-08-29 | ⚠️ unvollständig |
| Stromversorgung | PSU unbekannt, keine Kernel-Power-Events | Eventlog | 2026-08-29 | ⚠️ unvollständig |
| Godot/Compile | 4.7.2, 313 Skripte PASS | compile_gate.gd | 2026-08-29 | ✅ OK |
| Full Preflight | 43/43, 2024/2024 PASS | preflight.gd -x | 2026-08-29 | ✅ OK |

## 11. Risikobewertung

| Risiko | Schwere | Beschreibung |
|---|---|---|
| **Kein SSD** | 🔴 Hoch | I/O-Engpass für Godot-Editor, Preflight, Git, narrative Runtime |
| **Kein RAM-Test** | 🟡 Mittel | Gemischte DDR3-Module ohne XMP; Stabilität unbewiesen |
| **CPU 11 Jahre alt** | 🟡 Mittel | FX-6300: langsam für Godot 4.7, Preflight ~60s statt ~10s |
| **GPU 2GB VRAM** | 🟡 Mittel | Minimale Godot-Kompatibilität; große Szenen können zur Limit werden |
| **HDD 10+ Jahre** | 🟡 Mittel | SMART-Daten nicht abrufbar; Ausfallrisiko steigt mit Alter |
| **PSU unbekannt** | 🟡 Mittel | Keine Leistungsreserve dokumentiert |
| **BIOS seit 2015** | 🟢 Niedrig | Keine Sicherheitsupdates; Funktioniert stabil |

## 12. Nächste Schritte

Priorisiert nach Dringlichkeit:

1. **SMART/SMART-Daten abrufen** — Admin-Rechte oder Hersteller-Tool für Toshiba HDWD110
2. **RAM-Stabilitätstest** — MemTest86 oder Windows Memory Diagnostic (mindestens 2 Durchläufe)
3. **CPU-Stresstest** — 30 Min. Prime95 mit HWiNFO-Temperaturlogging
4. **GPU-Stresstest** — 30 Min. FurMark oder 3DMark mit nvidia-smi-Temperaturlogging
5. **PSU physikalisch erfassen** — Hersteller, Modell, Watt, Alter
6. **Temperatur-Idle/Last-Werte** — HWiNFO64 installieren und Werte eintragen
7. **SSD-Upgradeprozess planen** — Auf SSD umsteigen für Godot-Performance

## 13. Sicherheitsregeln

- Keine BIOS-/XMP-/EXPO- oder Spannungseinstellungen automatisch ändern.
- Keine destruktiven Festplattentests auf dem Systemlaufwerk ohne Admin-Rechte und Backup.
- Keine Administratorbefehle ohne bewusste Freigabe.
- Messwerte nicht aus Toolnamen oder theoretischen Datenblättern ableiten.
- Ein grüner Godot-Preflight beweist nicht die Gesundheit von RAM, SSD, Netzteil oder Kühlung; beide Prüfklassen werden getrennt dokumentiert.
