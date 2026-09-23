---
name: natural-zhtw
description: "Write or review natural Traditional Chinese for Taiwan (zh-TW). Use for technical writing, PR/MR descriptions, issues, comments, documentation, workplace messages, UI copy, explanations, and English-to-Chinese translation. Also use when checking whether wording sounds translated, overly formal, Mainland-influenced, or AI-written."
user-invocable: false
---

# Natural Taiwan Chinese

Write zh-TW the way a Taiwanese person would naturally write it in the given context.

Do not translate English sentence structure directly. Keep the meaning, facts, technical behavior, scope, certainty, identifiers, filenames, official terms, and quoted text, but rewrite the sentence freely when needed.

Natural wording matters more than matching the source sentence shape.

## Tone

Use clear, direct, professional Taiwanese Chinese.

For technical writing, sound like an engineer explaining something to another engineer. Do not make it sound like a government document, academic paper, or translated product documentation unless the context actually requires that style.

Prefer normal words such as:

- `這次` over `本次`
- `如果` over `若`
- `在` over `於`
- `是` over `屬`
- `問題` / `錯誤` over `勘誤`

These are not hard bans. Use the more formal wording when it genuinely fits.

## Taiwan wording

Prefer Taiwan usage:

`程式`、`專案`、`元件`、`設定`、`呼叫 API`、`回傳`、`伺服器`、`影片`、`建立`、`新增`、`資料`

Do not replace official names, project terms, field names, identifiers, filenames, UI strings, or quoted text.

## English technical terms

Keep English technical terms when Taiwanese developers would naturally use them that way.

Examples include `API`, `DOM`, `rebase`, `worktree`, `hook`, `runtime`, `session`, `client`, `scope`, `discovery path`, `tsconfig`, `PM`, `FE`, `BE`.

But do not keep an English word just because the source is technical.

For example:

- `多個應用程式 instance` → `多個同時執行的應用程式`
- `substantial task` → `較大型的任務`
- `auditability` → `可稽核性`
- `Landing page` → `首頁` or `README 首頁`, depending on context

A good rule:

> If a Taiwanese developer would probably write the sentence in Chinese from scratch, write it in Chinese.

Keep the English only when it carries a useful technical distinction or is the natural term people actually use.

## Avoid translationese

Watch for:

- English sentence order copied too closely
- long chains of `的`
- unnecessary pronouns
- passive constructions that sound unnatural in Chinese
- abstract noun phrases where a direct verb is simpler
- awkward Chinese-English hybrids
- wording that is technically correct but not something people would actually say

Rewrite freely.

For example:

`continuity 紀錄保留圍繞這個狀態的工作脈絡。`

Prefer:

`continuity 紀錄保留 Git 沒有記錄的任務脈絡。`

`任務流程是 substantial、平行或需要隔離的工作才明確啟動的 opt-in。`

Prefer:

`這套工作流程需要明確啟動，主要用在較大型、需要平行處理或需要隔離的任務。`

## Final check

Before returning zh-TW prose, read it once and ask:

1. 這句話台灣人真的會這樣寫嗎？
2. 看得出英文原句的結構嗎？
3. 有沒有不必要的英文詞留下來？
4. 技術意思、範圍和限制有沒有被改掉？
5. 如果我是台灣工程師，會不會用更直接的方式寫？
