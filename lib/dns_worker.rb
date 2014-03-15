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

  def query_host(ip, base_host)
    reversed_ip = ip.split('.').reverse.join('.')
    host = [reversed_ip, base_host].join('.')

    return host
  end

  def rbl_lookup(ip, base_host)
    response = resolver(query_host(ip, base_host), {:query_type => 'rbldns'})

    response.empty? ? response : base_host
  end

  def score_lookup(ip)
    response = resolver(query_host(ip, 'score.senderscore.com'), {:query_type => 'rbldns'})

    response.empty? ? 'no score' : response.split('.')[3]
  end
end
