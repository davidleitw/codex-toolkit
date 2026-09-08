# Codex Toolkit — 交接

## 目前狀態（2026-09-07）

初版已完成並提交：四個 skill（`codex`、`codex-assets`、`codex-visual-review`、`codex-setup`）各自帶 SKILL.md 與一支 bash 腳本；Claude Code 與 Codex 兩邊的 plugin manifest 指向同一份 `skills/`；英文 README 加 README.zh-TW.md 中文版；`assets/header.jpg` 進版圖（由 `codex-assets` 腳本實際生成，兩個變體中選了米白單浪版）。

本輪刻意縮小範圍：只確定 skill 內容、寫 SKILL.md 與必要的輕量腳本、提供 plugin 封裝。沒有 jobs 系統、session 續接、MCP、瀏覽器自動化、Node runner、JSON schema 檔、自動化測試。前一版交接裡的這些規劃全部作廢，未來要做時重新評估，不要當成既定契約。

## 檔案配置

```
.claude-plugin/plugin.json, marketplace.json   Claude Code plugin；marketplace source "./"
.codex-plugin/plugin.json                      Codex plugin manifest
.agents/plugins/marketplace.json               Codex marketplace；source local path "./"
skills/<name>/SKILL.md + scripts/<one script>  四個 skill，各自獨立可 symlink 安裝
assets/header.jpg                              README 進版圖
```

每個 skill 目錄自足（自己的腳本、自己的錯誤分類），沒有跨 skill 的共用 lib。錯誤分類那 ~15 行在四支腳本裡重複，是刻意換來的單獨安裝能力。

## 已定案的模型與速度政策（沿用，不變）

- 討論、review（任何規模）、debug、程式追蹤、設計判斷：`gpt-5.6-sol` / `high`。不用 `gpt-5.6-terra`。
- 決策已確定的輕量 implement（含機械修改）：`gpt-5.6-luna` / `max`。
- `codex-assets`、`codex-visual-review` 預設 sol / high（有設計判斷）。
- `gpt-6-astra` 與 fast mode（`-c service_tier="fast"`）各自需要使用者明確指定，互不隱含；不因難度、失敗、繼承設定自動升級。
- 第一個委派送出後，呼叫端提醒一次可選 fast；非阻塞、不重送。
- 對話中已授權的設定持續沿用。

腳本層的落實：`run-codex.sh` 強制 `--model` 與 `--effort`（缺一即 `invalid_arguments`）；三支委派腳本明確拒絕 `gpt-5.6-terra`；四支腳本每次執行都帶 `-c service_tier="default"`，只有 `--fast` 才改成 `fast`。實際環境的全域 config 是 `model = "gpt-6-astra"`，這條強制是有意義的。CLI `-c` 覆寫優先於 profile、project、user、system 各層 config，所以這三個值不會被任何一層改掉（sol high review 查過官方 config precedence 文件）。

## sol high 方案 review（2026-09-07，`codex discuss`，gpt-5.6-sol / high）

已採納：終止 marker 一律走 stdout（原本失敗走 stderr）；腳本拒絕 terra；`--staging-root` 與資產路徑禁止空白／控制字元（marker 欄位以空白分隔）；`preview.html` 對模型文字做 HTML escape、路徑 URL encode；PNG 透明判斷加 tRNS chunk；比對宣告 format 與檔頭（`format_mismatch`）；visual-review 驗證四個段落齊全；setup 的 config 檢查改稱 base user config；SKILL.md 收緊 marker 語意（OK = CLI 回傳成功且結構檢查通過，不代表驗收）、「不自動重試，只允許輸入或範圍改變的另一次請求」、背景執行改用 harness 機制而非 shell `&`。

未採納（附理由）：鎖 `-c model_provider="openai"`（會弄壞用 Azure 等自訂 provider 的人；模型名已明確帶入）；python3 改硬相依並取代 jq（改寫成本高於收益，缺 python3 時尺寸欄位為 null 已在 SKILL.md 標明）；移除 `smoke-test --imagegen`（那是唯一能確認生圖真的可用的方法，且只在明確要求時跑）；`--ignore-user-config`（sol 自己也不建議，會丟掉 trust、hooks、provider 設定）。

## 已驗證 / 未驗證

已驗證（本機，2026-09-07）：
- `bash -n` 四支腳本通過；缺 `--model`、terra、錯誤 mode、compare 缺 `--reference`、repo 不存在、staging root 含空白等參數路徑正確回 `kind=invalid_arguments`。
- 圖片檔頭解析單獨測過：JPEG、RGB PNG、indexed PNG + tRNS（alpha=true）。
- `claude plugin validate`（marketplace、plugin.json、skills 目錄、`--strict`）通過；Codex `validate_plugin.py` 通過。
- `codex plugin marketplace add <local path>` 可辨識 plugin；`codex plugin add codex-toolkit@codex-toolkit` 可安裝到 `~/.codex/plugins/cache/`；已移除。
- `codex-setup.sh doctor` 實跑。
- `run-codex-assets.sh` 實際生成進版圖：兩張 1672x941 PNG，manifest 由腳本補上 sha256/bytes/寬高/alpha，`CODEX_ASSETS_READY status=complete`（在加入 format_mismatch 與 HTML escape 之前跑的，那段後處理只做過離線片段測試）。
- `run-codex.sh discuss` 實跑一次（sol high 方案 review，marker `CODEX_DELEGATION_OK`）。

未驗證：
- 從 GitHub 安裝（push 前無法試）；Claude Code 端的實際 `plugin install`（只跑過 validate）。
- `run-codex.sh` 三種 mode 在真實任務上的完整流程；`--fast` 實際被 CLI/帳號接受與否。
- `run-codex-visual-review.sh` 的真實跑法（只驗過參數路徑）。
- `codex-setup.sh smoke-test`（會耗額度，沒跑）。
- partial manifest、越界路徑、format_mismatch 等失敗分支。
- Codex 在 `--sandbox read-only` 下透過 `--output-last-message` 寫報告（CLI 自身寫檔，預期不受 sandbox 限制，未實測）。

## 下一步建議

1. 真實任務各跑一次三個 Codex 委派 skill，修 SKILL.md 中 agent 誤讀的地方。
2. 若需要 follow-up 續接，再評估 `codex exec resume` 與去掉 `--ephemeral` 的取捨；不要一開始就做完整 jobs 系統。
3. 公開 release、marketplace 上架、license 選擇留待有實際使用回饋後處理。

## 參考

- Codex config reference（`service_tier`）：https://learn.chatgpt.com/docs/config-file/config-reference
- Codex plugin manifest 規格：`~/.codex/skills/.system/plugin-creator/references/plugin-json-spec.md`
- 參考過但未借用程式碼的專案：openai/codex-plugin-cc、KingGyuSuh/codex-image-in-cc、Sateezg/codex-bridge、thenamangoyal/codex-vision、kununu/agent-bridge、vercel-labs/skills。
