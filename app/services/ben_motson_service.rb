class BenMotsonService
  def initialize(context_type, context_data = {})
    @context_type = context_type # :leaderboard or :matches
    @context_data = context_data
  end

  def generate_insight
    # AI disabled - using free fallback messages
    # To enable AI: Set ANTHROPIC_API_KEY environment variable
    fallback_insight
  end

  private

  def build_comprehensive_prompt
    case @context_type
    when :leaderboard
      build_leaderboard_prompt
    when :matches
      build_matches_prompt
    end
  end

  def build_leaderboard_prompt
    groups = Group.includes(:teams, :friend).sort_by { |g| -g.total_points }
    leader = groups.first
    upcoming_knockout_matches = Match.where(status: 'PreEvent')
                                     .where.not(stage: 'Group Stage')
                                     .where('start_time > ?', Time.current)
                                     .order(:start_time)
                                     .limit(5)

    prompt = []
    prompt << "You are Ben Motson, an enthusiastic sports commentator analyzing a World Cup sweepstake competition."
    prompt << ""
    prompt << "SCORING SYSTEM:"
    prompt << "- Progression from Group Stage: 1 point (one-time)"
    prompt << "- Round of 16 win: 1 point"
    prompt << "- Quarter Final win: 1 point"
    prompt << "- Semi Final win: 1 point"
    prompt << "- Final winner: 2 points, runner-up: 1 point"
    prompt << "- Bronze Final win: 1 point"
    prompt << "- Each friend has a multiplier (×2 to ×6) applied to their team's total points"
    prompt << ""
    prompt << "CURRENT STANDINGS:"
    groups.first(5).each_with_index do |group, i|
      prompt << "#{i+1}. #{group.friend.name}: #{group.total_points.to_i} points (×#{group.multiplier.to_i} multiplier)"
      prompt << "   Teams: #{group.teams.map(&:name).join(', ')}"
      progressed = group.teams.select(&:progressed?)
      prompt << "   Progressed to knockouts: #{progressed.map(&:name).join(', ')}" if progressed.any?
    end
    prompt << ""

    if upcoming_knockout_matches.any?
      prompt << "UPCOMING KNOCKOUT MATCHES:"
      upcoming_knockout_matches.each do |match|
        home_friend = match.home_team.groups.first&.friend&.name || "No owner"
        away_friend = match.away_team.groups.first&.friend&.name || "No owner"
        prompt << "- #{match.stage}: #{match.home_team.name} (#{home_friend}) vs #{match.away_team.name} (#{away_friend})"
      end
      prompt << ""
    end

    prompt << "Generate 2-3 sentences of exciting commentary that:"
    prompt << "1. Acknowledges the current leader and their position"
    prompt << "2. Mentions a specific upcoming match and what's at stake"
    prompt << "3. Creates excitement about who might win"
    prompt << ""
    prompt << "Be specific with names and scenarios. Make it feel like live sports commentary!"
    prompt << "Keep it under 60 words."

    prompt.join("\n")
  end

  def build_matches_prompt
    matches = @context_data[:matches]
    filter_type = @context_data[:filter_type]

    prompt = []
    prompt << "You are Ben Motson, an enthusiastic World Cup commentator."
    prompt << ""

    case filter_type
    when 'MidEvent'
      live_matches = matches.select { |m| m.status == 'MidEvent' }
      prompt << "#{live_matches.count} match(es) are currently LIVE!"
      prompt << ""
      live_matches.first(3).each do |match|
        prompt << "- #{match.home_team.name} #{match.home_score} - #{match.away_score} #{match.away_team.name} (#{match.stage})"
      end
      prompt << ""
      prompt << "Generate 1-2 exciting sentences about the live action. Mention specific teams and scores!"

    when 'PostEvent'
      finished_matches = matches.select { |m| m.status == 'PostEvent' }
      knockout_matches = finished_matches.reject { |m| m.stage == 'Group Stage' }

      if knockout_matches.any?
        prompt << "RECENT KNOCKOUT RESULTS:"
        knockout_matches.first(3).each do |match|
          winner = match.winner == 'home' ? match.home_team.name : match.away_team.name
          prompt << "- #{match.stage}: #{match.home_team.name} #{match.home_score} - #{match.away_score} #{match.away_team.name} (#{winner} wins!)"
        end
        prompt << ""
        prompt << "Generate 1-2 sentences analyzing these knockout results. Be dramatic and specific!"
      else
        prompt << "#{finished_matches.count} matches completed."
        prompt << ""
        prompt << "Generate 1 sentence summing up the recent action."
      end

    when 'PreEvent'
      upcoming = matches.select { |m| m.status == 'PreEvent' }
      prompt << "#{upcoming.count} upcoming match(es)!"
      prompt << ""
      upcoming.first(3).each do |match|
        prompt << "- #{match.home_team.name} vs #{match.away_team.name} (#{match.stage}) at #{match.start_time.strftime('%H:%M')}"
      end
      prompt << ""
      prompt << "Generate 1-2 sentences building excitement for these upcoming matches!"
    end

    prompt << ""
    prompt << "Keep it under 40 words. Make it punchy and exciting!"

    prompt.join("\n")
  end

  def call_claude_api(prompt)
    require 'net/http'
    require 'json'

    api_key = ENV['ANTHROPIC_API_KEY'] || Rails.application.credentials.dig(:anthropic, :api_key)

    return nil unless api_key

    uri = URI('https://api.anthropic.com/v1/messages')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path)
    request['x-api-key'] = api_key
    request['anthropic-version'] = '2023-06-01'
    request['content-type'] = 'application/json'

    request.body = {
      model: 'claude-3-5-haiku-20241022',
      max_tokens: 150,
      messages: [{ role: 'user', content: prompt }]
    }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    result.dig('content', 0, 'text')
  rescue => e
    Rails.logger.error("Claude API call failed: #{e.message}")
    nil
  end

  def fallback_insight
    case @context_type
    when :leaderboard
      groups = Group.includes(:friend, :teams).sort_by { |g| -g.total_points }
      leader = groups.first
      second = groups[1]

      upcoming_knockout = Match.where(status: 'PreEvent')
                               .where.not(stage: 'Group Stage')
                               .where('start_time > ?', Time.current)
                               .order(:start_time)
                               .first

      if upcoming_knockout
        home_friend = upcoming_knockout.home_team.groups.first&.friend&.name
        away_friend = upcoming_knockout.away_team.groups.first&.friend&.name
        "#{leader.friend.name} leads with #{leader.total_points.to_i} points! Next up: #{upcoming_knockout.home_team.name}#{home_friend ? " (#{home_friend})" : ''} faces #{upcoming_knockout.away_team.name}#{away_friend ? " (#{away_friend})" : ''} in the #{upcoming_knockout.stage}. Everything could change!"
      elsif second
        gap = leader.total_points - second.total_points
        "#{leader.friend.name} is dominating with #{leader.total_points.to_i} points, #{gap.to_i} points ahead of #{second.friend.name}. Can anyone catch them?"
      else
        "#{leader.friend.name} is leading with #{leader.total_points.to_i} points! The race is on!"
      end

    when :matches
      filter = @context_data[:filter_type]
      matches = @context_data[:matches] || []
      count = matches.count

      case filter
      when 'MidEvent'
        live = matches.select { |m| m.status == 'MidEvent' }.first
        if live
          "#{live.home_team.name} #{live.home_score} - #{live.away_score} #{live.away_team.name} and #{count - 1} more #{'match'.pluralize(count - 1)} in progress! The tension is electric!"
        else
          "#{count} #{'match'.pluralize(count)} LIVE right now! Incredible action across the tournament!"
        end

      when 'PostEvent'
        knockout = matches.reject { |m| m.stage == 'Group Stage' }.first
        if knockout
          winner = knockout.winner == 'home' ? knockout.home_team.name : knockout.away_team.name
          "What a #{knockout.stage}! #{knockout.home_team.name} #{knockout.home_score} - #{knockout.away_score} #{knockout.away_team.name}. #{winner} marches on!"
        else
          "#{count} #{'match'.pluralize(count)} completed. Some thrilling results in there!"
        end

      when 'PreEvent'
        upcoming = matches.first
        if upcoming
          "#{upcoming.home_team.name} vs #{upcoming.away_team.name} kicks off soon! #{count} exciting #{'match'.pluralize(count)} on the horizon."
        else
          "#{count} #{'match'.pluralize(count)} coming up. Get ready for the action!"
        end
      end
    end
  end
end
