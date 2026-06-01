// WorkPanelTests/MCPServerAuthTests.swift
import Testing
@testable import WorkPanel

struct MCPServerAuthTests {
    @Test func acceptsMatchingBearerToken() {
        #expect(MCPServer.authorized(["authorization": "Bearer secret"], token: "secret"))
    }
    @Test func rejectsMissingOrWrongToken() {
        #expect(MCPServer.authorized([:], token: "secret") == false)
        #expect(MCPServer.authorized(["authorization": "Bearer nope"], token: "secret") == false)
    }
}
