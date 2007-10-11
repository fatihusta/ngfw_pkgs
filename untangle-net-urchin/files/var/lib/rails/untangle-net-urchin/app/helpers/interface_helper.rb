require "ipaddr"

module InterfaceHelper
  def InterfaceHelper.validateNetmask( errors, netmask )
    ## not an ip address.
    begin
      IPAddr.new( "1.2.3.4/#{netmask}" )
    rescue
      errors.add( "Invalid Netmask '#{netmask}'" )
    end
  end

  ## REVIEW :: These Strings need to be internationalized.
  class ConfigType
    STATIC="static"
    DYNAMIC="dynamic"
    BRIDGE="bridge"
  end

  ## Array of all of the available config types
  CONFIGTYPES = [ ConfigType::STATIC, ConfigType::DYNAMIC, ConfigType::BRIDGE ].freeze

  ## An array of the config types that you can bridge with
  BRIDGEABLE_CONFIGTYPES = [ ConfigType::STATIC, ConfigType::DYNAMIC ].freeze
end
