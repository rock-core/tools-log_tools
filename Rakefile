require 'utilrb/doc/rake'
task 'default'
Utilrb.doc

begin
    require 'hoe'
    Hoe::plugin :yard

    Hoe::RUBY_FLAGS.gsub! /-w/, ''

    hoe_spec = Hoe.spec 'log_tools' do
        developer 'Alexander Duda', 'alexander.duda@dfki.de'
        self.version = 0.1
        self.summary = 'Ruby library for data processing'
        self.urls        = ["http://rock-robotics.org/"]
        self.readme_file = FileList['README*'].first
        self.history_file = "History.txt"
        licenses << 'GPLv2+'

        extra_deps <<
            ['flexmock'] <<
            ['hoe'] <<
            ['hoe-yard'] <<

        test_globs = ['test/suite.rb']
    end

    Rake.clear_tasks(/^default$/)
    task :default => []
    task :docs => :yard
    task :redocs => :yard
rescue LoadError
    STDERR.puts "cannot load the Hoe gem. Distribution is disabled"
rescue Exception => e
    puts e.backtrace
    if e.message !~ /\.rubyforge/
        STDERR.puts "WARN: cannot load the Hoe gem, or Hoe fails. Publishing tasks are disabled"
        STDERR.puts "WARN: error message is: #{e.message}"
    end
end
