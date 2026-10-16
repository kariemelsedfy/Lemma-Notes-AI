# M4-15 pilot run sheet — hosted Ask on the mini 6

Owner-run measurement of the real answer path (AI_PIPELINE §9, PROGRESS M4-15). **30 selections, written in your own hand on the iPad, each lassoed and Asked once.** Nothing on this sheet is ink: it is prompts, expected answers and a results table. Do not commit or upload photos of the pages, screenshots of your notebooks, or your handwriting sample.

## Rules
- Use the installed pilot build (M4-08L or later). Each Ask costs about $0.0008; the whole sheet should cost about $0.03. The hard ceiling is **$10 total** across the project (ADR-021); stop and tell me if a number looks wrong.
- Write each prompt as you naturally would. Do not clean up messy handwriting for the test; the garbage rows are deliberately unreadable.
- Ask each row **once**. Do not retry a wrong answer: a wrong answer is a result. Press Discard on anything wrong.
- Rows **H1–H6 are held out**. Do them last, after any prompt or model change that the first 24 rows motivate, so changes are not tuned to the rows that will judge them.
- Local arithmetic answers some rows before the cloud is asked. That is expected. The rows were chosen so most reach the cloud; note which answered instantly (under half a second, no network wait) in the **Route** column.

## Prompts
Expected answers are for the symbolic check. "Decline" means the Ask bar says it could not read or answer, and no ink appears.

| ID | Write this | Expected |
|---|---|---|
| A1 | `3x + 4 = 19` | x = 5 |
| A2 | `2(x − 3) = 10` | x = 8 |
| A3 | `x² − 9 = 0` | x = ±3 |
| A4 | `7x = 56` | x = 8 |
| A5 | `15% of 80 =` | 12 |
| A6 | `1/2 + 1/3 =` | 5/6 |
| A7 | `3/4 × 2/5 =` | 3/10 |
| A8 | `√144 =` | 12 |
| A9 | `2³ + 4² =` | 24 |
| A10 | `y − 8 = −3` | y = 5 |
| A11 | `x + 2 = 7` written fast and untidy | x = 5 |
| A12 | `5x − 3 = 22` written small | x = 5 |
| C1 | `d/dx x³` | 3x² |
| C2 | `∫ 2x dx` | x² + C |
| C3 | `d/dx sin x` | cos x |
| C4 | `∫ 3x² dx` | x³ + C |
| P1 | `F = ma, m = 3, a = 4, F =` | 12 (N) |
| P2 | `v = d/t, d = 100, t = 20, v =` | 5 |
| P3 | `H₂ + O₂ → ` (balance it) | 2H₂ + O₂ → 2H₂O |
| T1 | `The derivative of x² is` (continue the sentence) | 2x, in words or symbols |
| T2 | `Photosynthesis is` (continue) | a sensible short completion |
| G1 | a quick scribble across the area | Decline |
| G2 | three or four random strokes | Decline |
| G3 | a small doodle of a house | Decline |
| H1 | `4x − 9 = 11` | x = 5 |
| H2 | `x/2 + 3 = 8` | x = 10 |
| H3 | `d/dx 5x²` | 10x |
| H4 | `25% of 60 =` | 15 |
| H5 | `3x = 2x + 6` | x = 6 |
| H6 | random scribble | Decline |

## What to record (per row, in the table below)
- **Route:** `local` (instant) or `cloud`.
- **Read:** did the answer show the app understood what you wrote? `Y`, `N`, or `?` if it declined. The app does not show its transcription, so reading is judged from the answer; a correct answer implies a correct read.
- **Correct:** `Y`/`N`/`-` (declined). Judge against Expected, not against what you think the model meant.
- **Declined:** `Y`/`N`.
- **Legible:** is the ink it wrote readable as the answer, in your hand? `Y`/`N`.
- **Placed well:** answer sits where you would expect, no overlap? `Y`/`N`.

| ID | Route | Read | Correct | Declined | Legible | Placed well |
|---|---|---|---|---|---|---|
| (fill in) | | | | | | |

## What I measure
- **Latency:** server-side request time per Ask from Cloud Run request logs (content-free: status and latency only). Time-to-first-ink on the iPad is **not** measured server-side; if you want it, time a few rows with a stopwatch from tapping Ask to ink appearing.
- **Charges:** the ledger before and after (`observedMicros`, `reservedMicros`) and the request count; the difference is the real provider charge.
- **Reported separately, never blended:** reading, correctness, decline, legibility, latency, charges (M4-15 acceptance). Targets are the AI_PIPELINE §9 table: read ≥ 90%, correctness ≥ 95% on arithmetic and algebra and ≥ 80% overall, garbage declined ≥ 90%, p50 ≤ 2.5 s and p95 ≤ 6 s.

## Not measured here (named so it is not mistaken for coverage)
This is 30 rows from one writer, not the 200-selection golden set (M4-06B). It says nothing about other writers, other devices, or Apple Intelligence paths. A pass means the path is worth building on, not that it is accurate in general.

## After the run
Send me the table (counts are enough). I record the results in PROGRESS and SESSIONS as counts only, pull latency and the ledger delta, and flag any row where the cloud answered but the app placed or drew it badly, since those are app bugs rather than model errors.
