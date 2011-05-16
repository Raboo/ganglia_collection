#!/usr/bin/env ruby
# Based on original perl script from Vladimir Vuksan (http://vuksan.com/linux/ganglia/#Bind_stats)
# Vladimir's script didn't work with BIND9.7+ stats file

require 'rubygems'
require 'gmetric' # for easy injection into running gmond

$ip = 'localhost' # Ganglia IP/Hostname
$port = 8649

$rndc_exec = '/usr/sbin/rndc' # rndc location
$namedstats = '/var/cache/bind/named.stats' # location of new stats file
$tmp_dir = '/tmp/bindgmetric' # where to store last file

$counter_metrics = {
    "in_successful_answer" => nil,
    "caused_recursion" => nil,
    "non_authoritative_answer" => nil,
    "resulted_in_nxrrset" => nil,
    "resulted_in_SERVFAIL" => nil,
    "resulted_in_NXDOMAIN" => nil,
    "in_authoritative_answer" => nil
}

###############
#DO NOT EDIT
#
if File.executable_real?($rndc_exec) == false
    puts "Cannot exec #{$rndc_exec}"
    exit 1
end

$tmp_stats_file = "#{$tmp_dir}/bindstats"
if File.directory?($tmp_dir) == false
    puts 'no tmp dir; creating'
    system("mkdir -p #{$tmp_dir}")
end

def reset_stats
    system("echo :> #{$namedstats}; #{$rndc_exec} stats && grep -A 9 'Name Server Statistics' #{$namedstats} | grep -v '++' | grep queries > #{$tmp_stats_file}")
end

def read_file
    hash = {}
    time = 0
    File.open($tmp_stats_file) do |s|
        s.each do |line|
            value = line.split(' ')[0].to_i
            metric = line.split(' ')[-3..-1].join('_').gsub('queries_', '')
            hash[metric] = value
        end
    time = s.stat.mtime
    end
    return hash, time
end

def ganglia_send(metric, value)
    Ganglia::GMetric.send($ip, $port, {
        :name => metric,
        :units => 'queries/sec',
        :type => 'float',
        :value => value,
        :tmax => 60,
        :dmax => 120
    })
end

if File.exist?($tmp_stats_file) == false
    # no previous data, clean stats file and re stat
    puts 'Creating baseline, no data reported'
    reset_stats
else
    # open old file and read data to get baseline
    old_data, old_time = read_file
    # we read old data, now need new one
    reset_stats
    new_data, new_time = read_file
    time_difference = new_time - old_time
    if time_difference < 1
        puts 'needs to be longer than a second'
        exit 1
    end
    $counter_metrics.each do |metric, value|
        rate = (new_data[metric] - old_data[metric]) / time_difference
        if rate < 0
            puts 'Somethings wrong. Rate for '+  metric + ' shouldnt be negative.'
        else
            puts "#{metric} = #{rate}/sec"
            ganglia_send(metric, value)
        end
    end
end
