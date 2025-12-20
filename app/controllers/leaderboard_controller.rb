class LeaderboardController < ApplicationController
  def index
    @groups = Group.includes(:teams, :friend).all.sort_by { |group| -group_total_points(group) }
  end

  def show
    @leaderboard = Group.includes(:friend).sort_by { |group| -group.total_points }
    @ben_motson_insight = BenMotsonService.new(:leaderboard).generate_insight
  end



  def update_team_progress
    team = Team.find(params[:id])
    was_progressed = team.progressed?
    new_progressed = !was_progressed

    # Update progressed status
    team.update(progressed: new_progressed)

    # Award or remove the progression point
    if new_progressed && !was_progressed
      # Team is now progressed, add 1 point
      team.update(points: (team.points || 0) + 1)
    elsif !new_progressed && was_progressed
      # Team is no longer progressed, remove 1 point
      team.update(points: [(team.points || 0) - 1, 0].max)
    end

    redirect_to leaderboard_index_path
  end

  private

  def group_total_points(group)
    group.teams.sum(&:points).to_i
  end
end
