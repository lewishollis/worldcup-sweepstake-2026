# Fetches the BBC match-lineups container for a match and extracts the
# yellow/red cards per side. Cards only appear here — the scores feed the app
# already polls carries goals but not bookings.
class BbcLineupsService
  BASE_URL = 'https://web-cdn.api.bbci.co.uk/wc-data/container/match-lineups'

  def self.cards(match_id)
    json = fetch(match_id)
    json ? parse(json) : { home: [], away: [] }
  end

  def self.parse(json)
    home_urn = json.dig('homeTeam', 'urn')
    cards = { home: [], away: [] }

    (json['playerStats'] || []).each do |player|
      side = player['teamUrn'] == home_urn ? :home : :away
      (player['cards'] || []).each do |card|
        cards[side] << {
          type: card['type'].to_s.downcase.tr(' ', '-'),
          name: player['displayName'],
          minute: card.dig('timeLabel', 'value')
        }
      end
    end

    cards
  end

  def self.fetch(match_id)
    url = URI("#{BASE_URL}?urn=#{CGI.escape("urn:bbc:sportsdata:football:event:#{match_id}")}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    request = Net::HTTP::Get.new(url)
    request['accept'] = 'application/json'

    response = http.request(request)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.warn("BbcLineupsService fetch failed for #{match_id}: #{e.message}")
    nil
  end
end
