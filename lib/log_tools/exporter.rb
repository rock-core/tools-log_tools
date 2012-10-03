require 'pocolog'
require 'utilrb/logger'
require 'orocos'
require 'pp'

module LogTools
    extend Logger::Root('LogTools', Logger::INFO)

    module ExporterBase
        def self.included(other)
            other.extend ClassMethods
            @exporters ||= Array.new
            @exporters << other
        end

        def self.exporters
            @exporters
        end

        def export(value,filename,options = Hash.new)
        end

        module ClassMethods
            attr_reader :doc, :suffix, :type_name

            def type_name=(names)
                @type_name = Array(names)
            end

            def suffix=(suffix)
                @suffix = Array(suffix)
            end

            def handle_type_name?(name)
                if self.type_name.include? name
                    return true
                else
                    return false
                end
            end

            def normalize_name(name)
                if(name_m = Orocos.master_project.intermediate_type_for(name))
                    ExporterBase.info "#{name} is an intermedia type called #{name_m}"
                    name_m.name
                else
                    name
                end
            rescue Typelib::NotFound
                name
            end

            def handle_suffix?(suffix)
                if self.suffix.include? suffix 
                    return true
                else
                    return false
                end
            end

            def handle_options?(options)
            end

            def pretty_print(q)
                q.text "Exporter: #{name}"
                q.newline
                q.nest(2) do
                    q.breakable
                    q.text "#{doc}"
                    q.breakable
                    q.text "type: #{type_name}"
                    q.breakable
                    q.text "file suffix: " 
                    suffix.pretty_print(q)
                    q.breakable
                end
            end
        end
    end

    class Exporter
        extend Logger::Hierarchy
        extend Logger::Forward

        attr_accessor :output_folder, :stream_name,:stream_type, :filename, :exporter_name ,:start_index, :end_index

        def stream_name=(streams)
            @stream_name = Array(streams)
        end

        def stream_type=(stream_types)
            @stream_type = Array(stream_types)
        end

        def initialize
        end

        def find_exporter(stream,filename,exporter_name=nil)
            suffix = if filename =~ /\.(.*)$/
                        $1
                     else
                         nil
                     end
            ExporterBase.exporters.find do |exp|
                if exporter_name && exp.class.name == exporter_name
                    exp
                elsif exp.handle_suffix?(suffix) && exp.handle_type_name?(stream.type.name)
                    exp
                end
            end
        end

        def generate_filename(pattern,stream_name,sample_index)
            name = pattern.gsub("#STREAM",stream_name)
            name.gsub("#INDEX",sample_index.to_s)
        end

        def export(*logfiles)
            #create folder if given
            if output_folder && !File.directory?(output_folder)
                Dir.mkdir(output_folder)
            end

            logfiles.flatten!
            logfiles.each do |logfile|
                Exporter.info "exporting #{logfile}"

                file = Pocolog::Logfiles.open(logfile)
                file.streams.each do |stream|
                    if(stream_name && !stream_name.include?(stream.name))||(stream_type && !stream_type.include?(stream.type.name))
                        #ignore all streams which are not listed if a filter is given
                        Exporter.info "ignoring stream #{stream.name} (#{stream.size} samples)"
                        next
                    end

                    #find exporter
                    exporter_class = find_exporter(stream,filename,exporter_name)
                    if !exporter_class
                        Exporter.info "ignoring stream #{stream.name} (#{stream.size} samples): cannot find an exporter for this type"
                        next
                    end

                    exporter = exporter_class.new(stream)
                    index = 0
                    time = Time.now
                    Exporter.info " exporting stream #{stream.name} (#{stream.size} samples): "
                    stream.samples.each do |rt,lg,sample|
                        if start_index && index < start_index
                            index += 1
                            next
                        end
                        if (Time.now-time).to_f < 1
                            Exporter.debug "    #{stream.name}.sample #{index+1}/#{stream.size}"
                        else
                            time = Time.now
                            Exporter.info "    #{stream.name}.sample #{index+1}/#{stream.size}"
                        end

                        temp_index = index.to_s
                        temp_index = "0"*(stream.size.to_s.size-temp_index.size)+temp_index
                        file = generate_filename(self.filename,stream.name,temp_index)
                        file = File.join(output_folder,filename) if output_folder

                        # Undo any custom convertions that typelib might have applied
                        sample = Typelib.from_ruby(sample, stream.type)
                        exporter.export(sample,file)
                        index += 1
                        if end_index && end_index > 0 && index > end_index
                            break
                        end
                    end
                end
            end
        end
    end
end
