require 'opennebula'
require 'json'

# require_relative 'base'
require_relative '../utils/command'
require_relative '../utils/misc'

# Module implementing OpenNebula::Datastore exension for verifying Datastores
module ImageDatastoreVerifier

    def self.verify(client, _config)
        ds_pool = OpenNebula::DatastorePool.new(client)
        rc = ds_pool.info

        if OpenNebula.is_error?(rc)
            raise "Error getting OpenNebula information: #{rc.message}"
        end

        ds_pool.each do |ds|
            ds.info

            next if ds.type_str == 'SYSTEM'

            ds.extend(ImageDatastoreVerifier)
            ds.verify
        end
    end

    def self.extend_object(obj)
        raise 'Incorrect resource type' if obj.class != OpenNebula::Datastore

        class << obj

            def verify
                begin
                    bridge_list = retrieve_elements('//BRIDGE_LIST')[0].split
                rescue StandardError
                    # command class will run the commands locally if remote host is nil
                    bridge_list = [nil]
                end

                print_map({ :name      => name,
                            :id        => id,
                            :tm        => self['TM_MAD'],
                            :ds        => self['DS_MAD'],
                            :base_path => self['BASE_PATH'] })

                bridge_list.each do |host|
                    cmd = Command.new(nil, host)

                    info = {
                        :host      => cmd.host,
                        :real_path => self['BASE_PATH']
                    }

                    if symlink?(cmd, info[:real_path])
                        info[:real_path] = readlink(cmd, info[:real_path])
                    end

                    if bridge_list != [nil]
                        info[:bridge_list] = bridge_list
                    end

                    # TODO, what about Ceph?
                    rc = cmd.run('findmnt', '-no', 'source,size,avail', '-T',
                                 info[:real_path])
                    unless rc[2].success?
                        raise 'Error getting disk information for host '\
                            "#{info[:host]}: #{rc[1]}"
                    end

                    # Get host information
                    info[:device], info[:size], info[:available] = rc[0].split

                    # Get ONE monitroing info
                    info[:one_size]      = "#{(Float(self['TOTAL_MB']) / 1024).round(1)}G"
                    info[:one_available] = "#{(Float(self['FREE_MB']) / 1024).round(1)}G"

                    print_map(info, 1)
                end
            end

        end
    end

end
