Rails.application.routes.draw do
  # Define routes for MatchesController
  resources :matches, only: [:index, :show]

  # Define routes for LeaderboardController
  resources :leaderboard, only: [:index, :show] do
    patch :update_team_progress, on: :member
    get :team, on: :collection
  end

  # Game routes
  get  '/game',        to: 'games#index'
  post '/game/scores', to: 'games#create'
  get  '/game/scores', to: 'games#scores'

  # Set root route
  root 'matches#index'
end
