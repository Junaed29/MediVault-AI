//
//  SafetyFilter.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//


enum SafetyFilter {
    static func filter(_ response: RAGResponse) -> FilteredResponse {
        if !response.groundingResult.isGrounded {
            return .ungrounded(response)
        }
        if response.groundingResult.hasDangerousContent {
            return .unsafe
        }
        if response.averageScore < 0.4 {
            return .lowConfidence(response)
        }
        return .safe(response)
    }

    enum FilteredResponse {
        case safe(RAGResponse)
        case ungrounded(RAGResponse)
        case unsafe
        case lowConfidence(RAGResponse)

        var displayText: String {
            switch self {
            case .safe(let response):
                return response.answer
            case .ungrounded(let response):
                return "Unverified information. Generated answer:\n\n\(response.answer)"
            case .unsafe:
                return "Safety intervention. This assistant cannot provide medical advice."
            case .lowConfidence(let response):
                return "Low confidence answer. Possible answer:\n\n\(response.answer)"
            }
        }
    }
}