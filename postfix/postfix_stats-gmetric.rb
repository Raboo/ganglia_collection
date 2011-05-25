#!/usr/bin/env ruby

require 'rubygems'
require 'gmetric'
require 'yaml'

POSTFIX_LOG = 'mail.log'
TMP_FILE = '/tmp/mail.tmp.yml'

#GMOND
IP = 'localhost' # Ganglia IP/Hostname
PORT = 8649
METRIC_GNAME = 'postfix'

def ganglia_send(metric, value)
  Ganglia::GMetric.send(IP, PORT, {
    :name => metric,
    :group => METRIC_GNAME,
    :units => 'msgs/sec',
    :type => 'float',
    :value => value,
    :tmax => 60,
    :dmax => 120
  })
end

def read_log
  stats = {
    "incoming" => 0,
    "outgoing" => 0,
    "bounced" => 0,
    "rejected" => 0,
    "deferred" => 0
  }
  File.open(POSTFIX_LOG).each_line do |line|
    case line
      when /status=sent/ && /relay=filter/
        stats['incoming'] += 1
      when /status=sent/ && /relay=local/
        # do nothing for local delivery
      when /status=sent/
        stats['outgoing'] += 1
      when /status=bounced/
        stats['bounced'] += 1
      when /status=deferred/
        stats['deferred'] += 1
      when /NOQUEUE/
        stats['rejected'] += 1
    end
  end
  return stats
end

def put_stats(stats)
  File.open(TMP_FILE, 'w').write(stats.to_yaml)
end

if File.exists?(TMP_FILE)
  old_time = File.stat(TMP_FILE).mtime
  old_stats = YAML.load(File.read(File.expand_path(TMP_FILE)))
else
  puts 'Creating baseline, no data reported'
end

begin
  new_stats = read_log
rescue Errno::ENOENT => e
  puts e
  exit 1
end

if old_stats
  new_time = Time.now
  new_stats.each do |metric, value|
    rate = (value - old_stats[metric]) / (new_time - old_time)
    ganglia_send(metric, rate)
  end
end

put_stats(new_stats)
