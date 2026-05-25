Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  match "/auth/google_oauth2/callback", to: "sessions#create", via: [ :get, :post ]
  match "/auth/failure", to: "sessions#failure", via: [ :get, :post ]
  get "/sign_in", to: "sessions#new", as: :sign_in
  delete "/sign_out", to: "sessions#destroy", as: :sign_out

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "shares#index"
  get "now", to: "now_playing#index", as: :now_playing
  get "log", to: "share_audit_logs#index", as: :share_audit_logs
  get "status", to: "status#index", as: :status
  get "users", to: "users#index", as: :users
  get "users/:plex_user_id", to: "users#show", as: :user
  patch "users/:plex_user_id/note", to: "users#update_note", as: :user_note
  post "refresh", to: "shares#refresh", as: :refresh_shares
  post "shares", to: "shares#create"
  post "shares/bulk", to: "shares#bulk_update", as: :bulk_shares
  patch "shares/:share_id", to: "shares#update", as: :share
  delete "shares/:share_id", to: "shares#destroy"
  delete "invites/:invite_id", to: "shares#destroy_invite", as: :pending_invite
end
