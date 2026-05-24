class RefreshRun < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  validates :machine_identifier, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(status: %w[queued running]) }

  def self.latest_for(machine_identifier)
    where(machine_identifier: machine_identifier).latest_first.first
  end

  def self.active_for(machine_identifier)
    where(machine_identifier: machine_identifier).active.latest_first.first
  end

  def active?
    status.in?(%w[queued running])
  end

  def elapsed_seconds
    return unless started_at

    ((finished_at || Time.current) - started_at).round
  end

  def label
    status.humanize
  end
end
