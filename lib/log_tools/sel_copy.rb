#!/usr/bin/env ruby

require 'pocolog'

# Copies all log samples lying insight a log interval of the reference stream to the new log file
#
# @param [String] reference_stream_name the name of the reference stream
# @param [String] folder the path to the folder containing all log files
# @param [String] new_file_name path of the new log file 
# @param [Array] black_list list of stream names which shall be ignored
def selective_copy(reference_stream_name,folder,new_file_name,black_list = Array.new)
    folder = File.expand_path(folder)
    all_files = Dir.enum_for(:glob, File.join(folder, '*.*.log'))

    intervals = Array.new
    streams = Array.new
    logfiles = all_files.map do |file|
        file = Pocolog::Logfiles.new(File.open(file))
        file.streams.each do |stream|
            next if black_list.include?(stream.name)
            intervals << stream.time_interval if stream.name == reference_stream_name
            streams << stream
        end
        file
    end
    intervals = compact_intevals(intervals)

    #copy all time intervals matching the reference_stream
    output = Pocolog::Logfiles.new(Typelib::Registry.new)
    output.new_file(new_file_name)
    new_streams = Hash.new
    intervals.each do |interval|
        puts "interval: #{interval.first} / #{interval.last}"
        streams.each do |stream|
            if stream.samples?(interval.first,interval.last)
                puts "  #{stream.name} copy samples" 
                new_streams[stream.name] ||= output.stream(stream.name,stream.type,true)
                stream.copy_to(interval.first,interval.last,new_streams[stream.name])
            end
        end
    end
    output.close
end

# Sorts the given intervals and joins overlapping ones to get a more compact 
# representation 
# @param [Array<Array<Time,Time>>] intervals time intervals
# @return [Array<Array<Time,Time>>] sorted and joined intervals 
def compact_intevals(intervals)
    #sort time intervals 
    intervals = intervals.sort do |x,y|
                    x.first <=> y.first
                end

    #remove overlapping parts 
    intervals.each_with_index do |interval,index|
        next unless interval
        (index+1).upto(intervals.size-1) do |i|
            if intervals[i].first < interval.last
                interval[1] = intervals[i].last
                intervals[i] = nil
            else
                break
            end
        end
    end
    intervals.delete_if do |interval| 
        interval == nil
    end
    intervals
end

if ARGV.size < 3 
    puts "Wrong number of arguments"
    puts "Copies all log samples lying insight a log interval of the reference stream to the new log file."
    puts ""
    puts "call_seq: sel_copy reference_stream folder new.log"
else
    selective_copy ARGV[0],ARGV[1],ARGV[2],ARGV[3..-1]
end
