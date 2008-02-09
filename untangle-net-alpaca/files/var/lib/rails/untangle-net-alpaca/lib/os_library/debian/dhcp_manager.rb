#
# $HeadURL$
# Copyright (c) 2007-2008 Untangle, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# AS-IS and WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE, TITLE, or
# NONINFRINGEMENT.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
#
class OSLibrary::Debian::DhcpManager < OSLibrary::DhcpManager
  include Singleton
  
  ConfigDir = "/etc/untangle-net-alpaca"
  ConfigFileBase = "dhcp-overrides."

  OverrideIPAddress = "DHCP_IP_ADDRESS"
  OverrideNetmask = "DHCP_IP_NETMASK"
  OverrideGateway = "DHCP_GATEWAY"
  OverrideDnsServer = "DHCP_DNS_SERVERS"
  OverrideDomainName = "DHCP_DOMAIN_NAME"

  def register_hooks
    os["network_manager"].register_hook( -100, "dhcp_manager", "write_files", :hook_commit )
  end

  def get_dhcp_status( interface )
    config = interface.current_config

    ## Return an empty one
    return DhcpStatus.new if ( config.nil? || !config.is_a?( IntfDynamic ))
    
    ## Get the correct name
    name = interface.os_name
    name = OSLibrary::Debian::NetworkManager.bridge_name( interface ) if interface.is_bridge?

    ## Grab the current IP and Netmask    
    address, netmask = `ifconfig #{name} 2>/dev/null | awk '/^ *inet / { sub( "addr:", "", $2 ) ; sub( "Mask:", "", $4 ) ; print $2 " " $4 }'`.strip.split( " " )

    ## This is all that is needed for non-wan interfaces
    return DhcpStatus.new( address, netmask ) unless interface.wan

    ## Grab the default gateway
    default_gateway = `ip route show | awk ' /^default via.*#{name}/ { print $3 } '`.strip

    ## DNS Servers are only stored in the 
    dns_1, dns_2 = `awk '/^server=/ { sub( "server=", "" ); print }' /etc/dnsmasq.conf`.strip.split
    
    DhcpStatus.new( address, netmask, default_gateway, dns_1, dns_2 )
  end
  
  def hook_commit
    ## Delete all of the existing config files
    delete_config_files

    ## Write out all of the config files
    write_config_files
  end

  private
  ## Delete all of the config files, this guarantees there
  ## are no leftover configuration files when an interface goes from Dynamic -> Static
  def delete_config_files
    Dir.foreach( ConfigDir ) do |file_name|
      next if file_name.match( /^#{ConfigFileBase}/ ).nil?

      os["override_manager"].rm_file( "#{ConfigDir}/#{file_name}" )
    end
  end

  def write_config_files
    Interface.find( :all ).each do |interface|
      config = interface.current_config
      
      ## Ignore anything that is not dynamic
      next unless config.is_a?( IntfDynamic )
      
      ## Don't like this code living in multiple places
      name = interface.os_name
      name = OSLibrary::Debian::NetworkManager.bridge_name( interface ) if interface.is_bridge?
      
      cfg = []

      ## REVIEW how to handle search domain
      ## [ OverrideDomainName, [ config.dns_1, config.dns_2 ].join( " " ).strip ]]

      gateway, dns = "ignore", "ignore"
      if interface.wan
        ## Only set the DNS and Gateway for WAN interfaces.
        gateway = config.default_gateway
        dns = [ config.dns_1, config.dns_2 ].join( " " ).strip 
      end

      overrideManager = os["override_manager"]

      ## Review : should this ignore the entry, because it isn't actually under the control
      ## of the net-alpaca.
      unless overrideManager.writable?( OSLibrary::Debian::DnsServerManager::ResolvConfFile )
        ## Always ignore the DNS update if resolv.conf shouldn't be updated.
        dns = "ignore"
      end
      
      [[ OverrideIPAddress, config.ip ],
       [ OverrideNetmask, IPAddr.parse_netmask( config.netmask ).to_s ], 
       [ OverrideGateway, gateway ],
       [ OverrideDnsServer, dns ]].each do |var,val|
        next if ( ApplicationHelper.null?( val ))
        next if ( IPAddr.parse_ip( val ).nil? )
        
        cfg << "#{var}=\"#{val}\""
      end
      
      next if cfg.size == 0
      
      file_name = "#{ConfigDir}/#{ConfigFileBase}#{name}"

      os["override_manager"].write_file( file_name, header, "\n", cfg.join( "\n" ), "\n" )
    end
  end

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
