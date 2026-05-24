class SharesController < ApplicationController
  def index
    @machine_identifier = required_machine_identifier
    @snapshot = ShareSnapshot.latest_for(@machine_identifier)
    @refresh_run = RefreshRun.latest_for(@machine_identifier)
    @active_refresh_run = RefreshRun.active_for(@machine_identifier)
    @report = @snapshot&.to_report
    @notes_by_user_id = PlexUserNote.for_users(@report&.users || [])
  rescue Plex::ConfigurationError => error
    @configuration_error = error.message
  rescue Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    @plex_error = error.message
  end

  def refresh
    active_run = RefreshRun.active_for(required_machine_identifier)
    if active_run
      redirect_to root_path, notice: "Plex refresh is already #{active_run.status}."
      return
    end

    refresh_run = RefreshRun.create!(
      machine_identifier: required_machine_identifier,
      status: "queued",
      admin_email: current_admin_email,
      include_history: truthy_param?(params[:include_history])
    )
    PlexRefreshJob.perform_later(refresh_run.id)

    redirect_to root_path, notice: "Plex refresh queued."
  rescue Plex::ConfigurationError, Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    redirect_to root_path, alert: error.message
  end

  def create
    invited_email = params[:invited_email].to_s.strip
    library_ids = Array(params[:library_ids]).compact_blank
    raise Plex::ConfigurationError, "Enter a Plex username or email." if invited_email.blank?
    raise Plex::ConfigurationError, "Choose at least one library to share." if library_ids.empty?

    snapshot = ShareSnapshot.latest_for(required_machine_identifier)
    selected_libraries = libraries_for_ids(snapshot, library_ids)
    client = Plex::Client.from_env
    client.create_shared_server(
      required_machine_identifier,
      invited_email,
      library_ids,
      allow_sync: truthy_param?(params[:allow_sync])
    )
    refresh_snapshot(include_history: false)
    ShareAuditLog.record!(
      action: "library_access_granted",
      admin_email: current_admin_email,
      target: { label: invited_email, email: invited_email },
      libraries_added: selected_libraries,
      libraries_after: selected_libraries,
      metadata: { allow_sync: truthy_param?(params[:allow_sync]) }
    )

    redirect_to root_path, notice: "Plex invite sent."
  rescue Plex::ConfigurationError, Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    redirect_to root_path, alert: error.message
  end

  def update
    library_ids = Array(params[:library_ids]).compact_blank
    snapshot = ShareSnapshot.latest_for(required_machine_identifier)
    current_user = snapshot_user_for_share(snapshot, params[:share_id])
    previous_libraries = current_user_libraries(current_user)
    selected_libraries = libraries_for_ids(snapshot, library_ids)
    client = Plex::Client.from_env

    if library_ids.any?
      client.update_shared_server(required_machine_identifier, params[:share_id], library_ids)
    else
      client.remove_shared_server(required_machine_identifier, params[:share_id])
    end

    update_cached_share(params[:share_id], library_ids)
    record_share_update(params[:share_id], current_user, previous_libraries, selected_libraries)
    redirect_to root_path, notice: "Plex share updated."
  rescue Plex::ConfigurationError, Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    redirect_to root_path, alert: error.message
  end

  def destroy
    snapshot = ShareSnapshot.latest_for(required_machine_identifier)
    current_user = snapshot_user_for_share(snapshot, params[:share_id])
    previous_libraries = current_user_libraries(current_user)
    client = Plex::Client.from_env
    client.remove_shared_server(required_machine_identifier, params[:share_id])
    update_cached_share(params[:share_id], [])
    ShareAuditLog.record!(
      action: "library_access_removed",
      admin_email: current_admin_email,
      target: audit_target(current_user),
      share_id: params[:share_id],
      libraries_removed: previous_libraries
    )

    redirect_to root_path, notice: "Plex share removed."
  rescue Plex::ConfigurationError, Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    redirect_to root_path, alert: error.message
  end

  private

  def refresh_snapshot(include_history: true)
    Plex::SnapshotRefresh.new(
      client: Plex::Client.from_env,
      machine_identifier: required_machine_identifier,
      include_history: include_history
    ).call
  end

  def required_machine_identifier
    ENV["PLEX_MACHINE_IDENTIFIER"].presence ||
      raise(Plex::ConfigurationError, "Missing PLEX_MACHINE_IDENTIFIER in .env")
  end

  def update_cached_share(share_id, library_ids)
    snapshot = ShareSnapshot.latest_for(required_machine_identifier)
    return refresh_snapshot(include_history: false) unless snapshot

    libraries_by_id = snapshot.libraries.index_by { |library| library["id"].to_s }
    selected_libraries = library_ids.filter_map { |library_id| libraries_by_id[library_id.to_s] }
    users = snapshot.users.filter_map do |user|
      next user unless user["share_id"].to_s == share_id.to_s
      next if selected_libraries.empty?

      user.merge(
        "libraries" => selected_libraries,
        "library_count" => selected_libraries.size,
        "all_libraries" => selected_libraries.size == snapshot.libraries.size
      )
    end

    ShareSnapshot.create!(
      machine_identifier: snapshot.machine_identifier,
      server: snapshot.server,
      libraries: snapshot.libraries,
      users: users,
      fetched_at: Time.current
    )
  end

  def truthy_param?(value)
    value == true || value.to_s == "1" || value.to_s.casecmp("true").zero?
  end

  def snapshot_user_for_share(snapshot, share_id)
    snapshot&.users&.find { |user| user["share_id"].to_s == share_id.to_s }
  end

  def current_user_libraries(user)
    Array(user && user["libraries"])
  end

  def libraries_for_ids(snapshot, library_ids)
    libraries_by_id = snapshot&.libraries.to_a.index_by { |library| library["id"].to_s }
    library_ids.filter_map { |library_id| libraries_by_id[library_id.to_s] }
  end

  def record_share_update(share_id, user, previous_libraries, selected_libraries)
    if selected_libraries.empty?
      ShareAuditLog.record!(
        action: "library_access_removed",
        admin_email: current_admin_email,
        target: audit_target(user),
        share_id: share_id,
        libraries_removed: previous_libraries
      )
      return
    end

    previous_ids = previous_libraries.map { |library| library["id"].to_s }
    selected_ids = selected_libraries.map { |library| library["id"].to_s }
    added = selected_libraries.select { |library| previous_ids.exclude?(library["id"].to_s) }
    removed = previous_libraries.select { |library| selected_ids.exclude?(library["id"].to_s) }
    return if added.empty? && removed.empty?

    action = if added.any? && removed.any?
      "libraries_changed"
    elsif added.any?
      "libraries_added"
    else
      "libraries_removed"
    end

    ShareAuditLog.record!(
      action: action,
      admin_email: current_admin_email,
      target: audit_target(user),
      share_id: share_id,
      libraries_added: added,
      libraries_removed: removed,
      libraries_after: selected_libraries
    )
  end

  def audit_target(user)
    return { label: "Unknown user" } unless user

    {
      id: user["id"],
      share_id: user["share_id"],
      label: user["title"].presence || user["username"].presence || user["email"],
      email: user["email"]
    }
  end
end
