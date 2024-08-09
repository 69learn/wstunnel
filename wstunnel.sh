#!/bin/bash



display_progress() {
    local duration=$1
    local sleep_interval=0.1
    local progress=0
    local bar_length=40
    local colors=("[36m" "[32m" "[36m" "[32m" "[36m" "[32m" "[36m")

    while [ $progress -lt $duration ]; do
        echo -ne "\r${colors[$((progress % 7))]}"
        for ((i = 0; i < bar_length; i++)); do
            if [ $i -lt $((progress * bar_length / duration)) ]; then
                echo -ne "█"
            else
                echo -ne "░"
            fi
        done
        echo -ne "[0m ${progress}%"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r${colors[0]}"
    for ((i = 0; i < bar_length; i++)); do
        echo -ne " "
    done
    echo -ne "[0m 100%"
    echo
}

# Check if running as root
root_access() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi
}

# Detect Linux distribution
detect_distribution() {
    local supported_distributions=("ubuntu" "debian" "centos" "fedora")
    
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "${ID}" = "ubuntu" || "${ID}" = "debian" || "${ID}" = "centos" || "${ID}" = "fedora" ]]; then
            pm="apt-get"
            [ "${ID}" = "centos" ] && pm="yum"
            [ "${ID}" = "fedora" ] && pm="dnf"
        else
            echo "Unsupported distribution!"
            exit 1
        fi
    else
        echo "Unsupported distribution!"
        exit 1
    fi
}

#Check dependencies
check_dependencies() {
    root_access
    detect_distribution
    display_progress 8
    "${pm}" update -y
    local dependencies=("wget" "tar")
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "${dep} is not installed. Installing..."
            sudo "${pm}" install "${dep}" -y
        fi
    done
}

#Check installed service 
check_installed() {
    if systemctl is-enabled --quiet wstunnel.service > /dev/null 2>&1; then
        echo "The WsTunnel service is already installed."
        exit 1
    fi
}

#Install wstunnel
install_wstunnel() {
    check_installed
    mkdir wstunnel && cd wstunnel
    check_dependencies
    
    # Determine system architecture
    if [[ $(arch) == "x86_64" ]]; then
        latest_version=$(curl -s https://api.github.com/repos/erebe/wstunnel/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
        wstunnel_file="wstunnel_${latest_version//v}_linux_amd64.tar.gz"
    elif [[ $(arch) == "aarch64" ]]; then
        wstunnel_file="wstunnel_${latest_version//v}_linux_arm64.tar.gz"
    elif [[ $(arch) == "armv7l" ]]; then
        wstunnel_file="wstunnel_${latest_version//v}_linux_armv7.tar.gz"
    elif [[ $(uname) == "Darwin" ]]; then
        wstunnel_file="wstunnel_${latest_version//v}_darwin_amd64.tar.gz"
    else
        echo "Unsupported architecture!"
        exit 1
    fi
    
    # Download and extract wstunnel
    wget "https://github.com/erebe/wstunnel/releases/download/${latest_version}/${wstunnel_file}" -q
    tar -xvf "$wstunnel_file" > /dev/null
    chmod +x wstunnel
    # Move wstunnel binary to /usr/local/bin (adjust if necessary)
    sudo mv wstunnel /usr/local/bin/wstunnel
    cd ..
    rm -rf wstunnel
}


# Get inputs
get_inputs() {
    clear
    PS3=$'\n'"# Please Enter your choice: "
    options=("External-[server]" "Internal-[client]" "Exit")

    select server_type in "${options[@]}"; do
        case "$REPLY" in
            1)
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi

                argument="server $use_tls://[::]:$port"
                break
                ;;
            2)
                read -p "Enter foreign IP [External-server]: " foreign_ip
                read -p "Please Enter Your config [vpn] Port :" config_port
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi
                
                echo -e "Enter connection type:
1) tcp  ${purple}[vless , vmess , trojan , ...]${rest}
2) udp  ${purple}[Wireguard , hysteria, tuic , ...]${rest}
3) socks5
4) stdio"
echo ""
read -p "Enter number (default is: 1--> tcp): " choice

                case $choice in
                    1) connection_type="tcp" ;;
                    2) connection_type="udp" ;;
                    3) connection_type="socks5" ;;
                    4) connection_type="stdio" ;;
                    *) connection_type="tcp" ;;
                esac
                read -p "Do you want to use SNI? (yes/no) [default: yes]: " use_sni
                use_sni=${use_sni:-yes}
			    if [ "$use_sni" = "yes" ]; then
			        read -p "Please Enter SNI [default: google.com]: " tls_sni
			        tls_sni=${tls_sni:-google.com}
			        tls_sni_argument="--tls-sni-override $tls_sni"
			    fi

                # Add ?timeout_sec=0 only for UDP
                if [ "$connection_type" = "udp" ]; then
                    timeout_argument="?timeout_sec=0"
                else
                    timeout_argument=""
                fi

                read -p "Do you want to add more ports? (yes/no) [default: no]: " add_port
				add_port=${add_port:-no}
				
				if [ "$add_port" == "yes" ]; then
				    read -p "Enter ports separated by commas (e.g., 2096,8080): " port_list
				    IFS=',' read -ra ports <<< "$port_list"
				
				    for new_port in "${ports[@]}"; do
				        argument+=" -L '$connection_type://[::]:$new_port:localhost:$new_port$timeout_argument'"
				    done
				fi

                argument="client -L '$connection_type://[::]:$config_port:localhost:$config_port$timeout_argument'$argument $use_tls://$foreign_ip:$port $tls_sni_argument"
                break
                ;;
            3)
                echo "Exiting..."
                exit 0 
                ;;
            *)
                echo "Invalid choice. Please Enter a valid number."
                ;;
        esac
    done

    create_service
}


get_inputs_Reverse() {
    clear
    PS3=$'\n'"# Please Enter your choice: "
    options=("Internal-[client]" "External-[server]" "Exit")

    select server_type in "${options[@]}"; do
        case "$REPLY" in
            1)
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi

                argument="server $use_tls://[::]:$port"
                break
                ;;
            2)
                echo -e "${yellow}Please install on [Internal-client] first. If you have installed it, press Enter to continue...${rest}"
                read -r
                read -p "Enter Internal IP [Internal-client]: " foreign_ip
                read -p "Please Enter Your config [vpn] Port :" config_port
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi
                
                echo -e "Enter connection type:
1) tcp  ${purple}[vless , vmess , trojan , ...]${rest}
2) udp  ${purple}[Wireguard , hysteria, tuic , ...]${rest}
3) socks5
4) stdio"
echo ""
read -p "Enter number (default is: 1--> tcp): " choice

                case $choice in
                    1) connection_type="tcp" ;;
                    2) connection_type="udp" ;;
                    3) connection_type="socks5" ;;
                    4) connection_type="stdio" ;;
                    *) connection_type="tcp" ;;
                esac
                read -p "Do you want to use SNI? (yes/no) [default: yes]: " use_sni
                use_sni=${use_sni:-yes}
			    if [ "$use_sni" = "yes" ]; then
			        read -p "Please Enter SNI [default: google.com]: " tls_sni
			        tls_sni=${tls_sni:-google.com}
			        tls_sni_argument="--tls-sni-override $tls_sni"
			    fi

                # Add ?timeout_sec=0 only for UDP
                if [ "$connection_type" = "udp" ]; then
                    timeout_argument="?timeout_sec=0"
                else
                    timeout_argument=""
                fi

                read -p "Do you want to add more ports? (yes/no) [default: no]: " add_port
				add_port=${add_port:-no}
				
				if [ "$add_port" == "yes" ]; then
				    read -p "Enter ports separated by commas (e.g., 2096,8080): " port_list
				    IFS=',' read -ra ports <<< "$port_list"
				
				    for new_port in "${ports[@]}"; do
				        argument+=" -R '$connection_type://[::]:$new_port:localhost:$new_port$timeout_argument'"
				    done
				fi

                argument="client -R '$connection_type://[::]:$config_port:localhost:$config_port$timeout_argument'$argument $use_tls://$foreign_ip:$port $tls_sni_argument"
                break
                ;;
            3)
                echo "Exiting..."
                exit 0 
                ;;
            *)
                echo "Invalid choice. Please Enter a valid number."
                ;;
        esac
    done

    create_service
}

# Create service
create_service() {
    cd /etc/systemd/system

    cat <<EOL>> wstunnel.service
[Unit]
Description=WsTunnel
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel $argument

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable wstunnel.service
    sudo systemctl start wstunnel.service
}




install_custom() {
    install_wstunnel
    cd /etc/systemd/system
    echo ""
    read -p "Enter Your custom arguments (Example: wstunnel server wss://[::]:443): " arguments
    
    # Create the custom_tunnel.service file with user input
    cat <<EOL>> wstunnel.service
[Unit]
Description=WsTunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/$arguments

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable wstunnel.service
    sudo systemctl start wstunnel.service
    sleep 1
    check_tunnel_status
}

install() {
    if systemctl is-active --quiet wstunnel.service; then
        echo "The wstunnel service is already installed. and actived."
    else
        install_wstunnel
        get_inputs
    fi
        check_tunnel_status
}

install_reverse() {
    if systemctl is-active --quiet wstunnel.service; then
        echo "The wstunnel service is already installed. and actived."
    else
        install_wstunnel
        get_inputs_Reverse
    fi  
        sleep 1
        check_tunnel_status
}


#Uninstall 
uninstall() {
    if ! systemctl is-enabled --quiet wstunnel.service > /dev/null 2>&1; then
        echo "WsTunnel is not installed."
        return
    else

	    sudo systemctl stop wstunnel.service
	    sudo systemctl disable wstunnel.service
	    sudo rm /etc/systemd/system/wstunnel.service
	    sudo systemctl daemon-reload
	    sudo rm /usr/local/bin/wstunnel
	
	    echo "WsTunnel has been uninstalled."
    fi
}

check_tunnel_status() {
    # Check the status of the tunnel service
    if systemctl is-active --quiet wstunnel.service; then
        echo -e "${yellow}════════════════════════════════${rest}"
        echo -e "${cyan} WS Tunnel :${purple}[${green}running ✔${purple}]${rest}"
    else
        echo -e "${cyan} WS Tunnel :${purple}[${red}Not running ✗ ${purple}]${rest}"
    fi
}

#Termux check_dependencies_termux
check_dependencies_termux() {
    local dependencies=("wget" "curl" "tar")
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "${dep} is not installed. Installing..."
            pkg install "${dep}" -y
        fi
    done
}
#Termux install wstunnel
install_ws_termux() {
    if [ -e "$PATH/wstunnel" ]; then
        echo -e "${green}wstunnel already Installed. Skipping installation.${rest}"
        sleep 1
    else
        pkg update -y
        pkg upgrade -y
        pkg update
        check_dependencies_termux
        latest_version=$(curl -s https://api.github.com/repos/erebe/wstunnel/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
        wstunnel_file="wstunnel_${latest_version//v}_linux_arm64.tar.gz"
        wget "https://github.com/erebe/wstunnel/releases/download/${latest_version}/${wstunnel_file}"
        tar -xvf "$wstunnel_file" > /dev/null
        chmod +x wstunnel
        mv wstunnel "$PATH/"
        rm "$wstunnel_file" LICENSE README.md
    fi
    inputs_termux
}

uninstall_ws_termux() {
    if [ -e "$PATH/run" ]; then
        rm "$PATH/run"
        echo -e "${green}Ws Tunnel has been uninstalled.${rest}"
    else
        echo -e "${red}Ws Tunnel is not installed.${rest}"
    fi
}

#Termux get inputs
inputs_termux() {
    clear
    read -p "Enter foreign IP [External-server]: " foreign_ip
    read -p "Please Enter Your config [vpn] Port: " config_port
    read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
    port=${port:-443}
    
    read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
    use_tls=${use_tls:-yes}
    use_tls_option="wss" # default to wss
    [ "$use_tls" = "no" ] && use_tls_option="ws"
    
    echo -e "Enter connection type:
1) tcp  ${purple}[vless , vmess , trojan , ...]${rest}
2) udp  ${purple}[Wireguard , hysteria, tuic , ...]${rest}
3) socks5
4) stdio"
echo ""
read -p "Enter number (default is: 1--> tcp): " choice

    case $choice in
        1) connection_type="tcp" ;;
        2) connection_type="udp" ;;
        3) connection_type="socks5" ;;
        4) connection_type="stdio" ;;
        *) connection_type="tcp" ;;
    esac
    
    read -p "Do you want to use SNI? (yes/no) [default: yes]: " use_sni
    use_sni=${use_sni:-yes}
    if [ "$use_sni" = "yes" ]; then
	    read -p "Please Enter SNI [default: google.com]: " tls_sni
	    tls_sni=${tls_sni:-google.com}
	    tls_sni_argument="--tls-sni-override $tls_sni"
	fi
	
     # Add ?timeout_sec=0 only for UDP
    if [ "$connection_type" = "udp" ]; then
        timeout_argument="?timeout_sec=0"
   else
        timeout_argument=""
    fi
    argument="wstunnel client -L $connection_type://[::]:$config_port:localhost:$config_port$timeout_argument $use_tls_option://$foreign_ip:$port $tls_sni_argument"
    echo -e "${purple}________________Your-Arguments________________${rest}"
    echo "$argument"
    echo -e "${purple}___________________________________________${rest}"
    echo ""
    save "$argument"
    run
}

save() {
    if [ -z "$1" ]; then
        echo "Usage: save <argument>"
    else
        echo -n "$1" > run
        chmod +x run
        mv run "$PATH/"
        echo "Argument saved to 'run' binary file."
        echo -e "${purple}___________________________________________${rest}"
        echo -e "${green}** To Run Tunnel again, you can only type 'run' and press Enter **${rest}"
        echo -e "${purple}___________________________________________${rest}"
    fi
}

main_menu_termux() {
     if [ "$(uname -o)" != "Android" ]; then
        echo -e "${red}Please Run script in Termux.${rest}"
        exit 1
    fi
    
    clear
    echo -e "${cyan}-----Ws tunnel in Termux----${rest}"
    echo ""
    echo -e "${cyan}1) ${purple}Install Ws Tunnel${rest}"
    echo ""
    echo -e "${cyan}2) ${purple}Uninstall Ws Tunnel${rest}"
    echo ""
    echo -e "${cyan}3) ${purple}Back to Menu${rest}"
    echo ""
    echo -e "${cyan}0) ${purple}Exit${rest}"
    echo ""
    read -p "Enter your choice: " choice
    case "$choice" in
        1)
            install_ws_termux
            ;;
        2)
            uninstall_ws_termux
            ;;
        3)
            main_menu
            ;;
        0)
            exit
            ;;
        *)
            echo "Invalid choice. Please select a valid option."
            ;;
    esac
}

# Main menu
main_menu() {
    clear
    echo -e "${Purple}"
    cat << "EOF"
                 
══════════════════════════════════════════════════════════════════════════════════════
        ____                             _     _                                     
    ,   /    )                           /|   /                                  /   
-------/____/---_--_----__---)__--_/_---/-| -/-----__--_/_-----------__---)__---/-__-
  /   /        / /  ) /   ) /   ) /    /  | /    /___) /   | /| /  /   ) /   ) /(    
_/___/________/_/__/_(___(_/_____(_ __/___|/____(___ _(_ __|/_|/__(___/_/_____/___\__

══════════════════════════════════════════════════════════════════════════════════════
EOF
    echo ""
    echo -e "${purple}════════════════ MENU ════════════════"
    echo ""
    echo -e "${purple}════════════════════════════════${rest}"
    echo ""
    check_tunnel_status
    echo ""
    echo -e "${purple}════════════════════════════════${rest}"

    echo -e "${cyan}1. Install Ws-Tunnel"
    echo ""
    echo -e "${cyan}2. ${cyan}Install Ws Reverse Tunnel"
    echo ""
    echo -e "${cyan}3. ${cyan}Install Custom"
    echo ""
    echo -e "${cyan}4. ${cyan}Uninstall wstunnel"
    echo ""
    echo -e "${cyan}5. ${cyan}Install on Termux (no root)"
    echo ""
    echo -e "${cyan}0. Exit"
    echo -e "${purple}═════════════════════════════════════${rest}"
    read -p "Please choose: " choice

    case $choice in
        1)
            install
            ;;
        2)
            install_reverse
            ;;
        3)
            install_custom
            ;;
        4)
            uninstall
            ;;
        5)
            main_menu_termux
            ;;
        0)
            exit
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
}

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[0;37m'
rest='\033[0m'

main_menu
