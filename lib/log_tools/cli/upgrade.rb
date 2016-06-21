require 'thor'
require 'log_tools'
require 'pastel'
require 'orogen'
require 'pocolog/file_upgrader'
require 'pocolog/cli/tty_reporter'

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
                    output_file = path.sub(/$/, options[:output] || '.upgraded')
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
                all_paths.each do |in_path, out_path|
                    if out_path.exist?
                        if options[:skip_existing]
                            puts "skipping #{in_path}: #{out_path} already exists"
                            next
                        else
                            out_path.unlink
                        end
                    end

                    puts
                    puts pastel.bold("processing logfile #{in_path}")
                    reporter = Pocolog::CLI::TTYReporter.new("|:bar| :current_byte/:total_byte :eta (:byte_rate/s)", total: in_path.stat.size)
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
        end
    end
end

