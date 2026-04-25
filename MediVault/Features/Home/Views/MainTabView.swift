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
                            NavigationLink(
                                destination: DocumentDetailView(
                                    documentId: doc,
                                    orchestrator: orchestrator
                                )
                            ) {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text(doc)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete(perform: deleteDocuments)
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

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            let documentId = scannedDocuments[index]
            Task {
                do {
                    try await orchestrator.deleteDocument(documentId: documentId)
                } catch {
                    print("Failed to delete document: \(error)")
                }
            }
        }
        scannedDocuments.remove(atOffsets: offsets)
    }
}

struct DocumentDetailView: View {
    let documentId: String
    let orchestrator: RAGOrchestrator
    @State private var content: String = ""
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading document...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
            } else {
                Text(content)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        do {
            content = try await orchestrator.fetchDocumentContent(documentId: documentId)
            isLoading = false
        } catch {
            content = "Failed to load document: \(error.localizedDescription)"
            isLoading = false
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

                Section("Developer") {
                    NavigationLink("Run Benchmark") {
                        BenchmarkView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct BenchmarkView: View {
    @State private var results: [Phi4MiniService.BenchmarkResult] = []
    @State private var isRunning = false
    @State private var median: Double = 0
    @State private var exportPath: String?

    var body: some View {
        List {
            if isRunning {
                HStack {
                    ProgressView()
                    Text("Running 5 prompts…")
                }
            }

            if !results.isEmpty {
                Section("Median: \(String(format: "%.2f", median)) tok/s") {
                    ForEach(results, id: \.label) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.label).font(.headline)
                            Text("\(r.tokenCount) tok in \(String(format: "%.2f", r.decodeSeconds))s → \(String(format: "%.2f", r.tokensPerSecond)) tok/s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("prefill \(String(format: "%.2f", r.prefillSeconds))s · out \(r.outputChars) chars")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    Button("Export Markdown") { exportMarkdown() }
                    if let path = exportPath {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Button(isRunning ? "Running…" : "Run Benchmark") {
                Task { await run() }
            }
            .disabled(isRunning)
        }
        .navigationTitle("Benchmark")
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        do {
            let service = Phi4MiniService()
            try await service.loadModel()
            let r = try await service.benchmarkSuite()
            results = r
            let sorted = r.map(\.tokensPerSecond).sorted()
            median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            await service.unloadModel()
        } catch {
            print("Benchmark failed:", error)
        }
    }

    private func exportMarkdown() {
        var md = "# MediVault Benchmark\n\n"
        md += "Qwen 2.5-1.5B-Instruct Q4_K_M via SwiftLlama streaming · Metal backend · batch 256 · ctx 4096\n\n"
        md += "| Case | Tokens | Decode (s) | tok/s | Prefill (s) |\n"
        md += "|---|---:|---:|---:|---:|\n"
        for r in results {
            md += "| \(r.label) | \(r.tokenCount) | \(String(format: "%.2f", r.decodeSeconds)) | \(String(format: "%.2f", r.tokensPerSecond)) | \(String(format: "%.2f", r.prefillSeconds)) |\n"
        }
        md += "\n**Median: \(String(format: "%.2f", median)) tok/s**\n"

        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("benchmark.md")
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            exportPath = url.path
            print("Wrote benchmark to:", url.path)
        } catch {
            exportPath = "Export failed: \(error.localizedDescription)"
        }
    }
}
