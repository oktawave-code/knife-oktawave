#
# Oktawave::OktawaveClient - a wrapper around SOAP calls to Oktawave API
#

require 'rubygems'
gem 'savon', '=0.9.5'
require 'savon'

module Oktawave

  # An exception thrown when a SOAP error occurs.
  # It will contain a more human-readable description of the error than standard
  # Savon::SOAP::Fault (if the API provides one)
  
  class OktawaveApiException < StandardError
  end

  # An Oktawave API client.
  # It contains generic SOAP call methods (call, soap_client) as well as wrappers around commonly
  # used calls (login, oci_get, ...) and utilities to manage the parsed SOAP responses (dive2*).

  class OktawaveClient

    def initialize(username, password, debug = false)
      @username = username
      @password = password
      @debug = debug
      @client_cache = {}
      @oci_classes = nil
    end

    # A helper to dive down a nested data structure (hash or array)
    # Meant for use with parsed SOAP responses.
    # Params:
    # +hash+:: The nested structure we want to dive into
    # +path+:: An array of keys to descend (can be integers if we're diving into an array)
    # +default+:: The default value returned if the path doesn't exist in the structure
    def dive(hash, path, default = nil)
      for key in path
        return default if hash.nil?
        if hash.is_a? Array
          hash = hash[key.to_i]
        else
          hash = hash[key]
        end
      end
      return hash.nil? ? default : hash
    end

    # A helper that dives into a nested data structure and makes sure that the
    # returned value is an array.
    # Used primarily to fix problems with inconsistent SOAP response parsing
    # (not as much a problem with Savon as it is with SOAP - single-element
    # arrays are not parsed as arrays but as the one element they contain).
    # Takes the same arguments as dive.
    def dive2arr(hash, path, default = [])
      res = dive(hash, path, default)
      return res if res.is_a? Array
      return [res]
    end

    # Helper method to dive into a dictionary data structure, retrieving the
    # English translation of a dictionary item (if available)
    def dive2name(hash, key = :dictionary_item_name, default = nil)
      arr = dive2arr(hash, [(key.to_s + 's').to_sym, key])
      if arr.length == 0
        return default
      end
      for item in arr
        if item.is_a? Hash and item[:language_dict_id] and item[:language_dict_id] == 2
          return item
        end
      end
      return arr[0]
    end

    # Returns a Savon::Client object for use with a SOAP method.
    # Configures global Savon settings for use with this method.
    # Maintains a per-method client cache to avoid downloading and parsing WSDL files
    # multiple times (a local WSDL cache is a planned feature).
    # Params:
    # +service+:: The name of the webservice ("Common" and "Clients" are supported)
    # +method_name+:: The method name, such as "LogonUser".
    def soap_client(service, method_name)
      @client_cache[service] ||= {}
      d = @debug
      Savon.configure do |config|
        config.soap_header = {
          "a:Action" => "http://K2.CloudsFactory/I#{service}/#{method_name}",
          "a:To" => "https://adamm.cloud.local:450/#{service}Service.svc"
        }
        config.soap_version = 2
        config.env_namespace = "ns0"
        config.log = d
        HTTPI.log = d
      end
      u = @username
      p = @password
      @client_cache[service][method_name] ||= Savon::Client.new do
        wsdl.document = "https://api.oktawave.com/#{service}Service.svc?wsdl"
        http.auth.basic("API\\#{u}", p)
        http.headers["SOAPAction"] = "http://K2.CloudsFactory/I#{service}/#{method_name}"
        http.headers["Content-Type"] = 'application/soap+xml; charset=utf-8'
      end
      return @client_cache[service][method_name]
    end

    # Performs an API login (if necessary) and returns the client ID.
    def cid
      self.login
      @client_id
    end

    # Returns a Savon::Client for CommonService
    def common_client(method_name = 'LogonUser')
      self.soap_client('Common', method_name)
    end

    # Returns a Savon::Client for ClientsService
    def clients_client(method_name)
      self.soap_client('Clients', method_name)
    end

    # Performs a SOAP method call and returns the result.
    # Params:
    # +method+:: Method name, as processed by Savon ('logon_user' for LogonUser method)
    # +arg+:: The method arguments, as a hashref. See Savon documentation for details.
    # +options+:: A hash with extra options. Supported options:
    #   * +:client+:: The webservice to use ("Clients" or "Common", default is Clients")
    #   * +:no_auto_dive+:: Return the whole response (by default it automatically dives into the main and only top-level element)
    # SOAP Faults will make it raise an OktawaveApiException.
    # Returns a parsed API response (to_hash called on Savon response)
    def soap_call(method, arg, options = {})
      self.login
      soap_method = method.split('_').map {|m| m.capitalize}.join('');
      client = options[:client] || 'Clients'
      begin
        response = self.soap_client(client, soap_method).request :wsdl, method.to_sym do
          soap.body = arg
          soap.namespaces["xmlns:a"] = "http://www.w3.org/2005/08/addressing"
          soap.namespaces["xmlns:env"] = "http://www.w3.org/2003/05/soap-envelope"
          soap.namespaces["xmlns:ins0"] ="http://schemas.datacontract.org/2004/07/K2.CloudsFactory.Common.Models"
        end
      rescue Savon::SOAP::Fault => e
        fault = e.to_hash
        msg = "Oktawave API reported error: #{dive(fault, [:fault, :code, :value], '')} - #{dive(fault, [:fault, :reason, :text], 'Unknown error')}"
        details = dive2arr(fault, [:fault, :detail])
        if details.length > 0
          for dd in details
            dd ||= {}
            dd.each do |key, d|
              msg += "\n#{dive(d, [:error_code], '-')} - #{dive(d, [:error_msg], 'unknown')}"
            end
          end
        end
        raise OktawaveApiException.new(msg)
      end
      full_res = response.to_hash
      unless options[:no_auto_dive]
        return dive(full_res, [(method.to_s + '_response').to_sym, (method.to_s + '_result').to_sym], {})
      end
      full_res
    end

    # Perform an API login and store the client id in @client_id.
    # Login is skipped if @client_id is already set.
    def login
      return if @client_id
      client = self.common_client
      u = @username
      p = @password
      result = client.request :wsdl, :logon_user do
        soap.body = {
          :user => u,
          :password => p,
          :ipAddress => "127.0.0.1",
          :userAgent => 'Savon',
        }
        soap.namespaces["xmlns:a"] = "http://www.w3.org/2005/08/addressing"
        soap.namespaces["xmlns:env"] = "http://www.w3.org/2003/05/soap-envelope"
      end 
      @login_response = result.to_hash
      @client_id = dive(@login_response, [:logon_user_response, :logon_user_result, :_x003_c_client_x003_e_k__backing_field, :client_id])
      raise "Login failed" unless @client_id
    end

    # Tries to fetch the access (SSH) password to an OCI from the logs.
    # Returns nil if the password is not found in the logs.
    def oci_password(oci_id)
      raw_res = self.soap_call('get_virtual_machine_histories', {
        'searchParams' => {
          'ins0:PageSize' => 100,
          'ins0:VirtualMachineId' => oci_id,
        },
        'clientId' => self.cid
      })
      ops = dive2arr(raw_res, [:_results, :virtual_machine_history])
      for op in ops
        type = dive2name(op[:operation_type])[:dictionary_item_id].to_i
        if type == 247
          return dive(op, [:parameters, :virtual_machine_history_parameter, :value])
        end
      end
      return nil
    end

    # Returns a list of OCI
    def oci_list
      raw_res = self.soap_call('get_virtual_machines', {
        'searchParams' => {'ins0:ClientId' => self.cid}
      })
      dive2arr(raw_res, [:_results, :virtual_machine_view])
    end

    # Returns information about an instance
    def oci_get(id)
      raw_res = self.soap_call('get_virtual_machine_by_id', {
        'virtualMachineId' => id,
        'clientId' => self.cid
      })
    end

    # Returns an OCI's IPv4 address
    def oci_ip(oci)
      addrs = dive2arr(oci, [:i_ps, :virtual_machine_ip]).select {|a| a[:address] =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/}
      addrs[0][:address]
    end

    # Deletes an OCI
    def oci_delete(id)
      self.soap_call('delete_virtual_machine', {
        'virtualMachineId' => id,
        'clientId' => self.cid
      })
    end

    # Powers an OCI on
    def oci_power_on(id)
      self.soap_call('turn_on_virtual_machine', {
        'virtualMachineId' => id,
        'clientId' => self.cid
      })
    end

    # Powers an OCI off
    def oci_power_off(id)
      self.soap_call('turnoff_virtual_machine', {
        'virtualMachineId' => id,
        'clientId' => self.cid
      })
    end

    # Restarts an OCI
    def oci_restart(id)
      self.soap_call('restart_virtual_machine', {
        'virtualMachineId' => id,
        'clientId' => self.cid
      })
    end

    def _templates_list_item(callback, depth, cat)
      callback.call(:category, depth, cat)
      raw_res = self.soap_call('get_templates_by_category', {
        'categoryId' => dive(cat, [:template_category_id]),
        'categorySystemId' => nil,
        'type' => nil,
        'clientId' => self.cid
      }, {:client => 'Common'})
      templates = dive2arr(raw_res, [:template_view])
      if templates.length > 0
        for t in templates
          callback.call(:template, depth + 1, t)
        end
      else
        callback.call(:no_templates, depth + 1, nil)
      end
      subcats = dive2arr(cat, [:category_children, :template_category])
      if (subcats.length > 0)
        for sc in subcats
          self._templates_list_item(callback, depth + 1, sc)
        end
      else
        callback.call(:no_subcategories, depth + 1, nil)
      end
      callback.call(:end_category, depth, nil)
    end

    # Fetches an list of OCI templates.
    def templates_list(callback)
      raw_res = self.soap_call('get_template_categories', {
        'ClientId' => self.cid
      }, {:client => 'Common'})
      tcs = dive2arr(raw_res, [:template_category])
      for tc in tcs
        self._templates_list_item(callback, 0, tc)
      end
    end

    # Creates an OCI.
    # Params:
    # +template_id+:: The ID of an OCI template
    # +name+:: The name of the new OCI
    # +oci_class_id+:: The ID of the OCI class
    # +autoscaler+:: The autoscaler setting ("on", "off" or "notify")
    def oci_create(template_id, name, oci_class_id = nil, autoscaler = 'on')
      autoscaler ||= 'on'
      autoscaler_id = {:off => 187, :on => 188, :notify => 235}[autoscaler.to_sym]
      raw_res = self.soap_call('create_virtual_machine', {
        'templateId' => template_id,
        'disks' => nil,
        'additionalDisks' => nil,
        'machineName' => name,
        'selectedClass' => oci_class_id,
        'selectedContainer' => nil,
        'selectedConnectionType' => 37,
        'selectedPaymentMethod' => 33,
        'clientId' => self.cid,
        'providervAppClientId' => nil,
        'vAppType' => 'Machine',
        'databaseTypeId' => nil,
        'clientVmParameter' => nil,
        'autoScalingTypeId' => autoscaler_id,
      })
    end

    # Returns available OCI classes
    def _load_oci_classes
      arr = dive2arr((self.soap_call('get_dictionary_items', {'dictionaryId' => 12}, {:client => 'Common'}) || []), [:dictionary_item])
      @oci_classes = arr.map {|c| [
        c[:dictionary_item_id].to_i, dive2name(c)[:item_name]
      ]}
    end

    # Returns OCI class id by class name (such as "Large")
    def oci_class_id(name)
      self._load_oci_classes
      for c in @oci_classes
        return c[0] if c[1] == name
      end
      raise "Incorrect OCI class (available: #{@oci_classes.map {|c| c[1]}.join(', ')})"
    end

    # Returns running operations history
    def running_jobs(period = 60)
      raw_res = self.soap_call('get_asynchronous_operations', {
        'clientId' => self.cid,
        'period' => period
      }, {:client => 'Common'})
      dive2arr(raw_res, [:asynchronous_operation_item])
    end

    def to_s
      "<<Oktawave client for user #{@username}>>";
    end

  end # class OktawaveClient

end # module Oktawave
