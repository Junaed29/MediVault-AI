# MediVault: Complete Architecture Guide

> A privacy-first, fully offline iOS app that lets users scan medical documents and query their health history using natural language — all processed entirely on-device.

---

## How the App Works (End-to-End Flow)

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  User scans  │ →  │   OCR +      │ →  │   Embed +    │ →  │   Stored in  │
│  document    │    │   Chunking   │    │   Vectorize  │    │   SQLite DB  │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
       ↑                                                            │
       │                                                            ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Answer     │ ←  │   LLM        │ ←  │   Build      │ ←  │   Retrieve   │
│   displayed  │    │   Generation │    │   Prompt     │    │   Top Chunks │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

### The Two Main Flows

| Flow | What Happens |
|------|--------------|
| **Document Ingestion** | Scan → OCR → Chunk → Embed → Store |
| **Query Processing** | Question → Embed → Retrieve → Generate → Validate → Answer |

---

## What's Validated at Each Stage

| Stage | Validation | Why |
|-------|-----------|-----|
| **OCR (VisionKit)** | Text extraction quality | Ensures readable text from scanned images |
| **Chunking** | 500-char chunks with overlap | Keeps context coherent, fits embedding model limits |
| **Embedding** | 384-dimension vectors | Fixed size required by MiniLM model |
| **Retrieval** | Cosine similarity ≥ 0.5 | Filters out irrelevant chunks |
| **Safety Filter** | Blocks dangerous queries | Prevents medical advice that could harm users |
| **Grounding Validator** | Answer cites sources | Ensures LLM doesn't hallucinate information |

---

## Behind the Scenes: Example Walkthrough

**User asks:** *"What was my last medical report about?"*

### Step 1: Embed the Query
```swift
// RAGOrchestrator.swift line 55
let queryEmbedding = try await embeddingService.embed(text: userQuery)
→ [0.023, -0.156, 0.089, ...] (384 floats)
```

### Step 2: Retrieve Similar Chunks
```swift
// RAGOrchestrator.swift line 59
let retrieved = try await vectorStore.findSimilar(
    queryEmbedding: queryEmbedding,
    limit: 3,
    threshold: 0.5
)
→ Returns top 3 matching chunks:
  1. "Blood test results: Hemoglobin 14.2..." (score: 0.87)
  2. "Doctor notes: Patient shows improvement..." (score: 0.72)
  3. "Prescription: Continue current medication..." (score: 0.65)
```

### Step 3: Build Prompt
```swift
// RAGOrchestrator.swift line 75-76
let systemPrompt = PromptBuilder.systemPrompt()
let userPrompt = PromptBuilder.userPrompt(context: context, query: userQuery)
→ System: "You are a medical assistant. Answer based ONLY on the provided context..."
→ User: "Context: [3 chunks above]\n\nQuestion: What was my last medical report about?"
```

### Step 4: LLM Generation
```swift
// RAGOrchestrator.swift line 77-79
let result = try await phi4Service.generate(
    systemPrompt: systemPrompt, userPrompt: userPrompt
)
→ CitedAnswer {
    answer: "Your last medical report was a blood test showing hemoglobin at 14.2...",
    sources: [0, 1]
}
```

### Step 5: Grounding Validation (AFTER LLM)

The `GroundingValidator` checks if the LLM's answer is actually supported by the source documents:

```swift
// RAGOrchestrator.swift line 83
let groundingResult = groundingValidator.validate(answer: answer, context: context)
```

#### How `isGrounded` is Determined

Uses **claim-by-claim verification**:

```swift
// GroundingValidator.swift
func validate(answer: String, context: String) -> GroundingResult {
    let claims = extractClaims(from: answer)  // Split into sentences
    
    for claim in claims {
        let keyTerms = extractKeyTerms(from: claim)  // Words > 4 chars, numbers, units
        
        var foundCount = 0
        for term in keyTerms {
            if context.contains(term) { foundCount += 1 }
        }
        
        let coverage = foundCount / keyTerms.count
        if coverage >= 0.6 { groundedCount += 1 }  // ≥60% terms found → grounded
    }
    
    let groundingRatio = groundedCount / totalClaims
    let isGrounded = groundingRatio >= 0.8  // ≥80% claims grounded → answer is grounded
}
```

**Example:**
```
Answer: "Your hemoglobin was 14.2 mg/dL on January 15th"
Key Terms: ["hemoglobin", "14.2", "mg/dL", "january"]
Context: "Blood test Jan 15: Hemoglobin 14.2 mg/dL..."
Found: 4/4 terms → 100% coverage → claim grounded ✓
```

#### How `hasDangerousContent` is Determined

Checks for **dangerous phrase patterns** that indicate medical advice:

```swift
// GroundingValidator.swift
private func containsDangerousAdvice(_ text: String) -> Bool {
    let dangerousPatterns = [
        // Diagnosing
        "you have", "you are diagnosed", "this indicates", "this means you have",
        // Prescribing
        "you should take", "start taking", "stop taking", "discontinue",
        // Dosage advice
        "increase your dose", "decrease your dose",
        // Imperative medical advice
        "you must", "you need to", "immediately start",
        // Contradicting professionals
        "ignore your doctor", "doctor is wrong", "don't listen to"
    ]
    
    return dangerousPatterns.contains { text.lowercased().contains($0) }
}
```

**Examples:**
```
Safe ✓: "Your blood pressure was 120/80 according to the document"
→ hasDangerousContent = false

Blocked 🚫: "You should stop taking your medication"
→ contains "stop taking" → hasDangerousContent = true

Blocked 🚫: "This indicates you have diabetes"
→ contains "this indicates" → hasDangerousContent = true
```

#### GroundingResult Summary

| Field | Threshold | Meaning |
|-------|-----------|---------|
| `isGrounded` | ≥60% per claim, ≥80% of claims | Answer is supported by documents |
| `hasDangerousContent` | Any pattern match | LLM gave medical advice |

### Step 6: SafetyFilter (AFTER Response is Built)

The SafetyFilter applies a **decision tree** to determine how to display the response:

```swift
// SafetyFilter.swift
static func filter(_ response: RAGResponse) -> FilteredResponse {
    // Check 1: Is the answer grounded in source documents?
    if !response.groundingResult.isGrounded {
        return .ungrounded(response)  // ⚠️ Show with warning
    }
    
    // Check 2: Does it contain dangerous medical advice?
    if response.groundingResult.hasDangerousContent {
        return .unsafe  // 🚫 Block completely
    }
    
    // Check 3: Is the retrieval confidence high enough?
    if response.averageScore < 0.4 {
        return .lowConfidence(response)  // ⚠️ Show with warning
    }
    
    // All checks passed
    return .safe(response)  // ✅ Show normally
}
```

**Decision Flow:**
```
                    ┌─────────────────────┐
                    │  RAGResponse input  │
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │   isGrounded?       │
                    └──────────┬──────────┘
                         NO ↙     ↘ YES
                   ┌──────────┐    ▼
                   │.ungrounded│   ┌─────────────────────┐
                   └──────────┘   │ hasDangerousContent?│
                                  └──────────┬──────────┘
                                       YES ↙     ↘ NO
                                 ┌──────────┐    ▼
                                 │  .unsafe │   ┌─────────────────────┐
                                 └──────────┘   │ averageScore > 0.4? │
                                                └──────────┬──────────┘
                                                     NO ↙     ↘ YES
                                             ┌───────────────┐ ┌───────┐
                                             │.lowConfidence │ │ .safe │
                                             └───────────────┘ └───────┘
```

**What User Sees for Each Case:**
| Result | User Message |
|--------|--------------|
| `.safe` | *"Your blood pressure was 120/80..."* |
| `.ungrounded` | *"⚠️ Unverified information. Generated answer: ..."* |
| `.unsafe` | *"🚫 Safety intervention. Cannot provide medical advice."* |
| `.lowConfidence` | *"⚠️ Low confidence answer. Possible answer: ..."* |

### Step 7: Display to User
```
ChatViewModel receives FilteredResponse
→ .safe case: Shows answer directly
→ User sees: "Your last medical report was a blood test showing hemoglobin at 14.2..."
```

---

## Data Flow Diagram

```
                    DOCUMENT INGESTION
                    ==================
                    
User → [Camera/Photos] → VisionOCRService → TextChunker → EmbeddingService
                              │                  │              │
                              ▼                  ▼              ▼
                         Raw Text           Chunks[]        Embeddings[]
                                                │              │
                                                └──────┬───────┘
                                                       ▼
                                                  VectorStore
                                                  (SQLite DB)


                    QUERY PROCESSING
                    =================
                    
User Question → SafetyFilter → EmbeddingService → VectorStore.findSimilar()
                    │                                    │
                    ▼                                    ▼
              (block if unsafe)              Top-K Relevant Chunks
                                                       │
                                                       ▼
                                              PromptBuilder.build()
                                                       │
                                                       ▼
                                              Phi4MiniService.generate()
                                                       │
                                                       ▼
                                              GroundingValidator.validate()
                                                       │
                                                       ▼
                                              RAGResponse → ChatView
```

---

## Document Ingestion Pipeline (Detailed)

When a user scans or imports a document, here's exactly what happens:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Camera/   │ →  │  VisionOCR  │ →  │   Text      │ →  │  Embedding  │
│   Photos    │    │   Service   │    │   Chunker   │    │   Service   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     Image         →   Raw Text    →    Chunks[]     →   Embeddings[]
                                              │                │
                                              └───────┬────────┘
                                                      ▼
                                              ┌─────────────────┐
                                              │   VectorStore   │
                                              │    (SQLite)     │
                                              └─────────────────┘
```

### Step 1: Image Capture
- User taps "Scan Document" → Opens iOS camera via VisionKit
- User taps "Import from Photos" → Opens photo picker
- Result: One or more `UIImage` objects

### Step 2: OCR (VisionOCRService)
```swift
VisionOCRService.recognizeText(from: image)
→ "Patient visited on Jan 15, 2024. Blood pressure 120/80..."
```
- Uses Apple Vision framework (`VNRecognizeTextRequest`)
- Extracts text from scanned document images
- Handles multiple pages, rotations, and image quality issues

### Step 3: Chunking (TextChunker)
```swift
TextChunker.chunk(text: rawText, size: 500, overlap: 50)
→ ["Patient visited on Jan 15...", "Blood pressure 120/80...", ...]
```
- Splits long text into ~500 character chunks
- **Why 500?** Fits within embedding model's token limit (~512 tokens)
- **Why overlap?** Preserves context at chunk boundaries
- Result: Array of text strings

### Step 4: Embedding (EmbeddingService)
```swift
for chunk in chunks {
    let embedding = try await embeddingService.embed(text: chunk)
    // embedding = [0.023, -0.156, 0.089, ...] (384 floats)
}
```
- Each chunk is converted to a 384-dimensional vector
- Uses MiniLM model via CoreML
- Vectors capture semantic meaning (similar text → similar vectors)

### Step 5: Storage (VectorStore)
```swift
try await vectorStore.insertBatch(documentChunks)
```

Each `DocumentChunk` record stored in SQLite contains:

| Field | Type | Example |
|-------|------|---------|
| `id` | Int64 | 1, 2, 3... |
| `documentId` | String | "scan_2024-01-28_143022" |
| `chunkIndex` | Int | 0, 1, 2... |
| `content` | String | "Patient visited on Jan 15..." |
| `embedding` | Data | Binary blob of 384 floats |
| `createdAt` | Date | 2024-01-28 14:30:22 |

### Why Store Both Text AND Embedding?

| Stored | Used For |
|--------|----------|
| **content** (text) | Displayed in LLM prompt, shown in DocumentDetailView |
| **embedding** (vector) | Similarity search to FIND relevant chunks |

**The embedding helps FIND the chunk → The content is what gets READ!**

---

## Viewing Full Documents in DocumentsTab

### How It Works (Already Implemented)

1. **Tap any document** → `NavigationLink` opens `DocumentDetailView`
2. **DocumentDetailView** calls `orchestrator.fetchDocumentContent(documentId:)`
3. **VectorStore** retrieves all chunks for that document, ordered by `chunkIndex`
4. **Chunks are joined** with `\n\n` separator → Full document text displayed

```swift
// VectorStore.swift
func fetchDocumentContent(documentId: String) async throws -> String {
    let chunks = try await dbQueue.read { db in
        try DocumentChunk
            .filter(DocumentChunk.Columns.documentId == documentId)
            .order(DocumentChunk.Columns.chunkIndex.asc)
            .fetchAll(db)
    }
    return chunks.map { $0.content }.joined(separator: "\n\n")
}
```

### User Flow
```
DocumentsTab (list) → Tap document → DocumentDetailView (full text)
                                      └── ScrollView with all content
                                      └── Loading spinner while fetching
```

---

## How to Explain This in an Interview

### 60-90 Second Pitch

> "MediVault is a privacy-focused iOS app I built that lets users scan their medical documents and query their health history using natural language — all processed entirely on-device for maximum privacy.
>
> The core architecture is a RAG pipeline: when you scan a document, it goes through OCR using Apple's Vision framework, gets chunked into smaller pieces, embedded into vectors using a MiniLM CoreML model, and stored in a local SQLite database.
>
> When you ask a question, the system embeds your query, performs a cosine similarity search to find relevant chunks, builds a prompt with that context, and generates an answer using a quantized Qwen 1.5B model running via llama.cpp.
>
> I added safety filters to block potentially harmful medical advice queries, and a grounding validator to ensure the LLM only responds with information from your actual documents — preventing hallucinations.
>
> The key technical challenge was making all of this run efficiently on an iPhone without an internet connection, which required careful optimization of model sizes and using Swift actors for thread safety."

---

### Architecture Bullet Flow

When asked "Walk me through the architecture":

1. **Presentation Layer**: SwiftUI views + @Observable ViewModels
2. **Business Logic**: RAGOrchestrator coordinates the pipeline
3. **Services Layer**: 
   - `EmbeddingService` (CoreML, MiniLM, 384-dim)
   - `VectorStore` (GRDB/SQLite, cosine similarity)
   - `Phi4MiniService` (llama.cpp, quantized LLM)
4. **Safety Layer**: SafetyFilter + GroundingValidator
5. **Data Layer**: DocumentChunk model, persistent SQLite storage

---

### Key Tradeoffs and Decisions

| Decision | Tradeoff | Why I Chose It |
|----------|----------|----------------|
| **On-device only** | Limited model size vs. privacy | Medical data is sensitive; privacy is non-negotiable |
| **Qwen 1.5B over GPT-4** | Lower quality vs. offline capability | Users can query without internet; acceptable quality |
| **SQLite over vector DB** | No ANN index vs. simplicity | Small dataset size; brute-force works fine |
| **384-dim embeddings** | Less precision vs. speed | MiniLM is fast enough for mobile; good quality |
| **Q4 quantization** | Slight accuracy loss vs. 60% size reduction | Makes model fit in memory on older devices |

---

### Common Interviewer Follow-ups

**Q: "Why not use a cloud API like OpenAI?"**
> "Medical documents contain extremely sensitive personal health information. Sending that to external servers creates privacy and compliance risks. On-device processing ensures data never leaves the user's phone."

**Q: "How do you handle hallucinations?"**
> "Two mechanisms: First, the GroundingValidator checks that the LLM's answer is actually supported by the retrieved documents. Second, the prompt explicitly instructs the model to only use provided context and say 'I don't know' if information isn't available."

**Q: "What if the document database grows large?"**
> "Currently using brute-force cosine similarity which works fine for hundreds of documents. For scale, I'd add an approximate nearest neighbor index like HNSW, or shard the database by document type."

**Q: "How do you handle concurrent access?"**
> "All services are Swift actors, which provide automatic isolation and thread-safe access. The VectorStore wraps GRDB's DatabaseQueue which handles SQLite concurrency internally."

**Q: "What was the hardest technical challenge?"**
> "Getting the LLM to run efficiently on-device. I had to carefully select a model small enough (1.5B parameters), use aggressive quantization (Q4_K_M), and optimize the prompt length to balance context quality with inference speed. The first iteration took 30+ seconds per query; now it's under 5 seconds."

**Q: "How would you improve this?"**
> "Three things: (1) Add document type classification to improve retrieval relevance, (2) Implement streaming responses so users see partial answers faster, (3) Add a re-ranking step using a cross-encoder to improve chunk selection."

---

## File Reference

| Component | File | Purpose |
|-----------|------|---------|
| App Entry | `MediVaultApp.swift` | Initializes services, shows loading state |
| Chat UI | `ChatView.swift` | Message list, input field |
| ViewModel | `ChatViewModel.swift` | Manages messages, calls orchestrator |
| Orchestrator | `RAGOrchestrator.swift` | Coordinates full RAG pipeline |
| Embeddings | `EmbeddingService.swift` | CoreML MiniLM inference |
| Vector DB | `VectorStore.swift` | SQLite storage + similarity search |
| LLM | `Phi4MiniService.swift` | llama.cpp inference wrapper |
| Document Model | `DocumentChunk.swift` | GRDB record definition |
| Safety | `SafetyFilter.swift` | Blocks dangerous queries |
| Grounding | `GroundingValidator.swift` | Validates LLM cites sources |

---

## Tech Stack Summary

- **Language**: Swift 5.0
- **UI**: SwiftUI
- **Embeddings**: MiniLM via CoreML
- **LLM**: Qwen 2.5-1.5B-Instruct (Q4_K_M GGUF) via SwiftLlama
- **Database**: SQLite via GRDB.swift
- **OCR**: Apple Vision framework
- **Concurrency**: Swift actors + async/await
