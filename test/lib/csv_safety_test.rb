require "test_helper"

class CsvSafetyTest < ActiveSupport::TestCase
  test "escapes spreadsheet formula prefixes" do
    assert_equal "'=cmd", CsvSafety.cell("=cmd")
    assert_equal "'+cmd", CsvSafety.cell("+cmd")
    assert_equal "'-cmd", CsvSafety.cell("-cmd")
    assert_equal "'@cmd", CsvSafety.cell("@cmd")
  end

  test "leaves non-string values and ordinary strings alone" do
    assert_equal "viewer", CsvSafety.cell("viewer")
    assert_equal 42, CsvSafety.cell(42)
    assert_nil CsvSafety.cell(nil)
  end
end
