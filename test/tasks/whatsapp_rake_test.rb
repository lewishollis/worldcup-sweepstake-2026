require "test_helper"
require "rake"

class WhatsappRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
    @friend = Friend.create!(name: "Test Friend")
    @group = Group.create!(friend: @friend, name: "Test Group")
    @brazil = Team.create!(name: "Brazil")
    @germany = Team.create!(name: "Germany")
    @group.teams << @brazil
    @group.teams << @germany
  end

  teardown do
    WhatsappNotification.delete_all
    Match.delete_all
    Team.delete_all
    Group.delete_all
    Friend.delete_all
    Rake::Task["whatsapp:morning_digest"].reenable
    Rake::Task["whatsapp:check_results"].reenable
  end

  # --- morning_digest ---

  test "morning_digest sends when matches exist today and no prior notification" do
    Match.create!(
      home_team: @brazil, away_team: @germany,
      start_time: Date.today.to_time + 15.hours,
      status: "PreEvent", match_id: "rake-morning-1"
    )

    sent = []
    WhatsappSender.stub(:call, ->(msg) { sent << msg }) do
      Rake::Task["whatsapp:morning_digest"].invoke
    end

    assert_equal 1, sent.size
    assert_includes sent.first, "Brazil"
    assert_equal 1, WhatsappNotification.where(notification_type: "morning_digest").count
  end

  test "morning_digest skips when already sent today" do
    WhatsappNotification.create!(
      notification_type: "morning_digest",
      dedupe_key: "morning_digest:#{Date.today}",
      sent_at: Time.current
    )
    Match.create!(
      home_team: @brazil, away_team: @germany,
      start_time: Date.today.to_time + 15.hours,
      status: "PreEvent", match_id: "rake-morning-2"
    )

    sent = []
    WhatsappSender.stub(:call, ->(msg) { sent << msg }) do
      Rake::Task["whatsapp:morning_digest"].invoke
    end

    assert_equal 0, sent.size
  end

  test "morning_digest skips when no matches today" do
    sent = []
    WhatsappSender.stub(:call, ->(msg) { sent << msg }) do
      Rake::Task["whatsapp:morning_digest"].invoke
    end

    assert_equal 0, sent.size
    assert_equal 0, WhatsappNotification.count
  end

  # --- check_results ---

  test "check_results sends result and leaderboard for unnotified PostEvent matches" do
    match = Match.create!(
      home_team: @brazil, away_team: @germany,
      home_score: 2, away_score: 1,
      home_points: 1, away_points: 0,
      status: "PostEvent",
      start_time: 2.hours.ago,
      match_id: "rake-result-1"
    )

    sent = []
    WhatsappSender.stub(:call, ->(msg) { sent << msg }) do
      Rake::Task["whatsapp:check_results"].invoke
    end

    assert_equal 2, sent.size   # result + leaderboard
    assert_includes sent.first, "Full Time"
    assert_includes sent.last, "Leaderboard"
    assert_equal 1, WhatsappNotification.where(notification_type: "match_result", match_id: match.id).count
  end

  test "check_results skips already-notified matches" do
    match = Match.create!(
      home_team: @brazil, away_team: @germany,
      home_score: 2, away_score: 1,
      home_points: 1, away_points: 0,
      status: "PostEvent",
      start_time: 2.hours.ago,
      match_id: "rake-result-2"
    )
    WhatsappNotification.create!(
      notification_type: "match_result",
      match_id: match.id,
      dedupe_key: "match_result:#{match.id}",
      sent_at: Time.current
    )

    sent = []
    WhatsappSender.stub(:call, ->(msg) { sent << msg }) do
      Rake::Task["whatsapp:check_results"].invoke
    end

    assert_equal 0, sent.size
  end
end
