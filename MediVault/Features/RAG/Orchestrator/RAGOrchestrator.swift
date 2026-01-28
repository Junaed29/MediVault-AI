//
//  RAGOrchestrator.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import UIKit

@MainActor
class RAGOrchestrator {
    func ingestDocument(
        images: [UIImage],
        documentId: String,
        documentTitle: String
    ) async throws {
        let ocrService = VisionOCRService()
        let text = try await ocrService.recognizeText(from: images)
        let chunks = TextChunker.chunk(text: text)
        print("OCR chars:", text.count)
        print("Chunks:", chunks.count)
    }
}

