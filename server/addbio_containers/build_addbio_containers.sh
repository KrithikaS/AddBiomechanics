#!/bin/bash

# Build the base container. If you don't plan on modifying version of OpenSim
# used in the AddBiomechanics processing pipeline, then you should only need to
# do this once. Replace "nbianco/addbio_base" with "<your_dockerhub_username>/addbio_base"
# so it can be pushed to your Docker Hub account.
docker build -t kswami235/addbio_base -f Dockerfile.base --platform linux/amd64 .
docker push kswami235/addbio_base

# Build the container with the AddBiomechanics engine code. In "Dockerfile.addbio",
# you will need to replace "nbianco/addbio_base" with "<your_dockerhub_username>/addbio_base"
# so that it pulls the base image from your Docker Hub account. Similary, replace
# "nbianco/addbio" with "<your_dockerhub_username>/addbio" so that it can be pushed to your
# Docker Hub account. If you want to modify the engine code, you will need to run this command
# each time you want to update the container.
docker build -t kswami235/addbio -f Dockerfile.addbio --platform linux/amd64 .
docker push kswami235/addbio
