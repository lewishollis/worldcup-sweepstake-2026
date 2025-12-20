# AI-Powered Ben Motson Commentary Setup

Your app now features AI-driven insights from "Ben Motson" powered by Claude (Anthropic's AI).

## What It Does

**Leaderboard Page:**
- Analyzes current standings
- Understands your scoring system (progression points, knockout wins, multipliers)
- Provides strategic insights like: "If Argentina beats France in the final, Lewis will overtake Sam for first place!"

**Matches Page:**
- Comments on live matches with specific scores
- Analyzes finished knockout results
- Builds excitement for upcoming matches

## Setup Instructions

### 1. Get an Anthropic API Key

1. Go to https://console.anthropic.com/
2. Sign up or log in
3. Go to API Keys
4. Create a new API key
5. Copy it (you won't see it again!)

### 2. Add the API Key to Your App

**Option A: Using Environment Variable (Recommended for development)**

```bash
# Add to your .env file (create one if it doesn't exist)
echo "ANTHROPIC_API_KEY=your-api-key-here" >> .env
```

**Option B: Using Rails Credentials (Recommended for production)**

```bash
# Edit credentials
EDITOR="code --wait" rails credentials:edit

# Add this to the file:
anthropic:
  api_key: your-api-key-here

# Save and close
```

### 3. Restart Your Rails Server

```bash
rails s
```

### 4. Test It Out!

Visit your leaderboard or matches page and you should see AI-generated commentary!

## How It Works

The `BenMotsonService` class:
1. Gathers context (standings, scoring rules, upcoming matches)
2. Sends a detailed prompt to Claude AI
3. Receives strategic commentary back
4. Falls back to static messages if the API fails

## Cost

Using Claude 3.5 Haiku (the fastest, cheapest model):
- ~$0.001 per commentary generation
- You'll spend pennies even with heavy usage

## Troubleshooting

**No commentary showing up?**
- Check logs: `tail -f log/development.log`
- Verify API key is set: `rails c` then `ENV['ANTHROPIC_API_KEY']`
- Check for errors in console

**Want to customize the commentary?**
- Edit `app/services/ben_motson_service.rb`
- Modify the prompts to change Ben's personality or focus

## Disabling AI (Fallback Mode)

If you don't set up an API key, the app automatically falls back to simple static messages. Everything still works, just without the AI magic!
