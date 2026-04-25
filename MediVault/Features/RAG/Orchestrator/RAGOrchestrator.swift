//
//  RAGOrchestrator.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import Foundation
import Observation
import UIKit

@Observable
@MainActor
class RAGOrchestrator {
    private let embeddingService: EmbeddingServiceProtocol
    private let vectorStore: VectorStoreProtocol
    private let llmService: LLMServiceProtocol
    private let groundingValidator: GroundingValidator

    var isProcessing = false
    var currentStep: ProcessingStep = .idle
    var progress: Double = 0.0
    var errorMessage: String?

    enum ProcessingStep: String {
        case idle = "Ready"
        case embedding = "Analyzing question"
        case retrieving = "Searching documents"
        case generating = "Generating answer"
        case validating = "Verifying accuracy"
        case complete = "Done"
    }

    init(
        embeddingService: EmbeddingServiceProtocol,
        vectorStore: VectorStoreProtocol,
        llmService: LLMServiceProtocol
    ) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.llmService = llmService
        self.groundingValidator = GroundingValidator()
    }

    func query(_ userQuery: String) async throws -> RAGResponse {
        isProcessing = true
        errorMessage = nil
        defer {
            isProcessing = false
            currentStep = .idle
        }

        currentStep = .embedding
        progress = 0.2
        let queryEmbedding = try await embeddingService.embed(text: userQuery)

        currentStep = .retrieving
        progress = 0.4
        let retrieved = try await vectorStore.findSimilar(
            queryEmbedding: queryEmbedding,
            limit: 3,
            threshold: 0.5
        )

        guard !retrieved.isEmpty else {
            throw RAGError.noRelevantDocuments
        }

        let chunks = retrieved.map { $0.chunk }
        let scores = retrieved.map { $0.score }
        let context = buildContext(from: chunks)

        currentStep = .generating
        progress = 0.6
        let systemPrompt = PromptBuilder.systemPrompt()
        let userPrompt = PromptBuilder.userPrompt(context: context, query: userQuery)
        let result = try await llmService.generate(
            systemPrompt: systemPrompt, userPrompt: userPrompt)
        let answer = result.answer

        currentStep = .validating
        progress = 0.9
        let groundingResult = groundingValidator.validate(answer: answer, context: context)

        currentStep = .complete
        progress = 1.0

        return RAGResponse(
            answer: answer,
            sources: chunks,
            scores: scores,
            citedSourceIndices: result.sources,
            groundingResult: groundingResult,
            metrics: PerformanceMetrics()
        )
    }

    /// Query with conversation history for multi-turn conversations
    func queryWithHistory(
        _ userQuery: String,
        conversationHistory: [(role: String, content: String)]
    ) async throws -> RAGResponse {
        isProcessing = true
        errorMessage = nil
        defer {
            isProcessing = false
            currentStep = .idle
        }

        currentStep = .embedding
        progress = 0.2
        let queryEmbedding = try await embeddingService.embed(text: userQuery)

        currentStep = .retrieving
        progress = 0.4
        let retrieved = try await vectorStore.findSimilar(
            queryEmbedding: queryEmbedding,
            limit: 3,
            threshold: 0.5
        )

        guard !retrieved.isEmpty else {
            throw RAGError.noRelevantDocuments
        }

        let chunks = retrieved.map { $0.chunk }
        let scores = retrieved.map { $0.score }
        let context = buildContext(from: chunks)

        currentStep = .generating
        progress = 0.6
        let systemPrompt = PromptBuilder.systemPrompt()
        let userPrompt = PromptBuilder.userPrompt(context: context, query: userQuery)

        // Use history-aware generation
        let result = try await llmService.generateWithHistory(
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            currentUserPrompt: userPrompt
        )
        let answer = result.answer

        currentStep = .validating
        progress = 0.9
        let groundingResult = groundingValidator.validate(answer: answer, context: context)

        currentStep = .complete
        progress = 1.0

        return RAGResponse(
            answer: answer,
            sources: chunks,
            scores: scores,
            citedSourceIndices: result.sources,
            groundingResult: groundingResult,
            metrics: PerformanceMetrics()
        )
    }

    private func buildContext(from chunks: [DocumentChunk]) -> String {
        var context = ""
        for (index, chunk) in chunks.enumerated() {
            context += "--- Source \(index + 1) ---\n"
            context += chunk.content
            context += "\n\n"
        }
        return context.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func ingestDocument(
        images: [UIImage],
        documentId: String,
        documentTitle: String
    ) async throws {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let ocrService = VisionOCRService()
        let extractedText = try await ocrService.recognizeText(from: images)

        let textChunks = TextChunker.chunk(text: extractedText)

        let documentChunks = textChunks.enumerated().map { index, content in
            DocumentChunk(
                documentId: documentId,
                chunkIndex: index,
                content: content
            )
        }

        var embeddedChunks: [DocumentChunk] = []
        embeddedChunks.reserveCapacity(documentChunks.count)

        for chunk in documentChunks {
            let embedding = try await embeddingService.embed(text: chunk.content)
            let embeddedChunk = DocumentChunk(
                documentId: chunk.documentId,
                chunkIndex: chunk.chunkIndex,
                content: chunk.content,
                embedding: embedding
            )
            embeddedChunks.append(embeddedChunk)
        }

        try await vectorStore.insertBatch(embeddedChunks)
    }

    func fetchStoredDocumentIds() async throws -> [String] {
        try await vectorStore.fetchAllDocumentIds()
    }

    func fetchDocumentContent(documentId: String) async throws -> String {
        try await vectorStore.fetchDocumentContent(documentId: documentId)
    }

    func deleteDocument(documentId: String) async throws {
        try await vectorStore.deleteDocument(documentId: documentId)
    }

    enum RAGError: LocalizedError {
        case noRelevantDocuments
        case lowConfidenceAnswer
        case generationFailed

        var errorDescription: String? {
            switch self {
            case .noRelevantDocuments:
                return "No relevant information found in your documents."
            case .lowConfidenceAnswer:
                return "The answer has low confidence."
            case .generationFailed:
                return "Failed to generate answer."
            }
        }
    }
}

struct RAGResponse {
    let answer: String
    let sources: [DocumentChunk]
    let scores: [Float]
    let citedSourceIndices: [Int]
    let groundingResult: GroundingResult
    let metrics: PerformanceMetrics

    var averageScore: Float {
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Float(scores.count)
    }

    var displaySources: [DocumentChunk] {
        guard !citedSourceIndices.isEmpty else { return sources }
        return citedSourceIndices.compactMap { index in
            let i = index - 1
            guard i >= 0 && i < sources.count else { return nil }
            return sources[i]
        }
    }
}

struct PerformanceMetrics {
    var embeddingTime: TimeInterval = 0
    var retrievalTime: TimeInterval = 0
    var generationTime: TimeInterval = 0
    var validationTime: TimeInterval = 0
    var totalTime: TimeInterval = 0
}
