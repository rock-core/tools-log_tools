require 'readline'
require 'test_helper'
require 'log_tools/cli/upgrade'
require 'tmpdir'
require 'erb'

module LogTools
    module CLI
        describe Upgrade do
            attr_reader :fixture_pkgconfig_dir, :fixture_dir
            before do
                @fixture_pkgconfig_dir = Pathname.new(Dir.mktmpdir)
                @fixture_dir = Pathname.new(__dir__) + "upgrade_fixtures"

                %w{orogen-project-test.pc test-typekit-gnulinux.pc}.each do |basename|
                    rendered = ERB.new((fixture_dir + (basename + ".erb")).read).
                        result(binding)
                    (fixture_pkgconfig_dir + basename).open('w') do |io|
                        io.write rendered
                    end
                end
                Pocolog.logger.level = Logger::WARN
                ENV['PKG_CONFIG_PATH'] = fixture_pkgconfig_dir.to_s
            end
            after do
                fixture_pkgconfig_dir.rmtree
            end

            describe 'process' do
                describe "when given the path to a directory" do
                    attr_reader :base_time
                    before do
                        @base_time = Time.at(10, 100)
                        create_logfile 'test.0.log' do
                            create_logfile_stream 'test'
                            write_logfile_sample base_time, base_time + 1, 1
                            write_logfile_sample base_time + 10, base_time + 2, 2
                        end
                        create_logfile 'test.1.log' do
                            create_logfile_stream 'other'
                            write_logfile_sample base_time + 100, base_time + 3, 3
                            write_logfile_sample base_time + 200, base_time + 4, 4
                        end
                    end

                    it "processes all the log files within the directory" do
                        flexmock(Pocolog::FileUpgrader).new_instances.
                            should_receive(:upgrade).
                            with(logfile_path('test.0.log'), logfile_path('upgraded/test.0.log'), Hash).
                            once.pass_thru
                        flexmock(Pocolog::FileUpgrader).new_instances.
                            should_receive(:upgrade).
                            with(logfile_path('test.1.log'), logfile_path('upgraded/test.1.log'), Hash).
                            once.pass_thru

                        Upgrade.start(['process', '--silent', logfiles_dir], debug: true)
                        assert logfile_pathname('upgraded/test.0.log').exist?
                        assert logfile_pathname('upgraded/test.1.log').exist?
                    end
                    it "uses its --output argument as the output directory" do
                        target_dir = File.join(logfiles_dir, "custom")
                        flexmock(Pocolog::FileUpgrader).new_instances.
                            should_receive(:upgrade).
                            with(logfile_path('test.0.log'), logfile_path('custom/test.0.log'), Hash).
                            once.pass_thru
                        flexmock(Pocolog::FileUpgrader).new_instances.
                            should_receive(:upgrade).
                            with(logfile_path('test.1.log'), logfile_path('custom/test.1.log'), Hash).
                            once.pass_thru

                        Upgrade.start(['process', '--silent', '--output', target_dir, logfiles_dir], debug: true)
                        assert logfile_pathname('custom/test.0.log').exist?
                        assert logfile_pathname('custom/test.1.log').exist?
                    end
                end
                describe "when given the path to a file" do
                    attr_reader :base_time
                    before do
                        @base_time = Time.at(10, 100)
                        create_logfile 'test.0.log' do
                            create_logfile_stream 'test'
                            write_logfile_sample base_time, base_time + 1, 1
                            write_logfile_sample base_time + 10, base_time + 2, 2
                        end
                        create_logfile 'test.1.log' do
                            create_logfile_stream 'other'
                            write_logfile_sample base_time + 100, base_time + 3, 3
                            write_logfile_sample base_time + 200, base_time + 4, 4
                        end
                    end

                    it "processes the given logfile" do
                        Upgrade.start(['process', '--silent', logfile_path('test.0.log')], debug: true)
                        flexmock(Pocolog::FileUpgrader).new_instances.
                            should_receive(:upgrade).
                            with(logfile_path('test.0.log'), logfile_path('upgraded/test.0.log'), Hash).
                            once.pass_thru

                        assert logfile_pathname('upgraded/test.0.log').exist?
                    end
                    it "uses its --output argument as the output directory" do
                        target_file = File.join(logfiles_dir, "custom", 'custom.0.log')
                        Upgrade.start(['process', '--silent', '--output', target_file, logfile_path('test.0.log')], debug: true)
                        flexmock(Pocolog::FileUpgrader).new_instances.
                            should_receive(:upgrade).
                            with(logfile_path('test.0.log'), target_file, Hash).
                            once.pass_thru

                        assert logfile_pathname('custom/custom.0.log').exist?
                    end
                end

                describe "handling of conversions" do
                    attr_reader :base_time, :test_t
                    before do
                        @base_time = Time.at(10, 100)
                        @test_t = Typelib::Registry.new.create_numeric '/test_t', 4, :sint
                        create_logfile 'test.0.log' do
                            create_logfile_stream 'test', type: test_t
                            write_logfile_sample base_time, base_time + 1, 1
                            write_logfile_sample base_time + 10, base_time + 2, 2
                        end
                    end
                    it "uses the local orogen type as a target type" do
                        Upgrade.start(['process', '--silent', logfile_path('test.0.log')], debug: true)
                        stream = open_logfile_stream logfile_path('upgraded/test.0.log'), 'test'
                        reg = Typelib::Registry.from_xml((fixture_dir + "test.tlb").read)
                        assert reg.get('/test_t'), stream.type
                    end
                    it "uses the same type if the local installation does not have the expected type" do
                        ENV.delete('PKG_CONFIG_PATH')
                        Upgrade.start(['process', '--silent', logfile_path('test.0.log')], debug: true)
                        stream = open_logfile_stream logfile_path('upgraded/test.0.log'), 'test'
                        assert test_t, stream.type
                    end
                    it "loads the converters present in the --converters path and applies them" do
                        out, _err = capture_io do
                            Upgrade.start(['process', '--converters', fixture_dir, logfile_path('test.0.log')], debug: true)
                        end
                        assert_match /loaded 1 converters from #{fixture_dir}/, out
                        stream = open_logfile_stream logfile_path('upgraded/test.0.log'), 'test'
                        expected = [
                            [base_time, base_time + 1, 2],
                            [base_time + 10, base_time + 2, 4]]
                        assert_equal expected, stream.samples.to_a
                    end
                end
                it "deletes the last upgraded file if the upgrade process raises" do
                    create_logfile 'test.0.log' do
                        create_logfile_stream 'test'
                    end
                    create_logfile 'test.1.log' do
                        create_logfile_stream 'other'
                    end
                    flexmock(Pocolog::FileUpgrader).new_instances.
                        should_receive(:upgrade).
                        with(logfile_path('test.0.log'), String, Hash).
                        once.pass_thru

                    error_m = Class.new(Exception)
                    flexmock(Pocolog::FileUpgrader).new_instances.
                        should_receive(:upgrade).
                        with(logfile_path('test.1.log'), String, Hash).
                        once.and_raise(error_m)
                    assert_raises(error_m) do
                        Upgrade.start(['process', '--silent', logfiles_dir], debug: true)
                    end
                    
                    assert logfile_pathname('upgraded/test.0.log').exist?
                    refute logfile_pathname('upgraded/test.1.log').exist?
                end

                it "skips existing files if --skip-existing is given" do
                    create_logfile 'test.0.log' do
                        create_logfile_stream 'test'
                    end
                    FileUtils.mkdir_p(logfile_path('upgraded'))
                    FileUtils.touch logfile_path('upgraded/test.0.log')
                    out, err = capture_io do
                        Upgrade.start(['process', '--skip-existing', logfiles_dir], debug: true)
                    end
                    assert_match /skipping #{logfile_path('test.0.log')}: #{logfile_path('upgraded/test.0.log')} already exists/, out 
                    assert File.read(logfile_path('upgraded/test.0.log')).empty?
                end

                it "overrides existing files by default" do
                    create_logfile 'test.0.log' do
                        create_logfile_stream 'test'
                    end
                    FileUtils.mkdir_p(logfile_path('upgraded'))
                    FileUtils.touch logfile_path('upgraded/test.0.log')
                    Upgrade.start(['process', '--silent', '--skip-existing=f', logfiles_dir], debug: true)
                    open_logfile 'upgraded/test.0.log'
                end

                it "reports its progress" do
                    base_time = Time.now
                    # This is not a test per se. It is there only to exercise
                    # that part of the code, making sure that it won't break
                    create_logfile 'test.0.log' do
                        create_logfile_stream 'test'
                        write_logfile_sample base_time, base_time + 1, 1
                        write_logfile_sample base_time + 10, base_time + 2, 2
                    end
                    create_logfile 'test.1.log' do
                        create_logfile_stream 'other'
                        write_logfile_sample base_time + 100, base_time + 3, 3
                        write_logfile_sample base_time + 200, base_time + 4, 4
                    end

                    capture_io do
                        Upgrade.start(['process', logfiles_dir], debug: true)
                    end
                end
            end

            describe 'create-converter' do
                attr_reader :base_time, :test_t
                before do
                    @base_time = Time.new(1970, 10, 1, 5)
                    @test_t = Typelib::Registry.new.create_numeric '/test_t', 4, :sint
                    FileUtils.mkdir_p(logfile_path('converters'))
                end

                describe "nominal operations" do
                    attr_reader :test_t
                    before do
                        create_logfile 'test.0.log' do
                            create_logfile_stream 'test', type: test_t
                            write_logfile_sample base_time, base_time, 10
                        end
                    end

                    it "creates all that is necessary for the converter registry to load" do
                        Upgrade.start(['create-converter', '--silent', logfile_path('converters'), logfile_path('test.0.log'), '/test_t'], debug: true)
                        registry = Pocolog::Upgrade::ConverterRegistry.new
                        converters = Pocolog::Upgrade::DSL.load_dir(logfile_path('converters'), registry)
                        assert_equal 1, converters.size
                        assert_equal test_t, converters[0].from_type
                        reg = Typelib::Registry.from_xml((fixture_dir + "test.tlb").read)
                        assert_equal reg.get('/test_t'), converters[0].to_type
                    end

                    it "uses the day after the latest sample in the logfile as reference time by default" do
                        ref = Time.new(1970, 10, 2)
                        Upgrade.start(['create-converter', '--silent', logfile_path('converters'), logfile_path('test.0.log'), '/test_t'], debug: true)
                        registry = Pocolog::Upgrade::ConverterRegistry.new
                        converters = Pocolog::Upgrade::DSL.load_dir(logfile_path('converters'), registry)
                        assert_equal ref, converters[0].time_to
                    end

                    it "overrides the reference time by the date given to --date" do
                        ref = Time.new(1970, 10, 5)
                        Upgrade.start(['create-converter', '--silent', logfile_path('converters'), logfile_path('test.0.log'), "--date", ref.to_s, '/test_t'], debug: true)
                        registry = Pocolog::Upgrade::ConverterRegistry.new
                        converters = Pocolog::Upgrade::DSL.load_dir(logfile_path('converters'), registry)
                        assert_equal ref, converters[0].time_to
                    end
                    it "informs the user of what extra steps need to be done" do
                        out, _err = capture_io do
                            Upgrade.start(['create-converter', logfile_path('converters'), logfile_path('test.0.log'), '/test_t'], debug: true)
                        end
                        assert_match /You must edit (.*) and perform the actual conversion/, out
                        /You must edit (.*) and perform the actual conversion/ =~ out
                        assert File.file?($1)
                    end
                end

                describe "failure situations" do
                    attr_reader :test_t
                    it "fails if the file has only empty streams and --time was not given" do
                        create_logfile 'test.0.log' do
                            create_logfile_stream 'test', type: test_t
                        end
                        error = assert_raises(ArgumentError) do
                            Upgrade.start(['create-converter', logfile_path('converters'), logfile_path('test.0.log'), '/test_t'], debug: true)
                        end
                        assert_match /--date/, error.message
                    end
                    it "uses the time given as --date if the file has no samples" do
                        create_logfile 'test.0.log' do
                            create_logfile_stream 'test', type: test_t
                        end
                        ref = Time.new(1980, 9, 30)
                        Upgrade.start(
                            ['create-converter', '--silent', logfile_path('converters'),
                             logfile_path('test.0.log'), '/test_t',
                             '--date', ref.to_s], debug: true)
                        registry = Pocolog::Upgrade::ConverterRegistry.new
                        converters = Pocolog::Upgrade::DSL.load_dir(logfile_path('converters'), registry)
                        assert_equal ref, converters.first.time_to
                    end
                    it "fails if the requested type name is not present in the log file" do
                        create_logfile 'test.0.log' do
                            create_logfile_stream 'test', type: test_t
                            write_logfile_sample Time.now, Time.now, 10
                        end
                        error = assert_raises(ArgumentError) do
                            Upgrade.start(['create-converter', logfile_path('converters'), logfile_path('test.0.log'), '/does_not_exist'], debug: true)
                        end
                        assert_match /#{logfile_path('test.0.log')} does not contain a definition for \/does_not_exist/, error.message
                    end
                end
            end
        end
    end
end

