class UsersController < ApplicationController
  require "csv"
  require "set"

  SORT_COLUMNS = %w[name last_streamed].freeze
  SORT_DIRECTIONS = %w[asc desc].freeze
  helper_method :local_history_user?

  def index
    @machine_identifier = required_machine_identifier
    @snapshot = ShareSnapshot.latest_for(@machine_identifier)
    @sort = params[:sort].presence_in(SORT_COLUMNS) || "name"
    @direction = params[:direction].presence_in(SORT_DIRECTIONS) || default_direction_for(@sort)
    @report = @snapshot&.to_report
    @libraries = @report&.libraries || []
    @all_users = users_with_local_stream_accounts(@report&.users || [])
    @filter_params = filter_params
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
    @all_users = users_with_local_stream_accounts(@report&.users || [])
    @user = @all_users.find { |user| user.id.to_s == params[:plex_user_id].to_s }
    raise ActiveRecord::RecordNotFound, "Unknown Plex user" unless @user

    @note = PlexUserNote.find_by(plex_user_id: @user.id.to_s)
    @stream_events = PlexStreamEvent.for_user(@machine_identifier, @user.id, limit: 25)
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

  private

  def note_params
    params.require(:plex_user_note).permit(:username, :email, :notes)
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

  def note_redirect_path
    url_from(params[:return_to]) || users_path(filter_params.merge(sort: params[:sort], direction: params[:direction]))
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

  def users_with_local_stream_accounts(users)
    users + local_stream_users(excluding: users)
  end

  def local_stream_users(excluding:)
    excluded_ids = excluding.map { |user| user.id.to_s }.to_set
    newest_stream_by_account_id(excluded_ids).map do |account_id, stream|
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
    else
      true
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

  def user_status(user)
    return "pending" if user.pending
    return "local_history" if local_history_user?(user)

    "accepted"
  end
end
