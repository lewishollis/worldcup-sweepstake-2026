namespace :matches do
  # Maps BBC Sport API team names to the canonical names used in seeds/groups
  TEAM_NAME_ALIASES = {
    "Iran"               => "IR Iran",
    "Bosnia-Herzegovina" => "Bosnia And Herz.",
    "Cape Verde"         => "Cabo Verde",
    "Ivory Coast"        => "Côte d'Ivoire",
    "Turkey"             => "Türkiye",
    "United States"      => "USA",
    "South Korea"        => "Korea Republic",
    "Czech Republic"     => "Czechia"
  }.freeze

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
    skipped = 0

    data["eventGroups"].each do |event_group|
      next unless event_group["secondaryGroups"].is_a?(Array)

      event_group["secondaryGroups"].each do |secondary_group|
        next unless secondary_group["events"].is_a?(Array)

        secondary_group["events"].each do |event|
          home_name = TEAM_NAME_ALIASES.fetch(event.dig("home", "fullName"), event.dig("home", "fullName"))
          away_name = TEAM_NAME_ALIASES.fetch(event.dig("away", "fullName"), event.dig("away", "fullName"))
          stage_name = event.dig("stage", "name") || "Unknown Stage"
          start_time = event.dig("date", "iso")

          unless home_name && away_name && start_time
            Rails.logger.warn("[matches:sync] Skipping event #{event["id"].inspect} — missing required fields")
            skipped += 1
            next
          end

          home_team = Team.find_or_create_by(name: home_name)
          away_team = Team.find_or_create_by(name: away_name)
          winner    = event["status"] == "MidEvent" ? nil : event["winner"]

          match = Match.find_or_initialize_by(match_id: event["id"])
          new_record = match.new_record?

          match.assign_attributes(
            home_team:                home_team,
            away_team:                away_team,
            start_time:               start_time,
            stage:                    stage_name,
            home_score:               event.dig("home", "score").to_i,
            away_score:               event.dig("away", "score").to_i,
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

    Rails.logger.info("[matches:sync] Done — #{created} created, #{updated} updated, #{skipped} skipped")
  end
end
