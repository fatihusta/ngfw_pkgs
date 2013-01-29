#!/bin/dash

# This script addes the appropriate ip route rules for a WAN interface
# Usage: add-uplink.sh <interface> <gatewayIP> <routeTableNum>

## All of the untangle rules MUST fall in this priority.  This makes it easy to
## flush all of the rules.
UNTANGLE_PRIORITY_BASE="36"
UNTANGLE_PRIORITY_DEFAULT="${UNTANGLE_PRIORITY_BASE}6900"

## Functions
debug()
{
    /bin/echo -e "[DEBUG: `date`] ${*}"
}

debug_ip()
{
    debug ip $*
    ip $*
}

usage()
{
    echo "$0 <interface> <gateway> <rt_table>"
    echo "\t This will configure an uplink table <rt_table> with gateway"
    echo "\t and add routing entries for all of the addresses on interface."
    exit 254
}

ip_rule_get_priority()
{
    local t_min_priority=$1
    local t_max_priority=$2
    
    ip rule show | awk -v min_priority=$t_min_priority \
        -v max_priority=$t_max_priority -v priority=$t_min_priority  \
        '{ sub( ":", "" ) ; if (( $1 >= min_priority ) && ( $1 < max_priority ) && ( priority == $1 )) priority=$1 +1 } END { print priority }'

}

## Determine all of the routable aliases.
ip_route_get_aliases()
{
    local t_interface
    local t_gateway
    local t_pppoe_interface
    local t_connection_file
    
    t_interface=$1
    t_gateway=$2
    
    ## Print out all of the aliases
    ip -f inet addr show ${t_interface} scope global | \
        awk '/inet/ { sub ( "/.*", "", $2 ) ; print  $2 }'
            
    if [ "${t_interface#ppp}" != "${t_interface}" ]; then
        
        if [ -f "/var/run/${t_interface}.pid" ]; then
            t_pppoe_interface=`cat /var/run/${t_interface}.pid`
            t_connection_file=`cat "/proc/${t_pppoe_interface}/cmdline" | tr '\000' '\001' | awk -v RS='\001' '/^connection./ { print ; exit }'`
            
            t_connection_file="/etc/ppp/peers/${t_connection_file}"
            if [ -f ${t_connection_file} ] ; then
                t_pppoe_interface=`awk '/^plugin rp-pppoe.so/ { print $3 ; exit }' ${t_connection_file}`
            else
                t_pppoe_interface=""
            fi
            
            if [ -n "${t_pppoe_interface}" ] ; then
                ip -f inet addr show ${t_pppoe_interface} scope global | \
                    awk '/inet/ { sub("/.*","") ; print $2 }'
            fi
        fi
    fi    
}

## Determine if the rules are up to date.
ip_rule_update_source_routes()
{
    local t_interface
    local t_gateway
    local t_rt_table
    local t_aliases
    local t_expected_hash
    local t_current_hash
    local t_current_aliases
    local t_alias

    t_interface=$1
    t_gateway=$2
    t_rt_table=$3
    
    t_aliases=`ip_route_get_aliases $t_interface $t_gateway`
    t_current_aliases=`ip rule show | awk "/from [0-9].*lookup ${t_rt_table}/ { print \\$3 }"`
 
    if [ "${t_aliases}x" = "${t_current_aliases}x" ]; then
        $DEBUG "Source based uplinks are up to date for '${t_interface}'"
        return 0
    fi

    ## Delete the current rules
    for t_alias in ${t_current_aliases}; do 
        ${IP} rule del from ${t_alias} lookup ${t_rt_table}
    done

    for t_alias in ${t_aliases} ; do
        t_priority=`ip_rule_get_priority ${UNTANGLE_PRIORITY_BASE}500 ${UNTANGLE_PRIORITY_BASE}600`
        ${IP} rule add from ${t_alias} priority  ${t_priority} lookup ${t_rt_table}
    done
}

## Start of script
IFACE=$1
GATEWAY=$2
RT_TABLE=$3

DEBUG=/bin/true
IP="ip"

[ -n "${DEBUG_MODE}" ] && {
    DEBUG="debug"
    IP="debug_ip"
}

[ -z "${IFACE}" ] && usage
[ -z "${GATEWAY}" ] && usage
[ -z "${RT_TABLE}" ] && usage

$DEBUG "Adding uplink for[${IFACE}] ${ADDRESS}: -> ${GATEWAY} to ${RT_TABLE}"

ip_rule_update_source_routes ${IFACE} ${GATEWAY} ${RT_TABLE}

if [ "${GATEWAY}" = "ppp" ]; then
    ${IP} route replace table ${RT_TABLE} default dev ${IFACE}
else
    ${IP} route replace table ${RT_TABLE} default via ${GATEWAY}
fi

## If necessary add the default uplink rule
ip rule show | grep -q ${UNTANGLE_PRIORITY_DEFAULT} || {
    $DEBUG "Adding default uplink rule for ${RT_TABLE}"
    ip rule add priority ${UNTANGLE_PRIORITY_DEFAULT} lookup ${RT_TABLE}
}