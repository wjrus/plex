require "net/http"
require "uri"

class PlexCoversController < ApplicationController
  def show
    uri = cover_uri
    response = fetch_cover(uri)

    if response.is_a?(Net::HTTPSuccess)
      expires_in 1.hour, public: false
      send_data response.body,
        type: response["Content-Type"].presence || "image/jpeg",
        disposition: "inline"
    else
      head :not_found
    end
  rescue Plex::ConfigurationError, URI::InvalidURIError
    head :not_found
  rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT
    head :bad_gateway
  end

  private

  def cover_uri
    path = params.require(:path).to_s
    raise URI::InvalidURIError, "invalid Plex cover path" unless path.start_with?("/")

    base_url = ENV["PLEX_SERVER_BASE_URL"].to_s.delete_suffix("/")
    token = ENV["PLEX_TOKEN"].to_s
    raise Plex::ConfigurationError, "Missing PLEX_SERVER_BASE_URL" if base_url.blank?
    raise Plex::ConfigurationError, "Missing PLEX_TOKEN" if token.blank?

    uri = URI("#{base_url}#{path}")
    query = URI.decode_www_form(uri.query.to_s)
    query << [ "X-Plex-Token", token ] unless query.any? { |key, _value| key == "X-Plex-Token" }
    uri.query = URI.encode_www_form(query)
    uri
  end

  def fetch_cover(uri)
    Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 10,
      write_timeout: 10
    ) do |http|
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
      http.request(request)
    end
  end
end
