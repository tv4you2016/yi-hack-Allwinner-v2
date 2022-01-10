#!/bin/sh

YI_HACK_PREFIX="/tmp/sd/yi-hack"

sedencode(){
#  echo -e "$(sed 's/\\/\\\\\\/g;s/\&/\\\&/g;s/\//\\\//g;')"
  echo "$(sed 's/\\/\\\\/g;s/\"/\\\"/g;s/\&/\\\&/g;s/\//\\\//g;')"
}

removedoublequotes(){
  echo "$(sed 's/^"//g;s/"$//g')"
}

get_conf_type()
{
    CONF="$(echo $QUERY_STRING | cut -d'=' -f1)"
    VAL="$(echo $QUERY_STRING | cut -d'=' -f2)"

    if [ $CONF == "conf" ] ; then
        echo $VAL
    fi
}

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh

if ! $(validateQueryString $QUERY_STRING); then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

CONF_TYPE="$(get_conf_type)"
CONF_FILE=""

if [ "$CONF_TYPE" == "mqtt" ] ; then
    CONF_FILE="$YI_HACK_PREFIX/etc/mqttv4.conf"
else
    CONF_FILE="$YI_HACK_PREFIX/etc/$CONF_TYPE.conf"
fi

read -r POST_DATA
# Validate json
VALID=$(echo "$POST_DATA" | jq -e . >/dev/null 2>&1; echo $?)
if [ "$VALID" != "0" ]; then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
fi
# Change temporarily \n with \t (2 bytes)
POST_DATA="${POST_DATA/\\n/\\t}"
IFS=$(echo -en "\n\b")
ROWS=$(echo "$POST_DATA" | jq -r '. | keys[] as $k | "\($k)=\(.[$k])"')
for ROW in $ROWS; do
    ROW=$(echo "$ROW" | removedoublequotes)
    KEY=$(echo "$ROW" | cut -d'=' -f1)
    # Change back tab with \n
    VALUE=$(echo "$ROW" | cut -d'=' -f2 | sed 's/\t/\\n/g')

    if [ "$KEY" == "HOSTNAME" ] ; then
        if [ -z $VALUE ] ; then

            # Use 2 last MAC address numbers to set a different hostname
            MAC=$(cat /sys/class/net/wlan0/address|cut -d ':' -f 5,6|sed 's/://g')
            if [ "$MAC" != "" ]; then
                hostname yi-$MAC
            else
                hostname yi-hack
            fi
            hostname > $YI_HACK_PREFIX/etc/hostname
        else
            hostname $VALUE
            echo "$VALUE" > $YI_HACK_PREFIX/etc/hostname
        fi
    elif [ "$KEY" == "MOTION_IMAGE_DELAY" ] ; then
        if $(validateNumber $VALUE); then
            VALUE=$(echo $VALUE | sed 's/,/./g')
            VAR=$(awk 'BEGIN{ print "'$VALUE'"<="'5.0'" }')
            if [ "$VAR" == "1" ]; then
                sed -i "s/^\(${KEY}\s*=\s*\).*$/\1${VALUE}/" $CONF_FILE
            fi
        fi
    else
        VALUE=$(echo "$VALUE" | sedencode)
        sed -i "s/^\(${KEY}\s*=\s*\).*$/\1${VALUE}/" $CONF_FILE
    fi

done

# Yeah, it's pretty ugly.

printf "Content-type: application/json\r\n\r\n"

printf "{\n"
printf "\"%s\":\"%s\"\\n" "error" "false"
printf "}"
