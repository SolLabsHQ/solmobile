//
//  ShareSheetView.swift
//  SolMobile
//

import SwiftUI

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: (Bool, String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            completion(completed, activityType?.rawValue)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
