import os
import sys
import subprocess
import datetime

# TODO PPPoE
# TODO inet6

# This class is responsible for writing /etc/network/interfaces
# based on the settings object passed from sync-settings.py
class InterfacesManager:
    defaultFilename = "/etc/network/interfaces"
    interfacesFilename = defaultFilename
    interfacesFile = None

    def write_interface( self, interface_settings, interfaces ):
        if interface_settings['symbolicDev'] == None:
            print "ERROR: Missisg symbolic dev!"
            return
        if interface_settings['interfaceId'] == None:
            print "ERROR: Missisg interface ID!"
            return
        if interface_settings['name'] == None:
            print "ERROR: Missisg interface name!"
            return

        isV4Auto = False
        if interface_settings['v4ConfigType'] == 'auto':
            isV4Auto = True

        # find interfaces bridged to this interface
        isBridge = False
        bridgedInterfaces = []
        for intf in interfaces:
            if intf['config'] == 'bridged' and intf['bridgedTo'] == interface_settings['interfaceId']:
                bridgedInterfaces.append(str(intf['symbolicDev']))
        if len(bridgedInterfaces) > 0:
            isBridge = True

        self.interfacesFile.write("## Interface %i (%s)\n" % (interface_settings['interfaceId'], interface_settings['name']) )
        self.interfacesFile.write("auto %s\n" % interface_settings['symbolicDev'])
        self.interfacesFile.write("iface %s inet %s\n" % (interface_settings['symbolicDev'], ("auto" if isV4Auto else "manual")) )
        self.interfacesFile.write("\tnetd_interface_index %i\n" % interface_settings['interfaceId'])
        if not isV4Auto:
            self.interfacesFile.write("\tnetd_v4_address %s\n" % interface_settings['v4StaticAddress'])
            self.interfacesFile.write("\tnetd_v4_netmask %s\n" % interface_settings['v4StaticNetmask'])
            self.interfacesFile.write("\tnetd_v4_gateway %s\n" % interface_settings['v4StaticGateway'])
        if isBridge:
            self.interfacesFile.write("\tnetd_bridge_mtu %i\n" % 1500) #XXX
            self.interfacesFile.write("\tnetd_bridge_ageing %i\n" % 900) #XXX
            self.interfacesFile.write("\tnetd_bridge_ports %s\n" % " ".join(bridgedInterfaces))
            
        self.interfacesFile.write("\n\n");

    def sync_settings( self, settings, prefix="", verbosity=0 ):
        
        self.interfacesFilename = prefix + self.defaultFilename
        self.interfacesDir = os.path.dirname( self.interfacesFilename )
        if not os.path.exists( self.interfacesDir ):
            os.makedirs( self.interfacesDir )

        self.interfacesFile = open( self.interfacesFilename, "w+" )
        self.interfacesFile.write("## Auto Generated on %s\n" % datetime.datetime.now());
        self.interfacesFile.write("## DO NOT EDIT. Changes will be overwritten\n");
        self.interfacesFile.write("\n\n");

        self.interfacesFile.write("## XXX what is this? why? add comment here\n");
        self.interfacesFile.write("auto cleanup\n");
        self.interfacesFile.write("iface cleanup inet manual\n");
        self.interfacesFile.write("\n\n");

        if settings != None and settings['interfaces'] != None and settings['interfaces']['list'] != None:
            for interface_settings in settings['interfaces']['list']:
                # only write 'addressed' interfaces
                if interface_settings['config'] != 'addressed':
                    continue
                self.write_interface( interface_settings, settings['interfaces']['list'] )

        self.interfacesFile.write("## XXX what is this? why? add comment here\n");
        self.interfacesFile.write("auto update\n");
        self.interfacesFile.write("iface update inet manual\n");
        self.interfacesFile.write("\n\n");
        
        self.interfacesFile.flush()
        self.interfacesFile.close()

        if verbosity > 1:
            print "Writing %s" % interfacesFilename

        

        
