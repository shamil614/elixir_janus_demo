#!/bin/bash

function stop_containers() {
  id=$(docker ps | awk 'NR > 1 {print $1}' | tr '\n' ' ')
  # parse string into array
  IFS=' ' read -a ids <<< "${id}"

  if [ -z "$ids" ]; then
    echo "No containers running"
  fi

  # iterate and stop
  for i in "${ids[@]}"; do
      echo "Stopping containers $i"
      docker stop "$i"
  done
}


function delete_containers() {
  docker rm $(docker ps -a -q)
}

function delete_images() {
  if [ "$dang" == "true" ]
  then
    docker rmi -f $(docker images -q --filter "dangling=true")
  else
    docker rmi -f $(docker images -q)
  fi
}

function remove_unused_volumes() {
  docker volume rm $(docker volume ls -qf dangling=true)
}

PS3='Select a helper script: '
options=("Start Backend Services" "Stop all containers" "Delete all containers" "Delete dangling images" "Delete all images" "Remove Unused Volumes" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Start Backend Services")
            svc=$(docker start redis rabbitmq postgres | tr '\n' ' ')
            echo "Starting $svc"
            exit
            ;;
        "Stop all containers")
            stop_containers
            exit
            ;;
        "Delete all containers")
            stop_containers
            delete_containers
            exit
            ;;
        "Delete dangling images")
          stop_containers
          dang="true"
          delete_images
          exit
          ;;
        "Delete all images")
            delete_images
            exit
            ;;
        "Remove Unused Volumes")
            remove_unused_volumes
            exit
            ;;
        "Quit")
            break
            ;;
        *) echo invalid option;;
    esac
done
