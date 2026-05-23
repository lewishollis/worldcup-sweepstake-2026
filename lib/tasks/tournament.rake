namespace :tournament do
  desc "Create test tournament data for development"
  task create_test_data: :environment do
    puts "Creating test tournament data..."

    # Create test friends if they don't exist
    friends = [
      { name: "Alice", email: "alice@example.com" },
      { name: "Bob", email: "bob@example.com" },
      { name: "Charlie", email: "charlie@example.com" },
      { name: "Diana", email: "diana@example.com" }
    ].map do |attrs|
      Friend.find_or_create_by(email: attrs[:email]) do |f|
        f.name = attrs[:name]
      end
    end

    # Create test teams
    teams_data = [
      { name: "Brazil", group: "A" },
      { name: "Argentina", group: "A" },
      { name: "France", group: "B" },
      { name: "Germany", group: "B" },
      { name: "Spain", group: "C" },
      { name: "England", group: "C" },
      { name: "Portugal", group: "D" },
      { name: "Netherlands", group: "D" }
    ]

    teams = teams_data.each_with_index.map do |data, index|
      team = Team.find_or_create_by(name: data[:name]) do |t|
        t.group_name = data[:group]
        t.friend_id = friends[index % friends.length].id
      end
      puts "  Created #{team.name} (owned by #{team.friend.name})"
      team
    end

    # Create upcoming test matches
    matches_data = [
      { home: "Brazil", away: "Argentina", date: 2.days.from_now, stage: "Group Stage - Group A" },
      { home: "France", away: "Germany", date: 2.days.from_now, stage: "Group Stage - Group B" },
      { home: "Spain", away: "England", date: 3.days.from_now, stage: "Group Stage - Group C" },
      { home: "Portugal", away: "Netherlands", date: 3.days.from_now, stage: "Group Stage - Group D" },
      { home: "Brazil", away: "France", date: 5.days.from_now, stage: "Semi-Final 1" },
      { home: "Spain", away: "Portugal", date: 5.days.from_now, stage: "Semi-Final 2" }
    ]

    matches_data.each do |data|
      home_team = teams.find { |t| t.name == data[:home] }
      away_team = teams.find { |t| t.name == data[:away] }

      Match.find_or_create_by(
        home_team_id: home_team.id,
        away_team_id: away_team.id,
        start_time: data[:date]
      ) do |m|
        m.stage = data[:stage]
        m.status = 'PreEvent'
        m.home_score = 0
        m.away_score = 0
      end

      puts "  Created match: #{data[:home]} vs #{data[:away]} (#{data[:date].strftime('%b %d')})"
    end

    # Create some completed matches with results
    completed_matches = [
      { home: "Brazil", away: "Spain", home_score: 2, away_score: 1, stage: "Quarter Final 1" },
      { home: "Argentina", away: "England", home_score: 1, away_score: 2, stage: "Quarter Final 2" }
    ]

    completed_matches.each do |data|
      home_team = teams.find { |t| t.name == data[:home] }
      away_team = teams.find { |t| t.name == data[:away] }

      Match.find_or_create_by(
        home_team_id: home_team.id,
        away_team_id: away_team.id,
        start_time: 1.day.ago
      ) do |m|
        m.stage = data[:stage]
        m.status = 'PostEvent'
        m.home_score = data[:home_score]
        m.away_score = data[:away_score]
      end

      puts "  Created completed match: #{data[:home]} #{data[:home_score]}-#{data[:away_score]} #{data[:away]}"
    end

    puts "\n✅ Test tournament data created!"
    puts "\nFriends:"
    friends.each { |f| puts "  - #{f.name} (#{Team.where(friend_id: f.id).pluck(:name).join(', ')})" }
  end

  desc "Update a match result manually"
  task :update_match, [:match_id, :home_score, :away_score] => :environment do |t, args|
    match = Match.find(args[:match_id])

    match.update(
      home_score: args[:home_score].to_i,
      away_score: args[:away_score].to_i,
      status: 'PostEvent'
    )

    puts "✅ Updated match: #{match.home_team.name} #{match.home_score}-#{match.away_score} #{match.away_team.name}"
  end

  desc "List all upcoming matches"
  task list_upcoming: :environment do
    matches = Match.where(status: 'PreEvent').order(:start_time)

    puts "\n📅 Upcoming Matches:"
    matches.each do |match|
      puts "  [#{match.id}] #{match.home_team.name} vs #{match.away_team.name}"
      puts "      #{match.start_time.strftime('%b %d, %I:%M %p')} - #{match.stage}"
      puts ""
    end
  end

  desc "Generate AI insights for a friend"
  task :generate_insights, [:friend_id] => :environment do |t, args|
    friend = Friend.find(args[:friend_id])

    puts "\n🤖 Generating AI insights for #{friend.name}...\n"

    service = AiLeaderboardInsightsService.new(friend)
    result = service.generate_personalized_insight

    puts "Commentary:"
    puts result[:commentary]
    puts ""
    puts "Analysis:"
    puts "  Current Position: #{result[:analysis][:current_position]}"
    puts "  Current Points: #{result[:analysis][:current_points]}"
    puts "  Points Behind Leader: #{result[:analysis][:points_behind]}"

    if result[:analysis][:best_scenario]
      puts "  Best Scenario: #{result[:analysis][:best_scenario][:description]}"
      puts "  Would move to: #{result[:analysis][:best_scenario][:new_position]}"
    end
  end

  desc "Simulate a full World Cup tournament end-to-end (resets match data + team points)"
  task simulate: :environment do
    require Rails.root.join("lib", "tournament_simulation")

    if Group.count < 12
      puts "❌ Not enough groups (found #{Group.count}, need 12). Run db:seed first."
      next
    end

    print "\n⚠️  This will reset all match data and team points. Continue? (yes/no): "
    confirmation = STDIN.gets.chomp
    unless confirmation.downcase == "yes"
      puts "❌ Cancelled"
      next
    end

    puts "\n🔄 Resetting data..."
    Match.destroy_all
    Team.update_all(points: 0, progressed: false)
    AiInsightCache.destroy_all
    puts "✅ Reset complete\n"

    match_counter = 0
    stats = { group_stage: 0, last_16: 0, quarter_finals: 0, semi_finals: 0, third_place: 0, final: 0 }

    # ── Group Stage ──────────────────────────────────────────────────────────
    puts "⚽ Simulating Group Stage..."
    group_match_data = {}  # group_id => { teams: [], matches: [] }

    Group.includes(:teams).each do |group|
      teams   = group.teams.to_a
      matches = []

      teams.combination(2).each do |home_team, away_team|
        home_score = rand(0..3)
        away_score = rand(0..3)
        winner     = if home_score > away_score then "home" elsif away_score > home_score then "away" end

        match = Match.create!(
          home_team:   home_team,
          away_team:   away_team,
          home_score:  home_score,
          away_score:  away_score,
          winner:      winner,
          status:      "PostEvent",
          stage:       "Group Stage",
          start_time:  Time.now - rand(1..21).days,
          match_id:    "sim-gs-#{match_counter += 1}",
          home_points: 0,
          away_points: 0,
          result:      winner == "home" ? "W" : (winner == "away" ? "L" : "D")
        )
        matches << match
        stats[:group_stage] += 1
      end

      group_match_data[group.id] = { teams: teams, matches: matches }
    end
    puts "  ✅ #{stats[:group_stage]} matches\n"

    # ── Qualifiers: top team per group + best 4 runners-up ───────────────────
    puts "📊 Calculating group standings..."
    group_winners = []
    runners_up    = []

    group_match_data.each do |_group_id, data|
      sorted = TournamentSimulation.calculate_standings(data[:teams], data[:matches])
      group_winners << sorted[0]
      runners_up    << { team: sorted[1], stats: TournamentSimulation.standing_stats(sorted[1], data[:matches]) }
    end

    best_runners_up = runners_up
      .sort_by { |r| [-r[:stats][:pts], -r[:stats][:gd], -r[:stats][:gf]] }
      .first(4)
      .map { |r| r[:team] }

    qualifiers = (group_winners + best_runners_up).shuffle
    puts "  ✅ #{qualifiers.size} teams qualify\n"

    # ── Last 16 ───────────────────────────────────────────────────────────────
    puts "⚔️  Simulating Last 16..."
    last_16_winners = qualifiers.each_slice(2).map do |home, away|
      match = TournamentSimulation.simulate_knockout_match(home, away, "Last 16", match_counter += 1, "sim-l16")
      stats[:last_16] += 1
      match.winner == "home" ? home : away
    end
    puts "  ✅ #{stats[:last_16]} matches\n"

    # ── Quarter-finals ────────────────────────────────────────────────────────
    puts "⚔️  Simulating Quarter-finals..."
    qf_winners = last_16_winners.each_slice(2).map do |home, away|
      match = TournamentSimulation.simulate_knockout_match(home, away, "Quarter-finals", match_counter += 1, "sim-qf")
      stats[:quarter_finals] += 1
      match.winner == "home" ? home : away
    end
    puts "  ✅ #{stats[:quarter_finals]} matches\n"

    # ── Semi-finals ───────────────────────────────────────────────────────────
    puts "⚔️  Simulating Semi-finals..."
    sf_winners = []
    sf_losers  = []
    qf_winners.each_slice(2) do |home, away|
      match = TournamentSimulation.simulate_knockout_match(home, away, "Semi-finals", match_counter += 1, "sim-sf")
      stats[:semi_finals] += 1
      sf_winners << (match.winner == "home" ? home : away)
      sf_losers  << (match.winner == "home" ? away : home)
    end
    puts "  ✅ #{stats[:semi_finals]} matches\n"

    # ── 3rd Place Final ───────────────────────────────────────────────────────
    puts "🥉 Simulating 3rd Place Final..."
    TournamentSimulation.simulate_knockout_match(sf_losers[0], sf_losers[1], "3rd Place Final", match_counter += 1, "sim-3rd")
    stats[:third_place] = 1
    puts "  ✅ 1 match\n"

    # ── Final ─────────────────────────────────────────────────────────────────
    puts "🏆 Simulating Final..."
    final_match    = TournamentSimulation.simulate_knockout_match(sf_winners[0], sf_winners[1], "Final", match_counter += 1, "sim-final")
    stats[:final]  = 1
    champion       = final_match.winner == "home" ? sf_winners[0] : sf_winners[1]
    champion_owner = champion.groups.first&.friend
    puts "  ✅ 1 match\n"
  end

  desc "Reset all tournament data"
  task reset: :environment do
    print "⚠️  Are you sure you want to delete all tournament data? (yes/no): "
    confirmation = STDIN.gets.chomp

    if confirmation.downcase == 'yes'
      Match.destroy_all
      Team.update_all(friend_id: nil)
      puts "✅ Tournament data reset"
    else
      puts "❌ Cancelled"
    end
  end
end
