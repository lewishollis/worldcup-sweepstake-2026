require "test_helper"

class WhatsappNotificationTest < ActiveSupport::TestCase
  test "requires notification_type" do
    n = WhatsappNotification.new(dedupe_key: "k", sent_at: Time.current)
    assert_not n.valid?
    assert_includes n.errors[:notification_type], "can't be blank"
  end

  test "requires dedupe_key" do
    n = WhatsappNotification.new(notification_type: "morning_digest", sent_at: Time.current)
    assert_not n.valid?
    assert_includes n.errors[:dedupe_key], "can't be blank"
  end

  test "requires sent_at" do
    n = WhatsappNotification.new(notification_type: "morning_digest", dedupe_key: "k")
    assert_not n.valid?
    assert_includes n.errors[:sent_at], "can't be blank"
  end

  test "enforces uniqueness on dedupe_key" do
    WhatsappNotification.create!(
      notification_type: "morning_digest",
      dedupe_key: "morning_digest:2026-06-14",
      sent_at: Time.current
    )
    duplicate = WhatsappNotification.new(
      notification_type: "morning_digest",
      dedupe_key: "morning_digest:2026-06-14",
      sent_at: Time.current
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:dedupe_key], "has already been taken"
  end

  test "allows nil match_id for non-match notifications" do
    n = WhatsappNotification.new(
      notification_type: "morning_digest",
      dedupe_key: "morning_digest:2026-06-14",
      sent_at: Time.current
    )
    assert n.valid?
  end
end
