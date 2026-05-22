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
