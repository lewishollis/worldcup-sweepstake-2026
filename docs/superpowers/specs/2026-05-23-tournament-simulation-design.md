# Tournament Simulation — Design Spec
_Date: 2026-05-23_

## Goal

A single rake task (`tournament:simulate`) that runs a full end-to-end simulation of the World Cup tournament against the development database. Lets us verify the entire points/leaderboard/AI pipeline before the real tournament begins.

---

## Scope

- **In scope**: match creation, points assignment, leaderboard calculation, AI commentary (real Groq API).
- **Out of scope**: WhatsApp sending (completely skipped — no `WhatsappSender` calls, no `WhatsappNotification` records).
- **Database**: runs against the real (development) DB. Resets match data and team points at the start of every run. Friends/groups/teams are preserved.

---

## Tournament Structure

100 matches total across 6 phases:

| Phase            | Matches | Points logic |
|------------------|---------|-------------|
| Group Stage      | 72      | 0 pts (existing logic) |
| Last 16          | 16      | +1 progression, +1 win |
| Quarter-finals   | 8       | +1 progression, +1 win |
| Semi-finals      | 4       | +1 progression, +1 win |
| 3rd Place Final  | 1       | +1 progression, +1 win |
| Final            | 1       | +1 progression, +2 win / +1 runner-up |

**Group Stage (72 matches)**
- 12 groups of 4 teams, 6 matches per group (round-robin).
- Random scores generated (0–3 each side). Winner determined by score (draw = nil winner).
- `home_points` / `away_points` = 0 (as per existing logic).
- Group standings calculated from match results (3pts win, 1pt draw, 0 loss).
- Top 2 from each group advance (24 teams).
- Best 8 third-place finishers (by points, then goal difference) also advance.
- Total: 32 teams enter Last 16.

**Knockout rounds (Last 16 → Final)**
- No draws — a winner is randomly chosen.
- Both teams receive +1 progression point on their first knockout appearance (via existing `progressed` flag logic).
- Winner receives stage win points; Final runner-up receives +1.
- Bracket advances winners until champion is determined.

---

## Points Flow

The task inlines the points assignment logic (mirrors `MatchesController#assign_points` and `update_team_points`). This avoids touching production controller code while exercising the same rules.

No `BenMotsonService` or `MatchInsightService` calls during match processing — only a single `BenMotsonService.new(:leaderboard, ...).generate_insight` call at the very end.

---

## Reset Behaviour

On every run, before simulation:
1. `Match.destroy_all`
2. `Team.update_all(points: 0, progressed: false)`
3. `AiInsightCache.destroy_all`
4. Friends, groups, team associations: untouched.

A confirmation prompt is shown before proceeding:
```
⚠️  This will reset all match data and team points. Continue? (yes/no):
```

---

## Report Output

Printed at the end of the task:

```
========================================
  SIMULATION COMPLETE
========================================

Total matches simulated: 100
  Group Stage:     72
  Last 16:         16
  Quarter-finals:   8
  Semi-finals:      4
  3rd Place Final:  1
  Final:            1

FINAL LEADERBOARD
-----------------
1. Lewis     — 18pts  (Brazil, Morocco, Haiti, Scotland)
2. Ben       — 15pts  (...)
...

POINTS BREAKDOWN
----------------
Lewis:   Brazil(4) + Morocco(2) + Haiti(1) + Scotland(0) = 7 raw × 3 = 21pts
...

CHAMPION: Brazil (owned by Lewis)

BEN MOTSON SAYS:
"[AI commentary]"

========================================
```

Errors (e.g. Groq API failure) are caught and printed without crashing the task.

---

## Implementation Notes

- New task: `lib/tasks/tournament.rake` — add `tournament:simulate` to existing namespace.
- No new models, services, or routes needed.
- Safe to run multiple times — idempotent reset at the start of every run.
- After the real tournament begins, run `db:seed` to restore clean state.
