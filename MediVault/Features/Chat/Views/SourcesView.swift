//
//  SourcesView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//


import SwiftUI

struct SourcesView: View {
    let response: RAGResponse
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(response.displaySources.enumerated()), id: \.offset) { index, chunk in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Source \(index + 1)")
                                .font(.headline)
                            Text(chunk.content)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Retrieved Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}