require 'thor'
require 'log_tools'
require 'pastel'
require 'orogen'
require 'pocolog/file_upgrader'
require 'pocolog/cli/tty_reporter'
require 'pocolog/upgrade/dsl'

module LogTools
    module CLI
        class Upgrade < Thor
            default_command 'process'

            desc 'process PATH', 'upgrade a log file that uses older types to use the newer types'
            option :output, alias: 'o', desc: 'either the output file if PATH is a file or the output directory if PATH is a directory, defaults to resp. PATH.upgraded and PATH/upgraded'
            option :skip_existing, desc: 'skip existing upgraded files',
                type: :boolean, default: false
            option :skip_failures, desc: 'skip streams that cannot be upgraded',
                type: :boolean, default: false
            option :converters, desc: 'apply the converters stored in this path',
                type: :string
            option :silent, desc: 'remove all output',
                type: :boolean, default: false
            def process(path)
                path = Pathname.new(path)
                if path.directory?
                    output_dir =
                        if options[:output]
                            Pathname.new(options[:output])
                        else path + "upgraded"
                        end

                    all_paths = Pathname.glob(path + "*.?.log").map do |file|
                        if file.file?
                            [file, output_dir + file.basename]
                        end
                    end
                else
                    output_file =
                        if options[:output]
                            Pathname.new(options[:output])
                        else path.dirname + "upgraded" + path.basename
                        end
                    all_paths = [[path, output_file]]
                end

                pastel = Pastel.new

                loader = OroGen::Loaders::PkgConfig.new('gnulinux')
                type_mapper = lambda do |t|
                    begin
                        target_typekit = loader.typekit_for(t.name, false)
                        target_typekit.resolve_type(t.name)
                    rescue OroGen::NotTypekitType
                        t
                    end
                end
                upgrader = Pocolog::FileUpgrader.new(type_mapper)
                if options[:converters]
                    converters = Pocolog::Upgrade::DSL.load_dir(options[:converters], upgrader.converter_registry)
                    if !options[:silent]
                        puts "loaded #{converters.size} converters from #{options[:converters]}"
                    end
                end
                all_paths.each do |in_path, out_path|
                    if out_path.exist?
                        if options[:skip_existing]
                            puts "skipping #{in_path}: #{out_path} already exists"
                            next
                        else
                            out_path.unlink
                        end
                    end

                    if !options[:silent]
                        puts
                        puts pastel.bold("processing logfile #{in_path}")
                    end
                    reporter =
                        if options[:silent]
                            Pocolog::CLI::NullReporter.new
                        else
                            Pocolog::CLI::TTYReporter.new("|:bar| :current_byte/:total_byte :eta (:byte_rate/s)", total: in_path.stat.size)
                        end

                    begin
                        out_path.dirname.mkpath
                        upgrader.upgrade(in_path.to_s, out_path.to_s,
                                         reporter: reporter, skip_failures: options[:skip_failures])
                    rescue Interrupt
                        reporter.warn "Interrupted, deleted #{out_path}"
                        raise
                    rescue Exception
                        reporter.error "failed to upgrade #{in_path}, deleted #{out_path}"
                        raise
                    ensure
                        reporter.finish
                    end
                end
            end

            desc 'create-converter PATH LOGFILE SOURCE_TYPE [TARGET_TYPE]', 'create a new converter for a type present in a logfile and save it in PATH'
            option :date, desc: 'the date until which the converter should apply'
            option :silent, desc: 'do not display progress output',
                type: :boolean, default: false
            def create_converter(output_path, log_file_path, source_type_name, target_type_name = source_type_name)
                output_path   = Pathname.new(output_path)
                log_file_path = Pathname.new(log_file_path)

                in_logfile = Pocolog::Logfiles.open(log_file_path)
                source_type = nil
                in_logfile.streams.each do |s|
                    type = s.type
                    if !source_type && type.registry.include?(source_type_name)
                        source_type = type.registry.get(source_type_name)
                        break
                    end
                end
                if !source_type
                    raise ArgumentError, "#{log_file_path} does not contain a definition for #{source_type_name}"
                end

                loader  = OroGen::Loaders::PkgConfig.new('gnulinux')
                typekit = loader.typekit_for(target_type_name, false)
                target_type = typekit.resolve_type(target_type_name)

                if options[:date]
                    reference_time = Date.parse(options[:date])
                else
                    reference_time = in_logfile.streams.map { |s| s.time_interval[1] }.compact.max
                    if !reference_time
                        raise ArgumentError, "#{log_file_path} does not have any samples, cannot deduce the reference date. Use --date"
                    end
                    reference_time = reference_time.to_date.next_day
                end

                converter_file, source_tlb, target_tlb = Pocolog::Upgrade::DSL.create(
                    output_path, reference_time, source_type, target_type,
                    description: "Converter created at #{Time.now} from #{log_file_path.expand_path}")

                if !options[:silent]
                    puts "created template converter"
                    puts "  source type: #{source_tlb}"
                    puts "  target type: #{target_tlb}"
                    puts "You must edit #{converter_file} and perform the actual conversion"
                end
            end
        end
    end
end

