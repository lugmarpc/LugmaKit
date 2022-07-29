import AsyncHTTPClient
import WebSocketKit
import Foundation
import JSONValueRX

public protocol Stream {
    func on<T: Decodable>(event: String, _ callback: @escaping (T) async -> Void)
    func send<T: Encodable>(signal: String, item: T) async throws
}

public protocol Transport {
    associatedtype Extra

    func makeRequest<In: Codable, Out: Decodable, Err: Decodable>(endpoint: String, body: In, extra: Extra?) async throws -> Result<Out, Err>
    func openStream(endpoint: String, extra: Extra?) async throws -> Stream
}

public struct WebSocketStream: Stream {
    let ws: WebSocket
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(from socket: WebSocket) {
        self.ws = socket
    }

    private struct EncodableKinded<T: Encodable>: Encodable {
        let type: String
        let content: T
    }
    private struct DecodableKinded<T: Decodable>: Decodable {
        let type: String
        let content: T
    }

    public func on<T: Decodable>(event: String, _ callback: @escaping (T) async -> Void) {
        self.ws.onText { ws, txt in
            do {
                let kind = try decoder.decode(DecodableKinded<JSONValue>.self, from: txt.data(using: .utf8)!)
                guard kind.type == event else {
                    return
                }
                let inner: T = try kind.content.decode()
                await callback(inner)
            } catch { }
        }
    }

    public func send<T: Encodable>(signal: String, item: T) async throws {
        let json = try encoder.encode(EncodableKinded(type: signal, content: item))

        try await self.ws.send(raw: json, opcode: .text)
    }
}

public struct HTTPTransport: Transport {
    public typealias Extra = HTTPHeaders

    let client: HTTPClient
    let base: URL
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    public init(client: HTTPClient, base url: URL) {
        self.client = client
        self.base = url
    }

    public func makeRequest<In: Codable, Out: Decodable, Err: Decodable>(endpoint: String, body: In, extra: Extra?) async throws -> Result<Out, Err> {
        let body = try self.encoder.encode(body)
        let url = base.appendingPathComponent(endpoint).absoluteString
        var req = HTTPClientRequest(url: url)
        req.body = .bytes(body)
        req.headers = extra ?? HTTPHeaders()
        req.method = .POST
        req.url = url

        let resp = try await client.execute(req, timeout: .seconds(30))
        let respBody = try await resp.body.collect(upTo: 1024 * 1024) // 1 MB
        if resp.status == .ok {
            return try .success(decoder.decode(Out.self, from: respBody))
        } else {
            return try .failure(decoder.decode(Err.self, from: respBody))
        }
    }

    public func openStream(endpoint: String, extra: Extra?) async throws -> Stream {
        var extraDict: [String: String] = [:]
        for (head, val) in (extra ?? HTTPHeaders()) {
            extraDict[head] = val
        }
        let extraJSON = try encoder.encode(extraDict)

        let ws = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WebSocket, Error>) in
            Task {
                do {
                    try await WebSocket.connect(to: base.appendingPathComponent(endpoint), on: client.eventLoopGroup) { ws in
                        continuation.resume(returning: ws)
                    }.get()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        try await ws.send(raw: extraJSON, opcode: .binary)
        return WebSocketStream(from: ws)
    }
}
