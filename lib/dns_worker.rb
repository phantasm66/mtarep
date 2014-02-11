require 'resolv'
require 'timeout'
require 'error_logger'

module DnsWorker

  include ErrorLogger

  def dns_lookup(ip, query_host)
    reversed_ip = ip.split('.').reverse.join('.')
    count = 0

    begin
      Timeout.timeout(3) do
        response = Resolv.new.getaddress("#{reversed_ip}.#{query_host}")

        if query_host == 'score.senderscore.com'
          results = response.split('.')[3]
        else
          results = query_host
        end

        return results
      end
    rescue Resolv::ResolvError
      if query_host == 'score.senderscore.com'
        return 'no score'
      else
        return []
      end
    rescue => error
      count += 1
      sleep 1
      retry if count < 3

      log_error('Problem encountered during a dns lookup operation')
      log_error("DNS lookup returned: #{error}")
    end
  end
end
