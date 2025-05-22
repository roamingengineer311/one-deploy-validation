###############################################################################
# Miscelanus of helper methods and constants
###############################################################################

############################################################################
# CLI Colors Constants
############################################################################

ANSI_RED    = "\33[31m"
ANSI_GREEN  = "\33[32m"
ANSI_RESET  = "\33[0m"
ANSI_YELLOW = "\33[33m"

# Color setters
def set_green(string)
    ANSI_GREEN + string + ANSI_RESET
end

def set_red(string)
    ANSI_RED + string + ANSI_RESET
end

def set_yellow(string)
    ANSI_YELLOW + string + ANSI_RESET
end

# Prints a map in a readable way.
#
# map: map to print
# tabs: number of identation tabs to use
def print_map(map, tabs = 0)
    tab = '  ' * tabs
    map.each do |k, v|
        print "#{tab}#{k.to_s.gsub('_', ' ')}: "

        if v.class == Array
            puts v.join(', ')
        elsif v.class == String && v.strip.split("\n").size > 1
            puts
            v.strip.each_line do |l|
                print "#{tab}\t#{l}"
            end
            puts
        elsif v.class == Hash
            puts
            print_map(v, tabs + 1)
        else
            puts v
        end
    end
end

# Check if path is a symbolic link using the cmd.
# Note that cmd might run commands remotely
def symlink?(cmd, path)
    cmd.run('test', '-L', path)[2].success?
end

# Read where path link points. Note that cmd might run commands remotely
def readlink(cmd, path)
    cmd.run('readlink', path)[0].strip
end

# Return an array with the content of `ID_LIKE` attribute from /etc/os-release
def get_distribution_like(cmd)
    rc = cmd.run('cat', '/etc/os-release')

    unless rc[2].success?
        raise 'Error getting distribution information for host '\
              "#{cmd.host}: #{rc[1]}"
    end

    rc[0].match(/ID_LIKE=\"?(?<distro>[\w\s]+)\"?$/)[:distro].split
end

# Get MySQL information from oned.conf
def get_mysql_credentials
    begin
        # Suppress augeas require warning message
        $VERBOSE = nil

        gem 'augeas', '~> 0.6'
        require 'augeas'
    rescue Gem::LoadError
        STDERR.puts(
            'Augeas gem is not installed, run `gem install ' \
            'augeas -v \'0.6\'` to install it'
        )
        exit(-1)
    end

    ops = {}

    oned_conf      = '/etc/one/oned.conf'
    work_file_dir  = File.dirname(oned_conf)
    work_file_name = File.basename(oned_conf)

    aug = Augeas.create(:no_modl_autoload => true,
                        :no_load          => true,
                        :root             => work_file_dir,
                        :loadpath         => oned_conf)

    aug.clear_transforms
    aug.transform(:lens => 'Oned.lns', :incl => work_file_name)
    aug.context = "/files/#{work_file_name}"
    aug.load

    ops[:user]    = aug.get('DB/USER')
    ops[:passwd]  = aug.get('DB/PASSWD')
    ops[:db_name] = aug.get('DB/DB_NAME')

    ops.each do |k, v|
        next if !v || !(v.is_a? String)

        ops[k] = v.chomp('"').reverse.chomp('"').reverse
        ops[k].gsub!("\\", '') if ops[k] && (ops[k].is_a? String)
    end

    ops
rescue StandardError => e
    STDERR.puts "Unable to parse oned.conf: #{e}"
    exit(-1)
end

def wait_loop(options={}, &block)
    args = {
        :timeout => 10,
        :success => true
    }.merge!(options)

    timeout    = args[:timeout]
    success    = args[:success]
    break_cond = args[:break]

    timeout_reached = nil
    v = nil
    t_start = Time.now

    while Time.now - t_start < timeout
        v = block.call

        if break_cond
            if break_cond.instance_of?(Regexp)
                raise "Expected '#{v}' not to match '#{break_cond}'" if v.match(break_cond)
            else
                raise "Expected value not to be '#{break_cond}'" if v == break_cond
            end
        end

        if success.instance_of? Regexp
            result = success.match(v)
        else
            result = v == success
        end

        if result
            timeout_reached = false
            return v
        else
            sleep 1
        end
    end

    raise 'Timeout reached' if timeout_reached == false
end
