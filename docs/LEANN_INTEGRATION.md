# LEANN Integration Reference

> How CatchMeUp uses LEANN, what's already set up, and how to call it from Swift.

---

## 1. What LEANN is

LEANN ([github.com/yichuan-w/LEANN](https://github.com/yichuan-w/LEANN), Berkeley Sky Computing Lab) is a local vector index and RAG toolkit that achieves 97% storage reduction compared to traditional vector DBs via **graph-based selective recomputation with high-degree preserving pruning**. Paper: [arXiv:2506.08276](https://arxiv.org/abs/2506.08276).

**Why CatchMeUp uses it**:
- Local-first (the core differentiator we need to sell against Rewind/Limitless)
- Already has pre-built adapters for Apple Mail, WeChat, iMessage, ChatGPT/Claude history, Slack, Twitter, arbitrary documents (PDF/MD/TXT), browser history, and code
- Supports `--llm anthropic` out of the box for one-shot RAG+LLM calls
- CLI-first design (perfect for Swift subprocess integration)
- Ships with a working MCP server (`leann_mcp`) which Claude Code is already using in this session

## 2. Local Install State

**Location**: `/Users/yizhi/leann/`
**Install method**: git clone + `uv sync --extra diskann` (see `README.md` in that repo)
**Virtual environment**: `/Users/yizhi/leann/.venv/`
**CLI invocation**: `source /Users/yizhi/leann/.venv/bin/activate && leann ...`
**Global install** (required for MCP server): `uv tool install leann-core --with leann`
**MCP server registration**: `claude mcp add --scope user leann-server -- leann_mcp` (already done)

## 3. Existing Indices (as of 2026-04-08)

Run `leann list` to see the current state. At plan time:

| Index name | Size | Content | CatchMeUp role |
|---|---|---|---|
| `mail_index` | 26 MB | Apple Mail corpus (past ~years) | `MailDataSource` queries this for all mail-related retrieval |
| `wechat_history_magic_test_11Debug_new` | 43 MB | WeChat chat history (exported via WeChatTweak-CLI) | `WeChatDataSource` queries this for chat-related retrieval |
| `test-demo` | 2.7 MB | Small test fixture | safe to ignore or delete |

**Indices CatchMeUp will add**:

| Index name | Source | Built by | Notes |
|---|---|---|---|
| `transcripts_index` | Whisper output under `~/Library/Application Support/AllTimeRecorded/transcripts/` | `TranscriptIndexer.swift` (Phase 3) | Flat text per day; rebuilt incrementally via `leann watch` |
| `files_index` | `~/Documents/CatchMeUpInbox/` + user-added folders | `FileIndexManager.swift` (Phase 3) | User-curated whitelist, not the whole filesystem |
| `eval_adversarial_index` | `docs/eval/adversarial_corpus.json` fixtures | `EvalService.swift` (Phase 3) | Fixture only, used for guardrail testing |

## 4. CLI Commands We Depend On

All runtime operations go through the CLI. Python API is not embedded in Swift.

### 4.1 Search (primary runtime call)

```bash
leann search INDEX_NAME "QUERY" --top-k 5 --complexity 32
```

Returns top-K chunks. Output format is currently human-readable; Swift parses it line-by-line. **Action item**: once `leann search --format json` lands (track in LEANN upstream), switch to JSON parsing for robustness. Fallback: pipe through a small wrapper script that emits JSON.

Example:
```bash
leann search mail_index "what did Alice say about Q3" --top-k 5 --complexity 32
```

### 4.2 Ask (single-index RAG+LLM in one shot)

```bash
leann ask INDEX_NAME "QUERY" --llm anthropic --model claude-opus-4-6 --top-k 20
```

Used only in the "scoped source" fast path (when user prefixes query with `@mail` / `@wechat` / `@audio` / `@files`). For cross-source queries, we do `leann search` in parallel and call Claude ourselves via `AnthropicClient.swift`.

### 4.3 Build

```bash
leann build INDEX_NAME --docs PATH [PATH ...] \
  --backend hnsw \
  --embedding-mode sentence-transformers \
  --embedding-model all-MiniLM-L6-v2 \
  [--force]
```

First-time index creation. Rebuilds existing index if `--force` is passed. Idempotent otherwise (uses Merkle tree diff).

### 4.4 Watch (incremental update daemon)

```bash
leann watch INDEX_NAME
```

Long-lived subprocess. Detects file changes via SHA-256 Merkle tree snapshots. On change, re-chunks and re-indexes only the modified files. CatchMeUp runs this as a daemon for `transcripts_index` and `files_index`.

### 4.5 List / remove

```bash
leann list                         # all indices across projects
leann remove INDEX_NAME --force    # delete with confirmation skip
```

### 4.6 MCP server

```bash
leann_mcp                          # stdio MCP server, already wired into Claude Code
```

The MCP server exposes `leann_list` and `leann_search` as tools. Phase 4 may introduce `LEANNDaemonClient.swift` that speaks stdio JSON-RPC to this daemon for sub-100ms queries, bypassing subprocess cold-start overhead.

## 5. Swift Integration Contract

`Sources/CatchMeUp/RAG/LEANNBridge.swift` wraps LEANN CLI calls as Swift async methods. Skeleton:

```swift
actor LEANNBridge: LEANNBridging {
    private let leannPath: URL  // /Users/yizhi/leann/.venv/bin/leann
    private var cache: NSCache<NSString, CachedResult> = NSCache()

    func search(index: String, query: String, topK: Int) async throws -> [SourceChunk] {
        // 1. Check cache with key "\(index)|\(query)|\(topK)"
        // 2. If miss, launch Process:
        //    - executableURL = leannPath
        //    - arguments = ["search", index, query, "--top-k", "\(topK)", "--complexity", "32"]
        //    - environment = inherit ANTHROPIC_API_KEY from parent
        //    - stdout piped into UTF-8 reader
        // 3. Parse stdout into [SourceChunk]
        // 4. Cache and return
        // 5. On timeout (4s default), return empty and log warning
    }

    func ask(index: String, query: String, topK: Int,
             model: String = "claude-opus-4-6") async throws -> String {
        // Fast path for scoped single-source queries
        // Launches: leann ask INDEX QUERY --llm anthropic --model MODEL --top-k TOPK
    }

    func build(index: String, docs: [URL], force: Bool) async throws -> BuildStatus {
        // Phase 3: used for transcripts_index and files_index initial build
    }

    func watch(index: String) async throws -> Process {
        // Returns the long-lived Process handle so IndexHealthMonitor can tail it
    }

    func list() async throws -> [IndexInfo]
    func remove(index: String) async throws
}
```

**Why subprocess, not Python embed**: Swift ↔ Python bridging is complicated (PythonKit works but has macOS 15 quirks). Subprocess is language-agnostic, crashes are isolated, and the CLI is the canonical interface LEANN maintains. The only overhead is Python interpreter startup (~300–800 ms per call), mitigated by the in-memory cache and eventually the daemon.

## 6. Environment Requirements

- **Python**: 3.10+ (LEANN uses PEP 604 `X | Y` union syntax)
- **macOS**: 13.3+ for DiskANN backend; HNSW works on older
- **Embedding model on-disk**: `all-MiniLM-L6-v2` via sentence-transformers, ~90 MB, cached at `~/.cache/huggingface/`
- **Environment variable**: `ANTHROPIC_API_KEY` must be set for `leann ask --llm anthropic` calls. CatchMeUp sets it from Keychain before spawning subprocesses.

## 7. Supported Data Sources (from LEANN README)

LEANN ships with adapters for:

- **Documents** (`.pdf`, `.txt`, `.md`, `.docx`, `.pptx`, code files) via `apps.document_rag`
- **Apple Mail** via `apps.email_rag` (requires Full Disk Access for the terminal/IDE)
- **Chrome browser history** via `apps.browser_rag`
- **WeChat** via `apps.wechat_rag` (requires WeChatTweak-CLI exporter)
- **iMessage** via `apps.imessage_rag` (requires Full Disk Access for `~/Library/Messages/chat.db`)
- **ChatGPT history** via `apps.chatgpt_rag` (HTML/ZIP export)
- **Claude history** via `apps.claude_rag` (JSON export)
- **Slack** via `apps.slack_rag` (MCP server based)
- **Twitter bookmarks** via `apps.twitter_rag` (MCP server based)
- **Arbitrary code repos** via `apps.code_rag` (AST-aware chunking for Python/Java/C#/TypeScript)

CatchMeUp's roadmap uses a subset of these:
- V1 (Phases 1–4): mail, wechat, transcripts (our own), files
- Phase 5 (post-pitch runway): iMessage, browser history, ChatGPT/Claude exports

## 8. Known Quirks & Gotchas

1. **`leann search` cold start is 300–800 ms** per call. Parallel fanout of 4 sources → ~3 s worst case. Mitigations: in-memory cache, long-lived daemon via MCP server in Phase 4, warm interpreter via keeping `leann_mcp` running.
2. **`leann watch` needs to run as a daemon**. If CatchMeUp restarts, the watch process dies. Solution: `IndexHealthMonitor` relaunches watchers on app launch.
3. **WeChat index rebuild** requires re-running `wechattweak-cli` to export fresh data. Not automatic. Document this in the user-facing Settings → Sources → WeChat help text.
4. **Apple Mail index** requires Full Disk Access granted to the terminal/IDE running `leann build email`. This is a one-time setup. User will need to grant this to the CatchMeUp.app itself in Phase 4 if we move LEANN build in-app.
5. **`--compact` vs `--no-compact`** and `--recompute` vs `--no-recompute` are LEANN build flags that trade off storage vs query speed. Default (compact + recompute) is optimal for CatchMeUp. Do NOT change without benchmarking.
6. **SHA256 model verification is currently disabled** in AllTimeRecorded's `ModelAssetService.swift`. Re-enable as a hardening chore in Phase 3 or 4.
7. **The backend choice matters**. Default HNSW is fine for < 1M chunks. DiskANN is for larger-than-memory datasets (not CatchMeUp's profile). Stick with HNSW.

## 9. Quick Manual Test (when debugging Swift subprocess calls)

```bash
cd /Users/yizhi/leann
source .venv/bin/activate

# Sanity check
leann list

# Search mail_index
leann search mail_index "quarterly budget" --top-k 3

# Full RAG+LLM via Claude
export ANTHROPIC_API_KEY="$(security find-generic-password -s com.catchmeup.anthropic -a default -w)"
leann ask mail_index "what did we decide about the quarterly budget?" \
  --llm anthropic --model claude-opus-4-6 --top-k 10
```

If the manual commands work but Swift calls fail, the bug is in `LEANNBridge.swift` argument construction or stdout parsing. If the manual commands fail, the bug is in LEANN itself — fix in `/Users/yizhi/leann` and the fix flows through automatically.

## 10. Upgrade Path (when LEANN ships a new version)

1. `cd /Users/yizhi/leann && git pull && git submodule update --recursive`
2. `uv sync --extra diskann` (may need `brew install` of any new deps)
3. Re-install global: `uv tool install --force leann-core --with leann`
4. Run `EvalService.runFull()` to verify hit rate and stability did not regress
5. If regression, pin to the previous version in `/Users/yizhi/leann` (git checkout the previous tag) and file an issue upstream

## 11. Revision Log

| Date | Change |
|---|---|
| 2026-04-08 | Initial reference based on LEANN `README.md`, `CLAUDE.md`, and `packages/leann-mcp/README.md` |
