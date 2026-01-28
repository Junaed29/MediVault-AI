//
//  MainTabView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI

struct MainTabView: View {
    let orchestrator: RAGOrchestrator
    @State private var selectedTab: Tab = .chat

    enum Tab { case chat, documents, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatTab(orchestrator: orchestrator)
                .tabItem { Label("Chat", systemImage: "message.fill") }
                .tag(Tab.chat)

            DocumentsTab(orchestrator: orchestrator)
                .tabItem { Label("Documents", systemImage: "doc.text.fill") }
                .tag(Tab.documents)

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
    }
}

struct ChatTab: View {
    let orchestrator: RAGOrchestrator
    @State private var viewModel: ChatViewModel?

    var body: some View {
        NavigationStack {
            if let viewModel = viewModel {
                ChatView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task { viewModel = ChatViewModel(orchestrator: orchestrator) }
            }
        }
    }
}

struct DocumentsTab: View {
    let orchestrator: RAGOrchestrator
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var scannedDocuments: [String] = []

    var body: some View {
        NavigationStack {
            VStack {
                if scannedDocuments.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        Text("No Documents Yet")
                            .font(.headline)
                        Text("Scan your medical documents to get started")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                    .multilineTextAlignment(.center)
                } else {
                    List {
                        ForEach(scannedDocuments, id: \.self) { doc in
                            HStack {
                                Image(systemName: "doc.text")
                                Text(doc)
                            }
                        }
                    }
                }

                Button(action: { showScanner = true }) {
                    Label("Scan Document", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding()

                Button(action: { showPhotoPicker = true }) {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("Medical Documents")
            .task {
                await loadStoredDocuments()
            }
            .sheet(isPresented: $showScanner) {
                DocumentScannerView(
                    orchestrator: orchestrator,
                    isPresented: $showScanner,
                    onDocumentScanned: { doc in scannedDocuments.append(doc) }
                )
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoLibraryPickerView(
                    orchestrator: orchestrator,
                    isPresented: $showPhotoPicker,
                    onDocumentImported: { doc in scannedDocuments.append(doc) }
                )
            }
        }
    }

    private func loadStoredDocuments() async {
        do {
            let storedIds = try await orchestrator.fetchStoredDocumentIds()
            if scannedDocuments.isEmpty && !storedIds.isEmpty {
                scannedDocuments = storedIds
            }
        } catch {
            print("Failed to load stored documents: \(error)")
        }
    }
}

struct SettingsTab: View {
    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Model")
                        Spacer()
                        Text("Qwen2.5-1.5B-Instruct")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Privacy") {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("100% Offline")
                    }
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Local-only processing")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
