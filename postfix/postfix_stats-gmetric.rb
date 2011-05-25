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
  File.open(POSTFIX_LOG) do |s|
    s.each do |line|
      case line
      when /status=sent/
        case line
        when /relay=filter/
          incoming_count += 1
        when /relay=local/
          # do nothing for local delivery
        else
          outgoing_count += 1
        end
      when /status=bounced/
        bounce_count += 1
      when /status=deferred/
        deferred_count += 1
      when /NOQUEUE/
        reject_count += 1
      end
    end
  end
  puts incoming_count, outgoing_count, bounce_count, reject_count, deferred_count
end


puts 'starting'
read_log
