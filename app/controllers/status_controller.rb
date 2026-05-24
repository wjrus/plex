class StatusController < ApplicationController
  def index
    @machine_identifier = ENV["PLEX_MACHINE_IDENTIFIER"].presence
    @database_ok = database_ok?
    @latest_snapshot = @machine_identifier ? ShareSnapshot.latest_for(@machine_identifier) : ShareSnapshot.latest_first.first
    @latest_refresh = @machine_identifier ? RefreshRun.latest_for(@machine_identifier) : RefreshRun.latest_first.first
    @latest_audit_log = ShareAuditLog.recent.first
    @app_revision = app_revision
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.active?
  rescue ActiveRecord::ActiveRecordError
    false
  end

  def app_revision
    ENV["APP_REVISION"].presence ||
      ENV["GIT_SHA"].presence ||
      git_revision.presence ||
      "unknown"
  end

  def git_revision
    return unless Rails.root.join(".git").exist?

    `git rev-parse --short HEAD 2>/dev/null`.strip
  end
end
