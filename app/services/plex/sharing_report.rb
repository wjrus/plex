require "set"

module Plex
  class SharingReport
    Report = Data.define(:server, :libraries, :users, :generated_at)
    SharedUser = Data.define(
      :id,
      :share_id,
      :title,
      :username,
      :email,
      :thumb,
      :home,
      :restricted,
      :allow_sync,
      :allow_channels,
      :last_seen_at,
      :last_streamed_at,
      :last_streamed_title,
      :last_streamed_type,
      :pending,
      :all_libraries,
      :library_count,
      :libraries
    ) do
      def label
        title.presence || username.presence || email.presence || id.to_s
      end
    end
    Library = Data.define(:id, :key, :title, :type)

    def initialize(client:, machine_identifier:, progress: nil, include_history: true)
      @client = client
      @machine_identifier = machine_identifier.presence
      @progress = progress
      @include_history = include_history
    end

    def call
      raise ConfigurationError, "Missing PLEX_MACHINE_IDENTIFIER in .env" unless machine_identifier

      server_data = client.server(machine_identifier)
      library_lookup = build_library_lookup(server_data[:sections])
      shared_servers = client.shared_servers(machine_identifier)
      users_by_id = client.users.index_by { |user| user[:id].to_s }
      last_streams_by_account_id = playback_history_by_account_id(shared_servers)

      Report.new(
        server: server_data[:server],
        libraries: unique_libraries(library_lookup.values),
        users: shared_servers.map { |shared_server| build_user(shared_server, library_lookup, users_by_id, last_streams_by_account_id) }.sort_by { |user| user.label.downcase },
        generated_at: Time.zone.now
      )
    end

    private

    attr_reader :client, :machine_identifier, :progress

    def build_library_lookup(sections)
      sections.each_with_object({}) do |section, lookup|
        library = Library.new(
          id: section[:id].presence || section[:key],
          key: section[:key].presence || section[:id],
          title: section[:title],
          type: section[:type]
        )
        lookup[library.id.to_s] = library
        lookup[library.key.to_s] = library
      end
    end

    def build_user(shared_server, library_lookup, users_by_id, last_streams_by_account_id)
      user_id = shared_server[:user_id].presence || shared_server.dig(:user, :id)
      user = users_by_id[user_id.to_s] || shared_server[:user] || {}
      server_share = user_server_share(user, shared_server)
      shared_sections = shared_server[:sections].select { |section| truthy?(section[:shared]) }
      all_libraries_access = truthy?(shared_server[:all_libraries]) || truthy?(server_share[:all_libraries])
      shared_libraries = if shared_sections.any?
        unique_libraries(shared_sections.map do |section|
          lookup_library(section, library_lookup)
        end)
      elsif all_libraries_access
        unique_libraries(library_lookup.values)
      else
        []
      end
      last_stream = last_streams_by_account_id[user_id.to_s]

      SharedUser.new(
        id: user[:id].presence || user_id,
        share_id: shared_server[:id].presence || server_share[:id],
        title: user[:title].presence || user[:friendly_name].presence || user[:username],
        username: user[:username],
        email: user[:email],
        thumb: user[:thumb],
        home: truthy?(user[:home]),
        restricted: truthy?(user[:restricted]),
        allow_sync: truthy?(user[:allow_sync]),
        allow_channels: truthy?(user[:allow_channels]),
        last_seen_at: shared_server[:last_seen_at].presence || server_share[:last_seen_at],
        last_streamed_at: last_stream&.dig(:viewed_at),
        last_streamed_title: stream_title(last_stream),
        last_streamed_type: last_stream&.dig(:type),
        pending: truthy?(shared_server[:pending]) || truthy?(server_share[:pending]),
        all_libraries: all_libraries_access,
        library_count: shared_libraries.size,
        libraries: shared_libraries.sort_by { |library| library.title.to_s.downcase }
      )
    end

    def lookup_library(section, library_lookup)
      library_lookup[section[:id].to_s] ||
        library_lookup[section[:key].to_s] ||
        Library.new(
          id: section[:id].presence || section[:key],
          key: section[:key].presence || section[:id],
          title: section[:title].presence || "Library #{section[:id] || section[:key]}",
          type: section[:type]
        )
    end

    def truthy?(value)
      value == true || value.to_s == "1" || value.to_s.casecmp("true").zero?
    end

    def unique_libraries(libraries)
      libraries.uniq { |library| library.id.to_s }.sort_by { |library| library.title.to_s.downcase }
    end

    def stream_title(stream)
      return unless stream

      [ stream[:grandparent_title], stream[:parent_title], stream[:title] ].compact_blank.join(" - ")
    end

    def playback_history_by_account_id(shared_servers)
      return {} unless include_history?

      account_ids = shared_servers.filter_map do |shared_server|
        (shared_server[:user_id].presence || shared_server.dig(:user, :id)).to_s.presence
      end.to_set
      return {} if account_ids.empty?

      labels_by_account_id = history_labels_by_account_id(shared_servers)
      page_size = ENV.fetch("PLEX_HISTORY_PAGE_SIZE", "1000").to_i.clamp(1, 2_000)
      max_pages = history_max_pages
      viewed_after = history_viewed_after
      streams = {}

      page = 0
      loop do
        break if max_pages && page >= max_pages

        history = fetch_history_page(page, page_size)
        unless history
          report_history_progress(
            page: page + 1,
            rows: 0,
            account_ids: account_ids,
            streams: streams,
            labels_by_account_id: labels_by_account_id,
            stop_reason: "Plex history request failed"
          )
          break
        end
        if history.empty?
          report_history_progress(
            page: page + 1,
            rows: 0,
            account_ids: account_ids,
            streams: streams,
            labels_by_account_id: labels_by_account_id,
            stop_reason: "empty page"
          )
          break
        end

        history.each do |stream|
          next if before_history_window?(stream, viewed_after)

          account_id = stream[:account_id].to_s
          next unless account_ids.include?(account_id)

          streams[account_id] ||= stream
        end

        stop_reason = if streams.keys.to_set == account_ids
          "all users matched"
        elsif viewed_after && history_older_than_window?(history, viewed_after)
          "reached history window"
        elsif history.size < page_size
          "last page"
        end
        report_history_progress(
          page: page + 1,
          rows: history.size,
          account_ids: account_ids,
          streams: streams,
          labels_by_account_id: labels_by_account_id,
          stop_reason: stop_reason
        )
        break if stop_reason

        page += 1
      end

      fill_missing_streams_by_account_id(
        account_ids: account_ids,
        streams: streams,
        labels_by_account_id: labels_by_account_id,
        viewed_after: viewed_after
      )
      streams
    end

    def fetch_history_page(page, page_size)
      client.playback_history(size: page_size, offset: page * page_size)
    rescue Client::Error => error
      Rails.logger.warn("[plex.history] #{error.message}")
      nil
    end

    def fill_missing_streams_by_account_id(account_ids:, streams:, labels_by_account_id:, viewed_after:)
      remaining_ids = account_ids - streams.keys.to_set
      return if remaining_ids.empty?

      remaining_ids.each_with_index do |account_id, index|
        history = fetch_account_history(account_id)
        stream = history.first
        streams[account_id] = stream if stream && !before_history_window?(stream, viewed_after)

        report_account_lookup_progress(
          account_id: account_id,
          label: labels_by_account_id.fetch(account_id, account_id),
          index: index + 1,
          total: remaining_ids.size,
          account_ids: account_ids,
          streams: streams
        )
      end
    end

    def fetch_account_history(account_id)
      client.playback_history(account_id: account_id, size: 1, offset: 0)
    rescue Client::Error => error
      Rails.logger.warn("[plex.history] account #{account_id}: #{error.message}")
      []
    end

    def history_max_pages
      value = ENV.fetch("PLEX_HISTORY_MAX_PAGES", "all")
      return nil if value.to_s.casecmp("all").zero?

      value.to_i.clamp(1, 10_000)
    end

    def history_viewed_after
      days = ENV["PLEX_HISTORY_DAYS"].presence
      return unless days
      return if days.casecmp("all").zero?

      days.to_i.days.ago
    end

    def before_history_window?(stream, viewed_after)
      viewed_after && stream[:viewed_at].to_i < viewed_after.to_i
    end

    def history_older_than_window?(history, viewed_after)
      oldest_viewed_at = history.filter_map { |stream| stream[:viewed_at].presence&.to_i }.min
      oldest_viewed_at && oldest_viewed_at < viewed_after.to_i
    end

    def history_labels_by_account_id(shared_servers)
      shared_servers.each_with_object({}) do |shared_server, labels|
        account_id = (shared_server[:user_id].presence || shared_server.dig(:user, :id)).to_s
        labels[account_id] = shared_server.dig(:user, :title).presence ||
          shared_server.dig(:user, :username).presence ||
          shared_server.dig(:user, :email).presence ||
          account_id
      end
    end

    def report_history_progress(page:, rows:, account_ids:, streams:, labels_by_account_id:, stop_reason:)
      return unless progress

      remaining_ids = account_ids - streams.keys.to_set
      progress.call(
        phase: "page",
        page: page,
        rows: rows,
        matches: streams.size,
        remaining: remaining_ids.size,
        stop_reason: stop_reason,
        remaining_labels: stop_reason ? remaining_ids.map { |account_id| labels_by_account_id.fetch(account_id, account_id) } : [],
        streams: streams
      )
    end

    def report_account_lookup_progress(account_id:, label:, index:, total:, account_ids:, streams:)
      return unless progress

      remaining_ids = account_ids - streams.keys.to_set
      progress.call(
        phase: "account",
        account_id: account_id,
        label: label,
        index: index,
        total: total,
        matches: streams.size,
        remaining: remaining_ids.size,
        streams: streams
      )
    end

    def user_server_share(user, shared_server)
      Array(user[:servers]).find do |server|
        server[:machine_identifier] == machine_identifier || server[:id].to_s == shared_server[:id].to_s
      end || {}
    end

    def include_history?
      @include_history
    end
  end
end
