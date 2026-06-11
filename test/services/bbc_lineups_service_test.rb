require "test_helper"

class BbcLineupsServiceTest < ActiveSupport::TestCase
  # Trimmed shape of the BBC match-lineups container observed live on
  # 11 Jun 2026 (Mexico v South Africa).
  def lineups_json
    {
      "homeTeam" => { "urn" => "urn:bbc:sportsdata:football:team:mexico" },
      "awayTeam" => { "urn" => "urn:bbc:sportsdata:football:team:south-africa" },
      "playerStats" => [
        {
          "displayName" => "R. Rangel",
          "teamUrn" => "urn:bbc:sportsdata:football:team:mexico",
          "cards" => []
        },
        {
          "displayName" => "B. Gutiérrez",
          "teamUrn" => "urn:bbc:sportsdata:football:team:mexico",
          "cards" => [{ "type" => "Yellow Card", "timeLabel" => { "value" => "23'" } }]
        },
        {
          "displayName" => "T. Mokoena",
          "teamUrn" => "urn:bbc:sportsdata:football:team:south-africa",
          "cards" => [
            { "type" => "Yellow Card", "timeLabel" => { "value" => "17'" } },
            { "type" => "Red Card", "timeLabel" => { "value" => "70'" } }
          ]
        }
      ]
    }
  end

  test "parse groups cards by side with player, minute and normalised type" do
    cards = BbcLineupsService.parse(lineups_json)

    assert_equal [{ type: "yellow-card", name: "B. Gutiérrez", minute: "23'" }], cards[:home]
    assert_equal [
      { type: "yellow-card", name: "T. Mokoena", minute: "17'" },
      { type: "red-card", name: "T. Mokoena", minute: "70'" }
    ], cards[:away]
  end

  test "parse copes with missing playerStats" do
    cards = BbcLineupsService.parse({ "homeTeam" => { "urn" => "x" } })
    assert_equal({ home: [], away: [] }, cards)
  end

  test "cards returns empty sides when the fetch fails" do
    BbcLineupsService.stub :fetch, nil do
      assert_equal({ home: [], away: [] }, BbcLineupsService.cards("some-id"))
    end
  end
end
