# WhatsApp Notification Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a framework that automatically sends WhatsApp messages (morning fixture digest, match results, leaderboard snapshots) to the sweepstake group via the Meta Cloud API.

**Architecture:** A `WhatsappSender` service wraps the Meta HTTP call with a credential stub for dev. Three formatter classes produce message strings from existing DB models. Two Rake tasks — scheduled via the `whenever` gem — drive sending, using a `whatsapp_notifications` table with a `dedupe_key` unique index to guarantee idempotency at both job and DB level.

**Tech Stack:** Ruby on Rails 7.1, Minitest, PostgreSQL, `whenever` gem, Meta WhatsApp Cloud API (free tier).

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `Gemfile` | Modify | Add `whenever` gem |
| `db/migrate/TIMESTAMP_create_whatsapp_notifications.rb` | Create | Migration for notification tracking table |
| `app/models/whatsapp_notification.rb` | Create | Model with validations and scopes |
| `app/services/whatsapp_sender.rb` | Create | Wraps Meta Cloud API HTTP call |
| `app/messages/morning_fixtures_message.rb` | Create | Formats today's fixtures as a string |
| `app/messages/match_result_message.rb` | Create | Formats a single match result as a string |
| `app/messages/leaderboard_snapshot_message.rb` | Create | Formats current leaderboard standings as a string |
| `lib/tasks/whatsapp.rake` | Create | Rake tasks: `morning_digest` and `check_results` |
| `config/schedule.rb` | Create | `whenever` cron schedule |
| `test/models/whatsapp_notification_test.rb` | Create | Model validations and uniqueness |
| `test/services/whatsapp_sender_test.rb` | Create | Sender with/without credentials |
| `test/messages/morning_fixtures_message_test.rb` | Create | Formatter output |
| `test/messages/match_result_message_test.rb` | Create | Formatter output |
| `test/messages/leaderboard_snapshot_message_test.rb` | Create | Formatter output |
| `test/tasks/whatsapp_rake_test.rb` | Create | Rake task idempotency and delegation |

---

## Task 1: Add `whenever` gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add the gem**

Open `Gemfile` and add after the `gem "bootsnap"` line:

```ruby
gem "whenever", require: false
```

- [ ] **Step 2: Install**

```bash
bundle install
```

Expected: `Bundle complete!` with `whenever` in the output.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add whenever gem for cron scheduling"
```

---

## Task 2: Migration and model for `whatsapp_notifications`

**Files:**
- Create: `db/migrate/TIMESTAMP_create_whatsapp_notifications.rb` (generated)
- Create: `app/models/whatsapp_notification.rb`
- Create: `test/models/whatsapp_notification_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/whatsapp_notification_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/whatsapp_notification_test.rb
```

Expected: `NameError: uninitialized constant WhatsappNotification` (or similar — table doesn't exist yet).

- [ ] **Step 3: Generate the migration**

```bash
bin/rails generate migration CreateWhatsappNotifications
```

Open the generated file in `db/migrate/` and replace the `change` method body:

```ruby
def change
  create_table :whatsapp_notifications do |t|
    t.integer  :match_id
    t.string   :notification_type, null: false
    t.string   :dedupe_key, null: false
    t.datetime :sent_at, null: false
    t.timestamps
  end

  add_index :whatsapp_notifications, :dedupe_key, unique: true
  add_index :whatsapp_notifications, :match_id
end
```

- [ ] **Step 4: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs without error.

- [ ] **Step 5: Create the model**

Create `app/models/whatsapp_notification.rb`:

```ruby
class WhatsappNotification < ApplicationRecord
  validates :notification_type, presence: true
  validates :dedupe_key, presence: true, uniqueness: true
  validates :sent_at, presence: true
end
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bin/rails test test/models/whatsapp_notification_test.rb
```

Expected: `4 runs, 4 assertions, 0 failures, 0 errors`.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/ app/models/whatsapp_notification.rb test/models/whatsapp_notification_test.rb db/schema.rb
git commit -m "feat: add WhatsappNotification model and migration"
```

---

## Task 3: `WhatsappSender` service

**Files:**
- Create: `app/services/whatsapp_sender.rb`
- Create: `test/services/whatsapp_sender_test.rb`

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p test/services
```

Create `test/services/whatsapp_sender_test.rb`:

```ruby
require "test_helper"

class WhatsappSenderTest < ActiveSupport::TestCase
  test "logs message instead of sending when credentials are absent" do
    with_env("WHATSAPP_API_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => nil, "WHATSAPP_GROUP_ID" => nil) do
      logged = []
      Rails.logger.stub(:info, ->(msg) { logged << msg }) do
        WhatsappSender.call("Hello group")
      end
      assert logged.any? { |m| m.include?("Hello group") }
    end
  end

  test "posts to Meta API when credentials are present" do
    with_env(
      "WHATSAPP_API_TOKEN" => "token123",
      "WHATSAPP_PHONE_NUMBER_ID" => "phone456",
      "WHATSAPP_GROUP_ID" => "group789"
    ) do
      response_stub = OpenStruct.new(is_a?: true)
      response_stub.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }

      Net::HTTP.stub(:new, ->(host, port) {
        http = Minitest::Mock.new
        http.expect(:use_ssl=, nil, [true])
        http.expect(:request, response_stub, [Net::HTTP::Post])
        http
      }) do
        # Should not raise
        WhatsappSender.call("Test message")
      end
    end
  end

  test "raises when API returns non-success" do
    with_env(
      "WHATSAPP_API_TOKEN" => "token123",
      "WHATSAPP_PHONE_NUMBER_ID" => "phone456",
      "WHATSAPP_GROUP_ID" => "group789"
    ) do
      bad_response = OpenStruct.new(code: "400", body: "Bad Request")
      bad_response.define_singleton_method(:is_a?) { |_| false }

      Net::HTTP.stub(:new, ->(host, port) {
        http = Minitest::Mock.new
        http.expect(:use_ssl=, nil, [true])
        http.expect(:request, bad_response, [Net::HTTP::Post])
        http
      }) do
        assert_raises(RuntimeError) { WhatsappSender.call("Test") }
      end
    end
  end

  private

  def with_env(vars, &block)
    original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    block.call
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/services/whatsapp_sender_test.rb
```

Expected: `NameError: uninitialized constant WhatsappSender`.

- [ ] **Step 3: Implement `WhatsappSender`**

Create `app/services/whatsapp_sender.rb`:

```ruby
class WhatsappSender
  GRAPH_URL = "https://graph.facebook.com/v19.0"

  def self.call(message)
    new.call(message)
  end

  def call(message)
    unless credentials_present?
      Rails.logger.info("[WhatsappSender] STUB — would send: #{message}")
      return
    end

    send_message(message)
  end

  private

  def credentials_present?
    ENV["WHATSAPP_API_TOKEN"].present? &&
      ENV["WHATSAPP_PHONE_NUMBER_ID"].present? &&
      ENV["WHATSAPP_GROUP_ID"].present?
  end

  def send_message(body)
    uri = URI("#{GRAPH_URL}/#{ENV['WHATSAPP_PHONE_NUMBER_ID']}/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{ENV['WHATSAPP_API_TOKEN']}"
    request["Content-Type"] = "application/json"
    request.body = {
      messaging_product: "whatsapp",
      to: ENV["WHATSAPP_GROUP_ID"],
      type: "text",
      text: { body: body }
    }.to_json

    response = http.request(request)
    raise "WhatsApp API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/whatsapp_sender_test.rb
```

Expected: `3 runs, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add app/services/whatsapp_sender.rb test/services/whatsapp_sender_test.rb
git commit -m "feat: add WhatsappSender service with credential stub"
```

---

## Task 4: `MorningFixturesMessage` formatter

**Files:**
- Create: `app/messages/morning_fixtures_message.rb`
- Create: `test/messages/morning_fixtures_message_test.rb`

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p test/messages
```

Create `test/messages/morning_fixtures_message_test.rb`:

```ruby
require "test_helper"

class MorningFixturesMessageTest < ActiveSupport::TestCase
  setup do
    # Create minimal DB objects for each test
    @friend1 = Friend.create!(name: "Alice")
    @friend2 = Friend.create!(name: "Bob")
    @group1 = Group.create!(friend: @friend1, name: "Alice's Group")
    @group2 = Group.create!(friend: @friend2, name: "Bob's Group")
    @brazil = Team.create!(name: "Brazil")
    @argentina = Team.create!(name: "Argentina")
    @group1.teams << @brazil
    @group2.teams << @argentina
  end

  teardown do
    WhatsappNotification.delete_all
    Match.delete_all
    Team.delete_all
    Group.delete_all
    Friend.delete_all
  end

  test "returns nil when no matches today" do
    assert_nil MorningFixturesMessage.call(Date.today)
  end

  test "includes team names and friend names for today's matches" do
    Match.create!(
      home_team: @brazil,
      away_team: @argentina,
      start_time: Date.today.to_time + 15.hours,
      status: "PreEvent",
      match_id: "test-morning-1"
    )

    result = MorningFixturesMessage.call(Date.today)
    assert_not_nil result
    assert_includes result, "Brazil"
    assert_includes result, "Argentina"
    assert_includes result, "Alice"
    assert_includes result, "Bob"
  end

  test "excludes matches on other days" do
    Match.create!(
      home_team: @brazil,
      away_team: @argentina,
      start_time: Date.tomorrow.to_time + 15.hours,
      status: "PreEvent",
      match_id: "test-morning-2"
    )

    assert_nil MorningFixturesMessage.call(Date.today)
  end

  test "excludes PostEvent matches" do
    Match.create!(
      home_team: @brazil,
      away_team: @argentina,
      start_time: Date.today.to_time + 15.hours,
      status: "PostEvent",
      match_id: "test-morning-3"
    )

    assert_nil MorningFixturesMessage.call(Date.today)
  end

  test "shows No owner when team has no group" do
    orphan = Team.create!(name: "France")
    Match.create!(
      home_team: @brazil,
      away_team: orphan,
      start_time: Date.today.to_time + 15.hours,
      status: "PreEvent",
      match_id: "test-morning-4"
    )

    result = MorningFixturesMessage.call(Date.today)
    assert_includes result, "No owner"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/messages/morning_fixtures_message_test.rb
```

Expected: `NameError: uninitialized constant MorningFixturesMessage`.

- [ ] **Step 3: Create the formatter**

```bash
mkdir -p app/messages
```

Create `app/messages/morning_fixtures_message.rb`:

```ruby
class MorningFixturesMessage
  def self.call(date = Date.today)
    new(date).call
  end

  def initialize(date)
    @date = date
  end

  def call
    matches = Match.where(status: "PreEvent")
                   .where("DATE(start_time) = ?", @date)
                   .includes(home_team: :groups, away_team: :groups)
                   .order(:start_time)

    return nil if matches.empty?

    lines = ["⚽ *World Cup Today — #{@date.strftime('%A %-d %B')}*\n"]

    matches.each do |m|
      home_friend = m.home_team.groups.first&.friend&.name || "No owner"
      away_friend = m.away_team.groups.first&.friend&.name || "No owner"
      time = m.start_time.in_time_zone("London").strftime("%-I:%M%p")
      lines << "#{time} | #{m.home_team.name} (#{home_friend}) vs #{m.away_team.name} (#{away_friend})"
    end

    lines.join("\n")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/messages/morning_fixtures_message_test.rb
```

Expected: `5 runs, 5 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add app/messages/morning_fixtures_message.rb test/messages/morning_fixtures_message_test.rb
git commit -m "feat: add MorningFixturesMessage formatter"
```

---

## Task 5: `MatchResultMessage` formatter

**Files:**
- Create: `app/messages/match_result_message.rb`
- Create: `test/messages/match_result_message_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/messages/match_result_message_test.rb`:

```ruby
require "test_helper"

class MatchResultMessageTest < ActiveSupport::TestCase
  setup do
    @friend1 = Friend.create!(name: "Lewis")
    @friend2 = Friend.create!(name: "Jamie")
    @group1 = Group.create!(friend: @friend1, name: "Lewis's Group")
    @group2 = Group.create!(friend: @friend2, name: "Jamie's Group")
    @england = Team.create!(name: "England")
    @france = Team.create!(name: "France")
    @group1.teams << @england
    @group2.teams << @france
  end

  teardown do
    Match.delete_all
    Team.delete_all
    Group.delete_all
    Friend.delete_all
  end

  test "includes team names, score, and friend names" do
    match = Match.create!(
      home_team: @england,
      away_team: @france,
      home_score: 2,
      away_score: 1,
      home_points: 1,
      away_points: 0,
      status: "PostEvent",
      start_time: Time.current,
      match_id: "test-result-1"
    )

    result = MatchResultMessage.call(match)
    assert_includes result, "England"
    assert_includes result, "France"
    assert_includes result, "2"
    assert_includes result, "1"
    assert_includes result, "Lewis"
    assert_includes result, "Jamie"
  end

  test "shows points awarded" do
    match = Match.create!(
      home_team: @england,
      away_team: @france,
      home_score: 2,
      away_score: 1,
      home_points: 1,
      away_points: 0,
      status: "PostEvent",
      start_time: Time.current,
      match_id: "test-result-2"
    )

    result = MatchResultMessage.call(match)
    assert_includes result, "+1 pt"
  end

  test "shows No owner when team has no group" do
    orphan = Team.create!(name: "Brazil")
    match = Match.create!(
      home_team: @england,
      away_team: orphan,
      home_score: 0,
      away_score: 0,
      home_points: 0,
      away_points: 0,
      status: "PostEvent",
      start_time: Time.current,
      match_id: "test-result-3"
    )

    result = MatchResultMessage.call(match)
    assert_includes result, "No owner"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/messages/match_result_message_test.rb
```

Expected: `NameError: uninitialized constant MatchResultMessage`.

- [ ] **Step 3: Implement the formatter**

Create `app/messages/match_result_message.rb`:

```ruby
class MatchResultMessage
  def self.call(match)
    new(match).call
  end

  def initialize(match)
    @match = match
  end

  def call
    m = @match
    home_friend = m.home_team.groups.first&.friend&.name || "No owner"
    away_friend = m.away_team.groups.first&.friend&.name || "No owner"

    [
      "⚽ *Full Time!*",
      "#{m.home_team.name} #{m.home_score} - #{m.away_score} #{m.away_team.name}",
      "",
      "#{m.home_team.name} → #{home_friend}#{points_label(m.home_points)}",
      "#{m.away_team.name} → #{away_friend}#{points_label(m.away_points)}"
    ].join("\n")
  end

  private

  def points_label(pts)
    return "" if pts.to_i.zero?

    " (+#{pts} pt#{pts > 1 ? 's' : ''})"
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/messages/match_result_message_test.rb
```

Expected: `3 runs, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add app/messages/match_result_message.rb test/messages/match_result_message_test.rb
git commit -m "feat: add MatchResultMessage formatter"
```

---

## Task 6: `LeaderboardSnapshotMessage` formatter

**Files:**
- Create: `app/messages/leaderboard_snapshot_message.rb`
- Create: `test/messages/leaderboard_snapshot_message_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/messages/leaderboard_snapshot_message_test.rb`:

```ruby
require "test_helper"

class LeaderboardSnapshotMessageTest < ActiveSupport::TestCase
  setup do
    @alice = Friend.create!(name: "Alice")
    @bob = Friend.create!(name: "Bob")
    @charlie = Friend.create!(name: "Charlie")

    @g_alice = Group.create!(friend: @alice, name: "Alice's Group", multiplier: 1.0)
    @g_bob = Group.create!(friend: @bob, name: "Bob's Group", multiplier: 1.0)
    @g_charlie = Group.create!(friend: @charlie, name: "Charlie's Group", multiplier: 1.0)

    t1 = Team.create!(name: "Brazil", points: 5)
    t2 = Team.create!(name: "France", points: 3)
    t3 = Team.create!(name: "England", points: 1)

    @g_alice.teams << t1   # 5 pts
    @g_bob.teams << t2     # 3 pts
    @g_charlie.teams << t3 # 1 pt

    # Recalculate scores
    [@g_alice, @g_bob, @g_charlie].each(&:calculate_score)
  end

  teardown do
    Team.delete_all
    Group.delete_all
    Friend.delete_all
  end

  test "includes all friend names" do
    result = LeaderboardSnapshotMessage.call
    assert_includes result, "Alice"
    assert_includes result, "Bob"
    assert_includes result, "Charlie"
  end

  test "ranks by points descending" do
    result = LeaderboardSnapshotMessage.call
    alice_pos = result.index("Alice")
    bob_pos = result.index("Bob")
    charlie_pos = result.index("Charlie")

    assert alice_pos < bob_pos
    assert bob_pos < charlie_pos
  end

  test "includes points totals" do
    result = LeaderboardSnapshotMessage.call
    assert_includes result, "5"
    assert_includes result, "3"
    assert_includes result, "1"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/messages/leaderboard_snapshot_message_test.rb
```

Expected: `NameError: uninitialized constant LeaderboardSnapshotMessage`.

- [ ] **Step 3: Implement the formatter**

Create `app/messages/leaderboard_snapshot_message.rb`:

```ruby
class LeaderboardSnapshotMessage
  MEDALS = ["🥇", "🥈", "🥉"].freeze

  def self.call
    new.call
  end

  def call
    groups = Group.includes(:teams, :friend).sort_by { |g| -g.total_points }

    lines = ["📊 *Leaderboard*\n"]
    groups.each_with_index do |group, i|
      position = MEDALS[i] || "#{i + 1}."
      name = group.friend&.name || group.name || "Unknown"
      lines << "#{position} #{name} — #{group.total_points.to_i} pts"
    end

    lines.join("\n")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/messages/leaderboard_snapshot_message_test.rb
```

Expected: `3 runs, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add app/messages/leaderboard_snapshot_message.rb test/messages/leaderboard_snapshot_message_test.rb
git commit -m "feat: add LeaderboardSnapshotMessage formatter"
```

---

## Task 7: Rake tasks

**Files:**
- Create: `lib/tasks/whatsapp.rake`
- Create: `test/tasks/whatsapp_rake_test.rb`

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p test/tasks
```

Create `test/tasks/whatsapp_rake_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/tasks/whatsapp_rake_test.rb
```

Expected: rake task not found error (or similar — tasks don't exist yet).

- [ ] **Step 3: Implement the rake tasks**

Create `lib/tasks/whatsapp.rake`:

```ruby
namespace :whatsapp do
  desc "Send morning fixture digest if matches exist today and not already sent"
  task morning_digest: :environment do
    dedupe_key = "morning_digest:#{Date.today}"

    if WhatsappNotification.exists?(dedupe_key: dedupe_key)
      Rails.logger.info("[whatsapp:morning_digest] Already sent today, skipping")
      next
    end

    message = MorningFixturesMessage.call
    if message.nil?
      Rails.logger.info("[whatsapp:morning_digest] No matches today, skipping")
      next
    end

    WhatsappSender.call(message)
    WhatsappNotification.create!(
      notification_type: "morning_digest",
      dedupe_key: dedupe_key,
      sent_at: Time.current
    )
    Rails.logger.info("[whatsapp:morning_digest] Sent")
  rescue => e
    Rails.logger.error("[whatsapp:morning_digest] Failed: #{e.message}")
  end

  desc "Send result and leaderboard notifications for any unnotified PostEvent matches"
  task check_results: :environment do
    notified_ids = WhatsappNotification.where(notification_type: "match_result").pluck(:match_id).compact

    Match.where(status: "PostEvent")
         .where.not(id: notified_ids)
         .includes(home_team: :groups, away_team: :groups)
         .each do |match|
      dedupe_key = "match_result:#{match.id}"
      next if WhatsappNotification.exists?(dedupe_key: dedupe_key)

      WhatsappSender.call(MatchResultMessage.call(match))
      WhatsappNotification.create!(
        notification_type: "match_result",
        match_id: match.id,
        dedupe_key: dedupe_key,
        sent_at: Time.current
      )

      sleep 1

      WhatsappSender.call(LeaderboardSnapshotMessage.call)
      Rails.logger.info("[whatsapp:check_results] Sent result for match #{match.id}")
    rescue => e
      Rails.logger.error("[whatsapp:check_results] Failed for match #{match.id}: #{e.message}")
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/tasks/whatsapp_rake_test.rb
```

Expected: `5 runs, 5 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Smoke test manually**

```bash
bin/rails whatsapp:morning_digest
bin/rails whatsapp:check_results
```

Expected: logger output lines beginning with `[whatsapp:` — either "skipping" or "Sent" (or the WhatsappSender STUB line if no credentials).

- [ ] **Step 6: Commit**

```bash
git add lib/tasks/whatsapp.rake test/tasks/whatsapp_rake_test.rb
git commit -m "feat: add whatsapp rake tasks for morning digest and result checks"
```

---

## Task 8: `whenever` schedule

**Files:**
- Create: `config/schedule.rb`

- [ ] **Step 1: Create the schedule file**

Create `config/schedule.rb`:

```ruby
# Whenever schedule — generates crontab entries.
# Apply with: bundle exec whenever --update-crontab
# Remove with: bundle exec whenever --clear-crontab

set :output, Rails.root.join("log/cron.log")

every :day, at: "8:00 am" do
  rake "whatsapp:morning_digest"
end

every 15.minutes do
  rake "whatsapp:check_results"
end
```

- [ ] **Step 2: Preview the generated crontab**

```bash
bundle exec whenever
```

Expected: printed crontab entries — a `0 8 * * *` line for morning digest and a `*/15 * * * *` line for check_results.

- [ ] **Step 3: Write the crontab (only on the production server)**

> **Note:** Run this only on the server where the app is deployed. On a Mac dev machine this writes to your personal crontab — only do this if you want it running locally.

```bash
bundle exec whenever --update-crontab --set environment=production
```

Expected: `[write] crontab file updated`.

- [ ] **Step 4: Commit**

```bash
git add config/schedule.rb
git commit -m "feat: add whenever cron schedule for WhatsApp jobs"
```

---

## Post-Implementation: Meta Account Setup Checklist

When you're ready to wire up real WhatsApp sending:

1. Go to [developers.facebook.com](https://developers.facebook.com) → Create App → Business type
2. Add the **WhatsApp** product to your app
3. Register a phone number (Meta provides a free test number to start)
4. Note your **Phone Number ID** and generate a **permanent access token**
5. Add the bot number to your sweepstake WhatsApp group
6. Send a test message via the API Playground and capture the **Group Chat ID** from the recipient field
7. Set env vars on your server:
   ```
   WHATSAPP_API_TOKEN=your_token
   WHATSAPP_PHONE_NUMBER_ID=your_phone_number_id
   WHATSAPP_GROUP_ID=your_group_chat_id
   ```
8. Run `bin/rails whatsapp:morning_digest` manually to confirm a real message arrives

> **Important:** Verify that group chat messaging is enabled on your Meta Business account — this capability may require account-level approval. If the API rejects group sends, you can fall back to sending to individual numbers by iterating over `Friend` records that have a `phone` field added to the model.

---

## Run All Tests

```bash
bin/rails test test/models/whatsapp_notification_test.rb test/services/whatsapp_sender_test.rb test/messages/ test/tasks/whatsapp_rake_test.rb
```

Expected: all green, no failures.
