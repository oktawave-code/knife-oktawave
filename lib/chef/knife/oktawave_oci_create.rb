require 'chef/knife/oktawave_base'

class Chef
  class Knife
    class OktawaveOciCreate < Knife
      include OktawaveBase

      banner 'knife oktawave oci create (options)'

      option :node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The Chef node name for your new node",
        :proc => Proc.new { |key| Chef::Config[:knife][:node_name] = key }

      option :bootstrap_version,
        :long => "--bootstrap-version VERSION",
        :description => "The version of Chef to install",
        :proc => Proc.new { |v| Chef::Config[:knife][:bootstrap_version] = v }

      option :run_list,
        :short => "-r RUN_LIST",
        :long => "--run-list RUN_LIST",
        :description => "Comma separated list of roles/recipes to apply",
        :proc => lambda { |o| o.split(/[\s,]+/) }

      option :json_attributes,
        :short => "-j JSON",
        :long => "--json-attributes JSON",
        :description => "A JSON string to be added to the first run of chef-client",
        :proc => lambda { |o| JSON.parse(o) }

      option :distro,
        :short => "-d DISTRO",
        :long => "--distro DISTRO",
        :description => "Bootstrap a distro using a template; default is 'chef-full'",
        :proc => Proc.new { |d| Chef::Config[:knife][:distro] = d }

      option :skip_bootstrap,
        :long => "--skip-bootstrap",
        :boolean => true,
        :default => false,
        :description => "Only create the OCI, do not perform Chef bootstrap.",
        :proc => Proc.new { Chef::Config[:knife][:skip_bootstrap] = true }

      option :template,
        :short => '-T TEMPLATE_ID',
        :long => '--oci-template TEMPLATE_ID',
        :description => 'The OCI template ID to use. Run "knife oktawave template list" for a list of templates',
        :proc => Proc.new { |t| Chef::Config[:knife][:template] = t }

      option :oci_name,
        :long => '--oci-name NAME',
        :description => 'The OCI name. Default is the same as node_name.',
        :proc => Proc.new { |n| Chef::Config[:knife][:oci_name] = n }

      option :oci_id,
        :short => '-B ID',
        :long => '--bootstrap-oci ID',
        :description => 'ID of an existing OCI. Setting this will cause knife to skip creating a new OCI and just perform the bootstrap.',
        :proc => Proc.new { |id| Chef::Config[:knife][:oci_id] = id }

      option :oci_class,
        :short => '-C CLASS',
        :long => '--oci-class CLASS',
        :description => 'The OCI class to use ("Small", "Extreme" etc.). Defaults to the minimal class for the template.',
        :proc => Proc.new { |c| Chef::Config[:knife][:oci_class] = c }

      option :oci_autoscaler,
        :short => '-a TYPE',
        :long => '--oci-autoscaler TYPE',
        :description => 'Autoscaler type ("on", "off" or "notify", default is "on").',
        :proc => Proc.new { |a| Chef::Config[:knife][:oci_autoscaler] = a }

      option :prerelease,
        :long => "--prerelease",
        :description => "Install the pre-release chef gems"

      deps do
        require 'chef/knife/bootstrap'
        Chef::Knife::Bootstrap.load_deps
      end

      # Get a config value
      def conf(key)
        key = key.to_sym
        config[key] || Chef::Config[:knife][key]
      end

      # wait for sshd to accept connections
      def tcp_test_ssh(hostname, ssh_port = 22, tries = 8, timeout = 16)
        print "\n#{ui.color("Waiting for sshd ", :magenta)}" + '.'
        tries.times {|i|
          begin
            print "."
            tcp_socket = TCPSocket.new(hostname, ssh_port)
            readable = IO.select([tcp_socket], nil, nil, timeout)
            if readable
              puts " done"
              Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
              return true
            end
          rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, IOError
            sleep timeout
            false
          rescue Errno::EPERM, Errno::ETIMEDOUT
            false
          ensure
            tcp_socket && tcp_socket.close
          end
        }
      end

      def bootstrap_common_params(bootstrap)
        bootstrap.config[:run_list] = config[:run_list]
        bootstrap.config[:bootstrap_version] = conf(:bootstrap_version)
        bootstrap.config[:environment] = conf(:environment)
        bootstrap.config[:prerelease] = conf(:prerelease)
        bootstrap.config[:first_boot_attributes] = conf(:json_attributes) || {}
        bootstrap.config[:encrypted_data_bag_secret] = conf(:encrypted_data_bag_secret)
        bootstrap.config[:encrypted_data_bag_secret_file] = conf(:encrypted_data_bag_secret_file)
        bootstrap
      end

      def bootstrap_for_linux_node(oci)
        bootstrap = Chef::Knife::Bootstrap.new
        bootstrap.name_args = [@ip]
        bootstrap.config[:ssh_user] = 'root'
        bootstrap.config[:ssh_password] = conf(:ssh_password)
        bootstrap.config[:chef_node_name] = conf(:node_name) || oci[:virtual_machine_name] || self.fqdn || @ip || 'oci_unknown'
        bootstrap.config[:distro] = conf(:distro) || "chef-full"
        bootstrap.config[:use_sudo] = false
        bootstrap_common_params(bootstrap)
      end

      def fqdn
        require 'resolv'
        @fqdn ||= Resolv.getname(@ip)
      end

      def bootstrap(id)
        if conf(:skip_bootstrap)
          puts "skip_bootstrap option set, skipping bootstrap."
          return
        end
        unless id
          show_usage
          ui.fatal('You must specify the OCI ID (try "knife oktawave oci list")')
          exit 1
        end
        @oci = get_oci(id)
        @ip = api.oci_ip(@oci)
        puts "\nBootstrapping Chef on Oktawave Cloud Instance #{self.fqdn} (#{@ip}):"
        puts "(if this fails for some reason, you can retry by running \"knife oktawave oci create --bootstrap-oci #{id}\")"
        self.print_oci_summary(@oci)
        unless conf(:oci_id)
          print "\n#{ui.color("Waiting for the OCI ", :magenta)}" + '.'
          sleep 24
          print "done\n"
        end
        unless conf(:ssh_password)
          pass = api.oci_password(id)
          if pass != nil
            Chef::Config[:knife][:ssh_password] = pass
          end
        end
        if !tcp_test_ssh(@ip)
          ui.fatal('Failed to estabilish SSH connection for bootstrap')
          exit 1
        end
        sleep 1
        bootstrap_for_linux_node(@oci).run
      end

      def run
        $stdout.sync = true
        validate!
        if conf(:oci_id)
          bootstrap(conf(:oci_id))
          return
        end
        validate!([:node_name, :template])
        period = 60 # minutes
        interval = 5 # seconds
        timeout = 30 # iterations, multiply by interval for seconds approximation
        object_type_id = 139  # Machine
        name = conf(:oci_name) || conf(:node_name)
        template_id = conf(:template)
        oci_class = conf(:oci_class) || nil
        oci_class = api.oci_class_id(oci_class) if oci_class
        puts "Creating a new OCI instance \"#{name}\" (template #{template_id})"
        rj = api.running_jobs(period)
        old_oci_ids = Hash[
          api.oci_list.map {|o| [o[:virtual_machine_id], true]} +
          rj.select {|j| j[:object_type_id].to_i == object_type_id}.map {|j| [j[:object_id], true]}
        ]
        old_job_ids = Hash[rj.map {|j| [j[:asynchronous_operation_id], true]}]
        api.oci_create(template_id, name, oci_class, conf(:oci_autoscaler))
        oci_id = -1
        it = 0
        
        while true
          it += 1
          sleep interval
          all_jobs = api.running_jobs(period)
          jobs = all_jobs.select {|o| # select operations on the new machine only
            (not old_job_ids[o[:asynchronous_operation_id]])\
            and
            (o[:object_type_id].to_i == object_type_id)\
            and
            o[:status_id].to_i == 135\
            and
            o[:object_name] == name\
            and
            (
              (
                oci_id != -1\
                and
                o[:object_id].to_i == oci_id
              )\
              or
              oci_id == -1
            )\
            and
            (
              not old_oci_ids[o[:object_id]]\
              or
              o[:object_id].to_i == 0
            )
          }
          for j in jobs
            if oci_id == -1 and j[:object_id].to_i != 0
              puts "Created new OCI with ID: #{j[:object_id]}"
              oci_id = j[:object_id].to_i # we know the ID now, so we remember it
            end
            if oci_id != -1 and j[:object_id].to_i != oci_id  # different OCI id
              next
            end
            puts "#{j[:operation_type_name]}: #{j[:progress]}%"
          end
          if (jobs.length == 0 and oci_id != -1) or (it > timeout)  # timeout or finished
            break
          end
        end
        if (oci_id == -1)
          ui.fatal("Failed to deploy instance. Please check it at admin.oktawave.com and bootstrap manually.")
          exit 1
        end
        bootstrap(oci_id)
      end
    end
  end
end
