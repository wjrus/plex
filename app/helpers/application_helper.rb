module ApplicationHelper
  def plex_image_url(path)
    path = path.to_s
    return if path.blank?

    base_url = ENV["PLEX_SERVER_BASE_URL"].to_s.delete_suffix("/")
    token = ENV["PLEX_TOKEN"].to_s
    return if base_url.blank? || token.blank?

    uri = URI(path.start_with?("http") ? path : "#{base_url}#{path.start_with?("/") ? path : "/#{path}"}")
    query = URI.decode_www_form(uri.query.to_s)
    query << [ "X-Plex-Token", token ] unless query.any? { |key, _value| key == "X-Plex-Token" }
    uri.query = URI.encode_www_form(query)
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def plex_timestamp(value)
    return "Never" if value.blank?

    l(Time.zone.at(value.to_i), format: :long)
  end

  def optional_plex_timestamp(value)
    return "Unknown" if value.blank?

    plex_timestamp(value)
  end

  def users_sort_link(label, sort)
    active = @sort == sort
    next_direction = active && @direction == "asc" ? "desc" : "asc"
    indicator = active ? (@direction == "asc" ? "▲" : "▼") : "↕"
    aria_label = if active
      "#{label}, sorted #{@direction == 'asc' ? 'ascending' : 'descending'}. Activate to sort #{next_direction == 'asc' ? 'ascending' : 'descending'}."
    else
      "#{label}, not sorted. Activate to sort #{next_direction == 'asc' ? 'ascending' : 'descending'}."
    end

    link_to users_path(request.query_parameters.merge(sort: sort, direction: next_direction)), class: "inline-flex items-center gap-1 hover:text-white", aria: { label: aria_label } do
      safe_join([
        label,
        tag.span(indicator, aria: { hidden: true }, class: "text-[0.68rem] leading-none text-zinc-500")
      ], " ")
    end
  end
end
