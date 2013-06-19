require 'chef/knife/oktawave_base'

class Chef
  class Knife
    class OktawaveOciPowerOff < Knife
      include OktawaveBase
      banner 'knife oktawave oci power off ID (options)'
      def run
        validate!
        if name_args.length < 1
          show_usage
          ui.fatal('You must specify the OCI ID (try "knife oktawave oci list")')
          exit 1
        end
        id = name_args[0]
        oci = api.oci_get(id)
        api.oci_power_off(id)
        puts "Instance \##{id} (#{oci[:virtual_machine_name]}) powered off."
      end
    end
  end
end
