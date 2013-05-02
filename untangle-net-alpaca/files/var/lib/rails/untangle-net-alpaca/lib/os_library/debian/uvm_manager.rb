# $HeadURL$

class OSLibrary::Debian::UvmManager < OSLibrary::UvmManager
  ## Review : Many if not all of the generated iptables scripts contain zero variables,
  ## and don't actually need to be generated on the fly.

  include Singleton

  IPTablesCommand = OSLibrary::Debian::PacketFilterManager::IPTablesCommand
  
  Chain = OSLibrary::Debian::PacketFilterManager::Chain

  ## uvm subscription file
  UvmSubscriptionFile = "#{OSLibrary::Debian::PacketFilterManager::ConfigDirectory}/800-uvm"

  ## list of rules for the UVM (before the firewall (those rules should override these rules)).
  UvmServicesFile = "#{OSLibrary::Debian::PacketFilterManager::ConfigDirectory}/475-uvm-services"

  ## list of rules for the UVM (after the firewall (used when the user wants to override these rules)).
  UvmServicesPostFile = "#{OSLibrary::Debian::PacketFilterManager::ConfigDirectory}/675-uvm-services"

  ## list of rules for openvpn
  UvmOpenVPNFile = "#{OSLibrary::Debian::PacketFilterManager::ConfigDirectory}/475-openvpn-pf"

  ## file to write out the network config
  UvmNetworkConfigFile = "/etc/untangle-net-alpaca/netConfig.js"
  
  ## Function that contains all of the subscription / bypass rules
  BypassRules = "bypass_rules"

  ## Script to tell the UVM that the configuration has changed.
  UvmUpdateConfiguration = "/usr/share/untangle-net-alpaca/scripts/uvm/uvm-refresh-network-config"

  def register_hooks
    os["packet_filter_manager"].register_hook( 100, "uvm_manager", "write_files", :hook_write_files )
    os["network_manager"].register_hook( 100, "uvm_manager", "write_files", :hook_write_files )

    ## Register with the hostname manager to update when there are
    ## changes to the hostname
    os["hostname_manager"].register_hook( 1000, "uvm_manager", "commit", :hook_update_configuration )
    os["dns_server_manager"].register_hook( 1000, "uvm_manager", "commit", :hook_update_configuration )
  end

  ## Write out the files to load all of the iptables rules necessary to queue traffic.
  def hook_write_files
    ## These are all of the rules that are used to vector traffic to the UVM.
    write_subscription_script
    write_network_configuration_file

    ## These are all of the rules to filter / accept traffic to the various services
    ## the UVM provides (80, 443, etc)
    write_packet_filter_script
    write_openvpn_script
  end

  ## A helper function for the packet filter manager.
  def handle_custom_rule( rule )
    return nil
  end

  ## Tell the UVM that there has been a change in the alpaca settings.  This is only used when something
  ## Changes but doesn't call the network manager.
  def hook_update_configuration
    write_network_configuration_file
    run_command( UvmUpdateConfiguration )
  end

  def UID()
    key = "0000-0000-0000-0000"
    begin
        file = File.new("/usr/share/untangle/conf/uid", "r")
        key = file.gets
        key.strip!
    rescue => err
    end
    return key 
  end
  
  private
  
  def write_subscription_script
    text = header
    
    text += subscription_rules
    
    text += <<EOF
HELPER_SCRIPT="/usr/share/untangle-net-alpaca/scripts/uvm/uvm-helper-script"

if [ ! -f ${HELPER_SCRIPT} ]; then
  echo "[`date`] The script ${HELPER_SCRIPT} is not available"
  return 0
fi

. ${HELPER_SCRIPT}
set_proc_vars

if [ "`is_uvm_running`x" = "truex" ]; then
  echo "[`date`] The untangle-vm is running. Inserting queueing hooks and bypass rules..."
  uvm_iptables_rules
  
  ## Ignore any traffic that is on the utun interface
  #{IPTablesCommand} -t #{Chain::FirewallRules.table} -I #{Chain::FirewallRules} 1 -i ${TUN_DEV} -j RETURN -m comment --comment "Allow all traffic on utun interface"
  
  #{BypassRules}
  echo "[`date`] The untangle-vm is running. Inserting queueing hooks and bypass rules...done"

else
  echo "[`date`] The untangle-vm is not running. Doing nothing."
fi

return 0

EOF

    os["override_manager"].write_file( UvmSubscriptionFile, text, "\n" )    
  end

  def write_packet_filter_script( )
    text = header
    
    text += <<EOF
HELPER_SCRIPT="/usr/share/untangle-net-alpaca/scripts/uvm/uvm-helper-script"

if [ ! -f ${HELPER_SCRIPT} ]; then
  echo "[`date`] The script ${HELPER_SCRIPT} is not available"
  return 0
fi

. ${HELPER_SCRIPT}
set_proc_vars

if [ "`is_uvm_running`x" = "truex" ]; then
  echo "[`date`] The untangle-vm is running, inserting service rules."
  uvm_insert_non_wan_HTTP_rules
  uvm_insert_wan_HTTPS_rules
  uvm_insert_non_wan_HTTPS_rules
else
  echo "[`date`] The untangle-vm is currently not running."
fi

return 0
EOF

    uvm_settings = UvmSettings.find( :first )
    ## Default to evaluating the rules before the redirects.
    if ( uvm_settings.nil? || uvm_settings.override_redirects )
      os["override_manager"].write_file( UvmServicesFile, text, "\n" )    
      os["override_manager"].write_file( UvmServicesPostFile, header, "\n" )
    else
      os["override_manager"].write_file( UvmServicesFile, header, "\n" )    
      os["override_manager"].write_file( UvmServicesPostFile, text, "\n" )      
    end
  end

  def write_openvpn_script
    route_bridge_vpn_traffic = ""

    if Firewall.find( :first, :conditions => [ "system_id = ? and enabled='t'", "route-bridge-vpn-37ce4160" ] )
      route_bridge_vpn_traffic = "true"
    end

    
    text = header
    ## REVIEW This presently doesn't mark openvpn traffic as local.
    ## REVIEW 0x80 is a magic number.
    text  += <<EOF
HELPER_SCRIPT="/usr/share/untangle-net-alpaca/scripts/uvm/uvm-helper-script"

if [ ! -f ${HELPER_SCRIPT} ]; then
  echo "[`date`] The script ${HELPER_SCRIPT} is not available"
  return 0
fi

. ${HELPER_SCRIPT}
set_proc_vars

if [ "`is_uvm_running`x" != "truex" ]; then 
  echo "[`date`] The untangle-vm is running, not inserting rules for openvpn"
  return 0
fi

if [ "`pidof openvpn`x" = "x" ]; then
  echo "[`date`] OpenVPN is not running, not inserting rules for openvpn"
  return 0
fi    

## This is the openvpn mark rule
#{IPTablesCommand} #{Chain::MarkSrcInterface.args} -i tun0 -j MARK --set-mark #{0xfa}/#{0xff} -m comment --comment "Set OpenVPN source interface mark on traffic coming out of tun0"
#{IPTablesCommand} #{Chain::MarkDstInterface.args} -o tun0 -j MARK --set-mark #{0xfa << 8}/#{0xff00} -m comment --comment "Set OpenVPN destination interface mark on traffic going to tun0"
#{IPTablesCommand} #{Chain::MarkSrcInterface.args} -i tun0 -m conntrack --ctstate NEW -j CONNMARK --set-mark #{0xfa}/#{0xff} -m comment --comment "Set OpenVPN source interface mark on session coming out of tun0"
#{IPTablesCommand} #{Chain::MarkDstInterface.args} -o tun0 -m conntrack --ctstate NEW -j CONNMARK --set-mark #{0xfa << 8}/#{0xff00} -m comment --comment "Set OpenVPN destination interface mark on session going to tun0"

## The following two rules are marked XXX because they seem backwards
## The rule reads if the packet is in the original direction and the connmark says the source interface of the session is OpenVPN then the destination of the packet should be set to OpenVPN.
## My intuition says that the rule should read --ctdir REPLY, however it only works as intended with --ctdir ORIGINAL despite my understanding of the man page.
#{IPTablesCommand} #{Chain::MarkInterface.args} -m conntrack --ctdir ORIGINAL -m connmark --mark #{0xfa}/#{0xff} -j MARK --set-mark #{0xfa << 8}/#{0xff00} -m comment --comment "Set source interface mark based ot session connmark and direction (XXX)"
#{IPTablesCommand} #{Chain::MarkInterface.args} -m conntrack --ctdir ORIGINAL -m connmark --mark #{0xfa << 8}/#{0xff00} -j MARK --set-mark #{0xfa}/#{0xff} -m comment --comment "Set destination interface mark based ot session connmark and direction (XXX)"

## Accept traffic from the VPN
#{IPTablesCommand} #{Chain::FirewallRules.args} -i tun0 -j RETURN -m comment --comment "Allow traffic from the OpenVPN interface"

if [ -n "#{route_bridge_vpn_traffic}" ]; then
  uvm_openvpn_ebtables_rules || true
fi

true

EOF

    os["override_manager"].write_file( UvmOpenVPNFile, text, "\n" )
  end


  def append_attribute( text, attribute_name, value, indention, comma=true )

    if (value.nil? or value == "")
      return text;
    end

    text += ("    "*indention) + "\"" + "#{attribute_name}" + "\"" + ": " + "\"" + "#{value}" + "\""
    if comma:
      text += ","
    end
    text += "\n"

    return text;

  end


  ## This writes a file that indicates to the UVM the order
  ## of the interfaces
  def write_network_configuration_file
    ## Create an interface map
    interfaces = {}
    Interface.find( :all ).each { |interface| interfaces[interface.index] = interface }
    
    settings = UvmSettings.find( :first )
    settings = UvmSettings.new if settings.nil?
    
    intf_order = UvmHelper::DefaultOrder 
    intf_order = intf_order.split( "," ).map { |idx| idx.to_i }.delete_if { |idx| idx == 0 }
    wan_interfaces = []

    ## Go through and delete the interfaces that are in the map.
    intf_order.each do |idx|
      interface = interfaces[idx]
      next if interface.nil?
      
      ## Delete the item at index for the second loop
      interfaces.delete( idx )
      
      ## Append the index
      wan_interfaces << idx if ( interface.wan == true )
    end

    hostname_settings = HostnameSettings.find( :first )
    dns_settings = DnsServerSettings.find( :first )
    dhcp_settings = DhcpServerSettings.find( :first )

    netConfigFileText = ""
    netConfigFileText += "{\n"
    netConfigFileText = append_attribute( netConfigFileText, "javaClass", "com.untangle.uvm.networking.NetworkConfiguration", 1)

    if !hostname_settings.nil?
      netConfigFileText = append_attribute( netConfigFileText, "hostname", hostname_settings.hostname, 1)
    end
    if dns_settings.nil?
      netConfigFileText = append_attribute( netConfigFileText, "dnsServerEnabled", "false", 1)
    else 
      netConfigFileText = append_attribute( netConfigFileText, "dnsServerEnabled", dns_settings.enabled, 1)
      netConfigFileText = append_attribute( netConfigFileText, "dnsLocalDomain", dns_settings.suffix, 1)
    end
    if dhcp_settings.nil?
      netConfigFileText = append_attribute( netConfigFileText, "dhcpServerEnabled", "false", 1)
    else
      netConfigFileText = append_attribute( netConfigFileText, "dhcpServerEnabled", dhcp_settings.enabled, 1)
    end

    netConfigFileText += "    \"interfaceList\": {\n" 
    netConfigFileText = append_attribute( netConfigFileText, "javaClass", "java.util.LinkedList", 2)
    netConfigFileText += "        \"list\": [\n"

    first = true
    Interface.find( :all ).each { |interface| 
      if (first) 
        netConfigFileText += "               {\n"
        first = false
      else
        netConfigFileText += "              ,{\n"
      end
      netConfigFileText = append_attribute( netConfigFileText, "interfaceId", interface.index, 3)
      netConfigFileText = append_attribute( netConfigFileText, "systemName", interface.os_name, 3)
      netConfigFileText = append_attribute( netConfigFileText, "name", interface.name, 3)
      netConfigFileText = append_attribute( netConfigFileText, "configType", interface.config_type, 3)
      netConfigFileText = append_attribute( netConfigFileText, "WAN", interface.wan, 3)
      netConfigFileText = append_attribute( netConfigFileText, "macAddress", interface.mac_address, 3)
      netConfigFileText = append_attribute( netConfigFileText, "vendor", interface.vendor, 3)

      if (interface.config_type == "static")
        intfStatic = IntfStatic.find( :first, :conditions => [ "interface_id = ?", interface.id ] )

        if !intfStatic.nil?
          if !intfStatic.ip_networks.nil? 
            intfAddr = intfStatic.ip_networks[0]
            if !intfAddr.nil? and !intfAddr.ip.nil? and !intfAddr.netmask.nil?
              netConfigFileText = append_attribute( netConfigFileText, "primaryAddressStr", "#{intfAddr.ip}/#{intfAddr.netmask}", 3)
            end
          end

          if (interface.wan) 
            netConfigFileText = append_attribute( netConfigFileText, "gatewayStr", intfStatic.default_gateway, 3)
            netConfigFileText = append_attribute( netConfigFileText, "dns1Str", intfStatic.dns_1, 3)
            netConfigFileText = append_attribute( netConfigFileText, "dns2Str", intfStatic.dns_2, 3)
            netConfigFileText = append_attribute( netConfigFileText, "mtu", intfStatic.mtu, 3)
          end
        end
      end

      if (interface.config_type == "dynamic")
        intfDynamic = IntfDynamic.find( :first, :conditions => [ "interface_id = ?", interface.id ] )

        dhcp_status = os["dhcp_manager"].get_dhcp_status( interface )
        if !dhcp_status.nil?
          if !dhcp_status.ip.nil? and !dhcp_status.netmask.nil?
            netConfigFileText = append_attribute( netConfigFileText, "primaryAddressStr", "#{dhcp_status.ip}/#{dhcp_status.netmask}", 3)
          end
          
          netConfigFileText = append_attribute( netConfigFileText, "gatewayStr", dhcp_status.default_gateway, 3)
          netConfigFileText = append_attribute( netConfigFileText, "dns1Str", dhcp_status.dns_1, 3)
          netConfigFileText = append_attribute( netConfigFileText, "dns2Str", dhcp_status.dns_2, 3)
        end

        if !intfDynamic.nil?
          netConfigFileText = append_attribute( netConfigFileText, "overrideIPAddress" , intfDynamic.ip, 3)
          netConfigFileText = append_attribute( netConfigFileText, "overrideNetmask" , intfDynamic.netmask, 3)

          if (interface.wan) 
            netConfigFileText = append_attribute( netConfigFileText, "overrideGateway" , intfDynamic.default_gateway, 3)
            netConfigFileText = append_attribute( netConfigFileText, "overrideDns1" , intfDynamic.dns_1, 3)
            netConfigFileText = append_attribute( netConfigFileText, "overrideDns2" , intfDynamic.dns_2, 3)
          end
        end
      end

      if (interface.config_type == "bridge")
        intfBridge = IntfBridge.find( :first, :conditions => [ "interface_id = ?", interface.id ] )
        if !intfBridge.nil?
          bridgedToIntf = Interface.find( :first, :conditions => [ "id = ?", intfBridge.bridge_interface_id ] )
          if (!bridgedToIntf.nil?)
            netConfigFileText = append_attribute( netConfigFileText, "bridgedTo" , bridgedToIntf.name, 3)
          end
        end
      end

      if (interface.config_type == "pppoe")
        #pppoe username
        #pppoe password
      end

      # don't put a comma on the last line
      netConfigFileText = append_attribute( netConfigFileText, "javaClass", "com.untangle.uvm.networking.InterfaceConfiguration", 3, false)
      netConfigFileText += "        }\n"
    }

    # manually add the VPN interface
    netConfigFileText += "              ,{\n"
    netConfigFileText = append_attribute( netConfigFileText, "interfaceId", "#{UvmHelper::OpenVpnIndex}", 3)
    netConfigFileText = append_attribute( netConfigFileText, "systemName", "tun0", 3)
    netConfigFileText = append_attribute( netConfigFileText, "name", "OpenVPN", 3)
    netConfigFileText = append_attribute( netConfigFileText, "WAN", "false", 3)
    netConfigFileText = append_attribute( netConfigFileText, "javaClass", "com.untangle.uvm.networking.InterfaceConfiguration", 3, false)
    netConfigFileText += "        }\n"


    netConfigFileText += "         ]\n" 
    netConfigFileText += "    }\n" 
    netConfigFileText += "}\n" 
    netConfigFileText += "\n" 

    os["override_manager"].write_file( UvmNetworkConfigFile, netConfigFileText )

    return
  end

  def subscription_rules
    text = <<EOF
#{BypassRules}() {
  local t_rule
EOF

    ## Add the user rules
    rules = Subscription.find( :all, :conditions => [ "system_id IS NULL AND enabled='t'" ] )
    ## Add the system rules
    rules += Subscription.find( :all, :conditions => [ "system_id IS NOT NULL AND enabled='t'" ] )
    
    rules.each do |rule|
      begin
        next text << handle_custom_rule( rule ) if rule.is_custom

        filters, chain = OSLibrary::Debian::Filter::Factory.instance.filter( rule.filter )
        
        target = ( rule.subscribe ) ? "-j RETURN" : "-g #{Chain::BypassMark}"

        filters.each do |filter|
          break if filter.strip.empty?
          text << "#{IPTablesCommand} #{Chain::BypassRules.args} #{filter} #{target} -m comment --comment \"Bypass Rule #{rule.id}\"\n"
        end
        
      rescue
        logger.warn( "The subscription '#{rule.id}' '#{rule.filter}' could not be parsed: #{$!}" )
      end
    end
    
    text + "\n}\n"
  end

  ## Review: This should be a global function
  def header
    <<EOF
#!/bin/dash

## #{Time.new}
## Auto Generated by the Untangle Net Alpaca
## If you modify this file manually, your changes
## may be overriden

EOF
  end

end