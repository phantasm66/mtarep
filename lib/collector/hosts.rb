require 'dns_worker'

module Collector
  module Hosts

    include DnsWorker

    def mta_map(hostname_map)
      mta_data = []

      if hostname_map.class == Hash
        hostname_map.each_pair do |alias_name, fqdn|
          results = resolver(fqdn)
          mta_data << {:alias => alias_name, :ip => results, :fqdn => fqdn}
        end
      elsif hostname_map.class == Array
        hostname_map.each do |fqdn|
          results = resolver({:string => fqdn, :type => 'forward'})
          mta_data << {:alias => fqdn, :ip => results, :fqdn => fqdn}
        end
      end

      return mta_data
    end
  end
end
