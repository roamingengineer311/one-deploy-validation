require 'opennebula'
require 'json'

# require_relative 'base'
require_relative '../utils/command'
require_relative '../utils/misc'

# Module implementing OpenNebula::Datastore exension for verifying Datastores
module SystemDatastoreVerifier

    def self.verify(client, _config)
        ds_pool = OpenNebula::DatastorePool.new(client)
        rc = ds_pool.info

        if OpenNebula.is_error?(rc)
            raise "Error getting OpenNebula information: #{rc.message}"
        end

        ds_pool.each do |ds|
            ds.info

            next if ds.type_str != 'SYSTEM'

            ds.extend(SystemDatastoreVerifier)
            ds.verify(client)
        end
    end

    def self.extend_object(obj)
        raise 'Incorrect resource type' if obj.class != OpenNebula::Datastore

        class << obj

            def verify(client)
                info = { :name      => name,
                         :id        => id,
                         :tm        => self['TM_MAD'],
                         :base_path => self['BASE_PATH'],
                         :clusters  => retrieve_elements('//CLUSTERS/ID') }

                print_map(info)

                get_hosts(client, info).each do |host|
                    cmd = Command.new(nil, host)
                    info = {}

                    case self['TM_MAD'].downcase
                    when 'ssh', 'shared', 'qcow2'
                        verify_file_ds(cmd, info)
                    when 'fs_lvm', 'fs_lvm_ssh'
                        verify_file_ds(cmd, info) # storage used for metadata files
                        verify_lvm_ds(cmd, info)
                    else
                        raise "Support for TM_MAD=#{tm_mad} not " \
                            'implemented. Please check it manually.'
                    end

                    print_map({host.to_sym => info}, 1)
                end
            end

            private

            def get_hosts(client, info)
                hosts = []
                tm_mad = self['TM_MAD']

                case tm_mad.downcase
                when 'ssh', 'fs_lvm', 'fs_lvm_ssh'
                    info[:clusters].each do |cluster_id|
                        cluster = OpenNebula::Cluster.new_with_id(cluster_id.to_i,
                                                                  client)

                        cluster.info
                        cluster.host_ids.each do |host|
                            host = OpenNebula::Host.new_with_id(host, client)
                            host.info

                            hosts << host.name
                        end
                    end

                    hosts
                when 'shared', 'qcow2'
                    begin
                        hosts = retrieve_elements('//BRIDGE_LIST')[0].split
                    rescue StandardError
                        hosts = [nil]
                    end
                else
                    raise "Support for TM_MAD=#{tm_mad} not implemented. " \
                          'Please check it manually.'
                end
            end

            def verify_file_ds(cmd, info)
                info[:real_path] = self['BASE_PATH']

                if symlink?(cmd, info[:real_path])
                    info[:real_path] = readlink(cmd, info[:real_path])
                end

                # TODO, what about Ceph? LVM
                rc = cmd.run('findmnt', '-no', 'source,size,avail', '-T',
                             info[:real_path])
                unless rc[2].success?
                    raise 'Error getting disk information for host '\
                        "#{cmd.host}: #{rc[1]}"
                end

                # Get host information
                info[:device], info[:size], info[:available] = rc[0].split

                # Get ONE monitroing info
                info[:one_size]      = "#{(Float(self['TOTAL_MB']) / 1024).round(1)}G"
                info[:one_available] = "#{(Float(self['FREE_MB']) / 1024).round(1)}G"

                info
            end

            def verify_lvm_ds(cmd, info)
                info[:volume_group] = "vg-one-#{id}"

                # Gather VG info
                rc = cmd.run('sudo', 'vgdisplay', '--separator', ':', '--units',
                             'G', '-o', 'vg_size,vg_free', '--noheadings',
                             '-C', info[:volume_group])

                unless rc[2].success?
                    raise 'Error getting VGs information for host '\
                        "#{cmd.host}: #{rc[1]}"
                end

                info[:vg_size], info[:vg_free] = rc[0].strip.split(':')
            end

        end
    end

end
