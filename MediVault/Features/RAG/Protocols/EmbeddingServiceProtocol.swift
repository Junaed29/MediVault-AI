//
//  EmbeddingServiceProtocol.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

protocol EmbeddingServiceProtocol {
    func embed(text: String) async throws -> [Float]
}

protocol VectorStoreProtocol {
    func findSimilar(
        queryEmbedding: [Float],
        limit: Int,
        threshold: Float
    ) async throws -> [(chunk: DocumentChunk, score: Float)]

    func insertBatch(_ chunks: [DocumentChunk]) async throws

    func fetchAllDocumentIds() async throws -> [String]

    func fetchDocumentContent(documentId: String) async throws -> String

    func deleteDocument(documentId: String) async throws
}

protocol LLMServiceProtocol {
    func generate(systemPrompt: String, userPrompt: String) async throws -> CitedAnswer
    func generateWithHistory(
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)],
        currentUserPrompt: String
    ) async throws -> CitedAnswer
}

extension EmbeddingService: EmbeddingServiceProtocol {}
extension VectorStore: VectorStoreProtocol {}
extension LLMService: LLMServiceProtocol {}
