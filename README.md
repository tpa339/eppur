# Eppur

> *"Eppur si muove" – and yet it moves.*

Eppur is a macOS menu bar app for dictation and screenshots that runs **entirely on your Mac**:

- **Hold Fn and speak.** A waveform appears at the notch; when you release the key, the text is pasted into the active app.
- **Screenshots while you speak.** Clicking and scrolling keep working as usual, so you can switch windows while you talk; drag to capture a region, or press and hold on a window to capture it. The images go to the clipboard together with the text (text and PNG side by side) and their file paths are appended to the text.
- **Speech recognition:** [Parakeet TDT 0.6B v3](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) via [FluidAudio](https://github.com/FluidInference/FluidAudio) (CoreML, Neural Engine). German and English are detected automatically.
- **Correction:** Qwen 3.5 2B (4-bit, [MLX](https://github.com/ml-explore/mlx-swift-lm)) plus a vocabulary for names and technical terms. Rewrites are rejected; only spelling, casing, punctuation and vocabulary fixes are kept. Optionally use any OpenAI-compatible API (OpenAI, OpenRouter, Ollama, …) instead.
- **Local API, CLI and MCP** for agents and scripts – including files and YouTube links.

## Why "Eppur"?

Galileo Galilei is said to have muttered *"Eppur si muove"* – "and yet it moves" – after being forced in 1633 to recant that the Earth moves around the Sun. The quote is most likely legend (it first appears in print in 1757), but it stands for holding on to reality when everyone defends a comfortable assumption.

Eppur questions a few of those: that good speech recognition needs the cloud, that dictation is text only, and that screenshots have to be sent separately.

## Requirements

- macOS 26 or later
- **Apple silicon:** everything runs locally (Parakeet + Qwen).
- **Intel Macs:** the local models are not available. Speech recognition runs through an OpenAI-compatible API instead – suggested: [Mistral](https://console.mistral.ai) with `voxtral-small-transcribe-3-0`; OpenRouter or any other compatible server works too. Correction, vocabulary, CLI and MCP need the local service and are Apple-silicon only.
- Building from source: Xcode 27 with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)
- optional: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) for video URLs

## Install with an AI agent (copy & paste)

Paste this into Claude Code (or another coding agent with terminal access) on the Mac where Eppur should run:

```text
Install the macOS app Eppur from the GitHub repo tpa339/eppur for me.
1. Check `uname -m` and `sw_vers -productVersion` (macOS 26 or later is required; stop and tell me if it is older).
2. If the repo is private, make sure `gh auth status` works with access to tpa339/eppur; otherwise ask me to run `gh auth login`.
3. Apple silicon (arm64) with Xcode 27 installed: clone the repo to ~/eppur and run `./install.sh`
   (it builds the local service and the app; approve the keychain prompt with "Always Allow").
   Apple silicon without Xcode, or Intel (x86_64): run
   `gh release download --repo tpa339/eppur --pattern 'Eppur-*.zip' --dir "$TMPDIR/eppur-dl" --clobber`,
   unzip it with `ditto -x -k`, move Eppur.app to /Applications (replace an older copy),
   run `xattr -dr com.apple.quarantine /Applications/Eppur.app` and start it with `open /Applications/Eppur.app`.
4. Tell me what is left for me to do by hand: grant Microphone, Accessibility and (optional) Screen Recording
   in the setup window; set System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing";
   without the local service (Intel or prebuilt app): open Eppur → Settings → Speech recognition,
   choose provider "Mistral" (model voxtral-small-transcribe-3-0) or "OpenRouter" and paste my API key.
Do not handle or print my API keys yourself.
```

## Download (prebuilt app)

1. Download `Eppur-<version>.zip` from the [latest release](https://github.com/tpa339/eppur/releases/latest), unzip it and move `Eppur.app` to `/Applications`.
2. The app is signed with a self-made certificate, not notarized by Apple. On first launch macOS blocks it: open System Settings → Privacy & Security and click **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/Eppur.app`).
3. On an Intel Mac: Settings → Speech recognition → provider **Mistral**, paste your API key.

The prebuilt app contains no local models. On Apple silicon, run `./install.sh` from source to get the local service, or use an API as on Intel.

### Updates

Eppur checks GitHub releases every few hours (Settings → Updates, can be turned off). An update is installed only if it carries the same signature as the running app; Eppur then restarts. Permissions are kept.

Maintainers publish a release with `Eppur/scripts/release.sh` (universal build, ZIP, GitHub release for the current `MARKETING_VERSION`).

## Installation from source

```sh
git clone <repo-url> eppur && cd eppur
./install.sh
```

The script

1. creates a local code signing certificate "Eppur Local Signing" in your login keychain (once; asks for your password),
2. builds and installs the service to `~/Library/Application Support/Eppur/bin` and the `eppur` CLI to `~/.local/bin`,
3. builds the app and installs it to `/Applications/Eppur.app`.

On the first build, macOS asks whether `codesign` may use the key – choose **"Always Allow"**, otherwise the build hangs.

### Why a local certificate?

macOS remembers privacy permissions (microphone, accessibility, screen recording) per **bundle ID + code signature**. Without a stable signature, every rebuild counts as a new app and asks again. With the local certificate the identity stays stable: you grant permissions **once** and they survive updates. No Apple Developer account is required.

## Permissions

| Permission | Used for | Required |
|---|---|---|
| Microphone | Recording while Fn is held | yes |
| Accessibility | Detecting the Fn key, pasting text (Cmd+V) | yes |
| Screen Recording | Screenshots while speaking | only with screenshots |

Eppur shows a setup window on launch if something is missing. macOS occasionally asks on its own whether screen recording should stay allowed – that is system behavior.

Set System Settings → Keyboard → "Press 🌐 key to" to **Do Nothing**.

## Local API

The service listens on `127.0.0.1:47823` only.

```sh
# Status
curl -s http://127.0.0.1:47823/health

# Audio file (OpenAI-compatible), with correction
curl -s -X POST http://127.0.0.1:47823/v1/audio/transcriptions \
  -F file=@recording.m4a -F language=auto -F correct=true

# Local file or video URL (yt-dlp)
curl -s -X POST http://127.0.0.1:47823/v1/transcribe \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://www.youtube.com/watch?v=…"}'

# Correct text only
curl -s -X POST http://127.0.0.1:47823/v1/correct \
  -H 'Content-Type: application/json' -d '{"text":"…"}'
```

### Command line: `eppur`

```sh
eppur status                     # service and models
eppur list --limit 3             # latest dictations
eppur search "Parakeet"          # full-text search
eppur show 1a2b3c4d              # one dictation (short ID from list)
eppur transcribe video.mp4 --correct
eppur transcribe https://www.youtube.com/watch?v=…
eppur export --format md --out transcripts.md
eppur mcp                        # print the Claude Code setup command
```

### MCP for AI agents

```sh
claude mcp add --transport http --scope user eppur http://127.0.0.1:47823/mcp
```

Tools: `get_latest_transcript`, `list_transcripts`, `search_transcripts`, `get_transcript`, `transcribe_file`, `transcribe_url`, `correct_text`.

CLI and MCP can be turned off under Settings → Integrations. There is no access key: the endpoint is reachable from this Mac only, but any local program can use it while it is enabled.

Vocabulary: `~/Library/Application Support/Eppur/vocabulary.txt` (one term per line) or in Settings.

## Development

- App: `Eppur/Eppur.xcodeproj`. Debug builds are called **"Eppur Dev"** (`app.eppur.Eppur.dev`) and never touch the permissions of the installed app; while the installed app runs, a Dev build quits itself (set `EPPUR_DEV_TAKEOVER=1` to override).
- Service and CLI: `EppurServer/` (Swift package), install with `EppurServer/install.sh`.
- Diagnostics: `~/Library/Application Support/Eppur/app.log` and `server.log`.

The app UI is currently in German.

## License

Apache License 2.0 – see [LICENSE](LICENSE). Third-party libraries and models with their licenses are listed in [NOTICE](NOTICE). The models (Parakeet: CC-BY-4.0, Qwen 3.5: Apache-2.0) are downloaded on first launch and are not part of this repository.
