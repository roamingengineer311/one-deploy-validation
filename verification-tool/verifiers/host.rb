require 'opennebula'
require 'json'

# require_relative 'base'
require_relative '../utils/command'
require_relative '../utils/misc'

# Module implementing OpenNebula::Datastore exension for verifying Datastores
module HostVerifier

    def self.verify(client, _config)
        host_pool = OpenNebula::HostPool.new(client)
        rc = host_pool.info

        if OpenNebula.is_error?(rc)
            raise "Error getting OpenNebula information: #{rc.message}"
        end

        info = {}
        threads = []

        host_pool.each do |host|
            info[host.name.to_sym] = {}

            threads << Thread.new do
                host.info
                host.extend(HostVerifier)
                host.verify(info[host.name.to_sym])
            end
        end

        threads.each do |t|
            t.join
        end

        info.each do |_, v|
            print_map(v)
        end
    end

    def self.extend_object(obj)
        raise 'Incorrect resource type' if obj.class != OpenNebula::Host

        class << obj

            def verify(info)
                cmd = Command.new(nil, self.name)
                info[:name]   = name
                info[:id]     = id
                info[:im_mad] = self['IM_MAD']
                info[:vm_mad] = self['VM_MAD']

                check_state(info)
                check_offline_enable(info)
                check_monitoring_timestamp(info)
                check_hypervisor_enabled(info, cmd)
            end

            private

            def check_state(info)
                case state_str.upcase
                when 'MONITORED'
                    msg = set_green(state_str.upcase)
                when state_str.upcase.match(/ERROR/)
                    msg = set_red(state_str.upcase)
                else
                    msg = set_yellow(state_str.upcase)
                end

                info[:state] = msg
            end

            def check_offline_enable(info)
                if state_str != 'MONITORED'
                    msg = "Check cannot be done in #{state_str} state"
                    info[:reset_check] = set_red(msg)
                    return
                end

                # Set the host OFFLINE
                begin
                    offline
                    wait_loop(:success => 'OFFLINE') do
                        self.info
                        state_str
                    end
                rescue StandardError => e
                    msg = 'Error while seting the host into OFFLINE state:' \
                          "#{e.message}"

                    info[:reset_check] = set_red(msg)
                    return
                end

                # ENABLE the host back
                begin
                    enable
                    wait_loop(:success => 'MONITORED',
                              :timeout => 100, :break => /ERROR/) do
                        self.info
                        state_str
                    end
                rescue StandardError => e
                    msg = 'Error while enabling back the host' \
                          "#{e.message}"

                    info[:reset_check] = set_red(msg)
                    return
                end

                info[:reset_check] = set_green('OK')
            end

            def check_monitoring_timestamp(info)
                start_ts = self['MONITORING/TIMESTAMP']

                curr_ts = self['MONITORING/TIMESTAMP']
                retries = 13 # 130 seconds (default monitoring time 120)
                while start_ts == curr_ts && retries > 0
                    sleep 10
                    retries -= 1
                    self.info
                    curr_ts = self['MONITORING/TIMESTAMP']
                end

                if start_ts == curr_ts
                    msg = "Monitroing timestamp wasn't updated in the " \
                          'expected time (120s)'
                    msg = set_red(msg)
                else
                    msg = set_green('OK')
                end

                info[:monitoring_timestamp] = msg
            end

            def check_hypervisor_enabled(info, cmd)
                # only KVM requires a service enabled
                return if self['VM_MAD'].upcase != 'KVM'

                # Check if unit is enabled
                rc = cmd.run('systemctl', 'is-enabled', 'libvirtd')

                unless rc[2].success?
                    if rc[0].strip.downcase == 'disabled'
                        msg = 'disabled'
                    else
                        msg = "Error getting service info: #{rc[1].strip}"
                    end

                    info[:libvirtd] = set_red(msg)
                    return
                end

                info[:libvirtd] = set_green('enabled')
            end

        end
    end

end
