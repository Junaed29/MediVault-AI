//
//  TextChunker.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import Foundation

struct TextChunker {
    struct Config {
        let chunkSize: Int
        let overlap: Int
        let minChunkSize: Int
        let maxChunkSize: Int

        static let `default` = Config(
            chunkSize: 500,
            overlap: 50,
            minChunkSize: 100,
            maxChunkSize: 1000
        )
    }

    static func chunk(text: String, config: Config = .default) -> [String] {
        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "\n\n+",
                with: "\n\n",
                options: .regularExpression
            )

        guard !cleanedText.isEmpty else { return [] }

        var chunks: [String] = []
        var currentIndex = cleanedText.startIndex

        while currentIndex < cleanedText.endIndex {
            let idealEnd = cleanedText.index(
                currentIndex,
                offsetBy: config.chunkSize,
                limitedBy: cleanedText.endIndex
            ) ?? cleanedText.endIndex

            let chunkEnd = findSentenceBreak(
                in: cleanedText,
                around: idealEnd,
                searchRadius: 50
            ) ?? idealEnd

            let chunk = String(cleanedText[currentIndex..<chunkEnd])

            if chunk.count >= config.minChunkSize {
                chunks.append(
                    chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            let overlapOffset = max(
                config.chunkSize - config.overlap,
                config.minChunkSize
            )

            currentIndex = cleanedText.index(
                currentIndex,
                offsetBy: overlapOffset,
                limitedBy: cleanedText.endIndex
            ) ?? cleanedText.endIndex
        }

        return chunks
    }

    private static func findSentenceBreak(
        in text: String,
        around targetIndex: String.Index,
        searchRadius: Int
    ) -> String.Index? {
        let sentenceEnders: Set<Character> = [".", "!", "?", "\n"]

        let startSearch = text.index(
            targetIndex,
            offsetBy: -searchRadius,
            limitedBy: text.startIndex
        ) ?? text.startIndex

        let endSearch = text.index(
            targetIndex,
            offsetBy: searchRadius,
            limitedBy: text.endIndex
        ) ?? text.endIndex

        let searchRange = startSearch..<endSearch

        var closestBreak: String.Index?
        var minDistance = Int.max

        for index in text[searchRange].indices {
            if sentenceEnders.contains(text[index]) {
                let distance = text.distance(from: targetIndex, to: index)
                if abs(distance) < minDistance {
                    minDistance = abs(distance)
                    closestBreak = text.index(after: index)
                }
            }
        }

        return closestBreak
    }
}
