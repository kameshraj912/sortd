// bug-hunt: Sortd's review fan-out for stage 4 (sortd-test).
//
// How to run: the router calls the Workflow tool with
//   name: "bug-hunt"
//   args: {worktree: "<absolute path of a clean worktree made by scripts/worktree-new.sh>"}
// Always ask Raj first; one run is about 10 agents.
//
// What it does:
//   Review  5 reviewers in parallel, one per area, each acting as the project's
//           abuse-tester + code-reviewer, working from docs/testing/attacks.md.
//   Verify  findings are de-duplicated, ranked by severity, and the top 5 go to a
//           finding-verifier each, ONE AT A TIME. The worktree has one simulator;
//           two test runs on it fail with "Invalid device state" (HANDOVER.md Traps).
//
// It writes nothing itself. Reviewers may add one known-bug test file each under
// SpendTests/. The sortd-test skill writes docs/BugHunt-<date>.md from the result.
// ui-driver is not in here: it needs its own worktree and simulator, so sortd-test
// runs it beside this workflow.

export const meta = {
  name: 'bug-hunt',
  description: 'Sortd bug hunt: 5 area reviewers in parallel, then finding-verifier on the top 5 findings by severity. Returns confirmed and rejected findings; writes no docs.',
  whenToUse: 'Stage 4 (sortd-test), after scripts/test.sh --all, when Raj has said yes to a bug hunt. Pass args {worktree}.',
  phases: [
    { title: 'Review', detail: 'money-parsing, gmail-security, data-backup, ui-intents-widget, statement-import in parallel' },
    { title: 'Verify', detail: 'finding-verifier on the top 5 findings by severity, one at a time' },
  ],
}

if (!args || typeof args.worktree !== 'string' || !args.worktree.startsWith('/')) {
  throw new Error('bug-hunt needs args {worktree: "<absolute worktree path>"}')
}
const WT = args.worktree
const VERIFY_CAP = 5

const AREAS = [
  { id: 'money-parsing', suite: 'BugHuntMoneyTests',
    files: 'Spend/Services/Parsing.swift, QuickEntry.swift, BankAlerts.swift, EmailParsers.swift, GenericReceipts.swift, FXService.swift' },
  { id: 'gmail-security', suite: 'BugHuntGmailTests',
    files: 'Spend/Services/GmailSync.swift, GoogleAuth.swift, EmailSync.swift, Keychain.swift, AppLock.swift, ProStore.swift, CrashReporting.swift' },
  { id: 'data-backup', suite: 'BugHuntDataTests',
    files: 'Spend/Services/Backup.swift, Deduper.swift, SpendStore.swift, Exports.swift, Recurring.swift, CategoryBudgets.swift, and wherever TransactionLogger lives' },
  { id: 'ui-intents-widget', suite: 'BugHuntUITests',
    files: 'Spend/Intents/*, SortdWidget/*, Spend/Services/WidgetBridge.swift, WidgetSummary.swift, Reminders.swift, Spend/Views/*' },
  { id: 'statement-import', suite: 'BugHuntStatementTests',
    files: 'Spend/Services/StatementImport.swift, StatementReader.swift, Deduper.swift, Spend/Views (ImportView)' },
]

const SEVERITY_RANK = { critical: 0, high: 1, medium: 2, low: 3 }

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    branch: { type: 'string', description: 'output of git -C <worktree> branch --show-current' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          file: { type: 'string', description: 'repo-relative path' },
          line: { type: 'integer' },
          input: { type: 'string', description: 'the exact input that triggers it' },
          expected: { type: 'string' },
          actual: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          evidence: { type: 'string', description: 'code quoted from file:line, plus the known-bug test name if one was written' },
        },
        required: ['title', 'file', 'line', 'input', 'expected', 'actual', 'severity', 'evidence'],
      },
    },
  },
  required: ['branch', 'findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    isReal: { type: 'boolean' },
    verdict: { type: 'string', enum: ['CONFIRMED', 'NOT A BUG', 'CANNOT REPRODUCE'] },
    evidence: { type: 'string', description: 'the command run and its output, or why it is not a bug' },
  },
  required: ['isReal', 'verdict', 'evidence'],
}

function reviewPrompt(area) {
  return `You are reviewing the Sortd iPhone app for bugs in one area: ${area.id}.
Act as the project's abuse-tester and code-reviewer. First read
${WT}/.claude/agents/abuse-tester.md and ${WT}/.claude/agents/code-reviewer.md and follow their rules.

Worktree: ${WT}. Work only there. Never cd to the main Sortd folder or any other worktree.
Run \`git -C ${WT} branch --show-current\` first and return it as \`branch\`.

Start from the "${area.id}" section of ${WT}/docs/testing/attacks.md. Try every line, then add your own.
Main files: ${area.files}.
Skip bugs that ${WT}/docs/BugHunt-*.md lists as fixed, unless the fix has regressed.

Rules:
- Read-only, except you may create ONE file: ${WT}/SpendTests/${area.suite}.swift, with a failing
  Swift Testing case per finding, each tagged \`.tags(.knownBug)\` and \`.enabled(if: KnownBugs.run)\`.
  Use an in-memory ModelContainer. If KnownBugs or the .knownBug tag is not defined in SpendTests/
  on this branch, do not create the file; put the test code in \`evidence\` instead.
- Check the file parses: \`swiftc -parse ${WT}/SpendTests/${area.suite}.swift\`.
- Do NOT run scripts/build.sh, scripts/test.sh, xcodebuild or simctl. Four other reviewers share this
  worktree and its one simulator; the verifiers run the tests later, one at a time.
- Do not commit, stage, stash or edit any other file.
- Every finding needs a real file and line you read in ${WT}, a concrete input, expected vs actual.
  No input, no finding. Do not invent problems to look thorough. At most 8 findings.
- Severity: critical = wrong money or lost data for many users; high = wrong money or lost data in a
  real case; medium = wrong but visible and recoverable; low = cosmetic or rare.`
}

function verifyPrompt(f) {
  return `Act as the project's finding-verifier. First read ${WT}/.claude/agents/finding-verifier.md and follow it.

Worktree: ${WT}. Work only there. Check \`git -C ${WT} branch --show-current\` before anything else.

Claimed bug (${f.area}, severity ${f.severity}): ${f.title}
Where: ${f.file}:${f.line}
Input: ${f.input}
Expected: ${f.expected}
Actual (claimed): ${f.actual}
Reviewer evidence: ${f.evidence}

Reproduce it in the real code. Open ${f.file} at line ${f.line} and check the code says what the claim says.
If a known-bug test exists for it, run \`scripts/test.sh --known-bugs --only <SuiteName>\` from ${WT} and read the result.
Use scripts/*.sh only, never raw xcodebuild or simctl. Do not edit, create, commit or stash any file.
If the build fails because of a SpendTests/BugHunt*Tests.swift file, answer CANNOT REPRODUCE and paste the compiler error.

Verdict: CONFIRMED (you saw the wrong result), NOT A BUG (say why: intended, unreachable input, wrong reading),
or CANNOT REPRODUCE. isReal is true only for CONFIRMED. Evidence = the command and its output.`
}

// ---- Review: 5 areas in parallel ------------------------------------------
phase('Review')
const reviews = await parallel(AREAS.map(area => () =>
  agent(reviewPrompt(area), { label: `review ${area.id}`, phase: 'Review', schema: FINDINGS_SCHEMA })
    .then(r => (r ? { area: area.id, branch: r.branch, findings: r.findings || [] } : null))
))

const failedAreas = AREAS.filter((_, i) => !reviews[i]).map(a => a.id)
if (failedAreas.length) log(`No result from: ${failedAreas.join(', ')}`)

// Barrier is needed here: de-dup and rank across ALL areas before picking the top 5.
const seen = new Set()
const all = []
for (const r of reviews.filter(Boolean)) {
  for (const f of r.findings) {
    const key = `${f.file}:${f.line}`
    if (seen.has(key)) continue
    seen.add(key)
    all.push({ ...f, area: r.area, branch: r.branch })
  }
}
all.sort((a, b) => (SEVERITY_RANK[a.severity] ?? 9) - (SEVERITY_RANK[b.severity] ?? 9))
const toVerify = all.slice(0, VERIFY_CAP)
const unverified = all.slice(VERIFY_CAP)
log(`${all.length} findings after de-dup; verifying top ${toVerify.length}`)
if (unverified.length) log(`Not verified (over the cap of ${VERIFY_CAP}): ${unverified.length}. Returned as "unverified".`)

// ---- Verify: one at a time (one simulator per worktree) --------------------
phase('Verify')
const confirmed = []
const rejected = []
for (let i = 0; i < toVerify.length; i++) {
  const f = toVerify[i]
  const v = await agent(verifyPrompt(f), { label: `verify ${i + 1}: ${f.title.slice(0, 40)}`, phase: 'Verify', schema: VERDICT_SCHEMA })
  if (!v) {
    rejected.push({ ...f, verdict: 'CANNOT REPRODUCE', verifierEvidence: 'verifier returned nothing' })
  } else if (v.isReal && v.verdict === 'CONFIRMED') {
    confirmed.push({ ...f, verdict: v.verdict, verifierEvidence: v.evidence })
  } else {
    rejected.push({ ...f, verdict: v.verdict, verifierEvidence: v.evidence })
  }
}
log(`${confirmed.length} confirmed, ${rejected.length} rejected, ${unverified.length} not verified`)

return {
  worktree: WT,
  branches: [...new Set(reviews.filter(Boolean).map(r => r.branch))],
  failedAreas,
  confirmed,
  rejected,
  unverified,
}
