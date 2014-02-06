require 'resolv'

module Collector
  module Hosts
    def mta_map(hostnames)
      mta_hash = {}
      ips = []

      hostnames.each do |hostname|
        # dig.. in case results are huge!
        results = %x{dig #{hostname} +short +tcp}
        ips << results.split("\n")
      end

      ips.flatten!

      count = 0
      ips.each do |ip|
        begin
          mta = Resolv.new.getname(ip)
        rescue
          count += 1
          retry unless count > 5

          log_error("Unable to resolve rDNS for #{ip}... skipping")
          next
        end

        mta_hash[ip] = mta
      end

      return mta_hash
    end
  end
end
