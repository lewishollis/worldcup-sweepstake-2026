namespace :matches do
  desc "Fetch latest match data from BBC Sport API and upsert into DB"
  task sync: :environment do
    require "net/http"
    require "json"

    today_date = Time.now.strftime("%Y-%m-%d")
    url = URI("https://web-cdn.api.bbci.co.uk/wc-poll-data/container/sport-data-scores-fixtures?selectedEndDate=2026-07-19&selectedStartDate=2026-06-01&todayDate=#{today_date}&urn=urn%3Abbc%3Asportsdata%3Afootball%3Atournament%3Aworld-cup")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Get.new(url)
    request["accept"] = "application/json"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[matches:sync] BBC API request failed: #{response.code} #{response.message}")
      next
    end

    data = JSON.parse(response.body)

    unless data["eventGroups"].is_a?(Array)
      Rails.logger.error("[matches:sync] Unexpected response structure from BBC API")
      next
    end

    updated = 0
    created = 0

    data["eventGroups"].each do |event_group|
      event_group["secondaryGroups"].each do |secondary_group|
        secondary_group["events"].each do |event|
          home_team = Team.find_or_create_by(name: event["home"]["fullName"])
          away_team = Team.find_or_create_by(name: event["away"]["fullName"])
          stage     = event["stage"] || { "name" => "Unknown Stage" }
          winner    = event["status"] == "MidEvent" ? nil : event["winner"]

          match = Match.find_or_initialize_by(match_id: event["id"])
          new_record = match.new_record?

          match.assign_attributes(
            home_team:                home_team,
            away_team:                away_team,
            start_time:               event["date"]["iso"],
            stage:                    stage["name"],
            home_score:               event["home"]["score"].to_i,
            away_score:               event["away"]["score"].to_i,
            status:                   event["status"],
            winner:                   winner,
            accessible_event_summary: event["accessibleEventSummary"]
          )

          if new_record || match.changed?
            match.save!
            new_record ? (created += 1) : (updated += 1)
          end
        end
      end
    end

    Rails.logger.info("[matches:sync] Done — #{created} created, #{updated} updated")
  end
end
