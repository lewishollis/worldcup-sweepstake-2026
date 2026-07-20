require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @friend = Friend.create!(name: "Lewis")
  end

  test "GET /game returns 200" do
    get "/game"
    assert_response :success
  end

  test "GET /game/scores returns JSON leaderboard" do
    GameScore.create!(friend: @friend, streak: 7)
    get "/game/scores"
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data.length
    assert_equal 7, data.first["best_streak"]
    assert_equal @friend.id, data.first["friend_id"]
    assert data.first.key?("friend_name")
  end

  test "POST /game/scores saves a score and returns updated leaderboard" do
    assert_difference "GameScore.count", 1 do
      post "/game/scores",
        params: { friend_id: @friend.id, streak: 5 },
        as: :json
    end
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data.length
    assert_equal 5, data.first["best_streak"]
  end

  test "POST /game/scores with invalid friend_id returns 422" do
    post "/game/scores",
      params: { friend_id: 99999, streak: 5 },
      as: :json
    assert_response :unprocessable_entity
  end

  test "POST /game/scores with negative streak returns 422" do
    post "/game/scores",
      params: { friend_id: @friend.id, streak: -1 },
      as: :json
    assert_response :unprocessable_entity
  end

  test "POST /game/scores is rejected once the game is locked" do
    GameScore.stub(:locked?, true) do
      assert_no_difference "GameScore.count" do
        post "/game/scores",
          params: { friend_id: @friend.id, streak: 5 },
          as: :json
      end
      assert_response :forbidden
      assert JSON.parse(response.body)["locked"]
    end
  end

  test "POST /game/scores records the device_id" do
    post "/game/scores",
      params: { friend_id: @friend.id, streak: 5, device_id: "abc-123" },
      as: :json
    assert_response :success
    assert_equal "abc-123", GameScore.last.device_id
  end
end
