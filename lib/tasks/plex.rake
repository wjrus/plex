namespace :plex do
  desc "Refresh the local Plex sharing snapshot"
  task refresh: :environment do
    STDOUT.sync = true
    machine_identifier = ENV["PLEX_MACHINE_IDENTIFIER"].presence ||
      raise(Plex::ConfigurationError, "Missing PLEX_MACHINE_IDENTIFIER in .env")
    ENV["PLEX_HISTORY_DAYS"] ||= "730"

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    puts "Refreshing Plex shares for #{machine_identifier}..."
    puts "History scan: page_size=#{ENV.fetch('PLEX_HISTORY_PAGE_SIZE', '1000')} max_pages=#{ENV.fetch('PLEX_HISTORY_MAX_PAGES', 'all')}"
    history_window = ENV["PLEX_HISTORY_DAYS"].presence
    puts "History window: #{history_window && !history_window.casecmp('all').zero? ? "#{history_window}d" : "all"}"

    snapshot = Plex::SnapshotRefresh.new(
      client: Plex::Client.from_env,
      machine_identifier: machine_identifier,
      progress: lambda do |event|
        if event[:phase] == "account"
          puts "Account lookup #{event.fetch(:index)}/#{event.fetch(:total)}: #{event.fetch(:label)}; #{event.fetch(:matches)} users matched, #{event.fetch(:remaining)} remaining"
        else
          message = "History page #{event.fetch(:page)} retrieved: #{event.fetch(:rows)} rows, #{event.fetch(:matches)} users matched, #{event.fetch(:remaining)} remaining"
          message += " (#{event.fetch(:stop_reason)})" if event[:stop_reason].present?
          puts message
        end
        checkpoint = ShareSnapshot.checkpoint_streams!(machine_identifier, event[:streams])
        puts "Checkpoint snapshot ##{checkpoint.id} saved" if checkpoint&.id
        if event[:stop_reason].present? && event[:remaining_labels].present?
          puts "Unmatched users: #{event[:remaining_labels].to_sentence}"
        end
      end
    ).call

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    streamed_count = snapshot.users.count { |user| user["last_streamed_at"].present? }
    library_count = snapshot.libraries.size
    user_count = snapshot.users.size

    puts "Saved snapshot ##{snapshot.id}"
    puts "Users: #{user_count}"
    puts "Libraries: #{library_count}"
    puts "Users with last-streamed data: #{streamed_count}"
    puts "Fetched at: #{snapshot.fetched_at}"
    puts "Elapsed: #{elapsed.round(1)}s"
  end
end
