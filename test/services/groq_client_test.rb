require "test_helper"

class GroqClientTest < ActiveSupport::TestCase
  test "returns nil when GROQ_API_KEY is not set" do
    with_env("GROQ_API_KEY" => nil) do
      result = GroqClient.call(system_prompt: "You are helpful", user_message: "hello")
      assert_nil result
    end
  end

  test "calls Groq API and returns response text" do
    response_body = {
      "choices" => [{ "message" => { "content" => "Great commentary!" } }]
    }.to_json
    response_stub = OpenStruct.new(body: response_body)
    response_stub.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }

    with_env("GROQ_API_KEY" => "test-key") do
      Net::HTTP.stub(:new, ->(_host, _port) {
        http = Minitest::Mock.new
        http.expect(:use_ssl=, nil, [true])
        http.expect(:read_timeout=, nil, [15])
        http.expect(:request, response_stub, [Net::HTTP::Post])
        http
      }) do
        result = GroqClient.call(system_prompt: "You are helpful", user_message: "hello")
        assert_equal "Great commentary!", result
      end
    end
  end

  test "returns nil and logs on API failure" do
    bad_response = OpenStruct.new(code: "500", body: "Internal Server Error")
    bad_response.define_singleton_method(:is_a?) { |_| false }

    logged = []
    with_env("GROQ_API_KEY" => "test-key") do
      Net::HTTP.stub(:new, ->(_host, _port) {
        http = Minitest::Mock.new
        http.expect(:use_ssl=, nil, [true])
        http.expect(:read_timeout=, nil, [15])
        http.expect(:request, bad_response, [Net::HTTP::Post])
        http
      }) do
        Rails.logger.stub(:error, ->(msg) { logged << msg }) do
          result = GroqClient.call(system_prompt: "You are helpful", user_message: "hello")
          assert_nil result
        end
      end
    end
    assert logged.any? { |m| m.include?("Groq API") }
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
