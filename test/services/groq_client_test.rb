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
        http.expect(:open_timeout=, nil, [5])
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
        http.expect(:open_timeout=, nil, [5])
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

  test "sends reasoning_effort low for GPT-OSS models" do
    body = capture_request_body(model: "openai/gpt-oss-120b")
    assert_equal "low", body["reasoning_effort"]
  end

  test "omits reasoning_effort for non-GPT-OSS models" do
    body = capture_request_body(model: "llama-3.3-70b-versatile")
    assert_not body.key?("reasoning_effort")
  end

  private

  # Runs a stubbed GroqClient.call and returns the JSON request body sent to the API.
  def capture_request_body(model:)
    sent = nil
    response_body = { "choices" => [{ "message" => { "content" => "ok" } }] }.to_json
    response_stub = OpenStruct.new(body: response_body)
    response_stub.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }

    with_env("GROQ_API_KEY" => "test-key") do
      Net::HTTP.stub(:new, ->(_host, _port) {
        http = Object.new
        http.define_singleton_method(:use_ssl=) { |_| }
        http.define_singleton_method(:open_timeout=) { |_| }
        http.define_singleton_method(:read_timeout=) { |_| }
        http.define_singleton_method(:request) { |req| sent = req.body; response_stub }
        http
      }) do
        GroqClient.call(system_prompt: "sys", user_message: "msg", model: model)
      end
    end

    JSON.parse(sent)
  end

  def with_env(vars, &block)
    original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    block.call
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
