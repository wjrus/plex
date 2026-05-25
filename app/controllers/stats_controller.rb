class StatsController < ApplicationController
  def index
    @machine_identifier = required_machine_identifier
    @active_libraries = active_libraries
    @active_library_titles = @active_libraries.map(&:title)
    @active_library_ids = @active_libraries.flat_map { |library| [ library.id, library.key ] }.compact.map(&:to_s)
    @library_labels_by_identifier = library_labels_by_identifier
    @history_summary = PlexStreamEvent.history_summary(@machine_identifier)
    @library_stats = library_stats
    @type_stats = type_stats
    @monthly_stats = monthly_stats
    @top_users = top_users
    @max_library_plays = @library_stats.map { |stat| stat[:plays] }.max.to_i
    @max_type_plays = @type_stats.map { |stat| stat[:plays] }.max.to_i
    @max_monthly_plays = @monthly_stats.map { |stat| stat[:plays] }.max.to_i
    @max_user_plays = @top_users.map { |stat| stat[:plays] }.max.to_i
  rescue Plex::ConfigurationError => error
    @configuration_error = error.message
  rescue ActiveRecord::ActiveRecordError => error
    @plex_error = error.message
  end

  private

  def library_stats
    completed_event_scope
      .to_a
      .group_by(&:library_identifier)
      .map do |identifier, events|
        { label: @library_labels_by_identifier.fetch(identifier.to_s, identifier.to_s), plays: events.size, users: events.map(&:account_id).uniq.size, latest: events.map(&:viewed_at).max }
      end
      .sort_by { |stat| [ -stat[:plays], stat[:label].downcase ] }
      .first(12)
  end

  def type_stats
    completed_event_scope
      .where.not(media_type: [ nil, "" ])
      .group(:media_type)
      .order(Arel.sql("COUNT(*) DESC"))
      .pluck(:media_type, Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT account_id)"))
      .map do |media_type, plays, users|
        { label: media_type, plays: plays, users: users }
      end
  end

  def monthly_stats
    start_time = 11.months.ago.beginning_of_month
    counts_by_month = completed_event_scope
      .where("viewed_at >= ?", start_time)
      .pluck(:viewed_at)
      .each_with_object(Hash.new(0)) do |viewed_at, counts|
        counts[viewed_at.beginning_of_month.to_date] += 1
      end

    11.downto(0).map do |months_ago|
      month = months_ago.months.ago.beginning_of_month
      { label: month.strftime("%b %Y"), plays: counts_by_month.fetch(month.to_date, 0) }
    end
  end

  def top_users
    label_by_account_id = user_labels
    completed_event_scope
      .group(:account_id)
      .order(Arel.sql("COUNT(*) DESC"))
      .limit(12)
      .pluck(:account_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(viewed_at)"))
      .map do |account_id, plays, latest|
        { account_id: account_id, label: label_by_account_id.fetch(account_id.to_s, "Account #{account_id}"), plays: plays, latest: latest }
      end
  end

  def active_libraries
    snapshot = ShareSnapshot.latest_for(@machine_identifier)
    Array(snapshot&.to_report&.libraries)
  end

  def library_labels_by_identifier
    @active_libraries.each_with_object({}) do |library, labels|
      labels[library.title.to_s] = library.title
      labels[library.id.to_s] = library.title if library.id.present?
      labels[library.key.to_s] = library.title if library.key.present?
    end
  end

  def user_labels
    labels = PlexUserNote.where.not(username: [ nil, "" ]).pluck(:plex_user_id, :username).to_h
    snapshot = ShareSnapshot.latest_for(@machine_identifier)
    report = snapshot&.to_report
    (report&.users || []).each do |user|
      labels[user.id.to_s] = user.label
    end
    if ENV["PLEX_OWNER_ACCOUNT_ID"].present?
      labels[ENV["PLEX_OWNER_ACCOUNT_ID"].to_s] =
        ENV["PLEX_OWNER_USERNAME"].presence ||
        ENV["PLEX_OWNER_NAME"].presence ||
        ENV["PLEX_OWNER_EMAIL"].presence ||
        "Server owner"
    end
    labels
  end

  def event_scope
    PlexStreamEvent.where(machine_identifier: @machine_identifier)
  end

  def completed_event_scope
    PlexStreamEvent.completed_video_play_scope(event_scope, library_titles: @active_library_titles, library_ids: @active_library_ids)
  end

  def required_machine_identifier
    ENV["PLEX_MACHINE_IDENTIFIER"].presence ||
      raise(Plex::ConfigurationError, "Missing PLEX_MACHINE_IDENTIFIER in .env")
  end
end
