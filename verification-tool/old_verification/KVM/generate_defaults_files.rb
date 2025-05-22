#!/usr/bin/env ruby
#
#Generates a default.yaml file for each cluster named <cluster_name>.yaml
#

num_hosts = ARGV[0] == "upgrade" ? 1 : -1
clusters = `onecluster list --csv -l NAME`.split("\n")[1..-1]

clusters.each { |cluster|
	hosts = `onehost list --csv -l NAME,CLUSTER -f CLUSTER=#{cluster}`.split("\n")[1..-1]
	hosts_yaml = hosts[0].nil? ? "" : "- #{hosts[0].split(',')[0]}\\n" 
	
	if !hosts[1].nil?
		hosts[1..num_hosts].each { |host|
			hosts_yaml << "  - #{host.split(',')[0]}\\n"
		}
	end
	
	system("cp defaults.yaml #{cluster}.yaml")
	system("sed -i -e 's/%HOSTS%/" + hosts_yaml  + "/' #{cluster}.yaml")
}

