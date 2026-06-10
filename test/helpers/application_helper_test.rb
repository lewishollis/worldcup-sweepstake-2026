require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "vietnam_kickoff converts UK kick-off to UTC+7" do
    # 14:00 BST = 13:00 UTC = 20:00 in Vietnam, same date
    kickoff = Time.zone.local(2026, 6, 13, 14, 0, 0)
    assert_equal "20:00", vietnam_kickoff(kickoff)
  end

  test "vietnam_kickoff flags the next day when the date rolls over" do
    # 20:00 BST on Thu 11 Jun = 02:00 on Fri 12 Jun in Vietnam
    kickoff = Time.zone.local(2026, 6, 11, 20, 0, 0)
    assert_equal "02:00 Fri", vietnam_kickoff(kickoff)
  end

  test "vietnam_kickoff handles nil" do
    assert_nil vietnam_kickoff(nil)
  end
end
