//
//  EmbeddingService.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import CoreML
import Foundation
import Tokenizers

actor EmbeddingService {
    private var model: MLModel?
    private let modelURL: URL
    private let dimensions = 384

    private let tokenizerFolderURL: URL
    private var tokenizer: (any Tokenizer)?


    init() {
        guard let url = Bundle.main.url(
            forResource: "float16_model",
            withExtension: "mlmodelc"
        ) else {
            fatalError("MiniLM model not found in bundle. Add it to Resources/Models.")
        }
        self.modelURL = url

        // Option B: tokenizer files are added individually (no folder reference)
        guard let tokenizerConfigURL = Bundle.main.url(
            forResource: "tokenizer_config",
            withExtension: "json"
        ) else {
            fatalError("tokenizer_config.json not found in bundle. Add tokenizer files to Copy Bundle Resources.")
        }
        self.tokenizerFolderURL = tokenizerConfigURL.deletingLastPathComponent()
    }

    func loadModel() async throws {
        guard model == nil else { return }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)

        // Load tokenizer from local files
        tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolderURL)
    }

    func embed(text: String) async throws -> [Float] {
        guard let model = model else { throw EmbeddingError.modelNotLoaded }
        guard let tokenizer = tokenizer else { throw EmbeddingError.tokenizationFailed }
        guard !text.isEmpty else { throw EmbeddingError.emptyInput }

        let tokenIds = tokenizer.encode(text: text)
        let input = try prepareInput(tokenIds: tokenIds)

        let output = try await model.prediction(from: input)
        let embedding = try extractEmbedding(from: output)
        return embedding
    }

    private func padOrTruncate(_ ids: [Int], to length: Int, padValue: Int) -> [Int] {
        if ids.count > length { return Array(ids.prefix(length)) }
        if ids.count < length { return ids + Array(repeating: padValue, count: length - ids.count) }
        return ids
    }

    private func prepareInput(tokenIds: [Int]) throws -> MLFeatureProvider {
        let maxLength = 128
        let padId = tokenizer?.convertTokenToId("[PAD]") ?? 0

        let ids = padOrTruncate(tokenIds, to: maxLength, padValue: padId)
        let attention = ids.map { $0 == padId ? 0 : 1 }

        // 2‑D shape: [1, 128]
        let inputIdsArray = try MLMultiArray(shape: [1, maxLength] as [NSNumber], dataType: .int32)
        let attentionArray = try MLMultiArray(shape: [1, maxLength] as [NSNumber], dataType: .int32)

        for i in 0..<maxLength {
            inputIdsArray[[0, i] as [NSNumber]] = NSNumber(value: ids[i])
            attentionArray[[0, i] as [NSNumber]] = NSNumber(value: attention[i])
        }

        return try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIdsArray,
            "attention_mask": attentionArray
        ])
    }

    private func extractEmbedding(from output: MLFeatureProvider) throws -> [Float] {
        // Output key from Xcode Model Inspector (Predictions tab)
        let outputKey = "pooler_output"
        guard let embeddingFeature = output.featureValue(for: outputKey),
              let multiArray = embeddingFeature.multiArrayValue else {
            throw EmbeddingError.extractionFailed
        }

        var embedding: [Float] = []
        embedding.reserveCapacity(dimensions)

        for i in 0..<dimensions {
            embedding.append(multiArray[i].floatValue)
        }

        return embedding
    }

    enum EmbeddingError: LocalizedError {
        case modelNotLoaded
        case emptyInput
        case tokenizationFailed
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Embedding model must be loaded before use."
            case .emptyInput:
                return "Cannot embed empty text."
            case .tokenizationFailed:
                return "Failed to tokenize input text."
            case .extractionFailed:
                return "Failed to extract embedding from model output."
            }
        }
    }
}
