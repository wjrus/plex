module Plex
  class RefreshProgressRecorder
    def initialize(refresh_run)
      @refresh_run = refresh_run
    end

    def call(event)
      if event[:phase] == "account"
        record_account_progress(event)
      else
        record_page_progress(event)
      end

      ShareSnapshot.checkpoint_streams!(refresh_run.machine_identifier, event[:streams])
    end

    private

    attr_reader :refresh_run

    def record_account_progress(event)
      refresh_run.update!(
        account_lookups_completed: event.fetch(:index),
        account_lookups_total: event.fetch(:total),
        history_users_matched: event.fetch(:matches),
        history_users_remaining: event.fetch(:remaining),
        last_message: "Account lookup #{event.fetch(:index)}/#{event.fetch(:total)}: #{event.fetch(:label)}"
      )
    end

    def record_page_progress(event)
      refresh_run.with_lock do
        refresh_run.update!(
          history_pages_retrieved: event.fetch(:page),
          history_rows_retrieved: refresh_run.history_rows_retrieved + event.fetch(:rows),
          history_users_matched: event.fetch(:matches),
          history_users_remaining: event.fetch(:remaining),
          last_message: page_message(event)
        )
      end
    end

    def page_message(event)
      message = "History page #{event.fetch(:page)} retrieved"
      message += " (#{event.fetch(:stop_reason)})" if event[:stop_reason].present?
      message
    end
  end
end
