//
//  ContentView.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [League]
    
    private var addGameButton: some View {
        HStack {
            Spacer()
            Button(action: {}, label: {
                Text("게임 시작")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(30)
            })
            .frame(width: 100, height: 60, alignment: .center)
            Spacer()
                .frame(width: 30)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    Spacer()
                    addGameButton
                    
                    Spacer()
                        .frame(height: 30)
                }
            }
        }
        
//        NavigationSplitView {
//            List {
//                ForEach(items) { item in
//                    NavigationLink {
//                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
//                    } label: {
//                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
//                    }
//                }
//                .onDelete(perform: deleteItems)
//            }
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    EditButton()
//                }
//                ToolbarItem {
//                    Button(action: addItem) {
//                        Label("Add Item", systemImage: "plus")
//                    }
//                }
//            }
//        } detail: {
//            Text("Select an item")
//        }
    }

    private func addItem() {
//        withAnimation {
//            let newItem = League(timestamp: Date())
//            modelContext.insert(newItem)
//        }
    }

    private func deleteItems(offsets: IndexSet) {
//        withAnimation {
//            for index in offsets {
//                modelContext.delete(items[index])
//            }
//        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: League.self, inMemory: true)
}
