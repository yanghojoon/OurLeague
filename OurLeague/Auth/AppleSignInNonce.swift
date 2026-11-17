//
//  AppleSignInNonce.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/16.
//

import CryptoKit
import Foundation
import Security

struct AppleSignInNonce {
    let rawValue: String

    var sha256: String {
        SHA256.hash(data: Data(rawValue.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func generate() throws -> AppleSignInNonce {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NonceError.randomGenerationFailed
        }
        return AppleSignInNonce(rawValue: bytes.map { String(format: "%02x", $0) }.joined())
    }

    private enum NonceError: Error {
        case randomGenerationFailed
    }
}
