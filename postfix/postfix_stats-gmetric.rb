#!/usr/bin/env ruby

require 'rubygems'
require 'gmetric'
require 'yaml'

POSTFIX_LOG = 'mail.log'
TMP_FILE = 'mail.tmp'

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
    "incoming_count" => 0,
    "outgoing_count" => 0,
    "bounce_count" => 0,
    "reject_count" => 0,
    "deferred_count" => 0
  }
  File.open(POSTFIX_LOG).each_line do |line|
    case line
      when /status=sent/ && /relay=filter/
        stats['incoming_count'] += 1
      when /status=sent/ && /relay=local/
        # do nothing for local delivery
      when /status=sent/
        stats['outgoing_count'] += 1
      when /status=bounced/
        stats['bounce_count'] += 1
      when /status=deferred/
        stats['deferred_count'] += 1
      when /NOQUEUE/
        stats['reject_count'] += 1
    end
  end
  return stats
end

def make_metrics(old, new)

end

if File.exists?(TMP_FILE)
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

File.open(TMP_FILE, 'w').write(new_stats.to_yaml)
