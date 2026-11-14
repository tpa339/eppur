# Status · move_AI
Zustand: aktiv
Aktualisiert: 2026-11-14

## Nächster Schritt
Beta-Tester (Intel) als Collaborator auf tpa339/eppur einladen; er installiert v1.1 per Agent-Prompt aus der README und testet Mistral.

## Zuletzt
- 2026-11-14: v1.1 für Intel: Build-Ziel macOS 26, Universal-App (arm64+x86_64); auf Intel kein lokaler Dienst, Spracherkennung per API mit Anbieter-Auswahl (Standard Mistral `voxtral-small-transcribe-3-0`, OpenRouter, eigene). Update-Funktion über GitHub Releases (Signaturprüfung gegen eigenes Zertifikat, Tausch + Neustart). `Eppur/scripts/release.sh` (Universal-ZIP + GitHub-Release). Intel-Teil unter Rosetta gestartet (kein Dienst gestartet), v1.1 in /Applications, Freigaben erhalten. Mistral-API mit echtem Schlüssel und Update-Ablauf Ende-zu-Ende noch ungetestet.
- 2026-11-12: Hauptfenster „Eppur“ (MainWindow.swift): öffnet per Klick aufs App-Symbol; alles in einem Fenster (Seiten Jetzt/Transkripte/Einstellungen/Einrichtung, keine separaten Fenster mehr). Bühne „Höre zu“ mit Wellenform, Einstellungen als anklickbarer Satz inkl. Modelle mit Statuspunkt, letzte 3 Transkripte, Audio-Drop. Gestaltung danach beruhigt (Nutzerwunsch: keine Verläufe): native Fensterleiste mit Seitenumschalter, Systemfarben hell/dunkel, Akzent Indigo (AccentColor). Gebaut, vom Nutzer getestet und für gut befunden (2026-11-13), auf GitHub gepusht.
- 2026-11-12: Screenshot-Modus während Fn umgebaut: Ebene lässt alle Ereignisse durch (Scrollen/Klicken nativ), Event-Tap hält nur die linke Maustaste zurück – Klick wird an die App nachgereicht, Ziehen = Bereich, langes Halten = Fenster. Per install.sh gebaut, in der laufenden App vom Nutzer bestätigt (Screenshot entsteht).
- 2026-11-11: Neues App-Icon D2 (bewegtes „e“ + Mauszeiger) und passendes Template-Menüleistensymbol; `Eppur/design/render-icons.swift` erzeugt alle Größen direkt in die Assets. Asset-Katalog mit actool geprüft; App-Build in der Claude-Sandbox nicht möglich (Macro-Server braucht sandbox-exec) – Build/Ansicht in der laufenden App offen.
- 2026-11-11: Audiodateien im Fenster „Transkripte“ per Drag & Drop oder Toolbar-Knopf transkribieren – nur Spracherkennung, keine LLM-Korrektur/kein Wörterbuch (auch wenn Nachkorrektur an). Kopie im Sitzungsordner, Eintrag im Verlauf mit Dateiname, Warteschlange für mehrere Dateien. Build ok; Dienstpfad mit m4a/wav/aiff geprüft (`corrected: false`). Drop in der laufenden App noch nicht geprüft.

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
- [ ] GitHub-Release (ZIP, unsigniert mit Anleitung; ohne lokalen Dienst in der App) – v1.1 vorbereitet
- [ ] Mistral-Transkription mit echtem Schlüssel testen (Beta-Tester, Intel)
- [ ] Update-Funktion Ende-zu-Ende testen (braucht zweite Release-Version)
- [ ] Veröffentlichung auf GitHub vorbereiten (README, Lizenz, Build-Anleitung); fertige App-Downloads bräuchten Developer ID + Notarisierung (99 $/Jahr)

- [ ] Externe Korrektur mit echtem API-Schlüssel testen (Fehlerfälle geprüft)
- [ ] Optional: altes Zertifikat „MoveAI Local Signing“ und Ordner `Application Support/MoveAI` entfernen
- [x] Neues App-Icon und Menüleisten-Symbol

## Entscheidungen
- [x] Repo-Sichtbarkeit → privat lassen, Release anlegen (2026-11-14); automatische Update-Suche funktioniert damit nur bei öffentlichem Repo
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
