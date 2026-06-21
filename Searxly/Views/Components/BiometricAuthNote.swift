//
//  BiometricAuthNote.swift
//  Searxly
//
//  Small reusable explainer shown in Onboarding (App Lock step) and Settings.
//  Educates the user that the first time they use App Lock, macOS will present
//  its own system prompt for Touch ID / password. This is the "permission" flow.
//

import SwiftUI

struct BiometricAuthNote: View {
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                Image(systemName: "touchid")
                    .foregroundStyle(Color.white.opacity(0.75))
                Text("Touch ID & Password")
                    .font(compact ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }

            Text("Searxly uses macOS LocalAuthentication. The first time you enable or unlock with App Lock, your Mac will ask for Touch ID (or your login password). This is a standard secure system prompt — Searxly never sees or stores your password.")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 8 : 10)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 20) {
        BiometricAuthNote()
            .frame(width: 420)
        BiometricAuthNote(compact: true)
            .frame(width: 420)
    }
    .padding()
    .background(Color.black)
}
