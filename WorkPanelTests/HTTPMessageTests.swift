// WorkPanelTests/HTTPMessageTests.swift
import Testing
import Foundation
@testable import WorkPanel

struct HTTPMessageTests {
    @Test func parsesPostWithHeadersAndBody() {
        let raw = "POST /mcp HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer abc\r\nContent-Length: 7\r\n\r\n{\"a\":1}"
        let req = HTTPRequest.parse(Data(raw.utf8))
        #expect(req?.method == "POST")
        #expect(req?.path == "/mcp")
        #expect(req?.headers["authorization"] == "Bearer abc")   // keys lowercased
        #expect(req?.headers["content-length"] == "7")
        #expect(req?.body == Data("{\"a\":1}".utf8))
        #expect(req?.isComplete == true)
    }

    @Test func incompleteHeadersReturnNil() {
        #expect(HTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nHost: loc".utf8)) == nil)
    }

    @Test func incompleteBodyIsNotComplete() {
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort"
        #expect(HTTPRequest.parse(Data(raw.utf8))?.isComplete == false)
    }

    @Test func buildsResponses() {
        let json = HTTPResponse.json(Data("{}".utf8))
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{}"))

        #expect(String(decoding: HTTPResponse.unauthorized(), as: UTF8.self).hasPrefix("HTTP/1.1 401"))
        #expect(String(decoding: HTTPResponse.methodNotAllowed(), as: UTF8.self).hasPrefix("HTTP/1.1 405"))
        #expect(String(decoding: HTTPResponse.accepted(), as: UTF8.self).hasPrefix("HTTP/1.1 202"))
    }
}
