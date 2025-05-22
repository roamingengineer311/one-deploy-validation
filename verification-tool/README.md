# oneverify

The `oneverify` tool aims to help during the cloud verification process by providing information regarding the resources used by the current installation, its configuration, and helpful tips and checklist to ensure that important items are checked properly.

```
./oneverify -h
Usage: ./oneverify [options]
    -D, --debug                      Run in debug mode
        --dump                       Dump verification info into STDOUT (not interactive mode).Checklist/tips wont be printed

```

The `debug` option will print the entire bactrace when an error appears, while normaly only the error message will be printed. The dump mode is intended to be used as a way of dumping the information check to be attached to the customer final report.

## File Structure

```
├── config -----------------------------------------> Contains configuration files 
│   ├── checklist.yaml -----------------------------> YAML file containing the checklist for each verifier 
│   └── config.yaml --------------------------------> Contains general configuration attributes (e.g port to check, ...)
├── oneverify --------------------------------------> Main tool script - controls the tool workflow
├── utils
│   ├── command.rb ---------------------------------> Class for executing commands at specific host
│   └── misc.rb
└── verifiers --------------------------------------> Contains the implementation of each verifier. Each verifier defines 
    ├── host.rb                                       the `verify(_client, config)` method which takes care of carrying 
    ├── img_datastore.rb                              every verfication step needed. Usually the results are loaded into 
    ├── oned.rb                                       the `info` map which is printend at the end.
    ├── sunstone.rb
    ├── sys_datastore.rb
    └── vnet.rb

```

