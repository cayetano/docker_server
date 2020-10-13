#!/bin/bash
# script para editar y namejar un servidor de docker sencillo para la R-pi
# (c) Cayetano Gomez 2020 - cayetano@gomezgil.es


#variables
CONFIG_FILE="/etc/docker_server.conf"
STORAGE_DIR="/data"

TMP_DOCKER_COMPOSE_YML=./.tmp/docker-compose.tmp.yml
DOCKER_COMPOSE_YML=./docker-compose.yml
DOCKER_COMPOSE_OVERRIDE_YML=./compose-override.yml


COMPOSE_VERSION="3.6"
REQ_DOCKER_VERSION=18.2.0
REQ_PYTHON_VERSION=3.6.9
REQ_PYYAML_VERSION=5.3.1

declare -A cont_array=(
	[portainer]="Portainer"
	[portainer_agent]="Portainer agent"
	[nodered]="Node-RED"
	[influxdb]="InfluxDB"
	[telegraf]="Telegraf (Requires InfluxDB and Mosquitto)"
	[transmission]="transmission"
	[grafana]="Grafana"
	[mosquitto]="Eclipse-Mosquitto"
	[prometheus]="Prometheus"
	[postgres]="Postgres"
	[timescaledb]="Timescaledb"
	[mariadb]="MariaDB (MySQL fork)"
	[adminer]="Adminer"
	[openhab]="openHAB"
	[zigbee2mqtt]="zigbee2mqtt"
	[deconz]="deCONZ"
	[pihole]="Pi-Hole"
	[plex]="Plex media server"
	[tasmoadmin]="TasmoAdmin"
	[rtl_433]="RTL_433 to mqtt"
	[espruinohub]="EspruinoHub"
	[motioneye]="motionEye"
	[webthings_gateway]="Mozilla webthings-gateway"
	[blynk_server]="blynk-server"
	[nextcloud]="Next-Cloud"
	[nginx]="NGINX by linuxserver"
    [nginx-manager]="NGINX Manager Proxy"
	[diyhue]="diyHue"
	[homebridge]="Homebridge"
	[python]="Python 3"
	[gitea]="Gitea"
	[qbittorrent]="qbittorrent"
	[domoticz]="Domoticz"
	[dozzle]="Dozzle"
	[wireguard]="Wireguard"
)

declare -a armhf_keys=(
	"portainer"
	"portainer_agent"
	"nodered"
	"influxdb"
	"grafana"
	"mosquitto"
	"telegraf"
	"prometheus"
	"mariadb"
	"postgres"
	"timescaledb"
	"transmission"
	"adminer"
	"openhab"
	"zigbee2mqtt"
  	"deconz"
	"pihole"
	"plex"
	"tasmoadmin"
	"rtl_433"
	"espruinohub"
	"motioneye"
	"webthings_gateway"
	"blynk_server"
	"nextcloud"
	"diyhue"
	"homebridge"
	"python"
	"gitea"
	"qbittorrent"
	"domoticz"
	"dozzle"
	"wireguard"
	"nginx-manager"
)

sys_arch=$(uname -m)



#funciones
command_exists() {
	command -v "$@" > /dev/null 2>&1
}

timezones() {

	env_file=$1
	TZ=$(cat /etc/timezone)

	#test for TZ=
	[ $(grep -c "TZ=" $env_file) -ne 0 ] && sed -i "/TZ=/c\TZ=$TZ" $env_file

}


# this function creates the volumes, services and backup directories. It then assisgns the current user to the ACL to give full read write access
docker_setfacl() {
	[ -d $STORAGE_DIR/services ] || mkdir $STORAGE_DIR/services
	[ -d $STORAGE_DIR/volumes ] || mkdir $STORAGE_DIR/volumes
	[ -d $STORAGE_DIR/backups ] || mkdir $STORAGE_DIR/backups
	[ -d $STORAGE_DIR/tmp ] || mkdir $STORAGE_DIR/tmp

	#give current user rwx on the volumes and backups
	[ $(getfacl ./volumes | grep -c "default:user:$USER") -eq 0 ] && sudo setfacl -Rdm u:$USER:rwx ./volumes
	[ $(getfacl ./backups | grep -c "default:user:$USER") -eq 0 ] && sudo setfacl -Rdm u:$USER:rwx ./backups
}



function minimum_version_check() {
	# minimum_version_check required_version current_major current_minor current_build
	# minimum_version_check "1.2.3" 1 2 3
	REQ_MIN_VERSION_MAJOR=$(echo "$1"| cut -d' ' -f 2 | cut -d'.' -f 1)
	REQ_MIN_VERSION_MINOR=$(echo "$1"| cut -d' ' -f 2 | cut -d'.' -f 2)
	REQ_MIN_VERSION_BUILD=$(echo "$1"| cut -d' ' -f 2 | cut -d'.' -f 3)

	CURR_VERSION_MAJOR=$2
	CURR_VERSION_MINOR=$3
	CURR_VERSION_BUILD=$4
	
	VERSION_GOOD="Unknown"

	if [ -z "$CURR_VERSION_MAJOR" ]; then
		echo "$VERSION_GOOD"
		return 1
	fi

	if [ -z "$CURR_VERSION_MINOR" ]; then
		echo "$VERSION_GOOD"
		return 1
	fi

	if [ -z "$CURR_VERSION_BUILD" ]; then
		echo "$VERSION_GOOD"
		return 1
	fi

	if [ "${CURR_VERSION_MAJOR}" -ge $REQ_MIN_VERSION_MAJOR ]; then
		VERSION_GOOD="true"
		echo "$VERSION_GOOD"
		return 0
	else
		VERSION_GOOD="false"
	fi

	if [ "${CURR_VERSION_MAJOR}" -ge $REQ_MIN_VERSION_MAJOR ] && \
		[ "${CURR_VERSION_MINOR}" -ge $REQ_MIN_VERSION_MINOR ]; then
		VERSION_GOOD="true"
		echo "$VERSION_GOOD"
		return 0
	else
		VERSION_GOOD="false"
	fi

	if [ "${CURR_VERSION_MAJOR}" -ge $REQ_MIN_VERSION_MAJOR ] && \
		[ "${CURR_VERSION_MINOR}" -ge $REQ_MIN_VERSION_MINOR ] && \
		[ "${CURR_VERSION_BUILD}" -ge $REQ_MIN_VERSION_BUILD ]; then
		VERSION_GOOD="true"
		echo "$VERSION_GOOD"
		return 0
	else
		VERSION_GOOD="false"
	fi

	echo "$VERSION_GOOD"
}


#test de root

check_root () {
  if [[ $EUID -ne 0 ]]; then
    echo "Solo root puede ejecutar este script." 
    exit 1
  fi
}



function yml_builder() {

	service="services/$1/service.yml"

	[ -d $data/ ] || mkdir $data/

	if [ -d $data/$1 ]; then
		#directory already exists prompt user to overwrite
		sevice_overwrite=$(whiptail --radiolist --title "Opcion de Sobreescritura" --notags \
			"El direcotio del servicio $1 existe, use [ESPACIO] Para seleccionar su Opcion" 20 78 12 \
			"none" "No Sobreescribir" "ON" \
			"env" "Conserver entorno y ficheros" "OFF" \
			"full" "Reconfigurar totalmente" "OFF" \
			3>&1 1>&2 2>&3)

		case $sevice_overwrite in

		"full")
			echo "...pulled full $1 from template"
			rsync -a -q templates/$1/ services/$1/ --exclude 'build.sh'
			;;
		"env")
			echo "...pulled $1 excluding env file"
			rsync -a -q templates/$1/ services/$1/ --exclude 'build.sh' --exclude '$1.env' --exclude '*.conf'
			;;
		"none")
			echo "...$1 service not overwritten"
			;;

		esac

	else
		mkdir $data/$1
		echo "...pulled full $1 from template"
		rsync -a -q templates/$1/ services/$1/ --exclude 'build.sh'
	fi


	#if an env file exists check for timezone
	[ -f "$data/$1/$1.env" ] && timezones $data/$1/$1.env

	# if a volumes.yml exists, append to overall volumes.yml file
	[ -f "$data/$1/volumes.yml" ] && cat "$data/$1/volumes.yml" >> docker-volumes.yml

	#add new line then append service
	echo "" >> $TMP_DOCKER_COMPOSE_YML
	cat $service >> $TMP_DOCKER_COMPOSE_YML

	#test for post build
	if [ -f ./templates/$1/build.sh ]; then
		chmod +x ./templates/$1/build.sh
		bash ./templates/$1/build.sh
	fi

	#test for directoryfix.sh
	if [ -f ./templates/$1/directoryfix.sh ]; then
		chmod +x ./templates/$1/directoryfix.sh
		echo "...Corriendo directoryfix.sh on $1"
		bash ./templates/$1/directoryfix.sh
	fi

	#make sure terminal.sh is executable
	[ -f $data/$1/terminal.sh ] && chmod +x $data/$1/terminal.sh

}




#main
# Empieza el juego !!!!

#generamos y/o cargamos el fichero $CONFIG_FILE

check_root

. $CONFIG_FILE
echo "STORAGE_DIR="$STORAGE_DIR > $CONFIG_FILE

TMP_DOCKER_COMPOSE_YML=$STORAGE_DIR/tmp/docker-compose.tmp.yml
DOCKER_COMPOSE_YML=$STORAGE_DIR/docker-compose.yml
DOCKER_COMPOSE_OVERRIDE_YML=$STORAGE_DIR/compose-override.yml

mkdir -p $STORAGE_DIR
mkdir -p $STORAGE_DIR/tmp

# Comprobamos si está el docker instalado, en caso contrario avisa
# si está instalado se comprueba la actualización

clear





if command_exists docker; then
	echo "checking docker version"
	DOCKER_VERSION=$(docker version -f "{{.Server.Version}}")
	DOCKER_VERSION_MAJOR=$(echo "$DOCKER_VERSION"| cut -d'.' -f 1)
	DOCKER_VERSION_MINOR=$(echo "$DOCKER_VERSION"| cut -d'.' -f 2)
	DOCKER_VERSION_BUILD=$(echo "$DOCKER_VERSION"| cut -d'.' -f 3)

	if [ "$(minimum_version_check $REQ_DOCKER_VERSION $DOCKER_VERSION_MAJOR $DOCKER_VERSION_MINOR $DOCKER_VERSION_BUILD )" == "true" ]; then
		echo "Versión de Docker >= $REQ_DOCKER_VERSION. Listo para continuar."
	else
		if (whiptail --title "Docker y Docker-Compose" --yesno "La version de Docker instalada es $DOCKER_VERSION , la actual es $REQ_DOCKER_VERSION. Actualicela, puede tener problemas. Puede hacerlo manualmente mediante 'sudo apt upgrade docker docker-compose'. ¿Quiere actualiza ahora?" 20 78); then
			sudo apt -y upgrade docker docker-compose
		fi
	fi
else
	echo "docker not installed"
fi

sleep 2



mainmenu_selection=$(whiptail --title "Main Menu" --menu --notags \
	"" 20 78 12 -- \
	"install" "Instalar Docker" \
	"build" "Construir el instalador del servidor" \
	"hassio" "Instalar Home Assistant (Requiere Docker)" \
	"native" "Native Installs" \
	"commands" "Docker commands" \
	"backup" "Backup options" \
	"misc" "Miscellaneous commands" \
	"update" "Update IOTstack" \
	3>&1 1>&2 2>&3)

case $mainmenu_selection in
#MAINMENU Install docker  ------------------------------------------------------------
"install")
	#sudo apt update && sudo apt upgrade -y ;;

	if command_exists docker; then
		echo "docker already installed"
	else
		echo "Install Docker"
		curl -fsSL https://get.docker.com | sh
		sudo usermod -aG docker $USER
	fi

	if command_exists docker-compose; then
		echo "docker-compose already installed"
	else
		echo "Install docker-compose"
		sudo apt install -y docker-compose
	fi
	systemctl enable docker

	if (whiptail --title "Restart Required" --yesno "It is recommended that you restart your device now. Select yes to do so now" 20 78); then
		sudo reboot
	fi
	;;

### Instalar Hassio -------------------------------------------------------------------------------
"hassio")
	echo "Instalando requerimientos para Home Assistant"
	sudo apt install -y bash jq curl avahi-daemon dbus network-manager apparmor
	hassio_machine=$(whiptail --title "Modelo de Máquina" --menu \
		"Seleccione el Modelo" 20 78 12 -- \
		"raspberrypi4" " " \
		"raspberrypi3" " " \
		"raspberrypi2" " " \
		"raspberrypi4-64" " " \
		"raspberrypi3-64" " " \
		"qemux86" " " \
		"qemux86-64" " " \
		"qemuarm" " " \
		"qemuarm-64" " " \
		"orangepi-prime" " " \
		"odroid-xu" " " \
		"odroid-c2" " " \
		"intel-nuc" " " \
		"tinker" " " \
		3>&1 1>&2 2>&3)
	if [ -n "$hassio_machine" ]; then
		curl -sL https://raw.githubusercontent.com/home-assistant/supervised-installer/master/installer.sh | sudo bash -s -- -m $hassio_machine
	else
		echo "Seleccion Vacia"
		exit
	fi
	;;



### Generar instalacion por docker -------------------------------------------------------------------------------
"build")

	title=$'Seleciones COmponentes'
	message=$'Use la barra espaciadora para marar o desmarcar'
	entry_options=()

	#check architecture and display appropriate menu
	if [ $(echo "$sys_arch" | grep -c "arm") ]; then
		keylist=("${armhf_keys[@]}")
	else
		echo "Su arquitectura no está soportada."
		exit
	fi

	#loop through the array of descriptions
	for index in "${keylist[@]}"; do
		entry_options+=("$index")
		entry_options+=("${cont_array[$index]}")

		#check selection
		if [ -f $data/seleccion.txt ]; then
			[ $(grep "$index" $data/seleccion.txt) ] && entry_options+=("SI") || entry_options+=("no")
		else
			entry_options+=("no")
		fi
	done

	container_selection=$(whiptail --title "$title" --notags --separate-output --checklist \
		"$message" 20 78 12 -- "${entry_options[@]}" 3>&1 1>&2 2>&3)

	mapfile -t containers <<<"$container_selection"

	#if no container is selected then dont overwrite the docker-compose.yml file
	if [ -n "$container_selection" ]; then
		touch $TMP_DOCKER_COMPOSE_YML

		echo "version: '$COMPOSE_VERSION'" > $TMP_DOCKER_COMPOSE_YML
		echo "services:" >> $TMP_DOCKER_COMPOSE_YML

		#set the ACL for the stack
		#docker_setfacl

		# store last sellection
		[ -f $data/selection.txt ] && rm $data/selection.txt
		#first run service directory wont exist
		[ -d $data ] || mkdir services
		touch $data/selection.txt
		#Run yml_builder of all selected containers
		for container in "${containers[@]}"; do
			echo "Adding $container container"
			yml_builder "$container"
			echo "$container" >>$data/selection.txt
		done


		echo "docker-compose successfully created"
		echo "run 'docker-compose up -d' to start the stack"
	else

		echo "Build cancelled"

	fi
	;;



esac