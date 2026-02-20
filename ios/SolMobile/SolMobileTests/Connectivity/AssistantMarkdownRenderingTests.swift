import XCTest
@testable import SolMobile

@MainActor
final class AssistantMarkdownRenderingTests: XCTestCase {
    func test_assistantCreator_usesMarkdownRenderMode() {
        XCTAssertEqual(
            AssistantMarkdownPolicy.renderMode(for: .assistant),
            .assistantMarkdown
        )
    }

    func test_userAndSystemCreators_usePlainTextRenderMode() {
        XCTAssertEqual(
            AssistantMarkdownPolicy.renderMode(for: .user),
            .plainText
        )
        XCTAssertEqual(
            AssistantMarkdownPolicy.renderMode(for: .system),
            .plainText
        )
    }

    func test_markdownSanitizer_stripsInlineAndReferenceImages() {
        let input = """
        Before ![alt](https://cdn.example.com/image.png) middle ![chart][img-ref]
        [img-ref]: https://cdn.example.com/chart.png
        After
        """

        let output = AssistantMarkdownSanitizer.prepareForRender(input)

        XCTAssertFalse(output.contains("![alt]"))
        XCTAssertFalse(output.contains("![chart][img-ref]"))
        XCTAssertFalse(output.contains("[img-ref]:"))
        XCTAssertTrue(output.contains("Before"))
        XCTAssertTrue(output.contains("After"))
    }

    func test_markdownSanitizer_appendsClosingFenceWhenUnbalanced() {
        let input = """
        ```swift
        let x = 42
        """

        let output = AssistantMarkdownSanitizer.prepareForRender(input)

        XCTAssertTrue(output.hasSuffix("\n```"))
    }
}

@MainActor
final class ChatRequestContextEncodingTests: XCTestCase {
    func test_requestEncodesContextThreadMemento_whenProvided() throws {
        let memento = ThreadMementoDTO(
            id: "m-1",
            threadId: "t-1",
            createdAt: "2026-02-20T00:00:00Z",
            version: "memento-v0.2",
            arc: "Arc",
            active: ["a"],
            parked: ["p"],
            decisions: ["d"],
            next: ["n"]
        )

        let request = Request(
            threadId: "t-1",
            clientRequestId: "c-1",
            message: "hello",
            context: .init(threadMemento: memento)
        )

        let object = try decodeAsJSONObject(request)
        let context = try XCTUnwrap(object["context"] as? [String: Any])
        let encodedMemento = try XCTUnwrap(context["thread_memento"] as? [String: Any])

        XCTAssertEqual(encodedMemento["id"] as? String, "m-1")
        XCTAssertEqual(encodedMemento["version"] as? String, "memento-v0.2")
    }

    func test_requestOmitsContext_whenNoThreadMementoProvided() throws {
        let request = Request(
            threadId: "t-1",
            clientRequestId: "c-1",
            message: "hello",
            context: nil
        )

        let object = try decodeAsJSONObject(request)
        XCTAssertNil(object["context"])
    }

    private func decodeAsJSONObject(_ request: Request) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
