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

final class RedirectTracker: NSObject, URLSessionTaskDelegate {
    private let queue = DispatchQueue(label: "com.sollabshq.solmobile.redirect-tracker")
    private var chains: [Int: [RedirectHop]] = [:]
    private let maxRedirects = 3

    func recordRedirect(taskId: Int, from: URL, to: URL, statusCode: Int, method: String?) {
        queue.sync {
            var chain = chains[taskId] ?? []
            guard chain.count < maxRedirects else {
                chains[taskId] = chain
                return
            }
            chain.append(RedirectHop(from: from, to: to, statusCode: statusCode, method: method))
            chains[taskId] = chain
        }
    }

    func consumeChain(taskId: Int) -> [RedirectHop] {
        queue.sync {
            let chain = chains[taskId] ?? []
            chains[taskId] = nil
            return chain
        }
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
                taskId: task.taskIdentifier,
                from: fromURL,
                to: toURL,
                statusCode: response.statusCode,
                method: task.originalRequest?.httpMethod
            )
        }
        completionHandler(request)
    }
}
