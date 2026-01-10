//
//  URLProtocolStub.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import Foundation

final class URLProtocolStub: URLProtocol {

    struct StubbedResponse {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    // Set per test.
    static var requestHandler: ((URLRequest) throws -> StubbedResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let stub = try handler(request)

            let url = request.url ?? URL(string: "http://localhost/")!
            let http = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!

            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
