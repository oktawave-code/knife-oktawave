require 'chef/knife/oktawave_base'

class Chef
  class Knife
    class OktawaveOciShow < Knife
      include OktawaveBase
      banner 'knife oktawave oci show ID (options)'
      def run
        validate!
        if name_args.length < 1
          show_usage
          ui.fatal('You must specify the OCI ID (try "knife oktawave oci list")')
          exit 1
        end
        oci = api.oci_get(name_args[0])
        base = [
          'ID',
          'Name',
          'Class',
          'Status',
          'System category',
          'Autoscaling',
          'Connection',
          'CPU (used / available)',
          'Memory (used / available)',
          'IOPS',
          'Monitoring',
          'Payment type',
        ].map {|x| ui.color(x, :bold)}
        base << oci[:virtual_machine_id]
        base << oci[:virtual_machine_name]
        base << api.dive2name(oci[:vm_class])[:item_name]
        base << api.dive2name(oci[:status])[:item_name]
        base << api.dive2name(oci[:system_category])[:item_name]
        base << api.dive2name(oci[:auto_scaling_type])[:item_name]
        base << api.dive2name(oci[:connection_type])[:item_name]
        base << oci[:cpu_mhz_usage] + ' MHz / ' + oci[:cpu_mhz] + ' MHz' 
        base << oci[:ram_mb_usage] + ' MB / ' + oci[:ram_mb] + ' MB' 
        base << oci[:iops_usage]
        base << api.dive2name(oci[:monit_status])[:item_name]
        base << api.dive2name(oci[:payment_type])[:item_name]
        puts ui.list(base, :columns_down, 2)

        # Disks table
        puts "\nDisks\n"
        disks = [
          'ID', 'Name', 'Size', 'Tier', 'Primary?', 'Shared?'
        ].map {|x| ui.color(x, :bold)};
        ddata = api.dive2arr(oci, [:disk_drives, :virtual_machine_hdd])
        for d in ddata
          disks << d[:client_hdd][:client_hdd_id]
          disks << d[:client_hdd][:hdd_name]
          disks << d[:client_hdd][:capacity_gb] + ' GB'
          disks << api.dive2name(d[:client_hdd][:hdd_standard])[:item_name]
          disks << (d[:is_primary] ? 'Yes' : 'No')
          disks << (d[:client_hdd][:is_shared] ? 'Yes' : 'No')
        end
        puts ui.list(disks, :columns_across, 6)

        # IP addresses table
        puts "\nIP addresses\n"
        ips = [
          'IPv4 address', 'IPv6 address', 'DHCP branch', 'Gateway', 'Status', 'Type', 'MAC address'
        ].map {|x| ui.color(x, :bold)};
        idata = api.dive2arr(oci, [:i_ps, :virtual_machine_ip])
        for i in idata
          ips << i[:address]
          ips << i[:address_v6]
          ips << i[:dhcp_branch]
          ips << i[:gateway]
          ips << api.dive2name(i[:ip_status])[:item_name]
          ips << api.dive2name(i[:ip_type])[:item_name]
          ips << i[:mac_address]
        end
        puts ui.list(ips, :columns_across, 7)
      end
    end
  end
end
