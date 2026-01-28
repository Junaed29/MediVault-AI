//
//  Phi4MiniService.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import Foundation
import SwiftLlama

struct CitedAnswer: Codable {
    let answer: String
    let sources: [Int]
}

actor Phi4MiniService {
    private var llamaService: LlamaService?
    private let modelBaseName = "qwen2.5-1.5b-instruct-q4_k_m-00001-of-00001"

    func loadModel() async throws {
        guard
            let modelUrl = Bundle.main.url(
                forResource: modelBaseName,
                withExtension: "gguf"
            )
        else {
            throw Phi4MiniError.modelNotFound
        }

        llamaService = LlamaService(
            modelUrl: modelUrl,
            config: .init(batchSize: 256, maxTokenCount: 4096, useGPU: true)
        )
    }

    func unloadModel() async {
        llamaService = nil
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> CitedAnswer {
        guard let llamaService else { throw Phi4MiniError.modelNotLoaded }
        guard !systemPrompt.isEmpty else { throw Phi4MiniError.emptyPrompt }
        guard !userPrompt.isEmpty else { throw Phi4MiniError.emptyPrompt }

        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: userPrompt),
        ]

        do {
            return try await llamaService.respond(
                to: messages,
                generating: CitedAnswer.self
            )
        } catch {
            throw Phi4MiniError.generationFailed(error.localizedDescription)
        }
    }

    enum Phi4MiniError: LocalizedError {
        case modelNotLoaded
        case modelNotFound
        case emptyPrompt
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Phi-4-mini-instruct model must be loaded before use."
            case .modelNotFound:
                return "Phi-4-mini-instruct model not found in bundle."
            case .emptyPrompt:
                return "Cannot generate from empty prompt."
            case .generationFailed(let reason):
                return "Generation failed: \(reason)."
            }
        }
    }
}
