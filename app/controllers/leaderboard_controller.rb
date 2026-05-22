class LeaderboardController < ApplicationController
  before_action :require_admin, only: [:update_team_progress]

  def index
    @groups = Group.includes(:teams, :friend).all.sort_by { |group| -group_total_points(group) }
  end

  def show
    if params[:id] =~ /\A\d+\z/
      @group = Group.includes(:teams).find(params[:id])
      render :group_detail
    else
      @leaderboard = Group.includes(:friend).sort_by { |group| -group.total_points }
      @ben_motson_insight = BenMotsonService.new(:leaderboard).generate_insight
    end
  end



  def team
    @team = Team.find(params[:team_id])
    @matches = @team.matches.order(:start_time)
  end

  def update_team_progress
    team = Team.find(params[:id])
    was_progressed = team.progressed?
    new_progressed = !was_progressed

    if new_progressed && !was_progressed
      team.update!(progressed: true, points: (team.points || 0) + 1)
    elsif !new_progressed && was_progressed
      team.update!(progressed: false, points: [(team.points || 0) - 1, 0].max)
    end

    redirect_to leaderboard_index_path
  end

  private

  def require_admin
    admin_password = ENV.fetch("ADMIN_PASSWORD", "onlymesucker!")
    authenticate_or_request_with_http_basic("Admin") do |_username, password|
      ActiveSupport::SecurityUtils.secure_compare(password, admin_password)
    end
  end

  def group_total_points(group)
    group.teams.sum(&:points).to_i
  end
end
