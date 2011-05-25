#!/usr/bin/env ruby

require 'rubygems'
require 'gmetric'

$ip = 'localhost' # Ganglia IP/Hostname
$port = 8649
$metric_group_name = 'bind9'

def ganglia_send(metric, value)
  Ganglia::GMetric.send($ip, $port, {
    :name => metric,
    :group => $metric_group_name,
    :units => 'queries/sec',
    :type => 'float',
    :value => value,
    :tmax => 60,
    :dmax => 120
  })
end


