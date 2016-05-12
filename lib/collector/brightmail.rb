# encoding: utf-8
require 'net/http'
require 'timeout'
require 'json'
require 'error_logger'

module Collector
  module Brightmail
    include ErrorLogger

    def brightmail_reputation(ip)
      reputation = 'error'

      url = "http://www.symantec.com/s/wl-brightmail/ip/#{ip}.json"
      uri = URI.parse(url)

      begin
        Timeout.timeout(10) do
          http = Net::HTTP.new(uri.host, uri.port)
          response = http.get(uri.request_uri)

          json = JSON.parse(response.body)
          reputation = json['entityRecord']['rep']
        end
      rescue JSON::ParserError => error
        log_error('Unparsable JSON returned from symantec/brightmail reputation data query')
        log_error("JSON parser error returned: #{error}")
      rescue Timeout::Error,
             Errno::EINVAL,
             Errno::ECONNRESET,
             EOFError,
             Net::HTTPBadResponse,
             Net::HTTPHeaderSyntaxError,
             Net::ProtocolError => error

        log_error('Problem encountered while retrieving symantec/brightmail reputation data')
        log_error("Brightmail reputation http query returned: #{error}")
      end

      return reputation
    end
  end
end
