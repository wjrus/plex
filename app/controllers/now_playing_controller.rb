class NowPlayingController < ApplicationController
  VIEW_MODES = %w[tiles compact].freeze

  def index
    load_sessions
    render partial: "sessions", layout: false if params[:partial].present?
  end

  private

  def load_sessions
    @view_mode = params[:view].presence_in(VIEW_MODES) || "tiles"
    sessions = Rails.cache.fetch("plex:now_playing", expires_in: 8.seconds) do
      Plex::Client.from_env.playback_sessions
    end
    @sessions = sort_sessions(sessions)
    @playing_sessions = @sessions.select { |stream| Plex::StreamFormatter.playing?(stream) }
    @paused_sessions = @sessions.select { |stream| Plex::StreamFormatter.paused?(stream) }
    @other_sessions = @sessions - @playing_sessions - @paused_sessions
    @fetched_at = Time.current
  rescue Plex::ConfigurationError, Plex::Client::Error => error
    @view_mode ||= "tiles"
    @plex_error = error.message
    @sessions = []
    @playing_sessions = []
    @paused_sessions = []
    @other_sessions = []
  end

  def sort_sessions(sessions)
    now = Time.current
    Array(sessions).sort_by do |stream|
      [
        -state_rank(stream),
        -Plex::StreamFormatter.started_at(stream, now: now).to_i,
        Plex::StreamFormatter.user_label(stream).downcase
      ]
    end
  end

  def state_rank(stream)
    return 2 if Plex::StreamFormatter.playing?(stream)
    return 1 if Plex::StreamFormatter.paused?(stream)

    0
  end
end
