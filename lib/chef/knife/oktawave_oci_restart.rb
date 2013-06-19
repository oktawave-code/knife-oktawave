require 'chef/knife/oktawave_base'

class Chef
  class Knife
    class OktawaveOciRestart < Knife
      include OktawaveBase
      banner 'knife oktawave oci restart ID (options)'
      def run
        validate!
        if name_args.length < 1
          show_usage
          ui.fatal('You must specify the OCI ID (try "knife oktawave oci list")')
          exit 1
        end
        id = name_args[0]
        oci = api.oci_get(id)
        api.oci_restart(id)
        puts "Instance \##{id} (#{oci[:virtual_machine_name]}) restarted."
      end
    end
  end
end
