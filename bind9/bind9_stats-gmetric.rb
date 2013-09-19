#!/usr/bin/env ruby
# Based on original perl script from Vladimir Vuksan (http://vuksan.com/linux/ganglia/#Bind_stats)
# Vladimir's script didn't work with BIND9.7+ stats file
# 
# Edited kmullin's script to use gmetric binary instead of the gmetric gem.

require 'rubygems'

DEBUG = false
NAMEDSTATS = '/var/cache/bind/named.stats' # location of new stats file
TMP_DIR = '/var/cache/bind/named.stats.last' # where to store last file

GMETRIC_EXEC = "/usr/bin/gmetric";
unless File.executable_real?(GMETRIC_EXEC)
  puts "Cannot exec #{GMETRIC_EXEC}"
  exit 1
end
GMETRIC_OPTIONS = "-d 120 -u queries/sec -tfloat -n";
GMETRIC_CMD = "#{GMETRIC_EXEC} #{GMETRIC_OPTIONS}"

RNDC_EXEC = "/usr/sbin/rndc"
unless File.executable_real?(RNDC_EXEC)
  puts "Cannot exec #{RNDC_EXEC}"
  exit 1
end

unless File.directory?(TMP_DIR)
  puts 'no tmp dir; creating'
  system("mkdir -p #{TMP_DIR}")
end

class BindGMetric
  def initialize
    @tmp_stats_file = "#{TMP_DIR}/bindstats"
    @counter_metrics = {
      "in_successful_answer" => nil,
      "caused_recursion" => nil,
      "non_authoritative_answer" => nil,
      "resulted_in_nxrrset" => nil,
      "resulted_in_SERVFAIL" => nil,
      "resulted_in_NXDOMAIN" => nil,
      "in_authoritative_answer" => nil
    }
  end

  def reset_stats
    system(":> #{NAMEDSTATS}; #{RNDC_EXEC} stats && grep -A 16 'Name Server Statistics' #{NAMEDSTATS} | grep -v '++' | grep queries > #{@tmp_stats_file}")
  end

  def read_file
    hash = {}
    f = File.open(@tmp_stats_file)
    f.each do |line|
      value = line.split[0].to_i
      metric = line.split[-3..-1].delete_if { |x| x =~ /\d/ }.join('_').gsub('queries_', '')
      hash[metric] = value
    end
    return hash, f.stat.mtime
  end

  def send_metrics(metric, value)
    `#{GMETRIC_CMD} dns_#{metric} -v #{value}` unless DEBUG
    log "#{metric} = #{value}/sec"
  end

  def run
    unless File.exist?(@tmp_stats_file)
      # no previous data, clean stats file and re stat
      log 'Creating baseline, no data reported'
      reset_stats
    else
      # open old file and read data to get baseline
      old_data, old_time = read_file
      # we read old data, now need new one
      reset_stats
      new_data, new_time = read_file
      time_difference = new_time - old_time
      if time_difference < 1
        log 'needs to be longer than a second'
        return 1
      end
      old_data.each_key do |metric|
        rate = (new_data[metric] - old_data[metric]) / time_difference
        if rate < 0
          log 'Somethings wrong. Rate for ' +  metric + ' shouldnt be negative.'
        else
          send_metrics(metric, rate) if @counter_metrics.keys.include?(metric)
        end
      end
    end
  end

  def log(msg)
    puts msg if DEBUG
  end

end

a = BindGMetric.new
a.run
