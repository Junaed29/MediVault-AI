//
//  VisionOCRService.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//


import Vision
import UIKit
import Foundation

struct VisionOCRService {
    func recognizeText(from images: [UIImage]) async throws -> String {
        var allText: [String] = []

        for (index, image) in images.enumerated() {
            guard let cgImage = image.cgImage else { continue }
            let extractedText = try await processImage(cgImage, pageNumber: index + 1)
            allText.append(extractedText)
        }

        guard !allText.isEmpty else {
            throw OCRError.noTextFound
        }

        return allText.joined(separator: "\n\n--- PAGE BREAK ---\n\n")
    }

    private func processImage(_ cgImage: CGImage, pageNumber: Int) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let fullText = recognizedStrings.joined(separator: "\n")
                continuation.resume(returning: fullText)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.processingFailed(error))
                }
            }
        }
    }

    enum OCRError: LocalizedError {
        case noTextFound
        case processingFailed(Error)
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .noTextFound:
                return "No text detected in the scanned document"
            case .processingFailed(let error):
                return "OCR processing failed: \(error.localizedDescription)"
            case .invalidImage:
                return "Could not process image format"
            }
        }
    }
}
