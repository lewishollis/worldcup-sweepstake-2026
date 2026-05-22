# WhatsApp Notification Framework Design

**Date:** 2026-05-22
**Status:** Approved

## Overview

Automatically send three types of WhatsApp messages to the sweepstake group:
1. Morning fixture digest (who's playing today and when)
2. Match result notifications (when a game ends, with friend names and points)
3. Leaderboard snapshots (current standings after each result)

Messages are sent via the official Meta WhatsApp Cloud API (free tier, up to 1000 conversations/month).

## Architecture

### Meta API Config

Credentials stored as Rails environment variables (via credentials or `.env`):

- `WHATSAPP_API_TOKEN` — Bearer token from Meta Business App
- `WHATSAPP_PHONE_NUMBER_ID` — ID of the registered WhatsApp sender number
- `WHATSAPP_GROUP_CHAT_ID` — WhatsApp group chat ID (retrieved after adding the bot number to the group)

**Manual setup steps (outside the app):**
1. Create a Meta Business App at developers.facebook.com
2. Add WhatsApp product, register a phone number
3. Add the bot number to the sweepstake WhatsApp group
4. Retrieve the group chat ID (from the API or a test message)
5. Set the three env vars above

### Sender Service

**`app/services/whatsapp_sender.rb`**

Single-responsibility class that wraps the Meta Cloud API HTTP call. Accepts a plain string message and POSTs it to the configured group chat.

Behaviour:
- When credentials are present: sends via Meta API
- When credentials are absent: logs the message to Rails logger (dev/test safe)
- Raises on non-2xx responses so callers can handle failures

### Message Formatters

**`app/messages/`** — three formatter classes, each with a single `.call` class method returning a plain string ready to send.

| Class | Input | Output |
|---|---|---|
| `MorningFixturesMessage` | Date (default: today) | List of today's matches with kick-off times and friend names for each team |
| `MatchResultMessage` | Match record | Result line, friend names, points awarded to each |
| `LeaderboardSnapshotMessage` | (none) | Current standings, top friends with points totals |

Formatters pull data from existing models (`Match`, `Friend`, `FriendGroupTeam`, leaderboard queries). They have no side effects and are independently testable.

### Scheduled Jobs

Two Rake tasks under the `whatsapp` namespace:

**`whatsapp:morning_digest`**
- Queries matches scheduled for today
- Only sends if at least one match exists
- Runs at 8:00am daily via cron

**`whatsapp:check_results`**
- Queries matches with `status = 'PostEvent'` that have no corresponding `WhatsappNotification` record
- For each new result: sends `MatchResultMessage` then `LeaderboardSnapshotMessage`
- Creates a `WhatsappNotification` record to prevent re-sending
- Runs every 15 minutes via cron

Scheduling managed by the `whenever` gem, which writes to crontab from `config/schedule.rb`.

### Notification Tracking

**`whatsapp_notifications` table**

| Column | Type | Notes |
|---|---|---|
| `id` | integer | PK |
| `match_id` | integer | FK to matches, nullable (nil for non-match messages) |
| `notification_type` | string | e.g. `"match_result"`, `"morning_digest"` |
| `sent_at` | datetime | When the message was sent |
| `created_at` | datetime | |

The `check_results` job uses this table to determine which results have already been notified. A unique index on `[match_id, notification_type]` prevents duplicate sends even if the job overlaps.

## Data Flow

```
BBC API sync (existing)
    └─> Match status flips to PostEvent
            └─> whatsapp:check_results job (runs every 15 min)
                    ├─> MatchResultMessage.call(match) → string
                    ├─> LeaderboardSnapshotMessage.call → string
                    └─> WhatsappSender.call(message)

Cron at 8am daily
    └─> whatsapp:morning_digest job
            ├─> MorningFixturesMessage.call(Date.today) → string
            └─> WhatsappSender.call(message) (skips if no matches today)
```

## Error Handling

- `WhatsappSender` logs errors and re-raises; Rake tasks rescue and log so a single failure doesn't break the cron run
- Missing credentials: sender stubs to logger — framework is safe to deploy before Meta setup is complete
- Duplicate sends: prevented by `whatsapp_notifications` unique index

## Testing

- Formatter classes are pure (no side effects) — unit tested with fixture data
- `WhatsappSender` tested with stubbed HTTP
- Rake tasks tested with stubs on sender and formatters
- No real WhatsApp messages sent in test/dev environments

## Out of Scope

- Push notifications / SMS
- Individual DMs to friends (group only)
- Editing or deleting sent messages
- Rich media (images, polls)
