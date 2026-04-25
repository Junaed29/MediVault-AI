//
//  MediVaultTests.swift
//  MediVaultTests
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import XCTest
@testable import MediVault

final class MediVaultTests: XCTestCase {

    // MARK: - VectorMath.cosineSimilarity

    func testCosineSimilarity_identicalVectors_returnsOne() {
        let v: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(VectorMath.cosineSimilarity(v, v), 1.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_orthogonalVectors_returnsZero() {
        let a: [Float] = [1, 0, 0, 0]
        let b: [Float] = [0, 1, 0, 0]
        XCTAssertEqual(VectorMath.cosineSimilarity(a, b), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_oppositeVectors_returnsMinusOne() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [-1, -2, -3]
        XCTAssertEqual(VectorMath.cosineSimilarity(a, b), -1.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_scaleInvariant() {
        // Cosine similarity ignores magnitude — only direction matters.
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [10, 20, 30]
        XCTAssertEqual(VectorMath.cosineSimilarity(a, b), 1.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_zeroVector_returnsZero() {
        let a: [Float] = [0, 0, 0, 0]
        let b: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(VectorMath.cosineSimilarity(a, b), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_384Dimensions_matchesEmbeddingShape() {
        // Smoke test at the actual 384-dim shape used by the MiniLM embeddings.
        let a = Array(repeating: Float(1.0), count: 384)
        let b = Array(repeating: Float(1.0), count: 384)
        XCTAssertEqual(VectorMath.cosineSimilarity(a, b), 1.0, accuracy: 1e-5)
    }
}
