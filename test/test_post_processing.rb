require 'log_tools/test'

describe LogTools::PostProcessing do
    attr_reader :processor, :file_paths
    before do
        @processor = LogTools::PostProcessing.new
        @file_paths = Array.new
    end

    def mock_logfile(path, should_open)
        file_paths << path
        if should_open
            mock = flexmock("mocked logfile at #{path}")
            flexmock(Pocolog::Logfiles).should_receive(:open).with(path).and_return(mock)
            streams = Array.new
            mock.should_receive(:streams).and_return { streams }
            mock.should_receive(:each_stream).and_return { streams }
            mock
        else
            flexmock(Pocolog::Logfiles).should_receive(:open).with(path).never
        end
    end

    def mock_stream(logfile, stream_name, stream_type)
        stream = flexmock("mocked stream #{stream_name}:#{stream_type}", name: stream_name, type: flexmock(name: stream_type))
        logfile.streams << stream
        stream
    end

    describe "logfile filtering" do
        it "opens log files that are explicitely included" do
            logfile_mock = mock_logfile 'test.0.log', true
            mock_logfile 'other', true
            processor.exclude_all
            matcher = processor.include.logfile(/test/)
            assert_equal Hash[logfile_mock => [[true, matcher]]], processor.open_logfiles(file_paths)
        end

        it "opens all log files by default" do
            logfile_mock = mock_logfile 'test.0.log', true
            assert_equal Hash[logfile_mock => []], processor.open_logfiles(file_paths)
        end

        it "opens the log files for inclusion filters that match more than just the logfile" do
            logfile_mock = mock_logfile 'test.0.log', true
            processor.exclude_all
            matcher = processor.include.
                stream_type("/base/Time")
            assert_equal Hash[logfile_mock => [[true, matcher]]],
                processor.open_logfiles(file_paths)
        end

        it "does leave log files open for exclusion filters that match more than just the logfile" do
            logfile_mock = mock_logfile 'test.0.log', true
            processor.exclude_all
            matcher1 = processor.include.logfile(/test/)
            matcher2 = processor.exclude.logfile(/test/).
                stream_type("/base/Time")
            assert_equal Hash[logfile_mock => [[true, matcher1], [false, matcher2]]],
                processor.open_logfiles(file_paths)
        end

        it "does leave log files open for exclusion filters that do not match the logfile" do
            logfile_mock = mock_logfile 'test.0.log', true
            processor.exclude_all
            matcher1 = processor.include.logfile(/test/)
            processor.exclude.logfile(/bla/)
            assert_equal Hash[logfile_mock => [[true, matcher1]]],
                processor.open_logfiles(file_paths)
        end

        it "does leave log files open for exclusion filters that do not match the logfile path at all" do
            logfile_mock = mock_logfile 'test.0.log', true
            processor.exclude_all
            matcher1 = processor.include.logfile(/test/)
            matcher2 = processor.exclude.stream_name(/stream/)
            assert_equal Hash[logfile_mock => [[true, matcher1], [false, matcher2]]],
                processor.open_logfiles(file_paths)
        end

        it "does not force the opening of the log files for exclusion filters that match more than just the logfile" do
            mock_logfile 'test.0.log', false
            processor.exclude_all
            processor.exclude.logfile(/test/).
                stream_type("/base/Time")
            assert_equal Hash[], processor.open_logfiles(file_paths)
        end

        it "does not open log files that are explicitely excluded" do
            mock_logfile 'test.0.log', false
            processor.exclude.logfile(/test/)
            assert_equal Hash[], processor.open_logfiles(file_paths)
        end

        it "does not open log files whose inclusion has been overriden" do
            mock_logfile 'test.0.log', false
            processor.include.logfile(/test/)
            processor.exclude.logfile(/test/)
            assert_equal Hash[], processor.open_logfiles(file_paths)
        end
    end

    describe "stream filtering" do
        describe "inclusion" do
            attr_reader :stream_mock, :logfiles, :matcher
            before do
                logfile_mock = mock_logfile 'test.0.log', true
                @stream_mock  = mock_stream logfile_mock, "stream", "/base/Time"
                mock_stream logfile_mock, "other", "/double"
                processor.exclude_all
                @matcher = processor.include
                @logfiles = Hash[logfile_mock => [[true, matcher]]]
            end 
            it "includes only the streams matched by name" do
                matcher.stream_name(/stream/)
                assert_equal Hash[stream_mock => [[true, matcher]]],
                    processor.find_all_included_streams(logfiles)
            end

            it "includes only the streams matched by type" do
                matcher.stream_type("/base/Time")
                assert_equal Hash[stream_mock => [[true, matcher]]],
                    processor.find_all_included_streams(logfiles)
            end

            it "includes only the streams that match both name and type" do
                matcher.stream_name("other").stream_type("/base/Time")
                assert_equal Hash[],
                    processor.find_all_included_streams(logfiles)
            end
        end
    end

    describe "#substract_regions" do
        def region(min, max)
            LogTools::PostProcessing::Region.new(min, max)
        end
        it "leaves non-intersecting regions alone" do
            assert_equal [region(0, 1), region(1, 1.5)],
                processor.substract_regions([region(0, 1), region(1, 1.5)], [region(2, 3)])
            assert_equal [region(0, 1), region(1, 1.5)],
                processor.substract_regions([region(0, 1), region(1, 1.5)], [region(-2, -1)])
        end

        it "leaves intervals that share the same start/end point alone" do
            assert_equal [region(0, 1), region(2, 3)],
                processor.substract_regions([region(0, 1), region(2, 3)], [region(1, 2)])
            assert_equal [region(0, 1), region(2, 3)],
                processor.substract_regions([region(0, 1), region(2, 3)], [region(-1, 0)])
            assert_equal [region(0, 1), region(2, 3)],
                processor.substract_regions([region(0, 1), region(2, 3)], [region(3, 2)])
        end

        it "removes intervals if the removal share the same start point tham the removed" do
            assert_equal [], processor.substract_regions([region(0, 1)], [region(0, 2)])
        end
        it "removes exact intervals" do
            assert_equal [],
                processor.substract_regions([region(0, 3)], [region(0, 3)])
        end
        it "removes holes in intervals" do
            assert_equal [region(0, 1), region(2, 3)],
                processor.substract_regions([region(0, 3)], [region(1, 2)])
        end
        it "removes regions spanning multiple intervals" do
            assert_equal [region(0, 1), region(5, 6)],
                processor.substract_regions(
                    [region(0, 1.5), region(2, 3), region(3.5, 6)],
                    [region(1, 5)])
        end
        it "removes beginning of intervals" do
            assert_equal [region(0, 1)],
                processor.substract_regions([region(0, 1.5)], [region(1, 5)])
        end
        it "removes end of intervals" do
            assert_equal [region(2, 3)],
                processor.substract_regions([region(2, 4)], [region(3, 4)])
        end
    end

    describe "#normalize_regions" do
        it "does not touch an empty array" do
            assert_equal [], processor.normalize_regions([])
        end
    end
end

