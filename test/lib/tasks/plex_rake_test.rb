require "test_helper"
require "rake"

class PlexRakeTest < ActiveSupport::TestCase
  test "plex refresh task is defined" do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "plex:refresh" }

    assert Rake::Task.task_defined?("plex:refresh")
  end

  test "plex history backfill task is defined" do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "plex:backfill_history" }

    assert Rake::Task.task_defined?("plex:backfill_history")
  end
end
