class NowPlayingController < ApplicationController
  def index
    load_sessions
    render partial: "sessions", layout: false if params[:partial].present?
  end

  private

  def load_sessions
    @sessions = Rails.cache.fetch("plex:now_playing", expires_in: 8.seconds) do
      Plex::Client.from_env.playback_sessions
    end
    @fetched_at = Time.current
  rescue Plex::ConfigurationError, Plex::Client::Error => error
    @plex_error = error.message
    @sessions = []
  end
end
