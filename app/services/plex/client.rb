require "json"
require "net/http"
require "rexml/document"
require "openssl"
require "securerandom"
require "uri"

module Plex
  class Client
    class Error < StandardError; end

    DEFAULT_BASE_URL = "https://plex.tv"

    def self.from_env
      token = ENV["PLEX_TOKEN"].presence
      raise ConfigurationError, "Missing PLEX_TOKEN in .env" unless token

      new(
        token: token,
        base_url: ENV.fetch("PLEX_API_BASE_URL", DEFAULT_BASE_URL),
        server_base_url: ENV["PLEX_SERVER_BASE_URL"].presence,
        client_identifier: ENV.fetch("PLEX_CLIENT_IDENTIFIER", "plex-shares-local"),
        client_name: ENV.fetch("PLEX_CLIENT_NAME", "Plex Shares")
      )
    end

    def initialize(token:, base_url: DEFAULT_BASE_URL, server_base_url: nil, client_identifier: nil, client_name: "Plex Shares")
      @token = token
      @base_url = base_url.delete_suffix("/")
      @server_base_url = server_base_url&.delete_suffix("/")
      @client_identifier = client_identifier.presence || SecureRandom.uuid
      @client_name = client_name
    end

    def users
      media_container(fetch("/api/users"))[:users]
    end

    def servers
      media_container(fetch("/api/servers"))[:servers]
    end

    def server(machine_identifier)
      server_document(fetch("/api/servers/#{machine_identifier}"))
    end

    def shared_servers(machine_identifier)
      shared_server_document(fetch("/api/servers/#{machine_identifier}/shared_servers"))
    end

    def requested_invites
      media_container(fetch("/api/invites/requested"))[:invites]
    end

    def cancel_requested_invite(invite_id, friend:, home:, server:)
      request(
        "/api/invites/requested/#{invite_id}",
        method: :delete,
        params: {
          friend: truthy_value(friend),
          home: truthy_value(home),
          server: truthy_value(server)
        }
      )
    end

    def playback_history(account_id: nil, size: 100, offset: 0)
      return [] unless server_base_url.present?

      params = {
        sort: "viewedAt:desc",
        "X-Plex-Container-Start": offset,
        "X-Plex-Container-Size": size
      }
      params[:accountID] = account_id if account_id.present?

      media_container(server_fetch("/status/sessions/history/all", params: params))[:metadata]
    end

    def update_shared_server(machine_identifier, shared_server_id, library_section_ids)
      request_json(
        "/api/servers/#{machine_identifier}/shared_servers/#{shared_server_id}",
        method: :put,
        payload: {
          server_id: machine_identifier,
          shared_server: { library_section_ids: library_section_ids }
        }
      )
    end

    def create_shared_server(machine_identifier, invited_email, library_section_ids, allow_sync: false, allow_channels: false)
      request_json(
        "/api/servers/#{machine_identifier}/shared_servers",
        method: :post,
        payload: {
          server_id: machine_identifier,
          shared_server: {
            library_section_ids: library_section_ids,
            invited_email: invited_email
          },
          sharing_settings: {
            allowSync: allow_sync ? "1" : "0",
            allowChannels: allow_channels ? "1" : "0"
          }
        }
      )
    end

    def remove_shared_server(machine_identifier, shared_server_id)
      request_json(
        "/api/servers/#{machine_identifier}/shared_servers/#{shared_server_id}",
        method: :delete,
        payload: {
          server_id: machine_identifier,
          shared_server: { library_section_ids: [] }
        }
      )
    end

    private

    attr_reader :token, :base_url, :server_base_url, :client_identifier, :client_name

    def fetch(path)
      request(path, method: :get)
    end

    def server_fetch(path, params: {})
      request(path, method: :get, base: server_base_url, params: params)
    end

    def request_json(path, method:, payload:)
      request(path, method: method, body: JSON.generate(payload), headers: { "Content-Type" => "application/json" })
    end

    def request(path, method:, base: base_url, params: {}, body: nil, headers: {})
      uri = URI("#{base}#{path}")
      query_params = URI.decode_www_form(uri.query.to_s)
      query_params.concat(params.map { |key, value| [ key.to_s, value ] })
      query_params << [ "X-Plex-Token", token ]
      query_params << [ "X-Plex-Client-Identifier", client_identifier ]
      query_params << [ "X-Plex-Product", client_name ]
      uri.query = URI.encode_www_form(query_params)

      request = request_class(method).new(uri)
      request["Accept"] = "application/xml, application/json"
      headers.each { |key, value| request[key] = value }
      request.body = body if body.present?

      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 5,
        read_timeout: 10,
        write_timeout: 10
      ) do |http|
        http.request(request)
      end

      return response.body if response.is_a?(Net::HTTPSuccess)

      raise Error, "Plex API returned #{response.code} for #{path}"
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError => error
      raise Error, "Could not reach Plex API: #{error.message}"
    end

    def request_class(method)
      {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        put: Net::HTTP::Put,
        delete: Net::HTTP::Delete
      }.fetch(method)
    end

    def truthy_value(value)
      value == true || value.to_s == "1" || value.to_s.casecmp("true").zero? ? 1 : 0
    end

    def media_container(body)
      if body.lstrip.start_with?("{")
        json_media_container(JSON.parse(body))
      else
        xml_media_container(REXML::Document.new(body))
      end
    rescue JSON::ParserError, REXML::ParseException => error
      raise Error, "Plex API returned an unreadable response: #{error.message}"
    end

    def json_media_container(payload)
      container = payload.fetch("MediaContainer", payload)
      {
        users: Array(container["User"]).map { |user| normalize_user_hash(user) },
        servers: Array(container["Server"]).map { |server| normalize_hash(server) },
        invites: Array(container["Invite"]).map { |invite| normalize_invite_hash(invite) },
        metadata: Array(container["Metadata"]).map { |metadata| normalize_hash(metadata) }
      }
    end

    def xml_media_container(document)
      {
        users: elements(document, "//User").map { |element| user_attributes(element) },
        servers: elements(document, "//Server").map { |element| attributes(element) },
        invites: elements(document, "//Invite").map { |element| invite_attributes(element) },
        metadata: elements(document, "//Video|//Track|//Metadata").map { |element| attributes(element) }
      }
    end

    def server_document(body)
      document = REXML::Document.new(body)
      server = elements(document, "//Server").first
      {
        server: server ? attributes(server) : {},
        sections: elements(document, "//Section").map { |section| attributes(section) }
      }
    rescue REXML::ParseException => error
      raise Error, "Plex server response was unreadable: #{error.message}"
    end

    def shared_server_document(body)
      document = REXML::Document.new(body)
      elements(document, "//SharedServer").map do |shared_server|
        attributes(shared_server).merge(
          user: attributes(elements(shared_server, "User").first),
          sections: elements(shared_server, "Section").map { |section| attributes(section) }
        )
      end
    rescue REXML::ParseException => error
      raise Error, "Plex shared server response was unreadable: #{error.message}"
    end

    def elements(source, xpath)
      REXML::XPath.match(source, xpath)
    end

    def attributes(element)
      return {} unless element

      normalize_hash(element.attributes.each_with_object({}) { |(key, value), memo| memo[key] = value })
    end

    def user_attributes(element)
      attributes(element).merge(
        servers: elements(element, "Server").map { |server| attributes(server) }
      )
    end

    def normalize_user_hash(hash)
      normalized = normalize_hash(hash)
      normalized[:servers] = Array(hash["Server"]).map { |server| normalize_hash(server) }
      normalized
    end

    def invite_attributes(element)
      attributes(element).merge(
        servers: elements(element, "Server").map { |server| attributes(server) }
      )
    end

    def normalize_invite_hash(hash)
      normalized = normalize_hash(hash)
      normalized[:servers] = Array(hash["Server"]).map { |server| normalize_hash(server) }
      normalized
    end

    def normalize_hash(hash)
      hash.transform_keys { |key| key.to_s.underscore.to_sym }
    end
  end
end
