# Eppur

> *„Eppur si muove“ – und sie bewegt sich doch.*

Eppur ist eine macOS-Menüleisten-App für Diktat und Screenshots, die **komplett lokal** läuft:

- **Fn halten und sprechen.** Eine Waveform erscheint an der Notch, beim Loslassen wird der Text in die aktive App eingefügt.
- **Screenshots beim Sprechen.** Klick auf ein Fenster oder einen Bereich ziehen; die Bilder landen zusammen mit dem Text in der Zwischenablage (Text + PNG parallel) und als Dateipfad im Text.
- **Spracherkennung:** [Parakeet TDT 0.6B v3](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) über [FluidAudio](https://github.com/FluidInference/FluidAudio) (CoreML, Neural Engine).
- **Nachkorrektur:** Qwen 3.5 2B (4-Bit, [MLX](https://github.com/ml-explore/mlx-swift-lm)) plus Wörterbuch für Namen und Fachbegriffe. Umformulierungen werden verworfen.
- **Lokale API** für Agenten und Skripte – auch für Dateien und YouTube-Links.

## Voraussetzungen

- Mac mit Apple Silicon, macOS 27
- Xcode 27 mit Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain`
- optional: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) für Video-URLs

## Installation

```sh
git clone <repo-url> eppur && cd eppur
./install.sh
```

Das Skript

1. legt einmalig ein lokales Signaturzertifikat „MoveAI Local Signing“ im Schlüsselbund an (fragt nach deinem Passwort),
2. baut und installiert den Dienst nach `~/Library/Application Support/Eppur/bin`,
3. baut die App und installiert sie nach `/Applications/Eppur.app`.

Beim ersten Codesign fragt macOS, ob `codesign` den Schlüssel benutzen darf – **„Immer erlauben“** wählen, sonst hängt der Build.

### Warum ein lokales Zertifikat?

macOS merkt sich Freigaben (Mikrofon, Bedienungshilfen, Bildschirmaufnahme) pro **Bundle-ID + Signatur**. Ohne feste Signatur gilt jeder Neubau als neue App und fragt erneut. Mit dem lokalen Zertifikat bleibt die Identität stabil – Freigaben werden **einmal** erteilt und überstehen Updates. Ein Apple-Developer-Account ist dafür nicht nötig.

## Freigaben

| Freigabe | Wofür | nötig |
|---|---|---|
| Mikrofon | Aufnahme, solange Fn gehalten wird | ja |
| Bedienungshilfen | Fn-Taste erkennen, Text einfügen (Cmd+V) | ja |
| Bildschirmaufnahme | Screenshots beim Sprechen | nur mit Screenshots |

Eppur zeigt beim Start ein Einrichtungsfenster, falls etwas fehlt. macOS fragt bei Bildschirmaufnahme gelegentlich von sich aus nach, ob die Freigabe bestehen bleiben soll – das ist Systemverhalten.

Systemeinstellungen → Tastatur → „🌐-Taste drücken für“ auf **Keine Aktion** stellen.

## Lokale API

Der Dienst lauscht nur auf `127.0.0.1:47823`.

```sh
# Status
curl -s http://127.0.0.1:47823/health

# Audiodatei (OpenAI-kompatibel), mit Korrektur
curl -s -X POST http://127.0.0.1:47823/v1/audio/transcriptions \
  -F file=@aufnahme.m4a -F language=de -F correct=true

# Lokale Datei oder Video-URL (yt-dlp)
curl -s -X POST http://127.0.0.1:47823/v1/transcribe \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://www.youtube.com/watch?v=…","language":"de"}'

# Nur korrigieren
curl -s -X POST http://127.0.0.1:47823/v1/correct \
  -H 'Content-Type: application/json' -d '{"text":"…"}'
```

Wörterbuch: `~/Library/Application Support/Eppur/vocabulary.txt` (eine Zeile pro Begriff) oder in den Einstellungen.

## Entwicklung

- App: `MoveAI/MoveAI.xcodeproj` – Debug-Builds heißen **„Eppur Dev“** (`app.eppur.Eppur.dev`) und berühren die Freigaben der installierten App nicht.
- Dienst: `MoveAIServer/` (Swift Package), installieren mit `MoveAIServer/install.sh`.
- Diagnose: `~/Library/Application Support/Eppur/app.log` und `server.log`.
