require "test_helper"

class ThemeContrastTest < ActiveSupport::TestCase
  MINIMUM_AA_CONTRAST = 4.5

  test "theme tokens keep key UI states above WCAG AA contrast" do
    themes.each do |theme_name, tokens|
      panel = color_value(tokens.fetch("theme-panel"), tokens.fetch("theme-panel"))
      accent = color_value(tokens.fetch("theme-accent"), panel)
      accent_panel = mix(accent, panel, 0.12)
      danger = color_value(tokens.fetch("theme-danger"), panel)
      danger_panel = mix(danger, panel, 0.12)

      assert_contrast theme_name, "body text", tokens.fetch("theme-text"), panel
      assert_contrast theme_name, "muted text", tokens.fetch("theme-muted"), panel
      assert_contrast theme_name, "primary button", tokens.fetch("theme-accent-ink"), accent
      assert_contrast theme_name, "danger button", tokens.fetch("theme-accent-ink"), danger
      assert_contrast theme_name, "danger panel", danger, danger_panel
      assert_contrast theme_name, "accent badge", tokens.fetch("theme-accent-label"), accent_panel
      assert_contrast theme_name, "warning badge", tokens.fetch("theme-warning-text"), tokens.fetch("theme-warning-bg"), panel
      assert_contrast theme_name, "success badge", tokens.fetch("theme-success-text"), tokens.fetch("theme-success-bg"), panel
    end
  end

  private

  def assert_contrast(theme_name, label, foreground, background, backdrop = nil)
    ratio = contrast_ratio(color_value(foreground, backdrop), color_value(background, backdrop))

    assert ratio >= MINIMUM_AA_CONTRAST,
      "#{theme_name} #{label} contrast is #{ratio.round(2)}:1"
  end

  def themes
    css = Rails.root.join("app/assets/tailwind/application.css").read
    default_theme = css.match(/:root\s*\{(?<body>.*?)\n\}/m)[:body]
    data_themes = css.scan(/:root\[data-theme="(?<name>[^"]+)"\]\s*\{(?<body>.*?)\n\}/m)

    { "light" => tokens_from(default_theme) }.merge(
      data_themes.to_h { |name, body| [ name, tokens_from(default_theme).merge(tokens_from(body)) ] }
    )
  end

  def tokens_from(body)
    body.scan(/--(?<name>theme-[\w-]+):\s*(?<value>[^;]+);/).to_h
  end

  def color_value(value, backdrop)
    return value if value.is_a?(Array)

    value = value.strip
    return hex_to_rgb(value) if value.start_with?("#")

    if value.start_with?("rgba")
      rgba = value.scan(/[\d.]+/).map(&:to_f)
      rgb = rgba.first(3)
      alpha = rgba.fetch(3)
      base = backdrop || [ 255, 255, 255 ]

      return rgb.each_with_index.map { |channel, index| channel * alpha + base[index] * (1 - alpha) }
    end

    raise ArgumentError, "Unsupported color value: #{value}"
  end

  def hex_to_rgb(value)
    value.delete_prefix("#").scan(/../).map { |channel| channel.to_i(16) }
  end

  def mix(foreground, background, amount)
    foreground.each_with_index.map { |channel, index| channel * amount + background[index] * (1 - amount) }
  end

  def contrast_ratio(foreground, background)
    lighter, darker = [ luminance(foreground), luminance(background) ].sort.reverse

    (lighter + 0.05) / (darker + 0.05)
  end

  def luminance(rgb)
    normalized = rgb.map do |channel|
      channel /= 255.0
      channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end

    normalized.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |channel, weight| channel * weight }
  end
end
