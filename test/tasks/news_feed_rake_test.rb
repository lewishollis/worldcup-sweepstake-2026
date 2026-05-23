require "test_helper"

class NewsFeedRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
  end

  test "news_feed:fetch creates NewsItems from valid RSS" do
    rss_xml = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Brazil star injured ahead of quarter-final</title>
            <description>Key player ruled out with hamstring strain.</description>
            <guid>https://bbc.co.uk/sport/football/1</guid>
            <pubDate>Sat, 23 May 2026 08:00:00 GMT</pubDate>
          </item>
          <item>
            <title>France squad named for semi-final</title>
            <description>Manager names strong XI for the clash.</description>
            <guid>https://bbc.co.uk/sport/football/2</guid>
            <pubDate>Sat, 23 May 2026 07:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    Net::HTTP.stub(:get_response, OpenStruct.new(body: rss_xml, code: "200")) do
      assert_difference "NewsItem.count", 2 do
        Rake::Task["news_feed:fetch"].reenable
        Rake::Task["news_feed:fetch"].execute
      end
    end
  end

  test "news_feed:fetch is idempotent — does not duplicate on re-run" do
    existing_guid = "https://bbc.co.uk/sport/football/99"
    NewsItem.create!(guid: existing_guid, title: "Existing", published_at: 1.hour.ago)

    rss_xml = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Existing</title>
            <description>Same item.</description>
            <guid>#{existing_guid}</guid>
            <pubDate>Sat, 23 May 2026 07:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    Net::HTTP.stub(:get_response, OpenStruct.new(body: rss_xml, code: "200")) do
      assert_no_difference "NewsItem.count" do
        Rake::Task["news_feed:fetch"].reenable
        Rake::Task["news_feed:fetch"].execute
      end
    end
  end
end
