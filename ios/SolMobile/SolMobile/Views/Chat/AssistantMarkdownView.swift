import SwiftUI
import Foundation

#if canImport(Textual)
import Textual
#endif

enum AssistantMarkdownRenderMode: Equatable {
    case plainText
    case assistantMarkdown
}

enum AssistantMarkdownPolicy {
    static func renderMode(for creatorType: CreatorType) -> AssistantMarkdownRenderMode {
        creatorType == .assistant ? .assistantMarkdown : .plainText
    }
}

enum AssistantMarkdownSanitizer {
    static func prepareForRender(_ markdown: String) -> String {
        var output = markdown

        // Strip inline image markdown: ![alt](url)
        output = output.replacingOccurrences(
            of: #"!\[[^\]]*]\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )

        // Strip image reference markdown: ![alt][ref] and ![alt][]
        output = output.replacingOccurrences(
            of: #"!\[[^\]]*]\[[^\]]*]"#,
            with: "",
            options: .regularExpression
        )

        // Strip reference definitions (including image refs) for v0 safety.
        output = output.replacingOccurrences(
            of: #"(?m)^[ \t]{0,3}\[[^\]]+]:[^\n]*\n?"#,
            with: "",
            options: .regularExpression
        )

        let fenceCount = output.components(separatedBy: "```").count - 1
        if fenceCount % 2 != 0 {
            output += "\n```"
        }

        return output
    }
}

struct AssistantMarkdownView: View {
    let markdown: String

    private var renderableMarkdown: String {
        AssistantMarkdownSanitizer.prepareForRender(markdown)
    }

    var body: some View {
#if canImport(Textual)
        InlineText(markdown: renderableMarkdown)
            .textSelection(.enabled)
#else
        Text(renderableMarkdown)
            .textSelection(.enabled)
#endif
    }
}
