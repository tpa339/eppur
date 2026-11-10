# Status · move_AI
Zustand: aktiv
Aktualisiert: 2026-11-10

## Nächster Schritt
Im Alltag nutzen und Auffälligkeiten sammeln (Korrektur-Qualität, Wörterbuch); dann nächstes Feature wählen (MCP-Server, Session-Zuordnung, Qwen3-ASR).

## Zuletzt
- 2026-11-10: App heißt jetzt **Eppur** (vorher Notchly; Produktname + Icon `MoveAI/design/eppur-icon-1024.png`); Einstellungen als Tabs (Allgemein, Transkription, Wörterbuch, Screenshots, Klänge); Screenshot per Klick und per Ziehen getrennt schaltbar; eigene synthetische Klänge (Sanft/Tropfen/Glocke) mit Probehören; nur noch eine App-Instanz (ältere wird beendet) und ein Wiederholversuch bei Dienst-Verbindungsfehler (Ursache „Network Error“: zwei parallele Instanzen).
- 2026-11-10: Töne bei Aufnahme-Start („Tink“) und -Ende („Pop“), abschaltbar in Menü und Einstellungen. Neubau behielt alle Freigaben (AX/Screen/Mic = true).
- 2026-11-10: Praxistest erfolgreich: Fn-Diktat wird in Ghostty automatisch eingefügt, Screenshots (Fenster/Bereich) landen mit Pfad im Text. TCC-Einträge per `tccutil reset` bereinigt und für die neue Signatur neu erteilt (Log: AX=true Screen=true Mic=true). Diagnose-Log `~/Library/Application Support/MoveAI/app.log`.
- 2026-11-10: Freigaben-Problem behoben: App jetzt mit lokalem Zertifikat „MoveAI Local Signing“ signiert (designated requirement = Bundle-ID + Zertifikat, stabil über Neubauten). Bildschirmaufnahme-Dialog max. 1× pro Start; Auto-Einfügen sendet immer Cmd+V an die aktive App (Feldprüfung entfernt); Notch meldet fehlende Freigaben.
- 2026-11-10: Neuinstallation mit yt-dlp-Fix; YouTube-Transkription über `/v1/transcribe` geprüft (19-s-Video: Download 5,4 s, Parakeet 0,6 s).

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
- [ ] Vor Veröffentlichung: interne Namen angleichen (Bundle-ID `local.moveai.MoveAI`, Ordner `Application Support/MoveAI`, `moveai-server`, Xcode-Target `MoveAI`) – Bundle-ID-Wechsel erfordert einmalig neue Freigaben
- [ ] Veröffentlichung auf GitHub vorbereiten (README, Lizenz, Build-Anleitung); fertige App-Downloads bräuchten Developer ID + Notarisierung (99 $/Jahr)

## Entscheidungen
- [x] App-Name → Eppur (Galilei: „Eppur si muove“ – mit Grundannahmen brechen)
- [x] Signatur → lokales Zertifikat (kein Apple-Account)
- [ ] Veröffentlichung: nur Quellcode (ohne Apple-Account) oder fertige App (Developer ID nötig)? Empfehlung: erst Quellcode
- [x] Apple SpeechAnalyzer raus → Nutzer unzufrieden mit Qualität
- [x] Engine: Parakeet TDT 0.6B v3 (Standard), Korrektur: Qwen 3.5 2B → schnell, lokal, gute Deutsch-Abdeckung
- [x] SenseVoice Small nicht übernehmen → kein Deutsch (nur zh/yue/en/ja/ko)
- [x] Modelle in separatem lokalem Dienst statt in der App → eine Modellinstanz für App, Agenten und Skripte (API-Wunsch); umgeht Paketintegration ins neue Xcode-Projektformat
- [x] Erst Zwischenablage + Auto-Einfügen, automatische Session-Zuordnung später
