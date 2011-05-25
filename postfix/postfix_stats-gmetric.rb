#!/usr/bin/env ruby

require 'rubygems'
require 'gmetric'
require 'yaml'

POSTFIX_LOG = '/var/log/mail.log'
TMP_FILE = '/tmp/mail.tmp.yml'

IP = 'localhost' # Ganglia IP/Hostname (the host under udp_send_channel)
PORT = 8649
METRIC_GNAME = 'postfix'

def ganglia_send(metric, value, units='msgs/sec', type='float')
  Ganglia::GMetric.send(IP, PORT, {
    :name => metric,
    :group => METRIC_GNAME,
    :units => units,
    :type => type,
    :value => value,
    :tmax => 60,
    :dmax => 120
  })
end

def mailq
  in_queue = `/usr/sbin/qshape deferred | grep TOTAL | awk '{print $2}'`.strip.to_i
  ganglia_send('in_queue', in_queue, 'messages', 'uint8')
end

def read_log
  stats = {
    :incoming => 0,
    :outgoing => 0,
    :bounced => 0,
    :rejected => 0,
    :deferred => 0,
    :local => 0
  }
  File.open(POSTFIX_LOG).each_line do |line|
    case line
      when /status=sent/ && /relay=filter/
        stats[:incoming] += 1
      when /status=sent/ && /relay=local/
        stats[:local] += 1
      when /status=sent/
        stats[:outgoing] += 1
      when /status=bounced/
        stats[:bounced] += 1
      when /status=deferred/
        stats[:deferred] += 1
      when /NOQUEUE/
        stats[:rejected] += 1
    end
  end
  return stats
end

begin
  new_stats = read_log
rescue Errno::ENOENT => e
  puts e
  exit 1
end

if File.exists?(TMP_FILE)
  old_time = File.stat(TMP_FILE).mtime
  old_stats = YAML.load(File.read(File.expand_path(TMP_FILE)))
else
  puts 'Creating baseline, no data reported'
end

if old_stats && old_time
  time_diff = Time.now - old_time
  if time_diff < 1
    puts 'time difference needs to be > 1 second'
    exit 1
  end
  new_stats.each do |metric, value|
    if metric == :incoming || metric == :outgoing
      diff = value - old_stats[metric]
      diff > 0 | diff = 0
      ganglia_send('total_'+metric.to_s, diff, 'messages')
    end
    rate = (value - old_stats[metric]) / time_diff
    if rate >= 0
      ganglia_send(metric, rate)
    end
  end
end

mailq
File.open(TMP_FILE, 'w').write(new_stats.to_yaml)
