require "net/http"
require "rss"

namespace :news_feed do
  desc "Fetch BBC Sport RSS feed and store new headlines in NewsItem table"
  task fetch: :environment do
    url = URI("https://feeds.bbci.co.uk/sport/football/rss.xml")

    response = Net::HTTP.get_response(url)
    unless response.code.to_s.start_with?("2")
      Rails.logger.error("NewsFeed fetch failed: #{response.code}")
      next
    end

    feed = RSS::Parser.parse(response.body, false)
    unless feed
      Rails.logger.warn("NewsFeed: could not parse RSS")
      next
    end

    created = 0
    feed.items.each do |item|
      guid = item.guid&.content || item.link
      next unless guid.present?

      NewsItem.find_or_create_by(guid: guid) do |n|
        n.title        = item.title
        n.summary      = item.description
        n.published_at = item.pubDate || Time.current
        created += 1
      end
    end

    Rails.logger.info("NewsFeed: #{created} new items stored (#{feed.items.count} in feed)")
  end
end
