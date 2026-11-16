//
//  SupabaseConfiguration.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/16.
//

import Foundation

struct SupabaseConfiguration: Equatable {
    let url: URL
    let publishableKey: String

    init(infoDictionary: [String: Any]) throws {
        let urlValue = try Self.value(for: "SUPABASE_URL", in: infoDictionary)
        guard let url = URL(string: urlValue),
              url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.port == nil,
              url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil else {
            throw SupabaseConfigurationError.invalidURL
        }

        let key = try Self.value(for: "SUPABASE_PUBLISHABLE_KEY", in: infoDictionary)
        guard key.range(of: "^sb_publishable_[A-Za-z0-9_-]+$", options: .regularExpression) != nil || Self.isLegacyAnonKey(key) else {
            throw SupabaseConfigurationError.invalidPublishableKey
        }

        self.url = url
        publishableKey = key
    }

    static func load(bundle: Bundle = .main) throws -> SupabaseConfiguration {
        try SupabaseConfiguration(infoDictionary: bundle.infoDictionary ?? [:])
    }

    private static func isLegacyAnonKey(_ key: String) -> Bool {
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              segments.allSatisfy({ $0.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil }) else {
            return false
        }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return claims["role"] as? String == "anon"
    }

    private static func value(for key: String, in dictionary: [String: Any]) throws -> String {
        guard let rawValue = dictionary[key] as? String else {
            throw SupabaseConfigurationError.missingValue(key)
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              !value.contains("YOUR_"),
              !value.contains("REPLACE_ME") else {
            throw SupabaseConfigurationError.missingValue(key)
        }
        return value
    }
}

enum SupabaseConfigurationError: Error, Equatable, LocalizedError {
    case missingValue(String)
    case invalidURL
    case invalidPublishableKey

    var errorDescription: String? {
        switch self {
        case .missingValue(let key):
            return "\(key) 설정이 없습니다. Configuration/Supabase.local.xcconfig를 확인하세요."
        case .invalidURL:
            return "SUPABASE_URL에는 경로와 인증 정보가 없는 HTTPS 프로젝트 주소를 설정하세요."
        case .invalidPublishableKey:
            return "앱에는 sb_publishable_ 공개 키 또는 기존 anon 키만 사용할 수 있습니다. 관리자 키는 허용하지 않습니다."
        }
    }
}
