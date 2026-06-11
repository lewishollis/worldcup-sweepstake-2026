require "test_helper"

class BbcEventParserTest < ActiveSupport::TestCase
  # Shape observed during the Mexico v South Africa opener (11 Jun 2026):
  # BBC kept status "PreEvent" well after kick-off and published the live
  # score only via scoreUnconfirmed / unconfirmed goal actions.
  def live_but_unconfirmed_event
    {
      "home" => { "fullName" => "Mexico", "scoreUnconfirmed" => "1" },
      "away" => { "fullName" => "South Africa", "scoreUnconfirmed" => "0" },
      "status" => "PreEvent",
      "startDateTime" => "2026-06-11T19:00:00Z",
      "winner" => nil
    }
  end

  test "treats a PreEvent match with unconfirmed scores as live" do
    assert_equal "MidEvent", BbcEventParser.status(live_but_unconfirmed_event)
  end

  test "falls back to unconfirmed scores when confirmed scores are missing" do
    assert_equal 1, BbcEventParser.home_score(live_but_unconfirmed_event)
    assert_equal 0, BbcEventParser.away_score(live_but_unconfirmed_event)
  end

  test "leaves a genuinely upcoming match as PreEvent with no scores" do
    event = {
      "home" => { "fullName" => "Mexico" },
      "away" => { "fullName" => "South Africa" },
      "status" => "PreEvent"
    }
    assert_equal "PreEvent", BbcEventParser.status(event)
    assert_nil BbcEventParser.home_score(event)
    assert_nil BbcEventParser.away_score(event)
  end

  test "prefers confirmed scores over unconfirmed ones" do
    event = {
      "home" => { "score" => "2", "scoreUnconfirmed" => "1" },
      "away" => { "score" => "0" },
      "status" => "MidEvent"
    }
    assert_equal "MidEvent", BbcEventParser.status(event)
    assert_equal 2, BbcEventParser.home_score(event)
  end

  test "does not report a winner while the match is live" do
    event = live_but_unconfirmed_event.merge("winner" => "home")
    assert_nil BbcEventParser.winner(event)
  end

  test "reports the winner once the match has finished" do
    event = {
      "home" => { "score" => "2" },
      "away" => { "score" => "0" },
      "status" => "PostEvent",
      "winner" => "home"
    }
    assert_equal "home", BbcEventParser.winner(event)
  end

  test "merge_status never regresses the match lifecycle" do
    assert_equal "MidEvent", BbcEventParser.merge_status("PreEvent", "MidEvent")
    assert_equal "PostEvent", BbcEventParser.merge_status("MidEvent", "PostEvent")
    assert_equal "PostEvent", BbcEventParser.merge_status("PreEvent", "PostEvent")
  end

  test "merge_status applies forward progress and equal states" do
    assert_equal "MidEvent", BbcEventParser.merge_status("MidEvent", "PreEvent")
    assert_equal "PostEvent", BbcEventParser.merge_status("PostEvent", "MidEvent")
    assert_equal "MidEvent", BbcEventParser.merge_status("MidEvent", "MidEvent")
    assert_equal "PreEvent", BbcEventParser.merge_status("PreEvent", nil)
  end

  test "presumed_live? is true between kick-off and the end of the live window" do
    event = { "startDateTime" => "2026-06-11T19:00:00Z" }
    assert_not BbcEventParser.presumed_live?(event, now: Time.utc(2026, 6, 11, 18, 59))
    assert BbcEventParser.presumed_live?(event, now: Time.utc(2026, 6, 11, 19, 20))
    assert BbcEventParser.presumed_live?(event, now: Time.utc(2026, 6, 11, 21, 45))
    assert_not BbcEventParser.presumed_live?(event, now: Time.utc(2026, 6, 11, 22, 1))
  end

  test "presumed_live? is false when the start time is missing or malformed" do
    assert_not BbcEventParser.presumed_live?({}, now: Time.utc(2026, 6, 11, 19, 20))
    assert_not BbcEventParser.presumed_live?({ "startDateTime" => "nonsense" }, now: Time.utc(2026, 6, 11, 19, 20))
  end

  test "side_events flattens goal actions with scorer and minute" do
    event = {
      "home" => {
        "actions" => [
          {
            "playerName" => "J. Quiñones",
            "actionType" => "goal",
            "actions" => [
              { "type" => "Goal", "timeLabel" => { "value" => "9'" } },
              { "type" => "Goal", "timeLabel" => { "value" => "55'" } }
            ]
          }
        ]
      },
      "away" => {}
    }

    assert_equal [
      { type: "goal", name: "J. Quiñones", minute: "9'" },
      { type: "goal", name: "J. Quiñones", minute: "55'" }
    ], BbcEventParser.side_events(event, "home")
    assert_equal [], BbcEventParser.side_events(event, "away")
  end

  test "side_events normalises unconfirmed goals" do
    event = {
      "home" => {
        "actions" => [
          {
            "playerName" => "J. Quiñones",
            "actionType" => "goal-unconfirmed",
            "actions" => [{ "type" => "Goal", "timeLabel" => { "value" => "9'" } }]
          }
        ]
      }
    }

    assert_equal [{ type: "goal", name: "J. Quiñones", minute: "9'" }],
                 BbcEventParser.side_events(event, "home")
  end

  test "sort_by_minute orders events including stoppage-time minutes" do
    events = [
      { type: "goal", name: "A", minute: "45+2'" },
      { type: "yellow-card", name: "B", minute: "17'" },
      { type: "goal", name: "C", minute: "45+1'" },
      { type: "red-card", name: "D", minute: "9'" }
    ]

    assert_equal %w[D B C A], BbcEventParser.sort_by_minute(events).map { |e| e[:name] }
  end
end
