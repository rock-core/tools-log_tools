# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV['TEST_ENABLE_COVERAGE'] == '1'
    begin
        require 'simplecov'
        SimpleCov.start
    rescue LoadError
        require 'log_tools'
        LogTools.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require 'log_tools'
        LogTools.warn "coverage is disabled: #{e.message}"
    end
end

require 'log_tools'
require 'flexmock/minitest'
require 'pocolog/test_helpers'
require 'minitest/autorun'
require 'minitest/spec'
FlexMock.partials_are_based = true

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
    rescue Exception
        LogTools.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

module LogTools
    # This module is the common setup for all tests
    #
    # It should be included in the toplevel describe blocks
    #
    # @example
    #   require 'log_tools/test'
    #   describe LogTools do
    #   end
    #
    module SelfTest
        include Pocolog::TestHelpers

        def logfile_pathname(basename)
            Pathname.new(logfile_path(basename))
        end
    end
end

module Minitest
    class Test
        include LogTools::SelfTest
    end
end

