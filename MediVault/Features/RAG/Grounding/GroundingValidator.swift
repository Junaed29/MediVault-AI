//
//  GroundingValidator.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//


import Foundation

struct GroundingValidator {
    func validate(answer: String, context: String) -> GroundingResult {
        let claims = extractClaims(from: answer)
        var groundedCount = 0
        var totalConfidence: Float = 0.0

        for claim in claims {
            let result = validateClaim(claim: claim, context: context)
            if result.isGrounded { groundedCount += 1 }
            totalConfidence += result.confidence
        }

        let groundingRatio = Float(groundedCount) / Float(max(claims.count, 1))
        let avgConfidence = totalConfidence / Float(max(claims.count, 1))
        let isGrounded = groundingRatio >= 0.8
        let hasDangerousContent = containsDangerousAdvice(answer)

        return GroundingResult(
            isGrounded: isGrounded && !hasDangerousContent,
            confidence: avgConfidence,
            groundedClaims: groundedCount,
            totalClaims: claims.count,
            hasDangerousContent: hasDangerousContent
        )
    }

    private func extractClaims(from answer: String) -> [String] {
        let sentences = answer.components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ".!?")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 && !$0.starts(with: "Source") }
        return sentences
    }

    private func validateClaim(claim: String, context: String) -> ClaimValidationResult {
        let normalizedClaim = claim.lowercased()
        let normalizedContext = context.lowercased()
        let keyTerms = extractKeyTerms(from: normalizedClaim)

        guard !keyTerms.isEmpty else {
            return ClaimValidationResult(isGrounded: true, confidence: 0.5)
        }

        var foundCount = 0
        var matchedTerms: [String] = []

        for term in keyTerms {
            if normalizedContext.contains(term) {
                foundCount += 1
                matchedTerms.append(term)
            }
        }

        let coverage = Float(foundCount) / Float(keyTerms.count)
        let isGrounded = coverage >= 0.6

        return ClaimValidationResult(
            isGrounded: isGrounded,
            confidence: coverage,
            matchedTerms: matchedTerms
        )
    }

    private func extractKeyTerms(from text: String) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var keyTerms: [String] = []

        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if cleaned.count > 4 ||
                cleaned.contains(where: { $0.isNumber }) ||
                isMedicalUnit(cleaned) {
                keyTerms.append(cleaned.lowercased())
            }
        }

        return keyTerms
    }

    private func isMedicalUnit(_ word: String) -> Bool {
        let units = ["mg", "ml", "dl", "mmol", "kg", "lb", "cm", "mm", "bpm", "%"]
        return units.contains(word.lowercased())
    }

    private func containsDangerousAdvice(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let dangerousPatterns: [String] = [
            "you have",
            "you are diagnosed",
            "this indicates",
            "this means you have",
            "you should take",
            "start taking",
            "stop taking",
            "discontinue",
            "increase your dose",
            "decrease your dose",
            "you must",
            "you need to",
            "it's necessary to",
            "immediately start",
            "ignore your doctor",
            "doctor is wrong",
            "don't listen to"
        ]

        return dangerousPatterns.contains { lowercased.contains($0) }
    }
}

struct GroundingResult {
    let isGrounded: Bool
    let confidence: Float
    let groundedClaims: Int
    let totalClaims: Int
    let hasDangerousContent: Bool
}

private struct ClaimValidationResult {
    let isGrounded: Bool
    let confidence: Float
    var matchedTerms: [String] = []
}