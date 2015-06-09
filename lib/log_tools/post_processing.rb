require 'pocolog'

module LogTools
    # Main class to build post-processing pipelines for log datasets
    class PostProcessing
        # A region in a log stream
        class Region
            # The start sample of the region
            #
            # @return [Integer]
            attr_reader :start_time
            # The end sample of the region
            #
            # @return [Integer]
            attr_reader :end_time

            def initialize(s, e)
                @start_time = s
                @end_time   = e
            end

            def ==(other)
                other.kind_of?(Region) &&
                    other.start_time == start_time &&
                    other.end_time == end_time
            end
        end

        # Objects that define the parts of the dataset that should be processed
        attr_reader :region_matchers

        def initialize
            @region_matchers = Array.new
        end

        # Opens the log files that are included by the configured matchers
        #
        # @param [String] dir the dataset's directory
        # @return [{Pocolog::Logfiles=>[Matcher]}] the set of opened logfiles
        #   along with the set of matchers that should be used to further filter
        #   the logfile's streams
        def open_logfiles(paths, matchers = region_matchers)
            logfiles = Hash.new
            paths.each do |path|
                basename = File.basename(path)
                if related_matchers = perform_simple_match(!@exclude_all, matchers, "logfile", basename)
                    logfiles[Pocolog::Logfiles.open(path)] = related_matchers
                end
            end
            logfiles
        end

        # Gets the set of streams that should be post-processed
        #
        # @param [{Pocolog::Logfiles=>[Matcher]}] the set of logfiles
        #   along with the set of matchers that should be used to filter this
        #   logfile's streams. This is the same format returned by
        #   {open_logfiles}
        # @return [{Pocolog::DataStream=>[Matcher]}] the set of streams along
        #   with the set of matchers that should be used to further filter them.
        def find_all_included_streams(logfiles)
            streams = Hash.new
            logfiles.each do |file, matchers|
                file.streams.map do |s|
                    if related_matchers = perform_simple_match(!@exclude_all, matchers, "stream", s)
                        streams[s] = related_matchers
                    end
                end
            end
            streams
        end

        # Ensures that an array of Region objects is sorted and non-overlapping
        #
        # @param [Array<Region>] non-empty array of Region
        # @return [Array<Region>]
        def normalize_regions(regions)
            regions = regions.sort_by { |r| r.start_time }
            filtered_regions = Array.new
            last_region = regions.shift
            regions.each do |r|
                if r.start_time < last_region.end_time
                    last_region.end_time = [last_region.end_time, r.end_time].max
                else
                    filtered_regions << last_region
                    last_region = r
                end
            end
            if last_region
                filtered_regions << last_region
            end
            filtered_regions
        end

        # Given a set of streams and annotations, outputs a per-stream set of
        # regions that have to be postprocessed
        #
        # The regions are sorted by time, and are guaranteed to not overlap
        #
        # @param [{Pocolog::DataStream=>[Matcher]}] streams the set of streams
        #   along with the set of matchers that should be used to determine the
        #   regions. The method performs an union of the returned regions. This
        #   is the same format as the value returned by
        #   {find_all_included_streams}
        # @param [Array<Orocos::Log::Annotation>] array of annotations sorted in
        #   time
        # @return [{Pocolog::DataStream=>[Region]}] a per-stream list of regions
        #   that are sorted in time, and non-overlapping
        def find_all_matching_regions(streams, annotations)
            regions_by_stream = Hash.new
            streams.each do |s, matchers|
                if s.empty?
                    regions_by_stream[s] = []
                    next
                end

                initial_region = if @exclude_all then []
                                 else [Region.new(*s.time_interval)]
                                 end

                raw_regions = matchers.inject(initial_region) do |whole_region, (inclusive, matcher)|
                    r = matcher.matching_regions(s, annotations)
                    if inclusive
                        normalize_regions(whole_region + r)
                    else
                        substract_regions(whole_region, normalize_regions(r))
                    end
                end
                regions_by_stream[s] = raw_regions
            end
            regions_by_stream
        end

        # Gets all annotations stored in the provided streams
        def gather_annotations(streams)
            raw_annotations = streams.keys.inject(Array.new) do |a, s|
                if s.type.name == "/logger/Annotations"
                    a.concat(s.samples.enum_for(:raw_each).to_a)
                end
                a
            end
            raw_annotations.map(&:last).sort_by { |s| s.raw_time.microseconds }
        end

        # Substracts a set of regions from another set
        #
        # @param [Array<Region>] regions a sorted, non-overlapping list of regions
        # @param [Array<Region>] removed_regions a sorted, non-overlapping list of regions
        # @return [Array<Region>] the set of regions that contain all intervals
        #   in regions with the intervals in removed_regions removed
        def substract_regions(regions, removed_regions)
            regions = regions.dup
            removed_regions = removed_regions.dup

            result = Array.new
            current = regions.shift
            while current && !removed_regions.empty?
                current = current.dup
                current_removal = removed_regions.first
                while current_removal && (current_removal.end_time <= current.start_time)
                    current_removal = removed_regions.shift
                end
                if !current_removal
                    break
                elsif current.end_time <= current_removal.start_time
                    result << current
                    current = regions.shift
                    next
                end

                if current.start_time < current_removal.start_time
                    result << Region.new(current.start_time, current_removal.start_time)
                end

                if current.end_time > current_removal.end_time
                    current = Region.new(current_removal.end_time, current.end_time)
                else
                    current = regions.shift
                end
            end
            result + [current].compact + regions
        end

        def find_all_logfiles_in_dir(dir)
            Dir.enum_for(:glob, File.join(dir, '*.log')).
                find_all { |file| file =~ /\.\d+\.log$/ }
        end

        def show_matcher(inclusive, m, indent)
            flag = if inclusive then '+'
                   else '-'
                   end
            puts "  (#{flag}) #{m}"
        end

        def show(dir)
            files = find_all_logfiles_in_dir(dir)
            logfiles = open_logfiles(files)
            streams  = find_all_included_streams(logfiles)
            annotations = gather_annotations(streams)
            regions_by_stream = find_all_matching_regions(streams, annotations)

            puts "Available logfiles:"
            files.sort.each do |f|
                puts "  #{f}"
            end
            puts "Matchers:"
            region_matchers.each do |inclusive, m|
                show_matcher(inclusive, m, "  ")
            end
            puts "Matched logfiles:"
            logfiles.each do |file, matchers|
                puts "  #{file.io.first.path}, by"
                matchers.each do |inclusive, m|
                    show_matcher(inclusive, m, "    ")
                end
            end
            puts "Matched streams:"
            streams.each do |stream, matchers|
                puts "  #{stream.name}, by"
                matchers.each do |inclusive, m|
                    show_matcher(inclusive, m, "    ")
                end
            end
            puts "Processed Regions"
            regions_by_stream.each do |stream, regions|
                puts "  #{stream.name}: #{regions.map { |r| "[#{r.start_time}:#{r.end_time}]" }.join(" ")}"
            end
        end

        def run(dir, target_dir)
            files = Dir.enum_for(:glob, File.join(dir, '*.*.log')).to_a
            logfiles = open_logfiles(files)
            streams  = find_all_included_streams(logfiles)
            annotations = gather_annotations(streams)
            regions_by_stream = find_all_matching_regions(streams, annotations)

            data_buffer = String.new

            target_logfiles = Hash.new
            regions_by_stream.each do |stream, regions|
                logfile_path = stream.logfile.io.path
                logfile_basename = File.basename(logfile_path).gsub(/\.\d+\.log$/, '')
                logfile = target_logfiles[logfile_basename]
                if !logfile
                    target_path = File.join(target_dir, logfile_basename)
                    target_logfiles[logfile_basename] = Pocolog::Logfiles.
                        create(target_path)
                end

                target_stream = logfile.create_stream(stream.name, stream.type, stream.metadata)
                regions.each do |r|
                    header = stream.seek(r.start_time)
                    while header && header.lg < r.end_time
                        logfile.data(header, data_buffer)
                        target_stream.write_raw(header.rt, header.lg, data_buffer)
                        header = stream.advance
                    end
                end
            end
        end

        def perform_simple_match(initial_value, matchers, type, object, *args)
            related_matchers = Array.new
            does_match = matchers.inject(initial_value) do |v, (inclusion_matcher, matcher)|
                if !matcher.send("filters_#{type}s?")
                    related_matchers << [inclusion_matcher, matcher]
                    next(v || inclusion_matcher)
                end

                result = matcher.send("matches_#{type}?", object, *args)
                if result.nil?
                    related_matchers << [inclusion_matcher, matcher]
                    v || inclusion_matcher
                elsif result
                    related_matchers << [inclusion_matcher, matcher]
                    inclusion_matcher
                else v
                end
            end
            if does_match
                related_matchers
            end
        end

        class Matcher
            # Tests if this matcher acts on the log files (i.e. if
            # {matches_logfile?} does something). If false, matches_logfile?
            # will not be called and all included streams will be passed to
            # {matches_stream?}
            def filters_logfiles?; false end

            # Tests if this matcher acts on the streams (i.e. if
            # {matches_streams?} does something). If false, matches_streams?
            # will not be called and all included streams will be passed to
            # {matching_regions}
            def filters_streams?; false end

            # Tests if this matcher object requires to include or exclude a
            # logfile
            #
            # @param [String] path the logfile's basename
            # @return [Boolean] whether the log file is matched by this object
            #   or not
            def matches_logfile?(path); end

            # Tests if this matcher object requires to include or exclude a
            # stream
            #
            # If {filters_logfiles?} returns true, this method will be called
            # only for streams for which {matches_logfile?} returned true.
            #
            # @param [Pocolog::DataStream] stream the stream object
            # @return [Boolean] whether the stream is matched by this object
            #   or not
            def matches_stream?(stream); end

            # Returns which parts of a stream should be processed
            #
            # If either {filters_logfiles?} or {filters_streams?} return true,
            # this method will be called only for streams for which
            # the corresponding matching methods returned true.
            #
            # @param [Pocolog::DataStream] stream the stream object
            # @param [Array<Types::Logger::Annotations>] annotations the annotations
            #   known to this dataset that apply to this stream
            # @return [Array<Region>]
            def matching_regions(stream, annotations); [Region.new(*stream.time_interval)] end
        end

        def include_all
            region_matchers.clear
            @exclude_all = false
        end

        def exclude_all
            region_matchers.clear
            @exclude_all = true
        end

        # Includes regions of the log file for post-processing
        #
        # By default, all the data is included
        #
        # Inclusions and exclusions are processed in declaration order. This
        # means that e.g. calling {include_logfile} and then {exclude_logstream}
        # will exclude streams from this logfile. The other way around, the log
        # stream exclusion would have no effect on the logfile inclusion (i.e.
        # the log file would be completely included)
        #
        # @return [LogStreamMatcher]
        #
        # @example match a log file
        #   processor.include_regions_matching.
        #       logfile(/camera/)
        #
        # @example match all Time streams
        #   processor.include_regions_matching.
        #       stream_type("/base/Time")
        #
        def include(matcher = LogStreamMatcher.new)
            region_matchers << [true, matcher]
            matcher
        end

        # Excludes regions of the log file for post-processing
        #
        # See {include} for more information about inclusions and exclusions
        def exclude(matcher = LogStreamMatcher.new)
            region_matchers << [false, matcher]
            matcher
        end

        class AnnotationMatcher
            FIELDS = [:key, :value, :stream_name]

            def initialize(match)
                if match.respond_to?(:to_str)
                    match = Hash[key: match, value: match, stream_name: match]
                end
                @match = match
            end

            def match(stream, ann)
                @match.all? do |k, v|
                    v === ann.get(k)
                end
            end

            def to_s
                "annotation(#{@match.map { |k, v| "#{k}: #{v}" }.join(", ")})"
            end
        end

        class LogStreamMatcher < Matcher
            attr_reader :log_file_matcher
            attr_reader :stream_name_matcher
            attr_reader :stream_type_matcher
            attr_reader :annotation_ranges

            def initialize
                @annotation_ranges = Array.new
            end

            def stream_name(matcher)
                @stream_name_matcher = matcher
                self
            end

            def stream_type(matcher)
                @stream_type_matcher = matcher
                self
            end

            def logfile(matcher)
                @log_file_matcher = matcher
                self
            end

            def annotated_region(ann_start, ann_end)
                if !ann_start.respond_to?(:match)
                    ann_start = AnnotationMatcher.new(ann_start)
                end
                if !ann_end.respond_to?(:match)
                    ann_end = AnnotationMatcher.new(ann_end)
                end
                annotation_ranges << [ann_start, ann_end]
                self
            end

            def to_s
                result = Array.new
                if filters_logfiles?
                    result << "logfile(#{log_file_matcher})"
                end
                if stream_name_matcher
                    result << "stream_name(#{stream_name_matcher})"
                end
                if stream_type_matcher
                    result << "stream_type(#{stream_type_matcher})"
                end
                annotation_ranges.each do |s, e|
                    result << "annotation_ranges(#{s}, #{e})"
                end
                result.join(".")
            end

            def filters_logfiles?
                !!log_file_matcher
            end

            def matches_logfile?(path)
                if log_file_matcher === path
                    if filters_streams?
                        nil
                    else true
                    end
                else false
                end
            end

            def filters_streams?
                !!(stream_name_matcher || stream_type_matcher)
            end

            def matches_stream?(stream)
                if stream_name_matcher && !(stream_name_matcher === stream.name)
                    false
                elsif stream_type_matcher && !(stream_type_matcher === stream.type.name)
                    false
                elsif stream_name_matcher || stream_type_matcher
                    true
                else nil
                end
            end

            def matching_regions(stream, annotations)
                if annotation_ranges.empty?
                    return super
                end

                regions = Array.new

                region_start, current_ann_start, current_ann_end = nil
                annotations.each do |ann|
                    if region_start && current_ann_end.match(stream, ann)
                        regions << Region.new(region_start, ann.time)
                        region_start = nil
                    end

                    annotation_ranges.each do |ann_start, ann_end|
                        next if !ann_start.match(stream, ann)

                        if region_start
                            ann_value = ann.value.split("\n").join("\\n")
                            if ann_value.length > 10
                                ann_value = ann_value[0, 10] + "..."
                            end
                            ann_to_s = "annotation(#{ann.time}, key:#{ann.key}, stream:#{ann.stream_name}, value:#{ann_value})"
                            LogTools.warn "found #{ann_to_s} within an already opened region matched by #{current_ann_start}:#{current_ann_end}, dropping the current region"
                        end
                        region_start = ann.time
                        current_ann_start = ann_start
                        current_ann_end   = ann_end
                    end
                end
                regions
            end
        end

    end
end

