//
//  ChatView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var userInput = ""
    @State private var showSources = false
    @FocusState private var isTextFieldFocused: Bool

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isProcessing {
                                ProcessingIndicator(
                                    step: viewModel.orchestrator.currentStep,
                                    progress: viewModel.orchestrator.progress
                                )
                            }
                        }
                        .padding()
                    }
                    .onTapGesture {
                        isTextFieldFocused = false
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    TextField(
                        "Ask about your medical history...", text: $userInput, axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
                    .disabled(viewModel.isProcessing)
                    .focused($isTextFieldFocused)

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                userInput.isEmpty || viewModel.isProcessing ? .gray : .blue
                            )
                    }
                    .disabled(userInput.isEmpty || viewModel.isProcessing)
                }
                .padding()
            }
            .navigationTitle("Medical Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sources") { showSources = true }
                        .disabled(viewModel.lastResponse == nil)
                }
            }
            .sheet(isPresented: $showSources) {
                if let response = viewModel.lastResponse {
                    SourcesView(response: response)
                }
            }
        }
    }

    private func sendMessage() {
        let query = userInput
        userInput = ""
        Task { await viewModel.sendQuery(query) }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color(.systemGray6))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)

                if !message.isUser {
                    HStack(spacing: 8) {
                        if let sourceCount = message.sourceCount, sourceCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                Text("\(sourceCount) source\(sourceCount == 1 ? "" : "s")")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }

                        if let confidence = message.confidence {
                            HStack(spacing: 4) {
                                Image(systemName: confidenceIcon(confidence))
                                Text(String(format: "%.0f%%", confidence * 100))
                            }
                            .font(.caption2)
                            .foregroundColor(confidenceColor(confidence))
                        }
                    }
                }
            }
            .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser { Spacer() }
        }
    }

    private func confidenceIcon(_ confidence: Float) -> String {
        if confidence >= 0.8 { return "checkmark.circle.fill" }
        if confidence >= 0.6 { return "exclamationmark.circle.fill" }
        return "questionmark.circle.fill"
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .orange }
        return .red
    }
}

struct ProcessingIndicator: View {
    let step: RAGOrchestrator.ProcessingStep
    let progress: Double

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)

            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(step.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
