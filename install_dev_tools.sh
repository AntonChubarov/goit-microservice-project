#!/bin/bash

set -e

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo "Cannot detect distribution"
        exit 1
    fi
}

install_packages() {
    case "$DISTRO" in
        ubuntu|debian|linuxmint)
            sudo apt-get update

            if ! command_exists docker; then
                sudo apt-get install -y docker.io
            fi

            if ! command_exists docker-compose; then
                sudo apt-get install -y docker-compose
            fi

            if ! command_exists python3; then
                sudo apt-get install -y python3
            fi

            if ! command_exists pip3; then
                sudo apt-get install -y python3-pip
            fi
            ;;
        centos|rhel)
            sudo yum -y install yum-utils

            if ! command_exists docker; then
                sudo yum -y install docker
            fi

            if ! command_exists docker-compose; then
                sudo yum -y install docker-compose
            fi

            if ! command_exists python3; then
                sudo yum -y install python3
            fi

            if ! command_exists pip3; then
                sudo yum -y install python3-pip
            fi
            ;;
        fedora)
            sudo dnf -y install dnf-plugins-core

            if ! command_exists docker; then
                sudo dnf -y install docker
            fi

            if ! command_exists docker-compose; then
                sudo dnf -y install docker-compose
            fi

            if ! command_exists python3; then
                sudo dnf -y install python3
            fi

            if ! command_exists pip3; then
                sudo dnf -y install python3-pip
            fi
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm

            if ! command_exists docker; then
                sudo pacman -S --noconfirm docker
            fi

            if ! command_exists docker-compose; then
                sudo pacman -S --noconfirm docker-compose
            fi

            if ! command_exists python; then
                sudo pacman -S --noconfirm python
            fi

            if ! command_exists pip; then
                sudo pacman -S --noconfirm python-pip
            fi
            ;;
        opensuse*|suse*)
            sudo zypper refresh

            if ! command_exists docker; then
                sudo zypper install -y docker
            fi

            if ! command_exists docker-compose; then
                sudo zypper install -y docker-compose
            fi

            if ! command_exists python3; then
                sudo zypper install -y python3
            fi

            if ! command_exists pip3; then
                sudo zypper install -y python3-pip
            fi
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

install_django() {
    if ! python3 -m django --version >/dev/null 2>&1; then
        echo "Installing Django via pip..."
        pip3 install --user django
    else
        echo "Django already installed"
    fi
}

main() {
    detect_distro
    echo "Detected distribution: $DISTRO"
    install_packages
    install_django
    echo "All tasks completed"
}

main
