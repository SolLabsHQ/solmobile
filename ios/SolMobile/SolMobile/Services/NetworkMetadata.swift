//
//  NetworkMetadata.swift
//  SolMobile
//
//  Created by SolMobile Networking.
//

import Foundation

nonisolated struct RedirectHop {
    let from: URL
    let to: URL
    let statusCode: Int
    let method: String?
}

nonisolated struct ResponseInfo {
    let statusCode: Int
    let headers: [String: String]
    let finalURL: URL?
    let redirectChain: [RedirectHop]
}

final class RedirectTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sollabshq.solmobile.redirect-tracker")
    private var chains: [String: [RedirectHop]] = [:]
    private let maxRedirects = 3

    func recordRedirect(taskKey: String, from: URL, to: URL, statusCode: Int, method: String?) {
        queue.sync {
            var chain = chains[taskKey] ?? []
            guard chain.count < maxRedirects else {
                chains[taskKey] = chain
                return
            }
            chain.append(RedirectHop(from: from, to: to, statusCode: statusCode, method: method))
            chains[taskKey] = chain
        }
    }

    func consumeChain(taskKey: String) -> [RedirectHop] {
        queue.sync {
            let chain = chains[taskKey] ?? []
            chains[taskKey] = nil
            return chain
        }
    }

    private func taskKey(for task: URLSessionTask) -> String {
        if let description = task.taskDescription, !description.isEmpty {
            return description
        }
        return String(task.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let fromURL = response.url ?? task.currentRequest?.url,
           let toURL = request.url {
            recordRedirect(
                taskKey: taskKey(for: task),
                from: fromURL,
                to: toURL,
                statusCode: response.statusCode,
                method: task.originalRequest?.httpMethod
            )
        }
        completionHandler(request)
    }
}
