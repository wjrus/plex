class SharesController < ApplicationController
  def index
    @machine_identifier = required_machine_identifier
    @snapshot = ShareSnapshot.latest_for(@machine_identifier)
    @snapshot ||= refresh_snapshot
    @report = @snapshot.to_report
    @notes_by_user_id = PlexUserNote.for_users(@report.users)
  rescue Plex::ConfigurationError => error
    @configuration_error = error.message
  rescue Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    @plex_error = error.message
  end

  def refresh
    refresh_snapshot(include_history: false)
    redirect_to root_path, notice: "Plex shares refreshed."
  rescue Plex::ConfigurationError, Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    redirect_to root_path, alert: error.message
  end

  def create
    invited_email = params[:invited_email].to_s.strip
    library_ids = Array(params[:library_ids]).compact_blank
    raise Plex::ConfigurationError, "Enter a Plex username or email." if invited_email.blank?
    raise Plex::ConfigurationError, "Choose at least one library to share." if library_ids.empty?

    client = Plex::Client.from_env
    client.create_shared_server(
      required_machine_identifier,
      invited_email,
      library_ids,
      allow_sync: truthy_param?(params[:allow_sync])
    )
    refresh_snapshot(include_history: false)

    redirect_to root_path, notice: "Plex invite sent."
  rescue Plex::ConfigurationError, Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    redirect_to root_path, alert: error.message
  end

  def update
    library_ids = Array(params[:library_ids]).compact_blank
    client = Plex::Client.from_env

    if library_ids.any?
      client.update_shared_server(required_machine_identifier, params[:share_id], library_ids)
    else
      client.remove_shared_server(required_machine_identifier, params[:share_id])
    end

    update_cached_share(params[:share_id], library_ids)
    redirect_to root_path, notice: "Plex share updated."
  rescue Plex::ConfigurationError, Plex::Client::Error, ActiveRecord::ActiveRecordError => error
    redirect_to root_path, alert: error.message
  end

  def destroy
    client = Plex::Client.from_env
    client.remove_shared_server(required_machine_identifier, params[:share_id])
    update_cached_share(params[:share_id], [])

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
end
