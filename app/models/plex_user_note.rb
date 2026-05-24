class PlexUserNote < ApplicationRecord
  validates :plex_user_id, presence: true, uniqueness: true

  def self.for_users(users)
    where(plex_user_id: users.map { |user| user.id.to_s }).index_by(&:plex_user_id)
  end
end
