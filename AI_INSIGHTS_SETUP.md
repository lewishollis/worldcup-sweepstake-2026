# AI Leaderboard Insights Setup Guide

## Overview

This system analyzes the leaderboard and tells each friend what results they need to climb the rankings.

**Example output:**
> "You're in 3rd place, just 6 points behind the leader! If Brazil beats Argentina tomorrow, you'll jump to 1st place. Even better—if France loses to Germany, you'll extend your lead!"

## How It Works

### 1. Mathematical Analysis (`LeaderboardScenarioAnalyzer`)
- Calculates current standings
- Analyzes all upcoming matches
- Projects different outcomes (what if X team wins?)
- Finds which results benefit each friend most

### 2. AI Commentary (`AiLeaderboardInsightsService`)
- Takes the math analysis
- Uses Claude AI (or OpenAI/Gemini) to generate engaging commentary
- Personalizes the message for each friend
- Makes it fun and strategic

## Setup Instructions

### Step 1: Add API Key

```bash
# Edit Rails credentials
EDITOR="code --wait" bin/rails credentials:edit

# Add your API key:
anthropic:
  api_key: sk-ant-xxxxx

# Or for OpenAI:
openai:
  api_key: sk-xxxxx
```

### Step 2: Create Test Tournament Data

```bash
# Create friends, teams, and matches
bin/rails tournament:create_test_data
```

This creates:
- 4 test friends (Alice, Bob, Charlie, Diana)
- 8 teams (Brazil, Argentina, France, etc.)
- Upcoming matches
- Some completed matches

### Step 3: Test the AI Insights

```bash
# List all friends
bin/rails console
Friend.all.each { |f| puts "#{f.id}: #{f.name}" }
exit

# Generate insights for a friend (use their ID)
bin/rails tournament:generate_insights[1]
```

You'll see output like:
```
🤖 Generating AI insights for Alice...

Commentary:
Alice, you're sitting in 3rd place with 12 points, just 5 points behind the leader!
Your path to the top is clear: root for Brazil to beat Argentina in 2 days.
That single result would catapult you to 1st place—time to become Brazil's biggest fan!

Analysis:
  Current Position: 3
  Current Points: 12
  Points Behind Leader: 5
  Best Scenario: Brazil beats Argentina
  Would move to: 1
```

### Step 4: Manually Update Match Results

```bash
# List upcoming matches to get IDs
bin/rails tournament:list_upcoming

# Update a match result (match_id, home_score, away_score)
bin/rails tournament:update_match[1,2,1]
```

### Step 5: Display in Your App

Add to your leaderboard or matches view:

```erb
<!-- app/views/leaderboard/show.html.erb -->
<% if current_user_friend %>
  <% insight = AiLeaderboardInsightsService.new(current_user_friend).generate_personalized_insight %>

  <div class="commentary-box mb-6">
    <div class="commentary-header">
      <i class="fas fa-robot commentary-icon"></i>
      <h3 class="commentary-title">Your Strategic Insight</h3>
    </div>
    <p class="commentary-text">
      <%= insight[:commentary] %>
    </p>
  </div>
<% end %>
```

## Usage Examples

### Manually Create a Match

```ruby
# In Rails console
Match.create!(
  home_team: Team.find_by(name: "Brazil"),
  away_team: Team.find_by(name: "France"),
  start_time: 3.days.from_now,
  stage: "Final",
  status: "PreEvent",
  home_score: 0,
  away_score: 0
)
```

### Update Match to "Live"

```ruby
match = Match.find(1)
match.update(
  status: "MidEvent",
  home_score: 1,
  away_score: 1
)
```

### Mark Match as Finished

```ruby
match = Match.find(1)
match.update(
  status: "PostEvent",
  home_score: 2,
  away_score: 1
)
```

### Test Different Scenarios

```ruby
friend = Friend.find(1)
analyzer = LeaderboardScenarioAnalyzer.new(friend)
analysis = analyzer.analyze_path_to_top

puts "Current position: #{analysis[:current_position]}"
puts "Points behind: #{analysis[:points_behind]}"

if analysis[:best_scenario]
  puts "Best outcome: #{analysis[:best_scenario][:description]}"
  puts "Would move to: #{analysis[:best_scenario][:new_position]}"
end
```

## Customization

### Change the AI Model

Edit `app/services/ai_leaderboard_insights_service.rb`:

```ruby
# For cheaper/faster (Haiku)
model: 'claude-3-5-haiku-20241022'

# For better quality (Sonnet)
model: 'claude-3-5-sonnet-20241022'

# For OpenAI
model: 'gpt-4o-mini'
```

### Adjust Scoring System

Edit the `calculate_team_points` method in `LeaderboardScenarioAnalyzer`:

```ruby
def calculate_team_points(team)
  # Example: 5 points for win, 2 for draw, bonus for knockout stages
  team.matches.where(status: 'PostEvent').sum do |match|
    points = 0
    is_winner = (match.home_team_id == team.id && match.home_score > match.away_score) ||
                (match.away_team_id == team.id && match.away_score > match.home_score)

    if is_winner
      points += match.stage.include?("Final") ? 10 : 5
    elsif match.home_score == match.away_score
      points += 2
    end

    points
  end
end
```

## When Tournament Starts

1. **Clear test data**: `bin/rails tournament:reset`
2. **Import real tournament structure**: Create matches from official schedule
3. **Assign friends to teams**: Update `Team.friend_id`
4. **Let AI generate insights**: It will automatically analyze real matchups

## API Costs (Approximate)

- **Claude Haiku**: ~$0.0001 per insight (very cheap!)
- **GPT-4o-mini**: ~$0.0002 per insight
- **Claude Sonnet**: ~$0.001 per insight

For 4 friends checking 10 times/day = $0.04/day with Haiku 💰

## Troubleshooting

**"No API key found"**
```bash
EDITOR="code --wait" bin/rails credentials:edit
# Add your anthropic or openai key
```

**"No upcoming matches"**
```bash
bin/rails tournament:create_test_data
```

**"AI returns generic message"**
- Check your API key is correct
- Try with a friend who has teams playing upcoming matches
- Check Rails logs for API errors

## Next Steps

1. **Add caching**: Cache insights for 5-10 minutes
2. **Background jobs**: Generate insights automatically
3. **Email notifications**: Send daily strategic updates
4. **Multi-scenario analysis**: "Here are your top 3 scenarios"

Enjoy your AI-powered sweepstake! 🏆🤖
