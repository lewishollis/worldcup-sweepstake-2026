require "test_helper"

class TeamTest < ActiveSupport::TestCase
  test "team should start with 0 points" do
    team = Team.create!(name: "Test Team", flag_url: "https://example.com/flag.svg")
    assert_equal 0, team.points
  end

  test "team should not be progressed by default" do
    team = Team.create!(name: "Test Team", flag_url: "https://example.com/flag.svg")
    assert_not team.progressed?
  end

  test "marking team as progressed should be persisted" do
    team = Team.create!(name: "Test Team", flag_url: "https://example.com/flag.svg")
    team.update!(progressed: true)
    assert team.reload.progressed?
  end

  test "team points should be updatable" do
    team = Team.create!(name: "Test Team", flag_url: "https://example.com/flag.svg")
    team.update!(points: 5)
    assert_equal 5, team.reload.points
  end
end
