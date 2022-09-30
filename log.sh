#!/bin/bash

function log() {
    echo -e "\033[37m$@\033[0m"
}

function log_info() {
    echo -e "\033[32m$@\033[0m"
}

function log_warn() {
    echo -e "\033[33m$@\033[0m"
}

function log_error() {
    echo -e "\033[31m$@\033[0m"
}
