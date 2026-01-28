# MediVault AI – Technical Details

> Privacy-First On-Device Medical RAG Assistant (iOS, Offline)  
> Status: In Development (2026)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      End-to-End Pipeline                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [Document Scan] → [OCR] → [Chunk] → [Embed] → [VectorStore]   │
│                                                                 │
│  [User Query] → [Embed] → [Retrieve Top-K] → [Build Prompt]    │
│              → [LLM Generate] → [Ground/Validate] → [Display]   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key Components:**
- **Ingestion**: VisionKit OCR → TextChunker → EmbeddingService → VectorStore
- **Query**: EmbeddingService → VectorStore → PromptBuilder → LLM → GroundingValidator → SafetyFilter
- **All processing on-device** – no network calls

---

## 2. Technology Choices & Rationale

| Component | Technology | Why |
|-----------|------------|-----|
| **Concurrency** | Swift 6 + `actor` + `async/await` | Thread-safe, no data races, clean async code |
| **Vector Math** | Accelerate framework | SIMD-optimized cosine similarity, <50ms retrieval |
| **Embeddings** | all-MiniLM-L6-v2 (CoreML) | 384-dim, fast inference, good semantic quality |
| **LLM Runtime** | SwiftLlama (llama.cpp wrapper) | Native GGUF support, Metal GPU acceleration |
| **LLM Model** | Qwen2.5 1.5B Instruct (Q4_K_M) | Best quality/size trade-off for mobile |
| **Storage** | SQLite via GRDB.swift | Reliable, single-file DB, good iOS support |

**Trade-off**: Chose Qwen2.5 1.5B over larger models (3B+) to stay within 3.4GB memory budget while maintaining coherent medical responses.

---

## 3. Data Ingestion & Preprocessing

**Pipeline:**
```
Image → VisionKit OCR → Raw Text → Normalize → Chunk → Embed → Store
```

**Steps:**
- **OCR**: `VNRecognizeTextRequest` with `.accurate` recognition level
- **Normalization**: Trim whitespace, collapse newlines, remove OCR artifacts
- **Chunking**: 500 characters per chunk, 50 character overlap
- **Metadata**: `documentId`, `chunkIndex`, `timestamp`

**Why 500/50?**
- MiniLM has 256 token max → ~500 chars stays within limit
- 50 char overlap preserves context across chunk boundaries

---

## 4. Embedding & Indexing

| Parameter | Value |
|-----------|-------|
| Embedding model | all-MiniLM-L6-v2 |
| Vector dimension | 384 |
| Index type | Brute-force (flat) |
| Distance metric | Cosine similarity |
| Top-K retrieval | 3 chunks |
| Similarity threshold | 0.5 |

**Retrieval Flow:**
```swift
queryEmbedding = embed(userQuery)           // 384-dim vector
results = vectorStore.findSimilar(          
    queryEmbedding, limit: 3, threshold: 0.5
)
// Uses Accelerate vDSP for SIMD cosine similarity
```

**Trade-off**: Brute-force search is O(n) but sufficient for personal document scale (~1000s of chunks). HNSW index planned if scale increases.

---

## 5. Prompt & RAG Orchestration

**Context Window Strategy:**
- System prompt: ~400 tokens (instructions, safety rules)
- Context: Top 3 chunks (~300 tokens each = 900 tokens)
- Conversation history: Last 4 Q&A pairs (~400 tokens)
- User query: ~50 tokens
- **Total**: ~1750 tokens input, 512 tokens output budget

**Prompt Structure:**
```
[System] You are MediVault AI...rules...JSON format
[User Q1] → [Assistant A1] → [User Q2] → [Assistant A2]  // History
[Context] Source 1: ... Source 2: ... Source 3: ...
[Current Query] User's question
```

**Grounding Checks:**
- Extract claims from response
- Validate each claim against source context (40% key term match per claim)
- Require 50% of claims grounded for "verified" status
- Pattern match for dangerous medical advice

---

## 6. On-Device Inference Details

**Model Specification:**
```
Model: Qwen2.5 1.5B Instruct
Quantization: Q4_K_M (4-bit, k-quant mixed)
File: qwen2.5-1.5b-instruct-q4_k_m-00001-of-00001.gguf
Size: ~1.1GB on disk
```

**Runtime Configuration:**
```swift
LlamaService(
    modelUrl: modelUrl,
    config: .init(
        batchSize: 256,        // Tokens per batch
        maxTokenCount: 4096,   // Context window
        useGPU: true           // Metal acceleration
    )
)
```

**Memory Strategy:**
- Model loaded once at app launch, kept in memory
- Context cleared between conversations
- KV cache reused within conversation turn

**Performance Targets:**
| Metric | Target | Achieved |
|--------|--------|----------|
| Token generation | 8–10 tok/s | ~9 tok/s (iPhone 12 Pro) |
| Memory usage | <3.4GB | ~2.8GB typical |
| Retrieval latency | <50ms | ~30ms |

**Trade-off**: Q4_K_M chosen over Q8 (better quality) to fit memory budget. Quality loss minimal for RAG use case.

---

## 7. Privacy & Security

**Core Principles:**
- ✅ **100% on-device** – no API calls, no telemetry
- ✅ **No network by default** – app works in airplane mode
- ✅ **Local storage only** – SQLite in app sandbox

**Data Protection:**
- iOS Data Protection (file-level encryption at rest)
- App sandbox isolation
- No cloud sync of medical documents
- Documents stay in user's control

**HIPAA-Aligned Practices:**
- No PHI leaves device
- No logging of medical content
- User can delete all data via "Clear All Documents"

---

## 8. Safety Guardrails

**Multi-Layer Safety:**

```
LLM Output → GroundingValidator → SafetyFilter → User Display
```

**Layer 1: Prompt Engineering**
- Explicit instructions: "Never diagnose", "Never prescribe"
- Required JSON output format constrains response

**Layer 2: GroundingValidator**
- Checks if response cites source documents
- Detects dangerous phrases: "you should take", "stop taking", "this indicates you have"
- Flags ungrounded claims

**Layer 3: SafetyFilter**
- `.safe` → Display directly
- `.ungrounded` → "Unverified information" prefix
- `.unsafe` → Block response, show warning
- `.lowConfidence` → Show with confidence warning

**Response Patterns Blocked:**
```swift
let dangerousPatterns = [
    "you should take", "stop taking", "discontinue",
    "you have", "this indicates", "diagnosis is",
    "increase your dose", "ignore your doctor"
]
```

---

## 9. Performance Plan

**Latency Budget Breakdown:**
| Stage | Budget | Actual |
|-------|--------|--------|
| Query embedding | 50ms | ~40ms |
| Vector retrieval | 50ms | ~30ms |
| Prompt building | 10ms | ~5ms |
| LLM generation (100 tokens) | 10s | ~11s |
| Grounding validation | 20ms | ~15ms |
| **Total (excluding LLM)** | 130ms | ~90ms |

**Caching Strategy:**
- Document embeddings: Computed once, stored in VectorStore
- Model: Loaded at startup, kept in memory
- No query caching (queries are unique)

**Profiling Approach:**
- Instruments: Time Profiler for CPU bottlenecks
- Instruments: Allocations for memory profiling
- Custom timing logs per pipeline stage

---

## 10. Testing Plan

**Unit Tests:**
- TextChunker: Verify chunk sizes, overlap
- VectorMath: Cosine similarity correctness
- GroundingValidator: Claim extraction, dangerous pattern detection
- SafetyFilter: Correct filtering for each case

**Integration Tests:**
- End-to-end: Ingest document → Query → Get response
- Conversation history: Multi-turn context preservation

**Grounding Accuracy Measurement:**
```
Dataset: 100 Q&A pairs with known source documents
Metric: % of responses correctly citing source material
Target: 90% grounded accuracy
```

**Regression Tests:**
- Golden test set of queries with expected response patterns
- Run after model or threshold changes

---

## 11. Deployment & Setup

**Model Packaging:**
```
MediVault/Resources/Models/
├── qwen2.5-1.5b-instruct-q4_k_m-00001-of-00001.gguf  (~1.1GB)
└── float16_model.mlpackage/  (MiniLM embedding model)
```

**App Size Considerations:**
| Component | Size |
|-----------|------|
| LLM (GGUF) | ~1.1GB |
| Embedding model | ~90MB |
| App code + assets | ~20MB |
| **Total** | ~1.2GB |

**Build Configurations:**
- Debug: Full logging, slower
- Release: Optimizations enabled, no logging
- Models bundled in app (not downloaded on-demand)

**Minimum Requirements:**
- iOS 17.0+
- iPhone 12 or newer (for memory/performance)
- 4GB+ RAM recommended

---

## 12. Known Limitations & Next Steps

**Current Limitations:**
- ❌ OCR quality depends on document clarity
- ❌ No PDF native support (images only)
- ❌ English-only (model limitation)
- ❌ Context window limits long conversations
- ❌ No document organization/folders

**Next Steps:**
1. **Improve OCR**: Add PDF text extraction, table parsing
2. **Multi-language**: Test multilingual models
3. **Better retrieval**: Implement hybrid search (keyword + semantic)
4. **User experience**: Add document naming, folders, search
5. **Performance**: Profile on A15/A16 chips, optimize further
6. **Testing**: Expand evaluation dataset, add automated accuracy tests

---

## Quick Reference for Interviews

**"How does retrieval work?"**
> Query embedded with MiniLM → cosine similarity search in SQLite-backed vector store → top 3 chunks returned in <50ms

**"Why on-device?"**
> Medical data privacy. No API calls means no PHI exposure, no network dependency, HIPAA-aligned by design.

**"How do you prevent hallucinations?"**
> Multi-layer: grounding validation checks if response terms exist in source docs, pattern matching blocks dangerous advice, SafetyFilter categorizes responses.

**"Why Qwen2.5 1.5B?"**
> Best quality-to-size ratio for mobile. Q4_K_M quantization fits in 3.4GB memory budget while maintaining coherent generation at 8-10 tok/s.

**"How do you handle multi-turn?"**
> Last 4 Q&A pairs passed to LLM via SwiftLlama's message array. Enables follow-up questions like "tell me more" without re-stating context.
