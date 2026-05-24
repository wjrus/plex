class UsersController < ApplicationController
  SORT_COLUMNS = %w[name username last_streamed].freeze
  SORT_DIRECTIONS = %w[asc desc].freeze

  def index
    @machine_identifier = required_machine_identifier
    @snapshot = ShareSnapshot.latest_for(@machine_identifier)
    @sort = params[:sort].presence_in(SORT_COLUMNS) || "name"
    @direction = params[:direction].presence_in(SORT_DIRECTIONS) || default_direction_for(@sort)
    @users = sort_users(@snapshot ? @snapshot.to_report.users : [])
    @notes_by_user_id = PlexUserNote.for_users(@users)
  rescue Plex::ConfigurationError => error
    @configuration_error = error.message
  rescue ActiveRecord::ActiveRecordError => error
    @plex_error = error.message
  end

  def update_note
    note = PlexUserNote.find_or_initialize_by(plex_user_id: params[:plex_user_id])
    note.assign_attributes(note_params.merge(last_edited_by: current_admin_email))
    note.save!

    redirect_to users_path(sort: params[:sort], direction: params[:direction]), notice: "User note saved."
  rescue ActiveRecord::ActiveRecordError => error
    redirect_to users_path, alert: error.message
  end

  private

  def note_params
    params.require(:plex_user_note).permit(:username, :email, :notes)
  end

  def required_machine_identifier
    ENV["PLEX_MACHINE_IDENTIFIER"].presence ||
      raise(Plex::ConfigurationError, "Missing PLEX_MACHINE_IDENTIFIER in .env")
  end

  def sort_users(users)
    sorted_users = users.sort_by { |user| sort_key_for(user) }
    @direction == "desc" ? sorted_users.reverse : sorted_users
  end

  def sort_key_for(user)
    case @sort
    when "username"
      [ user.username.to_s.downcase, user.label.downcase ]
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
end
