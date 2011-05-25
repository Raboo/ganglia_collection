#!/usr/bin/env ruby

require 'rubygems'
require 'gmetric'

POSTFIX_LOG = 'mail.log'

#GMOND
IP = 'localhost' # Ganglia IP/Hostname
PORT = 8649
METRIC_GNAME = 'postfix'

def ganglia_send(metric, value)
  Ganglia::GMetric.send(IP, PORT, {
    :name => metric,
    :group => METRIC_GNAME,
    :units => 'queries/sec',
    :type => 'float',
    :value => value,
    :tmax => 60,
    :dmax => 120
  })
end

def read_log
  incoming_count = 0
  outgoing_count = 0
  bounce_count = 0
  reject_count = 0
  deferred_count = 0
  File.open(POSTFIX_LOG).each_line do |line|
    case line
      when /status=sent/ && /relay=filter/
        incoming_count += 1
      when /status=sent/ && /relay=local/
        # do nothing for local delivery
      when /status=sent/
        outgoing_count += 1
      when /status=bounced/
        bounce_count += 1
      when /status=deferred/
        deferred_count += 1
      when /NOQUEUE/
        reject_count += 1
    end
  end
  puts incoming_count, outgoing_count, bounce_count, reject_count, deferred_count
end

begin
  read_log
rescue Errno::ENOENT => e
  puts e
  exit 1
end
