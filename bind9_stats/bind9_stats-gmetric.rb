#!/usr/bin/env ruby
# Based on original perl script from Vladimir Vuksan (http://vuksan.com/linux/ganglia/#Bind_stats)
# Vladimir's script didn't work with BIND9.7+ stats file

require 'rubygems'
require 'gmetric' # for easy injection into running gmond

$rndc_exec = '/usr/sbin/rndc' # rndc location
$namedstats = '/var/cache/bind/named.stats' # location of new stats file
$tmp_dir = '/tmp/bindgmetric' # where to store last file


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
    puts "rndc stats"
    system("echo :> #{$namedstats}; #{$rndc_exec} stats && grep -A 9 'Name Server Statistics' #{$namedstats} | grep -v '++' | grep queries > #{$tmp_stats_file}")
end

def read_file
    hash = {}
    time = 0
    File.open($tmp_stats_file) do |s|
        s.each do |line|
            value = line.split(' ')[0]
            metric = line.split(' ')[-3..-1].join('_')
            hash[metric] = value
        end
    time = s.stat.mtime
    end
    return hash, time
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
end
