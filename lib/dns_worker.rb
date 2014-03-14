# encoding: utf-8
require 'resolv'
require 'timeout'
require 'error_logger'

module DnsWorker

  include ErrorLogger

  def resolver(name, option={})
    counter = 0

    begin
      Timeout.timeout(5) do
        results = Resolv.new.getaddress(name)

        if option[:query_type] == 'rbldns'
          raise Resolv::ResolvError unless results.match(/^127\./)
        end

        return results
      end
    rescue Resolv::ResolvError
      return String.new
    rescue => error
      counter += 1
      sleep 1
      retry if counter < 3

      log_error("Problem encountered during a dns lookup for #{name}")
      log_error("DNS lookup returned: #{error}")

      return String.new
    end
  end

  def rbl_lookup(ip, query_host)
    reversed_ip = ip.split('.').reverse.join('.')
    rbl_query = [reversed_ip, query_host].join('.')
    response = resolver(rbl_query, {:query_type => 'rbldns'})

    response.empty? ? response : query_host
  end

  def score_lookup(ip)
    reversed_ip = ip.split('.').reverse.join('.')
    senderscore_query = [reversed_ip, 'score.senderscore.com'].join('.')
    response = resolver(senderscore_query, {:query_type => 'rbldns'})

    response.empty? ? 'no score' : response.split('.')[3]
  end
end
