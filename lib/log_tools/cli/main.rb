require 'thor'
require 'log_tools'
require 'log_tools/cli/upgrade'

module LogTools
    module CLI
        class Main < Thor
            desc 'upgrade ...', 'commands related to upgrading old log files'
            subcommand 'upgrade', Upgrade
        end
    end
end

