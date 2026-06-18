# english-coach 混用本地文法（Harper）+ LLM 語感 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 english-coach 先用本地 Harper 擋文法錯（有錯就 gate 住、不呼叫 LLM），文法乾淨才讓 LLM 做純 idiom，兼顧速度、隱私與「像美國人」。

**Architecture:** `check.sh` 維持薄派工不阻塞；`worker.sh` 依四態（hard_tip / verified_clean / hard_unrenderable / unavailable）決定走本地行、idiom-only LLM、不出網路、或 combined LLM。新增 `lib/grammar.sh` 封裝 Harper 呼叫＋解析＋渲染；Harper 為可選（`EC_GRAMMAR=auto|harper|off`），沒裝就退回今天的 combined。

**Tech Stack:** bash、jq、perl（僅 Insert/Remove 渲染需要）、Harper CLI（`harper-cli`，離線）。測試用純 bash 斷言＋假 harper。

**Branch:** 已在 `english-coach-hybrid-grammar`（spec 已 commit 於此）。全程在此分支實作。

**Spec:** `docs/superpowers/specs/2026-06-18-english-coach-hybrid-grammar-design.md`

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `plugins/english-coach/lib/config.sh` | 改 | 加 `EC_GRAMMAR`/`EC_HARPER_BIN`/`EC_HARPER_DIALECT`/`EC_HARPER_GATE` |
| `plugins/english-coach/lib/grammar.sh` | 新增 | `ec_grammar_resolve`、`ec_grammar_candidates`、`ec__sug_quoted`、`ec__reason`、`ec_sanitize_local`、`ec_map_lint`、`ec__render_edit`、`ec_grammar_check`、`EC_HARD_KINDS` |
| `plugins/english-coach/lib/worker.sh` | 改 | source grammar.sh；`ec_rubric` 收 template 參數；providers/`ec_run_provider` 帶 template；`ec_worker_main` 四態狀態機＋logging |
| `plugins/english-coach/lib/prompt-template-idiom.txt` | 新增 | idiom-only rubric |
| `plugins/english-coach/tests/_assert.sh` | 新增 | bash 斷言小工具 |
| `plugins/english-coach/tests/fake-harper` | 新增 | harper-cli 測試替身 |
| `plugins/english-coach/tests/run.sh` | 新增 | 跑所有 `tests/test-*.sh` |
| `plugins/english-coach/tests/test-grammar.sh` | 新增 | grammar.sh 單元測試 |
| `plugins/english-coach/tests/test-worker.sh` | 新增 | worker 路由測試（stub provider） |
| `plugins/english-coach/README.md` | 改 | grammar 層、安裝、設定、隱私 |
| `plugins/english-coach/skills/setup/SKILL.md` | 改 | 提一句 Harper 選配 |
| `plugins/english-coach/.claude-plugin/plugin.json` | 改 | `0.1.0` → `0.2.0` |
| `.claude-plugin/marketplace.json` | 改 | english-coach `0.1.0` → `0.2.0` |

---

## Task 1: 設定旋鈕（config.sh）

**Files:**
- Modify: `plugins/english-coach/lib/config.sh`（在 `EC_OPENAI_MAX_TOKENS` 區塊之後、`# Derived runtime dirs` 之前插入）

- [ ] **Step 1: 加入四個 grammar 旋鈕**

在 `plugins/english-coach/lib/config.sh` 的這一行之後：

```sh
: "${EC_OPENAI_MAX_TOKENS:=512}"   # generous: reasoning models (Groq gpt-oss/qwen3) spend tokens on hidden reasoning
```

新增（接在該行下方的註解區塊後、`# Derived runtime dirs` 之前）：

```sh
# Local grammar pre-pass (§3/§5 of the spec). One of: auto | harper | off
#   auto   = use Harper if $EC_HARPER_BIN is on PATH, else fall back to combined LLM (today)
#   harper = force Harper (if missing: log + fall back), off = never use Harper
: "${EC_GRAMMAR:=auto}"
: "${EC_HARPER_BIN:=harper-cli}"   # brew installs the one-shot CLI as `harper-cli` (NOT `harper`)
: "${EC_HARPER_DIALECT:=us}"       # American English — matches the coach's "sound like an American" goal
: "${EC_HARPER_GATE:=errors}"      # errors | any — which lint kinds gate the LLM
```

- [ ] **Step 2: 驗證預設值載入**

Run:
```bash
EC_HOME=$(mktemp -d) bash -c '. plugins/english-coach/lib/config.sh; printf "%s|%s|%s|%s\n" "$EC_GRAMMAR" "$EC_HARPER_BIN" "$EC_HARPER_DIALECT" "$EC_HARPER_GATE"'
```
Expected: `auto|harper-cli|us|errors`

- [ ] **Step 3: Commit**

```bash
git add plugins/english-coach/lib/config.sh
git commit -m "feat(english-coach): add EC_GRAMMAR/EC_HARPER_* config knobs"
```

---

## Task 2: 測試骨架（assert + 假 harper + runner）

**Files:**
- Create: `plugins/english-coach/tests/_assert.sh`
- Create: `plugins/english-coach/tests/fake-harper`
- Create: `plugins/english-coach/tests/run.sh`

- [ ] **Step 1: 寫斷言小工具** — `plugins/english-coach/tests/_assert.sh`

```sh
# Minimal bash assertion helpers. Source after defining the code under test.
EC_TPASS=0; EC_TFAIL=0
assert_eq() { # $1=desc $2=expected $3=actual
  if [ "$2" = "$3" ]; then EC_TPASS=$((EC_TPASS+1));
  else EC_TFAIL=$((EC_TFAIL+1)); printf 'FAIL - %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
assert_rc() { # $1=desc $2=expected_rc $3=actual_rc
  if [ "$2" = "$3" ]; then EC_TPASS=$((EC_TPASS+1));
  else EC_TFAIL=$((EC_TFAIL+1)); printf 'FAIL - %s\n  expected rc:%s actual rc:%s\n' "$1" "$2" "$3"; fi
}
ec_tests_done() { printf '%s: %d passed, %d failed\n' "${0##*/}" "$EC_TPASS" "$EC_TFAIL"; [ "$EC_TFAIL" -eq 0 ]; }
```

- [ ] **Step 2: 寫 harper 測試替身** — `plugins/english-coach/tests/fake-harper`

```sh
#!/usr/bin/env bash
# Test double for `harper-cli`. Ignores all args; emits the JSON in $FAKE_HARPER_OUT
# and exits with $FAKE_HARPER_RC (default 0). Mirrors real harper: it may print valid
# JSON yet exit non-zero when lints are found.
cat "${FAKE_HARPER_OUT:?FAKE_HARPER_OUT unset}"
exit "${FAKE_HARPER_RC:-0}"
```

Run: `chmod +x plugins/english-coach/tests/fake-harper`

- [ ] **Step 3: 寫 runner** — `plugins/english-coach/tests/run.sh`

```sh
#!/usr/bin/env bash
# Run every tests/test-*.sh; non-zero exit if any file reports a failure.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$here"/test-*.sh; do
  [ -e "$t" ] || continue
  echo "== ${t##*/} =="
  bash "$t" || fail=1
done
exit "$fail"
```

Run: `chmod +x plugins/english-coach/tests/run.sh`

- [ ] **Step 4: 暫無 test-*.sh，runner 應乾淨通過**

Run: `bash plugins/english-coach/tests/run.sh; echo rc=$?`
Expected: 沒有 `==` 區段、`rc=0`

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/tests/_assert.sh plugins/english-coach/tests/fake-harper plugins/english-coach/tests/run.sh
git commit -m "test(english-coach): add bash assert harness + fake harper"
```

---

## Task 3: `ec_grammar_resolve`（grammar.sh 起手）

**Files:**
- Create: `plugins/english-coach/lib/grammar.sh`
- Create: `plugins/english-coach/tests/test-grammar.sh`

- [ ] **Step 1: 寫失敗測試** — `plugins/english-coach/tests/test-grammar.sh`

```sh
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$(cd "$HERE/../lib" && pwd)"
export EC_HOME="$(mktemp -d)"
. "$LIB/config.sh"
. "$LIB/lib.sh"
. "$LIB/grammar.sh"
. "$HERE/_assert.sh"

# --- ec_grammar_resolve ---
EC_GRAMMAR=off  assert_eq "off -> off" "off" "$(ec_grammar_resolve)"
EC_GRAMMAR=auto EC_HARPER_BIN="$HERE/fake-harper" assert_eq "auto + present -> harper" "harper" "$(ec_grammar_resolve)"
EC_GRAMMAR=auto EC_HARPER_BIN="ec-no-such-bin-xyz" assert_eq "auto + absent -> off" "off" "$(ec_grammar_resolve)"
EC_GRAMMAR=harper EC_HARPER_BIN="ec-no-such-bin-xyz" assert_eq "harper + absent -> off" "off" "$(ec_grammar_resolve)"
EC_GRAMMAR=harper EC_HARPER_BIN="$HERE/fake-harper" assert_eq "harper + present -> harper" "harper" "$(ec_grammar_resolve)"

ec_tests_done
```

- [ ] **Step 2: 跑測試確認失敗** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 因 `grammar.sh` 不存在，`source` 失敗（找不到檔案）。

- [ ] **Step 3: 建 grammar.sh 並實作 resolve**

`plugins/english-coach/lib/grammar.sh`：

```sh
# english-coach: local grammar pre-pass via Harper (offline). Sourced after config.sh.
#
# Harper CLI (pinned expectation: harper-cli v2.x, 2026-06):
#  - `harper-cli lint --format json` prints a JSON array to stdout, THEN exits
#    non-zero when any lint is found (`bail!("Lints were found")`). So exit code
#    is NOT a success signal — judge success by parseable JSON on stdout.
#  - lint fields: {rule,kind,span{char_start,char_end} (CHAR idx, half-open),
#    message,priority,suggestions[] (Display strings, curly-quoted),matched_text}.
#  - CLI is experimental; parse defensively — any surprise => unavailable.

# kinds that GATE the LLM (everything else is style/idiom -> goes to the LLM).
EC_HARD_KINDS="Spelling Typo Grammar Agreement Capitalization Punctuation Usage Malapropism BoundaryError Eggcorn Nonstandard"

# echoes "harper" or "off"
ec_grammar_resolve() {
  case "${EC_GRAMMAR:-auto}" in
    off) printf 'off' ;;
    harper)
      if command -v "$EC_HARPER_BIN" >/dev/null 2>&1; then printf 'harper'
      else
        [ "${EC_LOG:-0}" = "1" ] && printf '{"grammar":"harper-missing"}\n' >> "$EC_LOG_FILE" 2>/dev/null
        printf 'off'
      fi ;;
    *) # auto
      if command -v "$EC_HARPER_BIN" >/dev/null 2>&1; then printf 'harper'; else printf 'off'; fi ;;
  esac
}
```

- [ ] **Step 4: 跑測試確認通過** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: `test-grammar.sh: 5 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/lib/grammar.sh plugins/english-coach/tests/test-grammar.sh
git commit -m "feat(english-coach): ec_grammar_resolve (auto/harper/off)"
```

---

## Task 4: `ec_grammar_candidates`（kind 過濾＋排序）

把 Harper JSON（stdin）轉成「硬錯誤候選」JSONL（依 `char_start`、`priority` 排序）。schema 不符 → `return 2`（unavailable）。

**Files:**
- Modify: `plugins/english-coach/lib/grammar.sh`（append 函式）
- Modify: `plugins/english-coach/tests/test-grammar.sh`（append 測試）

- [ ] **Step 1: append 失敗測試** — 加到 `tests/test-grammar.sh` 的 `ec_tests_done` 之前：

```sh
# --- ec_grammar_candidates ---
J_TWO='[{"file":"stdin","lint_count":2,"lints":[
  {"rule":"X","kind":"Style","span":{"char_start":1,"char_end":2},"message":"m","priority":5,"suggestions":["Replace with: “a”"],"matched_text":"a"},
  {"rule":"Y","kind":"Spelling","span":{"char_start":9,"char_end":16},"message":"sp?","priority":7,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}
]}]'
# gate=errors -> only the Spelling lint survives
assert_eq "candidates errors-only kind" "Spelling" \
  "$(printf '%s' "$J_TWO" | EC_HARPER_GATE=errors ec_grammar_candidates | jq -r .kind)"
# gate=any -> both, ordered by char_start (Style at 1 first)
assert_eq "candidates any first kind" "Style" \
  "$(printf '%s' "$J_TWO" | EC_HARPER_GATE=any ec_grammar_candidates | head -1 | jq -r .kind)"
# no hard lints -> empty, rc 0
J_STYLE='[{"file":"stdin","lint_count":1,"lints":[{"rule":"X","kind":"Style","span":{"char_start":1,"char_end":2},"message":"m","priority":5,"suggestions":[],"matched_text":"a"}]}]'
assert_eq "candidates none -> empty" "" "$(printf '%s' "$J_STYLE" | EC_HARPER_GATE=errors ec_grammar_candidates)"
printf '%s' "$J_STYLE" | EC_HARPER_GATE=errors ec_grammar_candidates >/dev/null; assert_rc "candidates parsed rc0" 0 $?
# bad shape -> rc 2
printf 'not json' | ec_grammar_candidates >/dev/null 2>&1; assert_rc "candidates bad -> rc2" 2 $?
printf '{"oops":1}' | ec_grammar_candidates >/dev/null 2>&1; assert_rc "candidates wrong-shape -> rc2" 2 $?
```

- [ ] **Step 2: 跑測試確認失敗** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 新增的 candidates 斷言 FAIL（函式未定義）。

- [ ] **Step 3: 實作** — append 到 `lib/grammar.sh`：

```sh
# stdin: harper JSON. stdout: ordered hard-candidate lints as JSONL (compact).
# return 2 iff stdout is not the expected harper shape (array of {lints:...}).
ec_grammar_candidates() {
  local json
  json="$(cat)"
  printf '%s' "$json" | jq -e \
    '(type=="array") and (length>=1) and (.[0]|type=="object") and (.[0]|has("lints"))' \
    >/dev/null 2>&1 || return 2
  printf '%s' "$json" | jq -c --arg hard "$EC_HARD_KINDS" --arg gate "${EC_HARPER_GATE:-errors}" '
    [.[].lints[]?]
    | (if $gate=="any" then .
       else ($hard|split(" ")) as $hk | map(select(.kind as $k | $hk|index($k)))
       end)
    | sort_by(.span.char_start, .priority) | .[]
  ' 2>/dev/null
}
```

- [ ] **Step 4: 跑測試確認通過** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 全部 passed（含前一批）。

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/lib/grammar.sh plugins/english-coach/tests/test-grammar.sh
git commit -m "feat(english-coach): ec_grammar_candidates (kind gate + ordering)"
```

---

## Task 5: `ec__sug_quoted` + `ec__reason`

`ec__sug_quoted`：從 Display 字串取出引號內 payload（容忍彎引號 U+201C/U+201D 與 ASCII `"`）。
`ec__reason`：決定性推導 reason——優先用 Harper `message`，疑問句／過長則退到具體短語（**絕不裸分類**，對齊 `lib/prompt-template.txt:14`）。

**Files:**
- Modify: `plugins/english-coach/lib/grammar.sh`（append）
- Modify: `plugins/english-coach/tests/test-grammar.sh`（append）

- [ ] **Step 1: append 失敗測試**：

```sh
# --- ec__sug_quoted ---
assert_eq "quoted curly" "believe" "$(ec__sug_quoted 'Replace with: “believe”')"
assert_eq "quoted ascii" "a" "$(ec__sug_quoted 'Insert "a"')"
assert_eq "quoted none" "" "$(ec__sug_quoted 'Remove error')"
# --- ec__reason ---
assert_eq "reason declarative kept" "advice is uncountable" "$(ec__reason 'advice is uncountable' 'Usage')"
assert_eq "reason question -> phrase" "possible misspelling" "$(ec__reason 'Did you mean to spell “x” this way?' 'Spelling')"
assert_eq "reason empty -> phrase" "repeated word" "$(ec__reason '' 'Repetition')"
```

- [ ] **Step 2: 跑測試確認失敗** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 新斷言 FAIL（函式未定義）。

- [ ] **Step 3: 實作** — append 到 `lib/grammar.sh`：

```sh
# Extract the payload between the first/last quote (curly U+201C/U+201D or ASCII ").
ec__sug_quoted() {
  printf '%s' "$1" | perl -CSDA -ne 'print $1 if /[\x{201c}"]([^\x{201c}\x{201d}"]*)[\x{201d}"]/'
}

# Deterministic concrete reason. Prefer Harper message; question-form/overlong/empty
# -> concrete phrase per kind. NEVER a bare bucket like "spelling"/"grammar".
ec__reason() {
  local m="$1" kind="$2"
  m="$(printf '%s' "$m" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$m" in ''|*\?) m="" ;; esac
  if [ -n "$m" ]; then
    [ "$(printf '%s' "$m" | wc -m | tr -d ' ')" -gt 48 ] && m="$(printf '%s' "$m" | cut -c1-48)"
    printf '%s' "$m"; return 0
  fi
  case "$kind" in
    Spelling)       printf 'possible misspelling' ;;
    Typo)           printf 'likely typo' ;;
    Agreement)      printf 'subject–verb agreement' ;;
    Capitalization) printf 'capitalization' ;;
    Punctuation)    printf 'missing/incorrect punctuation' ;;
    Repetition)     printf 'repeated word' ;;
    Usage)          printf 'nonstandard usage' ;;
    Malapropism)    printf 'wrong word' ;;
    BoundaryError)  printf 'word-boundary error' ;;
    Eggcorn)        printf 'misheard phrase' ;;
    Nonstandard)    printf 'nonstandard form' ;;
    Grammar)        printf 'grammar mistake' ;;
    *)              printf '%s' "$(printf '%s' "$kind" | tr 'A-Z' 'a-z')" ;;
  esac
}
```

- [ ] **Step 4: 跑測試確認通過** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 全部 passed。

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/lib/grammar.sh plugins/english-coach/tests/test-grammar.sh
git commit -m "feat(english-coach): ec__sug_quoted + ec__reason (concrete, no bare category)"
```

---

## Task 6: `ec_sanitize_local` + `ec_map_lint`（Replace 路徑）

Replace 是最常見且最可靠的情形：`original=matched_text`、`improved=payload`，**不需 perl**。`ec_sanitize_local` 對本地行做 control-char strip + 長度上限（no-op guard 已在 map_lint）。

**Files:**
- Modify: `plugins/english-coach/lib/grammar.sh`（append）
- Modify: `plugins/english-coach/tests/test-grammar.sh`（append）

- [ ] **Step 1: append 失敗測試**：

```sh
# --- ec_map_lint: Replace ---
TF="$(mktemp)"; printf 'I beleive it' > "$TF"
L_SP='{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"Did you mean to spell “beleive” this way?","priority":63,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}'
assert_eq "map replace spelling" "😇 beleive → believe (possible misspelling)" "$(ec_map_lint "$TF" "$L_SP")"
L_AGR='{"kind":"Agreement","span":{"char_start":0,"char_end":4},"message":"Use the singular verb here.","priority":10,"suggestions":["Replace with: “is”"],"matched_text":"are"}'
assert_eq "map replace agreement (message kept)" "😇 are → is (Use the singular verb here.)" "$(ec_map_lint "$TF" "$L_AGR")"
# no-op (matched == payload) -> unrenderable rc1
L_NOOP='{"kind":"Spelling","span":{"char_start":0,"char_end":1},"message":"x","priority":1,"suggestions":["Replace with: “are”"],"matched_text":"are"}'
ec_map_lint "$TF" "$L_NOOP" >/dev/null; assert_rc "map noop -> rc1" 1 $?
# unknown suggestion -> unrenderable rc1
L_UNK='{"kind":"Spelling","span":{"char_start":0,"char_end":1},"message":"x","priority":1,"suggestions":[],"matched_text":"are"}'
ec_map_lint "$TF" "$L_UNK" >/dev/null; assert_rc "map empty-sug -> rc1" 1 $?
```

- [ ] **Step 2: 跑測試確認失敗** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 新斷言 FAIL。

- [ ] **Step 3: 實作** — append 到 `lib/grammar.sh`：

```sh
# Defense-in-depth for locally-built lines: strip control chars, cap length.
ec_sanitize_local() {
  local line; line="$(cat)"
  line="$(printf '%s' "$line" | LC_ALL=C tr -d '\000-\037\177')"
  local max n; max="${EC_MAX_TIP_LEN:-120}"
  n="$(printf '%s' "$line" | wc -m | tr -d ' ')"
  [ "$n" -gt "$max" ] && line="$(printf '%s' "$line" | cut -c1-"$max")…"
  printf '%s' "$line"
}

# $1=textfile $2=lint(JSON). echo "😇 a → b (reason)" + return 0, or return 1 (unrenderable).
ec_map_lint() {
  local tf="$1" lint="$2" cs ce kind msg matched sug action payload original improved frag
  cs="$(printf '%s' "$lint" | jq -r '.span.char_start // empty')"
  ce="$(printf '%s' "$lint" | jq -r '.span.char_end // empty')"
  kind="$(printf '%s' "$lint" | jq -r '.kind // empty')"
  msg="$(printf '%s' "$lint" | jq -r '.message // empty')"
  matched="$(printf '%s' "$lint" | jq -r '.matched_text // empty')"
  sug="$(printf '%s' "$lint" | jq -r '.suggestions[0] // empty')"
  [ -n "$cs" ] && [ -n "$ce" ] || return 1

  case "$sug" in
    'Replace with: '*) action="replace"; payload="$(ec__sug_quoted "$sug")" ;;
    'Insert '*)        action="insert";  payload="$(ec__sug_quoted "$sug")" ;;
    'Remove'*)         action="remove";  payload="" ;;
    *) return 1 ;;
  esac

  if [ "$action" = "replace" ]; then
    [ -n "$matched" ] && [ -n "$payload" ] || return 1
    original="$matched"; improved="$payload"
  else
    [ "$action" = "insert" ] && [ -z "$payload" ] && return 1
    frag="$(ec__render_edit "$tf" "$cs" "$ce" "$action" "$payload")" || return 1
    original="${frag%%$'\t'*}"; improved="${frag#*$'\t'}"
  fi
  [ -n "$original$improved" ] || return 1
  [ "$original" = "$improved" ] && return 1

  printf '😇 %s → %s (%s)' "$original" "$improved" "$(ec__reason "$msg" "$kind")" | ec_sanitize_local
}
```

> 註：`ec__render_edit` 在 Task 7 定義；本 task 只測 Replace 路徑（不觸發它）。

- [ ] **Step 4: 跑測試確認通過** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 全部 passed。

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/lib/grammar.sh plugins/english-coach/tests/test-grammar.sh
git commit -m "feat(english-coach): ec_map_lint replace path + ec_sanitize_local"
```

---

## Task 7: `ec__render_edit`（perl 字元 diff）+ `ec_map_lint` Insert/Remove

用 char-level 最長共同前/後綴 + 詞邊界擴張，把 Insert/Remove 渲染成自然的 `original → improved`。Insert 會做空白正規化（避免 `havea`），Remove 在 improved 為空時拉前一個詞當語境（`return back → return`）。

**Files:**
- Modify: `plugins/english-coach/lib/grammar.sh`（append）
- Modify: `plugins/english-coach/tests/test-grammar.sh`（append）

- [ ] **Step 1: append 失敗測試**：

```sh
# --- ec_map_lint: Insert / Remove (perl diff) ---
TF2="$(mktemp)"; printf 'I have cat' > "$TF2"
# Insert "a" before "cat": zero-width point at char 7 (after "have "), payload missing space
L_INS='{"kind":"Grammar","span":{"char_start":7,"char_end":7},"message":"Add the article.","priority":20,"suggestions":["Insert “a”"],"matched_text":""}'
assert_eq "map insert article" "😇 cat → a cat (Add the article.)" "$(ec_map_lint "$TF2" "$L_INS")"
TF3="$(mktemp)"; printf 'please return back to me' > "$TF3"
# Remove redundant "back": span covers " back" [13,18)
L_RM='{"kind":"Redundancy","span":{"char_start":13,"char_end":18},"message":"“back” is redundant","priority":30,"suggestions":["Remove error"],"matched_text":" back"}'
# Redundancy is style; for this unit test we call ec_map_lint directly (gate is tested elsewhere)
assert_eq "map remove redundant" "😇 return back → return (“back” is redundant)" "$(ec_map_lint "$TF3" "$L_RM")"
# perl absent OR unrenderable -> rc1 (simulate by an out-of-range span)
L_BAD='{"kind":"Grammar","span":{"char_start":99,"char_end":99},"message":"m","priority":1,"suggestions":["Insert “z”"],"matched_text":""}'
ec_map_lint "$TF2" "$L_BAD" >/dev/null; assert_rc "map oob span -> rc1" 1 $?
```

- [ ] **Step 2: 跑測試確認失敗** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: insert/remove 斷言 FAIL（`ec__render_edit` 未定義 → render 路徑失敗）。

- [ ] **Step 3: 實作** — append 到 `lib/grammar.sh`：

```sh
# $1=textfile $2=char_start $3=char_end $4=action(insert|remove) $5=payload
# echo "original<TAB>improved" + return 0, or return 1.
ec__render_edit() {
  perl -CSDA - "$2" "$3" "$4" "$5" "$1" <<'PL'
use strict; use warnings;
my ($cs,$ce,$action,$payload,$tf)=@ARGV;
open(my $fh,'<:encoding(UTF-8)',$tf) or exit 1;
local $/; my $T=<$fh>//''; close($fh);
my $len=length($T);
exit 1 if $cs<0 || $ce<$cs || $ce>$len;
# insert: avoid gluing two word chars together regardless of harper's spacing convention
if ($action eq 'insert' && length($payload)) {
  my $before = $ce>0 ? substr($T,$ce-1,1) : ' ';
  my $after  = $ce<$len ? substr($T,$ce,1) : ' ';
  $payload = ' '.$payload if ($before=~/\w/ && substr($payload,0,1)=~/\w/);
  $payload = $payload.' ' if (substr($payload,-1)=~/\w/ && $after=~/\w/);
}
my $corrected;
if    ($action eq 'insert'){ $corrected=substr($T,0,$ce).$payload.substr($T,$ce); }
elsif ($action eq 'remove'){ $corrected=substr($T,0,$cs).substr($T,$ce); }
else  { exit 1; }
$corrected =~ s/[ \t]{2,}/ /g;
my @a=split //,$T; my @b=split //,$corrected;
my ($na,$nb)=(scalar(@a),scalar(@b));
my $p=0; $p++ while($p<$na && $p<$nb && $a[$p] eq $b[$p]);
my $s=0; $s++ while($s<($na-$p) && $s<($nb-$p) && $a[$na-1-$s] eq $b[$nb-1-$s]);
my $lo=$p; my $ha=$na-$s; my $hb=$nb-$s;
$lo-- while($lo>0 && $a[$lo-1]=~/\S/);                      # prefix -> word start
if ($action ne 'remove'){ while($ha<$na && $a[$ha]=~/\S/){$ha++;$hb++;} }  # suffix -> word end
my $om=substr($T,$lo,$ha-$lo);
my $im=substr($corrected,$lo,$hb-$lo);
if ($om=~/^\s*$/ || $im=~/^\s*$/){                          # empty side -> pull preceding word
  my $q=$lo;
  $q-- while($q>0 && $a[$q-1]=~/\s/);
  $q-- while($q>0 && $a[$q-1]=~/\S/);
  if ($q<$lo){ $om=substr($T,$q,$ha-$q); $im=substr($corrected,$q,$hb-$q); }
}
for($om,$im){ s/^\s+//; s/\s+$//; }
exit 1 if ($om eq $im) || ($om eq '' && $im eq '');
print "$om\t$im";
PL
}
```

- [ ] **Step 4: 跑測試確認通過** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 全部 passed。

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/lib/grammar.sh plugins/english-coach/tests/test-grammar.sh
git commit -m "feat(english-coach): ec__render_edit + ec_map_lint insert/remove"
```

---

## Task 8: `ec_grammar_check`（四態狀態機）

跑 harper → 解析 → 選候選 → 渲染。回傳 4 態：`return 0`+行=hard_tip、`return 0`+空=verified_clean、`return 3`=hard_unrenderable、`return 2`=unavailable。**成敗只看 stdout 能否解析、不看 exit code**（守住 §5.2 的 upstream bail 行為）。

**Files:**
- Modify: `plugins/english-coach/lib/grammar.sh`（append）
- Modify: `plugins/english-coach/tests/test-grammar.sh`（append）

- [ ] **Step 1: append 失敗測試**：

```sh
# --- ec_grammar_check: 4 states ---
export EC_HARPER_BIN="$HERE/fake-harper"
mk() { FAKE_HARPER_OUT="$(mktemp)"; printf '%s' "$1" > "$FAKE_HARPER_OUT"; export FAKE_HARPER_OUT; }
TFC="$(mktemp)"; printf 'I beleive it' > "$TFC"

# hard_tip — valid JSON WITH a hard error, harper exits 1 (lints found). Must still gate.
mk '[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}]}]'
FAKE_HARPER_RC=1 ; out="$(ec_grammar_check "$TFC")"; rc=$?
assert_rc "check hard_tip rc0 despite exit1" 0 "$rc"
assert_eq "check hard_tip line" "😇 beleive → believe (possible misspelling)" "$out"

# verified_clean — valid JSON, no hard lint, exit 0
mk '[{"file":"x","lint_count":0,"lints":[]}]'
FAKE_HARPER_RC=0 ; out="$(ec_grammar_check "$TFC")"; rc=$?
assert_rc "check verified_clean rc0" 0 "$rc"; assert_eq "check verified_clean empty" "" "$out"

# hard_unrenderable — valid JSON, hard error, but suggestions empty -> rc3, no line
mk '[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":[],"matched_text":"beleive"}]}]'
FAKE_HARPER_RC=1 ; out="$(ec_grammar_check "$TFC")"; rc=$?
assert_rc "check hard_unrenderable rc3" 3 "$rc"; assert_eq "check hard_unrenderable empty" "" "$out"

# unavailable — garbage stdout (any exit)
mk 'not json at all'
FAKE_HARPER_RC=0 ; ec_grammar_check "$TFC" >/dev/null 2>&1; assert_rc "check unavailable rc2" 2 $?
```

- [ ] **Step 2: 跑測試確認失敗** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: check 斷言 FAIL（函式未定義）。

- [ ] **Step 3: 實作** — append 到 `lib/grammar.sh`：

```sh
# $1=textfile. echo tip-or-empty. return: 0 (hard_tip if non-empty / verified_clean if empty),
# 3 (hard_unrenderable), 2 (unavailable). NEVER trust harper's exit code.
ec_grammar_check() {
  local tf="$1" out cands rc cand line
  out="$("$EC_HARPER_BIN" lint --format json --quiet --no-color -d "${EC_HARPER_DIALECT:-us}" "$tf" 2>/dev/null)"
  cands="$(printf '%s' "$out" | ec_grammar_candidates)"; rc=$?
  [ "$rc" -ne 0 ] && return 2                      # not parseable -> unavailable
  [ -z "$cands" ] && { printf ''; return 0; }      # parsed, no hard candidate -> verified_clean
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    if line="$(ec_map_lint "$tf" "$cand")" && [ -n "$line" ]; then
      printf '%s' "$line"; return 0               # hard_tip
    fi
  done <<EOF
$cands
EOF
  return 3                                          # hard error(s) but none renderable
}
```

- [ ] **Step 4: 跑測試確認通過** — Run: `bash plugins/english-coach/tests/test-grammar.sh`
Expected: 全部 passed（含 exit-1-with-JSON 與 hard_unrenderable 兩個隱私回歸）。

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/lib/grammar.sh plugins/english-coach/tests/test-grammar.sh
git commit -m "feat(english-coach): ec_grammar_check 4-state machine (exit-code agnostic)"
```

---

## Task 9: worker.sh —— `ec_rubric` 收 template、providers 帶 template

讓 LLM 路徑能選用不同 rubric 檔（combined vs idiom-only），並 source grammar.sh。

**Files:**
- Modify: `plugins/english-coach/lib/worker.sh`

- [ ] **Step 1: source grammar.sh** — 把：

```sh
. "$EC_SELF_DIR/config.sh"
. "$EC_SELF_DIR/lib.sh"
```

改成：

```sh
. "$EC_SELF_DIR/config.sh"
. "$EC_SELF_DIR/lib.sh"
. "$EC_SELF_DIR/grammar.sh"
```

- [ ] **Step 2: `ec_rubric` 收參數** — 把：

```sh
# Load the rubric/system prompt once.
ec_rubric() { cat "$EC_SELF_DIR/prompt-template.txt"; }
```

改成：

```sh
# Load a rubric/system prompt. $1 = template filename (default: combined).
ec_rubric() { cat "$EC_SELF_DIR/${1:-prompt-template.txt}"; }
```

- [ ] **Step 3: 三個 provider 與 dispatch 帶 template** — 分別把每個 `ec_rubric` 呼叫改帶 `"$tmpl"`，並讓函式收第二參數。

`ec_provider_claude_cli`：把

```sh
ec_provider_claude_cli() {
  local pf="$1"
  ( cd /tmp && ENGLISH_COACH_SKIP=1 claude -p --model "$EC_CLAUDE_MODEL" "$(ec_rubric)" < "$pf" )
}
```

改成

```sh
ec_provider_claude_cli() {
  local pf="$1" tmpl="$2"
  ( cd /tmp && ENGLISH_COACH_SKIP=1 claude -p --model "$EC_CLAUDE_MODEL" "$(ec_rubric "$tmpl")" < "$pf" )
}
```

`ec_provider_anthropic`：把 `local pf="$1" url body reqf key out` 改成 `local pf="$1" tmpl="$2" url body reqf key out`，並把 `--arg sys "$(ec_rubric)"` 改成 `--arg sys "$(ec_rubric "$tmpl")"`。

`ec_provider_openai`：把 `local pf="$1" url body reqf out` 改成 `local pf="$1" tmpl="$2" url body reqf out`，並把 `--arg sys "$(ec_rubric)"` 改成 `--arg sys "$(ec_rubric "$tmpl")"`。

`ec_run_provider`：把

```sh
ec_run_provider() {
  case "$EC_BACKEND" in
    claude-cli) ec_provider_claude_cli "$1" ;;
    anthropic)  ec_provider_anthropic "$1" ;;
    openai)     ec_provider_openai "$1" ;;
    *) printf '' ;;
  esac
}
```

改成

```sh
# $1 = prompt file, $2 = template filename. Echoes RAW model text (caller sanitizes).
ec_run_provider() {
  case "$EC_BACKEND" in
    claude-cli) ec_provider_claude_cli "$1" "$2" ;;
    anthropic)  ec_provider_anthropic "$1" "$2" ;;
    openai)     ec_provider_openai "$1" "$2" ;;
    *) printf '' ;;
  esac
}
```

- [ ] **Step 4: 驗證 source + rubric 選檔** — Run:

```bash
EC_HOME=$(mktemp -d) bash -c '
  d=plugins/english-coach/lib; EC_SELF_DIR=$d; . $d/config.sh; . $d/lib.sh; . $d/grammar.sh
  ec_rubric | head -1 | grep -q "concise English coach" && echo combined-ok
  ec_rubric prompt-template.txt | head -1 | grep -q "concise English coach" && echo named-ok
'
```
Expected: `combined-ok` 與 `named-ok` 兩行（確認 grammar.sh 可被 source、`ec_rubric` 仍讀得到 combined）。

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/lib/worker.sh
git commit -m "refactor(english-coach): ec_rubric/providers take a template; source grammar.sh"
```

---

## Task 10: idiom-only prompt template

**Files:**
- Create: `plugins/english-coach/lib/prompt-template-idiom.txt`

- [ ] **Step 1: 寫 idiom-only rubric** — `plugins/english-coach/lib/prompt-template-idiom.txt`：

```text
You are a concise English coach for a non-native professional who wants to sound like a native AMERICAN English speaker. The user's hand-typed English message is provided as input.

Grammar and spelling have ALREADY been checked locally. Your ONLY job is NATURALNESS: if the message is grammatically valid but sounds non-native, awkward, wordy, stiff, or unidiomatic, rewrite the key fragment the way a native American speaker would actually say it (idiom, natural collocation, better word choice, concision, smoother flow). Do NOT nitpick minor grammar, punctuation, or spelling — that layer is handled elsewhere. (Only if you spot a GLARING grammar error that clearly slipped through may you flag that instead.)

Ignore anything that is not natural English prose: code, logs, URLs, file paths, commands, names, quotes, and non-English text — for those, output NOTHING.

Output EXACTLY ONE line — the single most valuable suggestion — in this format and nothing else:
😇 original → improved (reason)

Rules:
- "original" = the smallest fragment worth changing; "improved" = the more native-sounding version.
- "(reason)" = a brief, concrete WHY in plain words — the actual reason a native says it differently. Examples: ("back" is redundant), (natives don't "revert" to people), (wordy — just say "use"). A few words, aim for ≤ 8. NEVER a bare category label like (word choice) or (style) — name the specific reason.
- Pick only ONE thing. Keep the whole line comfortably under ~100 characters.
- If the message already sounds natural to a native American speaker, output NOTHING — do not nitpick small stylistic preferences.
- American English. No reasoning aloud, no extra lines, no markdown, no code fences — output the one line and stop.
```

- [ ] **Step 2: 驗證可被 `ec_rubric` 讀到** — Run:

```bash
EC_HOME=$(mktemp -d) bash -c '
  d=plugins/english-coach/lib; EC_SELF_DIR=$d; . $d/config.sh; . $d/lib.sh; . $d/grammar.sh
  ec_rubric prompt-template-idiom.txt | grep -q "ONLY job is NATURALNESS" && echo idiom-ok'
```
Expected: `idiom-ok`

- [ ] **Step 3: Commit**

```bash
git add plugins/english-coach/lib/prompt-template-idiom.txt
git commit -m "feat(english-coach): add idiom-only prompt template"
```

---

## Task 11: worker.sh —— `ec_worker_main` 四態狀態機 + routing 測試

**Files:**
- Modify: `plugins/english-coach/lib/worker.sh`
- Create: `plugins/english-coach/tests/test-worker.sh`

- [ ] **Step 1: 寫失敗測試** — `plugins/english-coach/tests/test-worker.sh`：

```sh
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$(cd "$HERE/../lib" && pwd)"
export EC_HOME="$(mktemp -d)"
. "$LIB/worker.sh"          # pulls in config.sh + lib.sh + grammar.sh; sets EC_SELF_DIR
. "$HERE/_assert.sh"

export EC_HARPER_BIN="$HERE/fake-harper"
MARK="$(mktemp)"
# stub the LLM provider: record the template it was called with, emit a canned tip
ec_run_provider() { printf '%s' "$2" > "$MARK"; printf '😇 utilize → use (just say "use")'; }

run_worker() { # $1=harper-json $2=harper-rc ; echoes the written tip body
  local sid="s1" seq=1
  : > "$MARK"
  FAKE_HARPER_OUT="$(mktemp)"; printf '%s' "$1" > "$FAKE_HARPER_OUT"; export FAKE_HARPER_OUT
  export FAKE_HARPER_RC="$2"
  mkdir -p "$EC_STATE_DIR"; printf '%s' "$seq" > "$EC_STATE_DIR/$sid.seq"
  local pf; pf="$(mktemp)"; printf 'I beleive utilize it' > "$pf"
  ( ec_worker_main "$sid" "$seq" "$pf" )
  sed -n '2,$p' "$EC_TIPS_DIR/$sid"
}

SP_RENDER='[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}]}]'
SP_EMPTY='[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":[],"matched_text":"beleive"}]}]'

# hard_tip: local line, provider NOT called (privacy gate)
TIP="$(run_worker "$SP_RENDER" 1)"
assert_eq "worker hard_tip line"        "😇 beleive → believe (possible misspelling)" "$TIP"
assert_eq "worker hard_tip no provider" "" "$(cat "$MARK")"

# verified_clean: idiom-only provider
TIP="$(run_worker '[{"file":"x","lint_count":0,"lints":[]}]' 0)"
assert_eq "worker verified_clean tmpl" "prompt-template-idiom.txt" "$(cat "$MARK")"
assert_eq "worker verified_clean tip"  '😇 utilize → use (just say "use")' "$TIP"

# hard_unrenderable: no provider, empty tip
TIP="$(run_worker "$SP_EMPTY" 1)"
assert_eq "worker hard_unrenderable no provider" "" "$(cat "$MARK")"
assert_eq "worker hard_unrenderable empty tip"   "" "$TIP"

# unavailable (garbage): combined provider
run_worker 'not json' 0 >/dev/null
assert_eq "worker unavailable tmpl" "prompt-template.txt" "$(cat "$MARK")"

# EC_GRAMMAR=off: never call harper -> combined provider even though a hard error exists
EC_GRAMMAR=off run_worker "$SP_RENDER" 1 >/dev/null
assert_eq "worker off -> combined" "prompt-template.txt" "$(cat "$MARK")"

ec_tests_done
```

- [ ] **Step 2: 跑測試確認失敗** — Run: `bash plugins/english-coach/tests/test-worker.sh`
Expected: 多數斷言 FAIL（`ec_worker_main` 仍是舊版：總是呼叫 provider、tmpl 為空）。

- [ ] **Step 3: 重寫 `ec_worker_main`** — 把 worker.sh 裡整個 `ec_worker_main()` 函式替換為：

```sh
ec_worker_main() {
  local sid_key="$1" seq="$2" pf="$3" state tip rc tmpl
  # shellcheck disable=SC2064
  trap "rm -f '$pf'" EXIT

  # Local grammar pre-pass first; gate the LLM on detected hard errors (§4.1).
  state="unavailable"; tip=""
  if [ "$(ec_grammar_resolve)" = "harper" ]; then
    tip="$(ec_grammar_check "$pf")"; rc=$?
    case "$rc" in
      0) [ -n "$tip" ] && state="hard_tip" || state="verified_clean" ;;
      3) state="hard_unrenderable" ;;
      *) state="unavailable" ;;
    esac
  fi

  case "$state" in
    verified_clean) tmpl="prompt-template-idiom.txt" ;;   # grammar clean -> idiom only
    unavailable)    tmpl="prompt-template.txt" ;;         # off/missing/parse-fail -> combined (= today)
    *)              tmpl="" ;;                            # hard_tip / hard_unrenderable -> no LLM
  esac
  if [ -n "$tmpl" ]; then
    tip="$(ec_run_provider "$pf" "$tmpl" | ec_sanitize_tip)"
  fi
  [ "$state" = "hard_unrenderable" ] && tip=""            # detected hard error stays off the network

  # Seq guard (§4.4): only write if no newer prompt has arrived.
  [ "$(ec_seq_current "$sid_key")" = "$seq" ] || return 0

  mkdir -p "$EC_TIPS_DIR"
  printf 'seq=%s\n%s' "$seq" "$tip" | ec_atomic_write "$EC_TIPS_DIR/$sid_key"

  # Optional logging (off by default, §7) — now records the resolved state.
  if [ "${EC_LOG:-0}" = "1" ]; then
    mkdir -p "$EC_HOME"
    if [ "${EC_LOG_ORIGINAL:-0}" = "1" ] && command -v jq >/dev/null 2>&1; then
      jq -nc --arg s "$seq" --arg b "$EC_BACKEND" --arg st "$state" --arg t "$tip" --rawfile o "$pf" \
        '{seq:$s, backend:$b, state:$st, tip:$t, original:$o}' >> "$EC_LOG_FILE" 2>/dev/null || true
    else
      printf '{"seq":"%s","backend":"%s","state":"%s","has_tip":%s}\n' \
        "$seq" "$EC_BACKEND" "$state" "$([ -n "$tip" ] && echo true || echo false)" >> "$EC_LOG_FILE"
    fi
  fi
}
```

- [ ] **Step 4: 跑測試確認通過** — Run: `bash plugins/english-coach/tests/test-worker.sh`
Expected: `test-worker.sh: N passed, 0 failed`

- [ ] **Step 5: 全套測試** — Run: `bash plugins/english-coach/tests/run.sh; echo rc=$?`
Expected: 兩個檔案皆 0 failed、`rc=0`

- [ ] **Step 6: Commit**

```bash
git add plugins/english-coach/lib/worker.sh plugins/english-coach/tests/test-worker.sh
git commit -m "feat(english-coach): wire worker to 4-state grammar gating"
```

---

## Task 12: 文件（README + setup skill）

**Files:**
- Modify: `plugins/english-coach/README.md`
- Modify: `plugins/english-coach/skills/setup/SKILL.md`

- [ ] **Step 1: README 設定範例加 grammar 旋鈕** — 把：

```sh
EC_TIP_SGR=38;5;248                       # tip 顏色（ANSI SGR）
[ -f "$EC_HOME/secrets.env" ] && . "$EC_HOME/secrets.env" || true
```

改成：

```sh
EC_TIP_SGR=38;5;248                       # tip 顏色（ANSI SGR）
EC_GRAMMAR=auto                           # auto|harper|off：本地文法層（裝了 harper-cli 就用）
EC_HARPER_GATE=errors                     # errors|any：哪些 lint 種類擋住 LLM
[ -f "$EC_HOME/secrets.env" ] && . "$EC_HOME/secrets.env" || true
```

- [ ] **Step 2: README 新增「本地文法」段** — 在 `## 移除` 這一行之前，插入：

```markdown
## 本地文法（Harper，選配）

裝了 [Harper](https://github.com/Automattic/harper)（離線文法檢查）後，english-coach 會**先在本地擋文法／拼字錯**：抓到硬錯誤就直接在狀態列給一行修正、**完全不呼叫 LLM**（那句話不出網路）；只有文法乾淨時才把句子交給 LLM 做 native-American 語感。沒裝 Harper 就維持原本「LLM 同時做文法＋語感」。

```text
brew install harper      # 裝出 harper-cli（也可用 cargo 或 GitHub releases 預編譯檔）
```

- 開關：`EC_GRAMMAR=auto`（裝了就用）／`harper`（強制）／`off`（停用）。
- `EC_HARPER_GATE=errors`（預設）只讓硬錯誤擋 LLM；`any` 則 Harper 抓到什麼風格建議也顯示。
- 想連語感都全本地：把 `EC_OPENAI_BASE_URL` 指向本地 Ollama（`http://localhost:11434/v1`）。
```

- [ ] **Step 3: README 運作細節加一條** — 把：

```markdown
- per-session 單調遞增 `seq` 確保只顯示「對得上當前輸入」的 tip；送下一句舊 tip 自動失效。
```

改成：

```markdown
- 有裝 Harper 時，worker 先跑本地文法：抓到硬錯誤就顯示本地行並跳過 LLM；文法乾淨才用 idiom-only prompt 問 LLM；Harper 沒裝／解析失敗則退回 combined prompt（＝原行為）。
- per-session 單調遞增 `seq` 確保只顯示「對得上當前輸入」的 tip；送下一句舊 tip 自動失效。
```

- [ ] **Step 4: setup skill 補一句** — 在 `plugins/english-coach/skills/setup/SKILL.md` 檔尾新增一行：

```markdown

> 選配：裝 `harper-cli`（`brew install harper`）即啟用本地文法層——有文法錯時本地直接修、不呼叫 LLM。見 README 的「本地文法」段。
```

- [ ] **Step 5: Commit**

```bash
git add plugins/english-coach/README.md plugins/english-coach/skills/setup/SKILL.md
git commit -m "docs(english-coach): document the local Harper grammar layer"
```

---

## Task 13: 版本 bump + 驗證

**Files:**
- Modify: `plugins/english-coach/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: bump plugin.json** — 把 `"version": "0.1.0",` 改成 `"version": "0.2.0",`（`plugins/english-coach/.claude-plugin/plugin.json`）。

- [ ] **Step 2: bump marketplace.json** — 在 `.claude-plugin/marketplace.json`，用這個**唯一錨點**只改 english-coach 那筆（kehao-util 也是 `0.1.0`，別動到）。把：

```json
      "source": "./plugins/english-coach",
      "description": "Background English coach: checks hand-typed English on submit and shows a one-line native-American suggestion in the statusline. Zero context/token impact.",
      "version": "0.1.0",
```

改成（只有最後一行的版本變）：

```json
      "source": "./plugins/english-coach",
      "description": "Background English coach: checks hand-typed English on submit and shows a one-line native-American suggestion in the statusline. Zero context/token impact.",
      "version": "0.2.0",
```

- [ ] **Step 3: 一致性檢查** — Run:

```bash
grep -n '"version"' plugins/english-coach/.claude-plugin/plugin.json
grep -n -A1 '"name": "english-coach"' .claude-plugin/marketplace.json | grep version
```
Expected: 兩處皆 `0.2.0`。

- [ ] **Step 4: 跑全套測試** — Run: `bash plugins/english-coach/tests/run.sh; echo rc=$?`
Expected: `rc=0`，所有檔案 0 failed。

- [ ] **Step 5: 跑 repo 驗證** — Run: `./scripts/validate.sh`
Expected: 通過（plugin validate --strict + 版本一致檢查）。

- [ ] **Step 6: Commit**

```bash
git add plugins/english-coach/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore(english-coach): bump to 0.2.0 (hybrid local-grammar + LLM idiom)"
```

- [ ] **Step 7:（選配，需真 Harper）人工煙霧測試** — 若本機有 `harper-cli`，開新 session 手打下列各一句，確認狀態列：
  - `i beleive this is teh answer` → 本地拼字修正、無網路（可 `EC_LOG=1` 看 `state":"hard_tip"`）。
  - `I have cat on the table` → 漏冠詞，本地 `cat → a cat` 之類。
  - `Please kindly do the needful` → 文法乾淨、LLM 給 idiom（`state":"verified_clean"`）。

---

## Spec 覆蓋對照（規劃自我檢查）

| Spec 段 | 對應 Task |
|---|---|
| §4.1 控制流四態 | T11（狀態機）、T8（ec_grammar_check 回傳碼） |
| §5.1 ec_grammar_resolve | T3 |
| §5.2 exit-code 不可信＋四態 return | T8（＋fake-harper exit1 回歸於 T8 Step1） |
| §5.3 kind 分桶＋選擇 | T4 |
| §5.4 映射（Replace / Insert / Remove / reason） | T5、T6、T7 |
| §5.5 共用 sanitizer | T6（ec_sanitize_local） |
| §6 兩條 prompt + ec_rubric(template) | T9、T10 |
| §7 隱私（hard_tip / hard_unrenderable 不出網路） | T11（routing 測試斷言 no-provider） |
| §8 退回（unavailable→combined、failure 不降級 idiom） | T8、T11 |
| §9 測試 1–13 | T3–T8、T11 散佈涵蓋 |
| §10 發版 0.2.0 | T13 |
| §12 風險（experimental/exit-code/perl 字元） | T8 防禦、T7 `-CSDA`、註解 pin 版本 |

> 註：spec §9 測 3/4（Insert/Remove 真實渲染）在 T7 以 canned JSON 驗證；harper 真實 Insert/Remove 的 span/payload 慣例由 T13 Step 7 人工煙霧測試把關，必要時微調 T7 的空白正規化。

