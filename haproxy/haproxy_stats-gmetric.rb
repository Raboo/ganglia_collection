#!/usr/bin/env ruby

require 'rubygems'
require 'gmetric'
require 'socket'
require 'faster_csv'

TMP_FILE = '/tmp/haproxy_stats.csv.tmp'

IP = '< gmond_ip >' # Ganglia IP/Hostname (the host under udp_send_channel)
PORT = < gmond_port >
METRIC_GNAME = 'haproxy'
DEBUG=false

def ganglia_send(metric, value, params=Hash.new)
  Ganglia::GMetric.send(IP, PORT, {
    :name => metric,
    :group => METRIC_GNAME,
    :units => params[:units] ||= 'reqs/sec',
    :type => params[:type] ||= 'float',
    :value => value,
    :tmax => 60,
    :dmax => 120
  }) if not DEBUG
end

# pxname,svname,qcur,qmax,scur,smax,slim,stot,bin,bout,dreq,dresp,ereq,econ,eresp,wretr,wredis,status,weight,act,bck,chkfail,chkdown,lastchg,downtime,qlimit,pid,iid,sid,throttle,lbtot,tracked,type,rate,rate_lim,rate_max,check_status,check_code,check_duration,hrsp_1xx,hrsp_2xx,hrsp_3xx,hrsp_4xx,hrsp_5xx,hrsp_other,hanafail,req_rate,req_rate_max,req_tot,cli_abrt,srv_abrt
class HAproxyStats
  attr_accessor :stats, :old_stats
  @@metrics = {
    :hrsp_2xx => {
      :name => '2xx Responses',
      :units => 'responses/sec'
    },
    :hrsp_3xx => {
      :name => '3xx Responses',
      :units => 'responses/sec'
    },
    :hrsp_4xx => {
      :name => '4xx Responses',
      :units => 'responses/sec'
    },
    :hrsp_5xx => {
      :name => '5xx Responses',
      :units => 'responses/sec'
    },
    :downtime => {
      :name => 'Time Down',
      :fixed => true,
      :type => 'uint32'
    },
    :smax => {
      :name => 'Max Sessions achieved',
      :fixed => true,
      :type => 'uint16'
    },
    :qcur => {
      :name => 'In Queue',
      :fixed => true,
      :type => 'uint16',
      :units => 'Connections'
    },
    :stot => {
      :name => 'Sessions',
      :units => 'sessions/sec'
    },
    :bout => {
      :name => 'Bytes Out',
      :units => 'bytes/sec'
    },
    :bin => {
      :name => 'Bytes In',
      :units => 'bytes/sec'
    },
    :eresp => {
      :name => 'Response Errors',
      :units => 'errors/sec'
    },
  }

  def initialize(params=Hash.new)
    params[:sock_path] ||= '/var/run/haproxy.sock'
    @params = params
    sock = UNIXSocket.new(params[:sock_path])
    sock.send "show stat\n", 0
    s_output = sock.read
    sock.close
    @stats = read_haproxy_csv(s_output)
    if File.exists?(TMP_FILE)
      old_mtime = File.stat(TMP_FILE).mtime
      @old_stats = read_haproxy_csv(File.read(TMP_FILE))
    end
    if old_mtime && @old_stats
      time_diff = Time.now - old_mtime
      dont_write=true if time_diff < 1
    end
    if not dont_write
      if @old_stats
        @@metrics.each do |col,args|
          time = args[:fixed].nil? ? time_diff : nil
          calc_diff(col, time).each do |server,value|
            puts [server.to_s.capitalize, args[:name], value, args[:units], args[:type]].compact.reject { |s| s.nil? }.join(' ') if DEBUG
            ganglia_send "#{server.to_s.capitalize} #{args[:name]}", value, args if value >= 0
          end
        end
      end
      open(TMP_FILE, 'wb') { |f| f << s_output }
    end
  end

  def read_haproxy_csv(s)
    options = {
      :headers => true,
      :skip_blanks => true,
    }
    csv = FasterCSV.new(s, options)
    csv.header_convert { |field| field.gsub(/#/, '').strip.downcase.to_sym if field } # needed for first line comment
    csv = csv.read.delete_if { |row| row[:pxname] != @params[:proxy_name] if @params[:proxy_name] }
    csv.by_col.delete nil
    return csv
  end

  def calc_diff(key, time_diff)
    new = @stats.values_at(:svname, key)
    old = @old_stats.values_at(:svname, key)
    d = Hash.new
    new.each_with_index do |a,index|
      if time_diff
        d[a[0].to_sym] = ((a[1].to_i - old[index][1].to_i) / time_diff * 100).round / 100.0
      else
        d[a[0].to_sym] = a[1].to_i
      end
    end if new.length == old.length
    return d
  end

end

options = Hash.new
options = {:proxy_name => '<name of proxy on HAproxy>'}
s = HAproxyStats.new(options)
#p s.headers
#p s.stats.values_at(:svname, :lastchg)
#p s.old_stats.values_at(:svname, :lastchg)
