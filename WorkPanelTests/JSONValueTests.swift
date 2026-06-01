// WorkPanelTests/JSONValueTests.swift
import Testing
import Foundation
@testable import WorkPanel

struct JSONValueTests {
    @Test func decodesObjectAndReadsTypedAccessors() throws {
        let data = Data(#"{"title":"写文档","count":3,"done":true,"tags":["a","b"]}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(v["title"]?.stringValue == "写文档")
        #expect(v["count"]?.intValue == 3)
        #expect(v["done"]?.boolValue == true)
        #expect(v["tags"]?.arrayValue?.compactMap(\.stringValue) == ["a", "b"])
        #expect(v["missing"] == nil)
    }

    @Test func contagiousNullVsAbsent() throws {
        let data = Data(#"{"deadline":null}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(v.contains("deadline"))
        #expect(v["deadline"]?.isNull == true)
        #expect(v.contains("other") == false)
    }

    @Test func encodesViaLiterals() throws {
        let v: JSONValue = ["type": "object", "n": 1, "ok": true, "list": ["x"]]
        let data = try JSONEncoder().encode(v)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(back["type"]?.stringValue == "object")
        #expect(back["n"]?.intValue == 1)
        #expect(back["ok"]?.boolValue == true)
        #expect(back["list"]?.arrayValue?.first?.stringValue == "x")
    }
}
