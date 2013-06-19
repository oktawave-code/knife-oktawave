require 'chef/knife/oktawave_base'

class Chef
  class Knife
    class OktawaveOciList < Knife
      include OktawaveBase
      banner 'knife oktawave oci list (options)'
      def run
        validate!
        puts ui.list([
          ui.color('ID', :bold),
          ui.color('Name', :bold),
          ui.color('Class', :bold)
        ] + api.oci_list.map {|o| [
          o[:virtual_machine_id] || '',
          o[:virtual_machine_name],
          api.dive2name(o[:vm_class])[:item_name]
        ]}.flatten(1), :columns_across, 3)
      end
    end
  end
end
