#!/usr/bin/env ruby

$: << 'lib' unless $:.include?('lib')
$: << 'lib/collector' unless $:.include?('lib/collector')

require 'runner'
require 'config_parser'
require 'yaml'

config = YAML.load_file('config/mtarep-conf.yml')

ENV['ERROR_LOG'] = config['error_log']

run_collector({ :active_pid => Process.pid,
                :command => File.expand_path($0),
                :rbls => config['rbls'],
                :mta_map => config['mta_map'],
                :snds_key => config['snds_key'],
                :block_strings => config['block_strings'],
                :ssh_user => config['ssh_user'],
                :ssh_key => config['ssh_key'],
                :maillog => config['maillog_path'],
                :redis_host => config['redis_host'],
                :removal_links => config['removal_links'] })
