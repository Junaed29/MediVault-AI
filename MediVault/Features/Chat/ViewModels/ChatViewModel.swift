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
        messages.append(
            ChatMessage(
                content: content,
                isUser: false,
                sourceCount: sources.count,
                confidence: confidence
            ))
    }

    func addErrorMessage(_ error: String) {
        messages.append(
            ChatMessage(
                content: "Error: \(error)",
                isUser: false
            ))
    }

    func sendQuery(_ query: String) async {
        isProcessing = true
        defer { isProcessing = false }

        addUserMessage(query)

        // Check if it's a greeting or simple non-question
        if isGreetingOrSimpleInput(query) {
            addAssistantMessage(
                "Hello! I'm your MediVault assistant. I can help you find information from your scanned medical documents. Try asking something like:\n\n• \"What was my last blood pressure?\"\n• \"Show me my medication list\"\n• \"What did the doctor say about my condition?\"",
                sources: [],
                scores: []
            )
            return
        }

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

    private func isGreetingOrSimpleInput(_ text: String) -> Bool {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let greetings = [
            "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
            "howdy", "greetings", "yo", "sup", "what's up", "whats up",
            "how are you", "how r u", "hru", "thanks", "thank you", "bye",
            "goodbye", "ok", "okay", "yes", "no", "sure", "help", "test",
        ]

        // Exact match for short greetings
        if greetings.contains(lowercased) {
            return true
        }

        // Starts with greeting
        for greeting in greetings {
            if lowercased.hasPrefix(greeting + " ") || lowercased.hasPrefix(greeting + "!") {
                return true
            }
        }

        // Very short input (less than 10 chars) that doesn't look like a question
        if lowercased.count < 10 && !lowercased.contains("?") {
            return true
        }

        return false
    }

    func clearMessages() {
        messages.removeAll()
        addWelcomeMessage()
        lastResponse = nil
    }

    private func addWelcomeMessage() {
        messages.append(
            ChatMessage(
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
