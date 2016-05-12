# encoding: utf-8
require 'net/http'
require 'timeout'
require 'error_logger'

module Collector
  module Snds
    include ErrorLogger

    def snds_data(snds_key)
      response = nil
      snds_hash = {}

      url = "https://postmaster.live.com/snds/data.aspx?key=#{snds_key}"
      uri = URI.parse(url)

      begin
        Timeout.timeout(30) do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE

          response = http.get(uri.request_uri)
          response = response.body
        end

        raise Errno::ECONNRESET if response.nil?

        response.each_line do |line|
          line = line.split(',')
          ip = line[0]
          color = line[6]
          traps = line[10]

          color = color.downcase
          snds_hash[ip] = [color, traps]
        end
      rescue Timeout::Error,
             Errno::EINVAL,
             Errno::ECONNRESET,
             EOFError,
             Net::HTTPBadResponse,
             Net::HTTPHeaderSyntaxError,
             Net::ProtocolError => error
        log_error('Problem encountered while retrieving microsoft snds data')
        log_error("Microsoft snds http query returned: #{error}")
      end

      return snds_hash
    end
  end
end
