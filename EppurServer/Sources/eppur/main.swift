//
//  eppur – Kommandozeile für den lokalen Eppur-Dienst (127.0.0.1:47823)
//
//  eppur status
//  eppur list [--limit N]            letzte Diktate
//  eppur latest                      neuestes Diktat
//  eppur search <text> [--limit N]   Volltextsuche
//  eppur show <id>                   ein Diktat
//  eppur transcribe <datei|url> [--lang de|en] [--correct]
//  eppur correct "<text>"
//  eppur export [--format md|txt|json] [--limit N] [--out datei]
//  eppur mcp                         Befehl zum Einrichten in Claude Code
//  Option überall: --json (rohe Antwort)
//

import Foundation

let port = ProcessInfo.processInfo.environment["EPPUR_PORT"] ?? "47823"
let base = "http://127.0.0.1:\(port)"

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i); return true
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]; args.removeSubrange(i...(i + 1)); return value
}

let rawJSON = flag("--json")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("eppur: \(message)\n".utf8))
    exit(1)
}

func request(_ method: String, _ path: String, body: [String: Any]? = nil, timeout: TimeInterval = 30) async -> Any {
    var components = URLComponents(string: base + path)!
    if path.contains("?") { components = URLComponents(string: base + path)! }
    var req = URLRequest(url: components.url!)
    req.httpMethod = method
    req.timeoutInterval = timeout
    if let body {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    do {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        if !(200..<300).contains(status) {
            fail(((json as? [String: Any])?["error"] as? String) ?? "HTTP \(status)")
        }
        return json
    } catch {
        fail("Eppur-Dienst nicht erreichbar (\(base)). Läuft die Eppur-App?")
    }
}

func printJSON(_ value: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    print(String(decoding: data, as: UTF8.self))
}

func shortDate(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    guard let date = parser.date(from: iso) else { return iso }
    let out = DateFormatter(); out.dateFormat = "dd.MM.yy HH:mm"
    return out.string(from: date)
}

func printEntries(_ value: Any) {
    guard let entries = value as? [[String: Any]] else { return printJSON(value) }
    if entries.isEmpty { print("(keine Einträge)"); return }
    for e in entries {
        let id = (e["id"] as? String ?? "").prefix(8)
        let images = (e["images"] as? [String])?.count ?? 0
        let text = (e["text"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
        let preview = text.count > 100 ? String(text.prefix(100)) + "…" : text
        print("\(shortDate(e["date"] as? String ?? ""))  \(id)\(images > 0 ? "  📷\(images)" : "")  \(preview)")
    }
}

func encodedQuery(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? s
}

let usage = """
eppur – lokaler Zugriff auf Eppur

  eppur status
  eppur list [--limit N]
  eppur latest
  eppur search <text> [--limit N]
  eppur show <id>
  eppur transcribe <datei|url> [--lang de|en] [--correct]
  eppur correct "<text>"
  eppur export [--format md|txt|json] [--limit N] [--out datei]
  eppur mcp
  Option: --json  (rohe JSON-Ausgabe)
"""

let limit = option("--limit")
let lang = option("--lang")
let format = option("--format") ?? "md"
let outPath = option("--out")
let correct = flag("--correct")
let command = args.first ?? "help"
let rest = Array(args.dropFirst())

switch command {
case "status":
    let health = await request("GET", "/health")
    if rawJSON { printJSON(health); break }
    let h = health as? [String: Any] ?? [:]
    func mark(_ key: String) -> String { (h[key] as? Bool) == true ? "✓" : "…" }
    print("Eppur-Dienst: \(base)")
    print("  Parakeet  \(mark("asr_ready"))   Qwen  \(mark("correction_ready"))   yt-dlp  \(mark("yt_dlp"))")

case "list":
    let value = await request("GET", "/v1/transcripts?limit=\(limit ?? "10")")
    rawJSON ? printJSON(value) : printEntries(value)

case "latest":
    let value = await request("GET", "/v1/transcripts/latest")
    if rawJSON { printJSON(value); break }
    let e = value as? [String: Any] ?? [:]
    print(e["text"] as? String ?? "(kein Diktat)")
    for path in e["images"] as? [String] ?? [] { print("[Screenshot: \(path)]") }

case "search":
    guard let query = rest.first else { fail("Suchtext fehlt") }
    let value = await request("GET", "/v1/transcripts?limit=\(limit ?? "20")&query=\(encodedQuery(query))")
    rawJSON ? printJSON(value) : printEntries(value)

case "show":
    guard let prefix = rest.first?.lowercased() else { fail("ID fehlt") }
    // Kurz-IDs aus „eppur list“ (8 Zeichen) zulassen.
    let all = await request("GET", "/v1/transcripts?limit=500") as? [[String: Any]] ?? []
    guard let entry = all.first(where: { ($0["id"] as? String ?? "").lowercased().hasPrefix(prefix) }) else { fail("Kein Diktat \(prefix)") }
    if rawJSON { printJSON(entry); break }
    print("\(shortDate(entry["date"] as? String ?? ""))  ·  \(entry["engine"] as? String ?? "")")
    print(entry["text"] as? String ?? "")
    if let raw = entry["raw_text"] as? String { print("\nOriginal vor Korrektur:\n\(raw)") }
    for path in entry["images"] as? [String] ?? [] { print("[Screenshot: \(path)]") }

case "transcribe":
    guard let target = rest.first else { fail("Datei oder URL fehlt") }
    var body: [String: Any] = ["correct": correct]
    if let lang { body["language"] = lang }
    if target.hasPrefix("http://") || target.hasPrefix("https://") {
        body["url"] = target
    } else {
        body["path"] = URL(fileURLWithPath: (target as NSString).expandingTildeInPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL.path
    }
    let value = await request("POST", "/v1/transcribe", body: body, timeout: 3600)
    if rawJSON { printJSON(value); break }
    print((value as? [String: Any])?["text"] as? String ?? "")

case "correct":
    guard let text = rest.first else { fail("Text fehlt") }
    let value = await request("POST", "/v1/correct", body: ["text": text], timeout: 120)
    rawJSON ? printJSON(value) : print((value as? [String: Any])?["text"] as? String ?? "")

case "export":
    let entries = await request("GET", "/v1/transcripts?limit=\(limit ?? "500")") as? [[String: Any]] ?? []
    var output = ""
    switch format {
    case "json":
        output = String(decoding: (try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])) ?? Data(), as: UTF8.self)
    case "txt":
        output = entries.map { "\(shortDate($0["date"] as? String ?? ""))\n\($0["text"] as? String ?? "")\n" }.joined(separator: "\n")
    default:
        output = "# Eppur-Transkripte\n\n" + entries.map { e in
            var block = "## \(shortDate(e["date"] as? String ?? ""))\n\n\(e["text"] as? String ?? "")\n"
            for path in e["images"] as? [String] ?? [] { block += "\n![Screenshot](\(path))\n" }
            return block
        }.joined(separator: "\n")
    }
    if let outPath {
        do { try output.write(toFile: (outPath as NSString).expandingTildeInPath, atomically: true, encoding: .utf8) }
        catch { fail("Konnte \(outPath) nicht schreiben: \(error.localizedDescription)") }
        print("\(entries.count) Einträge → \(outPath)")
    } else {
        print(output)
    }

case "mcp":
    print("claude mcp add --transport http eppur \(base)/mcp")

case "help", "-h", "--help":
    print(usage)

default:
    fail("Unbekannter Befehl „\(command)“\n\n\(usage)")
}
