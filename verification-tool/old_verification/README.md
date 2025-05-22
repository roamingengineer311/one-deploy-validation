## Description

Verification testing can be executed in two modes install verification and update verification. Both modes will run the same tests, but install verification will run it in every host of each cluster and upgrade verification will run in just two host of each cluster.

### KVM

In order to run the verification test for KVM you can use the generate_defaults_files.rb tool for generate a default.yaml file for each cluster, each file will contains the hosts belonging to each cluster. For upgrade verification you can run the generate_defaults_files.rb with "upgrade" as a parameter and each file will have just two of the hosts.

        $ ./generate_default_files.rb # will generate the files with all the host
        $ ./generate_default_files.rb upgrade # will generate the files with just two hosts
        
Once the defaults.yaml are generated it's needed to replace all the variables inside in order to use the right templates, vnets...

### vCenter

For vCenter test it's needed to create a defaults.yaml file for each cluster, using as a template the `/verification/vCenter/defaults.yaml` file, and replacing all the inside variables by the right ones.

## Running the tests
Once all the defaults.yaml are ready you have to run the tests for each cluster using the readiness tool (https://github.com/OpenNebula/infra/wiki/Readiness) with the the corresponding test.yaml (if the cluster is KVM or vCenter) and the corresponding defaults.yaml.
        
        $ cd development/readiness #Move to the development repository
        $ ./readiness.rb --defaults ~/engineering/verification/<KVM-vCenter>/default.yaml --microenv ~/engineering/verification/<KVM-vCenter>/test.yaml

