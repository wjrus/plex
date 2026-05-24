class PlexRefreshJob < ApplicationJob
  queue_as :default

  def perform(refresh_run_id)
    refresh_run = RefreshRun.find(refresh_run_id)
    refresh_run.update!(status: "running", started_at: Time.current, last_message: "Refresh started")

    snapshot = Plex::SnapshotRefresh.new(
      client: Plex::Client.from_env,
      machine_identifier: refresh_run.machine_identifier,
      include_history: refresh_run.include_history,
      progress: ->(event) { record_progress(refresh_run, event) }
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

  private

  def record_progress(refresh_run, event)
    if event[:phase] == "account"
      refresh_run.update!(
        account_lookups_completed: event.fetch(:index),
        account_lookups_total: event.fetch(:total),
        history_users_matched: event.fetch(:matches),
        history_users_remaining: event.fetch(:remaining),
        last_message: "Account lookup #{event.fetch(:index)}/#{event.fetch(:total)}: #{event.fetch(:label)}"
      )
    else
      refresh_run.update!(
        history_pages_retrieved: event.fetch(:page),
        history_rows_retrieved: refresh_run.history_rows_retrieved + event.fetch(:rows),
        history_users_matched: event.fetch(:matches),
        history_users_remaining: event.fetch(:remaining),
        last_message: page_message(event)
      )
    end

    ShareSnapshot.checkpoint_streams!(refresh_run.machine_identifier, event[:streams])
  end

  def page_message(event)
    message = "History page #{event.fetch(:page)} retrieved"
    message += " (#{event.fetch(:stop_reason)})" if event[:stop_reason].present?
    message
  end
end
