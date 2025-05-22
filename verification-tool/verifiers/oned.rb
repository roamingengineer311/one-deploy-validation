require 'opennebula'
require 'json'

# require_relative 'base'
require_relative '../utils/command'
require_relative '../utils/misc'

# Class implementing verification methods for Frontend services
class OnedVerifier

    class << self

        def verify(_client, config)
            info = {}
            cmd = Command.new(nil, nil)

            get_version(info, cmd)
            get_mirror(info, cmd)

            check_cli(info, cmd)
            check_ports(info, cmd, config)
            check_db_storage(info, cmd)
            check_services(info, cmd, config)

            print_map(info)
        end

        # Fill the info map with oned version and commit information
        def get_version(info, cmd)
            rc = cmd.run('oned', '-v')
            raise "Error getting OpenNebula version: #{rc[1]}" unless rc[2].success?

            regex = /(?<version>OpenNebula \d+\.\d+\.\d+) \((?<commit>[[:alnum:]]{8})\)(?<ee> Enterprise Edition)?/
            match = rc[0].match(regex)

            begin
                info[:version] = match[:version]
                info[:commit]  = match[:commit]

                if match[:ee].nil?
                    info[:Enterprise_Edition] = set_red('No')
                else
                    info[:Enterprise_Edition] = set_green('Yes')
                end
            rescue StandardError
                raise 'Error parsing OpenNebula version (oned -v)'
            end
        end

        # Fill the info map with the distro familly and the configured mirrors for OpenNebula
        def get_mirror(info, cmd)
            info[:distribution_like] = get_distribution_like(cmd)

            if info[:distribution_like].include?('debian')
                repo_path = '/etc/apt/sources.list.d/opennebula.list'
            elsif info[:distribution_like].include?('rhel')
                repo_path = '/etc/yum.repos.d/opennebula.repo'
            else
                raise 'Unsupported distribution.'
            end

            rc = cmd.run('cat', repo_path)
            unless rc[2].success?
                raise 'Error getting distribution information host '\
                      "#{cmd.host}: #{rc[1]}"
            end

            info[:mirror] = rc[0]
        end

        # Check if the CLI works with default auth and fill the info map with the result
        def check_cli(info, cmd)
            rc = cmd.run('oneuser', 'show')

            raise "Error checking CLI: #{rc[1]}" unless rc[2].success?

            info[:CLI] = set_green('Working') + ' (with default authentication)'
        end

        # Get ports listeneing on the host pointed by cmd, and checks if the
        # :default_ports defined at the configuration file are in use.
        # The info map is filled with the above information.
        def check_ports(info, cmd, config)
            # Get listening ports
            rc = cmd.run('ss', '-anpl')
            raise "Error getting listening services: #{rc[1]}" unless rc[2].success?

            listening_ports = {}
            rc[0].each_line do |line|
                regex = /^(?<protocol>\w+)\s+(?<mode>\w+)\s+\d+\s+\d+\s+(?<address>\d+.\d+.\d+.\d+):(?<port>\d+).*(?<info>users:.*)/
                match = line.match(regex)

                next if match.nil?

                listening_ports[Integer(match[:port])] = match
            end

            info[:ports] = config[:default_ports]

            # Check if default ports are available
            config[:default_ports].each do |serv, port|
                if listening_ports[port]
                    msg = "listnening (#{listening_ports[port]['address']}:"\
                          "#{port})"
                    info[:ports][serv] = set_green(msg)
                else
                    info[:ports][serv] = set_red("not listnening (#{port})")
                end
            end
        end

        # Check DB storage configuration and availability. The information is
        # stored in the info map.
        def check_db_storage(info, cmd)
            aux = {}

            creds = get_mysql_credentials

            # Get msyql datadir
            rc = cmd.run('mysql', '-u', creds[:user], "-p#{creds[:passwd]}",
                         '-srNe', 'show variables like "datadir"')
            raise "Error getting DB datadir: #{rc[1]}" unless rc[2].success?

            aux[:datadir] = rc[0].split[1]

            # Get msyql datadir size
            rc = cmd.run('findmnt', '-no', 'source,size,avail', '-T',
                         aux[:datadir])

            unless rc[2].success?
                raise "Error getting DB disk information #{info[:host]}: #{rc[1]}"
            end

            aux[:device], aux[:size], aux[:available] = rc[0].split

            # Get msyql cache size
            rc = cmd.run('mysql', '-u', creds[:user], "-p#{creds[:passwd]}",
                         '-srNe', 'SELECT variable_value FROM ' \
                         'information_schema.global_variables WHERE ' \
                         'variable_name = "innodb_buffer_pool_size"')

            raise "Error getting DB cache size: #{rc[1]}" unless rc[2].success?

            # Value in bytes, convert into GB
            aux[:db_cache_size] = "#{Float(rc[0].strip) / 1024**3}G"

            info[:db_storage] = aux
        end

        # Check if the services defined in the :enabled_units filed of the
        # configuration file are properly enabled. The information is stored in
        # the info map
        def check_services(info, cmd, config)
            distro = get_distribution_like(cmd)
            aux = {}

            config[:enabled_units].each do |service|
                if service.class == Hash
                    if distro.include?('debian')
                        srv_name = service[:debian]
                    elsif distro.include?('rhel')
                        srv_name = service[:rhel]
                    else
                        raise 'Unsupported distribution.'
                    end
                else
                    srv_name = service
                end

                # Check if unit is enabled
                rc = cmd.run('systemctl', 'is-enabled', srv_name)

                unless rc[2].success?
                    if rc[0].strip.downcase == 'disabled'
                        msg = 'disabled'
                    else
                        msg = "Error getting service info: #{rc[1].strip}"
                    end

                    aux[srv_name.to_sym] = set_red(msg)

                    next
                end

                aux[srv_name.to_sym] = set_green('enabled')
            end

            info[:enabled_units] = aux
        end

    end

end
