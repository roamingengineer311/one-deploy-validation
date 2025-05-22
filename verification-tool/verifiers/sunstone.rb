require 'opennebula'
require 'yaml'

# require_relative 'base'
require_relative '../utils/command'
require_relative '../utils/misc'

# Class implementing verification methods for Sunstone specifics
class SunstoneVerifier

    class << self

        def verify(_client, _config)
            info = {}
            cmd = Command.new(nil, nil)

            check_support_token(info, cmd)

            print_map(info)
        end

        # Check if the support token is set in the Sunstone configuration file.
        # It will mark the info as wrong if the tokne is either undefined or
        # doesn't have the right format. It will be marked as green otherwise
        def check_support_token(info, _cmd)
            sunstone_config = YAML.load_file('/etc/one/sunstone-server.conf')
            token = sunstone_config[:token_remote_support]

            if token.nil? || token.empty?
                info[:support_token] = set_red('not defined')
            else
                if token.match?(/^[[:alnum:]_]{8}:[[:alnum:]_]{8}$/)
                    info[:support_token] = set_green(token)
                else
                    msg = "#{token} (invalid format)"
                    info[:support_token] = set_red(msg)
                end
            end
        end

    end

end
