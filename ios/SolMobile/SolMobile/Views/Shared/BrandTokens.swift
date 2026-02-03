//
//  BrandTokens.swift
//  SolMobile
//

import SwiftUI

enum BrandColors {
    static let deepSpace = Color(red: 0.0, green: 0.094, blue: 0.271)
    static let deepSpaceAlt = Color(red: 0.02, green: 0.04, blue: 0.12)
    static let gold = Color(red: 0.95, green: 0.82, blue: 0.32)
    static let slate = Color(red: 0.12, green: 0.14, blue: 0.2)
    static let userBubbleFill = Color(red: 0.38, green: 0.4, blue: 0.5).opacity(0.42)
    static let userBubbleText = Color.white.opacity(0.92)
    static let assistantBubbleText = Color.white.opacity(0.9)
    static let statusText = Color.white.opacity(0.85)
    static let timeLaneText = Color.white.opacity(0.72)
    static let iconAction = BrandColors.gold.opacity(0.95)
    static let userBubble = userBubbleFill
    static let assistantBubble = Color.white.opacity(0.08)
    static let glassStroke = Color.white.opacity(0.12)
    static let badgeFill = Color.white.opacity(0.12)
    static let badgeText = Color.white.opacity(0.9)
    static let error = Color(red: 0.92, green: 0.32, blue: 0.32)
    static let errorFill = Color(red: 0.92, green: 0.32, blue: 0.32).opacity(0.18)
    static let cardFill = slate.opacity(0.35)
}

enum BrandGradients {
    static let deepSpace = LinearGradient(
        colors: [BrandColors.deepSpace, BrandColors.deepSpaceAlt],
        startPoint: .top,
        endPoint: .bottom
    )
}
