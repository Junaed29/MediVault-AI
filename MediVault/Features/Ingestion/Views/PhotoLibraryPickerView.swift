//
//  PhotoLibraryPickerView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI
import PhotosUI
import UIKit

struct PhotoLibraryPickerView: View {
    let orchestrator: RAGOrchestrator
    @Binding var isPresented: Bool
    var onDocumentImported: (String) -> Void

    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label("Select Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                Text("Pick 1–10 document photos to import.")
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("Import from Photos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                Task { await importSelectedItems(newItems) }
            }
        }
    }

    private func importSelectedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var images: [UIImage] = []
        images.reserveCapacity(items.count)

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }

        guard !images.isEmpty else { return }

        do {
            let documentId = UUID().uuidString
            let documentTitle = "Imported-\(Date().formatted(date: .abbreviated, time: .omitted))"

            try await orchestrator.ingestDocument(
                images: images,
                documentId: documentId,
                documentTitle: documentTitle
            )

            onDocumentImported(documentTitle)
            isPresented = false
        } catch {
            isPresented = false
        }
    }
}
