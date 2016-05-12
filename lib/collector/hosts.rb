# encoding: utf-8
require 'dns_worker'
require 'error_logger'

module Collector
  module Hosts
    include DnsWorker
    include ErrorLogger

    def mta_map(hostname_map)
      mta_data = []

      if hostname_map.class == Hash
        hostname_map.each_pair do |shortname, host_info|
          fqdn = "#{shortname}.bluestatedigital.com"
          results = resolver(fqdn)
          mta_data << {
            :shortname => shortname,
            :ssh_host => host_info['ssh_host'],
            :maillog_path => host_info['maillog_path'],
            :ip => results,
            :fqdn => fqdn
          }
        end

      ###
      ### why the fuck did i add this ?
      ###
      elsif hostname_map.class == Array
        hostname_map.each do |fqdn|
          results = resolver(fqdn)
          mta_data << {:alias => fqdn, :ip => results, :fqdn => fqdn}
        end
      else
        log_error("the 'mta_map' config must be a YAML hash or array collection!")
        log_error("please review the 'Configuration' section of the README")

        exit
      end

      return mta_data
    end
  end
end
