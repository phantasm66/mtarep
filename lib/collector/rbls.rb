require 'dns_worker'

module Collector
  module Rbls

    include DnsWorker

    def rbl_listings(ip, rbls)
      listings_hash = {}
      listings = []

      rbls.each do |rbl_host|
        results = dns_lookup(ip, rbl_host)
        listings << results unless results.empty?
      end

      if listings.empty?
        listings = 'unlisted'
      else
        listings = listings.join(',')
      end

      listings_hash[ip] = listings

      return listings_hash
    end
  end
end
