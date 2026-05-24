class PlexRefreshJob < ApplicationJob
  queue_as :default

  def perform(refresh_run_id)
    refresh_run = RefreshRun.find(refresh_run_id)
    refresh_run.update!(status: "running", started_at: Time.current, last_message: "Refresh started")

    snapshot = Plex::SnapshotRefresh.new(
      client: Plex::Client.from_env,
      machine_identifier: refresh_run.machine_identifier,
      include_history: refresh_run.include_history,
      progress: Plex::RefreshProgressRecorder.new(refresh_run)
    ).call

    refresh_run.update!(
      status: "completed",
      share_snapshot_id: snapshot.id,
      finished_at: Time.current,
      last_message: "Saved snapshot ##{snapshot.id}"
    )
  rescue StandardError => error
    refresh_run&.update!(
      status: "failed",
      finished_at: Time.current,
      error_message: error.message,
      last_message: "Refresh failed"
    )
    raise
  end
end
