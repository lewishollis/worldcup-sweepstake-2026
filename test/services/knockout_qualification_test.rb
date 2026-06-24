require "test_helper"

class KnockoutQualificationTest < ActiveSupport::TestCase
  setup { KnockoutQualification.reset! }
  teardown { KnockoutQualification.reset! }

  def team(name)
    Team.create!(name: name, flag_url: "https://x.com/#{name}.svg")
  end

  def group_match(home, away, hs:, as:, mid:)
    Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: "PostEvent",
                  group_name: "Group Q", home_score: hs, away_score: as,
                  match_id: mid, start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
  end

  def pre_match(home, away, mid)
    Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: "PreEvent",
                  group_name: "Group Q", match_id: mid, start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
  end

  def finish!(match, hs, as)
    match.update!(status: "PostEvent", home_score: hs, away_score: as)
  end

  test "clinched? is true for a team that has secured a top-2 group finish" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    group_match(a, b, hs: 1, as: 0, mid: "q-ab")
    group_match(a, c, hs: 1, as: 0, mid: "q-ac")
    group_match(a, d, hs: 1, as: 0, mid: "q-ad") # Aa 9
    group_match(b, c, hs: 1, as: 0, mid: "q-bc")
    group_match(b, d, hs: 1, as: 0, mid: "q-bd") # Bb 6
    group_match(c, d, hs: 1, as: 0, mid: "q-cd") # Cc 3, Dd 0

    assert KnockoutQualification.clinched?(a)
    assert KnockoutQualification.clinched?(b)
    refute KnockoutQualification.clinched?(c)
    refute KnockoutQualification.clinched?(d)
  end

  test "clinched? recomputes when a new group result changes the picture" do
    a, b, c, d = team("Ee"), team("Ff"), team("Gg"), team("Hh")
    ab = pre_match(a, b, "q-ab2")
    ac = pre_match(a, c, "q-ac2")
    ad = pre_match(a, d, "q-ad2")
    pre_match(b, c, "q-bc2")
    pre_match(b, d, "q-bd2")
    pre_match(c, d, "q-cd2")

    finish!(ab, 1, 0) # Aa 3 with two to play — rivals can still overtake
    refute KnockoutQualification.clinched?(a)

    finish!(ac, 1, 0)
    finish!(ad, 1, 0) # Aa 9, all its games done; no two rivals can reach 9
    assert KnockoutQualification.clinched?(a), "cache must invalidate on new results"
  end

  test "clinched? is false for a team in no group table" do
    lonely = team("Ii")
    refute KnockoutQualification.clinched?(lonely)
  end
end
