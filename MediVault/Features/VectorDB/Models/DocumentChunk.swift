//
//  DocumentChunk.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import Foundation
import GRDB

nonisolated struct DocumentChunk: Sendable {
    var id: Int64?
    let documentId: String
    let chunkIndex: Int
    let content: String
    var embedding: Data?
    let characterCount: Int
    let createdAt: Date

    var hasEmbedding: Bool {
        embedding != nil && !(embedding?.isEmpty ?? true)
    }

    var embeddingVector: [Float]? {
        guard let embedding = embedding else { return nil }
        return embedding.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    init(
        id: Int64? = nil,
        documentId: String,
        chunkIndex: Int,
        content: String,
        embedding: [Float]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.documentId = documentId
        self.chunkIndex = chunkIndex
        self.content = content
        self.characterCount = content.count
        self.createdAt = createdAt

        if let embedding = embedding {
            var floatArray = embedding
            self.embedding = Data(
                bytes: &floatArray,
                count: floatArray.count * MemoryLayout<Float>.stride
            )
        }
    }
}

nonisolated extension DocumentChunk: FetchableRecord, PersistableRecord {
    static let databaseTableName = "chunks"

    init(row: Row) {
        id = row[Columns.id]
        documentId = row[Columns.documentId]
        chunkIndex = row[Columns.chunkIndex]
        content = row[Columns.content]
        embedding = row[Columns.embedding]
        characterCount = row[Columns.characterCount]
        createdAt = row[Columns.createdAt]
    }

    enum Columns: String, ColumnExpression {
        case id
        case documentId = "document_id"
        case chunkIndex = "chunk_index"
        case content
        case embedding
        case characterCount = "character_count"
        case createdAt = "created_at"
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.documentId] = documentId
        container[Columns.chunkIndex] = chunkIndex
        container[Columns.content] = content
        container[Columns.embedding] = embedding
        container[Columns.characterCount] = characterCount
        container[Columns.createdAt] = createdAt
    }
}


nonisolated extension DocumentChunk {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { table in
            table.autoIncrementedPrimaryKey(Columns.id.rawValue)
            table.column(Columns.documentId.rawValue, .text).notNull()
            table.column(Columns.chunkIndex.rawValue, .integer).notNull()
            table.column(Columns.content.rawValue, .text).notNull()
            table.column(Columns.embedding.rawValue, .blob)
            table.column(Columns.characterCount.rawValue, .integer).notNull()
            table.column(Columns.createdAt.rawValue, .datetime).notNull()
            table.uniqueKey([Columns.documentId.rawValue, Columns.chunkIndex.rawValue])
        }

        try db.create(
            index: "idx_chunks_document_id",
            on: databaseTableName,
            columns: [Columns.documentId.rawValue],
            ifNotExists: true
        )
    }
}
