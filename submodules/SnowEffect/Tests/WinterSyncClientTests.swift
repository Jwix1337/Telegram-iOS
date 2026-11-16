import Foundation
import XCTest
@testable import SnowEffect

private final class WinterSyncURLProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handle else { throw WinterSyncError.invalidData }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class WinterSyncClientTests: XCTestCase {
    private let device = "11111111-1111-4111-8111-111111111111"
    private let pair = "22222222-2222-4222-8222-222222222222"
    private func client() throws -> WinterSyncClient {
        let credentials = try WinterSyncCredentials(endpoint: URL(string: "https://winter.example")!, deviceID: device, token: String(repeating: "a", count: 43))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WinterSyncURLProtocol.self]
        return WinterSyncClient(credentials, configuration: configuration)
    }
    override func tearDown() { WinterSyncURLProtocol.handle = nil; super.tearDown() }

    func testRejectsInsecureAndCredentialBearingEndpoints() {
        for endpoint in ["http://winter.example", "https://token@winter.example", "https://winter.example?token=a", "https://winter.example/path"] {
            XCTAssertThrowsError(try WinterSyncCredentials(endpoint: URL(string: endpoint)!, deviceID: device, token: String(repeating: "a", count: 43)))
        }
    }
    func testIdentityUsesBearerAndNoTokenInURL() async throws {
        let client = try client(); defer { client.stop() }
        WinterSyncURLProtocol.handle = { request in
            XCTAssertEqual(request.url?.path, "/v1/device")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "a", count: 43))
            return (200, Data("{\"device_id\":\"\(self.device)\"}".utf8))
        }
        let identity = try await client.identity()
        XCTAssertEqual(identity, device)
    }
    func testPublishDoesNotSerializeTelegramIdentitiesOrLamportClock() async throws {
        let event = WinterEvent(type: .snowman_update, senderID: 12345, recipientID: 67890,
            sessionID: UUID().uuidString, mutation: SnowmanMutation(part: .bottom, value: 1, clock: 50))
        let request = WinterSyncRequest(event, pair: pair, expected: 2)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["version", "event_id", "pair_id", "type", "session_id", "expected_version", "mutation"]))
        XCTAssertEqual(object["expected_version"] as? Int, 2)
        XCTAssertNil((object["mutation"] as? [String: Any])?["clock"])
        XCTAssertEqual(object["event_id"] as? String, event.eventID.lowercased())
    }
    func testServerUnavailableDoesNotReportSuccessfulDelivery() async throws {
        let client = try client(); defer { client.stop() }
        WinterSyncURLProtocol.handle = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.publish(WinterSyncRequest(WinterEvent(type: .snowball, senderID: 1, recipientID: 2), pair: pair, expected: nil))
            XCTFail("An unavailable service must not acknowledge delivery")
        } catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
    }

    func testVersionConflictRemainsAnErrorForExplicitRetry() async throws {
        let client = try client(); defer { client.stop() }
        WinterSyncURLProtocol.handle = { _ in (409, Data("{\"detail\":\"version conflict\"}".utf8)) }
        do {
            _ = try await client.publish(WinterSyncRequest(WinterEvent(type: .snowball, senderID: 1, recipientID: 2), pair: pair, expected: nil))
            XCTFail("409 must not be treated as sent")
        } catch WinterSyncError.http(let status) { XCTAssertEqual(status, 409) }
    }
    func testSnapshotRequiresRealCreatorAndBoundedParts() throws {
        let valid = "{\"version\":1,\"cursor\":4,\"hats\":{},\"sessions\":[{\"session_id\":\"\(pair)\",\"version\":2,\"creator_id\":\"\(device)\",\"created_at\":1800000000,\"accepted\":true,\"completed\":false,\"parts\":{}}]}"
        let snapshot = try JSONDecoder().decode(WinterSyncSnapshot.self, from: Data(valid.utf8))
        XCTAssertTrue(try XCTUnwrap(snapshot.sessions.first).valid)
        let missing = valid.replacingOccurrences(of: "\"creator_id\":\"\(device)\",", with: "")
        XCTAssertThrowsError(try JSONDecoder().decode(WinterSyncSnapshot.self, from: Data(missing.utf8)))
    }
}
