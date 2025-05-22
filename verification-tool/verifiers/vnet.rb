require 'opennebula'

# require_relative 'base'
require_relative '../utils/command'
require_relative '../utils/misc'

# Module implementing OpenNebula::Datastore exension for verifying Datastores
module VnetVerifier

    def self.verify(client, _config)
        vnet_pool = OpenNebula::VirtualNetworkPool.new(client)
        rc = vnet_pool.info

        if OpenNebula.is_error?(rc)
            raise "Error getting OpenNebula information: #{rc.message}"
        end

        vnet_pool.each do |vnet|
            vnet.info
            vnet.extend(VnetVerifier)
            vnet.verify(client)
        end
    end

    def self.extend_object(obj)
        raise 'Incorrect resource type' if obj.class != OpenNebula::VirtualNetwork

        class << obj

            def verify(client)
                info = { :name     => name,
                         :id       => id,
                         :vn_mad   => self['VN_MAD'],
                         :clusters => retrieve_elements('//CLUSTERS/ID'),
                         :phydev   => { :name => self['TEMPLATE/PHYDEV'] } }

                check_phydev(info, client)

                print_map(info)
            end

            private

            def check_phydev(info, client)
                info[:phydev][:config] = {}

                if info[:phydev][:name].empty?
                    info[:phydev][:config] = 'No phydev configured'
                    return
                end

                info[:clusters].each do |cluster_id|
                    cluster = OpenNebula::Cluster.new_with_id(cluster_id.to_i,
                                                              client)
                    cluster.info

                    cluster.host_ids.each do |host|
                        host = OpenNebula::Host.new_with_id(host, client)
                        host.info

                        cmd = Command.new(nil, host.name)
                        rc = cmd.run('ip', '--json', '-d', 'address',
                                     'show', info[:phydev][:name])

                        unless rc[2].success?
                            raise 'Error getting PHYDEV information on host: '\
                                "#{host.name}: #{rc[1]}"
                        end

                        phydev_info = JSON.parse(rc[0])[0]

                        info[:phydev][:config][host.name.to_sym] = {}
                        info[:phydev][:config][host.name.to_sym][:kind] = phydev_info['linkinfo']['info_kind']
                        info[:phydev][:config][host.name.to_sym][:mtu] = phydev_info['mtu']

                        addresses = []
                        phydev_info['addr_info'].each do |a|
                            addresses << "#{a['local']}/#{a['prefixlen']}"
                        end

                        info[:phydev][:config][host.name.to_sym][:addresses] = addresses
                    end
                end
            end

        end
    end

end
