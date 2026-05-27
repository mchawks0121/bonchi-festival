# 指示

あなたはシニアソフトウェアアーキテクト兼フルスタックエンジニアです。

Claude Code / Claude Desktop / MCP と連携可能な、
ローカル完結型「AI Runtime Observability Platform」を実装してください。

このプロダクトは:

- AI Runtime Trace
- Agent Execution Flow
- Context Flow
- MCP Tool Call
- Replay
- Runtime Visualization
- Runtime Analysis
- Runtime Feedback
- Runtime Optimization

を行う、
AI Runtime の監視・分析・可視化基盤です。

単なる Prompt 保存ツールは禁止。

最重要なのは:

- AIが何をしたか
- なぜその出力になったか
- どこで失敗したか
- どのContextが影響したか

を観測可能にすることです。

---

# プロダクトコンセプト

本プロダクトは:

「AI版 Datadog / OpenTelemetry / Sentry / Chrome DevTools」

を目指します。

AI Runtime の:

- tracing
- observability
- replay
- debugging
- optimization

を可能にしてください。

---

# 想定ユースケース

ユーザーは Claude Code に:

```text
Laravel認可バグ直して
```

のように普通に依頼します。

システムは裏側で:

- Context収集
- MCP Tool Call
- Runtime Event
- Tool Flow
- AI Output
- Eval

を自動収集してください。

ユーザーが:
「保存ボタン」
を押す必要はありません。

AI Runtime を自動記録してください。

---

# 最重要機能

# Runtime Visualization

保存は目的ではなく、
Visualization のための手段です。

以下をリアルタイム可視化してください:

- Runtime Timeline
- Context Graph
- Tool Call Graph
- Runtime Event Stream
- Output Diff
- Runtime Heatmap
- Failure Highlight
- Replay Visualization
- Runtime Suggestions
- Runtime Health Score

---

# 技術構成

# Frontend

- Vue 3
- TypeScript
- Vite
- Pinia
- Vue Router
- TailwindCSS
- Monaco Editor
- xterm.js
- VueFlow
- ECharts

---

# Backend

- Python 3.12
- FastAPI
- SQLAlchemy 2
- asyncpg
- Alembic
- Pydantic v2
- asyncio
- WebSocket

---

# Database

- PostgreSQL
- pgvector

---

# Docker構成

```text
project/
├ web/
├ api/
├ db/
├ docker-compose.yml
└ .env
```

docker-compose で:

- web
- api
- db

を起動。

ホットリロード対応。

---

# pgvector

必ず有効化:

```sql
CREATE EXTENSION vector;
```

---

# ポート設計

既存プロダクトと衝突しにくいよう、
38000番台をデフォルト使用。

以下を `.env` に定義:

```env
# =========================================
# AI Runtime Observability Platform
# =========================================

WEB_PORT=38100
API_PORT=38101
POSTGRES_PORT=38102
REDIS_PORT=38103
MCP_HTTP_PORT=38104
MCP_SSE_PORT=38105

# Optional
GRAFANA_PORT=38106
PROMETHEUS_PORT=38107

# =========================================
# Frontend Runtime URLs
# =========================================

VITE_API_URL=http://localhost:38101

VITE_WS_URL=ws://localhost:38101/runtime/stream

# =========================================
# MCP
# =========================================

MCP_HTTP_ENDPOINT=http://localhost:38104

MCP_SSE_ENDPOINT=http://localhost:38105

# =========================================
# Database
# =========================================

POSTGRES_DB=ai_runtime_observability

POSTGRES_USER=runtime_user

POSTGRES_PASSWORD=runtime_password

DATABASE_URL=postgresql+asyncpg://runtime_user:runtime_password@db:5432/ai_runtime_observability
```

---

# ポートルール

以下禁止:

- localhost:3000
- localhost:5173
- localhost:8000
- localhost:5432

必ず `.env` 参照。

---

# Docker Composeルール

禁止:

```yaml
ports:
  - "3000:3000"
```

必須:

```yaml
ports:
  - "${WEB_PORT}:5173"
```

---

# Docker Network

専用network使用:

```yaml
networks:
  runtime_observability_network:
```

volume名prefix付与:

```yaml
volumes:
  ai_runtime_pgdata:
```

---

# Claude Code向け最重要ルール

Claude Code のコンテキスト効率を最優先してください。

---

# コンテキスト最適化

## 巨大ファイル禁止

1ファイル300行以内。

以下禁止:

- 巨大service
- 巨大component
- 巨大router
- 巨大store

---

# 責務分離

backend:

```text
api/
├ domain/
├ application/
├ infrastructure/
├ presentation/
├ runtime/
├ feedback/
└ mcp/
```

frontend:

```text
web/src/
├ app/
├ pages/
├ widgets/
├ features/
├ entities/
├ shared/
├ runtime/
└ visualization/
```

---

# 命名ルール

悪い例:

```text
utils.py
helpers.ts
service.py
```

良い例:

```text
runtime_event_publisher.py
execution_trace_repository.py
tool_call_graph_builder.ts
context_flow_visualizer.vue
```

---

# 過剰抽象化禁止

以下禁止:

- generic manager
- abstract repository
- base service乱用

YAGNI重視。

---

# Event中心設計

以下イベントをコア概念として扱う:

- EXECUTION_STARTED
- CONTEXT_LOADED
- TOOL_CALLED
- TOOL_COMPLETED
- MODEL_GENERATING
- OUTPUT_RECEIVED
- EVAL_COMPLETED
- EXECUTION_FINISHED
- EXECUTION_FAILED

すべて:

- DB保存
- WebSocket配信
- Replay利用
- Visualization利用

可能にする。

---

# Dashboard UI

トップページ:

```text
┌────────────────────────────────────┐
│ Runtime Overview                   │
├────────────────────────────────────┤
│ Active Executions      12          │
│ Avg Latency            4.2s        │
│ Tool Failures          3           │
│ Token Usage            2.1M        │
│ Replay Available       182         │
└────────────────────────────────────┘
```

---

# Runtime Visualization

Executionをクリックすると:

```text
┌ Prompt ──────────────┐
└─────────┬────────────┘
          ▼
┌ Context Loaded ──────┐
└─────────┬────────────┘
          ▼
┌ Tool Calls ──────────┐
└─────────┬────────────┘
          ▼
┌ Model Generate ──────┐
└─────────┬────────────┘
          ▼
┌ Output Diff ─────────┐
└──────────────────────┘
```

を可視化。

---

# Runtime Timeline

リアルタイムイベント表示:

```text
10:01 CONTEXT_LOADED
10:02 TOOL_CALLED
10:03 MODEL_GENERATING
10:06 OUTPUT_RECEIVED
```

---

# Context Graph

AIへ流入したContextを可視化。

例:

```text
security.md
↓
AuthService.php
↓
Output
```

「どのContextがOutputへ影響したか」
辿れるようにする。

---

# Tool Call Graph

MCP Tool呼び出しをグラフ表示。

例:

```text
github.search
↓
filesystem.read
↓
postgres.query
↓
sentry.get_issue
```

---

# Replay Visualization

Execution をタイムライン再生可能にする。

```text
▶ Replay Execution #182
```

以下を順番に再生:

1. Context読込
2. Tool Call
3. Model Generate
4. Output

---

# Runtime Heatmap

以下を可視化:

- token usage
- tool latency
- context size
- failure location

---

# Runtime Suggestions

AI Runtime を分析し、
改善提案を生成してください。

Dashboard表示:

```text
Runtime Suggestions
────────────────────
⚠ Context too large
⚠ Tool retry loop detected
⚠ Hallucination risk
✓ Replay reproducible
```

---

# Runtime Feedback Engine

Execution 完了後、
Runtime を自動分析してください。

分析対象:

- Context
- Tool Call
- Runtime Event
- Token Usage
- Output
- Eval

---

# 必須フィードバック

# 1. Context Overload Detection

例:

```text
42 files loaded
182k tokens
```

提案:

```text
Context量が過剰です。
Auth関連ファイルへ限定してください。
```

---

# 2. Duplicate Tool Detection

例:

```text
github.search
github.search
github.search
```

提案:

```text
同一Tool Callが多発しています。
結果キャッシュを推奨します。
```

---

# 3. Agent Loop Detection

例:

```text
search → read → search → read
```

提案:

```text
Agent loop detected.
```

---

# 4. Hallucination Risk Detection

例:

- Tool根拠無し
- Context不足
- unsupported claim

提案:

```text
根拠となるContextが不足しています。
```

---

# 5. Prompt Quality Feedback

例:

```text
レビューしてください
```

提案:

```text
OWASP / performance / readability
など観点指定を推奨します。
```

---

# 6. Runtime Failure Analysis

例:

```text
filesystem.read timeout
```

提案:

```text
Tool timeoutがExecution失敗原因の可能性。
```

---

# 7. Cost Optimization

提案:

```text
このRuntimeは Sonnet でも十分な可能性があります。
```

---

# MCP対応

Claude Desktop / Claude Code と連携可能にしてください。

---

# MCP構成

```text
api/
├ mcp/
│  ├ server/
│  ├ tools/
│  ├ schemas/
│  ├ handlers/
│  └ transports/
```

---

# MCP Transport

対応:

- stdio
- SSE
- HTTP

---

# MCP Tool

以下実装:

- get_execution
- search_executions
- replay_execution
- get_runtime_timeline
- get_tool_calls
- get_context_snapshot
- compare_executions
- get_runtime_graph
- stream_runtime_events

---

# API

REST + WebSocket。

```text
GET    /executions
GET    /executions/{id}
GET    /runtime-events/{execution_id}
GET    /tool-calls/{execution_id}
GET    /feedbacks/{execution_id}
POST   /replay/{execution_id}
WS     /runtime/stream
```

---

# DBテーブル

作成:

- prompts
- executions
- runtime_events
- tool_calls
- context_snapshots
- execution_outputs
- eval_results
- runtime_feedbacks
- replay_sessions
- execution_comparisons

---

# runtime_feedbacks

項目:

- id
- execution_id
- feedback_type
- severity
- title
- description
- suggestion
- metadata
- created_at

---

# Visualization最重要

以下必須:

- Runtime Timeline
- Context Graph
- Tool Call Graph
- Replay Visualization
- Runtime Heatmap
- Failure Highlight
- Runtime Suggestions
- Execution Compare

---

# ドキュメント

以下作成:

```text
docs/
├ architecture/
│  ├ runtime-flow.md
│  ├ event-system.md
│  ├ visualization-system.md
│  ├ replay-system.md
│  ├ feedback-engine.md
│  ├ mcp-system.md
│  ├ websocket-events.md
│  └ db-schema.md
```

---

# 実装順序

以下順で段階実装:

1. DB
2. Backend Core
3. Runtime Event System
4. WebSocket Stream
5. MCP Integration
6. Frontend Dashboard
7. Runtime Visualization
8. Replay
9. Feedback Engine
10. Embedding Search
11. Eval
12. UI改善

---

# Claude Code向け重要ルール

## 毎回巨大コードを再出力しない

変更ファイルのみ。

---

## Context節約

小さな単位で実装。

---

## 局所理解可能性重視

Claude Code が:
「このファイルは何責務か」
すぐ理解できる構造にする。

---

# 出力順序

以下順番で出力:

1. システム全体アーキテクチャ
2. ディレクトリ構成
3. docker-compose.yml
4. DB schema
5. Alembic migration
6. Backend Core
7. Runtime Event System
8. WebSocket
9. MCP Integration
10. Frontend Dashboard
11. Runtime Visualization
12. Replay UI
13. Feedback Engine
14. Embedding Search
15. Eval
16. 実行方法
17. 今後の拡張

---

# 重要

省略禁止。

「TODO」「仮実装」「ダミー」禁止。

実際に動作可能なレベルで実装。

最終目標は:

「AI Runtime Observability Platform」

を構築すること。