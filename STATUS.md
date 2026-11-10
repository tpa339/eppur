# Status · move_AI
Zustand: aktiv
Aktualisiert: 2026-11-10

## Nächster Schritt
`./install.sh` erneut ausführen (Dienst mit API-Korrektur + App), dann Freigaben im Einrichtungsfenster prüfen.

## Zuletzt
- 2026-11-10: Sprache standardmäßig „Automatisch“ (Parakeet erkennt de/en selbst – mit synthetischer Sprache geprüft, identisch mit/ohne Vorgabe). Korrektur wahlweise lokal (Qwen) oder per OpenAI-kompatibler Chat-API (OpenAI, OpenRouter, Ollama …), Wörterbuch + Umformulierungsschutz gelten für beide; auch für die API-Spracherkennung nutzbar.
- 2026-11-10: Endgültige Bundle-ID `app.eppur.Eppur` (Debug: `app.eppur.Eppur.dev` „Eppur Dev“); Datenordner `Application Support/Eppur` mit Übernahme aus `MoveAI`; Einrichtungsfenster statt Systemdialogen beim Start; Start beim Anmelden (SMAppService); `install.sh` für Zertifikat + Dienst + App nach /Applications; README. Git-Repo angelegt.
- 2026-11-10: App heißt jetzt **Eppur** (vorher Notchly; Produktname + Icon `MoveAI/design/eppur-icon-1024.png`); Einstellungen als Tabs (Allgemein, Transkription, Wörterbuch, Screenshots, Klänge); Screenshot per Klick und per Ziehen getrennt schaltbar; eigene synthetische Klänge (Sanft/Tropfen/Glocke) mit Probehören; nur noch eine App-Instanz (ältere wird beendet) und ein Wiederholversuch bei Dienst-Verbindungsfehler (Ursache „Network Error“: zwei parallele Instanzen).
- 2026-11-10: Töne bei Aufnahme-Start („Tink“) und -Ende („Pop“), abschaltbar in Menü und Einstellungen. Neubau behielt alle Freigaben (AX/Screen/Mic = true).
- 2026-11-10: Praxistest erfolgreich: Fn-Diktat wird in Ghostty automatisch eingefügt, Screenshots (Fenster/Bereich) landen mit Pfad im Text. TCC-Einträge per `tccutil reset` bereinigt und für die neue Signatur neu erteilt (Log: AX=true Screen=true Mic=true). Diagnose-Log `~/Library/Application Support/MoveAI/app.log`.

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
- [ ] Optional: MCP-Server für Agenten auf Basis der HTTP-API
- [x] Stabile Code-Signatur (lokales Zertifikat, Entscheidung Nutzer)
- [x] Alte MoveAI-Einträge in Datenschutz-Einstellungen entfernen und Freigaben einmal neu erteilen
- [ ] Später: automatische Session-Zuordnung
- [x] Bundle-ID und Datenordner auf Eppur umgestellt
- [ ] Restliche interne Namen angleichen (Xcode-Target/Ordner `MoveAI`, `moveai-server`, Zertifikat „MoveAI Local Signing“)
- [ ] Name „Eppur“ vor Veröffentlichung auf Kollisionen prüfen (Marke, GitHub)
- [ ] Veröffentlichung auf GitHub vorbereiten (README, Lizenz, Build-Anleitung); fertige App-Downloads bräuchten Developer ID + Notarisierung (99 $/Jahr)

- [ ] Externe Korrektur mit echtem API-Schlüssel testen (OpenRouter/OpenAI)
- [ ] Neues Menüleisten-Symbol (Nutzer liefert Inspiration)

## Entscheidungen
- [x] App-Name → Eppur (Galilei: „Eppur si muove“ – mit Grundannahmen brechen)
- [x] Signatur → lokales Zertifikat (kein Apple-Account)
- [x] Veröffentlichung → Open Source ohne Developer-Account (selbst bauen per `install.sh`)
- [x] Apple SpeechAnalyzer raus → Nutzer unzufrieden mit Qualität
- [x] Engine: Parakeet TDT 0.6B v3 (Standard), Korrektur: Qwen 3.5 2B → schnell, lokal, gute Deutsch-Abdeckung
- [x] SenseVoice Small nicht übernehmen → kein Deutsch (nur zh/yue/en/ja/ko)
- [x] Modelle in separatem lokalem Dienst statt in der App → eine Modellinstanz für App, Agenten und Skripte (API-Wunsch); umgeht Paketintegration ins neue Xcode-Projektformat
- [x] Erst Zwischenablage + Auto-Einfügen, automatische Session-Zuordnung später
