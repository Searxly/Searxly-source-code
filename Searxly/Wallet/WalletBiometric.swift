//
//  WalletBiometric.swift
//  Searxly
//
//  Face ID / Touch ID gate for the wallet. Uses a dedicated LAContext so it does NOT
//  alter the app-wide App Lock session state. The 6-digit PIN remains the explicit
//  in-app fallback whenever biometrics are unavailable or fail.
//

import Foundation
import LocalAuthentication

@MainActor
enum WalletBiometric {
    // Kept alive for the duration of an evaluation; releasing an LAContext mid-evaluation
    // can terminate the prompt (and historically the app).
    private static var activeContext: LAContext?

    static var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var label: String {
        switch biometryType {
        case .touchID: return "Touch ID"
        case .faceID:  return "Face ID"
        case .opticID: return "Optic ID"
        default:       return "Biometrics"
        }
    }

    static var symbol: String {
        switch biometryType {
        case .touchID: return "touchid"
        case .faceID:  return "faceid"
        case .opticID: return "opticid"
        default:       return "lock.fill"
        }
    }

    /// Presents a biometric prompt and, on success, returns the authenticated LAContext so a
    /// follow-up read of a biometry-gated Keychain item reuses this auth instead of prompting again.
    /// Returns nil on cancel / failure / no biometrics.
    static func authenticatedContext(reason: String) async -> LAContext? {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.touchIDAuthenticationAllowableReuseDuration = 10   // let the Keychain reuse this match
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return nil }
        let ok: Bool = await withCheckedContinuation { cont in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                cont.resume(returning: success)
            }
        }
        return ok ? context : nil
    }

    /// Presents a biometric prompt. Returns true only on a successful biometric match.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        activeContext = context

        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            activeContext = nil
            return false
        }

        let ok: Bool = await withCheckedContinuation { cont in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                cont.resume(returning: success)
            }
        }
        activeContext = nil
        return ok
    }
}
