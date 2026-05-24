module ApplicationHelper
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

    link_to users_path(sort: sort, direction: next_direction), class: "inline-flex items-center gap-1 hover:text-white", aria: { label: aria_label } do
      safe_join([
        label,
        tag.span(indicator, aria: { hidden: true }, class: "text-[0.68rem] leading-none text-zinc-500")
      ], " ")
    end
  end
end
