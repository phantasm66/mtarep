# encoding: utf-8
require 'resolv'
require 'timeout'
require 'error_logger'

module DnsWorker
  include ErrorLogger

  def resolver(name, option={})
    begin
      Timeout.timeout(5) do
        results = Resolv.getaddress(name)

        if option[:query_type] == 'rbldns'
          raise Resolv::ResolvError unless results.match(/^127\./)
        end

        return results
      end
    rescue Resolv::ResolvError
      return String.new
    rescue Timeout::Error => error
      log_error("Problem encountered during a dns lookup for #{name}")
      log_error("DNS lookup returned: #{error}")

      return String.new
    end
  end

  def dns_match?(ip, name)
    check_smtp = '/usr/lib64/nagios/plugins/check_smtp'
    check_smtp = '/usr/local/nrpe/libexec/check_smtp' unless File.exist?(check_smtp)

    begin
      Timeout.timeout(10) do
        smtp_host = name.split('.')[0]

        session_output = %x{#{check_smtp} -v -H #{smtp_host}}
        session_output = session_output.split("\n")

        helo = session_output.select {|x| x.match(/220\s.*ESMTP\sPostfix/)}
        helo = helo[0].split unless helo.empty?
        helo.select! {|x| x.match(name)}

        fwd = resolver(name)
        rev = Resolv.getname(ip)

        raise Resolv::ResolvError, 'HELO' if helo[0].nil?
        raise Resolv::ResolvError, 'rDNS' unless rev == name
        raise Resolv::ResolvError, 'fDNS' unless fwd == ip

        return '<span style="color:green">&#x2714;</span>'
      end
    rescue Resolv::ResolvError => issue
      return "<span style='color:red'>#{issue}</span>"
    rescue Timeout::Error => error
      log_error("Problem encountered during a reverse dns lookup for #{ip}")
      log_error("DNS lookup returned: #{error}")

      return '<span style="color:red">&#x2718;</span>'
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
