Rails.application.routes.draw do
  get "up"     => "rails/health#show", as: :rails_health_check
  get "health" => "health#show"

  namespace :api do
    namespace :v1 do
      post "auth/wechat" => "auth#wechat"

      post "trips/match/run" => "trips#run_match"
      resources :trips, only: [ :create, :show ]
    end
  end
end
