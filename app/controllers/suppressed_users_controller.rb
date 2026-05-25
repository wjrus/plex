class SuppressedUsersController < ApplicationController
  def index
    @machine_identifier = ENV["PLEX_MACHINE_IDENTIFIER"].presence
    @suppressed_notes = PlexUserNote.where(suppressed: true).order(suppressed_at: :desc, updated_at: :desc)
    @latest_streams_by_user_id = latest_streams_by_user_id(@suppressed_notes.map(&:plex_user_id))
  end

  private

  def latest_streams_by_user_id(user_ids)
    return {} if @machine_identifier.blank? || user_ids.empty?

    latest_by_account_id = PlexStreamEvent
      .where(machine_identifier: @machine_identifier, account_id: user_ids)
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
end
