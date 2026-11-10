//
//  HTTPServer.swift
//  Minimaler HTTP/1.1-Server auf Network.framework, nur an 127.0.0.1 gebunden.
//

import Foundation
import Network

struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }
}

struct HTTPResponse: Sendable {
    var status: Int
    var contentType: String
    var body: Data

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    static func jsonArray(_ array: [Any], status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["error": message], status: status)
    }
}

final class HTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let listener: NWListener
    private let handler: Handler
    private let queue = DispatchQueue(label: "eppur.http")
    private let maxBodyBytes = 1_500_000_000

    init(port: UInt16, handler: @escaping Handler) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
        self.handler = handler
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                FileHandle.standardError.write(Data("Listener-Fehler: \(error)\n".utf8))
                exit(1)
            }
        }
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = self.parse(buffer) {
                Task {
                    let response = await self.handler(request)
                    self.send(response, on: connection)
                }
                return
            }
            if buffer.count > self.maxBodyBytes {
                self.send(.error("Anfrage zu groß", status: 413), on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    /// Liefert die Anfrage, sobald Kopf und kompletter Body da sind.
    private func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return nil }
        let body = buffer[bodyStart..<(bodyStart + length)]

        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        components?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }

        return HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: Data(body)
        )
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let reason = [200: "OK", 202: "Accepted", 403: "Forbidden", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed",
                      413: "Payload Too Large", 500: "Internal Server Error", 503: "Service Unavailable"][response.status] ?? "OK"
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - Multipart

struct MultipartPart {
    var name: String
    var filename: String?
    var data: Data

    var string: String { String(decoding: data, as: UTF8.self) }
}

enum Multipart {
    static func parse(_ body: Data, contentType: String) -> [MultipartPart] {
        guard let boundaryRange = contentType.range(of: "boundary=") else { return [] }
        var boundary = String(contentType[boundaryRange.upperBound...])
        if let semicolon = boundary.firstIndex(of: ";") { boundary = String(boundary[..<semicolon]) }
        boundary = boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let delimiter = Data("--\(boundary)".utf8)

        var parts: [MultipartPart] = []
        var searchStart = body.startIndex
        var ranges: [Range<Data.Index>] = []
        while let range = body.range(of: delimiter, in: searchStart..<body.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        for (index, range) in ranges.enumerated() where index + 1 < ranges.count {
            var chunk = body[range.upperBound..<ranges[index + 1].lowerBound]
            if chunk.starts(with: Data("\r\n".utf8)) { chunk = chunk.dropFirst(2) }
            if chunk.suffix(2) == Data("\r\n".utf8) { chunk = chunk.dropLast(2) }
            guard let split = chunk.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let head = String(decoding: chunk[..<split.lowerBound], as: UTF8.self)
            let content = chunk[split.upperBound...]
            guard let name = value(of: "name", in: head) else { continue }
            parts.append(MultipartPart(name: name, filename: value(of: "filename", in: head), data: Data(content)))
        }
        return parts
    }

    private static func value(of key: String, in header: String) -> String? {
        // "; name=" darf nicht in "filename=" gefunden werden.
        guard let range = header.range(of: "; \(key)=\"") ?? header.range(of: " \(key)=\"") else { return nil }
        let rest = header[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
