//
//  Supabase.swift
//  OurLeague
//
//  Created by 양호준 on 10/17/25.
//

import Foundation
import Supabase

enum SupabaseEnvironment {
    private static let configuredClient: Result<SupabaseClient, Error> = Result {
        let configuration = try SupabaseConfiguration.load()
        return SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
    }

    static func client() throws -> SupabaseClient {
        try configuredClient.get()
    }
}
