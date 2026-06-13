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
            home_team = Team.find_or_create_by(name: Team.canonical_name(event['home']['fullName']))
            away_team = Team.find_or_create_by(name: Team.canonical_name(event['away']['fullName']))

            home_friend = home_team.groups.first&.friend
            away_friend = away_team.groups.first&.friend

            home_friend_profile_picture_url = home_friend.profile_picture_url if home_friend.present?
            away_friend_profile_picture_url = away_friend.profile_picture_url if away_friend.present?

            home_friend_name = home_friend&.name || 'No owner'
            away_friend_name = away_friend&.name || 'No owner'

            stage = event['stage'] || { 'name' => 'Unknown Stage' }

            match = Match.find_or_initialize_by(match_id: event['id'])
            status = BbcEventParser.merge_status(BbcEventParser.status(event), match.status)
            winner = status == 'MidEvent' ? nil : (BbcEventParser.winner(event) || match.winner)

            match.assign_attributes(
              home_team: home_team,
              away_team: away_team,
              start_time: event['date']['iso'],
              match_id: event['id'],
              stage: stage['name'],
              group_name: BbcEventParser.group_name(event, secondary_group['displayLabel']),
              home_friend_name: home_friend_name,
              away_friend_name: away_friend_name,
              home_friend_profile_picture_url: home_friend_profile_picture_url,
              away_friend_profile_picture_url: away_friend_profile_picture_url,
              home_score: BbcEventParser.home_score(event) || match.home_score || 0,
              away_score: BbcEventParser.away_score(event) || match.away_score || 0,
              status: status,
              winner: winner,
              accessible_event_summary: event['accessibleEventSummary']
            )
            match.save! if match.new_record? || match.changed?

            # Render-only: not persisted, so a genuinely delayed or postponed
            # match falls back to upcoming once the window passes.
            if match.status == 'PreEvent' && BbcEventParser.presumed_live?(event)
              match.status = 'MidEvent'
            end

            if @filter_params['MidEvent'] == '1' && match.status == 'MidEvent'
              cards = BbcLineupsService.cards(match.match_id)
              match.live_clock = event.dig('periodLabel', 'value')
              match.home_events = BbcEventParser.sort_by_minute(BbcEventParser.side_events(event, 'home') + cards[:home])
              match.away_events = BbcEventParser.sort_by_minute(BbcEventParser.side_events(event, 'away') + cards[:away])
            end

            @matches << match
          end
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

      if @matches.any? && @filter_params.present?
        filter_type = @filter_params.find { |k, v| v == '1' }&.first
        if filter_type == 'PreEvent'
          @upcoming_summary = UpcomingMatchesInsightService.call(@matches)
        elsif filter_type == 'PostEvent'
          @leaderboard_standings = Group.includes(:friend, teams: [:home_matches, :away_matches])
                                        .all
                                        .sort_by { |g| -g.total_points }
        end
        # MidEvent: no AI commentary
      end
    else
      @error_message = "Failed to fetch match data: #{response.code} - #{response.message}"
    end
  end

  def show
    @match = Match.includes(:home_team, :away_team).find(params[:id])
    if @match.status == "PreEvent"
      @scenarios = ScenarioEngine.new(@match).call
      @match_insight = MatchInsightService.cached_call(@match)
    end
  end

  private

  def filter_params
    params.fetch(:filter, {}).permit(:PostEvent, :MidEvent, :PreEvent).to_h
  end
end
