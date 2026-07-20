Rails.application.routes.draw do
  resources :matches, only: [:index, :show]

  resources :leaderboard, only: [:index, :show] do
    get :team, on: :collection
  end

  get  '/game',        to: 'games#index'
  post '/game/scores', to: 'games#create'
  get  '/game/scores', to: 'games#scores'
  get  '/game/audit',  to: 'games#audit'

  root 'matches#index'
end
