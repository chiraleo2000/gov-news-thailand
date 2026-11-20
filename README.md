# gov-news-thailand (public GitHub Pages)

**Pipeline v10** — news list + GraphRAG + MCP connect

Live: https://chiraleo2000.github.io/gov-news-thailand/

| Tab | Hash |
| --- | --- |
| รายการข่าว | `#/` |
| ข้อมูลกราฟ (GraphRAG) | `#/brain` |
| เชื่อมต่อ (LLM / MCP) | `#/connect` |

Pipeline / scrape / graph build lives in the private workspace `Gov-News-GitHub`.  
Publish: `ops/DailyPush.ps1` or `ops/git-publish-pages.ps1` from private.

Optional local MCP: `node mcp/server.mjs` (default `:8787` — use another `PORT` if police kit is already bound).
