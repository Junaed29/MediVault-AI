//
//  ContentView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI

struct ContentView: View {
    @State private var status = "Running embedding test..."

    var body: some View {
        Text(status)
            .padding()
            .task {
                do {
                    let service = EmbeddingService()
                    try await service.loadModel()
                    let vec = try await service.embed(text: "Glucose 180 mg/dL")
                    status = "Embedding OK. Length = \(vec.count)"
                } catch {
                    status = "Embedding failed: \(error.localizedDescription)"
                }
            }
    }
}


#Preview {
    ContentView()
}
