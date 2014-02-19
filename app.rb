#!/usr/bin/env ruby

$:.unshift File.expand_path('lib')
$:.unshift File.expand_path('lib/collector')

require 'sinatra'
require 'digest/sha1'
require 'redis'
require 'yaml'
require 'net/https'
require 'uri'
require 'redis_worker'
require 'collector/hosts'

include RedisWorker
include Collector::Hosts

configure do
  set :config_options, YAML.load_file('config/mtarep.yml')
  set :this_version, IO.read('VERSION').chomp
  set :public_folder, Proc.new { File.join(root, 'vendor') }

  set :environment, :production
  set :show_exceptions, true
  enable :sessions, :logging

  authfile = settings.config_options['http_auth_file']
  authlist = IO.read(authfile).split("\n")

  use Rack::Auth::Basic, 'Protected Area' do |user, pass|
    set :username, user
    pass = Digest::SHA1.base64digest(pass)
    match = authlist.grep(/#{user}:/)
    match = match[0].split(':{SHA}') unless match.empty?
    user == match[0] && pass == match[1]
  end
end

before do
  @mta_keys = []
  @redis = redis_connection(settings.config_options['redis_host'])
  @graph_domains = settings.config_options['graph_domains']

  mta_map(settings.config_options['mta_map']).each {|hash| @mta_keys << hash[:ip]}
end

get '/' do
  count = 0
  begin
    @assistance_links = settings.config_options['assistance_links']
    @provider_block_strings = settings.config_options['provider_block_strings']
    @mta_redis_data_hash = {}

    @mta_keys.each do |ip|
      @mta_redis_data_hash[ip] = @redis.lrange(ip, 0, -1)
      new_hash = @mta_redis_data_hash.clone

      @mta_redis_data_hash.each_pair {|ip ,data| new_hash[ip] = Hash[*data.flatten]}
      @mta_redis_data_hash = new_hash
    end
  rescue
    count += 1
    sleep 1
    retry unless count > 5
  end
  erb :main
end

get '/help' do
  erb :help
end

get '/graphs' do
  fbl = []
  sent = []
  bounced = []
  expired = []

  date = Time.now.to_s.split[0].gsub('-', '')

  def graph_counts(type, graph_domains)
    results = type.inject {|x, y| x.merge(y) {|k, ov, nv| ov + nv}}

    if results.nil?
      results = {}
      graph_domains.each{|domain| results[domain] = 0}
    end

    counts = []
    graph_domains.each {|domain| counts << results[domain]}

    return counts
  end

  count = 0
  begin
    graph_keys = @redis.keys("*:#{date}:*")
  rescue
    count += 1
    retry unless count > 5
  end

  graph_keys_new = graph_keys.clone

  graph_keys.each do |key|
    if key =~ /:bounced/
      graph_keys_new.delete(key) unless graph_keys.include?(key.gsub('bounced', 'sent'))
    end
  end

  graph_keys_new.each do |graph_key|
    @graph_domains.each do |domain|
      count = @redis.hget(graph_key, domain)
      count = 0 if count.nil?
      count = count.to_i

      if graph_key.split(':')[2] == 'sent'
        sent << {domain => count}
      elsif graph_key.split(':')[2] == 'expired'
        expired << {domain => count}
      elsif graph_key.split(':')[2] == 'fbl'
        fbl << {domain => count}
      else
        bounced << {domain => count}
      end
    end
  end

  @fbl_data = graph_counts(fbl, @graph_domains)
  @sent_data = graph_counts(sent, @graph_domains)
  @bounced_data = graph_counts(bounced, @graph_domains)
  @expired_data = graph_counts(expired, @graph_domains)

  erb :graphs
end

get '/version' do
  def latest_version
    begin
      uri = URI.parse('https://raw.github.com/phantasm66/mtarep/master/VERSION')

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      if response.code.to_s == '200'
        response.body.to_s
      else
        response.code.to_s
      end
    rescue SocketError => error
      return error
    end
  end

  @this_version = settings.this_version
  @latest_version = latest_version

  erb :version
end

post '/ack' do
  timestamp = Time.now.to_s.split[0..1].join(' ')
  key = params[:ack]
  count = 0
  begin
    @redis.set(key, "#{settings.username} #{timestamp}")
  rescue
    count += 1
    retry unless count > 5
  end
  redirect to('/')
end

