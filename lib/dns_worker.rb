require 'resolv'
require 'timeout'
require 'error_logger'

module DnsWorker

  include ErrorLogger

  def resolver(name)
    counter = 0

    begin
      Timeout.timeout(3) do
        results = Resolv.new.getaddress(name)
        return results
      end
    rescue Resolv::ResolvError
      return []
    rescue => error
      counter += 1
      sleep 1
      retry if counter < 3

      log_error('Problem encountered during a dns lookup operation')
      log_error("DNS lookup returned: #{error}")
    end
  end

  def rbl_lookup(ip, query_host)
    reversed_ip = ip.split('.').reverse.join('.')
    response = resolver("#{reversed_ip}.#{query_host}")

    if response.empty?
      return response
    else
      return query_host
    end
  end

  def score_lookup(ip)
    reversed_ip = ip.split('.').reverse.join('.')
    response = resolver("#{reversed_ip}.score.senderscore.com")

    if response.empty?
      return 'no score'
    else
      return response.split('.')[3]
    end
  end
end
