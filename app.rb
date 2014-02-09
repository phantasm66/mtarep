#!/usr/bin/env ruby

$: << 'lib' unless $:.include?('lib')
$: << 'lib/collector' unless $:.include?('lib/collector')

require 'sinatra'
require 'digest/sha1'
require 'redis'
require 'yaml'
require 'redis_worker'
require 'hosts'

configure do
  set :public_folder, Proc.new { File.join(root, 'vendor') }
  set :environment, :production
  set :show_exceptions, true
  enable :sessions, :logging

  authfile = '/home/httpd/local/htpasswd'
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
  config = YAML.load_file('config/mtarep-conf.yml')
  @redis = redis_connection(config['redis_host'])
  mta_map(config['mta_map']).each_pair {|ip, mta| @mta_keys << ip}

  graph_domains = config['graph_domains']

  date = Time.now.to_s.split[0].gsub('-', '')

  fbl = []
  sent = []
  bounced = []
  expired = []

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
    graph_domains.each do |domain|
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

  @fbl_data = graph_counts(fbl, graph_domains)
  @sent_data = graph_counts(sent, graph_domains)
  @bounced_data = graph_counts(bounced, graph_domains)
  @expired_data = graph_counts(expired, graph_domains)
end

get '/' do
  count = 0
  begin
    @hash = Hash.new

    @mta_keys.each do |ip|
      @hash[ip] = @redis.lrange(ip, 0, -1)
      new_hash = @hash.clone

      @hash.each_pair {|ip ,data| new_hash[ip] = Hash[*data.flatten]}
      @hash = new_hash
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
  erb :graphs
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

