//
//  ContentView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI

import SwiftUI

struct ContentView: View {
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 16) {
            Button("Scan Document") { showScanner = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showScanner) {
            DocumentScannerView(
                orchestrator: RAGOrchestrator(),
                isPresented: $showScanner,
                onDocumentScanned: { _ in }
            )
        }
    }
}


#Preview {
    ContentView()
}
