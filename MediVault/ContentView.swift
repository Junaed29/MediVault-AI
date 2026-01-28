//
//  ContentView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI

struct ContentView: View {
    @State private var status = "Running LLM test..."

    var body: some View {
        Text(status)
            .padding()
            .task {
                do {
                    let service = Phi4MiniService()
                    try await service.loadModel()
                    let reply = try await service.generate(
                        systemPrompt: PromptBuilder.systemPrompt(),
                        userPrompt: "Say hello in one sentence."
                    )
                    status = "LLM OK: \(reply.answer)"
                } catch {
                    status = "LLM failed: \(error.localizedDescription)"
                }
            }
    }
}

#Preview {
    ContentView()
}
