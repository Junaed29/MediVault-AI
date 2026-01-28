//
//  VectorStore.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import Foundation
import GRDB

actor VectorStore {
    private let dbQueue: DatabaseQueue
    private let dimensions: Int = 384

    init(databaseURL: URL) throws {
        self.dbQueue = try DatabaseQueue(path: databaseURL.path)
        try setupDatabase()
    }

    private func setupDatabase() throws {
        try dbQueue.write { db in
            try DocumentChunk.createTable(in: db)
        }
    }

    func insert(_ chunk: DocumentChunk) async throws {
        try await dbQueue.write { db in
            try chunk.insert(db)
        }
    }

    func insertBatch(_ chunks: [DocumentChunk]) async throws {
        try await dbQueue.write { db in
            for chunk in chunks {
                try chunk.insert(db)
            }
        }
    }

    func fetchChunks(documentId: String) async throws -> [DocumentChunk] {
        try await dbQueue.read { db in
            try DocumentChunk
                .filter(DocumentChunk.Columns.documentId == documentId)
                .order(DocumentChunk.Columns.chunkIndex.asc)
                .fetchAll(db)
        }
    }

    func fetchEmbeddedChunks() async throws -> [DocumentChunk] {
        try await dbQueue.read { db in
            try DocumentChunk
                .filter(DocumentChunk.Columns.embedding != nil)
                .fetchAll(db)
        }
    }

    func findSimilar(
        queryEmbedding: [Float],
        limit: Int = 3,
        threshold: Float = 0.5
    ) async throws -> [(chunk: DocumentChunk, score: Float)] {
        precondition(queryEmbedding.count == dimensions, "Query vector must be 384 dimensions")

        let chunks = try await fetchEmbeddedChunks()
        guard !chunks.isEmpty else { return [] }

        var scoredChunks: [(chunk: DocumentChunk, score: Float)] = []
        scoredChunks.reserveCapacity(chunks.count)

        for chunk in chunks {
            guard let chunkEmbedding = chunk.embeddingVector else { continue }
            let similarity = VectorMath.cosineSimilarity(queryEmbedding, chunkEmbedding)
            if similarity >= threshold {
                scoredChunks.append((chunk, similarity))
            }
        }

        scoredChunks.sort { $0.score > $1.score }
        return Array(scoredChunks.prefix(limit))
    }

    func fetchAllDocumentIds() async throws -> [String] {
        try await dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT document_id FROM chunks ORDER BY created_at DESC"
            )
        }
    }

    func fetchDocumentContent(documentId: String) async throws -> String {
        let chunks = try await dbQueue.read { db in
            try DocumentChunk
                .filter(DocumentChunk.Columns.documentId == documentId)
                .order(DocumentChunk.Columns.chunkIndex.asc)
                .fetchAll(db)
        }
        return chunks.map { $0.content }.joined(separator: "\n\n")
    }

    func deleteDocument(documentId: String) async throws {
        try await dbQueue.write { db in
            try DocumentChunk
                .filter(DocumentChunk.Columns.documentId == documentId)
                .deleteAll(db)
        }
    }
}
