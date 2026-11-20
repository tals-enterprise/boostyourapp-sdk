import Foundation
import XCTest
@testable import BoostNetwork

/// Serveur simulé : intercepte les requêtes de la session de test.
private final class StubProtocol: URLProtocol {
    static var status = 200
    static var response = Data()
    static var lastRequest: URLRequest?
    static var lastBody = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        StubProtocol.lastRequest = request
        StubProtocol.lastBody = StubProtocol.body(of: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: StubProtocol.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubProtocol.response)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession transmet le corps sous forme de flux aux URLProtocol
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class ApiTests: XCTestCase {
    private let device = DeviceInfo(lang: "en", os: "iOS 17")

    private func client(baseUrl: String = "https://example.supabase.co/") -> ApiClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return ApiClient(baseUrl: baseUrl, apiKey: "sb_publishable_test", sdkVersion: "9.9.9",
                         session: URLSession(configuration: configuration))
    }

    private func json(_ data: Data) -> [String: Any] {
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func testNextSendsTheSqlParametersAndHeaders() {
        StubProtocol.status = 200
        StubProtocol.response = Data("""
        {"ads":[{"id":"a1","name":"Météo","descriptions":["Un","Deux"],"languageCode":"fr","iconUrl":"https://i/1.png",
        "rating":4.5,"cta":"Gratuit","rotationSeconds":99,"token":"tok1"},{"id":"broken"}],
        "refreshSeconds":5,"accepted":2,"rejected":1}
        """.utf8)

        let done = expectation(description: "next")
        var received: Result<NextResponse, ApiError>?
        let request = NextRequest(appKey: "bya_key", installationId: "1b4e28ba-2fa1-11d2-883f-0016d3cca427",
                                  device: DeviceInfo(lang: "fr-FR", os: "iOS 17"),
                                  recent: ["r1"], impressions: ["i1", "i2"])
        client().next(request) { result in
            received = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        let sent = StubProtocol.lastRequest!
        XCTAssertEqual(sent.url?.absoluteString, "https://example.supabase.co/rest/v1/rpc/network_next")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Client-Info"), "boostnetwork-ios/9.9.9")

        let body = json(StubProtocol.lastBody)
        XCTAssertEqual(Set(body.keys), ["p_app_key", "p_installation_id", "p_lang", "p_os",
                                        "p_recent", "p_impressions"])
        XCTAssertEqual(body["p_app_key"] as? String, "bya_key")
        XCTAssertEqual(body["p_lang"] as? String, "fr-FR")
        XCTAssertEqual(body["p_os"] as? String, "iOS 17")
        XCTAssertEqual(body["p_recent"] as? [String], ["r1"])
        XCTAssertEqual(body["p_impressions"] as? [String], ["i1", "i2"])

        guard case .success(let response)? = received else { return XCTFail("réponse attendue") }
        // La pub sans jeton est ignorée ; durées ramenées dans leurs bornes
        XCTAssertEqual(response.ads.count, 1)
        XCTAssertEqual(response.ads[0].name, "Météo")
        XCTAssertEqual(response.ads[0].descriptions, ["Un", "Deux"])
        XCTAssertEqual(response.ads[0].rating, 4.5)
        XCTAssertEqual(response.ads[0].rotationSeconds, 30)
        XCTAssertEqual(response.refreshSeconds, 15)
        XCTAssertEqual(response.accepted, 2)
        XCTAssertEqual(response.rejected, 1)
    }

    func testServerErrorsCarryThePostgrestMessage() {
        StubProtocol.status = 400
        StubProtocol.response = Data(#"{"code":"P0001","details":null,"hint":null,"message":"unknown_app"}"#.utf8)

        let done = expectation(description: "next")
        var received: Result<NextResponse, ApiError>?
        client().next(NextRequest(appKey: "x", installationId: "y", device: device, recent: [], impressions: [])) { result in
            received = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(received, .failure(ApiError(code: "unknown_app", status: 400)))
    }

    func testNextSendsCountAndCachedVersions() {
        StubProtocol.status = 200
        StubProtocol.response = Data(#"{"ads":[],"refreshSeconds":60,"accepted":0,"rejected":0}"#.utf8)

        var done = expectation(description: "report")
        client().next(NextRequest(appKey: "k", installationId: "i", device: device, recent: [], impressions: ["t1"], count: 0)) { _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        var body = json(StubProtocol.lastBody)
        XCTAssertEqual(body["p_count"] as? Int, 0)
        XCTAssertNil(body["p_cached"])

        done = expectation(description: "cached")
        client().next(NextRequest(appKey: "k", installationId: "i", device: device, recent: [], impressions: [],
                                  cached: ["v1", "v2"])) { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        body = json(StubProtocol.lastBody)
        XCTAssertNil(body["p_count"])
        XCTAssertEqual(body["p_cached"] as? [String], ["v1", "v2"])
    }

    func testAdWithoutContentComesFromTheCacheOrIsSkipped() throws {
        let data = Data("""
        {"ads":[{"id":"a","version":"v1","token":"tok-a"},{"id":"b","version":"v9","token":"tok-b"},
        {"id":"c","name":"C","descriptions":["x"],"languageCode":"en","iconUrl":null,"rating":null,
        "cta":"Free","rotationSeconds":30,"version":"v3","token":"tok-c"}],
        "refreshSeconds":60,"accepted":0,"rejected":0}
        """.utf8)
        let cachedA = Ad(id: "a", name: "A", descriptions: ["y"], languageCode: "fr", iconUrl: "https://i", rating: 4,
                         cta: "Gratuit", rotationSeconds: 15, token: "", version: "v1")
        let response = try ApiJson.parseNext(data) { id, version in id == "a" && version == "v1" ? cachedA : nil }
        XCTAssertEqual(response.ads.map { $0.id }, ["a", "c"])
        XCTAssertEqual(response.ads[0], cachedA.with(token: "tok-a"))
        XCTAssertEqual(response.ads[1].version, "v3")
        XCTAssertEqual(response.ads[1].token, "tok-c")
    }

    func testHostLookAndScreenshotsSurviveTheCache() throws {
        let data = Data("""
        {"ads":[{"id":"a","name":"A","descriptions":["x"],"languageCode":"en","iconUrl":null,"rating":null,
        "cta":"Free","rotationSeconds":30,"version":"v1","token":"tok-a",
        "screenshots":["https://s.test/1.png","javascript:alert(1)","https://s.test/2.png","https://s.test/3.png","https://s.test/4.png"]},
        {"id":"b","name":"B","descriptions":["y"],"languageCode":"en","iconUrl":null,"rating":null,
        "cta":"Free","rotationSeconds":30,"token":"tok-b"}],
        "look":{"style":"dynamic","colors":{"background":"#0369A1","background2":"#4F46E5","title":"#FFFFFF","button":"blanc"},
        "pattern":"grid","font":"serif"},
        "refreshSeconds":60,"accepted":0,"rejected":0}
        """.utf8)
        let response = try ApiJson.parseNext(data) { _, _ in nil }
        // 3 captures au plus, adresses http(s) seulement
        XCTAssertEqual(response.ads[0].screenshots, ["https://s.test/1.png", "https://s.test/2.png", "https://s.test/3.png"])
        XCTAssertEqual(response.ads[1].screenshots, [])
        XCTAssertEqual(ApiJson.parseContent(ApiJson.contentJson(response.ads[0])), response.ads[0].with(token: ""))
        // Rendu de l'app : couleur mal formée ignorée (celle du style par défaut), gardé tel quel
        let look = try XCTUnwrap(response.look)
        XCTAssertEqual(look.style, "dynamic")
        XCTAssertEqual(look.colors, ["background": "#0369A1", "background2": "#4F46E5", "title": "#FFFFFF"])
        XCTAssertEqual(look.pattern, "grid")
        XCTAssertEqual(look.font, "serif")
        XCTAssertEqual(ApiJson.parseLook(ApiJson.lookJson(look)), look)
    }

    func testNextSendsTheRequestedStyle() throws {
        var request = NextRequest(appKey: "k", installationId: "i", device: DeviceInfo(lang: "en", os: "iOS 17"),
                                  recent: [], impressions: [], style: "dynamic", palette: "neon")
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: ApiJson.nextRequest(request)) as? [String: Any])
        XCTAssertEqual(body["p_style"] as? String, "dynamic")
        XCTAssertEqual(body["p_palette"] as? String, "neon")
        // Sans setStyle : rien d'envoyé, le serveur prend le standard
        request.style = nil
        request.palette = nil
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: ApiJson.nextRequest(request)) as? [String: Any])
        XCTAssertNil(body["p_style"])
    }

    func testInterstitialRequestAndSettings() throws {
        var request = NextRequest(appKey: "k", installationId: "i", device: DeviceInfo(lang: "en", os: "iOS 17"),
                                  recent: [], impressions: [], count: 1, format: "interstitial")
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: ApiJson.nextRequest(request)) as? [String: Any])
        XCTAssertEqual(body["p_format"] as? String, "interstitial")
        request.format = nil
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: ApiJson.nextRequest(request)) as? [String: Any])
        XCTAssertNil(body["p_format"])

        let json = """
        {"ads":[{"id":"a","name":"A","descriptions":["Une *longue* histoire"],"cta":"Get","token":"t.i.s"}],
         "refreshSeconds":60,"accepted":0,"rejected":0,"interstitial":{"closeSeconds":3,"intervalSeconds":99999}}
        """
        let response = try ApiJson.parseNext(Data(json.utf8))
        XCTAssertEqual(response.interstitial, InterstitialConfig(closeSeconds: 3, intervalSeconds: 3600))
        XCTAssertEqual(response.ads.first?.token, "t.i.s")
        let banner = try ApiJson.parseNext(Data(#"{"ads":[],"refreshSeconds":60,"accepted":0,"rejected":0}"#.utf8))
        XCTAssertNil(banner.interstitial)
        let config = InterstitialConfig(closeSeconds: 3, intervalSeconds: 120)
        XCTAssertEqual(ApiJson.parseInterstitial(ApiJson.interstitialJson(config)), config)
    }

    func testClickReturnsTheStoreUrl() {
        StubProtocol.status = 200
        StubProtocol.response = Data(#"{"url":"https://apps.apple.com/app/id123"}"#.utf8)

        let done = expectation(description: "click")
        var received: Result<String, ApiError>?
        client().click("tok") { result in
            received = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(json(StubProtocol.lastBody) as NSDictionary, ["p_token": "tok"])
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/rest/v1/rpc/network_click")
        XCTAssertEqual(received, .success("https://apps.apple.com/app/id123"))
    }

    func testClickSendsLanguageAndSystem() {
        StubProtocol.status = 200
        StubProtocol.response = Data(#"{"url":"https://apps.apple.com/app/id123"}"#.utf8)

        let done = expectation(description: "click")
        client().click("tok", device: DeviceInfo(lang: "fr-FR", os: "iOS 17")) { _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(json(StubProtocol.lastBody) as NSDictionary,
                       ["p_token": "tok", "p_lang": "fr-FR", "p_os": "iOS 17"])
    }

    func testUnreachableServerIsANetworkError() {
        let done = expectation(description: "next")
        var received: Result<NextResponse, ApiError>?
        // Port fermé : connexion refusée
        ApiClient(baseUrl: "http://127.0.0.1:9", apiKey: "k", sdkVersion: "1")
            .next(NextRequest(appKey: "x", installationId: "y", device: device, recent: [], impressions: [])) { result in
                received = result
                done.fulfill()
            }
        wait(for: [done], timeout: 20)

        XCTAssertEqual(received, .failure(ApiError(code: "network", status: 0)))
    }
}
