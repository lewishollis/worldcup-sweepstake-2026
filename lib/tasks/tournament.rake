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
