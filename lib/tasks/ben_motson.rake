namespace :ben_motson do
  desc "Test Ben Motson AI commentary generation"
  task test_leaderboard: :environment do
    puts "\n" + "="*60
    puts "TESTING BEN MOTSON - LEADERBOARD ANALYSIS"
    puts "="*60 + "\n"

    service = BenMotsonService.new(:leaderboard)
    insight = service.generate_insight

    puts "Generated Insight:"
    puts "-" * 60
    puts insight
    puts "-" * 60
    puts "\n"

    if insight.include?("heating up") && insight.length < 100
      puts "⚠️  Using fallback - AI not configured"
      puts "\nTo enable AI commentary:"
      puts "1. Get an API key from https://console.anthropic.com/"
      puts "2. Set it: export ANTHROPIC_API_KEY=your-key"
      puts "3. Run this task again"
    else
      puts "✅ AI commentary generated successfully!"
    end

    puts "\n"
  end

  desc "Test Ben Motson match commentary"
  task test_matches: :environment do
    puts "\n" + "="*60
    puts "TESTING BEN MOTSON - MATCH COMMENTARY"
    puts "="*60 + "\n"

    finished_matches = Match.where(status: 'PostEvent').order(start_time: :desc).limit(5)

    if finished_matches.any?
      service = BenMotsonService.new(:matches, {
        matches: finished_matches,
        filter_type: 'PostEvent'
      })
      commentary = service.generate_insight

      puts "Generated Commentary:"
      puts "-" * 60
      puts commentary
      puts "-" * 60
    else
      puts "No finished matches found to analyze!"
    end

    puts "\n"
  end

  desc "Show current leaderboard data"
  task show_data: :environment do
    puts "\n" + "="*60
    puts "CURRENT LEADERBOARD DATA"
    puts "="*60 + "\n"

    groups = Group.includes(:teams, :friend).sort_by { |g| -g.total_points }

    groups.each_with_index do |group, i|
      puts "#{i+1}. #{group.friend.name}: #{group.total_points.to_i} points (×#{group.multiplier.to_i})"
      puts "   Teams: #{group.teams.map(&:name).join(', ')}"
      progressed = group.teams.select(&:progressed?)
      puts "   Progressed: #{progressed.map(&:name).join(', ')}" if progressed.any?
      puts ""
    end

    upcoming = Match.where(status: 'PreEvent')
                   .where.not(stage: 'Group Stage')
                   .where('start_time > ?', Time.current)
                   .order(:start_time)
                   .limit(5)

    if upcoming.any?
      puts "\nUPCOMING KNOCKOUT MATCHES:"
      upcoming.each do |match|
        home_friend = match.home_team.groups.first&.friend&.name || "None"
        away_friend = match.away_team.groups.first&.friend&.name || "None"
        puts "- #{match.stage}: #{match.home_team.name} (#{home_friend}) vs #{match.away_team.name} (#{away_friend})"
      end
    end

    puts "\n"
  end
end
