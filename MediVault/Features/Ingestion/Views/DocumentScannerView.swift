//
//  DocumentScannerView.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import SwiftUI
import VisionKit
import UIKit

struct DocumentScannerView: UIViewControllerRepresentable {
    let orchestrator: RAGOrchestrator
    @Binding var isPresented: Bool
    var onDocumentScanned: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard VNDocumentCameraViewController.isSupported else {
            let fallback = UIViewController()
            print("Document scanner not supported on this device")
            return fallback
        }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, orchestrator: orchestrator)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        let orchestrator: RAGOrchestrator

        init(parent: DocumentScannerView, orchestrator: RAGOrchestrator) {
            self.parent = parent
            self.orchestrator = orchestrator
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            print("Scanner finished, pages:", scan.pageCount)

            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: pageIndex))
            }

            Task {
                do {
                    let documentId = UUID().uuidString
                    let documentTitle = "Document-\(Date().formatted(date: .abbreviated, time: .omitted))"

                    try await orchestrator.ingestDocument(
                        images: images,
                        documentId: documentId,
                        documentTitle: documentTitle
                    )

                    parent.onDocumentScanned(documentTitle)
                    parent.isPresented = false
                } catch {
                    print("OCR/ingestion failed:", error.localizedDescription)
                    parent.isPresented = false
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            print("Scanner cancelled")
            parent.isPresented = false
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            print("Scanner failed:", error.localizedDescription)
            parent.isPresented = false
        }
    }
}
