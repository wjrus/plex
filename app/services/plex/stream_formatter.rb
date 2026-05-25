module Plex
  module StreamFormatter
    module_function

    def title(stream)
      [ stream[:grandparent_title], stream[:parent_title], stream[:title] ].compact_blank.join(" - ")
    end

    def user_label(stream)
      user = stream[:user] || {}
      user[:title].presence || user[:username].presence || user[:email].presence || user[:id].presence || stream[:account_id].presence || "Unknown user"
    end

    def player_label(stream)
      player = stream[:player] || {}
      [ player[:title], player[:platform] ].compact_blank.join(" · ").presence || "Unknown player"
    end

    def state(stream)
      player = stream[:player] || {}
      player[:state].presence || "unknown"
    end

    def progress_percent(stream)
      duration = stream[:duration].to_i
      offset = stream[:view_offset].to_i
      return 0 unless duration.positive? && offset.positive?

      ((offset.to_f / duration) * 100).clamp(0, 100).round
    end
  end
end
