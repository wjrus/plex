class PlexUserNote < ApplicationRecord
  require "set"

  validates :plex_user_id, presence: true, uniqueness: true

  def self.for_users(users)
    where(plex_user_id: users.map { |user| user.id.to_s }).index_by(&:plex_user_id)
  end

  def self.suppressed_ids
    where(suppressed: true).pluck(:plex_user_id).to_set
  end
end
