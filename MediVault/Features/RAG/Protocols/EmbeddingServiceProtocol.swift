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
}

protocol Phi4MiniServiceProtocol {
    func generate(systemPrompt: String, userPrompt: String) async throws -> CitedAnswer
}

extension EmbeddingService: EmbeddingServiceProtocol {}
extension VectorStore: VectorStoreProtocol {}
extension Phi4MiniService: Phi4MiniServiceProtocol {}
