//
//  VectorMath.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//


import Accelerate
import Foundation

enum VectorMath {
    static func cosineSimilarity(_ vectorA: [Float], _ vectorB: [Float]) -> Float {
        precondition(vectorA.count == vectorB.count, "Vectors must have same dimensions")
        precondition(!vectorA.isEmpty, "Vectors cannot be empty")

        let n = vDSP_Length(vectorA.count)

        var dotProduct: Float = 0.0
        vDSP_dotpr(vectorA, 1, vectorB, 1, &dotProduct, n)

        var normA: Float = 0.0
        vDSP_svesq(vectorA, 1, &normA, n)
        normA = sqrt(normA)

        var normB: Float = 0.0
        vDSP_svesq(vectorB, 1, &normB, n)
        normB = sqrt(normB)

        guard normA > 0 && normB > 0 else { return 0.0 }

        return dotProduct / (normA * normB)
    }
}