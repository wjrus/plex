class ShareAuditLog < ApplicationRecord
  require "csv"

  ACTIONS = %w[
    library_access_granted
    library_access_removed
    libraries_added
    libraries_removed
    libraries_changed
    pending_invite_canceled
  ].freeze

  validates :action, inclusion: { in: ACTIONS }
  validates :admin_email, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.record!(action:, admin_email:, target:, share_id: nil, libraries_added: [], libraries_removed: [], libraries_after: [], metadata: {})
    create!(
      action: action,
      admin_email: admin_email,
      plex_user_id: target[:id],
      share_id: share_id || target[:share_id],
      target_label: target[:label],
      target_email: target[:email],
      libraries_added: library_names(libraries_added),
      libraries_removed: library_names(libraries_removed),
      libraries_after: library_names(libraries_after),
      metadata: metadata.compact
    )
  end

  def self.to_csv(logs)
    CSV.generate(headers: true) do |csv|
      csv << [ "created_at", "admin_email", "action", "summary", "target", "target_email", "libraries_added", "libraries_removed", "libraries_after" ]
      logs.limit(10_000).each do |entry|
        csv << [
          entry.created_at.iso8601,
          entry.admin_email,
          entry.action,
          entry.summary,
          entry.target_name,
          entry.target_email,
          entry.libraries_added.to_sentence,
          entry.libraries_removed.to_sentence,
          entry.libraries_after.to_sentence
        ]
      end
    end
  end

  def summary
    case action
    when "library_access_granted"
      "granted library access to #{target_name}"
    when "library_access_removed"
      "removed #{target_name} from all libraries"
    when "libraries_added"
      "added #{libraries_added.to_sentence} to #{target_name}"
    when "libraries_removed"
      "removed #{libraries_removed.to_sentence} from #{target_name}"
    when "pending_invite_canceled"
      "canceled pending invite for #{target_name}"
    else
      "changed library access for #{target_name}"
    end
  end

  def details
    case action
    when "library_access_granted"
      "Shared: #{libraries_after.to_sentence.presence || "No libraries recorded"}"
    when "library_access_removed"
      "Removed: #{libraries_removed.to_sentence.presence || "All libraries"}"
    when "libraries_changed"
      [
        ("Added: #{libraries_added.to_sentence}" if libraries_added.present?),
        ("Removed: #{libraries_removed.to_sentence}" if libraries_removed.present?),
        ("Now shared: #{libraries_after.to_sentence}" if libraries_after.present?)
      ].compact.join(" · ")
    when "pending_invite_canceled"
      "Pending invite was canceled before acceptance"
    else
      ("Now shared: #{libraries_after.to_sentence}" if libraries_after.present?)
    end
  end

  def target_name
    target_label.presence || target_email.presence || plex_user_id.presence || "unknown user"
  end

  def self.library_names(libraries)
    Array(libraries).map { |library| library.respond_to?(:title) ? library.title : library["title"] || library[:title] }.compact_blank
  end
  private_class_method :library_names
end
