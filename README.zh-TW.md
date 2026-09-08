# Codex Toolkit

[English](README.md) | 繁體中文

![Codex Toolkit](assets/header.jpg)

在你原本的 coding agent（Claude Code、Codex CLI，或任何看得懂 agent skills 的工具）裡，把工作丟給本機的 Codex：找它討論、請它 review 或改程式、做圖、看截圖。

這是社群製作的 toolkit，跟 OpenAI、Anthropic 都沒有關係，也不是官方套件。

## 四個 skill

| skill | 什麼時候會用到 | 你會拿到什麼 |
|---|---|---|
| `codex` | 想聽第二意見、想讓 Codex review 還沒 commit 的修改，或把一件已經講清楚的修改交給 Codex 做 | Codex 的分析、review findings 或 diff。你的 agent 會自己核對過再回報 |
| `codex-assets` | 需要插圖、背景、mockup、icon、一整組同風格的素材，或想修改既有圖片 | 暫存目錄裡的檔案、`manifest.json`（尺寸、大小、checksum 由程式讀檔計算）、`preview.html`（可切換深淺背景檢查透明圖） |
| `codex-visual-review` | 手上有 UI 截圖想被檢查，或想比對設計稿和實作畫面 | `report.md`：每張圖的問題位置、影響、修改建議，以及截圖看不出來、需要人工確認的項目 |
| `codex-setup` | 第一次安裝，或 Codex 跑不起來 | 逐項檢查報告（CLI、登入、內建生圖 skill、jq/python3 等）。只報告，不改你的設定 |

分工原則：程式的事找 `codex`，做圖找 `codex-assets`，看圖找 `codex-visual-review`，環境有問題找 `codex-setup`。截圖 review 發現的問題要改程式時，會回到 `codex` 的 implement 模式；素材要修改時，會用 `codex-assets` 的 revise 模式產生新版本，原檔不動。

## 事前需求

- Codex CLI（`npm install -g @openai/codex`），並已執行過 `codex login`。本 toolkit 以 codex-cli 0.153.4 開發。
- `jq`（`codex-assets` 需要）；`sha256sum` 或 `shasum`。
- `python3`：用來讀圖片的寬高與透明通道。沒有也能跑，這幾個欄位會是 `null`。
- 做圖靠 Codex 內建的 imagegen skill（隨 CLI 提供，位於 `~/.codex/skills/.system/imagegen`），不需要另外的 API key。

裝好後可以先讓 agent 跑 `codex-setup` 的 doctor 檢查。

## 安裝

四個 skill 都在 `skills/` 底下，Claude Code 和 Codex 的 plugin 讀的是同一份。

### Claude Code

```bash
claude plugin marketplace add davidleitw/codex-toolkit
claude plugin install codex-toolkit@codex-toolkit
```

本機 clone 的話，第一行改成 `claude plugin marketplace add /path/to/codex-toolkit`。

移除：

```bash
claude plugin uninstall codex-toolkit
claude plugin marketplace remove codex-toolkit
```

### Codex

```bash
codex plugin marketplace add davidleitw/codex-toolkit
codex plugin add codex-toolkit@codex-toolkit
```

本機 clone 的話，第一行改成 `codex plugin marketplace add /path/to/codex-toolkit`。

移除：

```bash
codex plugin remove codex-toolkit@codex-toolkit
codex plugin marketplace remove codex-toolkit
```

### 不用 plugin，直接放 skill

每個 skill 目錄自帶自己的腳本，可以只裝需要的那幾個：

```bash
git clone https://github.com/davidleitw/codex-toolkit.git
# Claude Code
ln -s "$PWD/codex-toolkit/skills/codex" ~/.claude/skills/codex
# Codex
ln -s "$PWD/codex-toolkit/skills/codex" ~/.codex/skills/codex
```

其他看得懂 agent skills 的工具，通常會讀 `~/.agents/skills/`，同樣用 symlink 放進去即可。

## 怎麼用

用自然語言講就好，agent 會自己挑 skill：

- 「找 Codex 討論一下這個 retry 機制該放在哪一層，先不要改程式。」
- 「請 Codex review 我還沒 commit 的修改，重點看錯誤處理。」
- 「這個 rename 已經確定了，交給 Codex 做，做完跑一次測試。」
- 「用 Codex 幫我做一張 README 的封面圖，日式版畫風，要有終端機的元素。」
- 「這是我截的設定頁畫面，請 Codex 看一下排版有沒有問題。」
- 「Codex 好像跑不起來，幫我檢查一下環境。」

## 模型與速度規則

所有腳本每次執行都明確帶上模型、推理強度（effort）與服務等級（service tier），不會繼承你 `~/.codex/config.toml` 裡的預設值。這是刻意的：全域設定即使寫了 GPT-6 或 fast，也不會在你沒開口的情況下被用到。

| 工作 | 模型 / effort |
|---|---|
| 討論、review（不論大小）、debug、程式追蹤、任何需要設計判斷的工作 | `gpt-5.6-sol` / `high` |
| 決策已確定、範圍明確的輕量修改（包含機械式修改） | `gpt-5.6-luna` / `max` |
| 做圖、看截圖 | `gpt-5.6-sol` / `high` |

- 不會使用 `gpt-5.6-terra`。
- `gpt-6-astra` 只在你明確說要用 GPT-6 / Astra 時才會用。任務很難、上一次失敗、或設定檔寫著它，都不算授權。
- fast mode（Codex 的 `service_tier="fast"`）另外需要你明確說要。要 GPT-6 不等於要 fast，反過來也一樣。
- 同一段對話裡授權過的設定會延用，不會每次重問。
- 第一次委派送出後，agent 會提醒你一次：「若想加快後續 Codex 工作，可以說『接下來用 fast mode』；可能增加額度消耗。」只提醒一次，不會等你回答，也不會為了換速度重送任務。

## 結果放在哪

| skill | 位置 |
|---|---|
| `codex` | 直接印在 agent 的執行輸出裡。最後一行是 `CODEX_DELEGATION_OK ...` 或 `CODEX_DELEGATION_FAILED kind=...`，agent 以這一行判斷成敗，不看 exit code |
| `codex-assets` | `$TMPDIR/codex-toolkit/assets/job-XXXXXX/`（`TMPDIR` 沒設就是 `/tmp`）。裡面有產出的檔案、`manifest.json`、`preview.html`、`request.txt`、`codex-stderr.log` |
| `codex-visual-review` | `$TMPDIR/codex-toolkit/visual-review/job-XXXXXX/report.md` |
| `codex-setup` | 直接印在執行輸出裡 |

Codex 產出的素材不會自己跑進你的 repo。agent 看過 manifest 和圖之後，才把接受的檔案複製到專案的 source assets 目錄。

## 目前狀態

已完成：四個 skill 的 SKILL.md 與腳本、Claude Code 與 Codex 的 plugin manifest、本份 README、進版圖。

已檢查過的事：腳本語法與參數錯誤路徑、`claude plugin validate` 與 Codex plugin validator 都通過、本機 `codex plugin marketplace add` + `codex plugin add` 能安裝並移除、`codex-setup doctor` 實跑、進版圖由 `codex-assets` 腳本實際生成。

還沒做的事：沒有自動化測試；沒有在真實任務上完整驗證四個 skill 的每條路徑；從 GitHub 安裝的指令（`marketplace add davidleitw/codex-toolkit`）在 push 之前沒辦法試。

規劃中（本版刻意不做）：任務記錄與 session 續接、瀏覽器自動截圖、MCP 介面、`codex-setup` 的自動修正。
