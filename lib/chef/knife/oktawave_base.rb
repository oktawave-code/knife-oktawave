#
# Base class for knife oktawave subcommands
#

require 'chef/knife'
require 'oktawave/client'

class Chef
  class Knife
    module OktawaveBase

      def self.included(includer)
        includer.class_eval do
          deps do
          end

          option :oktawave_login,
            :short => "-A LOGIN",
            :long => "--oktawave-login LOGIN",
            :description => "Your Oktawave login",
            :proc => Proc.new { |l| Chef::Config[:knife][:oktawave_login] = l }

          option :oktawave_password,
            :short => "-K PASSWORD",
            :long => "--oktawave-password PASSWORD",
            :description => "Your Oktawave password",
            :proc => Proc.new { |key| Chef::Config[:knife][:oktawave_password] = key }
          
          option :debug,
            :long => "--debug",
            :description => "Enable debug mode (including a log of SOAP API requests)",
            :proc => Proc.new { |d| Chef::Config[:knife][:debug] = d }

        end
      end

      def oci_not_found
        ui.fatal("OCI not found")
        exit 1
      end

      # A wrapper around oci_get
      def get_oci(id)
        res = api.oci_get(id)
        if !res[:virtual_machine_id]
          oci_not_found
        end
        res
      end

      # Returns the underlying Oktawave::OktawaveClient instance
      def api
        @api ||= begin
          api = Oktawave::OktawaveClient.new(
            config[:oktawave_login],
            config[:oktawave_password],
            Chef::Config[:knife][:debug] ? true : false
          )
        end
      end

      def msg_pair(label, value, color=:cyan)
        if value && !value.to_s.empty?
          puts "#{ui.color(label, color)}: #{value}"
        end
      end

      # Prints basic information about an OCI. Expects the oci argument to be an
      # instance returned by get_oci.
      def print_oci_summary(oci)
        if !oci[:virtual_machine_id]
          oci_not_found
        end
        msg_pair("OCI ID", oci[:virtual_machine_id])
        msg_pair("Name", oci[:virtual_machine_name])
        msg_pair("Class", api.dive2name(oci[:vm_class])[:item_name])
        msg_pair("Status", api.dive2name(oci[:status])[:item_name])
      end

      def validate!(keys=[:oktawave_login, :oktawave_password])
        errors = []
        keys.each do |k|
          unless Chef::Config[:knife][k]
            errors << "You did not provide a valid '#{k}' value."
          end
        end
        if errors.each{|e| ui.error(e)}.any?
          exit 1
        end
      end
    end
  end
end


