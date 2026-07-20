class GamesController < ApplicationController
  before_action :require_admin, only: :audit

  def index
    @friends = Friend.all.order(:name)
    @leaderboard = leaderboard_data
    @game_locked = GameScore.locked?
    @game_deadline = GameScore::DEADLINE
  end

  def create
    if GameScore.locked?
      render json: { error: "The penalty game is closed", locked: true }, status: :forbidden
      return
    end

    friend = Friend.find_by(id: score_params[:friend_id])

    if friend.nil?
      render json: { error: "Friend not found" }, status: :unprocessable_entity
      return
    end

    score = GameScore.new(
      friend: friend,
      streak: score_params[:streak],
      device_id: score_params[:device_id]
    )

    if score.save
      render json: leaderboard_data
    else
      render json: { errors: score.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def scores
    render json: leaderboard_data
  end

  # Admin-only audit: every device that has played, with multi-friend ones flagged.
  def audit
    @devices = GameScore.device_summary
  end

  private

  def require_admin
    admin_password = ENV.fetch("ADMIN_PASSWORD", "onlymesucker!")
    authenticate_or_request_with_http_basic("Admin") do |_username, password|
      ActiveSupport::SecurityUtils.secure_compare(password, admin_password)
    end
  end

  def score_params
    params.permit(:friend_id, :streak, :device_id)
  end

  def leaderboard_data
    GameScore.best_per_friend.map do |entry|
      {
        friend_id: entry[:friend_id],
        friend_name: entry[:friend].name,
        friend_picture_url: entry[:friend].profile_picture_url,
        best_streak: entry[:best_streak],
        first_achieved: entry[:first_achieved]
      }
    end
  end
end
