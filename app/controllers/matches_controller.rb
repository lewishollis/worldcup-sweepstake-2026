class MatchesController < ApplicationController
  def index
    @filter_params = filter_params
    if @filter_params.blank?
      redirect_to matches_path(filter: { PreEvent: '1' }) and return
    end
    today_date = Time.now.strftime("%Y-%m-%d")
    url = URI("https://web-cdn.api.bbci.co.uk/wc-poll-data/container/sport-data-scores-fixtures?selectedEndDate=2026-07-19&selectedStartDate=2026-06-01&todayDate=#{today_date}&urn=urn%3Abbc%3Asportsdata%3Afootball%3Atournament%3Aworld-cup")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Get.new(url)
    request["accept"] = 'application/json'

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      @matches = []

      unless data['eventGroups'].is_a?(Array)
        @error_message = "Unexpected response from match data source."
        return
      end

      data['eventGroups'].each do |event_group|
        event_group['secondaryGroups'].each do |secondary_group|
          secondary_group['events'].each do |event|
            home_team = Team.find_or_create_by(name: event['home']['fullName'])
            away_team = Team.find_or_create_by(name: event['away']['fullName'])

            home_friend = home_team.groups.first&.friend
            away_friend = away_team.groups.first&.friend

            home_friend_profile_picture_url = home_friend.profile_picture_url if home_friend.present?
            away_friend_profile_picture_url = away_friend.profile_picture_url if away_friend.present?

            home_friend_name = home_friend&.name || 'No owner'
            away_friend_name = away_friend&.name || 'No owner'

            stage = event['stage'] || { 'name' => 'Unknown Stage' }

            if event['status'] == 'MidEvent'
              winner = nil
            else
              winner = event['winner']
            end

            match = Match.find_or_initialize_by(match_id: event['id'])
            match.assign_attributes(
              home_team: home_team,
              away_team: away_team,
              start_time: event['date']['iso'],
              match_id: event['id'],
              stage: stage['name'],
              home_friend_name: home_friend_name,
              away_friend_name: away_friend_name,
              home_friend_profile_picture_url: home_friend_profile_picture_url,
              away_friend_profile_picture_url: away_friend_profile_picture_url,
              home_score: event['home']['score'].to_i,
              away_score: event['away']['score'].to_i,
              status: event['status'],
              winner: winner,
              accessible_event_summary: event['accessibleEventSummary']
            )

            if match.new_record?
              assign_points(match)
              match.save!
            end

            @matches << match
          end
        end
      end

      # Recalculate points only for matches that have changed.
      # Reverse previously awarded match points before applying the new calculation
      # to prevent points accumulating across page loads.
      @matches.each do |match|
        if match.persisted? && match.changed?
          prev_home_pts = match.home_points.to_i
          prev_away_pts = match.away_points.to_i

          assign_points(match)

          # Subtract what was previously awarded so the net change is correct
          update_team_points(match.home_team, -prev_home_pts) if prev_home_pts > 0
          update_team_points(match.away_team, -prev_away_pts) if prev_away_pts > 0

          match.save!
        end
      end

      if @filter_params.present?
        @matches.select! do |match|
          (@filter_params['PostEvent'] == '1' && match.status == 'PostEvent') ||
          (@filter_params['MidEvent'] == '1' && match.status == 'MidEvent') ||
          (@filter_params['PreEvent'] == '1' && match.status == 'PreEvent')
        end
      end

      @matches.sort_by! { |match| match.start_time } if @filter_params['PostEvent'] == '1'
      @matches.reverse! if @filter_params['PostEvent'] == '1'

      # Generate AI insight for matches
      if @matches.any? && @filter_params.present?
        filter_type = @filter_params.find { |k, v| v == '1' }&.first
        if filter_type == 'PreEvent'
          result = UpcomingMatchesInsightService.call(@matches)
          @upcoming_summary = result[:summary]
          @match_insights = result[:per_match]
        else
          @ben_botcurdy_commentary = BenBotcurdyService.new(:matches, {
            matches: @matches,
            filter_type: filter_type
          }).generate_insight
        end
      end
    else
      @error_message = "Failed to fetch match data: #{response.code} - #{response.message}"
    end
  end

  def show
    @match = Match.includes(:home_team, :away_team).find(params[:id])
    if @match.status == "PreEvent"
      @scenarios = ScenarioEngine.new(@match).call
      if @match.stage == "Group Stage"
        result = UpcomingMatchesInsightService.call([@match])
        @match_insight = result[:per_match][@match.match_id]
      else
        @match_insight = MatchInsightService.cached_call(@match)
      end
    end
  end

  private

  def filter_params
    params.fetch(:filter, {}).permit(:PostEvent, :MidEvent, :PreEvent).to_h
  end

  def assign_points(match)
    puts "Assigning points for match: #{match.inspect}"

    stage = match.stage

    # Automatically mark teams as progressed and award 1 point if they're playing in knockout stages
    knockout_stages = ['Last 16', 'Quarter-finals', 'Semi-finals', 'Final', '3rd Place Final']
    if knockout_stages.include?(stage)
      unless match.home_team.progressed?
        match.home_team.update(progressed: true)
        update_team_points(match.home_team, 1)
        puts "#{match.home_team.name} marked as progressed and awarded 1 point for progression"
      end
      unless match.away_team.progressed?
        match.away_team.update(progressed: true)
        update_team_points(match.away_team, 1)
        puts "#{match.away_team.name} marked as progressed and awarded 1 point for progression"
      end
    end

    case stage
    when 'Group Stage'
      match.home_points = 0
      match.away_points = 0
      puts "Group Stage match. No points awarded."
    when 'Last 16', 'Quarter-finals', 'Semi-finals', '3rd Place Final'
      if match.winner == 'home'
        match.home_points = 1
        match.away_points = 0
        match.result = 'W'
        puts "Home team wins #{stage}. Home points: #{match.home_points}, Away points: #{match.away_points}"
      elsif match.winner == 'away'
        match.home_points = 0
        match.away_points = 1
        match.result = 'L'
        puts "Away team wins #{stage}. Home points: #{match.home_points}, Away points: #{match.away_points}"
      else
        match.home_points = 0
        match.away_points = 0
        match.result = 'D'
        puts "Draw in #{stage}. Home points: #{match.home_points}, Away points: #{match.away_points}"
      end
    when 'Final'
      if match.winner == 'home'
        match.home_points = 2
        match.away_points = 1
        match.result = 'W'
        puts "Home team wins Final. Home points: #{match.home_points}, Away points: #{match.away_points}"
      elsif match.winner == 'away'
        match.home_points = 1
        match.away_points = 2
        match.result = 'L'
        puts "Away team wins Final. Home points: #{match.home_points}, Away points: #{match.away_points}"
      else
        match.home_points = 0
        match.away_points = 0
        match.result = 'D'
        puts "Draw in Final. Home points: #{match.home_points}, Away points: #{match.away_points}"
      end
    else
      match.home_points = 0
      match.away_points = 0
      match.result = 'TBC'
      puts "Unknown stage. No points awarded. Stage: #{stage}"
    end

    update_team_points(match.home_team, match.home_points)
    update_team_points(match.away_team, match.away_points)
  end

  def update_team_points(team, points)
    puts "Updating team points: Team: #{team.name}, Current Points: #{team.points}, Points to Add: #{points}"
    team.points = (team.points || 0) + points
    team.save!
    puts "New team points: Team: #{team.name}, Updated Points: #{team.points}"
  end
end
