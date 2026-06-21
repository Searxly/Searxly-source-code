//
//  SettingsBadge.swift
//  Searxly
//
//  Tiny reusable capsule badge for settings panes (Recommended, Protected, Active, On, etc.).
//  Created during settings UI rework to eliminate repeated manual .padding + .background + .clipShape patterns.
//  Consistent, minimal, uses subtle tinted backgrounds.
//

import SwiftUI

struct SettingsBadge: View {
    let text: String
    var tint: Color = .green

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
