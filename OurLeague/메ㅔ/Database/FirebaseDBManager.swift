//
//  FirebaseDBManager.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
//

import Foundation

import FirebaseFirestore

struct FirebaseDBManager {
    static let shared = FirebaseDBManager()
    private let firebaseDB = Firestore.firestore()
    
    private init() { }
    
    
}
