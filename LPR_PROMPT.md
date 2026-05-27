````markdown id="z8t2qv"
# 指示

あなたはシニアソフトウェアアーキテクト兼フルスタックエンジニアです。

Claude Code / Claude Desktop / MCP と連携可能な、
ローカル完結型「AI Runtime / Agent Observability Platform」を実装してください。

このプロダクトの目的は、
AI Runtime の内部状態を可視化し、
AI実行を「監視・追跡・再現」可能にすることです。

単なる Prompt 保存ツールは禁止。

最重要なのは:

- Runtime Visualization
- Execution Trace
- Context Flow
- Tool Call Flow
- Replay
- Observability

です。

---

# プロダクトコンセプト

本プロダクトは、

「AI版 Datadog / Sentry / OpenTelemetry / Chrome DevTools」

を目指します。

目的は:

- AIが何を読んだか
- 何のToolを呼んだか
- なぜその出力になったか
- どこで失敗したか

を可視化すること。

---

# 最重要要件

# Runtime Visualization を最優先してください

保存は目的ではなく、
Visualization のための手段です。

以下をリアルタイム可視化してください:

- Runtime Timeline
- Context Flow
- Tool Call Graph
- Event Stream
- Token Usage
- Output Diff
- Replay
- Execution Graph

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
- VueFlow (必須)
- ECharts または Recharts

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
````

docker-compose で:

* web
* api
* db

を起動。

---

# pgvector

必ず有効化:

```sql
CREATE EXTENSION vector;
```

---

# Claude Code向け重要ルール

Claude Code のコンテキスト効率を最優先してください。

---

# コンテキスト最適化

## 巨大ファイル禁止

1ファイル300行以内。

巨大:

* service
* component
* store
* router

禁止。

---

# 責務分離

backend:

```text
api/
├ domain/
├ application/
├ infrastructure/
├ presentation/
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
```

---

# 明確な命名

悪い例:

```text
utils.ts
helpers.py
service.py
```

良い例:

```text
runtime_event_publisher.py
execution_trace_repository.py
tool_call_graph_builder.ts
```

---

# 過剰抽象化禁止

以下禁止:

* generic manager
* abstract repository
* base service乱用

YAGNI重視。

---

# Event中心設計

以下イベントをコア概念にしてください:

* EXECUTION_STARTED
* CONTEXT_LOADED
* TOOL_CALLED
* TOOL_COMPLETED
* MODEL_GENERATING
* OUTPUT_RECEIVED
* EVAL_COMPLETED
* EXECUTION_FINISHED

すべて:

* DB保存
* WebSocket配信
* Replay利用

可能にする。

---

# プロダクトUI

IDE + Monitoring Dashboard + DevTools の融合。

---

# Dashboard UI

トップページに:

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

# Execution Visualizer

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

# Context Flow Visualization

AIへ流入したContextを可視化。

例:

```text
AuthService.ts
security.md
incident-442.md
```

どのContextがOutputへ影響したか
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
sentry.get_error
```

---

# Replay UI

Executionを再生可能にする。

```text
▶ Replay Execution #182
```

実行をタイムライン再生。

---

# Output Diff Viewer

コード差分表示。

```diff
- if (user)
+ if (user && user.isActive)
```

---

# Runtime Heatmap

以下を可視化:

* token usage
* latency
* tool duration
* failure point

---

# Execution Compare

以下比較:

* Claude vs GPT
* Prompt A vs Prompt B

比較項目:

* token
* latency
* tool count
* eval score

---

# 保存対象

# executions

* model
* provider
* token_usage
* latency
* status

---

# runtime_events

* event_type
* payload
* timestamp

---

# tool_calls

* tool_name
* input_json
* output_json
* duration_ms
* success

---

# context_snapshots

* file_path
* content
* embedding
* metadata

---

# eval_results

* score
* hallucination_detected
* feedback

---

# 機能要件

# 1. Prompt Registry

Prompt保存。

---

# 2. Runtime Trace

AI実行全体保存。

---

# 3. Tool Call Trace

MCP Tool実行保存。

---

# 4. Context Snapshot

AIへ渡したContext保存。

---

# 5. Runtime Event Stream

WebSocketでリアルタイム配信。

---

# 6. Replay

Execution再現。

---

# 7. Embedding Search

pgvector利用。

---

# 8. Eval

品質評価保存。

---

# API

REST + WebSocket。

```text
GET    /executions
GET    /executions/{id}
GET    /runtime-events/{execution_id}
GET    /tool-calls/{execution_id}
POST   /replay/{execution_id}
WS     /runtime/stream
```

---

# WebSocket

リアルタイム更新必須。

以下をstream:

* runtime event
* token stream
* tool status
* execution update

---

# Visualization最重要

以下を絶対実装:

* Runtime Timeline
* Context Graph
* Tool Call Graph
* Execution Replay
* Output Diff
* Failure Highlight
* Runtime Dashboard

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
│  ├ db-schema.md
│  └ websocket-events.md
```

---

# 実装順序

以下順で段階実装:

1. DB
2. Backend Core
3. Runtime Event System
4. WebSocket Stream
5. Frontend Dashboard
6. Runtime Visualization
7. Replay
8. Embedding Search
9. Eval
10. UI改善

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
9. Frontend Dashboard
10. Runtime Visualization
11. Replay UI
12. Embedding Search
13. Eval
14. 実行方法
15. 今後の拡張

---

# 重要

省略禁止。

「TODO」「仮実装」「ダミー」禁止。

実際に動作可能なレベルで実装。

最終目標は:

「AI Runtime / Agent Observability Dashboard」

を構築すること。

```
```
