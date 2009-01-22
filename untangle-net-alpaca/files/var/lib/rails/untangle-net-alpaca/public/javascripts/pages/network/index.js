Ext.ns('Ung');
Ext.ns('Ung.Alpaca');
Ext.ns('Ung.Alpaca.Pages');
Ext.ns('Ung.Alpaca.Pages.Network');

if ( Ung.Alpaca.Glue.hasPageRenderer( "network", "index" )) {
    Ung.Alpaca.Util.stopLoading();
}

Ung.Alpaca.Pages.Network.Index = Ext.extend( Ung.Alpaca.PagePanel, {
    initComponent : function()
    {
        var items = [];

        items.push({
            xtype : 'button',
            text : this._( "Refresh Interfaces" ),
            handler : this.refreshInterfaces.createDelegate( this )
        });

        items.push({
            xtype : 'button',
            text : this._( "External Aliases" ),
            handler : this.externalAliases.createDelegate( this )
        });

        for ( var c = 0 ; c < this.settings.config_list.length ; c++ ) {
            var config = this.settings.config_list[c];
            var interfaceConfig = config["interface"];
            items.push({
                xtype : "label",
                html : String.format( this._( "{0} Interface" ), interfaceConfig["name"] )
            });

            if ( interfaceConfig["wan"] ) {
                items.push( this.buildWanPanel( c ));
            } else {
                items.push( this.buildStandardPanel( c ));
            }
        }

        Ext.apply( this, {
            defaults : {
                xtype : "fieldset"
            },
            items : items
        });
        
        Ung.Alpaca.Pages.Network.Index.superclass.initComponent.apply( this, arguments );
    },

    saveMethod : "/network/set_settings",
    
    buildWanPanel : function( i )
    {
        var staticPanel = {
            items : [{
                defaults : {
                    xtype : 'textfield'
                },
                items : [{
                    fieldLabel : "Address",
                    name : this.generateName( "config_list", i, "static.ip" )
                },{
                    xtype : "combo",
                    fieldLabel : "Netmask",
                    name : this.generateName( "config_list", i, "static.netmask" ),
                    store : Ung.Alpaca.Util.cidrData,
                    listWidth : 140,
                    width : 40,
                    triggerAction : "all",
                    mode : "local",
                    editable : false
                },{
                    fieldLabel : "Default Gateway",
                    name : this.generateName( "config_list", i, "static.default_gateway" )
                },{
                    fieldLabel : "Primary DNS Server",
                    name : this.generateName( "config_list", i, "static.dns_1" )
                },{
                    fieldLabel : "Secondary DNS Server",
                    name : this.generateName( "config_list", i, "static.dns_2" )
                }]
            }]
        };

        var dynamicPanel = {
            items : [{
                defaults : {
                    xtype : 'textfield',
                    readOnly : true
                },
                items : [{
                    fieldLabel : "Address",
                    name : "dhcp_status.ip"
                },{
                    fieldLabel : "Netmask",
                    name : "dhcp_status.netmask"
                },{
                    fieldLabel : "Default Gateway",
                    name : "dhcp_status.default_gateway"
                },{
                    fieldLabel : "Primary DNS Server",
                    name : "dhcp_status.dns_1"
                },{
                    fieldLabel : "Secondary DNS Server",
                    name :  "dhcp_status.dns_2"
                }]
            }]
        };

        var pppoePanel = {
            items : [{
                defaults : {
                    xtype : 'textfield'
                },
                items : [{
                    fieldLabel : "Username",
                    name : this.generateName( "config_list", i, "pppoe.username" )
                },{
                    fieldLabel : "Password",
                    name : this.generateName( "config_list", i, "pppoe.password" )
                },{
                    xtype : "checkbox",
                    fieldLabel : "User peer DNS",
                    name : this.generateName( "config_list", i, "pppoe.use_peer_dns" )
                },{
                    fieldLabel : "Primary DNS Server",
                    name : this.generateName( "config_list", i, "pppoe.dns_1" )
                },{
                    fieldLabel : "Secondary DNS Server",
                    name : this.generateName( "config_list", i, "pppoe.dns_2" )
                }]
            }]
        };

        var switchBlade = new Ext.Panel({
            layout : "card",
            activeItem : 0,
            border : false,
            defaults : {
                border : false,
                layout : 'form',
                xtype : 'panel',
                defaults : {
                    autoHeight : true,
                    xtype : 'fieldset'
                }
            },
            items : [ staticPanel, dynamicPanel, pppoePanel ]
        });

        var panel = new Ext.FormPanel({
            border : false,
            items : [{
                xtype : "fieldset",
                autoHeight : true,
                items : [{
                    xtype : "combo",
                    name : this.generateName( "config_list", i, "interface.config_type" ),
                    fieldLabel : "Config Type",
                    store : [ 'static', 'dynamic', 'pppoe' ],
                    switchBlade : switchBlade,
                    triggerAction : "all",
                    mode : "local",
                    editable : false,
                    listeners : {
                        "select" : {
                            fn : this.onSelectConfigType,
                            scope : this
                        }
                    }
                }],
            }, switchBlade ]
        });

        return panel;
    },

    buildStandardPanel : function( i )
    {
        var staticPanel = {
            items : [{
                defaults : {
                    xtype : 'textfield'
                },
                items : [{
                    fieldLabel : "Address",
                    name : this.generateName( "config_list", i, "static.ip" )
                },{
                    xtype : "combo",
                    fieldLabel : "Netmask",
                    name : this.generateName( "config_list", i, "static.netmask" ),
                    store : Ung.Alpaca.Util.cidrData,
                    listWidth : 140,
                    width : 40,
                    triggerAction : "all",
                    mode : "local",
                    editable : false
                }]
            }]
        };

        var bridgePanel = {
            items : [{
                items : [{
                    fieldLabel : "Bridge To",
                    xtype : "combo",
                    mode : "local",
                    triggerAction : "all",
                    editable : false,
                    listWidth : 160,
                    name : this.generateName( "config_list", i, "bridge" ),
                    store :  this.settings.config_list[i]["bridgeable_interfaces_v2"]
                }]
            }]
        };

        var configTypes = [ "static", "bridge" ];
        var configType = this.settings.config_list[i]["interface"]["config_type"];

        var switchBlade = new Ext.Panel({
            layout : "card",
            activeItem : this.getActiveItem( configType, configTypes ),
            border : false,
            defaults : {
                border : false,
                layout : 'form',
                xtype : 'panel',
                defaults : {
                    autoHeight : true,
                    xtype : 'fieldset'
                }
            },
            items : [ staticPanel, bridgePanel ]
        });

        var panel = new Ext.FormPanel({
            border : false,
            items : [{
                xtype : "fieldset",
                autoHeight : true,
                items : [{
                    xtype : "combo",
                    name : this.generateName( "config_list", i, "interface.config_type" ),
                    fieldLabel : "Config Type",
                    store : configTypes,
                    switchBlade : switchBlade,
                    triggerAction : "all",
                    editable : false,
                    listeners : {
                        "select" : {
                            fn : this.onSelectConfigType,
                            scope : this
                        }
                    }
                }],
            }, switchBlade ]
        });

        return panel;
    },

    refreshInterfaces : function()
    {
        Ext.MessageBox.wait( this._( "Refreshing Physical Interfaces", "Please wait" ));
        
        var handler = this.completeRefreshInterfaces.createDelegate( this );
        Ung.Alpaca.Util.executeRemoteFunction( "/interface/get_interface_list", handler );        
    },

    completeRefreshInterfaces : function( result, response, options )
    {
        icon = Ext.MessageBox.INFO;
        message = this._( "No new physical interfaces were detected." );

        var newInterfaces = result["new_interfaces"];
        var deletedInterfaces = result["deleted_interfaces"];
        
        if ( newInterfaces == null ) {
            newInterfaces = [] 
        }

        if ( deletedInterfaces == null ) {
            deletedInterfaces = [] 
        }
        
        if (( deletedInterfaces.length + newInterfaces.length ) > 0 ) {
            icon = Ext.MessageBox.INFO;
            message = [];
            var l = deletedInterfaces.length;
            if ( l > 0 ) {
                message.push( String.format( this.i18n.pluralise( this._( "One interface was removed." ),
                                                                  this._( "{0} interfaces were removed." ),
                                                                  l ),
                                             l ));
            }
            
            var l = newInterfaces.length;
            if ( l > 0 ) {
                message.push( String.format( this.i18n.pluralise( this._( "One interface was added." ),
                                                                  this._( "{0} interfaces were added." ),
                                                                  l ),
                                             l ));
            }
            
            message = message.join( "<br/>" );
        }
        
        Ext.MessageBox.show({
            title : this._( "Interface Status" ),
            msg : message,
            buttons : Ext.MessageBox.OK,
            icon : icon
        });
    },

    externalAliases : function()
    {
        application.switchToQueryPath( "/alpaca/network/e_aliases" );
    },

    generateName : function( prefix, i, suffix )
    {
        return prefix + "." + i + "." + suffix;
    },

    onSelectConfigType : function( combo, record, index )
    {
        combo.switchBlade.layout.setActiveItem( index );
    },

    getActiveItem : function( value, valueArray )
    {
        for ( var c = 0 ; c < valueArray.length ; c++ ) {
            if ( value == valueArray[c] ) return c;
        }

        return 0;
    }
});

Ung.Alpaca.Pages.Network.Index.settingsMethod = "/network/get_settings";
Ung.Alpaca.Glue.registerPageRenderer( "network", "index", Ung.Alpaca.Pages.Network.Index );

