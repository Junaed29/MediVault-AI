//
//  MediVaultApp.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI

@main
struct MediVaultApp: App {
    @State private var orchestrator: RAGOrchestrator?
    @State private var isInitializing = true
    @State private var initializationError: String?

    var body: some Scene {
        WindowGroup {
            ZStack{
                if isInitializing {
                    InitializationView(error: $initializationError)
                } else if let orchestrator = orchestrator {
                    MainTabView(orchestrator: orchestrator)
                } else {
                    ErrorView(error: initializationError ?? "Unknown error")
                }
            }.task { await initializeApp() }
        }

    }

    private func initializeApp() async {
        do {
            let embeddingService = EmbeddingService()
            try await embeddingService.loadModel()

            let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            let dbURL = documentsURL.appendingPathComponent("medivault.db")
            let vectorStore = try VectorStore(databaseURL: dbURL)

            let phi4Service = Phi4MiniService()
            try await phi4Service.loadModel()

            orchestrator = RAGOrchestrator(
                embeddingService: embeddingService,
                vectorStore: vectorStore,
                phi4Service: phi4Service
            )
            isInitializing = false
        } catch {
            initializationError = error.localizedDescription
            isInitializing = false
        }
    }
}

struct InitializationView: View {
    @Binding var error: String?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                if let error = error {
                    Text("Initialization Error")
                        .font(.headline)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                    Text("Initializing MediVault AI...")
                        .font(.headline)
                    Text("Loading models and setting up the database.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
        }
    }
}

struct ErrorView: View {
    let error: String

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Failed to Initialize")
                    .font(.headline)
                Text(error)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
    }
}

