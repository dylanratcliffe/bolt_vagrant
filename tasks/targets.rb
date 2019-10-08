#!/opt/puppetlabs/bolt/bin/ruby
# frozen_string_literal: true

require 'csv'
require 'json'

# Class for organising the code
module Bolt # rubocop:disable Style/ClassAndModuleChildren
  # Interacts with the vagrant CLI
  class Vagrant
    def initialize(opts = {})
      @status         = nil
      @ssh_config     = {}
      @vagrant_dir    = opts['vagrant_dir'] || Dir.pwd
      @vagrant_binary = which('vagrant')
      @winrm_regex    = Regexp.new(opts['winrm_regex'] || 'windows')
      @node_match     = opts['match'].nil? ? nil : Regexp.new(opts['match'])
    end

    def inventory_targets
      targets = []

      # Get the running nodes using vagrant status
      running_nodes = status.keep_if { |_name, details| details['state'] == 'running' }

      unless @node_match.nil?
        running_nodes = running_nodes.select { |n, _d| @node_match.match?(n) }
      end

      # Split into winrm and ssh transports
      winrm_nodes = running_nodes.select { |n, _d| @winrm_regex.match?(n) }
      ssh_nodes   = running_nodes.reject { |n, _d| @winrm_regex.match?(n) }

      # Get the config
      winrm_conf = winrm_config(winrm_nodes.keys)
      ssh_conf   = ssh_config(ssh_nodes.keys)

      # Convert to SSH style config
      ssh_conf.each do |_name, config|
        targets << {
          'uri'    => "ssh://#{config['HostName']}:#{config['Port']}",
          'name'   => config['Host'],
          'config' => {
            'ssh' => {
              'user'           => config['User'],
              'run-as'         => 'root',
              'private-key'    => config['IdentityFile'],
              'host-key-check' => false,
            },
          },
        }
      end

      # Convert to winrm config
      winrm_conf.each do |_name, config|
        targets << {
          'uri'    => "winrm://#{config['HostName']}:#{config['Port']}",
          'name'   => config['Host'],
          'config' => {
            'winrm' => {
              'user'     => config['User'],
              'password' => config['Password'],
              'ssl'      => false,
            },
          },
        }
      end

      targets
    end

    def status
      return @status if @status

      debug('Running \'vagrant status\' to get the machine list')

      @status = parse_machine_readable(exec("#{@vagrant_binary} status --machine-readable"))
    end

    def ssh_config(hosts)
      hosts_regex = "/#{hosts.join('|')}/"

      debug("Running 'vagrant ssh-config '#{hosts_regex}'' to get the ssh details")
      hosts = parse_machine_readable(exec("#{@vagrant_binary} ssh-config '#{hosts_regex}' --machine-readable"))

      # Delete all non-winrm hosts
      hosts.keep_if { |_n, d| d.key? 'ssh-config' }

      # Parse the SSH config
      hosts.each do |host, details|
        hosts[host] = parse_ssh_config(details['ssh-config'].gsub('\n', "\n"))
      end

      @ssh_config = hosts
    end

    def winrm_config(hosts)
      hosts_regex = "/#{hosts.join('|')}/"

      debug("Running 'vagrant winrm-config '#{hosts_regex}'' to get the ssh details")
      hosts = parse_machine_readable(exec("#{@vagrant_binary} winrm-config '#{hosts_regex}' --machine-readable"))

      # Delete all non-winrm hosts
      hosts.keep_if { |_n, d| d.key? 'winrm-config' }

      # Parse the config
      hosts.each do |host, details|
        hosts[host] = parse_ssh_config(details['winrm-config'].gsub('\n', "\n"))
      end

      @ssh_config = hosts
    end

    # Executes a commend from the correct directory
    def exec(command)
      result = ''

      Dir.chdir(@vagrant_dir) do
        result = `#{command}`
      end

      result
    end

    private

    def deep_merge(first, second)
      merger = proc do |_key, v1, v2|
        (Hash === v1 && Hash === v2) ? v1.merge(v2, &merger) : v2 # rubocop:disable Style/CaseEquality
      end
      first.merge(second, &merger)
    end

    # This parses the CSV output from vagrant --machine-readable options
    def parse_machine_readable(output)
      parsed = {}

      CSV.new(output).each do |columns|
        # Remove anything that doesn't have a valid first column
        next unless columns[0].to_i > 10_000

        # Remove the timestamp
        columns.shift

        # Convert to a hash
        parsed = deep_merge(parsed, columns.reverse.reduce { |a, n| { n => a } })
      end

      # Detele things that aren't related to a node
      parsed.delete(nil)

      parsed
    end

    def parse_ssh_config(output)
      ssh_config_regex = %r{^\s*(?<setting>[A-Z]\w+)\s+(?<value>.*)$}

      Hash[output.scan(ssh_config_regex)]
    end

    def debug(message)
      STDERR.puts("DEBUG -> #{message}")
    end

    # Cross-platform way of finding an executable in the $PATH.
    #
    #   which('ruby') #=> /usr/bin/ruby
    def which(cmd)
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : [''] # rubocop:disable Style/TernaryParentheses
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          # Check that it's an executable but also that it's not the ruby version of vagrant
          return exe if File.executable?(exe) && !File.directory?(exe) && (File.read(exe)[0..1] != '#!')
        end
      end
      nil
    end
  end
end

# Parse the input
params = JSON.parse(STDIN.read)

# Get the details
vagrant = Bolt::Vagrant.new(params)
targets = vagrant.inventory_targets

result = {
  'targets' => targets,
}

puts(result.to_json)
