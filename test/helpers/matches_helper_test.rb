require "test_helper"

class MatchesHelperTest < ActionView::TestCase
  test "bolds the Football fact label" do
    html = format_commentary("Two matches today.\n\nFootball fact: Brazil love a World Cup.")
    assert_includes html, "<strong>Football fact:</strong>"
  end

  test "preserves line breaks" do
    html = format_commentary("Line one.\nLine two.")
    assert_includes html, "Line one.<br>Line two."
  end

  test "escapes HTML from the model so it cannot inject markup" do
    html = format_commentary("Sneaky <script>alert(1)</script> text")
    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;"
  end

  test "blank input returns an empty string" do
    assert_equal "", format_commentary(nil)
    assert_equal "", format_commentary("")
  end
end
