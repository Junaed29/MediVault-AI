//
//  ChatViewModel.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//


import Foundation
import Observation

@Observable
@MainActor
class ChatViewModel {
    var messages: [ChatMessage] = []
    var isProcessing = false
    var lastResponse: RAGResponse?

    let orchestrator: RAGOrchestrator

    init(orchestrator: RAGOrchestrator) {
        self.orchestrator = orchestrator
        addWelcomeMessage()
    }

    func addUserMessage(_ content: String) {
        messages.append(ChatMessage(content: content, isUser: true))
    }

    func addAssistantMessage(_ content: String, sources: [DocumentChunk], scores: [Float]) {
        let confidence = scores.isEmpty ? nil : (scores.reduce(0, +) / Float(scores.count))
        messages.append(ChatMessage(
            content: content,
            isUser: false,
            sourceCount: sources.count,
            confidence: confidence
        ))
    }

    func addErrorMessage(_ error: String) {
        messages.append(ChatMessage(
            content: "Error: \(error)",
            isUser: false
        ))
    }

    func sendQuery(_ query: String) async {
        isProcessing = true
        defer { isProcessing = false }

        addUserMessage(query)

        do {
            let response = try await orchestrator.query(query)
            lastResponse = response
            let filtered = SafetyFilter.filter(response)
            addAssistantMessage(
                filtered.displayText,
                sources: response.displaySources,
                scores: response.scores
            )
        } catch {
            addErrorMessage(error.localizedDescription)
        }
    }

    func clearMessages() {
        messages.removeAll()
        addWelcomeMessage()
        lastResponse = nil
    }

    private func addWelcomeMessage() {
        messages.append(ChatMessage(
            content: "Welcome to MediVault AI. Scan documents and ask a question.",
            isUser: false
        ))
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    let sourceCount: Int?
    let confidence: Float?

    init(
        id: UUID = UUID(),
        content: String,
        isUser: Bool,
        timestamp: Date = Date(),
        sourceCount: Int? = nil,
        confidence: Float? = nil
    ) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.sourceCount = sourceCount
        self.confidence = confidence
    }
}