# Status · move_AI
Zustand: aktiv
Aktualisiert: 2026-11-11

## Nächster Schritt
`./install.sh` ausführen und neues Icon in Dock/Finder und Menüleiste (hell/dunkel) ansehen; danach Audiodatei-Drop im Fenster „Transkripte“ (⌘T) prüfen.

## Zuletzt
- 2026-11-11: Neues App-Icon D2 (bewegtes „e“ + Mauszeiger) und passendes Template-Menüleistensymbol; `Eppur/design/render-icons.swift` erzeugt alle Größen direkt in die Assets. Asset-Katalog mit actool geprüft; App-Build in der Claude-Sandbox nicht möglich (Macro-Server braucht sandbox-exec) – Build/Ansicht in der laufenden App offen.
- 2026-11-11: Audiodateien im Fenster „Transkripte“ per Drag & Drop oder Toolbar-Knopf transkribieren – nur Spracherkennung, keine LLM-Korrektur/kein Wörterbuch (auch wenn Nachkorrektur an). Kopie im Sitzungsordner, Eintrag im Verlauf mit Dateiname, Warteschlange für mehrere Dateien. Build ok; Dienstpfad mit m4a/wav/aiff geprüft (`corrected: false`). Drop in der laufenden App noch nicht geprüft.
- 2026-11-10: Lokale CLI & MCP (ohne Schlüssel, Entscheidung Nutzer): MCP-Endpunkt `/mcp` (Streamable HTTP, 7 Werkzeuge), CLI `eppur` (list/search/show/transcribe/correct/export/mcp), Tab „Integrationen“ mit Schalter. Gegen Test-Dienst geprüft. Scrollen während Fn wird durchgereicht. Freigaben nach Zertifikatswechsel neu erteilt (AX/Screen/Mic = true).
- 2026-11-10: Interne Namen auf Eppur umgestellt (Eppur.xcodeproj, EppurServer, eppur-server, Zertifikat „Eppur Local Signing“); Lizenz Apache-2.0 + NOTICE; neues flaches App-Icon (generiert, maskiert) und Template-Menüleisten-Symbol; privates GitHub-Repo `eppur`. Fixes: Dev-Build verdrängt installierte App nicht mehr, veraltete Dienste werden ersetzt, MLX-Generierungen serialisiert.
- 2026-11-10: Sprache standardmäßig „Automatisch“ (Parakeet erkennt de/en selbst – mit synthetischer Sprache geprüft, identisch mit/ohne Vorgabe). Korrektur wahlweise lokal (Qwen) oder per OpenAI-kompatibler Chat-API (OpenAI, OpenRouter, Ollama …), Wörterbuch + Umformulierungsschutz gelten für beide; auch für die API-Spracherkennung nutzbar.

## To-dos
- [x] Metal Toolchain installieren
- [x] Dienst bauen, Modelle laden, Latenz Parakeet + Qwen messen
- [x] `install.sh` ausführen
- [x] `install.sh` erneut ausführen (yt-dlp-Fix)
- [ ] Korrektur an echten Diktaten prüfen (bisher nur synthetische Sprache)
- [ ] Fragezeichen bei gesprochenen Fragen (Qwen setzt teils Punkt)
- [ ] Fn-Erkennung, Overlays, Auto-Einfügen im echten Gebrauch testen
- [ ] Fn-Taste in Systemeinstellungen → Tastatur auf „Keine Aktion“ stellen
- [ ] Optional: Qwen3-ASR 1.7B als zweite Engine; CTC-Vokabular-Boosting von FluidAudio prüfen
- [x] MCP-Server und CLI für Agenten
- [ ] MCP mit echtem Claude-Code-Client testen
- [x] Stabile Code-Signatur (lokales Zertifikat, Entscheidung Nutzer)
- [x] Alte MoveAI-Einträge in Datenschutz-Einstellungen entfernen und Freigaben einmal neu erteilen
- [ ] Später: automatische Session-Zuordnung
- [x] Bundle-ID und Datenordner auf Eppur umgestellt
- [x] Restliche interne Namen angleichen
- [x] Name „Eppur“ geprüft: keine App/kein Repo gefunden (Markenregister nicht direkt abgefragt)
- [ ] Vor öffentlicher Freigabe: Markenregister (EUIPO/DPMA) direkt prüfen
- [ ] Veröffentlichung auf GitHub vorbereiten (README, Lizenz, Build-Anleitung); fertige App-Downloads bräuchten Developer ID + Notarisierung (99 $/Jahr)

- [ ] Externe Korrektur mit echtem API-Schlüssel testen (Fehlerfälle geprüft)
- [ ] Optional: altes Zertifikat „MoveAI Local Signing“ und Ordner `Application Support/MoveAI` entfernen
- [x] Neues App-Icon und Menüleisten-Symbol

## Entscheidungen
- [x] Neues App-Icon → D (bewegtes „e“) mit Mauszeiger, Wahl Nutzer
- [x] Variante D → D2 (gerades „e“ mit Spuren, heller Zeiger daneben), Wahl Nutzer
- [x] App-Name → Eppur (Galilei: „Eppur si muove“ – mit Grundannahmen brechen)
- [x] Signatur → lokales Zertifikat (kein Apple-Account)
- [x] Veröffentlichung → Open Source ohne Developer-Account (selbst bauen per `install.sh`)
- [x] Apple SpeechAnalyzer raus → Nutzer unzufrieden mit Qualität
- [x] Engine: Parakeet TDT 0.6B v3 (Standard), Korrektur: Qwen 3.5 2B → schnell, lokal, gute Deutsch-Abdeckung
- [x] SenseVoice Small nicht übernehmen → kein Deutsch (nur zh/yue/en/ja/ko)
- [x] Modelle in separatem lokalem Dienst statt in der App → eine Modellinstanz für App, Agenten und Skripte (API-Wunsch); umgeht Paketintegration ins neue Xcode-Projektformat
- [x] Erst Zwischenablage + Auto-Einfügen, automatische Session-Zuordnung später
