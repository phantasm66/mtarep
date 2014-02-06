module Collector
  module Rbls
    def rbl_listings(ip)
      hash = {}
      array = []

      rbls.each do |rbl_host|
        results = dns_lookup(ip, rbl_host)
        array << results
      end

      listings = listings.join(',')
      hash[ip] = listings

      return hash
    end
  end
end
