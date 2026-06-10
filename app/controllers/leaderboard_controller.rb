class LeaderboardController < ApplicationController
  def index
    @groups = Group.includes(:friend, teams: [:home_matches, :away_matches])
                   .all
                   .sort_by { |group| -group.total_points }
    ctx = TournamentContextService.new
    @pivotal_matches = ctx.pivotal_matches(count: 3)
    @pivotal_scenarios = @pivotal_matches.each_with_object({}) do |match, h|
      h[match.id] = ScenarioEngine.new(match).call
    end
  end

  def show
    if params[:id] =~ /\A\d+\z/
      @group = Group.includes(teams: [:home_matches, :away_matches]).find(params[:id])
      render :group_detail
    else
      # Best penalty streak per friend — the official tie-breaker on points
      @best_streaks = GameScore.best_per_friend.to_h { |e| [e[:friend_id], e[:best_streak]] }
      @leaderboard = Group.includes(:friend, teams: [:home_matches, :away_matches])
                          .sort_by { |group| [-group.total_points, -(@best_streaks[group.friend_id] || 0)] }
      @ben_botcurdy_insight = BenBotcurdyService.new(:leaderboard).generate_insight
    end
  end

  def team
    @team = Team.find(params[:team_id])
    @matches = @team.matches.order(:start_time)
  end

  private

  def require_admin
    admin_password = ENV.fetch("ADMIN_PASSWORD", "onlymesucker!")
    authenticate_or_request_with_http_basic("Admin") do |_username, password|
      ActiveSupport::SecurityUtils.secure_compare(password, admin_password)
    end
  end
end
