//
//  LLMService.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import Foundation
import os
import SwiftLlama

struct CitedAnswer: Codable {
    let answer: String
    let sources: [Int]
}

actor LLMService {
    private var llamaService: LlamaService?
    private let modelBaseName = "qwen2.5-1.5b-instruct-q4_k_m-00001-of-00001"

    private static let log = Logger(subsystem: "com.medivault", category: "benchmark")

    struct BenchmarkResult: Sendable {
        let label: String
        let promptChars: Int
        let outputChars: Int
        let tokenCount: Int
        let prefillSeconds: Double
        let decodeSeconds: Double
        let tokensPerSecond: Double
    }

    func loadModel() async throws {
        guard
            let modelUrl = Bundle.main.url(
                forResource: modelBaseName,
                withExtension: "gguf"
            )
        else {
            throw LLMError.modelNotFound
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
        guard let llamaService else { throw LLMError.modelNotLoaded }
        guard !systemPrompt.isEmpty else { throw LLMError.emptyPrompt }
        guard !userPrompt.isEmpty else { throw LLMError.emptyPrompt }

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
            throw LLMError.generationFailed(error.localizedDescription)
        }
    }

    /// Generate with conversation history for multi-turn conversations
    func generateWithHistory(
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)],
        currentUserPrompt: String
    ) async throws -> CitedAnswer {
        guard let llamaService else { throw LLMError.modelNotLoaded }
        guard !systemPrompt.isEmpty else { throw LLMError.emptyPrompt }
        guard !currentUserPrompt.isEmpty else { throw LLMError.emptyPrompt }

        var messages = [LlamaChatMessage(role: .system, content: systemPrompt)]

        // Last 4 exchanges to stay within context limit
        let recentHistory = conversationHistory.suffix(8)
        for entry in recentHistory {
            let role: LlamaChatMessage.Role = entry.role == "user" ? .user : .assistant
            messages.append(LlamaChatMessage(role: role, content: entry.content))
        }

        messages.append(LlamaChatMessage(role: .user, content: currentUserPrompt))

        do {
            return try await llamaService.respond(
                to: messages,
                generating: CitedAnswer.self
            )
        } catch {
            throw LLMError.generationFailed(error.localizedDescription)
        }
    }

    /// Runs one prompt via the streaming API so decode throughput can be measured.
    /// Counts streamed chunks — llama.cpp yields one decoded token per chunk, so
    /// this is accurate to ±1 token per run for portfolio-grade measurement.
    func benchmarkOne(
        label: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> BenchmarkResult {
        guard let llamaService else { throw LLMError.modelNotLoaded }

        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: userPrompt),
        ]

        let t0 = CFAbsoluteTimeGetCurrent()
        var tFirstToken: CFAbsoluteTime = 0
        var tokenCount = 0
        var output = ""

        let stream = try await llamaService.streamCompletion(
            of: messages,
            generating: CitedAnswer.self
        )

        for try await chunk in stream {
            if tFirstToken == 0 { tFirstToken = CFAbsoluteTimeGetCurrent() }
            tokenCount += 1
            output += chunk
        }

        let t1 = CFAbsoluteTimeGetCurrent()
        let firstTokenTime = tFirstToken == 0 ? t1 : tFirstToken
        let prefill = firstTokenTime - t0
        let decode = t1 - firstTokenTime
        let tps = decode > 0 ? Double(tokenCount) / decode : 0

        let result = BenchmarkResult(
            label: label,
            promptChars: systemPrompt.count + userPrompt.count,
            outputChars: output.count,
            tokenCount: tokenCount,
            prefillSeconds: prefill,
            decodeSeconds: decode,
            tokensPerSecond: tps
        )

        Self.log.info("""
            [\(label, privacy: .public)] \
            prompt=\(result.promptChars) chars, \
            out=\(result.tokenCount) tok / \(result.outputChars) chars, \
            prefill=\(String(format: "%.2f", result.prefillSeconds))s, \
            decode=\(String(format: "%.2f", result.decodeSeconds))s, \
            tok/s=\(String(format: "%.2f", result.tokensPerSecond))
            """)

        return result
    }

    func benchmarkSuite() async throws -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        for testCase in BenchmarkPrompts.cases {
            let userPrompt = PromptBuilder.userPrompt(
                context: testCase.context,
                query: testCase.query
            )
            let r = try await benchmarkOne(
                label: testCase.label,
                systemPrompt: PromptBuilder.systemPrompt(),
                userPrompt: userPrompt
            )
            results.append(r)
        }
        return results
    }

    enum LLMError: LocalizedError {
        case modelNotLoaded
        case modelNotFound
        case emptyPrompt
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "LLM must be loaded before use."
            case .modelNotFound:
                return "LLM model file not found in bundle."
            case .emptyPrompt:
                return "Cannot generate from empty prompt."
            case .generationFailed(let reason):
                return "Generation failed: \(reason)."
            }
        }
    }
}
