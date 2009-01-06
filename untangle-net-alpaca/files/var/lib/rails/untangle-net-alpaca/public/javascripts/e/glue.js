Ext.ns('Ung');
Ext.ns('Ung.Alpaca');

Ung.Alpaca.Glue = {
    // Map of all of the currently loaded pages.  Indexed with
    // buildPageKey( controller, page ) -> Ung.Alpaca.PagePanel child class.
    pages : {},
    
    /* This parses the path of the URL to determine the current page.
     * The URL looks like "/alpaca/#{controller}/#{page}?#{params}"
     * If <page> is not set, then it defaults to index.
     * If <controller> is not set, the it defaults to network.
     */
    buildQueryPath : function( base )
    {
        if (typeof( base ) != "string" ) {
            return base;
        }

        var a = base.split( "?" );
        var params = a[1];
        var path = a[0];

        path = path.replace( /\/+/g, "/" )
         a = path.split( "/" );
        var controller = a[2];
        var page = a[3];
        var pageID = parseInt( a[4] );
        
        if (( page == null ) || ( page.length == 0 )) page = "index";
        if (( controller == null ) || ( controller.length == 0 )) controller = "network";

        var requestedPage = { "controller" : controller, "page" : page };
        if ( pageID ) {
            requestedPage["pageID"] = pageID;
        }
        
        return requestedPage;
    },

    // Return true if this page already has a registered renderer.
    hasPageRenderer : function( controller, page )
    {
        return ( this.pages[this.buildPageKey( controller, page )] != null );
    },

    // Register a page renderer for a page.
    registerPageRenderer : function( controller, page, renderer )
    {
        this.pages[this.buildPageKey( controller, page )] = renderer;
    },

    // Get the page renderer for a page.
    getPageRenderer : function( controller, page )
    {
        return this.pages[this.buildPageKey( controller, page )];
    },

    // Recreate the current panel, and reload its settings.
    reloadCurrentPath : function()
    {        
        this.completeLoadPage( {}, {}, this.currentPath );
    },

    // Get the currently rendered panel.
    getCurrentPanel : function()
    {
        return this.currentPanel;
    },

    /*
     *  Get the current path, eg /hostname/index/1
     */
    getCurrentPath : function()
    {
        return this.currentPath;
    },

    // private : This is a handler called after a page has been loaded.
    // param targetPanel The panel that the new page is going to be rendered into.  If this is null,
    // this will use the current active panel in the menu.
    completeLoadPage : function( response, options, newPage, targetPanel )
    {
        var controller = newPage["controller"];
        var action = newPage["action"];
        var pageID = newPage["pageID"];
        var params = newPage["params"];

        var panelClass = this.getPageRenderer( controller, action );
        
        var handler = this.completeLoadSettings.createDelegate( this, [ newPage, panelClass, targetPanel ], 
                                                                true );

        if ( panelClass.loadSettings != null ) {
            panelClass.loadSettings( newPage, handler );
        } else if ( panelClass.settingsMethod != null ) {
            var m = panelClass.settingsMethod;
            if ( pageID ) {
                m += "/" + pageID;
            }
            if ( params ) {
                m += "?" + params;
            }
            Ung.Alpaca.Util.executeRemoteFunction( m, handler );
        } else {
            handler( null, null, null );
        }        
    },

    // private : This is a handler that is called after the settings have been loaded.
    // param targetPanel The panel that the new page is going to be rendered into.  If this is null,
    // this will use the current active panel in the menu.
    completeLoadSettings : function( settings, response, options, newPage, panelClass, targetPanel )
    {
        application.renderPanel( panelClass, settings )
        var panel = new panelClass({ settings : settings });
                
        if ( targetPanel == null ) {
            targetPanel = main.getActiveTab();
        }

        /* First clear out any children. */
        var el = null;
        if (( typeof targetPanel ) == "string" ) {
            el = Ext.get( targetPanel );
        } else {
            el = targetPanel.getEl();
        }

        if ( el != null ) {
            el.update( "" );
        }
        
        main.configureActions( panel, panel.saveSettings );

        panel.render( el );
        
        main.clearLastTab();

        /* Have to call this after rendering */
        panel.populateForm();

        this.currentPanel = panel;
        this.currentPath = newPage;        
    },

    // private : Get the key used to uniquely identify a controller, page combination
    buildPageKey : function( controller, page )
    {
        return  "/" + controller + "/" + page;
    }
}
