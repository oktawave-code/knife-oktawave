require 'chef/knife/oktawave_base'
require 'chef/node'
require 'chef/api_client'

class Chef
  class Knife
    class OktawaveOciDelete < Knife

      include Knife::OktawaveBase

      banner "knife oktawave oci delete ID [ID] (options)"

      option :purge,
        :long => "--purge",
        :short => "-P",
        :boolean => true,
        :default => false,
        :description => "Destroy corresponding node and client on the Chef Server, in addition to destroying the OCI instance. Assumes node and client have the same name as the server (if not, add the '--node-name' option)."

      option :chef_node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The name of the node and client to delete, if it differs from the server name. Only has meaning when used with the '--purge' option."

      def destroy_item(klass, name, type_name)
        begin
          object = klass.load(name)
          object.destroy
          ui.warn("Deleted #{type_name} #{name}")
        rescue Net::HTTPServerException
          ui.warn("Could not find a #{type_name} named #{name} to delete!")
        end
      end

      def run
        validate!
        @name_args.each do |oci_id|
          oci = get_oci(oci_id)
          print_oci_summary(oci)
          oci_name = oci[:virtual_machine_name]
          puts "\n"
          confirm("Do you really want to delete this OCI instance")
          api.oci_delete(oci_id)
          ui.warn("Deleted OCI instance \##{oci_id} (#{oci_name})")
          if config[:purge]
            thing_to_delete = config[:chef_node_name] || oci_name
            destroy_item(Chef::Node, thing_to_delete, "node")
            destroy_item(Chef::ApiClient, thing_to_delete, "client")
          else
            ui.warn("Corresponding node and client for the #{oci_id} instance (#{oci_name}) were not deleted and remain registered with the Chef Server")
          end
        end
      end

    end
  end
end
