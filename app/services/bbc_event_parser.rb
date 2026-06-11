# Derives match state from a BBC scores-fixtures event. The feed is unreliable
# around live matches: it can keep `status` at PreEvent after kick-off,
# publish the live score only via `scoreUnconfirmed`, and intermittently serve
# stale payloads with no live data at all. These helpers extract the best
# available state and stop stale payloads from regressing what we already know.
class BbcEventParser
  STATUS_ORDER = { 'PreEvent' => 0, 'MidEvent' => 1, 'PostEvent' => 2 }.freeze

  # Longest realistic match: extra time, penalties and stoppages.
  PRESUMED_LIVE_WINDOW = 3.hours

  def self.status(event)
    if event['status'] == 'PreEvent' && (unconfirmed_score?(event['home']) || unconfirmed_score?(event['away']))
      'MidEvent'
    else
      event['status']
    end
  end

  # Picks the more advanced lifecycle stage (PreEvent -> MidEvent -> PostEvent)
  # so a stale payload can't drag a live or finished match back to upcoming.
  def self.merge_status(new_status, existing_status)
    return new_status if existing_status.blank?

    STATUS_ORDER.fetch(new_status, 0) >= STATUS_ORDER.fetch(existing_status, 0) ? new_status : existing_status
  end

  # True while the scheduled kick-off window is in progress, used to surface a
  # match as live even when the feed hasn't caught up yet.
  def self.presumed_live?(event, now: Time.current)
    start_time = Time.iso8601(event['startDateTime'].to_s)
    now >= start_time && now < start_time + PRESUMED_LIVE_WINDOW
  rescue ArgumentError
    false
  end

  # Returns nil when the payload carries no score at all, so callers can keep
  # a previously known score instead of resetting it to 0.
  def self.home_score(event)
    side_score(event['home'])
  end

  def self.away_score(event)
    side_score(event['away'])
  end

  def self.winner(event)
    status(event) == 'MidEvent' ? nil : event['winner']
  end

  # Flattens one side's feed actions (goals, red cards) into display events
  # like { type: 'goal', name: 'J. Quiñones', minute: "9'" }.
  def self.side_events(event, side)
    actions = event.dig(side, 'actions') || []
    actions.flat_map do |action|
      type = action['actionType'].to_s.delete_suffix('-unconfirmed')
      (action['actions'] || []).map do |occurrence|
        { type: type, name: action['playerName'], minute: occurrence.dig('timeLabel', 'value') }
      end
    end
  end

  # Minutes arrive as strings like "9'" or "45+2'".
  def self.sort_by_minute(events)
    events.sort_by { |e| e[:minute].to_s.scan(/\d+/).map(&:to_i) }
  end

  def self.side_score(side)
    score = side['score'].presence || side['scoreUnconfirmed']
    score.nil? ? nil : score.to_i
  end

  def self.unconfirmed_score?(side)
    side['scoreUnconfirmed'].present?
  end

  private_class_method :side_score, :unconfirmed_score?
end
