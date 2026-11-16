import Foundation

public struct WinterSyncCredentials: Codable {
    public let endpoint: URL
    public let deviceID: String
    public let token: String

    public init(endpoint: URL, deviceID: String, token: String) throws {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              endpoint.path.isEmpty || endpoint.path == "/",
              UUID(uuidString: deviceID)?.uuidString.lowercased() == deviceID,
              (32 ... 256).contains(token.utf8.count),
              token.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }) else {
            throw WinterSyncError.invalidData
        }
        var origin = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        origin.host = origin.host?.lowercased(); origin.path = ""
        if origin.port == 443 { origin.port = nil }
        guard let normalized = origin.url else { throw WinterSyncError.invalidData }
        self.endpoint = normalized
        self.deviceID = deviceID
        self.token = token
    }
}

public enum WinterSyncError: Error {
    case invalidData, responseTooLarge
    case http(Int)
}

struct WinterSyncPair: Codable {
    let id: String
    let a: String
    let b: String
    let ca: Int
    let cb: Int
    let revoked: Int
    func other(_ own: String) -> String? {
        guard revoked == 0, a != b, a == own || b == own,
              UUID(uuidString: id) != nil, UUID(uuidString: a) != nil, UUID(uuidString: b) != nil else { return nil }
        return a == own ? b : a
    }
    var active: Bool { ca == 1 && cb == 1 && revoked == 0 }
}

struct WinterSyncHat: Codable, Equatable {
    let hat_id: Int
    let enabled: Bool
    let scale: Double
    let x: Double
    let y: Double
    let rotation: Double
    init(_ hat: SnowHatConfiguration) {
        hat_id = hat.hatID; enabled = hat.enabled; scale = hat.scale
        x = hat.offsetX; y = hat.offsetY; rotation = hat.rotation
    }
    func configuration(owner: Int64, timestamp: Int64) -> SnowHatConfiguration? {
        let result = SnowHatConfiguration(ownerID: owner, hatID: hat_id, enabled: enabled,
            scale: scale, offsetX: x, offsetY: y, rotation: rotation, modifiedAt: timestamp)
        return result.isValid ? result : nil
    }
}

struct WinterSyncMutation: Codable {
    let part: SnowmanPart
    let value: Int
}

struct WinterSyncRequest: Codable {
    let version: Int
    let event_id: String
    let pair_id: String
    let type: WinterEvent.Kind
    let session_id: String?
    let expected_version: Int64?
    let hat: WinterSyncHat?
    let mutation: WinterSyncMutation?

    var valid: Bool {
        guard version == 1, UUID(uuidString: event_id)?.uuidString.lowercased() == event_id,
              UUID(uuidString: pair_id)?.uuidString.lowercased() == pair_id else { return false }
        switch type {
        case .hat: return hat?.configuration(owner: 1, timestamp: 1) != nil && mutation == nil && session_id == nil && expected_version == nil
        case .snowball: return hat == nil && mutation == nil && session_id == nil && expected_version == nil
        default:
            guard let id = session_id, UUID(uuidString: id)?.uuidString.lowercased() == id,
                  let version = expected_version, (0 ... 1_000_000).contains(version), hat == nil else { return false }
            if type == .snowman_update {
                guard let mutation else { return false }
                return SnowmanMutation(part: mutation.part, value: mutation.value, clock: 1).isValid
            }
            return mutation == nil
        }
    }

    init(_ event: WinterEvent, pair: String, expected: Int64?) {
        version = 1; event_id = event.eventID.lowercased(); pair_id = pair
        type = event.type; session_id = event.sessionID?.lowercased()
        expected_version = expected; hat = event.hat.map(WinterSyncHat.init)
        mutation = event.mutation.map { WinterSyncMutation(part: $0.part, value: $0.value) }
    }
}

struct WinterSyncSession: Codable {
    let session_id: String
    let version: Int64
    let creator_id: String
    let created_at: Double
    let accepted: Bool
    let completed: Bool
    let parts: [String: Int]
    var valid: Bool {
        UUID(uuidString: session_id) != nil && UUID(uuidString: creator_id) != nil && (1 ... 1_000_000).contains(version)
            && created_at.isFinite && created_at > 0 && created_at < 4_000_000_000
            && parts.count <= 10 && parts.allSatisfy { key, value in
                guard let part = SnowmanPart(rawValue: key) else { return false }
                return SnowmanMutation(part: part, value: value, clock: 1).isValid
            } && (!completed || (accepted && SnowmanPart.assembly.allSatisfy { parts[$0.rawValue] == 1 }))
    }
}

struct WinterSyncSnapshot: Codable {
    let version: Int
    let cursor: Int64
    let hats: [String: WinterSyncHat]
    let sessions: [WinterSyncSession]
}

struct WinterSyncEnvelope: Codable {
    let version: Int
    let cursor: Int64
    let event: WinterSyncRequest
    let sender_id: String
    let created_at: Double
    let state: WinterSyncSession?
}
struct WinterSyncBatch: Codable { let events: [WinterSyncEnvelope] }
struct WinterSyncCode: Decodable { let code: String; let expires_in: Int }
struct WinterSyncClaim: Decodable { let pair_id: String }
private struct WinterSyncIdentity: Decodable { let device_id: String }
private struct WinterSyncActive: Decodable { let active: Bool }
private struct WinterSyncRevoked: Decodable { let revoked: Bool }

/// Uses system TLS validation, no cookies/cache, no credential-bearing redirects or URLs.
private final class WinterSyncRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class WinterSyncClient {
    let credentials: WinterSyncCredentials
    private let session: URLSession
    init(_ credentials: WinterSyncCredentials, configuration: URLSessionConfiguration? = nil) {
        self.credentials = credentials
        let configuration = (configuration?.copy() as? URLSessionConfiguration) ?? .ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration, delegate: WinterSyncRedirectGuard(), delegateQueue: nil)
    }
    func stop() { session.invalidateAndCancel() }
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: credentials.endpoint.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw WinterSyncError.invalidData }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard (body?.count ?? 0) <= 8192 else { throw WinterSyncError.responseTooLarge }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw WinterSyncError.invalidData }
        guard (200 ... 299).contains(response.statusCode) else { throw WinterSyncError.http(response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw WinterSyncError.responseTooLarge }
            data.append(byte)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func identity() async throws -> String {
        let identity: WinterSyncIdentity = try await request("v1/device")
        return identity.device_id
    }
    func pairs() async throws -> [WinterSyncPair] { try await request("v1/pairs") }
    func code() async throws -> WinterSyncCode { try await request("v1/pair-codes", method: "POST") }
    func claim(_ code: String) async throws -> String {
        let result: WinterSyncClaim = try await request("v1/pairs/claim", method: "POST", body: JSONEncoder().encode(["code": code]))
        return result.pair_id
    }
    func confirm(_ pair: String) async throws -> Bool {
        let response: WinterSyncActive = try await request("v1/pairs/\(pair)/confirm", method: "POST")
        return response.active
    }
    func revoke(_ pair: String) async throws {
        let _: WinterSyncRevoked = try await request("v1/pairs/\(pair)", method: "DELETE")
    }
    func snapshot(_ pair: String) async throws -> WinterSyncSnapshot { try await request("v1/pairs/\(pair)/state") }
    func events(after: Int64) async throws -> WinterSyncBatch { try await request("v1/events", query: [URLQueryItem(name: "after", value: String(after))]) }
    func publish(_ event: WinterSyncRequest) async throws -> WinterSyncEnvelope {
        try await request("v1/events", method: "POST", body: JSONEncoder().encode(event))
    }
    func socket(after: Int64) async throws -> URLSessionWebSocketTask {
        var components = URLComponents(url: credentials.endpoint.appendingPathComponent("v1/ws"), resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        guard let url = components.url else { throw WinterSyncError.invalidData }
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 1_048_576
        socket.resume()
        let hello: [String: Any] = ["token": credentials.token, "after": after]
        let data = try JSONSerialization.data(withJSONObject: hello)
        do {
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
            return socket
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            throw error
        }
    }
}
