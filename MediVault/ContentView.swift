//
//  ContentView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI

struct ContentView: View {
    @State private var status = "Running DB test..."

    var body: some View {
        Text(status)
            .padding()
            .task {
                do {
                    let dbURL = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("test.db")

                    let store = try VectorStore(databaseURL: dbURL)
                    let chunk = DocumentChunk(
                        documentId: "test-doc",
                        chunkIndex: 0,
                        content: "Glucose: 180 mg/dL",
                        embedding: Array(repeating: 0.5, count: 384)
                    )
                    try await store.insert(chunk)
                    let results = try await store.fetchChunks(documentId: "test-doc")
                    status = "DB OK. Retrieved \(results.count) chunk(s)."
                } catch {
                    status = "DB failed: \(error.localizedDescription)"
                }
            }
    }
}


#Preview {
    ContentView()
}
