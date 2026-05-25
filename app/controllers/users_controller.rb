class UsersController < ApplicationController
  require "csv"
  require "set"

  SORT_COLUMNS = %w[name last_streamed].freeze
  SORT_DIRECTIONS = %w[asc desc].freeze
  helper_method :local_history_user?, :suppressed_user?

  def index
    @machine_identifier = required_machine_identifier
    @snapshot = ShareSnapshot.latest_for(@machine_identifier)
    @sort = params[:sort].presence_in(SORT_COLUMNS) || "name"
    @direction = params[:direction].presence_in(SORT_DIRECTIONS) || default_direction_for(@sort)
    @report = @snapshot&.to_report
    @libraries = @report&.libraries || []
    @filter_params = filter_params
    @all_users = users_with_local_stream_accounts(@report&.users || [], include_suppressed: showing_suppressed?)
    @notes_by_user_id = PlexUserNote.for_users(@all_users)
    @pending_users = @all_users.select(&:pending)
    @users = sort_users(filter_users(@all_users))
    @audit_counts_by_user_id = audit_counts_for(@users)

    respond_to do |format|
      format.html
      format.csv do
        send_data users_csv(@users),
          filename: "plex-users-#{Time.zone.today}.csv",
          type: "text/csv"
      end
    end
  rescue Plex::ConfigurationError => error
    @configuration_error = error.message
  rescue ActiveRecord::ActiveRecordError => error
    @plex_error = error.message
  end

  def show
    @machine_identifier = required_machine_identifier
    @snapshot = ShareSnapshot.latest_for(@machine_identifier)
    @report = @snapshot&.to_report
    @libraries = @report&.libraries || []
    @all_users = users_with_local_stream_accounts(@report&.users || [], include_suppressed: true)
    @notes_by_user_id = PlexUserNote.for_users(@all_users)
    @user = @all_users.find { |user| user.id.to_s == params[:plex_user_id].to_s }
    raise ActiveRecord::RecordNotFound, "Unknown Plex user" unless @user

    @note = PlexUserNote.find_by(plex_user_id: @user.id.to_s)
    load_stream_history
    @audit_logs = ShareAuditLog.where(plex_user_id: @user.id.to_s).recent.limit(50)
  rescue Plex::ConfigurationError => error
    @configuration_error = error.message
  rescue ActiveRecord::ActiveRecordError => error
    @plex_error = error.message
  end

  def update_note
    note = PlexUserNote.find_or_initialize_by(plex_user_id: params[:plex_user_id])
    note.assign_attributes(note_params.merge(last_edited_by: current_admin_email))
    note.save!
    record_note_update(note) if note.saved_change_to_notes?

    redirect_to note_redirect_path, notice: "User note saved."
  rescue ActiveRecord::ActiveRecordError => error
    redirect_to users_path, alert: error.message
  end

  def update_suppression
    @machine_identifier = required_machine_identifier
    @snapshot = ShareSnapshot.latest_for(@machine_identifier)
    @report = @snapshot&.to_report
    @user = users_with_local_stream_accounts(@report&.users || [], include_suppressed: true)
      .find { |user| user.id.to_s == params[:plex_user_id].to_s }
    note = PlexUserNote.find_or_initialize_by(plex_user_id: params[:plex_user_id])
    suppressing = truthy_param?(params[:suppressed])
    note.assign_attributes(
      username: note.username.presence || @user&.username,
      email: note.email.presence || @user&.email,
      suppressed: suppressing,
      suppressed_at: suppressing ? Time.current : nil,
      suppressed_by: suppressing ? current_admin_email : nil
    )
    note.save!
    record_suppression_update(note, suppressing)

    redirect_to suppression_redirect_path, notice: suppressing ? "User suppressed." : "User unsuppressed."
  rescue ActiveRecord::ActiveRecordError => error
    redirect_to users_path, alert: error.message
  end

  private

  def note_params
    params.require(:plex_user_note).permit(:username, :email, :notes)
  end

  def truthy_param?(value)
    value == true || value.to_s == "1" || value.to_s.casecmp("true").zero?
  end

  def load_stream_history
    @stream_per_page = 25
    @stream_page = params.fetch(:stream_page, "1").to_i.clamp(1, 100_000)
    scope = PlexStreamEvent.where(machine_identifier: @machine_identifier, account_id: @user.id.to_s).recent
    @stream_events_count = scope.count
    @stream_total_pages = [ (@stream_events_count.to_f / @stream_per_page).ceil, 1 ].max
    @stream_page = [ @stream_page, @stream_total_pages ].min
    @stream_offset = (@stream_page - 1) * @stream_per_page
    @stream_events = scope.offset(@stream_offset).limit(@stream_per_page)
    @stream_has_player_data = scope.where.not(player_title: [ nil, "" ]).or(scope.where.not(player_platform: [ nil, "" ])).exists?
    @stream_has_ip_data = scope.where.not(ip_address: [ nil, "" ]).exists?
    @stream_page_start = @stream_events_count.zero? ? 0 : @stream_offset + 1
    @stream_page_end = [ @stream_offset + @stream_events.size, @stream_events_count ].min
  end

  def record_note_update(note)
    ShareAuditLog.record!(
      action: "user_note_updated",
      admin_email: current_admin_email,
      target: {
        id: note.plex_user_id,
        label: note.username.presence || note.email.presence || note.plex_user_id,
        email: note.email
      }
    )
  end

  def record_suppression_update(note, suppressing)
    ShareAuditLog.record!(
      action: suppressing ? "user_suppressed" : "user_unsuppressed",
      admin_email: current_admin_email,
      target: {
        id: note.plex_user_id,
        label: note.username.presence || note.email.presence || note.plex_user_id,
        email: note.email
      }
    )
  end

  def note_redirect_path
    url_from(params[:return_to]) || users_path(filter_params.merge(sort: params[:sort], direction: params[:direction]))
  end

  def suppression_redirect_path
    url_from(params[:return_to]) || user_path(params[:plex_user_id])
  end

  def required_machine_identifier
    ENV["PLEX_MACHINE_IDENTIFIER"].presence ||
      raise(Plex::ConfigurationError, "Missing PLEX_MACHINE_IDENTIFIER in .env")
  end

  def sort_users(users)
    sorted_users = users.sort_by { |user| sort_key_for(user) }
    @direction == "desc" ? sorted_users.reverse : sorted_users
  end

  def filter_params
    params.permit(:q, :status, :library_id, :notes, :streaming)
  end

  def showing_suppressed?
    @filter_params[:status].to_s == "suppressed"
  end

  def filter_users(users)
    users.select do |user|
      matches_search?(user) &&
        matches_status?(user) &&
        matches_library?(user) &&
        matches_notes?(user) &&
        matches_streaming?(user)
    end
  end

  def audit_counts_for(users)
    ShareAuditLog
      .where(plex_user_id: users.map { |user| user.id.to_s })
      .group(:plex_user_id)
      .count
  end

  def users_with_local_stream_accounts(users, include_suppressed:)
    users + local_stream_users(excluding: users, include_suppressed: include_suppressed)
  end

  def local_stream_users(excluding:, include_suppressed:)
    excluded_ids = excluding.map { |user| user.id.to_s }.to_set
    suppressed_ids = PlexUserNote.suppressed_ids
    newest_stream_by_account_id(excluded_ids).filter_map do |account_id, stream|
      suppressed = suppressed_ids.include?(account_id.to_s)
      next if suppressed && !include_suppressed

      Plex::SharingReport::SharedUser.new(
        id: account_id,
        share_id: nil,
        title: local_stream_account_title(account_id),
        username: local_stream_account_username(account_id),
        email: local_stream_account_email(account_id),
        thumb: nil,
        home: false,
        restricted: false,
        allow_sync: false,
        allow_channels: false,
        last_seen_at: nil,
        last_streamed_at: stream.viewed_at.to_i,
        last_streamed_title: stream.label,
        last_streamed_type: stream.media_type,
        invited_at: nil,
        invite_friend: nil,
        invite_server: nil,
        pending: false,
        all_libraries: false,
        library_count: 0,
        libraries: []
      )
    end
  end

  def newest_stream_by_account_id(excluded_ids)
    latest_by_account_id = PlexStreamEvent
      .where(machine_identifier: @machine_identifier)
      .where.not(account_id: excluded_ids.to_a)
      .group(:account_id)
      .maximum(:viewed_at)

    latest_by_account_id.each_with_object({}) do |(account_id, viewed_at), streams|
      stream = PlexStreamEvent
        .where(machine_identifier: @machine_identifier, account_id: account_id, viewed_at: viewed_at)
        .recent
        .first
      streams[account_id.to_s] = stream if stream
    end
  end

  def local_stream_account_title(account_id)
    return ENV["PLEX_OWNER_NAME"].presence if owner_account?(account_id)

    "Account #{account_id}"
  end

  def local_stream_account_username(account_id)
    return ENV["PLEX_OWNER_USERNAME"].presence if owner_account?(account_id)

    nil
  end

  def local_stream_account_email(account_id)
    return ENV["PLEX_OWNER_EMAIL"].presence if owner_account?(account_id)

    nil
  end

  def owner_account?(account_id)
    ENV["PLEX_OWNER_ACCOUNT_ID"].present? && ENV["PLEX_OWNER_ACCOUNT_ID"].to_s == account_id.to_s
  end

  def users_csv(users)
    CSV.generate(headers: true) do |csv|
      csv << [ "name", "username", "email", "status", "last_streamed_at", "last_streamed_title", "libraries", "library_count", "has_notes", "audit_events" ]
      users.each do |user|
        note = @notes_by_user_id[user.id.to_s]
        csv << [
          user.label,
          user.username,
          user.email,
          user_status(user),
          user.last_streamed_at.present? ? Time.zone.at(user.last_streamed_at.to_i).iso8601 : nil,
          user.last_streamed_title,
          user.libraries.map(&:title).to_sentence,
          user.libraries.size,
          note&.notes.present?,
          @audit_counts_by_user_id.fetch(user.id.to_s, 0)
        ]
      end
    end
  end

  def matches_search?(user)
    query = @filter_params[:q].to_s.strip.downcase
    return true if query.blank?

    [ user.label, user.username, user.email ].compact.any? { |value| value.downcase.include?(query) }
  end

  def matches_status?(user)
    case @filter_params[:status]
    when "pending"
      user.pending
    when "accepted"
      !user.pending && !local_history_user?(user)
    when "suppressed"
      suppressed_user?(user)
    else
      !suppressed_user?(user)
    end
  end

  def matches_library?(user)
    library_id = @filter_params[:library_id].to_s
    return true if library_id.blank?

    user.libraries.any? { |library| library.id.to_s == library_id }
  end

  def matches_notes?(user)
    case @filter_params[:notes]
    when "with"
      @notes_by_user_id[user.id.to_s]&.notes.present?
    when "without"
      @notes_by_user_id[user.id.to_s]&.notes.blank?
    else
      true
    end
  end

  def matches_streaming?(user)
    case @filter_params[:streaming]
    when "streamed"
      user.last_streamed_at.present?
    when "never"
      user.last_streamed_at.blank?
    else
      true
    end
  end

  def sort_key_for(user)
    case @sort
    when "last_streamed"
      [
        user.last_streamed_at.present? ? 0 : 1,
        user.last_streamed_at.to_i,
        user.label.downcase
      ]
    else
      [ user.label.downcase, user.username.to_s.downcase ]
    end
  end

  def default_direction_for(sort)
    sort == "last_streamed" ? "desc" : "asc"
  end

  def local_history_user?(user)
    !user.pending && user.share_id.blank? && user.libraries.empty? && user.last_streamed_at.present?
  end

  def suppressed_user?(user)
    @notes_by_user_id[user.id.to_s]&.suppressed?
  end

  def user_status(user)
    return "pending" if user.pending
    return "local_history" if local_history_user?(user)

    "accepted"
  end
end
