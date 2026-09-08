require "test_helper"
require "rake"

class PlexRakeTest < ActiveSupport::TestCase
  test "backfill raises after exhausted retries instead of returning success" do
    original = ENV.to_h.slice("PLEX_MACHINE_IDENTIFIER", "PLEX_HISTORY_RETRIES")
    ENV["PLEX_MACHINE_IDENTIFIER"] = "synthetic-backfill"
    ENV["PLEX_HISTORY_RETRIES"] = "0"
    client = Object.new
    client.define_singleton_method(:playback_history) { |**_| raise Plex::Client::Error, "Synthetic timeout" }
    original_from_env = Plex::Client.method(:from_env)
    Plex::Client.define_singleton_method(:from_env) { client }
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "plex:refresh" }
    task = Rake::Task["plex:backfill_history"]
    task.reenable

    capture_io do
      assert_raises(Plex::Client::Error) { task.invoke }
    end
    assert_equal "failed", RefreshRun.latest_for("synthetic-backfill").status
  ensure
    %w[PLEX_MACHINE_IDENTIFIER PLEX_HISTORY_RETRIES].each { |key| ENV[key] = original[key] }
    Plex::Client.define_singleton_method(:from_env, original_from_env)
    task&.reenable
  end

  test "plex refresh task is defined" do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "plex:refresh" }

    assert Rake::Task.task_defined?("plex:refresh")
  end

  test "plex history backfill task is defined" do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "plex:backfill_history" }

    assert Rake::Task.task_defined?("plex:backfill_history")
  end

  test "plex now playing sample task is defined" do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "plex:sample_now_playing" }

    assert Rake::Task.task_defined?("plex:sample_now_playing")
  end
end
